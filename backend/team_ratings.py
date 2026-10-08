"""
Team power ratings in goals per game against an average team.

"Three things you do, minus the same things you allow, adjusted for who you
played", the shape of Brian Nemhauser's HB Power Rankings carried over from the
football chassis. Offense is what a club creates and defense is what it
allows, each measured against the league and put on a goals-per-game scale:

* Expected goals: MoneyPuck's xGoal summed over a club's unblocked attempts
  for and against (the shot file), per 60 minutes.
* Goals: the scoreboard, per 60 minutes. A shootout is decided by one extra
  goal that is not scoring, so a shootout game counts its regulation and
  overtime goals (the shot file's), tied. Records and the stored goal totals
  keep the official scores.

Per club and game, rates are ``value * 3600 / game_seconds`` (3600 in
regulation, the length actually played in overtime, 3900 for a shootout), then
averaged over the club's games.

    offense = 0.5 * (xGF/60 - league) + 0.5 * (GF/60 - league)
    defense = 0.5 * (league - xGA/60) + 0.5 * (league - GA/60)
    rating  = offense + defense

so +0.5 means half a goal a game better than the average club. Offense and
defense are then adjusted for schedule the Simple Rating System way (an
offense that faced good defenses is credited for it, and the reverse), which
is iterated until it settles and re-centred on zero each pass.

Constants:

* ``XG_WEIGHT`` 0.5: xG and goals share the rating equally. Goals are the
  result but noisy, xG is the process but misses finishing and goaltending.
* ``FULL_SOS_GAMES`` 20: the schedule adjustment starts at zero after one game
  a club and is complete from the 20th (the median club's games). A few games
  say little about who was strong, and the NHL's schedule is balanced enough
  that the adjustment matters less than it does in football.
* ``CURRENT_SHRINK`` 0.8: this season's descriptive rating overstates what it
  predicts, so it is shrunk 20% toward average before it is blended.
* ``PRIOR_GAMES`` 20: last season counts as this many games of evidence. Its
  weight is 20 / (games + 20): all of it before a puck drops, half after 20
  games, a fifth after 82.
* ``PRIOR_REGRESSION`` 0.5: last season's rating is regressed halfway to
  average first, since rosters turn over.
* ``HOME_ICE`` 0.2 goals: the home edge in the margin.
* ``MARGIN_SCALE`` 0.9: ``home_win_prob = 1 / (1 + exp(-margin / 0.9))``, so a
  one-goal edge is a 75/25 game (1 / (1 + e^-1.11) = 0.75), which matches the
  NHL's historical margin-to-win curve. An even matchup is 0.2 goals for the
  home side, about 55/45.

So the number reads like a goal line: +0.4 against -0.2 on neutral ice is a
0.6 goal favourite, and home ice is worth a fifth of a goal.

Pure functions; no network. ``ingest_enrichment.py`` feeds them.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

import pandas as pd

from ingest_game_logs import short_game_id

HOME_ICE = 0.2
MARGIN_SCALE = 0.9
XG_WEIGHT = 0.5
FULL_SOS_GAMES = 20
PRIOR_GAMES = 20.0
PRIOR_REGRESSION = 0.5
CURRENT_SHRINK = 0.8
SOS_ITERATIONS = 60

REGULATION_SECONDS = 3600
SHOOTOUT_SECONDS = 3900


@dataclass
class TeamRating:
    team: str
    games: int
    rating: float
    offense: float
    defense: float
    schedule: float
    prior_weight: float
    goals_for: float
    goals_against: float
    wins: int
    losses: int
    otl: int


def game_shot_totals(shots: pd.DataFrame) -> pd.DataFrame:
    """Per shot-file game: xG and goals by side, and when the last goal fell.

    Index = shot-file game id; columns ``away_xg``, ``home_xg``, ``away_goals``,
    ``home_goals``, ``last_goal`` (game second of the final goal, 0 if none).
    """
    if shots is None or shots.empty:
        return pd.DataFrame(
            columns=["away_xg", "home_xg", "away_goals", "home_goals", "last_goal"]
        )
    frame = shots.assign(
        side=shots["team"].astype(str).str.upper(),
        goal=shots["goal"].fillna(0),
        xGoal=shots["xGoal"].fillna(0.0),
    )
    sums = frame.groupby(["game_id", "side"]).agg(xg=("xGoal", "sum"), goals=("goal", "sum")).unstack("side")
    sums = sums.reindex(columns=pd.MultiIndex.from_product([["xg", "goals"], ["AWAY", "HOME"]])).fillna(0.0)
    last = frame[frame["goal"] == 1].groupby("game_id")["time"].max()
    out = pd.DataFrame({
        "away_xg": sums[("xg", "AWAY")], "home_xg": sums[("xg", "HOME")],
        "away_goals": sums[("goals", "AWAY")], "home_goals": sums[("goals", "HOME")],
    })
    out["last_goal"] = last.reindex(out.index).fillna(0.0)
    return out


def game_seconds(overtime: bool, shootout: bool, last_goal: float) -> float:
    """Minutes actually played, in seconds: the divisor for a per-60 rate."""
    if not overtime:
        return float(REGULATION_SECONDS)
    if shootout or last_goal <= REGULATION_SECONDS:
        return float(SHOOTOUT_SECONDS)
    return float(min(last_goal, SHOOTOUT_SECONDS))


def team_game_rows(games: pd.DataFrame, totals: pd.DataFrame) -> pd.DataFrame:
    """One row per club per completed regular-season game with shot data.

    ``games`` is the ``public.games`` frame (``game_id``, ``week``, ``home_team``,
    ``away_team``, ``home_score``, ``away_score``, ``overtime``); a final that
    the shot file does not hold yet is skipped until it does.
    """
    if games.empty or totals.empty:
        return pd.DataFrame()
    done = games[games["home_score"].notna() & games["away_score"].notna()]
    rows: list[dict[str, object]] = []
    for game in done.itertuples(index=False):
        short = short_game_id(game.game_id)
        if short not in totals.index:
            continue
        shots = totals.loc[short]
        overtime = bool(game.overtime)
        shootout = overtime and shots["home_goals"] == shots["away_goals"]
        seconds = game_seconds(overtime, shootout, float(shots["last_goal"]))
        for side, team, opponent, home in (("home", game.home_team, game.away_team, True),
                                           ("away", game.away_team, game.home_team, False)):
            other = "away" if side == "home" else "home"
            score_for = float(game.home_score if home else game.away_score)
            score_against = float(game.away_score if home else game.home_score)
            rows.append({
                "game_id": str(game.game_id),
                "week": int(game.week),
                "team": team,
                "opponent": opponent,
                "home": home,
                "overtime": overtime,
                "seconds": seconds,
                "score_for": score_for,
                "score_against": score_against,
                "goals_for": float(shots[f"{side}_goals"]) if shootout else score_for,
                "goals_against": float(shots[f"{other}_goals"]) if shootout else score_against,
                "xg_for": float(shots[f"{side}_xg"]),
                "xg_against": float(shots[f"{other}_xg"]),
            })
    return pd.DataFrame(rows)


def sos_weight(games: float) -> float:
    """Zero after one game a club, complete from the ``FULL_SOS_GAMES``th."""
    return max(0.0, min(1.0, (games - 1) / (FULL_SOS_GAMES - 1)))


def prior_weight(games: int) -> float:
    """Last season's share of the rating: all of it before a puck drops."""
    return PRIOR_GAMES / (max(games, 0) + PRIOR_GAMES)


