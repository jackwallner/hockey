"""
Per-game shot-level box scores from MoneyPuck shots and the NHL gamecenter.

One ``public.game_details`` row per final game, in the shapes the app's
``GameDetail`` decoder reads (``project-docs/architecture/HOCKEY_CONTRACT.md``):

* ``team_stats`` ``{away, home}``: expected goals (all strengths and 5v5),
  xGF% and CF% at 5v5, high-danger chances, shots, attempts, goals, goals above
  expected, power play, faceoffs, hits, blocks and penalty minutes. The eight
  rated numbers carry ``{value, pct}``, the rest are plain counts.
* ``players``: every skater and goalie who played, with ``toi`` in seconds and
  ``{value, pct}`` on ixG, GAx and ixG/60 (skaters) or xGA, GSAx and SV%
  (goalies).
* ``win_probability`` (column name kept): the cumulative xG race, one
  ``[t_seconds, away_xg, home_xg, away_goals, home_goals]`` entry per shot plus
  a last entry at the end of the game that carries the official final score.
* ``big_plays``: every goal and the five highest-xG chances that were not.

Sources per game, joined on the NHL player id:

* MoneyPuck ``shots_<season>.zip`` (via ``ingest_game_logs.load_shots_frame``):
  every unblocked attempt with xGoal, shooter, goalie, period, game second,
  shot type, distance and the rebound, rush and empty-net flags. Shootout
  attempts are not in the file, so nothing is excluded here; a final is built
  only once the file contains it (else a false zero xG), the rest wait.
* NHL boxscore: assists, points, shots on goal, time on ice, goalie save
  lines, goals, the end of the game (period and clock) and team shots.
* NHL play-by-play: the blocked attempts MoneyPuck leaves out (per shooter for
  the player line, per team at 5v5 for CF%) and full player names.
* NHL ``right-rail``: team power play (goals and opportunities), faceoff wins
  and totals, hits, blocks and penalty minutes. The boxscore has only a
  per-player faceoff percentage and no opportunities. When the endpoint is
  missing the boxscore sums stand in for hits, blocks and penalty minutes.

Definitions (constants below):

* 5v5 = five skaters a side and no empty net, which matches the play-by-play
  situation code ``1551``.
* ``shot_attempts`` = MoneyPuck's unblocked attempts + NHL blocked attempts.
  CF% = attempts for / (for + against) at 5v5.
* ``hd_chances`` = attempts with xG >= 0.2 (the game-log rule).
* ``goals`` = the skaters' goals in the boxscore (shootout excluded), so a
  goal missing from the shot file still counts and GAx is goals - xG.
* Percentiles rank higher as better and are taken across this season's team
  games (or qualifying player games) of the same phase, REG and POST apart.
  Skaters qualify with 8+ minutes, goalies with 20+ minutes. A goalie's xGA is
  ranked higher = busier, like the snapshot's goalie xGA/60. Players below the
  bar keep their value with a null ``pct``.
* Shares (xGF%, CF%, faceoff %, SV%) are fractions 0..1.
* The race's last point is at the end of regulation (3600) or overtime. It
  carries the official score from ``public.games``, so a shootout game reads
  3-2 even though the shootout's goal is not a shot. Goals inside the race come
  from the shot file; a handful of goals are missing from MoneyPuck, which the
  last point corrects.

Incremental by default: finals with no row yet are built, then every row of
the season and phase is re-ranked from its stored values (percentiles move as
games arrive) and only rows whose ranks changed are written again. ``--full``
rebuilds every final from the sources. ``--season N`` overrides the season.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, Optional

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

from ingest import DEFAULT_SEASON, chunks, normalize_team, resolve_season
from ingest_game_logs import (
    HIGH_DANGER_XG,
    ShotTables,
    build_shot_tables,
    fetch_final_games,
    fetch_gamecenter,
    load_shots_frame,
    parse_play_by_play,
    short_game_id,
    toi_seconds,
)

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

BIG_PLAY_NON_GOALS = 5
MIN_SKATER_SECONDS = 8 * 60
MIN_GOALIE_SECONDS = 20 * 60
PERIOD_SECONDS = 1200
REGULATION_SECONDS = 3 * PERIOD_SECONDS
REGULAR_OT_SECONDS = 300
SHOOTOUT_GAME_SECONDS = REGULATION_SECONDS + REGULAR_OT_SECONDS
UPSERT_BATCH = 25
FETCH_WORKERS = 4  # games fetched at once; each game is three NHL calls
FETCH_CHUNK = 64
STORED_PAGE = 100
EVEN_STRENGTH_SKATERS = 5

SHOT_FIELDS = (
    "game_id", "event", "period", "time", "xGoal", "goal", "team", "teamCode",
    "shooterPlayerId", "shooterName", "goalieIdForShot", "shotType",
    "arenaAdjustedShotDistance", "shotDistance", "shotRebound", "shotRush",
    "shotOnEmptyNet", "shotWasOnGoal", "homeSkatersOnIce", "awaySkatersOnIce",
    "homeEmptyNet", "awayEmptyNet", "shotID",
)

SHOT_TYPES = {
    "WRIST": "Wrist shot", "SNAP": "Snap shot", "SLAP": "Slap shot", "TIP": "Tip-in",
    "BACK": "Backhand", "DEFL": "Deflection", "WRAP": "Wraparound",
}
# Upper bound in feet -> label, checked in order; the last label is the rest.
DISTANCE_BANDS = ((12, "in close"), (25, "slot"), (40, "mid-range"), (60, "from the point"))
FAR_BAND = "long range"
RESULTS = {"GOAL": "GOAL", "SHOT": "SAVE", "MISS": "MISS", "BLOCK": "BLOCK"}

# (key, higher_is_better). Every rated number ranks higher as better.
TEAM_METRICS = [
    ("xg", True), ("xg_5v5", True), ("xgf_pct_5v5", True), ("cf_pct_5v5", True),
    ("hd_chances", True), ("shot_attempts", True), ("gax", True), ("faceoff_pct", True),
]
SKATER_METRICS = [("ixg", True), ("gax", True), ("ixg_per_60", True)]
GOALIE_METRICS = [("xga", True), ("gsax", True), ("sv_pct", True)]


# --------------------------------------------------------------------------- #
# Small value helpers
# --------------------------------------------------------------------------- #
def _num(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(number) or math.isinf(number) else number


def _int(value: Any) -> int:
    number = _num(value)
    return 0 if number is None else int(number)


def _round(value: Optional[float], places: int = 3) -> Optional[float]:
    return None if value is None else round(value, places)


def _share(numerator: float, denominator: float) -> Optional[float]:
    return _round(numerator / denominator, 4) if denominator else None


def _ratio(text: Any) -> tuple[Optional[int], Optional[int]]:
    """``"34/63"`` -> (34, 63)."""
    try:
        left, right = str(text).split("/")
        return int(left), int(right)
    except (TypeError, ValueError):
        return None, None


def _flag(value: Any) -> bool:
    return _num(value) == 1


def clock_text(seconds: Any, period: int) -> str:
    """Game second -> elapsed time in its period, ``"12:34"``."""
    elapsed = max(0, _int(seconds) - PERIOD_SECONDS * (period - 1))
    return f"{elapsed // 60}:{elapsed % 60:02d}"


# --------------------------------------------------------------------------- #
# Shots: description, race, big plays
# --------------------------------------------------------------------------- #
def distance_band(feet: Any) -> str:
    distance = _num(feet)
    if distance is None:
        return ""
    for limit, label in DISTANCE_BANDS:
        if distance <= limit:
            return label
    return FAR_BAND


def shot_description(shot: Mapping[str, Any]) -> str:
    """``"Snap shot, slot, rebound"`` from shot type, distance band and flags."""
    kind = SHOT_TYPES.get(str(shot.get("shotType") or "").upper(), "Shot")
    distance = shot.get("arenaAdjustedShotDistance")
    parts = [kind, distance_band(distance if _num(distance) is not None else shot.get("shotDistance"))]
    for column, label in (("shotRebound", "rebound"), ("shotRush", "rush"), ("shotOnEmptyNet", "empty net")):
        if _flag(shot.get(column)):
            parts.append(label)
    return ", ".join(part for part in parts if part)


def ordered_shots(shots: pd.DataFrame) -> pd.DataFrame:
    """One game's shots in play order (game second, then the file's own order)."""
    keys = [c for c in ("time", "shotID") if c in shots.columns]
    return shots.sort_values(keys, kind="stable").reset_index(drop=True)


def game_end_seconds(boxscore: Optional[Mapping[str, Any]], last_shot: float = 0.0) -> int:
    """Game second of the final horn from the boxscore's last period and clock.

    A shootout is reached only after a full five-minute overtime. Without a
    boxscore the later of regulation and the last shot stands in.
    """
    if not boxscore:
        return int(max(REGULATION_SECONDS, last_shot))
    period = boxscore.get("periodDescriptor") or {}
    number = _int(period.get("number")) or 3
    if str(period.get("periodType") or "").upper() == "SO":
        return SHOOTOUT_GAME_SECONDS
    playoff = _int(boxscore.get("gameType")) == 3
    length = PERIOD_SECONDS if number <= 3 or playoff else REGULAR_OT_SECONDS
    remaining = _int((boxscore.get("clock") or {}).get("secondsRemaining"))
    return PERIOD_SECONDS * (number - 1) + length - remaining


def xg_race(
    shots: pd.DataFrame,
    final_away: Optional[int],
    final_home: Optional[int],
    end_seconds: int,
) -> list[list[float]]:
    """Cumulative xG race: one entry per shot, then the end of the game."""
    points: list[list[float]] = []
    xg = {"AWAY": 0.0, "HOME": 0.0}
    goals = {"AWAY": 0, "HOME": 0}
    for shot in shots.to_dict("records"):
        side = "HOME" if str(shot.get("team")).upper() == "HOME" else "AWAY"
        xg[side] += _num(shot.get("xGoal")) or 0.0
        goals[side] += int(_flag(shot.get("goal")))
        points.append([
            _int(shot.get("time")), round(xg["AWAY"], 3), round(xg["HOME"], 3),
            goals["AWAY"], goals["HOME"],
        ])
    last = points[-1][0] if points else 0
    points.append([
        max(end_seconds, last), round(xg["AWAY"], 3), round(xg["HOME"], 3),
        goals["AWAY"] if final_away is None else final_away,
        goals["HOME"] if final_home is None else final_home,
    ])
    return points


def _big_play(shot: Mapping[str, Any]) -> dict[str, Any]:
    period = _int(shot.get("period")) or 1
    player = _num(shot.get("shooterPlayerId"))
    name = shot.get("shooterName")
    return {
        "period": period,
        "clock": clock_text(shot.get("time"), period),
        "team": normalize_team(shot.get("teamCode")),
        "description": shot_description(shot),
        "xg": _round(_num(shot.get("xGoal")), 3),
        "result": "GOAL" if _flag(shot.get("goal")) else RESULTS.get(str(shot.get("event")).upper(), "MISS"),
        "player_id": None if player is None else int(player),
        "shooter": name if isinstance(name, str) and name else None,
        "_time": _int(shot.get("time")),
    }


def big_plays(shots: pd.DataFrame) -> list[dict[str, Any]]:
    """Every goal plus the five highest-xG non-goals, in game order."""
    records = shots.to_dict("records")
    goals = [s for s in records if _flag(s.get("goal"))]
    others = sorted(
        (s for s in records if not _flag(s.get("goal"))),
        key=lambda s: (-(_num(s.get("xGoal")) or 0.0), _int(s.get("time"))),
    )[:BIG_PLAY_NON_GOALS]
    plays = sorted((_big_play(s) for s in goals + others), key=lambda p: p["_time"])
    for play in plays:
        del play["_time"]
    return plays


# --------------------------------------------------------------------------- #
# Team stats
# --------------------------------------------------------------------------- #
def team_shot_totals(shots: pd.DataFrame) -> dict[str, dict[str, float]]:
    """Per side: xG, 5v5 xG, attempts, high-danger chances, goals and shots on goal."""
    if shots.empty:
        zero = dict.fromkeys(
            ("xg", "xg_5v5", "attempts", "attempts_5v5", "hd", "goals", "sog"), 0.0
        )
        return {"AWAY": dict(zero), "HOME": dict(zero)}
    even = (
        (shots["homeSkatersOnIce"] == EVEN_STRENGTH_SKATERS)
        & (shots["awaySkatersOnIce"] == EVEN_STRENGTH_SKATERS)
        & (shots["homeEmptyNet"].fillna(0) == 0)
        & (shots["awayEmptyNet"].fillna(0) == 0)
    )
    totals: dict[str, dict[str, float]] = {}
    for side in ("AWAY", "HOME"):
        mine = shots["team"].astype(str).str.upper() == side
        xg = shots["xGoal"].fillna(0.0)
        totals[side] = {
            "xg": float(xg[mine].sum()),
            "xg_5v5": float(xg[mine & even].sum()),
            "attempts": float(mine.sum()),
            "attempts_5v5": float((mine & even).sum()),
            "hd": float(((xg >= HIGH_DANGER_XG) & mine).sum()),
            "goals": float(shots["goal"].fillna(0)[mine].sum()),
            "sog": float(shots["shotWasOnGoal"].fillna(0)[mine].sum()),
        }
    return totals


def blocked_attempts(pbp: Optional[Mapping[str, Any]]) -> dict[str, dict[str, int]]:
    """Blocked shot attempts by the shooting team: all strengths and 5v5.

    The play-by-play ``eventOwnerTeamId`` of a blocked shot is the shooter's
    team. Situation ``1551`` is five skaters and a goalie a side.
    """
    counts = {"HOME": {"all": 0, "5v5": 0}, "AWAY": {"all": 0, "5v5": 0}}
    if not pbp:
        return counts
    home_id = (pbp.get("homeTeam") or {}).get("id")
    for play in pbp.get("plays") or []:
        if play.get("typeDescKey") != "blocked-shot":
            continue
        side = "HOME" if (play.get("details") or {}).get("eventOwnerTeamId") == home_id else "AWAY"
        counts[side]["all"] += 1
        if str(play.get("situationCode")) == "1551":
            counts[side]["5v5"] += 1
    return counts


def parse_rail(rail: Optional[Mapping[str, Any]]) -> dict[str, dict[str, Optional[int]]]:
    """Team totals from the right-rail ``teamGameStats`` list, per side."""
    stats = {c.get("category"): c for c in (rail or {}).get("teamGameStats") or []}
    out: dict[str, dict[str, Optional[int]]] = {}
    for side, column in (("AWAY", "awayValue"), ("HOME", "homeValue")):
        wins, total = _ratio((stats.get("faceoffWins") or {}).get(column))
        pp_goals, pp_opportunities = _ratio((stats.get("powerPlay") or {}).get(column))
        out[side] = {
            "faceoff_wins": wins, "faceoff_total": total,
            "pp_goals": pp_goals, "pp_opportunities": pp_opportunities,
            "hits": None if "hits" not in stats else _int(stats["hits"].get(column)),
            "blocks": None if "blockedShots" not in stats else _int(stats["blockedShots"].get(column)),
            "pim": None if "pim" not in stats else _int(stats["pim"].get(column)),
        }
    return out


def _side_players(boxscore: Mapping[str, Any], key: str, groups: Iterable[str]) -> list[Mapping[str, Any]]:
    stats = (boxscore.get("playerByGameStats") or {}).get(key) or {}
    return [p for group in groups for p in stats.get(group) or []]


def boxscore_sums(boxscore: Mapping[str, Any], key: str) -> dict[str, int]:
    """Fallback team totals summed over the boxscore's skaters (goalies add PIM)."""
    skaters = _side_players(boxscore, key, ("forwards", "defense"))
    goalies = _side_players(boxscore, key, ("goalies",))
    return {
        "goals": sum(_int(p.get("goals")) for p in skaters),
        "pp_goals": sum(_int(p.get("powerPlayGoals")) for p in skaters),
        "hits": sum(_int(p.get("hits")) for p in skaters),
        "blocks": sum(_int(p.get("blockedShots")) for p in skaters),
        "pim": sum(_int(p.get("pim")) for p in skaters + goalies),
    }


