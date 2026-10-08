"""
NHL season-snapshot ingest.

Builds one ``player_snapshots`` row per player per season and phase from
MoneyPuck's season summary files (expected goals, shot quality, on-ice
impact, goaltending) plus the NHL stats REST summary (the standard stats
MoneyPuck lacks), with percentiles ranked inside the player's own cohort:
forwards against forwards, defensemen against defensemen, goalies against
goalies. Powers the iOS player-percentile screens. The contract is
``project-docs/architecture/HOCKEY_CONTRACT.md``.

Pipeline (REG and POST are stored and ranked separately):
  1. Download MoneyPuck ``skaters.csv`` / ``goalies.csv`` (five situation rows
     per player) and sum them to one additive row per player. Rates are always
     derived from summed numerators and denominators, so the career rollup
     (``rollup_all_time.py``) pools seasons with the very same code.
  2. Merge the NHL skater/goalie summary (+/-, PPG, PPP, SHG, GWG, W/L/OT, SO,
     GS, shooting hand).
  3. Derive the metric catalog, rank each metric inside (category, cohort)
     among qualified players, and upsert to Supabase ``player_snapshots`` on
     (id, season, season_type).

Signature changes for ``refresh.py`` (to be adapted in the refresh pass).
Still exported with the same name and return type:
  ``DEFAULT_SEASON``, ``resolve_season``, ``build_snapshot_rows``,
  ``qualification_scale``, ``_to_pandas``.
Changed:
  ``build_agg_for_season(season, season_type="REG", live=False,
  enrichment_status=None)``. The ``weekly_frame`` parameter is gone: MoneyPuck
  publishes one file per phase, so there is no shared core download to pass in.
  ``enrichment_status`` now receives the single key ``"summary"`` (NHL stats
  REST: ``ready`` / ``pending`` / ``degraded``); it replaces the NFL ``ngs`` and
  ``pfr`` keys, and ``refresh.py`` should map it onto ``summary_status``.
  The ``shots`` key (MoneyPuck shots file) is owned by the game-details pass.
  ``build_snapshot_rows`` is unchanged in signature, but ``qual_scale`` now
  prorates by games played out of 82.
Removed (NFL only): ``gsis_to_id``, ``passer_rating``, ``merge_ngs``,
  ``merge_pfr_defense``, ``load_headshots``, ``NGS_FIRST_SEASON``. Other
  modules that still import them (``ingest_game_logs``, ``ingest_game_details``,
  ``ingest_enrichment``, ``rollup_recent_form``) are ported in later passes.
  ``player_type_from_position(position)`` now takes one argument.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. STATCAST_SEASON overrides the
season (name kept for workflow compatibility); ``--season N`` overrides both.
"""

import argparse
import hashlib
import io
import json
import logging
import math
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

import numpy as np
import pandas as pd
import requests
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Season label is the start year (2026 means 2026-27).
_now = datetime.now(UTC)
DEFAULT_SEASON = _now.year if _now.month >= 9 else _now.year - 1
MIN_SEASON = 2008
OLDEST_SUPPORTED_SEASON = 2008  # MoneyPuck's floor
# Sentinel season for the career rollup written by rollup_all_time.py. Zero
# rather than a future year so nothing that clamps to a maximum can mistake it
# for a real season; the app renders it as "All Time".
ALL_TIME_SEASON = 0
SOURCE = "moneypuck"
LEAGUE_GAMES = 82

# --------------------------------------------------------------------------- #
# Qualification thresholds (one place, see HOCKEY_CONTRACT.md "Qualification")
# --------------------------------------------------------------------------- #
QUAL_SKATER_TOI_MIN = 200       # all-situations minutes (Scoring, Shot Quality, Play Driving)
QUAL_SKATER_5V5_TOI_MIN = 150   # Play Driving additionally needs this at 5on5
QUAL_GOALIE_TOI_MIN = 600       # goalies: minutes ...
QUAL_GOALIE_GP = 10             # ... or games played
POST_QUAL_SKATER_GP = 4
POST_QUAL_GOALIE_GP = 2
CAREER_QUAL_SKATER_GP = 300
CAREER_QUAL_GOALIE_GP = 100
# The contract fixes the regular-season career bars only. A career playoff bar
# is measured in games, not seasons; these are roughly a deep run per season
# across a long career, chosen so the board is not a single name.
CAREER_POST_QUAL_SKATER_GP = 50
CAREER_POST_QUAL_GOALIE_GP = 25
# Live-season proration floor: qual_scale = league games played / 82, never
# below this, so the first week still has a non-trivial bar.
QUAL_SCALE_FLOOR = 0.1
MIN_FACEOFFS_FOR_STANDARD_STAT = 50

