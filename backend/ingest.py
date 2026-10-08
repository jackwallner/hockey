"""
NFL season-snapshot ingest.

Builds one ``player_snapshots`` row per player per season from the nflverse
data mirror (via ``nflreadpy``), computing within-category percentiles among
qualified players. Powers the iOS player-percentile screens.

Pipeline (REG and POST are stored and ranked separately):
  1. Aggregate weekly ``load_player_stats`` rows to season totals.
  2. Derive rate stats (cmp%, Y/A, sack%, explosive-rush%, CPOE, ...).
  3. Merge season-level Next Gen Stats (time-to-throw, separation, RYOE, ...).
  4. Merge PFR advanced defensive stats (pressures, coverage allowed, ...).
  5. Rank each metric within (season, category) among qualified players.
  6. Upsert to Supabase ``player_snapshots`` on_conflict=(id, season, season_type).

Metric availability is bounded by the sources, not by choice - see the coverage
table in ``handoff/NFL_CONTRACT.md``. In short: EPA and every counting stat run
the full 2000-present range; CPOE starts 2006 (when pbp air-yards tracking
begins); Next Gen Stats start 2016 (2018 for rushing-over-expected); PFR
advanced defence starts 2018; and nflverse's ``targets`` column is blank for
2003-2008, which is detected at runtime rather than hardcoded.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. STATCAST_SEASON overrides the
season; ``--season N`` overrides both.
"""

import argparse
import logging
import math
import os
import sys
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

import nflreadpy as nfl
import numpy as np
import pandas as pd
import polars as pl
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

_now = datetime.now(UTC)
DEFAULT_SEASON = _now.year if _now.month >= 9 else _now.year - 1
MIN_SEASON = 1999
OLDEST_SUPPORTED_SEASON = 2000
NGS_FIRST_SEASON = 2016
# Sentinel season for the career rollup written by rollup_all_time.py. Zero
# rather than a future year so nothing that clamps to a maximum can mistake it
# for a real season; the app renders it as "All Time".
ALL_TIME_SEASON = 0
# Pro-Football-Reference advanced defensive stats (pressures, coverage allowed,
# missed-tackle rate). Regular season only - the PFR season table carries no
# season_type, so there is no postseason split to merge.
PFR_DEF_FIRST_SEASON = 2018
SOURCE = "nflverse"

# Qualification thresholds per metric category (see NFL_CONTRACT.md).
QUAL_ATTEMPTS = 150   # Passing
QUAL_CARRIES = 80     # Rushing
QUAL_TARGETS = 40     # Receiving
QUAL_RECEPTIONS = 25  # Receiving fallback when historical targets are absent
QUAL_GAMES = 8        # Defense (>= 8 games; the contract's OR-branch, snaps not joined)
# Defensive *rate* thresholds. These don't gate whether a defender appears at
# all (games does that) - they gate the individual coverage and tackling rates,
# which are noise at low volume: a corner thrown at twice who allowed one catch
# is not a 50%-completion defender, and ranking him as one would put him
# mid-leaderboard on a two-target sample. Below the threshold the rate is nulled,
# so the player keeps his counting stats and simply isn't ranked on the rate.
QUAL_DEF_TARGETS = 20   # Cmp% / Yds per target / rating allowed / ADOT
QUAL_DEF_TACKLES = 20   # Missed tackle %
POST_QUAL_ATTEMPTS = 20
POST_QUAL_CARRIES = 8
POST_QUAL_TARGETS = 4
POST_QUAL_RECEPTIONS = 3
POST_QUAL_GAMES = 1
# Career thresholds for the all-time rollup, roughly three seasons as a starter.
# The single-season cut is far too low to reuse here: 150 career attempts is one
# month of one year, so an all-time rate board built on it would be topped by
# backups with a hot fortnight rather than by careers.
CAREER_QUAL_ATTEMPTS = 1500
CAREER_QUAL_CARRIES = 500
CAREER_QUAL_TARGETS = 300
CAREER_QUAL_RECEPTIONS = 200
CAREER_QUAL_GAMES = 48
# Career *playoff* thresholds, roughly a handful of postseason starts. A career
# is measured in seasons; a playoff career is measured in games, because nobody
# accumulates a regular season's worth of volume in January. Reusing the numbers
# above here produced a career-playoff board with exactly one qualifying player
# in the league's entire modern history (Brady, on 1,921 attempts), which is a
# hole dressed up as a leaderboard.
CAREER_POST_QUAL_ATTEMPTS = 150
CAREER_POST_QUAL_CARRIES = 60
CAREER_POST_QUAL_TARGETS = 40
CAREER_POST_QUAL_RECEPTIONS = 25
CAREER_POST_QUAL_GAMES = 6
# The single-season thresholds describe a finished season. A season in progress
# is held to the same bar prorated by how much of it has been played, otherwise
# nobody clears 150 attempts in week 1 and the live season has no rows at all
# until mid-October. 16 games a season through 2020, 17 from 2021.
SEVENTEEN_GAME_FIRST_SEASON = 2021


def qualification_scale(agg: pd.DataFrame, season: int) -> float:
    """Fraction of a full regular season played so far, capped at 1.

    Measured as the median club's games played (each club's busiest player).
    It used to be the most games any single player had appeared in, so one
    Thursday night game moved the whole league's bar up a week before thirty
    clubs had played: at 2026 Week 3 that flagged 56% of receiver metrics as
    unqualified overnight. A finished season always scales to 1, so every past
    season keeps exactly the thresholds it was ranked on.
    """
    if agg.empty or "games" not in agg.columns:
        return 1.0
    full = 17 if season >= SEVENTEEN_GAME_FIRST_SEASON else 16
    games = pd.to_numeric(agg["games"], errors="coerce")
    if "team" in agg.columns:
        teams = agg["team"].astype(str).str.strip()
        known = games[(teams != "") & (teams.str.lower() != "nan") & games.notna()]
        per_team = known.groupby(teams[known.index]).max()
        played = float(np.floor(per_team.median())) if not per_team.empty else games.max()
    else:
        played = games.max()
    if pd.isna(played) or played <= 0:
        return 1.0
    return min(1.0, float(played) / full)