def team_stats_for_side(
    side: str,
    totals: Mapping[str, Mapping[str, float]],
    blocked: Mapping[str, Mapping[str, int]],
    rail: Mapping[str, Mapping[str, Optional[int]]],
    sums: Mapping[str, int],
    box_sog: Optional[int],
) -> dict[str, Any]:
    """One side's ``team_stats`` entry; rated numbers are still raw floats."""
    other = "HOME" if side == "AWAY" else "AWAY"
    mine, theirs = totals[side], totals[other]
    my_blocked, their_blocked = blocked[side], blocked[other]
    rail_side = rail.get(side, {})
    xg = round(mine["xg"], 3)
    goals = sums["goals"] if sums["goals"] else int(mine["goals"])
    faceoff = _share(rail_side.get("faceoff_wins") or 0, rail_side.get("faceoff_total") or 0)
    cf_for = mine["attempts_5v5"] + my_blocked["5v5"]
    cf_against = theirs["attempts_5v5"] + their_blocked["5v5"]

    def pick(key: str) -> int:
        value = rail_side.get(key)
        return sums[key] if value is None else value

    return {
        "xg": xg,
        "xg_5v5": round(mine["xg_5v5"], 3),
        "xgf_pct_5v5": _share(mine["xg_5v5"], mine["xg_5v5"] + theirs["xg_5v5"]),
        "cf_pct_5v5": _share(cf_for, cf_for + cf_against),
        "hd_chances": int(mine["hd"]),
        "sog": int(mine["sog"]) if box_sog is None else box_sog,
        "shot_attempts": int(mine["attempts"]) + my_blocked["all"],
        "goals": goals,
        "gax": round(goals - xg, 3),
        "pp_goals": pick("pp_goals"),
        "pp_opportunities": rail_side.get("pp_opportunities"),
        "faceoff_pct": faceoff,
        "hits": pick("hits"),
        "blocks": pick("blocks"),
        "pim": pick("pim"),
    }


