"""
Context the stat snapshots do not carry: who a player is, how much he plays,
team power ratings and a projected margin for every game still to be played.

Writes three tables, none of which the published snapshots depend on, so this
job can fail, lag or be rerun without touching them:

* ``player_profiles``: one row per player with a snapshot in the live season.
  Bio from the NHL player landing endpoint (``api-web.nhle.com/v1/player/<id>/
  landing``: sweater number, birth date, height, weight, birthplace as
  "City, ST, CC" or "City, CC", draft, first NHL season), cached in
  ``backend/.cache/players/`` for 30 days because bios rarely change. Ice time
  from ``player_game_logs`` (regular season): ``toi_seconds``, ``toi_per_gp``
  (seconds a game) and ``toi_share`` (his time with his latest club over that
  club's total skater time, so a player who missed games reads lower; goalies
  have none), plus ``pp_toi_seconds`` and ``pk_toi_seconds`` from MoneyPuck's
  ``5on4`` and ``4on5`` icetime rows. There is no free contract, snap or injury
  source, so those columns stay null (the app hides them).
* ``team_ratings``: goals per game against an average team, see
  ``team_ratings.py``. ``points_for`` / ``points_against`` hold goals and
  ``ties`` holds overtime and shootout losses.
* ``game_projections``: projected home margin (goals) and win probability for
  each unplayed game this season.

``years_exp`` = season - rookie season (0 for a rookie); ``rookie_season`` is
the start year of his first NHL season in the landing ``seasonTotals``.

Every source is optional: a missing bio leaves that player's bio columns null
for this run rather than failing the others.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. ``HOCKEY_NO_CACHE=1`` ignores the
bio cache.
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Mapping, Optional

import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

import team_ratings as tr
from ingest import CACHE_DIR, DEFAULT_SEASON, MIN_SEASON, http_get, load_moneypuck, resolve_season
from ingest_game_logs import load_shots_frame

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc
BATCH = 500
PAGE = 1000

LANDING_URL = "https://api-web.nhle.com/v1/player/{pid}/landing"
PROFILE_CACHE_DIR = CACHE_DIR / "players"
PROFILE_TTL = timedelta(days=30)
RATING_SHOT_COLUMNS = ("game_id", "team", "xGoal", "goal", "time")
SKATER_TYPES = ("f", "d")

US_STATES = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA",
    "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE", "District of Columbia": "DC",
    "Florida": "FL", "Georgia": "GA", "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL",
    "Indiana": "IN", "Iowa": "IA", "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA",
    "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN",
    "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE", "Nevada": "NV",
    "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
    "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK", "Oregon": "OR",
    "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
    "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA",
    "Washington": "WA", "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
}
CA_PROVINCES = {
    "Alberta": "AB", "British Columbia": "BC", "Manitoba": "MB", "New Brunswick": "NB",
    "Newfoundland and Labrador": "NL", "Newfoundland": "NL", "Nova Scotia": "NS",
    "Northwest Territories": "NT", "Nunavut": "NU", "Ontario": "ON",
    "Prince Edward Island": "PE", "Quebec": "QC", "Québec": "QC", "Saskatchewan": "SK",
    "Yukon": "YT",
}
REGIONS = {"USA": US_STATES, "CAN": CA_PROVINCES}


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


def _localized(value: Any) -> Optional[str]:
    """``{"default": "Richmond Hill", "fr": ...}`` -> ``"Richmond Hill"``."""
    return _text(value.get("default")) if isinstance(value, dict) else _text(value)


# --------------------------------------------------------------------------- #
# Player profiles
# --------------------------------------------------------------------------- #
def birthplace(landing: Mapping[str, Any]) -> Optional[str]:
    """``"Richmond Hill, ON, CAN"``; the region only for Canada and the US."""
    city = _localized(landing.get("birthCity"))
    if not city:
        return None
    country = _text(landing.get("birthCountry"))
    region = _localized(landing.get("birthStateProvince"))
    if region and country in REGIONS:
        region = REGIONS[country].get(region, region if len(region) <= 3 else None)
    else:
        region = None
    return ", ".join(part for part in (city, region, country) if part)


def first_nhl_season(landing: Mapping[str, Any]) -> Optional[int]:
    """Start year of the first NHL season in ``seasonTotals`` (20152016 -> 2015)."""
    seasons = [
        _int(row.get("season")) for row in landing.get("seasonTotals") or []
        if row.get("leagueAbbrev") == "NHL"
    ]
    seasons = [s for s in seasons if s]
    return min(seasons) // 10000 if seasons else None


def parse_landing(landing: Mapping[str, Any]) -> dict[str, Any]:
    """The bio columns a landing payload supplies (season-independent)."""
    draft = landing.get("draftDetails") or {}
    return {
        "jersey": _int(landing.get("sweaterNumber")),
        "birth_date": _text(landing.get("birthDate")),
        "height_in": _int(landing.get("heightInInches")),
        "weight_lb": _int(landing.get("weightInPounds")),
        "birthplace": birthplace(landing),
        "rookie_season": first_nhl_season(landing),
        "draft_year": _int(draft.get("year")),
        "draft_round": _int(draft.get("round")),
        "draft_pick": _int(draft.get("overallPick")),
        "draft_team": _text(draft.get("teamAbbrev")),
    }


def _cache_path(pid: int) -> Path:
    return PROFILE_CACHE_DIR / f"{pid}.json"


def cached_bio(pid: int, now: datetime) -> Optional[dict[str, Any]]:
    """A bio younger than the TTL from ``backend/.cache/players/``, else None."""
    if os.environ.get("HOCKEY_NO_CACHE") == "1":
        return None
    try:
        saved = json.loads(_cache_path(pid).read_text())
        fetched = datetime.fromisoformat(saved["fetched_at"])
    except (OSError, ValueError, KeyError):
        return None
    return saved["bio"] if now - fetched < PROFILE_TTL else None


def save_bio(pid: int, bio: Mapping[str, Any], now: datetime) -> None:
    PROFILE_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    _cache_path(pid).write_text(json.dumps({"fetched_at": now.isoformat(), "bio": bio}))


def load_bio(pid: int, now: datetime) -> dict[str, Any]:
    """One player's bio: the cache, else the landing endpoint; {} when unavailable."""
    bio = cached_bio(pid, now)
    if bio is not None:
        return bio
    try:
        content = http_get(LANDING_URL.format(pid=pid))
    except Exception as error:  # noqa: BLE001 - one missing bio must not sink the rest
        logger.warning("Landing for %s failed: %s", pid, error)
        return {}
    if not content:
        return {}
    bio = parse_landing(json.loads(content))
    save_bio(pid, bio, now)
    return bio