def _per_60(frame: pd.DataFrame, column: str) -> pd.Series:
    return frame[column] * 3600 / frame["seconds"]


def rate(
    rows: pd.DataFrame,
    prior: Optional[dict[str, TeamRating]] = None,
    full_schedule_weight: bool = False,
) -> dict[str, TeamRating]:
    """Ratings from every game in ``rows``, blended with ``prior`` when given."""
    if rows.empty:
        return {}
    data = rows.assign(
        xgf60=_per_60(rows, "xg_for"), xga60=_per_60(rows, "xg_against"),
        gf60=_per_60(rows, "goals_for"), ga60=_per_60(rows, "goals_against"),
    )
    league_xg = data["xgf60"].mean()
    league_goals = data["gf60"].mean()

    raw_off: dict[str, float] = {}
    raw_def: dict[str, float] = {}
    games: dict[str, int] = {}
    opponents: dict[str, list[str]] = {}
    summary: dict[str, dict[str, float]] = {}
    for team, g in data.groupby("team"):
        raw_off[team] = (
            XG_WEIGHT * (g["xgf60"].mean() - league_xg)
            + (1 - XG_WEIGHT) * (g["gf60"].mean() - league_goals)
        )
        raw_def[team] = (
            XG_WEIGHT * (league_xg - g["xga60"].mean())
            + (1 - XG_WEIGHT) * (league_goals - g["ga60"].mean())
        )
        games[team] = int(len(g))
        opponents[team] = list(g["opponent"])
        margin = g["score_for"] - g["score_against"]
        summary[team] = {
            "gf": float(g["score_for"].sum()),
            "ga": float(g["score_against"].sum()),
            "w": int((margin > 0).sum()),
            "l": int(((margin < 0) & ~g["overtime"]).sum()),
            "otl": int(((margin < 0) & g["overtime"]).sum()),
        }

    weight = 1.0 if full_schedule_weight else sos_weight(float(pd.Series(games).median()))
    off = dict(raw_off)
    dfn = dict(raw_def)
    for _ in range(SOS_ITERATIONS):
        next_off = {t: raw_off[t] + weight * _mean([dfn.get(o, 0.0) for o in opponents[t]]) for t in raw_off}
        next_def = {t: raw_def[t] + weight * _mean([off.get(o, 0.0) for o in opponents[t]]) for t in raw_def}
        # Keep the league centred on zero so the numbers stay a goal line.
        off = _centre(next_off)
        dfn = _centre(next_def)

    out: dict[str, TeamRating] = {}
    for team in raw_off:
        base = prior.get(team) if prior else None
        # With no prior (last season's own final rating) the rating is the
        # plain descriptive one.
        pw = prior_weight(games[team]) if base else 0.0
        shrink = CURRENT_SHRINK if base else 1.0
        prior_off = base.offense * PRIOR_REGRESSION if base else 0.0
        prior_def = base.defense * PRIOR_REGRESSION if base else 0.0
        blended_off = (1 - pw) * shrink * off[team] + pw * prior_off
        blended_def = (1 - pw) * shrink * dfn[team] + pw * prior_def
        s = summary[team]
        out[team] = TeamRating(
            team=team,
            games=games[team],
            rating=blended_off + blended_def,
            offense=blended_off,
            defense=blended_def,
            schedule=(off[team] - raw_off[team]) + (dfn[team] - raw_def[team]),
            prior_weight=pw,
            goals_for=s["gf"],
            goals_against=s["ga"],
            wins=s["w"],
            losses=s["l"],
            otl=s["otl"],
        )
    return out


def average_club(team: str) -> TeamRating:
    """A club with no history: exactly average, all weight on the (empty) prior."""
    return TeamRating(team, 0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0, 0, 0)


def preseason(prior: dict[str, TeamRating]) -> dict[str, TeamRating]:
    """Before a puck drops: last season, regressed."""
    return {
        team: TeamRating(
            team=team, games=0,
            rating=(r.offense + r.defense) * PRIOR_REGRESSION,
            offense=r.offense * PRIOR_REGRESSION,
            defense=r.defense * PRIOR_REGRESSION,
            schedule=0.0, prior_weight=1.0,
            goals_for=0.0, goals_against=0.0, wins=0, losses=0, otl=0,
        )
        for team, r in prior.items()
    }


def project(home: TeamRating, away: TeamRating, neutral: bool = False) -> tuple[float, float]:
    """(home margin in goals, home win probability)."""
    margin = home.rating - away.rating + (0.0 if neutral else HOME_ICE)
    return margin, 1 / (1 + math.exp(-margin / MARGIN_SCALE))


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _centre(values: dict[str, float]) -> dict[str, float]:
    mean = _mean(list(values.values()))
    return {k: v - mean for k, v in values.items()}