# --------------------------------------------------------------------------- #
# Player lines
# --------------------------------------------------------------------------- #
def player_names(boxscore: Mapping[str, Any], pbp: Optional[Mapping[str, Any]]) -> dict[int, str]:
    """Full names from the play-by-play roster, boxscore initials as the fallback."""
    names: dict[int, str] = {}
    for key in ("awayTeam", "homeTeam"):
        for player in _side_players(boxscore, key, ("forwards", "defense", "goalies")):
            default = (player.get("name") or {}).get("default")
            if default:
                names[int(player["playerId"])] = str(default)
    for spot in (pbp or {}).get("rosterSpots") or []:
        first = (spot.get("firstName") or {}).get("default")
        last = (spot.get("lastName") or {}).get("default")
        if first and last and spot.get("playerId"):
            names[int(spot["playerId"])] = f"{first} {last}"
    return names


def skater_line(
    player: Mapping[str, Any],
    team: str,
    shots: Mapping[str, float],
    play: Mapping[str, int],
    names: Mapping[int, str],
) -> Optional[dict[str, Any]]:
    seconds = toi_seconds(player.get("toi"))
    if seconds <= 0:
        return None
    pid = int(player["playerId"])
    goals = _int(player.get("goals"))
    ixg = float(shots.get("ixg", 0.0))
    return {
        "role": "skater",
        "player_id": pid,
        "name": names.get(pid),
        "team": team,
        "position": player.get("position"),
        "toi": seconds,
        "goals": goals,
        "assists": _int(player.get("assists")),
        "points": _int(player.get("points")),
        "sog": _int(player.get("sog")),
        "shot_attempts": int(shots.get("attempts", 0)) + int(play.get("blocked_attempts", 0)),
        "hd_shots": int(shots.get("hd", 0)),
        "ixg": round(ixg, 3),
        "gax": round(goals - ixg, 3),
        "ixg_per_60": round(ixg * 3600 / seconds, 3),
    }