def ice_time(logs: pd.DataFrame) -> dict[int, dict[str, Any]]:
    """Season ice time per player from his regular-season game logs.

    ``logs`` has ``player_id``, ``team``, ``player_type``, ``game_date`` and
    ``toi`` (seconds). The share is over the latest club's skater time.
    """
    if logs.empty:
        return {}
    played = logs[logs["toi"] > 0]
    skater_totals = played[played["player_type"].isin(SKATER_TYPES)].groupby("team")["toi"].sum()
    out: dict[int, dict[str, Any]] = {}
    for pid, rows in played.groupby("player_id"):
        total = int(rows["toi"].sum())
        last = rows.sort_values("game_date").iloc[-1]
        share = None
        if last["player_type"] in SKATER_TYPES and skater_totals.get(last["team"], 0) > 0:
            with_club = rows.loc[rows["team"] == last["team"], "toi"].sum()
            share = round(float(with_club) / float(skater_totals[last["team"]]), 4)
        out[int(pid)] = {
            "toi_seconds": total,
            "toi_per_gp": round(total / len(rows), 1),
            "toi_share": share,
        }
    return out


def special_teams_toi(skaters: pd.DataFrame) -> dict[int, dict[str, int]]:
    """Power-play and penalty-kill seconds from MoneyPuck's ``5on4`` / ``4on5`` rows."""
    if skaters.empty:
        return {}
    out: dict[int, dict[str, int]] = {}
    for situation, column in (("5on4", "pp_toi_seconds"), ("4on5", "pk_toi_seconds")):
        rows = skaters[skaters["situation"] == situation]
        for pid, seconds in rows.groupby("playerId")["icetime"].sum().items():
            out.setdefault(int(pid), {})[column] = int(round(seconds))
    return out


