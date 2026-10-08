"""
Context the stat snapshots do not carry: who a player is, what he costs, how
much he plays and whether he is hurt, plus team power ratings and a projected
margin for every game still to be played.

Writes three tables, none of which any existing app build reads, so this job
can fail, lag or be rerun without touching the published snapshots:

* ``player_profiles``: bio (``load_players``), active contract (OverTheCap via
  ``load_contracts``), season snap counts (``load_snap_counts``) and the latest
  injury report (``load_injuries``). One row per player per season.
* ``team_ratings``: HB-style power ratings, see ``team_ratings.py``.
* ``game_projections``: projected home margin and win probability for each
  unplayed game this season.

Every source is optional: a missing or late table leaves its columns null for
this run rather than failing the others.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import sys
import time
from datetime import date, datetime, timezone
from typing import Any, Callable, Optional

import nflreadpy as nfl
import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

import team_ratings as tr
from ingest import gsis_to_id, resolve_season

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc
BATCH = 500
# PostgREST rejects a bulk upsert whose objects carry different keys, so every
# profile row carries every optional column, null when its source had nothing.
PROFILE_OPTIONAL_COLUMNS = [
    "contract_apy", "contract_cap_pct", "contract_years", "contract_year_signed",
    "contract_value", "contract_guaranteed",
    "snap_games", "team_games", "off_snaps", "def_snaps", "st_snaps",
    "off_snap_pct", "def_snap_pct",
    "injury_week", "injury_status", "injury", "practice_status",
]


def _pandas(frame: Any) -> pd.DataFrame:
    if frame is None:
        return pd.DataFrame()
    return frame.to_pandas() if hasattr(frame, "to_pandas") else frame


def _load(name: str, loader: Callable[[], Any], attempts: int = 3) -> pd.DataFrame:
    for attempt in range(1, attempts + 1):
        try:
            frame = _pandas(loader())
            logger.info("Loaded %s: %d rows", name, len(frame))
            return frame
        except Exception as error:  # noqa: BLE001 - one late source must not sink the rest
            if attempt == attempts:
                logger.warning("Skipping %s: %s", name, error)
                return pd.DataFrame()
            logger.info("Retrying %s after: %s", name, error)
            time.sleep(5 * attempt)
    return pd.DataFrame()


def _num(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(number) or math.isinf(number) else number


def _int(value: Any) -> Optional[int]:
    number = _num(value)
    return None if number is None else int(round(number))


def _text(value: Any) -> Optional[str]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    text = str(value).strip()
    return text or None


def _date(value: Any) -> Optional[str]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    if isinstance(value, (datetime, date)):
        return value.isoformat()[:10]
    text = str(value).strip()
    return text[:10] if len(text) >= 10 else None


# --------------------------------------------------------------------------- #
# Player profiles
# --------------------------------------------------------------------------- #
def active_contracts(contracts: pd.DataFrame) -> dict[int, dict[str, Any]]:
    """The one active deal per player: newest signing, then the richest.

    OverTheCap occasionally carries two active rows for a player mid-extension.
    APY share of the cap is taken at signing, which is what makes a 2022 deal
    and a 2026 deal comparable as the cap rises.
    """
    if contracts.empty or "gsis_id" not in contracts.columns:
        return {}
    active = contracts[contracts["is_active"] == True]  # noqa: E712 - pandas mask
    best: dict[int, dict[str, Any]] = {}
    for row in active.itertuples(index=False):
        pid = gsis_to_id(getattr(row, "gsis_id", None))
        apy = _num(getattr(row, "apy", None))
        if pid is None or apy is None or apy <= 0:
            continue
        candidate = {
            "contract_apy": round(apy, 3),
            "contract_cap_pct": _num(getattr(row, "apy_cap_pct", None)),
            "contract_years": _int(getattr(row, "years", None)),
            "contract_year_signed": _int(getattr(row, "year_signed", None)),
            "contract_value": _num(getattr(row, "value", None)),
            "contract_guaranteed": _num(getattr(row, "guaranteed", None)),
        }
        current = best.get(pid)
        key = (candidate["contract_year_signed"] or 0, apy)
        if current is None or key > (current["contract_year_signed"] or 0, current["contract_apy"]):
            best[pid] = candidate
    return best


def season_snaps(snaps: pd.DataFrame, pfr_to_pid: dict[str, int]) -> dict[int, dict[str, Any]]:
    """Season snap totals and share of the team's snaps.

    Share is over every game the player's (latest) club has played, not just
    the games he appeared in, so a starter who missed a week reads as having
    missed it. Team totals are recovered from any player's snaps / pct.
    """
    if snaps.empty:
        return {}
    reg = snaps[snaps["game_type"] == "REG"].copy()
    if reg.empty:
        return {}
    for column in ["offense_snaps", "offense_pct", "defense_snaps", "defense_pct", "st_snaps", "st_pct"]:
        reg[column] = pd.to_numeric(reg[column], errors="coerce").fillna(0)

    def team_total(group: pd.DataFrame, snaps_col: str, pct_col: str) -> float:
        valid = group[group[pct_col] > 0]
        if valid.empty:
            return 0.0
        return float((valid[snaps_col] / valid[pct_col]).median())

    totals: dict[tuple[str, str], tuple[float, float]] = {}
    for (game_id, team), group in reg.groupby(["game_id", "team"]):
        totals[(game_id, team)] = (
            team_total(group, "offense_snaps", "offense_pct"),
            team_total(group, "defense_snaps", "defense_pct"),
        )
    team_games: dict[str, list[str]] = {}
    for game_id, team in totals:
        team_games.setdefault(team, []).append(game_id)

    out: dict[int, dict[str, Any]] = {}
    reg = reg.sort_values("week")
    for pfr_id, group in reg.groupby("pfr_player_id"):
        pid = pfr_to_pid.get(str(pfr_id))
        if pid is None:
            continue
        team = str(group["team"].iloc[-1])
        games = team_games.get(team, [])
        team_off = sum(totals[(g, team)][0] for g in games)
        team_def = sum(totals[(g, team)][1] for g in games)
        # A traded player's snaps from his old club still count; the share is
        # read against the current club's schedule, which is what he is on now.
        off = int(group["offense_snaps"].sum())
        dfn = int(group["defense_snaps"].sum())
        out[pid] = {
            "snap_games": int(group["game_id"].nunique()),
            "team_games": len(games),
            "off_snaps": off,
            "def_snaps": dfn,
            "st_snaps": int(group["st_snaps"].sum()),
            "off_snap_pct": round(min(1.0, off / team_off), 3) if team_off else None,
            "def_snap_pct": round(min(1.0, dfn / team_def), 3) if team_def else None,
        }
    return out


def latest_injuries(injuries: pd.DataFrame) -> dict[int, dict[str, Any]]:
    """Each player's entry on the newest regular-season report he appears on."""
    if injuries.empty:
        return {}
    phase = "game_type" if "game_type" in injuries.columns else "season_type"
    reg = injuries[injuries[phase] == "REG"] if phase in injuries.columns else injuries
    if reg.empty:
        return {}
    out: dict[int, dict[str, Any]] = {}
    for row in reg.sort_values("week").itertuples(index=False):
        pid = gsis_to_id(getattr(row, "gsis_id", None))
        if pid is None:
            continue
        status = _text(getattr(row, "report_status", None))
        practice = _text(getattr(row, "practice_status", None))
        if status is None and practice is None:
            continue
        out[pid] = {
            "injury_week": _int(getattr(row, "week", None)),
            "injury_status": status,
            "injury": _text(getattr(row, "report_primary_injury", None))
            or _text(getattr(row, "practice_primary_injury", None)),
            "practice_status": practice,
        }
    return out


