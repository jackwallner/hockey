"""
Team power ratings in points per game against an average team.

Modelled on Brian Nemhauser's HB Power Rankings (hawkblogger.com): "three things
you do, minus the same three things you allow, adjusted for who you played".
Here the three are dropback EPA (sacks and scrambles included, the reason HB
moved from passer rating to ANY/A), rush EPA and points, each measured relative
to the league and put on a points-per-game scale:

* Efficiency: a club's EPA per dropback and per designed run, mixed at the
  league's own pass/run split (so a team is not rewarded or punished for the
  game script it found itself in), times the league's plays per game.
* Scoreboard: points scored and allowed per game.

Offense and defense are rated separately, then adjusted for schedule the
Simple Rating System way (an offense that faced good defenses is credited for
it, and vice versa). As in HB's 2026 formula the schedule adjustment starts at
zero and reaches full weight by Week 10.

Where this departs from HB is the anchoring. His fixed third-of-last-season,
gone by Week 9, overstated early-season gaps when backtested: a straight
descriptive rating predicted margins with a slope of about 0.55, so a
"ten-point favourite" won by five. Instead this season's rating is shrunk 20%
and blended with last season's (itself regressed halfway to average) as if
last season were worth five games. That is a third of the weight after ten
games and a fifth at the end. Backtested on every 2022-2025 regular-season
game using only data from before kickoff: correlation with the final margin
0.374 (HB reports 0.34; the closing Vegas line is 0.46), mean absolute error
10.0 points (Vegas 9.5), calibration slope 0.88.

So the number reads like a point spread: +7 against -3 on a neutral field is a
ten-point favourite, and home field is worth about two points.

Pure functions; no network. ``ingest_enrichment.py`` feeds them.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Optional

import pandas as pd

HOME_FIELD = 2.0
# Standard deviation of NFL final margins around the spread, for turning a
# projected margin into a win probability.
MARGIN_SIGMA = 13.5
FULL_SOS_WEEK = 10
# Last season counts as this many games of evidence about this one.
PRIOR_GAMES = 5.0
# Last season's rating is regressed toward average before it anchors this one:
# rosters turn over, and a +9 team rarely starts the next year at +9.
PRIOR_REGRESSION = 0.5
# This season's descriptive rating overstates what it predicts.
CURRENT_SHRINK = 0.8
EFFICIENCY_WEIGHT = 0.6
SOS_ITERATIONS = 60


@dataclass
class TeamRating:
    team: str
    games: int
    rating: float
    offense: float
    defense: float
    schedule: float
    prior_weight: float
    points_for: float
    points_against: float
    wins: int
    losses: int
    ties: int


def team_game_rows(pbp: pd.DataFrame, schedule: pd.DataFrame) -> pd.DataFrame:
    """One row per club per completed regular-season game.

    ``schedule`` supplies the final score and site (a neutral-site game has no
    home field); ``pbp`` supplies each offense's EPA. A game with a final score
    but no play-by-play yet still counts on the scoreboard side.
    """
    sched = schedule[
        (schedule["game_type"] == "REG")
        & schedule["home_score"].notna()
        & schedule["away_score"].notna()
    ]
    if sched.empty:
        return pd.DataFrame()

    epa = _offense_epa(pbp)
    rows: list[dict[str, Any]] = []
    for game in sched.itertuples(index=False):
        for team, opponent, pf, pa, home in (
            (game.home_team, game.away_team, game.home_score, game.away_score, True),
            (game.away_team, game.home_team, game.away_score, game.home_score, False),
        ):
            mine = epa.get((game.game_id, team), {})
            theirs = epa.get((game.game_id, opponent), {})
            rows.append({
                "game_id": game.game_id,
                "season": int(game.season),
                "week": int(game.week),
                "team": team,
                "opponent": opponent,
                "home": home,
                "points_for": float(pf),
                "points_against": float(pa),
                "off_db_epa": mine.get("db_epa", 0.0),
                "off_db": mine.get("db", 0),
                "off_rush_epa": mine.get("rush_epa", 0.0),
                "off_rush": mine.get("rush", 0),
                "def_db_epa": theirs.get("db_epa", 0.0),
                "def_db": theirs.get("db", 0),
                "def_rush_epa": theirs.get("rush_epa", 0.0),
                "def_rush": theirs.get("rush", 0),
            })
    return pd.DataFrame(rows)


def _offense_epa(pbp: pd.DataFrame) -> dict[tuple[str, str], dict[str, float]]:
    if pbp is None or pbp.empty:
        return {}
    plays = pbp[
        pbp["posteam"].notna()
        & pbp["epa"].notna()
        & ((pbp["pass"] == 1) | (pbp["rush"] == 1))
        & pbp["play_type"].isin(["pass", "run"])
    ]
    if "season_type" in plays.columns:
        plays = plays[plays["season_type"] == "REG"]
    dropback = plays["qb_dropback"] == 1
    out: dict[tuple[str, str], dict[str, float]] = {}
    for (game_id, team), group in plays.groupby(["game_id", "posteam"]):
        db = group[dropback.loc[group.index]]
        rush = group[(group["rush"] == 1) & ~dropback.loc[group.index]]
        out[(str(game_id), str(team))] = {
            "db_epa": float(db["epa"].sum()),
            "db": int(len(db)),
            "rush_epa": float(rush["epa"].sum()),
            "rush": int(len(rush)),
        }
    return out


def sos_weight(week: int) -> float:
    """Zero after Week 1, full from Week 10: early schedules say little."""
    return max(0.0, min(1.0, (week - 1) / (FULL_SOS_WEEK - 1)))


def prior_weight(games: int) -> float:
    """Last season's share of the rating: all of it before a snap, a third
    after ten games, a fifth after seventeen."""
    return PRIOR_GAMES / (max(games, 0) + PRIOR_GAMES)


def rate(
    rows: pd.DataFrame,
    through_week: Optional[int] = None,
    prior: Optional[dict[str, TeamRating]] = None,
    full_schedule_weight: bool = False,
) -> dict[str, TeamRating]:
    """Ratings from every game up to and including ``through_week``."""
    if rows.empty:
        return {}
    data = rows if through_week is None else rows[rows["week"] <= through_week]
    if data.empty:
        return {}
    week = int(data["week"].max())

    total_db = data["off_db"].sum()
    total_rush = data["off_rush"].sum()
    team_games = len(data)
    pass_mix = total_db / (total_db + total_rush) if total_db + total_rush else 0.58
    plays_pg = (total_db + total_rush) / team_games if team_games else 63.0
    league_db = data["off_db_epa"].sum() / total_db if total_db else 0.0
    league_rush = data["off_rush_epa"].sum() / total_rush if total_rush else 0.0
    league_points = data["points_for"].mean()
    # No play-by-play at all (a late or failed download): rate on the
    # scoreboard alone rather than diluting it with a flat zero.
    efficiency_weight = EFFICIENCY_WEIGHT if total_db + total_rush else 0.0

    def per_play(epa_sum: float, n: float, league: float) -> float:
        # A club with no plays of a kind (a score posted before its pbp) sits
        # at the league rate rather than at zero EPA.
        return epa_sum / n if n else league

    raw_off: dict[str, float] = {}
    raw_def: dict[str, float] = {}
    games: dict[str, int] = {}
    opponents: dict[str, list[str]] = {}
    summary: dict[str, dict[str, float]] = {}
    for team, g in data.groupby("team"):
        off_eff = (
            pass_mix * (per_play(g["off_db_epa"].sum(), g["off_db"].sum(), league_db) - league_db)
            + (1 - pass_mix) * (per_play(g["off_rush_epa"].sum(), g["off_rush"].sum(), league_rush) - league_rush)
        ) * plays_pg
        def_eff = (
            pass_mix * (league_db - per_play(g["def_db_epa"].sum(), g["def_db"].sum(), league_db))
            + (1 - pass_mix) * (league_rush - per_play(g["def_rush_epa"].sum(), g["def_rush"].sum(), league_rush))
        ) * plays_pg
        off_pts = g["points_for"].mean() - league_points
        def_pts = league_points - g["points_against"].mean()
        raw_off[team] = efficiency_weight * off_eff + (1 - efficiency_weight) * off_pts
        raw_def[team] = efficiency_weight * def_eff + (1 - efficiency_weight) * def_pts
        games[team] = int(len(g))
        opponents[team] = list(g["opponent"])
        results = (g["points_for"] - g["points_against"])
        summary[team] = {
            "pf": float(g["points_for"].sum()),
            "pa": float(g["points_against"].sum()),
            "w": int((results > 0).sum()),
            "l": int((results < 0).sum()),
            "t": int((results == 0).sum()),
        }

    weight = 1.0 if full_schedule_weight else sos_weight(week)
    off = dict(raw_off)
    dfn = dict(raw_def)
    for _ in range(SOS_ITERATIONS):
        next_off = {
            t: raw_off[t] + weight * _mean([dfn.get(o, 0.0) for o in opponents[t]])
            for t in raw_off
        }
        next_def = {
            t: raw_def[t] + weight * _mean([off.get(o, 0.0) for o in opponents[t]])
            for t in raw_def
        }
        # Keep the league centred on zero so the numbers stay a point spread.
        off = _centre(next_off)
        dfn = _centre(next_def)

    out: dict[str, TeamRating] = {}
    for team in raw_off:
        base = prior.get(team) if prior else None
        # With no prior (last season's own final rating), the rating is the
        # plain descriptive one.
        pw = prior_weight(games[team]) if base else 0.0
        shrink = CURRENT_SHRINK if base else 1.0
        prior_off = base.offense * PRIOR_REGRESSION if base else 0.0
        prior_def = base.defense * PRIOR_REGRESSION if base else 0.0
        blended_off = (1 - pw) * shrink * off[team] + pw * prior_off
        blended_def = (1 - pw) * shrink * dfn[team] + pw * prior_def
        schedule = (off[team] - raw_off[team]) + (dfn[team] - raw_def[team])
        s = summary[team]
        out[team] = TeamRating(
            team=team,
            games=games[team],
            rating=blended_off + blended_def,
            offense=blended_off,
            defense=blended_def,
            schedule=schedule,
            prior_weight=pw,
            points_for=s["pf"],
            points_against=s["pa"],
            wins=s["w"],
            losses=s["l"],
            ties=s["t"],
        )
    return out


def preseason(prior: dict[str, TeamRating]) -> dict[str, TeamRating]:
    """Before a snap: last season, regressed."""
    return {
        team: TeamRating(
            team=team, games=0,
            rating=(r.offense + r.defense) * PRIOR_REGRESSION,
            offense=r.offense * PRIOR_REGRESSION,
            defense=r.defense * PRIOR_REGRESSION,
            schedule=0.0, prior_weight=1.0,
            points_for=0.0, points_against=0.0, wins=0, losses=0, ties=0,
        )
        for team, r in prior.items()
    }


def project(home: TeamRating, away: TeamRating, neutral: bool = False) -> tuple[float, float]:
    """(home margin, home win probability)."""
    margin = home.rating - away.rating + (0.0 if neutral else HOME_FIELD)
    win = 0.5 * (1 + math.erf(margin / (MARGIN_SIGMA * math.sqrt(2))))
    return margin, win


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _centre(values: dict[str, float]) -> dict[str, float]:
    mean = _mean(list(values.values()))
    return {k: v - mean for k, v in values.items()}