# Weekly counting stats summed to season totals.
SUM_COLS = [
    "completions", "attempts", "passing_yards", "passing_tds",
    "passing_interceptions", "sacks_suffered", "passing_air_yards",
    "passing_first_downs", "passing_epa", "rushing_10",
    "carries", "rushing_yards", "rushing_tds", "rushing_first_downs",
    "rushing_epa", "rushing_fumbles",
    "receptions", "targets", "receiving_yards", "receiving_tds",
    "receiving_air_yards", "receiving_yards_after_catch",
    "receiving_first_downs", "receiving_epa",
    "def_tackles_solo", "def_tackle_assists", "def_sacks",
    "def_interceptions", "def_pass_defended", "def_fumbles_forced",
    "def_tackles_for_loss", "def_qb_hits",
]
# Weekly rate stats averaged across games.
MEAN_COLS = ["target_share", "air_yards_share"]
# Weekly rate stats averaged with a weight, because a plain mean of per-game
# rates over-counts low-volume games. (col -> weight col)
WEIGHTED_MEAN_COLS = {"passing_cpoe": "attempts"}

# Metric catalog: category -> list of (id, label, agg_col, fmt, inverted).
# ``inverted`` = lower raw value ranks higher (e.g. turnovers, sacks taken).
METRIC_DEFS: dict[str, list[tuple[str, str, str, str, bool]]] = {
    "Passing": [
        ("pass_yards", "Pass Yds", "passing_yards", "comma", False),
        ("pass_tds", "Pass TD", "passing_tds", "int", False),
        ("cmp_pct", "Cmp%", "cmp_pct", "pct1", False),
        ("ypa", "Y/A", "ypa", "dec1", False),
        ("int_rate", "INT%", "int_rate", "pct1", True),
        ("passer_rating", "Rating", "passer_rating", "dec1", False),
        ("passing_epa", "EPA/Play", "passing_epa_per_play", "dec2", False),
        ("cpoe", "CPOE", "cpoe", "signed1", False),
        ("avg_time_to_throw", "Time to Throw", "avg_time_to_throw", "dec2", False),
        ("aggressiveness", "Aggressiveness", "aggressiveness", "pct1", False),
        ("avg_intended_air_yards", "Intended Air Yds", "avg_intended_air_yards", "dec1", False),
        ("sack_rate", "Sack%", "sack_rate", "pct1", True),
    ],
    "Rushing": [
        ("rush_yards", "Rush Yds", "rushing_yards", "comma", False),
        ("rush_tds", "Rush TD", "rushing_tds", "int", False),
        ("ypc", "Y/C", "ypc", "dec1", False),
        ("rushing_epa_per_carry", "EPA/Rush", "rushing_epa_per_carry", "dec2", False),
        ("rushing_epa", "Rush EPA", "rushing_epa", "dec1", False),
        ("rush_first_downs", "Rush 1D", "rushing_first_downs", "int", False),
        ("explosive_rush_rate", "Explosive%", "explosive_rush_rate", "pct1", False),
        ("fumble_rate", "Fumble%", "fumble_rate", "pct1", True),
        ("rush_yoe", "RYOE", "rush_yoe", "dec1", False),
    ],
    "Receiving": [
        ("receptions", "Rec", "receptions", "int", False),
        ("rec_yards", "Rec Yds", "receiving_yards", "comma", False),
        ("rec_tds", "Rec TD", "receiving_tds", "int", False),
        ("yac", "YAC", "rec_yac", "comma", False),
        ("target_share", "Target Share", "target_share_pct", "pct1", False),
        ("wopr", "WOPR", "wopr", "dec2", False),
        ("racr", "RACR", "racr", "dec2", False),
        ("receiving_epa_per_target", "EPA/Tgt", "receiving_epa_per_target", "dec2", False),
        ("receiving_epa", "Rec EPA", "receiving_epa", "dec1", False),
        ("catch_pct", "Catch%", "catch_pct", "pct1", False),
        ("avg_separation", "Separation", "avg_separation", "dec1", False),
        ("avg_yac_above_expectation", "YAC+", "avg_yac_above_expectation", "signed1", False),
    ],
    # Defence used to be traditional counting stats only, which left defenders
    # as the one position group with no advanced view anywhere in the app. The
    # first six rows here are PFR's advanced defensive stats (2018+): what a
    # defender allowed in coverage, and the pressure he generated rushing - the
    # closest thing the public data has to a defensive EPA.
    "Defense": [
        ("def_pressures", "Pressures", "def_pressures", "int", False),
        ("def_hurries", "Hurries", "def_hurries", "int", False),
        ("def_qb_knockdowns", "QB KD", "def_qb_knockdowns", "int", False),
        ("def_cmp_pct_allowed", "Cmp% Allowed", "def_cmp_pct_allowed", "pct1", True),
        ("def_yds_per_tgt_allowed", "Yds/Tgt Allowed", "def_yds_per_tgt_allowed", "dec1", True),
        ("def_rating_allowed", "Rating Allowed", "def_rating_allowed", "dec1", True),
        ("def_missed_tkl_pct", "Missed Tkl%", "def_missed_tkl_pct", "pct1", True),
        ("tackles", "Tackles", "tackles", "int", False),
        ("sacks", "Sacks", "sacks", "dec1", False),
        ("def_ints", "INT", "def_ints", "int", False),
        ("passes_defended", "PD", "passes_defended", "int", False),
        ("forced_fumbles", "FF", "forced_fumbles", "int", False),
        ("tfl", "TFL", "tfl", "int", False),
        ("qb_hits", "QB Hits", "qb_hits", "int", False),
    ],
}

# PFR advanced-defence column -> our aggregate column. PFR ships the two rate
# columns as fractions (0.68), not percentages, so they are scaled on merge.
PFR_DEF_COLS = {
    "prss": "def_pressures",
    "hrry": "def_hurries",
    "qbkd": "def_qb_knockdowns",
    "cmp_percent": "def_cmp_pct_allowed",
    "yds_tgt": "def_yds_per_tgt_allowed",
    "rat": "def_rating_allowed",
    "m_tkl_percent": "def_missed_tkl_pct",
    "tgt": "def_targets_allowed",
    "comb": "def_combined_tackles",
}