def build_player_profiles(
    season: int,
    player_ids: set[int],
    players: pd.DataFrame,
    contracts: pd.DataFrame,
    snaps: pd.DataFrame,
    injuries: pd.DataFrame,
    now: datetime,
) -> list[dict[str, Any]]:
    """One row per player the app ships for ``season``."""
    bio: dict[int, Any] = {}
    pfr_to_pid: dict[str, int] = {}
    if not players.empty:
        for row in players.itertuples(index=False):
            pid = gsis_to_id(getattr(row, "gsis_id", None))
            if pid is None:
                continue
            bio[pid] = row
            pfr = _text(getattr(row, "pfr_id", None))
            if pfr:
                pfr_to_pid[pfr] = pid

    deals = active_contracts(contracts)
    snap_rows = season_snaps(snaps, pfr_to_pid)
    injury_rows = latest_injuries(injuries)
    stamp = now.isoformat()

    rows: list[dict[str, Any]] = []
    for pid in sorted(player_ids):
        info = bio.get(pid)
        row: dict[str, Any] = {
            "player_id": pid,
            "season": season,
            "jersey": _int(getattr(info, "jersey_number", None)) if info else None,
            "birth_date": _date(getattr(info, "birth_date", None)) if info else None,
            "height_in": _int(getattr(info, "height", None)) if info else None,
            "weight_lb": _int(getattr(info, "weight", None)) if info else None,
            "college": _text(getattr(info, "college_name", None)) if info else None,
            "years_exp": _int(getattr(info, "years_of_experience", None)) if info else None,
            "rookie_season": _int(getattr(info, "rookie_season", None)) if info else None,
            "draft_year": _int(getattr(info, "draft_year", None)) if info else None,
            "draft_round": _int(getattr(info, "draft_round", None)) if info else None,
            "draft_pick": _int(getattr(info, "draft_pick", None)) if info else None,
            "draft_team": _text(getattr(info, "draft_team", None)) if info else None,
            "updated_at": stamp,
        }
        row.update(dict.fromkeys(PROFILE_OPTIONAL_COLUMNS))
        row.update(deals.get(pid, {}))
        row.update(snap_rows.get(pid, {}))
        row.update(injury_rows.get(pid, {}))
        rows.append(row)
    return rows