def build_player_profiles(
    season: int,
    player_ids: set[int],
    bios: Mapping[int, Mapping[str, Any]],
    ice: Mapping[int, Mapping[str, Any]],
    special: Mapping[int, Mapping[str, int]],
    now: datetime,
) -> list[dict[str, Any]]:
    """One row per player the app ships for ``season``, every column present."""
    stamp = now.isoformat()
    rows: list[dict[str, Any]] = []
    for pid in sorted(player_ids):
        bio = bios.get(pid) or {}
        rookie = bio.get("rookie_season")
        times = ice.get(pid) or {}
        extra = special.get(pid) or {}
        rows.append({
            "player_id": pid,
            "season": season,
            "jersey": bio.get("jersey"),
            "birth_date": bio.get("birth_date"),
            "height_in": bio.get("height_in"),
            "weight_lb": bio.get("weight_lb"),
            "birthplace": bio.get("birthplace"),
            "years_exp": None if rookie is None else max(0, season - rookie),
            "rookie_season": rookie,
            "draft_year": bio.get("draft_year"),
            "draft_round": bio.get("draft_round"),
            "draft_pick": bio.get("draft_pick"),
            "draft_team": bio.get("draft_team"),
            "toi_seconds": times.get("toi_seconds"),
            "toi_per_gp": times.get("toi_per_gp"),
            "pp_toi_seconds": extra.get("pp_toi_seconds"),
            "pk_toi_seconds": extra.get("pk_toi_seconds"),
            "toi_share": times.get("toi_share"),
            "updated_at": stamp,
        })
    return rows