POSITION_GROUP_TO_TYPE = {
    "QB": "qb",
    "RB": "rb",
    "WR": "wr",
    "TE": "te",
    "DB": "def",
    "DL": "def",
    "LB": "def",
}


# --------------------------------------------------------------------------- #
# Pure helpers (unit-tested; no network)
# --------------------------------------------------------------------------- #
def resolve_season(cli_season: Optional[int] = None) -> int:
    """Resolve the season from CLI arg, then STATCAST_SEASON env, then default."""
    if cli_season is not None:
        candidate: Optional[int] = cli_season
    else:
        raw = os.environ.get("STATCAST_SEASON")
        if raw is None or raw == "":
            return DEFAULT_SEASON
        try:
            candidate = int(raw)
        except ValueError:
            return DEFAULT_SEASON
    if candidate is None or candidate < MIN_SEASON or candidate > DEFAULT_SEASON:
        return DEFAULT_SEASON
    return candidate


def gsis_to_id(gsis: Any) -> Optional[int]:
    """Convert an nflverse GSIS id ("00-0034796") to the DB bigint (34796)."""
    if gsis is None or (isinstance(gsis, float) and pd.isna(gsis)):
        return None
    text = str(gsis).strip()
    if not text:
        return None
    tail = text.split("-")[-1]
    try:
        return int(tail)
    except ValueError:
        return None


def player_type_from_position(position: Any, position_group: Any) -> str:
    """Map nflverse position/position_group to a contract player_type."""
    pos = str(position or "").strip().upper()
    if pos == "K":
        return "k"
    group = str(position_group or "").strip().upper()
    return POSITION_GROUP_TO_TYPE.get(group, "def" if group in {"DB", "DL", "LB"} else "")


def format_value(value: Any, fmt: str) -> str:
    """Format a raw stat value for display per the contract conventions."""
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    try:
        v = float(value)
    except (ValueError, TypeError):
        return ""
    if fmt == "comma":
        return f"{int(round(v)):,}"
    if fmt == "int":
        return str(int(round(v)))
    if fmt == "pct1":
        return f"{v:.1f}%"
    if fmt == "dec1":
        return f"{v:.1f}"
    if fmt == "dec2":
        return f"{v:.2f}"
    if fmt == "signed1":
        return f"{v:+.1f}"
    return str(v)


def passer_rating(cmp_: Any, att: Any, yds: Any, td: Any, ints: Any) -> Optional[float]:
    """Standard NFL passer rating (0-158.3) from season totals."""
    try:
        att = float(att)
        if att <= 0:
            return None
        a = min(max(((float(cmp_) / att) - 0.3) * 5, 0.0), 2.375)
        b = min(max(((float(yds) / att) - 3) * 0.25, 0.0), 2.375)
        c = min(max((float(td) / att) * 20, 0.0), 2.375)
        d = min(max(2.375 - (float(ints) / att) * 25, 0.0), 2.375)
    except (ValueError, TypeError):
        return None
    return round((a + b + c + d) / 6 * 100, 1)


def rank_percentiles(series: pd.Series, inverted: bool) -> dict[int, int]:
    """Percentile (1-100) of each non-null value within the series.

    ``inverted`` ranks lower raw values higher (turnovers, sacks taken).
    """
    s = pd.to_numeric(series, errors="coerce").dropna()
    if s.empty:
        return {}
    ranks = s.rank(method="average", ascending=not inverted, pct=True)
    return {int(pid): max(1, min(100, int(round(pct * 100)))) for pid, pct in ranks.items()}


LIVE_OFFENSE_TYPES = {"qb", "rb", "wr", "te"}


def has_opportunity(row: Any, category: str, player_type: str) -> bool:
    """Whether a player has any volume at all in a category.

    The live season ships every player who has played, not just those over the
    qualification bar: the app's "Qualified" filter is a choice the user makes,
    and in the early weeks nobody is over the full-season bar. One attempt,
    carry, target or game is data; zero is not (a receiver with no carries has
    no rushing line to rank).
    """
    def _num(col: str) -> float:
        val = row.get(col)
        try:
            return float(val) if val is not None and not pd.isna(val) else 0.0
        except (ValueError, TypeError):
            return 0.0

    if category == "Defense":
        return player_type == "def" and _num("games") >= 1
    if player_type not in LIVE_OFFENSE_TYPES:
        return False
    if category == "Passing":
        return _num("attempts") >= 1
    if category == "Rushing":
        return _num("carries") >= 1
    if category == "Receiving":
        if not bool(row.get("targets_reliable", True)):
            return _num("receptions") >= 1
        return _num("targets") >= 1
    return False