def goalie_line(
    player: Mapping[str, Any],
    team: str,
    shots: Mapping[str, float],
    names: Mapping[int, str],
) -> Optional[dict[str, Any]]:
    seconds = toi_seconds(player.get("toi"))
    if seconds <= 0:
        return None
    pid = int(player["playerId"])
    against = _int(player.get("goalsAgainst"))
    faced = _int(player.get("shotsAgainst"))
    saves = _int(player.get("saves"))
    xga = float(shots.get("xga", 0.0))
    return {
        "role": "goalie",
        "player_id": pid,
        "name": names.get(pid),
        "team": team,
        "position": "G",
        "toi": seconds,
        "shots_against": faced,
        "saves": saves,
        "goals_against": against,
        "xga": round(xga, 3),
        "gsax": round(xga - against, 3),
        "sv_pct": _share(saves, faced),
    }


def player_lines(
    boxscore: Mapping[str, Any],
    teams: Mapping[str, str],
    short: int,
    tables: ShotTables,
    pbp_stats: Mapping[int, Mapping[str, int]],
    names: Mapping[int, str],
) -> list[dict[str, Any]]:
    lines: list[Optional[dict[str, Any]]] = []
    for key, team in (("awayTeam", teams["AWAY"]), ("homeTeam", teams["HOME"])):
        for player in _side_players(boxscore, key, ("forwards", "defense")):
            pid = int(player["playerId"])
            lines.append(skater_line(
                player, team, tables.skaters.get((short, pid), {}), pbp_stats.get(pid, {}), names
            ))
        for player in _side_players(boxscore, key, ("goalies",)):
            lines.append(goalie_line(
                player, team, tables.goalies.get((short, int(player["playerId"])), {}), names
            ))
    return [line for line in lines if line is not None]