# --------------------------------------------------------------------------- #
# Sources
# --------------------------------------------------------------------------- #
USER_AGENT = "Hockey StatScout (jackwallner+bb@gmail.com)"
MONEYPUCK_URL = (
    "https://moneypuck.com/moneypuck/playerData/seasonSummary/{season}/{phase}/{kind}.csv"
)
NHL_SUMMARY_URL = "https://api.nhle.com/stats/rest/en/{kind}/summary"
NHL_PAGE_SIZE = 100
MUG_URL = "https://assets.nhle.com/mugs/nhl/{season}{next}/{team}/{pid}.png"
CACHE_DIR = Path(__file__).resolve().parent / ".cache"
REQUEST_PAUSE_SECONDS = 0.3
REQUEST_ATTEMPTS = 3
REQUEST_TIMEOUT = 90

# season_type -> (MoneyPuck folder, NHL gameTypeId)
PHASES = {"REG": ("regular", 2), "POST": ("playoffs", 3)}

# MoneyPuck and NHL team codes agree for the 32 current clubs; older seasons
# use dotted codes. Normalised here so every stored row uses the NHL code.
TEAM_ALIASES = {
    "L.A": "LAK", "N.J": "NJD", "S.J": "SJS", "T.B": "TBL",
    "PHX": "ARI", "WAS": "WSH", "VEG": "VGK", "MON": "MTL", "CLB": "CBJ",
}

POSITION_TO_TYPE = {"C": "f", "L": "f", "R": "f", "W": "f", "D": "d", "G": "g"}
PLAYER_TYPES = ("f", "d", "g")

# MoneyPuck columns summed per situation, mapped to our additive columns.
SKATER_ALL = {
    "games_played": "games", "icetime": "icetime", "gameScore": "game_score",
    "I_F_goals": "goals", "I_F_primaryAssists": "assists1",
    "I_F_secondaryAssists": "assists2", "I_F_points": "points",
    "I_F_shotsOnGoal": "sog", "I_F_shotAttempts": "shot_attempts",
    "I_F_xGoals": "ixg", "I_F_highDangerShots": "hd_shots",
    "I_F_unblockedShotAttempts": "unblocked", "I_F_rebounds": "rebounds_created",
    "shotsBlockedByPlayer": "blocks", "I_F_hits": "hits",
    "I_F_takeaways": "takeaways", "I_F_giveaways": "giveaways",
    "I_F_penalityMinutes": "pim_mp", "faceoffsWon": "fo_won",
    "faceoffsLost": "fo_lost",
}
SKATER_5V5 = {
    "icetime": "icetime_5v5",
    "OnIce_F_xGoals": "xgf_5v5", "OnIce_A_xGoals": "xga_5v5",
    "OnIce_F_goals": "gf_5v5", "OnIce_A_goals": "ga_5v5",
    "OnIce_F_shotAttempts": "cf_5v5", "OnIce_A_shotAttempts": "ca_5v5",
    "OnIce_F_highDangerShots": "hdf_5v5", "OnIce_A_highDangerShots": "hda_5v5",
    "OffIce_F_xGoals": "off_xgf_5v5", "OffIce_A_xGoals": "off_xga_5v5",
    "OffIce_F_shotAttempts": "off_cf_5v5", "OffIce_A_shotAttempts": "off_ca_5v5",
}
SKATER_PP = {"I_F_points": "pp_points"}
GOALIE_ALL = {
    "games_played": "games", "icetime": "icetime", "xGoals": "xgoals_against",
    "goals": "goals_against", "ongoal": "shots_against",
    "highDangerShots": "hd_shots_against", "highDangerGoals": "hd_goals_against",
    "rebounds": "rebounds_against",
}
IDENTITY_COLS = ["name", "team", "position", "season"]

# NHL stats REST columns summed (career pooling adds seasons), per report.
NHL_SKATER_COLS = {
    "gameWinningGoals": "gwg", "ppGoals": "ppg", "ppPoints": "ppp",
    "shGoals": "shg", "plusMinus": "plus_minus", "penaltyMinutes": "pim_nhl",
}
NHL_GOALIE_COLS = {
    "gamesStarted": "gs", "wins": "wins", "losses": "losses",
    "otLosses": "ot_losses", "shutouts": "shutouts",
}