def qualifies(
    row: Any,
    category: str,
    player_type: str,
    season_type: str = "REG",
    career: bool = False,
    scale: float = 1.0,
) -> bool:
    """Whether a player clears the qualification threshold for a category.

    Four tiers, one per (career, postseason) combination: a full season, a
    postseason run (a handful of games, so the bar drops), a career (roughly
    three starting seasons, so it rises), and a *playoff* career, which is a
    career measured in games rather than seasons.

    ``scale`` prorates the full-season tier for a season still being played
    (see ``qualification_scale``); the other tiers ignore it.
    """
    def _num(col: str) -> float:
        val = row.get(col)
        try:
            return float(val) if val is not None and not pd.isna(val) else 0.0
        except (ValueError, TypeError):
            return 0.0

    postseason = season_type == "POST"

    def _threshold(
        season: float,
        post: float,
        career_value: float,
        career_post: float,
    ) -> float:
        if career:
            return career_post if postseason else career_value
        if postseason:
            return post
        return max(1, math.ceil(season * scale)) if scale < 1 else season

    if category == "Passing":
        return _num("attempts") >= _threshold(
            QUAL_ATTEMPTS, POST_QUAL_ATTEMPTS,
            CAREER_QUAL_ATTEMPTS, CAREER_POST_QUAL_ATTEMPTS,
        )
    if category == "Rushing":
        return _num("carries") >= _threshold(
            QUAL_CARRIES, POST_QUAL_CARRIES,
            CAREER_QUAL_CARRIES, CAREER_POST_QUAL_CARRIES,
        )
    if category == "Receiving":
        if not bool(row.get("targets_reliable", True)):
            return _num("receptions") >= _threshold(
                QUAL_RECEPTIONS, POST_QUAL_RECEPTIONS,
                CAREER_QUAL_RECEPTIONS, CAREER_POST_QUAL_RECEPTIONS,
            )
        return _num("targets") >= _threshold(
            QUAL_TARGETS, POST_QUAL_TARGETS,
            CAREER_QUAL_TARGETS, CAREER_POST_QUAL_TARGETS,
        )
    if category == "Defense":
        return player_type == "def" and _num("games") >= _threshold(
            QUAL_GAMES, POST_QUAL_GAMES,
            CAREER_QUAL_GAMES, CAREER_POST_QUAL_GAMES,
        )
    return False


def _safe_div(numer: pd.Series, denom: pd.Series) -> pd.Series:
    return numer / denom.replace(0, np.nan)


def _derive(agg: pd.DataFrame, output: str, required: list[str], calculation: Any) -> None:
    """Add a derived column only when every required source column exists."""
    if all(column in agg.columns for column in required):
        agg[output] = calculation()


def aggregate_seasons(
    weekly: pd.DataFrame,
    season: int,
    season_type: str = "REG",
) -> pd.DataFrame:
    """Aggregate one season phase to one total row per player (indexed by id).

    Pure: takes a DataFrame, returns a DataFrame with all counting totals,
    derived rate columns, and identity columns. No NGS, no network.
    """
    df = weekly[
        (weekly["season"] == season)
        & (weekly["season_type"] == season_type)
    ].copy()
    if df.empty:
        return pd.DataFrame()

    df["pid"] = df["player_id"].map(gsis_to_id)
    df = df[df["pid"].notna()].copy()
    df["pid"] = df["pid"].astype(int)

    present_sum = [c for c in SUM_COLS if c in df.columns]
    present_mean = [c for c in MEAN_COLS if c in df.columns]

    sums = df.groupby("pid")[present_sum].sum(min_count=1)
    means = df.groupby("pid")[present_mean].mean() if present_mean else pd.DataFrame(index=sums.index)
    games = df.groupby("pid").size().rename("games")

    # Identity from the player's most recent (max week) row.
    latest = df.sort_values("week").groupby("pid").tail(1).set_index("pid")
    identity = latest[["player_display_name", "team", "position", "position_group"]]

    agg = sums.join(means).join(games).join(identity)

    # Volume-weighted season means. CPOE is the one that matters: it arrives as a
    # per-game rate, and a flat mean would let a 3-attempt week count as much as
    # a 40-attempt one. Weighting by attempts reconstructs the season figure.
    #
    # This is also what extends CPOE back to 2006. It used to come only from the
    # Next Gen Stats join, so it started in 2016 and simply did not exist for the
    # ten seasons before - even though the weekly feed has carried
    # ``passing_cpoe`` since 2006, when pbp air-yards tracking began. Deriving it
    # here and preferring it everywhere also keeps *one* definition across the
    # whole range: NGS's completion-percentage-above-expectation is a different
    # model (they correlate ~0.86 and differ by ~1.6 points over a season), so
    # splicing the two at 2016 would put a seam in the middle of every
    # year-over-year CPOE comparison the app draws.
    for column, weight_col in WEIGHTED_MEAN_COLS.items():
        if column not in df.columns or weight_col not in df.columns:
            continue
        w = df[["pid"]].copy()
        w["_value"] = pd.to_numeric(df[column], errors="coerce")
        w["_weight"] = pd.to_numeric(df[weight_col], errors="coerce")
        w = w[w["_value"].notna() & w["_weight"].notna() & (w["_weight"] > 0)]
        if w.empty:
            continue
        w["_product"] = w["_value"] * w["_weight"]
        grouped = w.groupby("pid")[["_product", "_weight"]].sum()
        agg[column] = grouped["_product"] / grouped["_weight"].replace(0, np.nan)

    agg["name"] = agg["player_display_name"].astype(str)
    agg["player_type"] = [
        player_type_from_position(p, g)
        for p, g in zip(agg["position"], agg["position_group"])
    ]

    # nflverse has complete receptions and yards back to 1999, but targets are
    # effectively blank for 2003-2008. Detect that at the phase level. Those
    # seasons qualify receivers by receptions and omit target-derived metrics.
    targets_total = pd.to_numeric(agg.get("targets"), errors="coerce").sum()
    receptions_total = pd.to_numeric(agg.get("receptions"), errors="coerce").sum()
    targets_reliable = targets_total >= receptions_total
    agg["targets_reliable"] = targets_reliable
    if not targets_reliable:
        for column in [
            "targets",
            "target_share",
            "air_yards_share",
            "receiving_air_yards",
        ]:
            if column in agg.columns:
                agg[column] = np.nan

    # Passing derived rates.
    # `cpoe` is the metric catalog's column name; the weighted mean above lands
    # under the feed's own name. Aliasing rather than renaming keeps the source
    # column visible for debugging.
    if "passing_cpoe" in agg.columns:
        agg["cpoe"] = agg["passing_cpoe"]
    _derive(agg, "cmp_pct", ["completions", "attempts"], lambda: _safe_div(agg["completions"], agg["attempts"]) * 100)
    _derive(agg, "ypa", ["passing_yards", "attempts"], lambda: _safe_div(agg["passing_yards"], agg["attempts"]))
    _derive(agg, "int_rate", ["passing_interceptions", "attempts"], lambda: _safe_div(agg["passing_interceptions"], agg["attempts"]) * 100)
    _derive(
        agg,
        "sack_rate",
        ["sacks_suffered", "attempts"],
        lambda: _safe_div(agg["sacks_suffered"], agg["attempts"] + agg["sacks_suffered"]) * 100,
    )
    _derive(
        agg,
        "passing_epa_per_play",
        ["passing_epa", "attempts", "sacks_suffered"],
        lambda: _safe_div(agg["passing_epa"], agg["attempts"] + agg["sacks_suffered"]),
    )
    passer_rating_columns = [
        "completions", "attempts", "passing_yards", "passing_tds",
        "passing_interceptions",
    ]
    if all(column in agg.columns for column in passer_rating_columns):
        agg["passer_rating"] = [
            passer_rating(c, a, y, t, i)
            for c, a, y, t, i in zip(
                agg["completions"], agg["attempts"], agg["passing_yards"],
                agg["passing_tds"], agg["passing_interceptions"],
            )
        ]

    # Rushing derived rates.
    _derive(agg, "ypc", ["rushing_yards", "carries"], lambda: _safe_div(agg["rushing_yards"], agg["carries"]))
    _derive(agg, "rushing_epa_per_carry", ["rushing_epa", "carries"], lambda: _safe_div(agg["rushing_epa"], agg["carries"]))
    _derive(agg, "explosive_rush_rate", ["rushing_10", "carries"], lambda: _safe_div(agg["rushing_10"], agg["carries"]) * 100)
    _derive(agg, "fumble_rate", ["rushing_fumbles", "carries"], lambda: _safe_div(agg["rushing_fumbles"], agg["carries"]) * 100)

    # Receiving derived rates.
    _derive(agg, "catch_pct", ["receptions", "targets"], lambda: _safe_div(agg["receptions"], agg["targets"]) * 100)
    _derive(agg, "receiving_epa_per_target", ["receiving_epa", "targets"], lambda: _safe_div(agg["receiving_epa"], agg["targets"]))
    _derive(agg, "racr", ["receiving_yards", "receiving_air_yards"], lambda: _safe_div(agg["receiving_yards"], agg["receiving_air_yards"]))
    if "receiving_yards_after_catch" in agg.columns:
        agg["rec_yac"] = agg["receiving_yards_after_catch"]
    if "target_share" in agg.columns:
        agg["target_share_pct"] = agg["target_share"] * 100
        if "air_yards_share" in agg.columns:
            agg["wopr"] = 1.5 * agg["target_share"] + 0.7 * agg["air_yards_share"]

    # Defense aliases. Only combine fields that the source season actually has.
    tackle_columns = [column for column in ["def_tackles_solo", "def_tackle_assists"] if column in agg.columns]
    if tackle_columns:
        agg["tackles"] = agg[tackle_columns].sum(axis=1, min_count=1)
    defense_aliases = {
        "sacks": "def_sacks",
        "def_ints": "def_interceptions",
        "passes_defended": "def_pass_defended",
        "forced_fumbles": "def_fumbles_forced",
        "tfl": "def_tackles_for_loss",
        "qb_hits": "def_qb_hits",
    }
    for alias, source in defense_aliases.items():
        if source in agg.columns:
            agg[alias] = agg[source]

    return agg