# --------------------------------------------------------------------------- #
# One game
# --------------------------------------------------------------------------- #
def build_game_row(
    game: Mapping[str, Any],
    shots: pd.DataFrame,
    tables: ShotTables,
    boxscore: Mapping[str, Any],
    pbp: Optional[Mapping[str, Any]],
    rail: Optional[Mapping[str, Any]],
    now: datetime,
) -> dict[str, Any]:
    """The ``game_details`` row for one final game, rated numbers still raw."""
    teams = {"AWAY": game["away_team"], "HOME": game["home_team"]}
    ordered = ordered_shots(shots)
    totals = team_shot_totals(ordered)
    blocked = blocked_attempts(pbp)
    rail_sides = parse_rail(rail)
    last_shot = float(ordered["time"].max()) if not ordered.empty else 0.0
    team_stats = {
        side.lower(): team_stats_for_side(
            side, totals, blocked, rail_sides,
            boxscore_sums(boxscore, f"{side.lower()}Team"),
            _int((boxscore.get(f"{side.lower()}Team") or {}).get("sog")) or None,
        )
        for side in ("AWAY", "HOME")
    }
    names = player_names(boxscore, pbp)
    players = player_lines(
        boxscore, teams, short_game_id(game["game_id"]), tables,
        parse_play_by_play(pbp or {}), names,
    )
    return {
        "game_id": str(game["game_id"]),
        "season": int(game["season"]),
        "season_type": game["season_type"],
        "week": int(game["week"]),
        "away_team": game["away_team"],
        "home_team": game["home_team"],
        "team_stats": team_stats,
        "players": players,
        "win_probability": xg_race(
            ordered, game.get("away_score"), game.get("home_score"),
            game_end_seconds(boxscore, last_shot),
        ),
        "big_plays": big_plays(ordered),
        "updated_at": now.isoformat(),
    }