# --------------------------------------------------------------------------- #
# Team ratings and projections
# --------------------------------------------------------------------------- #
def build_team_ratings(
    season: int,
    schedule: pd.DataFrame,
    totals: pd.DataFrame,
    prior_schedule: pd.DataFrame,
    prior_totals: pd.DataFrame,
    now: datetime,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Rows for ``team_ratings`` and ``game_projections`` (unplayed games)."""
    prior_rows = tr.team_game_rows(prior_schedule, prior_totals)
    prior = tr.rate(prior_rows, full_schedule_weight=True) if not prior_rows.empty else {}
    rows = tr.team_game_rows(schedule, totals)
    ratings = tr.rate(rows, prior=prior) if not rows.empty else {}
    through_week = int(rows["week"].max()) if not rows.empty else 0

    # Clubs yet to play start from last season; a club with no history at all
    # starts at average, so every club on the schedule is rated.
    clubs = set(schedule["home_team"]) | set(schedule["away_team"]) if not schedule.empty else set(prior)
    for team, start in tr.preseason(prior).items():
        if team in clubs:
            ratings.setdefault(team, start)
    for team in clubs:
        ratings.setdefault(team, tr.average_club(team))

    stamp = now.isoformat()
    ordered = sorted(ratings.values(), key=lambda r: (-r.rating, r.team))
    team_rows = [
        {
            "season": season,
            "team": r.team,
            "rank": index + 1,
            "games": r.games,
            "through_week": through_week,
            "rating": round(r.rating, 3),
            "offense": round(r.offense, 3),
            "defense": round(r.defense, 3),
            "schedule": round(r.schedule, 3),
            "prior_weight": round(r.prior_weight, 3),
            "wins": r.wins,
            "losses": r.losses,
            "ties": r.otl,
            "points_for": int(r.goals_for),
            "points_against": int(r.goals_against),
            "updated_at": stamp,
        }
        for index, r in enumerate(ordered)
    ]

    projections: list[dict[str, Any]] = []
    upcoming = (
        schedule[schedule["home_score"].isna() | schedule["away_score"].isna()]
        if not schedule.empty else schedule
    )
    for game in upcoming.itertuples(index=False):
        home = ratings.get(game.home_team)
        away = ratings.get(game.away_team)
        if home is None or away is None:
            continue
        margin, win = tr.project(home, away)
        projections.append({
            "game_id": str(game.game_id),
            "season": season,
            "week": int(game.week),
            "home_team": game.home_team,
            "away_team": game.away_team,
            "home_margin": round(margin, 2),
            "home_win_prob": round(win, 3),
            "updated_at": stamp,
        })
    return team_rows, projections


# --------------------------------------------------------------------------- #
# Database
# --------------------------------------------------------------------------- #
def _pages(query: Callable[[int, int], Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        page = query(offset, offset + PAGE - 1).execute().data or []
        rows.extend(page)
        if len(page) < PAGE:
            return rows
        offset += PAGE


def fetch_schedule(client: Any, season: int) -> pd.DataFrame:
    """Regular-season rows of ``public.games`` for the season."""
    rows = _pages(lambda lo, hi: (
        client.table("games")
        .select("game_id,week,home_team,away_team,home_score,away_score,overtime")
        .eq("season", season).eq("season_type", "REG")
        .order("game_id").range(lo, hi)
    ))
    return pd.DataFrame(rows)


def fetch_player_ids(client: Any, season: int) -> set[int]:
    rows = _pages(lambda lo, hi: (
        client.table("player_snapshots").select("id,season_type").eq("season", season)
        .order("id").order("season_type").range(lo, hi)
    ))
    return {int(row["id"]) for row in rows}


def fetch_toi_logs(client: Any, season: int) -> pd.DataFrame:
    rows = _pages(lambda lo, hi: (
        client.table("player_game_logs")
        .select("player_id,team,player_type,game_date,toi:metrics->>toi_seconds")
        .eq("season", season).eq("season_type", "REG")
        .order("player_id").order("game_date").order("player_type").range(lo, hi)
    ))
    frame = pd.DataFrame(rows)
    if not frame.empty:
        frame["toi"] = pd.to_numeric(frame["toi"], errors="coerce").fillna(0)
    return frame


def _upsert(client: Any, table: str, rows: list[dict[str, Any]], conflict: str) -> None:
    for start in range(0, len(rows), BATCH):
        client.table(table).upsert(rows[start:start + BATCH], on_conflict=conflict).execute()
    logger.info("Upserted %d %s rows", len(rows), table)


def shot_totals(season: int) -> pd.DataFrame:
    """Per-game xG and goals from the shot file; empty when it is not published."""
    frame = load_shots_frame(season, season >= DEFAULT_SEASON, RATING_SHOT_COLUMNS)
    return tr.game_shot_totals(frame) if frame is not None else pd.DataFrame()


def special_teams(season: int) -> dict[int, dict[str, int]]:
    try:
        return special_teams_toi(load_moneypuck("skaters", season, "REG"))
    except Exception:  # noqa: BLE001 - MoneyPuck is optional here
        logger.exception("Could not load MoneyPuck special teams ice time.")
        return {}


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true", help="Build but do not write.")
    args = parser.parse_args()
    season = resolve_season(args.season)
    now = datetime.now(UTC)
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

    schedule = fetch_schedule(client, season)
    prior_schedule = fetch_schedule(client, season - 1) if season - 1 >= MIN_SEASON else pd.DataFrame()
    team_rows, projections = build_team_ratings(
        season, schedule, shot_totals(season),
        prior_schedule, shot_totals(season - 1) if not prior_schedule.empty else pd.DataFrame(), now,
    )
    logger.info("Built %d team ratings, %d projections", len(team_rows), len(projections))
    if not args.dry_run:
        if team_rows:
            _upsert(client, "team_ratings", team_rows, "season,team")
        if projections:
            _upsert(client, "game_projections", projections, "game_id")

    player_ids = fetch_player_ids(client, season)
    bios = {pid: load_bio(pid, now) for pid in sorted(player_ids)}
    profiles = build_player_profiles(
        season, player_ids, bios, ice_time(fetch_toi_logs(client, season)), special_teams(season), now
    )
    logger.info("Built %d player profiles (%d with a bio)", len(profiles), sum(1 for b in bios.values() if b))
    if profiles and not args.dry_run:
        _upsert(client, "player_profiles", profiles, "player_id,season")
    return 0


if __name__ == "__main__":
    sys.exit(main())