# --------------------------------------------------------------------------- #
# Team ratings and projections
# --------------------------------------------------------------------------- #
def build_team_ratings(
    season: int,
    schedule: pd.DataFrame,
    pbp: pd.DataFrame,
    prior_schedule: pd.DataFrame,
    prior_pbp: pd.DataFrame,
    now: datetime,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    prior_rows = tr.team_game_rows(prior_pbp, prior_schedule)
    prior = tr.rate(prior_rows, full_schedule_weight=True) if not prior_rows.empty else {}
    rows = tr.team_game_rows(pbp, schedule)
    ratings = tr.rate(rows, prior=prior) if not rows.empty else {}
    through_week = int(rows["week"].max()) if not rows.empty else 0
    if prior:
        # Clubs yet to play (Week 1, or a late opener) start from last season.
        for team, start in tr.preseason(prior).items():
            ratings.setdefault(team, start)

    stamp = now.isoformat()
    ordered = sorted(ratings.values(), key=lambda r: r.rating, reverse=True)
    team_rows = [
        {
            "season": season,
            "team": r.team,
            "rank": index + 1,
            "games": r.games,
            "through_week": through_week,
            "rating": round(r.rating, 2),
            "offense": round(r.offense, 2),
            "defense": round(r.defense, 2),
            "schedule": round(r.schedule, 2),
            "prior_weight": round(r.prior_weight, 3),
            "wins": r.wins,
            "losses": r.losses,
            "ties": r.ties,
            "points_for": int(r.points_for),
            "points_against": int(r.points_against),
            "updated_at": stamp,
        }
        for index, r in enumerate(ordered)
    ]

    projections: list[dict[str, Any]] = []
    upcoming = schedule[schedule["home_score"].isna() | schedule["away_score"].isna()]
    for game in upcoming.itertuples(index=False):
        home = ratings.get(game.home_team)
        away = ratings.get(game.away_team)
        if home is None or away is None:
            continue
        margin, win = tr.project(home, away, neutral=str(getattr(game, "location", "")) == "Neutral")
        projections.append({
            "game_id": game.game_id,
            "season": season,
            "week": int(game.week),
            "home_team": game.home_team,
            "away_team": game.away_team,
            "home_margin": round(margin, 1),
            "home_win_prob": round(win, 3),
            "updated_at": stamp,
        })
    return team_rows, projections


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def _live_player_ids(client: Any, season: int) -> set[int]:
    ids: set[int] = set()
    offset = 0
    while True:
        page = (
            client.table("player_snapshots").select("id")
            .eq("season", season)
            .range(offset, offset + 999)
            .execute()
            .data
        )
        ids.update(int(row["id"]) for row in page)
        if len(page) < 1000:
            return ids
        offset += 1000


def _upsert(client: Any, table: str, rows: list[dict[str, Any]], conflict: str) -> None:
    for start in range(0, len(rows), BATCH):
        client.table(table).upsert(rows[start:start + BATCH], on_conflict=conflict).execute()
    logger.info("Upserted %d %s rows", len(rows), table)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    season = resolve_season(args.season)
    now = datetime.now(UTC)

    client = None
    if not args.dry_run:
        client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

    schedule = _load("schedules", lambda: nfl.load_schedules([season]))
    schedule = schedule[schedule["game_type"] == "REG"] if not schedule.empty else schedule
    prior_schedule = _load("prior schedules", lambda: nfl.load_schedules([season - 1]))
    pbp = _load("pbp", lambda: nfl.load_pbp([season]))
    prior_pbp = _load("prior pbp", lambda: nfl.load_pbp([season - 1]))
    team_rows, projections = build_team_ratings(season, schedule, pbp, prior_schedule, prior_pbp, now)
    logger.info("Built %d team ratings, %d projections", len(team_rows), len(projections))

    player_ids = _live_player_ids(client, season) if client else set()
    players = _load("players", nfl.load_players)
    if not player_ids and not players.empty:
        # Dry run: every active player, so the build is exercised end to end.
        player_ids = {
            pid for pid in (gsis_to_id(g) for g in players["gsis_id"]) if pid is not None
        } if args.dry_run else set()
    contracts = _load("contracts", nfl.load_contracts)
    snaps = _load("snap counts", lambda: nfl.load_snap_counts([season]))
    injuries = _load("injuries", lambda: nfl.load_injuries([season]))
    profiles = build_player_profiles(season, player_ids, players, contracts, snaps, injuries, now)
    logger.info("Built %d player profiles", len(profiles))

    if client is None:
        return 0
    if team_rows:
        _upsert(client, "team_ratings", team_rows, "season,team")
    if projections:
        _upsert(client, "game_projections", projections, "game_id")
    if profiles:
        _upsert(client, "player_profiles", profiles, "player_id,season")
    return 0


if __name__ == "__main__":
    sys.exit(main())
