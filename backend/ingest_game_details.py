"""
Per-game advanced box scores from nflverse play-by-play.

One ``public.game_details`` row per game: team efficiency (EPA/play, success
rate, early-down pass rate, explosive plays, third down and red zone), player
efficiency (passers, rushers, receivers), the win probability line, and the
plays that swung it most. The layout follows the advanced box scores fans
already read on rbsdm.com and similar sites: efficiency first, counts second.

Every team and player rate also carries a percentile against all of this
season's team games (or qualifying player games), recomputed on every run, so
a Week 1 number is ranked against Week 1 and a Week 9 number against nine
weeks of games.

Play filter matches nflfastR convention: offensive plays are passes (including
sacks and scrambles) and designed runs with a non-null EPA; special teams and
no-plays are excluded. Success is EPA > 0.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import sys
from datetime import datetime, timezone
from typing import Any, Iterable, Optional

import nflreadpy as nfl
import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

from ingest import gsis_to_id, resolve_season

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

WP_MAX_POINTS = 160
BIG_PLAYS = 5
# Player-game percentiles only rank lines with real volume behind them.
MIN_DROPBACKS = 10
MIN_CARRIES = 6
MIN_TARGETS = 3

# (key, higher_is_better)
TEAM_METRICS: list[tuple[str, bool]] = [
    ("epa_per_play", True),
    ("success_rate", True),
    ("pass_epa_per_dropback", True),
    ("pass_success_rate", True),
    ("rush_epa_per_carry", True),
    ("rush_success_rate", True),
    ("early_down_pass_rate", True),
    ("pass_rate_over_expected", True),
    ("explosive_play_rate", True),
    ("yards_per_play", True),
    ("third_down_rate", True),
    ("red_zone_td_rate", True),
    ("sack_rate", False),
    ("turnovers", False),
    ("cpoe", True),
    ("adot", True),
]
PASSER_METRICS = [("epa_per_dropback", True), ("success_rate", True), ("cpoe", True), ("adot", True)]
RUSHER_METRICS = [("epa_per_carry", True), ("success_rate", True)]
RECEIVER_METRICS = [("epa_per_target", True), ("success_rate", True), ("adot", True)]


def _f(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(number) or math.isinf(number) else number


def _mean(series: pd.Series) -> Optional[float]:
    s = pd.to_numeric(series, errors="coerce").dropna()
    return _f(s.mean()) if not s.empty else None


def _rate(numerator: float, denominator: float) -> Optional[float]:
    return numerator / denominator if denominator else None


def _round(value: Optional[float], places: int = 3) -> Optional[float]:
    return None if value is None else round(value, places)


def offensive_plays(pbp: pd.DataFrame) -> pd.DataFrame:
    plays = pbp[
        pbp["posteam"].notna()
        & pbp["epa"].notna()
        & ((pbp["pass"] == 1) | (pbp["rush"] == 1))
        & pbp["play_type"].isin(["pass", "run"])
    ].copy()
    plays["successful"] = plays["epa"] > 0
    return plays


def team_stats(game: pd.DataFrame, team: str) -> dict[str, Any]:
    """Efficiency for one offense in one game (``game`` is every pbp row)."""
    plays = offensive_plays(game)
    mine = plays[plays["posteam"] == team]
    dropbacks = mine[mine["qb_dropback"] == 1]
    rushes = mine[(mine["rush"] == 1) & (mine["qb_dropback"] != 1)]
    attempts = mine[(mine["pass"] == 1) & (mine["sack"] != 1) & mine["air_yards"].notna()]
    early = mine[mine["down"].isin([1, 2])]
    explosive = ((mine["pass"] == 1) & (mine["yards_gained"] >= 20)) | ((mine["rush"] == 1) & (mine["yards_gained"] >= 10))

    all_team = game[game["posteam"] == team]
    third_conv = float(pd.to_numeric(all_team["third_down_converted"], errors="coerce").fillna(0).sum())
    third_fail = float(pd.to_numeric(all_team["third_down_failed"], errors="coerce").fillna(0).sum())

    drives = all_team[all_team["fixed_drive"].notna()].groupby("fixed_drive")
    red_zone_trips = 0
    red_zone_tds = 0
    for _, drive in drives:
        if (pd.to_numeric(drive["yardline_100"], errors="coerce") <= 20).any():
            red_zone_trips += 1
            if (drive["fixed_drive_result"] == "Touchdown").any():
                red_zone_tds += 1

    turnovers = float(
        pd.to_numeric(all_team["interception"], errors="coerce").fillna(0).sum()
        + pd.to_numeric(all_team["fumble_lost"], errors="coerce").fillna(0).sum()
    )
    pass_oe = pd.to_numeric(mine["pass_oe"], errors="coerce").dropna()

    return {
        "plays": int(len(mine)),
        "total_epa": _round(_f(mine["epa"].sum()), 2),
        "epa_per_play": _round(_mean(mine["epa"])),
        "success_rate": _round(_rate(float(mine["successful"].sum()), len(mine))),
        "dropbacks": int(len(dropbacks)),
        "pass_epa_per_dropback": _round(_mean(dropbacks["epa"])),
        "pass_success_rate": _round(_rate(float((dropbacks["epa"] > 0).sum()), len(dropbacks))),
        "carries": int(len(rushes)),
        "rush_epa_per_carry": _round(_mean(rushes["epa"])),
        "rush_success_rate": _round(_rate(float((rushes["epa"] > 0).sum()), len(rushes))),
        "early_down_pass_rate": _round(_rate(float((early["pass"] == 1).sum()), len(early))),
        "pass_rate_over_expected": _round(_f(pass_oe.mean()) / 100 if not pass_oe.empty else None),
        "explosive_plays": int(explosive.sum()),
        "explosive_play_rate": _round(_rate(float(explosive.sum()), len(mine))),
        "yards_per_play": _round(_mean(mine["yards_gained"]), 2),
        "third_down_conversions": int(third_conv),
        "third_down_attempts": int(third_conv + third_fail),
        "third_down_rate": _round(_rate(third_conv, third_conv + third_fail)),
        "red_zone_trips": red_zone_trips,
        "red_zone_tds": red_zone_tds,
        "red_zone_td_rate": _round(_rate(red_zone_tds, red_zone_trips)),
        "sacks": int(pd.to_numeric(mine["sack"], errors="coerce").fillna(0).sum()),
        "sack_rate": _round(_rate(float(pd.to_numeric(dropbacks["sack"], errors="coerce").fillna(0).sum()), len(dropbacks))),
        "turnovers": int(turnovers),
        "cpoe": _round(_mean(attempts["cpoe"]), 1),
        "adot": _round(_mean(attempts["air_yards"]), 1),
    }


def _player_name(rows: pd.DataFrame, column: str) -> Optional[str]:
    names = rows[column].dropna() if column in rows.columns else pd.Series(dtype=object)
    return str(names.iloc[0]) if not names.empty else None


def player_stats(game: pd.DataFrame) -> list[dict[str, Any]]:
    """Passer, rusher and receiver efficiency lines for one game."""
    plays = offensive_plays(game)
    out: list[dict[str, Any]] = []

    dropbacks = plays[(plays["qb_dropback"] == 1) & plays["passer_player_id"].notna()]
    for gsis, rows in dropbacks.groupby("passer_player_id"):
        attempts = rows[(rows["pass"] == 1) & (rows["sack"] != 1) & rows["air_yards"].notna()]
        qb_epa = rows["qb_epa"] if "qb_epa" in rows.columns else rows["epa"]
        out.append({
            "role": "passer",
            "player_id": gsis_to_id(gsis),
            "name": _player_name(rows, "passer_player_name"),
            "team": str(rows["posteam"].iloc[0]),
            "dropbacks": int(len(rows)),
            "epa": _round(_f(qb_epa.sum()), 2),
            "epa_per_dropback": _round(_mean(qb_epa)),
            "success_rate": _round(_rate(float((rows["epa"] > 0).sum()), len(rows))),
            "cpoe": _round(_mean(attempts["cpoe"]), 1),
            "adot": _round(_mean(attempts["air_yards"]), 1),
        })

    rushes = plays[(plays["rush"] == 1) & plays["rusher_player_id"].notna()]
    for gsis, rows in rushes.groupby("rusher_player_id"):
        out.append({
            "role": "rusher",
            "player_id": gsis_to_id(gsis),
            "name": _player_name(rows, "rusher_player_name"),
            "team": str(rows["posteam"].iloc[0]),
            "carries": int(len(rows)),
            "epa": _round(_f(rows["epa"].sum()), 2),
            "epa_per_carry": _round(_mean(rows["epa"])),
            "success_rate": _round(_rate(float((rows["epa"] > 0).sum()), len(rows))),
        })

    targets = plays[(plays["pass"] == 1) & plays["receiver_player_id"].notna()]
    for gsis, rows in targets.groupby("receiver_player_id"):
        out.append({
            "role": "receiver",
            "player_id": gsis_to_id(gsis),
            "name": _player_name(rows, "receiver_player_name"),
            "team": str(rows["posteam"].iloc[0]),
            "targets": int(len(rows)),
            "epa": _round(_f(rows["epa"].sum()), 2),
            "epa_per_target": _round(_mean(rows["epa"])),
            "success_rate": _round(_rate(float((rows["epa"] > 0).sum()), len(rows))),
            "adot": _round(_mean(rows["air_yards"]), 1),
        })
    return [row for row in out if row["player_id"] is not None]


def win_probability(game: pd.DataFrame) -> list[list[float]]:
    """[elapsed_seconds, home_wp] points, downsampled, ending on the result."""
    rows = game[game["home_wp"].notna() & game["qtr"].notna()]
    points: list[list[float]] = []
    for _, row in rows.iterrows():
        qtr = int(row["qtr"])
        remaining = _f(row.get("quarter_seconds_remaining")) or 0.0
        elapsed = (qtr - 1) * 900 + (900 - remaining) if qtr <= 4 else 3600 + (600 - remaining)
        points.append([round(elapsed), round(float(row["home_wp"]), 3)])
    if len(points) > WP_MAX_POINTS:
        stride = math.ceil(len(points) / WP_MAX_POINTS)
        points = points[::stride] + [points[-1]]
    return points


def big_plays(game: pd.DataFrame) -> list[dict[str, Any]]:
    rows = game[game["wpa"].notna() & game["desc"].notna() & game["posteam"].notna()].copy()
    if rows.empty:
        return []
    rows["swing"] = rows["wpa"].abs()
    out = []
    for _, row in rows.sort_values("swing", ascending=False).head(BIG_PLAYS).iterrows():
        home = row["posteam"] == row["home_team"]
        wpa = float(row["wpa"])
        out.append({
            "qtr": int(row["qtr"]),
            "clock": str(row.get("time") or ""),
            "team": str(row["posteam"]),
            "description": str(row["desc"])[:240],
            "epa": _round(_f(row["epa"]), 2),
            # Win probability added for the home team, so the sign reads the
            # same way as the chart.
            "home_wpa": _round(wpa if home else -wpa, 3),
        })
    return out


def attach_percentiles(rows: list[dict[str, Any]], metrics: Iterable[tuple[str, bool]],
                       eligible=lambda row: True) -> None:
    """Replace each metric value with {"value", "pct"} ranked across ``rows``."""
    for key, higher in metrics:
        pool = [row[key] for row in rows if eligible(row) and row.get(key) is not None]
        series = pd.Series(pool, dtype=float)
        for row in rows:
            value = row.get(key)
            if value is None:
                row[key] = None
                continue
            pct = None
            if eligible(row) and len(series) > 1:
                below = float((series < value).sum()) if higher else float((series > value).sum())
                equal = float((series == value).sum())
                pct = max(1, min(100, round((below + equal / 2) / len(series) * 100)))
            row[key] = {"value": value, "pct": pct}


def build_rows(pbp: pd.DataFrame, now: datetime) -> list[dict[str, Any]]:
    games = []
    team_rows: list[dict[str, Any]] = []
    player_rows: list[dict[str, Any]] = []
    for game_id, game in pbp.groupby("game_id"):
        first = game.iloc[0]
        teams = {"away": str(first["away_team"]), "home": str(first["home_team"])}
        stats = {side: team_stats(game, abbr) for side, abbr in teams.items()}
        for side, row in stats.items():
            row["_game"] = game_id
            row["_side"] = side
            team_rows.append(row)
        players = player_stats(game)
        for row in players:
            row["_game"] = game_id
        player_rows.extend(players)
        games.append({
            "game_id": str(game_id),
            "season": int(first["season"]),
            "season_type": "REG" if str(first["season_type"]) == "REG" else "POST",
            "week": int(first["week"]),
            "away_team": teams["away"],
            "home_team": teams["home"],
            "win_probability": win_probability(game),
            "big_plays": big_plays(game),
        })

    attach_percentiles(team_rows, TEAM_METRICS)
    attach_percentiles([r for r in player_rows if r["role"] == "passer"], PASSER_METRICS,
                       eligible=lambda r: r["dropbacks"] >= MIN_DROPBACKS)
    attach_percentiles([r for r in player_rows if r["role"] == "rusher"], RUSHER_METRICS,
                       eligible=lambda r: r["carries"] >= MIN_CARRIES)
    attach_percentiles([r for r in player_rows if r["role"] == "receiver"], RECEIVER_METRICS,
                       eligible=lambda r: r["targets"] >= MIN_TARGETS)

    by_game_teams: dict[str, dict[str, Any]] = {}
    for row in team_rows:
        game_id, side = row.pop("_game"), row.pop("_side")
        by_game_teams.setdefault(game_id, {})[side] = row
    by_game_players: dict[str, list[dict[str, Any]]] = {}
    for row in player_rows:
        by_game_players.setdefault(row.pop("_game"), []).append(row)

    stamp = now.isoformat()
    for game in games:
        game["team_stats"] = by_game_teams.get(game["game_id"], {})
        game["players"] = by_game_players.get(game["game_id"], [])
        game["updated_at"] = stamp
    return games


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    season = resolve_season(args.season)

    pbp = nfl.load_pbp([season]).to_pandas()
    if pbp.empty:
        logger.info("No play-by-play for %s yet", season)
        return 0
    rows = build_rows(pbp, datetime.now(UTC))
    logger.info("Built %d game detail rows for %s", len(rows), season)
    if args.dry_run:
        return 0

    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    for start in range(0, len(rows), 50):
        client.table("game_details").upsert(rows[start:start + 50], on_conflict="game_id").execute()
    return 0


if __name__ == "__main__":
    sys.exit(main())