def merge_ngs(
    agg: pd.DataFrame,
    ngs_passing: pd.DataFrame,
    ngs_rushing: pd.DataFrame,
    ngs_receiving: pd.DataFrame,
    season: int,
    season_type: str = "REG",
) -> pd.DataFrame:
    """Join season-level Next Gen Stats columns onto ``agg``.

    Pure: NGS DataFrames in, augmented ``agg`` out.
    """
    def _season_level(ngs: pd.DataFrame, cols: dict[str, str]) -> pd.DataFrame:
        if ngs is None or ngs.empty:
            return pd.DataFrame(columns=list(cols.values()))
        d = ngs[
            (ngs["season"] == season)
            & (ngs["season_type"] == season_type)
            & (ngs["week"] == 0)
        ].copy()
        if d.empty:
            return pd.DataFrame(columns=list(cols.values()))
        d["pid"] = d["player_gsis_id"].map(gsis_to_id)
        d = d[d["pid"].notna()].copy()
        d["pid"] = d["pid"].astype(int)
        d = d[~d["pid"].duplicated(keep="first")].set_index("pid")
        present = {src: dst for src, dst in cols.items() if src in d.columns}
        return d[list(present.keys())].rename(columns=present)

    # NGS's completion-percentage-above-expectation lands in its own column, not
    # straight into `cpoe`: the pbp-derived CPOE computed in `aggregate_seasons`
    # is the preferred source because it spans 2006-present, and mixing two
    # different expectation models inside one column would put a discontinuity at
    # 2016. This is a fallback for the rare passer NGS has and pbp doesn't.
    pass_ngs = _season_level(ngs_passing, {
        "completion_percentage_above_expectation": "cpoe_ngs",
        "avg_time_to_throw": "avg_time_to_throw",
        "aggressiveness": "aggressiveness",
        "avg_intended_air_yards": "avg_intended_air_yards",
    })
    rush_ngs = _season_level(ngs_rushing, {
        "rush_yards_over_expected": "rush_yoe",
    })
    rec_ngs = _season_level(ngs_receiving, {
        "avg_separation": "avg_separation",
        "avg_yac_above_expectation": "avg_yac_above_expectation",
    })

    for extra in (pass_ngs, rush_ngs, rec_ngs):
        if not extra.empty:
            agg = agg.join(extra, how="left")

    if "cpoe_ngs" in agg.columns:
        if "cpoe" in agg.columns:
            agg["cpoe"] = agg["cpoe"].fillna(agg["cpoe_ngs"])
        else:
            agg["cpoe"] = agg["cpoe_ngs"]
    return agg