# --------------------------------------------------------------------------- #
# Percentiles
# --------------------------------------------------------------------------- #
def _unwrap(value: Any) -> Any:
    """The number inside a rated ``{value, pct}`` entry, or a plain number."""
    return value.get("value") if isinstance(value, dict) else value


def attach_percentiles(
    rows: list[dict[str, Any]],
    metrics: Iterable[tuple[str, bool]],
    eligible: Any = lambda row: True,
) -> None:
    """Replace each metric with ``{"value", "pct"}`` ranked across ``rows``.

    Rows may already hold rated entries (a re-rank from stored values). Only
    eligible rows enter the pool and receive a percentile; the others keep
    their value with a null ``pct``. A tie takes the midpoint of its block.
    """
    for key, higher in metrics:
        pool = np.sort(np.array(
            [v for r in rows if eligible(r) and (v := _num(_unwrap(r.get(key)))) is not None],
            dtype=float,
        ))
        for row in rows:
            value = _unwrap(row.get(key))
            if _num(value) is None:
                row[key] = None
                continue
            pct = None
            if eligible(row) and len(pool) > 1:
                left = int(np.searchsorted(pool, float(value), side="left"))
                right = int(np.searchsorted(pool, float(value), side="right"))
                below = left if higher else len(pool) - right
                score = (below + (right - left) / 2) / len(pool) * 100
                pct = max(1, min(100, int(math.floor(score + 0.5))))
            row[key] = {"value": value, "pct": pct}