# Metric catalog: category -> list of (id, label, agg_col, fmt, inverted).
# ``inverted`` = lower raw value ranks higher.
METRIC_DEFS: dict[str, list[tuple[str, str, str, str, bool]]] = {
    "Scoring": [
        ("goals", "G", "goals", "int", False),
        ("assists", "A", "assists", "int", False),
        ("points", "P", "points", "int", False),
        ("points_per_60", "P/60", "points_per_60", "dec2", False),
        ("primary_points", "Primary P", "primary_points", "int", False),
        ("pp_points", "PP P", "pp_points", "int", False),
        ("shots_on_goal", "SOG", "sog", "int", False),
        ("shooting_pct", "Sh%", "shooting_pct", "pct1", False),
        ("game_score_per_gp", "Game Score", "game_score_per_gp", "dec2", False),
    ],
    "Shot Quality": [
        ("ixg", "ixG", "ixg", "dec1", False),
        ("gax", "GAx", "gax", "signed1", False),
        ("ixg_per_60", "ixG/60", "ixg_per_60", "dec2", False),
        ("shot_attempts", "Shot Att", "shot_attempts", "int", False),
        ("shots_per_60", "Shots/60", "shots_per_60", "dec1", False),
        ("hd_shots", "HD Shots", "hd_shots", "int", False),
        ("xg_per_shot", "xG/Shot", "xg_per_shot", "dec3", False),
        ("rebounds_created", "Rebounds", "rebounds_created", "int", False),
    ],
    "Play Driving": [
        ("xgf_pct", "xGF%", "xgf_pct", "pct1", False),
        ("rel_xgf_pct", "Rel xGF%", "rel_xgf_pct", "signed1", False),
        ("cf_pct", "CF%", "cf_pct", "pct1", False),
        ("rel_cf_pct", "Rel CF%", "rel_cf_pct", "signed1", False),
        ("hdcf_pct", "HDCF%", "hdcf_pct", "pct1", False),
        ("gf_pct", "GF%", "gf_pct", "pct1", False),
        ("xgf_per_60", "xGF/60", "xgf_per_60", "dec2", False),
        ("xga_per_60", "xGA/60", "xga_per_60", "dec2", True),
        ("blocks", "Blocks", "blocks", "int", False),
        ("hits", "Hits", "hits", "int", False),
        ("takeaways", "Takeaways", "takeaways", "int", False),
        ("giveaways", "Giveaways", "giveaways", "int", True),
    ],
    "Goaltending": [
        ("gsax", "GSAx", "gsax", "signed1", False),
        ("gsax_per_60", "GSAx/60", "gsax_per_60", "dec2", False),
        ("sv_pct", "SV%", "sv_pct", "sv3", False),
        ("gaa", "GAA", "gaa", "dec2", True),
        ("hd_sv_pct", "HD SV%", "hd_sv_pct", "sv3", False),
        ("xga_per_60", "xGA/60", "g_xga_per_60", "dec2", False),
        ("rebound_pct", "Rebound%", "rebound_pct", "pct1", True),
        ("saves", "Saves", "saves", "int", False),
        ("goals_against", "GA", "goals_against", "int", True),
        ("wins", "W", "wins", "int", False),
        ("shutouts", "SO", "shutouts", "int", False),
    ],
}
CATEGORY_TYPES: dict[str, tuple[str, ...]] = {
    "Scoring": ("f", "d"),
    "Shot Quality": ("f", "d"),
    "Play Driving": ("f", "d"),
    "Goaltending": ("g",),
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


def season_id(season: int) -> int:
    """NHL API seasonId for a start-year season (2025 -> 20252026)."""
    return int(f"{season}{season + 1}")


def normalize_team(team: Any) -> str:
    text = str(team or "").strip()
    if not text or text.lower() == "nan":
        return ""
    return TEAM_ALIASES.get(text, text)


def player_type_from_position(position: Any) -> str:
    """Map a raw position code (C, L, R, W, D, G) to a contract player_type."""
    return POSITION_TO_TYPE.get(str(position or "").strip().upper(), "")


def headshot_url(season: Any, team: Any, pid: int) -> Optional[str]:
    """NHL mug URL for a player on a team in a season (200 for the right team)."""
    code = normalize_team(team)
    if not code or pd.isna(season):
        return None
    return MUG_URL.format(season=int(season), next=int(season) + 1, team=code, pid=pid)


def format_value(value: Any, fmt: str) -> str:
    """Format a raw stat value for display per the contract conventions."""
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    try:
        v = float(value)
    except (ValueError, TypeError):
        return ""
    if pd.isna(v):
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
    if fmt == "dec3":
        return f"{v:.3f}"
    if fmt == "signed1":
        rounded = round(v, 1)
        return f"{(rounded if rounded != 0 else 0.0):+.1f}"
    if fmt == "sv3":
        text = f"{v:.3f}"
        return text[1:] if text.startswith("0.") else text
    return str(v)


def format_toi(seconds: Any) -> str:
    """Seconds -> "19:42"."""
    try:
        total = int(round(float(seconds)))
    except (ValueError, TypeError):
        return ""
    return f"{total // 60}:{total % 60:02d}"


def rank_percentiles(series: pd.Series, inverted: bool) -> dict[int, int]:
    """Percentile (1-100) of each non-null value within the series.

    ``inverted`` ranks lower raw values higher (giveaways, goals against).
    """
    s = pd.to_numeric(series, errors="coerce").dropna()
    if s.empty:
        return {}
    ranks = s.rank(method="average", ascending=not inverted, pct=True)
    return {int(pid): max(1, min(100, int(round(pct * 100)))) for pid, pct in ranks.items()}


def _num(row: Any, col: str) -> float:
    val = row.get(col)
    try:
        return float(val) if val is not None and not pd.isna(val) else 0.0
    except (ValueError, TypeError):
        return 0.0


def _scaled(threshold: float, scale: float) -> float:
    """A full-season bar prorated for a season in progress (never below 1)."""
    return max(1, math.ceil(threshold * scale)) if scale < 1 else threshold


def has_opportunity(row: Any, category: str, player_type: str) -> bool:
    """Whether a player has any volume at all in a category.

    The live season ships every player who has played, not just those over the
    qualification bar: the app's "Qualified" filter is a choice the user makes,
    and early in the year nobody is over the full-season bar.
    """
    if player_type not in CATEGORY_TYPES.get(category, ()):
        return False
    if category == "Play Driving":
        return _num(row, "icetime_5v5") > 0
    return _num(row, "games") >= 1 and _num(row, "icetime") > 0


def qualifies(
    row: Any,
    category: str,
    player_type: str,
    season_type: str = "REG",
    career: bool = False,
    scale: float = 1.0,
) -> bool:
    """Whether a player clears the qualification bar for a category.

    Tiers: a full regular season (ice time), a postseason run (games), a career
    (games) and a career postseason (games). ``scale`` prorates only the
    full-season tier for a season still being played (``qualification_scale``).
    """
    if player_type not in CATEGORY_TYPES.get(category, ()):
        return False
    games = _num(row, "games")
    goalie = player_type == "g"
    postseason = season_type == "POST"
    if career:
        if postseason:
            return games >= (CAREER_POST_QUAL_GOALIE_GP if goalie else CAREER_POST_QUAL_SKATER_GP)
        return games >= (CAREER_QUAL_GOALIE_GP if goalie else CAREER_QUAL_SKATER_GP)
    if postseason:
        return games >= (POST_QUAL_GOALIE_GP if goalie else POST_QUAL_SKATER_GP)
    icetime = _num(row, "icetime")
    if goalie:
        return (
            icetime >= _scaled(QUAL_GOALIE_TOI_MIN * 60, scale)
            or games >= _scaled(QUAL_GOALIE_GP, scale)
        )
    if icetime < _scaled(QUAL_SKATER_TOI_MIN * 60, scale):
        return False
    if category == "Play Driving":
        return _num(row, "icetime_5v5") >= _scaled(QUAL_SKATER_5V5_TOI_MIN * 60, scale)
    return True


def qualification_scale(agg: pd.DataFrame, season: int) -> float:
    """Fraction of an 82-game regular season played so far, floored at 0.1.

    Measured as the median club's games played (each club's busiest player), so
    one early game does not move the whole league's bar. Only the live season
    is prorated: every finished season, including the shortened 2012-13 and
    2019-20 ones, keeps exactly the thresholds it is ranked on.
    """
    if season != DEFAULT_SEASON or agg.empty or "games" not in agg.columns:
        return 1.0
    games = pd.to_numeric(agg["games"], errors="coerce")
    if "team" in agg.columns:
        teams = agg["team"].astype(str).str.strip()
        known = games[(teams != "") & (teams.str.lower() != "nan") & games.notna()]
        per_team = known.groupby(teams[known.index]).max()
        played = float(np.floor(per_team.median())) if not per_team.empty else games.max()
    else:
        played = games.max()
    if pd.isna(played) or played <= 0:
        return QUAL_SCALE_FLOOR
    return max(QUAL_SCALE_FLOOR, min(1.0, float(played) / LEAGUE_GAMES))


def _col(df: pd.DataFrame, name: str) -> pd.Series:
    """A numeric column, or an all-NaN series when the source lacks it."""
    if name in df.columns:
        return pd.to_numeric(df[name], errors="coerce")
    return pd.Series(np.nan, index=df.index, dtype="float64")


def _div(numer: pd.Series, denom: pd.Series) -> pd.Series:
    return numer / denom.replace(0, np.nan)


def _sum_situation(raw: pd.DataFrame, situation: str, mapping: dict[str, str]) -> pd.DataFrame:
    """Sum the mapped MoneyPuck columns of one situation to one row per player."""
    sub = raw[raw["situation"] == situation]
    present = {src: dst for src, dst in mapping.items() if src in sub.columns}
    if sub.empty or not present:
        return pd.DataFrame(columns=list(mapping.values()), index=pd.Index([], dtype="int64"))
    nums = sub[list(present)].apply(pd.to_numeric, errors="coerce")
    nums.index = sub["playerId"].astype("int64").values
    return nums.groupby(level=0).sum(min_count=1).rename(columns=present)


def _identity(raw: pd.DataFrame) -> pd.DataFrame:
    """Name, team, position and season of each player's most recent row."""
    sub = raw[raw["situation"] == "all"].copy()
    sub["playerId"] = sub["playerId"].astype("int64")
    latest = sub.sort_values("season").groupby("playerId").tail(1).set_index("playerId")
    out = latest[[c for c in IDENTITY_COLS if c in latest.columns]].copy()
    out = out.rename(columns={"season": "season_last"})
    out["team"] = out["team"].map(normalize_team)
    return out


def skater_totals(raw: pd.DataFrame) -> pd.DataFrame:
    """Additive per-player totals from a MoneyPuck skaters frame (any seasons)."""
    if raw is None or raw.empty:
        return pd.DataFrame()
    out = _identity(raw).join(_sum_situation(raw, "all", SKATER_ALL), how="left")
    out = out.join(_sum_situation(raw, "5on5", SKATER_5V5), how="left")
    out = out.join(_sum_situation(raw, "5on4", SKATER_PP), how="left")
    out["pp_points"] = _col(out, "pp_points").fillna(0)
    out["player_type"] = out["position"].map(player_type_from_position)
    return out[out["player_type"].isin(("f", "d"))]


def goalie_totals(raw: pd.DataFrame) -> pd.DataFrame:
    """Additive per-player totals from a MoneyPuck goalies frame (any seasons)."""
    if raw is None or raw.empty:
        return pd.DataFrame()
    out = _identity(raw).join(_sum_situation(raw, "all", GOALIE_ALL), how="left")
    out["player_type"] = "g"
    return out


def summary_totals(summary: Optional[pd.DataFrame], cols: dict[str, str]) -> pd.DataFrame:
    """Sum an NHL summary frame (any seasons) to one row per player."""
    if summary is None or summary.empty or "playerId" not in summary.columns:
        return pd.DataFrame()
    present = {src: dst for src, dst in cols.items() if src in summary.columns}
    nums = summary[list(present)].apply(pd.to_numeric, errors="coerce")
    nums.index = summary["playerId"].astype("int64").values
    out = nums.groupby(level=0).sum(min_count=1).rename(columns=present)
    if "shootsCatches" in summary.columns:
        hand = summary.dropna(subset=["shootsCatches"])
        hand = hand.assign(playerId=hand["playerId"].astype("int64"))
        out["handedness"] = hand.groupby("playerId")["shootsCatches"].last()
    return out


def derive_skater_metrics(agg: pd.DataFrame) -> None:
    """Add every skater metric column (in place) from the additive totals."""
    hours = _col(agg, "icetime") / 3600
    hours5 = _col(agg, "icetime_5v5") / 3600
    goals = _col(agg, "goals")
    ixg = _col(agg, "ixg")
    agg["assists"] = _col(agg, "assists1") + _col(agg, "assists2")
    agg["primary_points"] = goals + _col(agg, "assists1")
    agg["points_per_60"] = _div(_col(agg, "points"), hours)
    agg["shooting_pct"] = _div(goals, _col(agg, "sog")) * 100
    agg["game_score_per_gp"] = _div(_col(agg, "game_score"), _col(agg, "games"))
    agg["gax"] = goals - ixg
    agg["ixg_per_60"] = _div(ixg, hours)
    agg["shots_per_60"] = _div(_col(agg, "shot_attempts"), hours)
    agg["xg_per_shot"] = _div(ixg, _col(agg, "unblocked"))

    xgf, xga = _col(agg, "xgf_5v5"), _col(agg, "xga_5v5")
    cf, ca = _col(agg, "cf_5v5"), _col(agg, "ca_5v5")
    gf, ga = _col(agg, "gf_5v5"), _col(agg, "ga_5v5")
    hdf, hda = _col(agg, "hdf_5v5"), _col(agg, "hda_5v5")
    off_xgf, off_xga = _col(agg, "off_xgf_5v5"), _col(agg, "off_xga_5v5")
    off_cf, off_ca = _col(agg, "off_cf_5v5"), _col(agg, "off_ca_5v5")
    agg["xgf_pct"] = _div(xgf, xgf + xga) * 100
    agg["rel_xgf_pct"] = agg["xgf_pct"] - _div(off_xgf, off_xgf + off_xga) * 100
    agg["cf_pct"] = _div(cf, cf + ca) * 100
    agg["rel_cf_pct"] = agg["cf_pct"] - _div(off_cf, off_cf + off_ca) * 100
    agg["hdcf_pct"] = _div(hdf, hdf + hda) * 100
    agg["gf_pct"] = _div(gf, gf + ga) * 100
    agg["xgf_per_60"] = _div(xgf, hours5)
    agg["xga_per_60"] = _div(xga, hours5)


def derive_goalie_metrics(agg: pd.DataFrame) -> None:
    """Add every goalie metric column (in place) from the additive totals."""
    hours = _col(agg, "icetime") / 3600
    xga = _col(agg, "xgoals_against")
    ga = _col(agg, "goals_against")
    shots = _col(agg, "shots_against")
    agg["gsax"] = xga - ga
    agg["gsax_per_60"] = _div(agg["gsax"], hours)
    agg["sv_pct"] = 1 - _div(ga, shots)
    agg["gaa"] = _div(ga, hours)
    agg["hd_sv_pct"] = 1 - _div(_col(agg, "hd_goals_against"), _col(agg, "hd_shots_against"))
    agg["g_xga_per_60"] = _div(xga, hours)
    agg["rebound_pct"] = _div(_col(agg, "rebounds_against"), shots) * 100
    agg["saves"] = shots - ga


def build_agg(
    skaters_raw: Optional[pd.DataFrame],
    goalies_raw: Optional[pd.DataFrame],
    skater_summary: Optional[pd.DataFrame] = None,
    goalie_summary: Optional[pd.DataFrame] = None,
) -> pd.DataFrame:
    """One id-indexed row per player with totals, identity and every metric.

    Pure. The raw frames may span several seasons (the career rollup passes the
    whole range), because every column is additive and every rate is derived
    after the sum.
    """
    parts = [p for p in (skater_totals(skaters_raw), goalie_totals(goalies_raw)) if not p.empty]
    if not parts:
        return pd.DataFrame()
    agg = pd.concat(parts, sort=False)
    # A player in both files (an emergency goalie) keeps his busier role.
    agg = agg.sort_values("icetime", ascending=False)
    agg = agg[~agg.index.duplicated(keep="first")].sort_index()
    agg.index.name = "pid"

    for summary, cols in ((skater_summary, NHL_SKATER_COLS), (goalie_summary, NHL_GOALIE_COLS)):
        extra = summary_totals(summary, cols)
        if extra.empty:
            continue
        extra = extra[~extra.index.duplicated(keep="first")]
        fresh = extra.drop(columns=[c for c in extra.columns if c in agg.columns], errors="ignore")
        agg = agg.join(fresh, how="left")
        if "handedness" in extra.columns:
            hand = extra["handedness"].reindex(agg.index)
            existing = agg["handedness"] if "handedness" in agg.columns else pd.Series(np.nan, index=agg.index)
            agg["handedness"] = existing.fillna(hand)

    derive_skater_metrics(agg)
    derive_goalie_metrics(agg)
    if "handedness" not in agg.columns:
        agg["handedness"] = ""
    agg["handedness"] = agg["handedness"].fillna("").astype(str)
    agg["image_url"] = [
        headshot_url(season, team, int(pid))
        for pid, season, team in zip(agg.index, agg["season_last"], agg["team"])
    ]
    return agg


def _int_text(value: float) -> str:
    return str(int(round(value)))


def build_standard_stats(row: Any) -> list[dict[str, str]]:
    """Assemble the standard_stats jsonb array from an aggregated row.

    Values come from MoneyPuck where it has them, and from the NHL summary for
    the fields it lacks; a field with no source is omitted rather than zeroed.
    """
    stats: list[dict[str, str]] = []

    def add(label: str, value: str) -> None:
        stats.append({"id": f"std-{label}", "label": label, "value": value})

    def has(col: str) -> bool:
        val = row.get(col)
        return val is not None and not pd.isna(val)

    def add_int(label: str, col: str, signed: bool = False) -> None:
        if has(col):
            value = float(row.get(col))
            add(label, f"{int(round(value)):+d}" if signed and round(value) != 0 else _int_text(value))

    games = _num(row, "games")
    add("GP", _int_text(games))
    if row.get("player_type") == "g":
        add_int("GS", "gs")
        add_int("W", "wins")
        add_int("L", "losses")
        add_int("OT", "ot_losses")
        if has("gaa"):
            add("GAA", format_value(row.get("gaa"), "dec2"))
        if has("sv_pct"):
            add("SV%", format_value(row.get("sv_pct"), "sv3"))
        add_int("SO", "shutouts")
        add_int("SA", "shots_against")
        if has("saves"):
            add("SV", _int_text(_num(row, "saves")))
        return stats

    add_int("G", "goals")
    add("A", _int_text(_num(row, "assists1") + _num(row, "assists2")))
    add_int("P", "points")
    add_int("+/-", "plus_minus", signed=True)
    pim = row.get("pim_nhl") if has("pim_nhl") else row.get("pim_mp")
    if pim is not None and not pd.isna(pim):
        add("PIM", _int_text(float(pim)))
    add_int("PPG", "ppg")
    add_int("PPP", "ppp")
    add_int("SHG", "shg")
    add_int("GWG", "gwg")
    add_int("SOG", "sog")
    if has("shooting_pct"):
        add("Sh%", format_value(row.get("shooting_pct"), "pct1"))
    if games > 0 and has("icetime"):
        add("TOI/GP", format_toi(_num(row, "icetime") / games))
    add_int("Hits", "hits")
    add_int("Blk", "blocks")
    faceoffs = _num(row, "fo_won") + _num(row, "fo_lost")
    if faceoffs >= MIN_FACEOFFS_FOR_STANDARD_STAT:
        add("FO%", format_value(_num(row, "fo_won") / faceoffs * 100, "pct1"))
    return stats


def _metric_id(category: str, pid: int, mid: str) -> str:
    return f"{category.lower().replace(' ', '-')}-{pid}-{mid}"


def build_snapshot_rows(
    agg: pd.DataFrame,
    season: int,
    now: datetime,
    season_type: str = "REG",
    qual_scale: float = 1.0,
    live: bool = False,
) -> list[dict]:
    """Build player_snapshots rows from an aggregated (id-indexed) DataFrame.

    Past seasons: percentiles are computed per category inside each cohort
    (forwards, defensemen, goalies) among qualified players only, and a player
    receives every category's metrics for which he qualifies.

    The live season (``live``): no minimum. Every player with any volume in a
    category is ranked and shipped, and each metric carries ``qualified`` (the
    bar prorated by ``qual_scale``) so the app's Qualified filter still works.
    """
    if agg.empty:
        return []

    now_str = now.isoformat()
    players: dict[int, dict] = {}
    # The career rollup reuses this function wholesale and differs only in where
    # the qualification bar sits.
    career = season == ALL_TIME_SEASON

    def _ensure(pid: int, row: Any) -> dict:
        if pid not in players:
            image = row.get("image_url")
            players[pid] = {
                "id": pid,
                "name": str(row.get("name") or ""),
                "team": str(row.get("team") or "TBD"),
                "position": str(row.get("position") or ""),
                "handedness": str(row.get("handedness") or ""),
                "image_url": image if isinstance(image, str) and image else None,
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
        cohort_types = CATEGORY_TYPES[category]
        for ptype in cohort_types:
            cohort = agg[agg["player_type"] == ptype]
            qual_ids = {
                int(pid) for pid, row in cohort.iterrows()
                if qualifies(row, category, ptype, season_type, career=career, scale=qual_scale)
            }
            if live:
                ranked_ids = [
                    int(pid) for pid, row in cohort.iterrows()
                    if has_opportunity(row, category, ptype)
                ]
            else:
                ranked_ids = sorted(qual_ids)
            if not ranked_ids:
                continue
            sub = agg.loc[ranked_ids]
            pct_maps = {
                mid: rank_percentiles(sub[col], inverted)
                for mid, _label, col, _fmt, inverted in defs
                if col in sub.columns
            }
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
                        "id": _metric_id(category, pid, mid),
                        "label": label,
                        "value": format_value(raw, fmt),
                        "percentile": percentile,
                        "category": category,
                    }
                    if live:
                        metric["qualified"] = pid in qual_ids
                    player["metrics"].append(metric)

    return [p for p in players.values() if p["metrics"]]


# --------------------------------------------------------------------------- #
# Network loaders
# --------------------------------------------------------------------------- #
def _to_pandas(frame: Any) -> pd.DataFrame:
    """Kept for refresh.py: every loader here already returns pandas."""
    return frame


def _cache_file(url: str, params: Optional[dict]) -> Path:
    key = url + "?" + "&".join(f"{k}={v}" for k, v in sorted((params or {}).items()))
    return CACHE_DIR / (hashlib.sha1(key.encode()).hexdigest() + ".bin")


def http_get(url: str, params: Optional[dict] = None, cache: bool = False) -> Optional[bytes]:
    """GET with a polite User-Agent, retries and an optional on-disk cache.

    Returns None on a 404 (a phase that has no file yet, e.g. playoffs in
    October). ``cache`` reads and writes ``backend/.cache/`` keyed by URL and
    parameters; callers enable it only for finished seasons.
    """
    path = _cache_file(url, params)
    if cache and os.environ.get("HOCKEY_NO_CACHE") != "1" and path.exists():
        return path.read_bytes()
    last_error: Optional[Exception] = None
    for attempt in range(1, REQUEST_ATTEMPTS + 1):
        try:
            response = requests.get(
                url, params=params, headers={"User-Agent": USER_AGENT}, timeout=REQUEST_TIMEOUT
            )
            time.sleep(REQUEST_PAUSE_SECONDS)
            if response.status_code == 404:
                return None
            response.raise_for_status()
            if cache:
                CACHE_DIR.mkdir(parents=True, exist_ok=True)
                path.write_bytes(response.content)
            return response.content
        except requests.RequestException as error:
            last_error = error
            logger.warning("GET %s failed (attempt %d): %s", url, attempt, error)
            time.sleep(2 ** attempt)
    raise RuntimeError(f"GET {url} failed after {REQUEST_ATTEMPTS} attempts") from last_error


def moneypuck_columns() -> set[str]:
    wanted = {"playerId", "season", "name", "team", "position", "situation"}
    for mapping in (SKATER_ALL, SKATER_5V5, SKATER_PP, GOALIE_ALL):
        wanted |= set(mapping)
    return wanted


def load_moneypuck(kind: str, season: int, season_type: str, cache: bool = False) -> pd.DataFrame:
    """MoneyPuck season summary (``skaters`` or ``goalies``); empty when absent."""
    folder, _game_type = PHASES[season_type]
    url = MONEYPUCK_URL.format(season=season, phase=folder, kind=kind)
    content = http_get(url, cache=cache)
    if not content:
        return pd.DataFrame()
    wanted = moneypuck_columns()
    frame = pd.read_csv(io.BytesIO(content), usecols=lambda c: c in wanted)
    logger.info("MoneyPuck %s %s %s: %d rows", kind, season, season_type, len(frame))
    return frame


def load_nhl_summary(kind: str, season: int, season_type: str, cache: bool = False) -> pd.DataFrame:
    """NHL stats REST ``skater`` / ``goalie`` summary, paginated 100 at a time."""
    _folder, game_type = PHASES[season_type]
    url = NHL_SUMMARY_URL.format(kind=kind)
    expression = f"seasonId={season_id(season)} and gameTypeId={game_type}"
    rows: list[dict] = []
    start = 0
    while True:
        params = {
            "limit": NHL_PAGE_SIZE, "start": start,
            "sort": "playerId", "cayenneExp": expression,
        }
        content = http_get(url, params=params, cache=cache)
        if not content:
            break
        payload = json.loads(content)
        page = payload.get("data", [])
        rows.extend(page)
        start += NHL_PAGE_SIZE
        if len(page) < NHL_PAGE_SIZE or start >= int(payload.get("total", 0)):
            break
    logger.info("NHL %s summary %s %s: %d rows", kind, season, season_type, len(rows))
    return pd.DataFrame(rows)


def load_season_sources(
    season: int,
    season_type: str,
    cache: bool,
    enrichment_status: Optional[dict[str, str]] = None,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Skater and goalie MoneyPuck frames plus the two NHL summary frames.

    The NHL summary is an enrichment: with ``enrichment_status`` supplied a
    failure publishes MoneyPuck-only rows and records ``degraded``; without it
    (the CLI backfill) a failure raises.
    """
    skaters = load_moneypuck("skaters", season, season_type, cache)
    goalies = load_moneypuck("goalies", season, season_type, cache)
    empty = pd.DataFrame()
    if skaters.empty and goalies.empty:
        return skaters, goalies, empty, empty
    try:
        sk_sum = load_nhl_summary("skater", season, season_type, cache)
        g_sum = load_nhl_summary("goalie", season, season_type, cache)
    except Exception:
        if enrichment_status is None:
            raise
        logger.exception("Failed to load NHL summary; publishing MoneyPuck stats as degraded.")
        enrichment_status["summary"] = "degraded"
        return skaters, goalies, empty, empty
    if enrichment_status is not None:
        enrichment_status["summary"] = "ready" if not (sk_sum.empty and g_sum.empty) else "pending"
    return skaters, goalies, sk_sum, g_sum


def build_agg_for_season(
    season: int,
    season_type: str = "REG",
    live: bool = False,
    enrichment_status: Optional[dict[str, str]] = None,
) -> pd.DataFrame:
    """Fetch MoneyPuck and NHL data and produce the fully-merged aggregate frame.

    Finished seasons are cached on disk (backend/.cache/) so a backfill and the
    career rollup download each file once; the live season always hits the
    network. Returns an empty frame when the phase has no file yet.
    """
    cache = season < DEFAULT_SEASON and not live
    skaters, goalies, sk_sum, g_sum = load_season_sources(
        season, season_type, cache, enrichment_status
    )
    agg = build_agg(skaters, goalies, sk_sum, g_sum)
    logger.info("Aggregated %s %s to %d players", season, season_type, len(agg))
    return agg


def chunks(lst: list, n: int) -> Iterator[list]:
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


def stored_ids(client: Any, season: int, phase: str, page_size: int = 1000) -> list[int]:
    """Every player id stored for (season, phase), paged past PostgREST's row cap."""
    ids: list[int] = []
    offset = 0
    while True:
        page = (
            client.table("player_snapshots")
            .select("id")
            .eq("season", season)
            .eq("season_type", phase)
            .order("id")
            .range(offset, offset + page_size - 1)
            .execute()
            .data
        )
        ids.extend(row["id"] for row in page)
        if len(page) < page_size:
            return ids
        offset += page_size


def prune_orphans(client: Any, rows: list[dict], season: int, phase: str) -> int:
    """Delete stored rows for (season, phase) that this run no longer produced."""
    kept = {row["id"] for row in rows}
    orphans = [pid for pid in stored_ids(client, season, phase) if pid not in kept]
    for batch in chunks(orphans, 100):
        (
            client.table("player_snapshots")
            .delete()
            .in_("id", batch)
            .eq("season", season)
            .eq("season_type", phase)
            .execute()
        )
    return len(orphans)


def upsert_rows(client: Any, rows: list[dict], batch_size: int = 150) -> None:
    for i, batch in enumerate(chunks(rows, batch_size)):
        logger.info("Upserting batch %d (%d rows)...", i + 1, len(batch))
        client.table("player_snapshots").upsert(batch, on_conflict="id,season,season_type").execute()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)

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
    logger.info("=== Ingesting NHL season %s (%s) ===", season, ", ".join(phases))
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
                by_type[row["player_type"]] = by_type.get(row["player_type"], 0) + 1
            logger.info("Built %d %s snapshots by type: %s", len(rows), phase, by_type)

            upsert_rows(client, rows)
            logger.info("Upserted %d player snapshots for %s %s.", len(rows), season, phase)

            sanity_floor = 20 if phase == "POST" else 150
            if len(rows) >= sanity_floor:
                pruned = prune_orphans(client, rows, season, phase)
                logger.info("Pruned %d stale/unqualified rows for %s %s.", pruned, season, phase)
            else:
                logger.warning("Only %d %s rows built, skipping prune.", len(rows), phase)
        if not any_rows:
            logger.error("No snapshots built for %s.", season)
            sys.exit(1)
    except Exception:
        logger.exception("Failed to process season %s", season)
        sys.exit(1)


if __name__ == "__main__":
    main()