def merge_pfr_defense(
    agg: pd.DataFrame,
    pfr_def: pd.DataFrame,
    rate_thresholds: bool = True,
) -> pd.DataFrame:
    """Join PFR advanced defensive stats onto ``agg`` and derive their rates.

    Pure: an id-indexed PFR frame in, augmented ``agg`` out. ``pfr_def`` is
    already remapped from ``pfr_id`` to our integer player id by the loader.
    """
    if pfr_def is None or pfr_def.empty:
        return agg

    present = [c for c in pfr_def.columns if c in set(PFR_DEF_COLS.values())]
    if not present:
        return agg
    agg = agg.join(pfr_def[present], how="left")

    # PFR ships these two as fractions; the app formats them as percentages.
    for column in ("def_cmp_pct_allowed", "def_missed_tkl_pct"):
        if column in agg.columns:
            agg[column] = pd.to_numeric(agg[column], errors="coerce") * 100

    return apply_def_rate_thresholds(agg) if rate_thresholds else agg


# Defensive rate columns and the volume each one is measured over. The live
# season keeps these rates at any volume and flags the thin ones instead of
# nulling them (see ``def_rate_volume_ok``).
DEF_RATE_GATES = {
    "def_cmp_pct_allowed": ("def_targets_allowed", QUAL_DEF_TARGETS),
    "def_yds_per_tgt_allowed": ("def_targets_allowed", QUAL_DEF_TARGETS),
    "def_rating_allowed": ("def_targets_allowed", QUAL_DEF_TARGETS),
    "def_missed_tkl_pct": ("def_combined_tackles", QUAL_DEF_TACKLES),
}


def def_rate_volume_ok(row: Any, column: str, scale: float = 1.0) -> bool:
    """Whether a defensive rate clears its (prorated) volume bar."""
    gate = DEF_RATE_GATES.get(column)
    if gate is None:
        return True
    volume_col, threshold = gate
    try:
        volume = float(row.get(volume_col))
    except (TypeError, ValueError):
        return False
    if pd.isna(volume):
        return False
    bar = max(1, math.ceil(threshold * scale)) if scale < 1 else threshold
    return volume >= bar


def apply_def_rate_thresholds(agg: pd.DataFrame) -> pd.DataFrame:
    """Null defensive rates measured over too little volume to mean anything.

    The counting stats (pressures, hurries, knockdowns) are kept whatever the
    volume - they are totals, not rates, so a small number is simply a small
    number rather than a misleading one. Split out from ``merge_pfr_defense`` so
    the career rollup, which pools already-scaled rates from several seasons, can
    apply exactly the same cut without going back through the scaling step.
    """
    targets = pd.to_numeric(agg.get("def_targets_allowed"), errors="coerce")
    if targets is not None:
        below = targets.isna() | (targets < QUAL_DEF_TARGETS)
        for column in (
            "def_cmp_pct_allowed",
            "def_yds_per_tgt_allowed",
            "def_rating_allowed",
        ):
            if column in agg.columns:
                agg.loc[below, column] = np.nan

    tackles = pd.to_numeric(agg.get("def_combined_tackles"), errors="coerce")
    if tackles is not None and "def_missed_tkl_pct" in agg.columns:
        agg.loc[
            tackles.isna() | (tackles < QUAL_DEF_TACKLES),
            "def_missed_tkl_pct",
        ] = np.nan

    return agg


def build_standard_stats(row: Any) -> list[dict[str, str]]:
    """Assemble the standard_stats jsonb array from an aggregated row."""
    def n(col: str) -> float:
        val = row.get(col)
        try:
            return float(val) if val is not None and not pd.isna(val) else 0.0
        except (ValueError, TypeError):
            return 0.0

    stats: list[dict[str, str]] = []

    def add(label: str, value: str) -> None:
        stats.append({"id": f"std-{label}", "label": label, "value": value})

    add("G", str(int(n("games"))))

    if n("attempts") > 0:
        add("Cmp/Att", f"{int(n('completions'))}/{int(n('attempts'))}")
        add("Pass Yds", f"{int(n('passing_yards')):,}")
        add("Pass TD", str(int(n("passing_tds"))))
        add("INT", str(int(n("passing_interceptions"))))
    if n("carries") > 0:
        add("Car", str(int(n("carries"))))
        add("Rush Yds", f"{int(n('rushing_yards')):,}")
        add("Rush TD", str(int(n("rushing_tds"))))
    if n("targets") > 0:
        add("Rec/Tgt", f"{int(n('receptions'))}/{int(n('targets'))}")
        add("Rec Yds", f"{int(n('receiving_yards')):,}")
        add("Rec TD", str(int(n("receiving_tds"))))
    if row.get("player_type") == "def":
        add("Tackles", str(int(n("tackles"))))
        add("Sacks", f"{n('sacks'):.1f}")
        add("Def INT", str(int(n("def_ints"))))
        # The volume behind the coverage rates. Emitted so the app can weight
        # them when pooling a roster (a team's Cmp% allowed is the target-weighted
        # mean of its defenders', not the flat average), and because "targeted 96
        # times" is context a reader wants next to "allowed 61%".
        if n("def_targets_allowed") > 0:
            add("Tgt Allowed", str(int(n("def_targets_allowed"))))

    return stats