def rate_games(games: Iterable[dict[str, Any]]) -> None:
    """Rank team games and player games, REG and POST separately, in place."""
    by_phase: dict[str, list[dict[str, Any]]] = {}
    for game in games:
        by_phase.setdefault(game["season_type"], []).append(game)
    for phase_games in by_phase.values():
        teams = [side for g in phase_games for side in (g["team_stats"]["away"], g["team_stats"]["home"])]
        players = [p for g in phase_games for p in g["players"]]
        skaters = [p for p in players if p["role"] == "skater"]
        goalies = [p for p in players if p["role"] == "goalie"]
        attach_percentiles(teams, TEAM_METRICS)
        attach_percentiles(skaters, SKATER_METRICS, lambda r: r["toi"] >= MIN_SKATER_SECONDS)
        attach_percentiles(goalies, GOALIE_METRICS, lambda r: r["toi"] >= MIN_GOALIE_SECONDS)


# --------------------------------------------------------------------------- #
# Network and database
# --------------------------------------------------------------------------- #
def fetch_stored_rows(client: Any, season: int) -> dict[str, dict[str, Any]]:
    """Every ``game_details`` row of the season, keyed by game id."""
    rows: dict[str, dict[str, Any]] = {}
    offset = 0
    while True:
        page = (
            client.table("game_details").select("*").eq("season", season)
            .order("game_id").range(offset, offset + STORED_PAGE - 1).execute().data
        ) or []
        rows.update({r["game_id"]: r for r in page})
        if len(page) < STORED_PAGE:
            return rows
        offset += STORED_PAGE


def fetch_payloads(game_id: str, live: bool) -> Optional[tuple[Any, Any, Any]]:
    """Boxscore, play-by-play and right-rail for one game; None when it is not ready."""
    try:
        boxscore = fetch_gamecenter(game_id, "boxscore", cache=not live)
        pbp = fetch_gamecenter(game_id, "play-by-play", cache=not live)
        rail = fetch_gamecenter(game_id, "right-rail", cache=not live)
    except Exception:  # noqa: BLE001 - one bad game must not stop the rest
        logger.exception("NHL payloads failed for %s", game_id)
        return None
    return (boxscore, pbp, rail) if boxscore and pbp else None