def build_snapshot_rows(
    agg: pd.DataFrame,
    season: int,
    now: datetime,
    season_type: str = "REG",
    qual_scale: float = 1.0,
    live: bool = False,
) -> list[dict]:
    """Build player_snapshots rows from an aggregated (id-indexed) DataFrame.

    Past seasons: percentiles are computed per category among qualified players
    only, and a player receives every category's metrics for which they qualify.

    The live season (``live``): no minimum. Every player with any volume in a
    category is ranked and shipped, and each metric carries ``qualified`` (the
    bar prorated by ``qual_scale``) so the app's Qualified filter still works.
    """
    if agg.empty:
        return []

    now_str = now.isoformat()
    players: dict[int, dict] = {}
    # The career rollup reuses this function wholesale - same formatting, same
    # percentile ranking - and differs only in where the qualification bar sits.
    career = season == ALL_TIME_SEASON

    def _ensure(pid: int, row: Any) -> dict:
        if pid not in players:
            players[pid] = {
                "id": pid,
                "name": str(row.get("name") or ""),
                "team": str(row.get("team") or "TBD"),
                "position": str(row.get("position") or ""),
                "handedness": "",
                "image_url": row.get("image_url") if pd.notna(row.get("image_url")) else None,
                "player_type": row.get("player_type") or "",
                "season": season,
                "season_type": season_type,
                "source": SOURCE,
                "metrics": [],
                "standard_stats": build_standard_stats(row),
                "games": [],
                "updated_at": now_str,
            }
        return players[pid]

    for category, defs in METRIC_DEFS.items():
        qual_ids = [
            int(pid) for pid, row in agg.iterrows()
            if qualifies(
                row,
                category,
                str(row.get("player_type") or ""),
                season_type,
                career=career,
                scale=qual_scale,
            )
        ]
        if live:
            ranked_ids = [
                int(pid) for pid, row in agg.iterrows()
                if has_opportunity(row, category, str(row.get("player_type") or ""))
            ]
        else:
            ranked_ids = qual_ids
        if not ranked_ids:
            continue
        qualified_ids = set(qual_ids)
        sub = agg.loc[ranked_ids]

        pct_maps: dict[str, dict[int, int]] = {}
        for mid, _label, col, _fmt, inverted in defs:
            if col in sub.columns:
                pct_maps[mid] = rank_percentiles(sub[col], inverted)

        for pid in ranked_ids:
            row = agg.loc[pid]
            player = _ensure(pid, row)
            for mid, label, col, fmt, _inverted in defs:
                if col not in agg.columns:
                    continue
                raw = row.get(col)
                if raw is None or pd.isna(raw):
                    continue
                percentile = pct_maps.get(mid, {}).get(pid)
                if percentile is None:
                    continue
                metric = {
                    "id": f"{category.lower()}-{pid}-{mid}",
                    "label": label,
                    "value": format_value(raw, fmt),
                    "percentile": percentile,
                    "category": category,
                }
                if live:
                    metric["qualified"] = pid in qualified_ids and def_rate_volume_ok(row, col, qual_scale)
                player["metrics"].append(metric)

    snapshots = [p for p in players.values() if p["metrics"]]
    return snapshots


# --------------------------------------------------------------------------- #
# Network loaders
# --------------------------------------------------------------------------- #
def _to_pandas(frame: Any) -> pd.DataFrame:
    if isinstance(frame, pl.DataFrame):
        return frame.to_pandas()
    return frame


def load_headshots() -> dict[int, str]:
    """Map DB player id -> headshot URL from load_players()."""
    players = _to_pandas(nfl.load_players())
    lookup: dict[int, str] = {}
    for _, row in players.iterrows():
        pid = gsis_to_id(row.get("gsis_id"))
        url = row.get("headshot")
        if pid is not None and isinstance(url, str) and url:
            lookup[pid] = url
    logger.info("Loaded %d headshots", len(lookup))
    return lookup


def load_pfr_id_crosswalk() -> dict[str, int]:
    """Map PFR player id -> our integer (gsis-derived) player id.

    PFR's advanced stats are keyed by their own id, so they cannot be joined to
    the weekly feed without this. ``load_players()`` carries both.
    """
    players = _to_pandas(nfl.load_players())
    lookup: dict[str, int] = {}
    for _, row in players.iterrows():
        pfr_id = row.get("pfr_id")
        pid = gsis_to_id(row.get("gsis_id"))
        if pid is not None and isinstance(pfr_id, str) and pfr_id:
            lookup[pfr_id] = pid
    logger.info("Loaded %d PFR id mappings", len(lookup))
    return lookup


def load_pfr_defense(season: int) -> pd.DataFrame:
    """Season-level PFR advanced defensive stats, indexed by our player id.

    Returns an empty frame for seasons before PFR coverage begins, so callers
    can join unconditionally.
    """
    if season < PFR_DEF_FIRST_SEASON:
        logger.info(
            "Skipping PFR advanced defence for %s (available since %s).",
            season,
            PFR_DEF_FIRST_SEASON,
        )
        return pd.DataFrame()

    raw = _to_pandas(nfl.load_pfr_advstats(seasons=[season], stat_type="def", summary_level="season"))
    if raw is None or raw.empty:
        logger.warning("No PFR advanced defence rows for %s.", season)
        return pd.DataFrame()

    df = raw[raw["season"] == season].copy()
    if df.empty:
        return pd.DataFrame()

    crosswalk = load_pfr_id_crosswalk()
    df["pid"] = df["pfr_id"].map(crosswalk)
    unmatched = int(df["pid"].isna().sum())
    df = df[df["pid"].notna()].copy()
    df["pid"] = df["pid"].astype(int)
    # A player who changed teams mid-season has one PFR row per stop. Sum the
    # counting columns and volume-weight the rates, so his season reads as one
    # line the way the weekly aggregate already does.
    present = {src: dst for src, dst in PFR_DEF_COLS.items() if src in df.columns}
    for src in present:
        df[src] = pd.to_numeric(df[src], errors="coerce")

    counting = ["prss", "hrry", "qbkd", "tgt", "comb"]
    rate_weights = {
        "cmp_percent": "tgt",
        "yds_tgt": "tgt",
        "rat": "tgt",
        "m_tkl_percent": "comb",
    }

    out = pd.DataFrame(index=sorted(df["pid"].unique()))
    for src in counting:
        if src in df.columns:
            out[PFR_DEF_COLS[src]] = df.groupby("pid")[src].sum(min_count=1)
    for src, weight_col in rate_weights.items():
        if src not in df.columns or weight_col not in df.columns:
            continue
        w = df[["pid", src, weight_col]].dropna()
        w = w[w[weight_col] > 0]
        if w.empty:
            continue
        product = (w[src] * w[weight_col]).groupby(w["pid"]).sum()
        weight = w[weight_col].groupby(w["pid"]).sum()
        out[PFR_DEF_COLS[src]] = product / weight.replace(0, np.nan)

    logger.info(
        "Loaded PFR advanced defence for %s: %d players (%d unmatched pfr ids).",
        season,
        len(out),
        unmatched,
    )
    return out


def build_agg_for_season(
    season: int,
    season_type: str = "REG",
    live: bool = False,
    weekly_frame: Optional[pd.DataFrame] = None,
    enrichment_status: Optional[dict[str, str]] = None,
) -> pd.DataFrame:
    """Fetch nflverse data and produce the fully-merged aggregate DataFrame.

    ``weekly_frame`` and ``enrichment_status`` are used by the event-aware
    publisher.  The normal command-line ingest keeps the original behavior,
    while the publisher can share one core download across REG and POST and
    publish core stats when an optional enrichment source is temporarily late.
    """
    logger.info("Loading weekly player stats for %s...", season)
    weekly = weekly_frame if weekly_frame is not None else _to_pandas(nfl.load_player_stats([season]))
    logger.info("Weekly rows: %d", len(weekly))

    agg = aggregate_seasons(weekly, season, season_type)
    if agg.empty:
        return agg
    logger.info("Aggregated to %d players", len(agg))

    if season >= NGS_FIRST_SEASON:
        logger.info("Loading Next Gen Stats for %s...", season)
        try:
            ngs_pass = _to_pandas(nfl.load_nextgen_stats([season], stat_type="passing"))
            ngs_rush = _to_pandas(nfl.load_nextgen_stats([season], stat_type="rushing"))
            ngs_rec = _to_pandas(nfl.load_nextgen_stats([season], stat_type="receiving"))
            agg = merge_ngs(
                agg,
                ngs_pass,
                ngs_rush,
                ngs_rec,
                season,
                season_type,
            )
            if enrichment_status is not None:
                enrichment_status["ngs"] = "ready" if any(
                    not frame.empty for frame in (ngs_pass, ngs_rush, ngs_rec)
                ) else "pending"
        except Exception:
            if enrichment_status is None:
                raise
            logger.exception("Failed to load Next Gen Stats; publishing core stats as degraded.")
            enrichment_status["ngs"] = "degraded"
    else:
        logger.info("Skipping Next Gen Stats for %s (available since %s).", season, NGS_FIRST_SEASON)
        if enrichment_status is not None:
            enrichment_status["ngs"] = "not_applicable"

    # PFR's advanced defensive table is regular season only - it carries no
    # season_type column to split on - so the postseason board keeps the
    # traditional defensive stats and simply has no advanced rows.
    if season_type == "REG":
        try:
            pfr = load_pfr_defense(season)
            agg = merge_pfr_defense(agg, pfr, rate_thresholds=not live)
            if enrichment_status is not None:
                enrichment_status["pfr"] = "ready" if not pfr.empty else "pending"
        except Exception:
            if enrichment_status is None:
                raise
            logger.exception("Failed to load PFR advanced defense; publishing core stats as degraded.")
            enrichment_status["pfr"] = "degraded"
    else:
        logger.info("Skipping PFR advanced defence for %s POST (regular season only).", season)
        if enrichment_status is not None:
            enrichment_status["pfr"] = "not_applicable"

    headshots = load_headshots()
    agg["image_url"] = [headshots.get(int(pid)) for pid in agg.index]

    return agg


def chunks(lst: list, n: int) -> Iterator[list]:
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="Season (starting year) to ingest.")
    parser.add_argument(
        "--season-type",
        choices=("REG", "POST", "all"),
        default="REG",
        help="Season phase to ingest. Nightly refresh uses all.",
    )
    args = parser.parse_args()

    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)
    season = resolve_season(args.season)
    live = season == DEFAULT_SEASON
    now = datetime.now(UTC)

    phases = ("REG", "POST") if args.season_type == "all" else (args.season_type,)
    logger.info("=== Ingesting NFL season %s (%s) ===", season, ", ".join(phases))
    try:
        any_rows = False
        for phase in phases:
            agg = build_agg_for_season(season, phase, live=live)
            scale = qualification_scale(agg, season) if phase == "REG" else 1.0
            if live:
                logger.info("Live season: every player ships; Qualified flag bar at %.2f of a season.", scale)
            rows = build_snapshot_rows(agg, season, now, phase, qual_scale=scale, live=live)
            if not rows:
                if phase == "POST":
                    logger.info("No postseason rows for %s yet.", season)
                    continue
                logger.error("No rows to upsert for %s %s.", season, phase)
                sys.exit(1)
            any_rows = True

            by_type: dict[str, int] = {}
            for row in rows:
                player_type = row["player_type"]
                by_type[player_type] = by_type.get(player_type, 0) + 1
            logger.info(
                "Built %d %s snapshots by type: %s",
                len(rows),
                phase,
                by_type,
            )

            batch_size = 150
            for i, batch in enumerate(chunks(rows, batch_size)):
                logger.info(
                    "Upserting batch %d (%d rows) for %s %s...",
                    i + 1,
                    len(batch),
                    season,
                    phase,
                )
                client.table("player_snapshots").upsert(
                    batch,
                    on_conflict="id,season,season_type",
                ).execute()

            logger.info(
                "Upserted %d player snapshots for %s %s.",
                len(rows),
                season,
                phase,
            )

            sanity_floor = 20 if phase == "POST" else 150
            if len(rows) >= sanity_floor:
                kept = {row["id"] for row in rows}
                existing = (
                    client.table("player_snapshots")
                    .select("id")
                    .eq("season", season)
                    .eq("season_type", phase)
                    .execute()
                    .data
                )
                orphans = [row["id"] for row in existing if row["id"] not in kept]
                for batch in chunks(orphans, 100):
                    (
                        client.table("player_snapshots")
                        .delete()
                        .in_("id", batch)
                        .eq("season", season)
                        .eq("season_type", phase)
                        .execute()
                    )
                logger.info(
                    "Pruned %d stale/unqualified rows for %s %s.",
                    len(orphans),
                    season,
                    phase,
                )
            else:
                logger.warning(
                    "Only %d %s rows built — skipping prune.",
                    len(rows),
                    phase,
                )
        if not any_rows:
            logger.error("No snapshots built for %s.", season)
            sys.exit(1)
    except Exception:
        logger.exception("Failed to process season %s", season)
        sys.exit(1)


if __name__ == "__main__":
    main()