def build_new_games(
    games: list[Mapping[str, Any]],
    frame: pd.DataFrame,
    tables: ShotTables,
    live: bool,
    now: datetime,
) -> tuple[list[dict[str, Any]], list[str]]:
    """Rows for the games whose shot data and NHL payloads are ready, plus the rest."""
    by_game = {int(g): rows for g, rows in frame.groupby("game_id")}
    built: list[dict[str, Any]] = []
    pending: list[str] = []
    ready = []
    for game in games:
        if short_game_id(game["game_id"]) in by_game:
            ready.append(game)
        else:
            pending.append(str(game["game_id"]))
    with ThreadPoolExecutor(max_workers=FETCH_WORKERS) as pool:
        for start in range(0, len(ready), FETCH_CHUNK):
            chunk = ready[start:start + FETCH_CHUNK]
            fetched = pool.map(lambda g: fetch_payloads(str(g["game_id"]), live), chunk)
            for game, payloads in zip(chunk, fetched):
                if payloads is None:
                    pending.append(str(game["game_id"]))
                    continue
                boxscore, pbp, rail = payloads
                shots = by_game[short_game_id(game["game_id"])]
                built.append(build_game_row(game, shots, tables, boxscore, pbp, rail, now))
            logger.info("  %d/%d games built", len(built), len(games))
    return built, pending


def changed_rows(
    stored: Mapping[str, dict[str, Any]], before: Mapping[str, str]
) -> list[dict[str, Any]]:
    """Stored rows whose team or player ranks differ from before the re-rank."""
    return [row for game_id, row in stored.items() if _signature(row) != before[game_id]]


def _signature(row: Mapping[str, Any]) -> str:
    return json.dumps([row["team_stats"], row["players"]], sort_keys=True)


def upsert(client: Any, rows: list[dict[str, Any]]) -> None:
    for batch in chunks(rows, UPSERT_BATCH):
        client.table("game_details").upsert(batch, on_conflict="game_id").execute()


def run(full: bool = False, cli_season: Optional[int] = None, dry_run: bool = False) -> int:
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        return 1
    client = create_client(url, key)
    season = resolve_season(cli_season)
    live = season >= DEFAULT_SEASON
    now = datetime.now(UTC)

    finals = fetch_final_games(client, season)
    if not finals:
        logger.info("No final games in public.games for %s; run sync_games.py first.", season)
        return 0
    stored = fetch_stored_rows(client, season)
    todo = finals if full else [g for g in finals if str(g["game_id"]) not in stored]
    logger.info("%s: %d finals, %d stored, %d to build%s", season, len(finals), len(stored), len(todo),
                " (full)" if full else "")

    built: list[dict[str, Any]] = []
    pending: list[str] = []
    if todo:
        frame = load_shots_frame(season, live, SHOT_FIELDS)
        if frame is None:
            logger.warning("No MoneyPuck shot file for %s yet.", season)
            pending = [str(g["game_id"]) for g in todo]
        else:
            built, pending = build_new_games(todo, frame, build_shot_tables(frame), live, now)
    fresh = {row["game_id"]: row for row in built}
    kept = {gid: row for gid, row in stored.items() if gid not in fresh}
    before = {gid: _signature(row) for gid, row in kept.items()}
    rate_games(list(fresh.values()) + list(kept.values()))
    rewrite = changed_rows(kept, before)
    for row in rewrite:
        row["updated_at"] = now.isoformat()
    logger.info("Built %d games (%d pending), re-ranked %d stored rows", len(built), len(pending), len(rewrite))
    if dry_run:
        return 0
    upsert(client, list(fresh.values()) + rewrite)
    return 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="Rebuild every final of the season.")
    parser.add_argument("--season", type=int, default=None, help="Season (starting year).")
    parser.add_argument("--dry-run", action="store_true", help="Build but do not write.")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    args = _parse_args()
    sys.exit(run(full=args.full, cli_season=args.season, dry_run=args.dry_run))
