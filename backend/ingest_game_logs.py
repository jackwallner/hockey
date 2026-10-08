"""
Per-player-per-game NFL ingest. Powers player profiles and the shared 3/5/8
week Trends windows.

Reads weekly ``load_player_stats`` rows (one row per player per game), joins
``load_schedules`` for the game date, and upserts one row per player per game
into Supabase ``public.player_game_logs``.
Regular season and postseason rows are stored separately.

Metrics are stored as raw per-game counts, never pre-divided rates: pass_yards,
attempts, carries, etc. go in as-is, not as yards-per-attempt. That's what lets
``rollup_recent_form.py`` recompute an exact window rate from summed
numerators and denominators instead of averaging already-averaged numbers,
which is the same reason the baseball app's game logs store counts. Passing,
rushing and receiving EPA are kept as three separate values (not just the
summed ``epa_total``) so a per-category recent-form rate can be derived later;
``epa_total`` stays too for the existing RecentFormCard.

Optionally folds in a handful of Next Gen Stats weekly metrics (CPOE, time to
throw, separation, YAC above expectation, rush yards over expected) that have
no other per-game source. The join is on (player_id, season, week) against
NGS's weekly (week > 0) rows; it's skipped for seasons before NGS existed.

Incremental by default: starts from the latest game_date already in the DB for
the season. Pass ``--full`` to re-ingest the whole season (also needed after a
metric-set change, since incremental only reaches new games). ``--season N``
overrides the resolved season.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import argparse
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Optional

import nflreadpy as nfl
import pandas as pd
import polars as pl
from dotenv import load_dotenv
from supabase import create_client

from ingest import NGS_FIRST_SEASON, gsis_to_id, player_type_from_position, resolve_season

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Per-game metric columns carried into the ``metrics`` jsonb (source -> key),
# stored as raw counts. Grouped by category to mirror NFL_CONTRACT.md; every
# column here is summed straight across a recent-form window, never averaged
# per-game, so the window's rates can be recomputed exactly from the sums.
METRIC_COLS = {
    # Passing.
    "passing_yards": "passing_yards",
    "passing_tds": "passing_tds",
    "passing_interceptions": "interceptions",
    "completions": "completions",
    "attempts": "attempts",
    "sacks_suffered": "sacks_suffered",
    "sack_yards_lost": "sack_yards_lost",
    "passing_first_downs": "passing_first_downs",
    "passing_air_yards": "passing_air_yards",
    # Rushing.
    "carries": "carries",
    "rushing_yards": "rushing_yards",
    "rushing_tds": "rushing_tds",
    "rushing_first_downs": "rushing_first_downs",
    "rushing_fumbles": "rushing_fumbles",
    "rushing_fumbles_lost": "rushing_fumbles_lost",
    # Receiving.
    "receptions": "receptions",
    "targets": "targets",
    "receiving_yards": "receiving_yards",
    "receiving_tds": "receiving_tds",
    "receiving_yards_after_catch": "receiving_yac",
    "receiving_first_downs": "receiving_first_downs",
    "receiving_air_yards": "receiving_air_yards",
    "receiving_fumbles": "receiving_fumbles",
    # Defense.
    "def_interceptions": "def_interceptions",
    "def_sacks": "def_sacks",
    "def_tackles_solo": "def_tackles_solo",
    "def_tackle_assists": "def_tackle_assists",
    "def_pass_defended": "def_pass_defended",
    "def_fumbles_forced": "def_fumbles_forced",
    "def_tackles_for_loss": "def_tackles_for_loss",
    "def_qb_hits": "def_qb_hits",
    # EPA, kept per-category (not just summed) so recent form can report a
    # per-category rate the way the season snapshot does.
    "passing_epa": "passing_epa",
    "rushing_epa": "rushing_epa",
    "receiving_epa": "receiving_epa",
}
EPA_COLS = ["passing_epa", "rushing_epa", "receiving_epa"]

# Weekly Next Gen Stats columns worth folding into the game log (source ->
# key). Season-only NGS metrics that have no clean per-game denominator
# (aggressiveness, avg_intended_air_yards) are deliberately left out — see the
# module docstring.
NGS_PASSING_COLS = {
    "completion_percentage_above_expectation": "cpoe",
    "avg_time_to_throw": "avg_time_to_throw",
}
NGS_RUSHING_COLS = {
    "rush_yards_over_expected": "rush_yoe",
}
NGS_RECEIVING_COLS = {
    "avg_separation": "avg_separation",
    "avg_yac_above_expectation": "avg_yac_above_expectation",
}
NGS_STORE_PLACES = 2  # storage precision; the rollup re-rounds its own output.


def _to_pandas(frame: Any) -> pd.DataFrame:
    if isinstance(frame, pl.DataFrame):
        return frame.to_pandas()
    return frame


def _num(row: pd.Series, col: str) -> float:
    val = row.get(col)
    try:
        return float(val) if val is not None and not pd.isna(val) else 0.0
    except (ValueError, TypeError):
        return 0.0


def schedule_map(schedule: pd.DataFrame) -> dict[str, str]:
    """Map game_id -> gameday (ISO date string)."""
    out: dict[str, str] = {}
    for _, row in schedule.iterrows():
        gid = row.get("game_id")
        day = row.get("gameday")
        if gid is not None and day is not None and not pd.isna(day):
            out[str(gid)] = str(day)[:10]
    return out


def ngs_weekly_lookup(ngs: pd.DataFrame, cols: dict[str, str]) -> dict[tuple[str, int], dict[str, float]]:
    """Map (gsis_id, week) -> {renamed metric: value} from a weekly NGS frame.

    Callers pass only week > 0 rows; week 0 is NGS's own season-aggregate row
    and isn't a per-game data point. Pure: no network, easy to unit test.
    """
    if ngs is None or ngs.empty:
        return {}
    present = {src: dst for src, dst in cols.items() if src in ngs.columns}
    if not present or "player_gsis_id" not in ngs.columns or "week" not in ngs.columns:
        return {}

    out: dict[tuple[str, int], dict[str, float]] = {}
    for _, row in ngs.iterrows():
        gsis = row.get("player_gsis_id")
        week = row.get("week")
        if gsis is None or week is None or pd.isna(week):
            continue
        values: dict[str, float] = {}
        for src, dst in present.items():
            raw = row.get(src)
            if raw is None or pd.isna(raw):
                continue
            values[dst] = round(float(raw), NGS_STORE_PLACES)
        if values:
            out[(str(gsis), int(week))] = values
    return out


def build_game_log_rows(
    weekly: pd.DataFrame,
    sched: dict[str, str],
    season: int,
    now: datetime,
    ngs_pass: Optional[dict[tuple[str, int], dict[str, float]]] = None,
    ngs_rush: Optional[dict[tuple[str, int], dict[str, float]]] = None,
    ngs_rec: Optional[dict[tuple[str, int], dict[str, float]]] = None,
) -> list[dict]:
    """Build one player_game_logs row per player per game (pure)."""
    df = weekly[weekly["season"] == season].copy()
    if df.empty:
        return []

    ngs_pass = ngs_pass or {}
    ngs_rush = ngs_rush or {}
    ngs_rec = ngs_rec or {}

    now_str = now.isoformat()
    rows: list[dict] = []

    def defensive_involvement(r: pd.Series) -> float:
        return (
            _num(r, "def_tackles_solo") + _num(r, "def_tackle_assists")
            + _num(r, "def_sacks") + _num(r, "def_interceptions")
            + _num(r, "def_pass_defended") + _num(r, "def_fumbles_forced")
        )

    for _, r in df.iterrows():
        pid = gsis_to_id(r.get("player_id"))
        if pid is None:
            continue
        game_date = sched.get(str(r.get("game_id")))
        if not game_date:
            continue

        week_raw = r.get("week")
        week = int(week_raw) if week_raw is not None and not pd.isna(week_raw) else None

        plays = int(_num(r, "attempts") + _num(r, "carries") + _num(r, "targets"))
        touches = int(_num(r, "completions") + _num(r, "carries") + _num(r, "receptions"))
        player_type = player_type_from_position(r.get("position"), r.get("position_group"))

        if plays == 0 and defensive_involvement(r) == 0:
            continue

        metrics: dict[str, Any] = {}
        for src, key in METRIC_COLS.items():
            if src in r:
                # EPA is a small-magnitude float where 2 decimal places loses
                # real precision across a summed window; everything else is a
                # whole-number or near-whole-number count.
                places = 3 if src in EPA_COLS else 2
                metrics[key] = round(_num(r, src), places)
        epa_total = sum(_num(r, c) for c in EPA_COLS if c in r)
        metrics["epa_total"] = round(epa_total, 3)

        if week is not None:
            gsis = str(r.get("player_id"))
            for lookup in (ngs_pass, ngs_rush, ngs_rec):
                extra = lookup.get((gsis, week))
                if extra:
                    metrics.update(extra)

        rows.append({
            "player_id": pid,
            "season": season,
            "season_type": str(r.get("season_type") or "REG"),
            # Keep the upstream game identity alongside the date.  The legacy
            # primary key remains date based for app compatibility, while the
            # refresh publisher uses this value to prove that a new source
            # generation did not silently drop a game already in production.
            "game_id": str(r.get("game_id") or ""),
            "game_date": game_date,
            "player_type": player_type or "def",
            "team": str(r.get("team") or ""),
            "opponent": str(r.get("opponent_team") or ""),
            "week": week,
            "plays": plays,
            "touches": touches,
            "metrics": metrics,
            "updated_at": now_str,
        })

    return rows


def _latest_game_date(client, season: int) -> Optional[str]:
    resp = (
        client.table("player_game_logs")
        .select("game_date")
        .eq("season", season)
        .order("game_date", desc=True)
        .limit(1)
        .execute()
    )
    if not resp.data:
        return None
    return str(resp.data[0]["game_date"])[:10]


def _upsert(client, rows: list[dict]) -> None:
    batch_size = 200
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        try:
            client.table("player_game_logs").upsert(
                batch,
                on_conflict=(
                    "player_id,season,season_type,game_date,player_type"
                ),
            ).execute()
        except Exception:
            logger.exception("Upsert failed for batch starting at %d", i)
            raise


def _load_ngs_lookups(
    season: int,
    enrichment_status: Optional[dict[str, str]] = None,
) -> tuple[dict, dict, dict]:
    """Load and index the three weekly NGS frames, or empty dicts if unusable.

    NGS data doesn't exist before 2016, and a fetch failure here shouldn't
    fail the whole ingest — the game log is still useful without these five
    extra metrics, so this degrades gracefully rather than raising.
    """
    if season < NGS_FIRST_SEASON:
        logger.info("Skipping weekly Next Gen Stats for %s (available since %s).", season, NGS_FIRST_SEASON)
        if enrichment_status is not None:
            enrichment_status["ngs"] = "not_applicable"
        return {}, {}, {}
    try:
        logger.info("Loading weekly Next Gen Stats for %s...", season)
        ngs_pass = _to_pandas(nfl.load_nextgen_stats([season], stat_type="passing"))
        ngs_rush = _to_pandas(nfl.load_nextgen_stats([season], stat_type="rushing"))
        ngs_rec = _to_pandas(nfl.load_nextgen_stats([season], stat_type="receiving"))
        pass_lookup = ngs_weekly_lookup(ngs_pass[ngs_pass["week"] > 0], NGS_PASSING_COLS)
        rush_lookup = ngs_weekly_lookup(ngs_rush[ngs_rush["week"] > 0], NGS_RUSHING_COLS)
        rec_lookup = ngs_weekly_lookup(ngs_rec[ngs_rec["week"] > 0], NGS_RECEIVING_COLS)
        logger.info(
            "  NGS weekly rows indexed: passing=%d rushing=%d receiving=%d",
            len(pass_lookup), len(rush_lookup), len(rec_lookup),
        )
        if enrichment_status is not None:
            enrichment_status["ngs"] = "ready" if any(
                (pass_lookup, rush_lookup, rec_lookup)
            ) else "pending"
        return pass_lookup, rush_lookup, rec_lookup
    except Exception:
        logger.exception("Failed to load weekly Next Gen Stats; continuing without them.")
        if enrichment_status is not None:
            enrichment_status["ngs"] = "degraded"
        return {}, {}, {}


def run(full: bool = False, cli_season: Optional[int] = None) -> None:
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)
    season = resolve_season(cli_season)
    now = datetime.now(UTC)

    logger.info("Loading weekly stats + schedule for %s...", season)
    weekly = _to_pandas(nfl.load_player_stats([season]))
    sched = schedule_map(_to_pandas(nfl.load_schedules([season])))

    ngs_pass_lookup, ngs_rush_lookup, ngs_rec_lookup = _load_ngs_lookups(season)

    rows = build_game_log_rows(weekly, sched, season, now, ngs_pass_lookup, ngs_rush_lookup, ngs_rec_lookup)
    logger.info("Built %d game-log rows for %s", len(rows), season)

    if not full:
        latest = _latest_game_date(client, season)
        if latest:
            # Re-ingest the latest known day too (late/updated games).
            before = len(rows)
            rows = [r for r in rows if r["game_date"] >= latest]
            logger.info("Incremental: keeping %d/%d rows on/after %s", len(rows), before, latest)

    if not rows:
        logger.info("Nothing to ingest for %s.", season)
        return

    _upsert(client, rows)
    if full:
        cutoff = now.isoformat()
        response = (
            client.table("player_game_logs")
            .delete()
            .eq("season", season)
            .lt("updated_at", cutoff)
            .execute()
        )
        logger.info(
            "Pruned %d stale game-log rows for %s.",
            len(response.data or []),
            season,
        )
    logger.info("Done. Upserted %d game-log rows for %s.", len(rows), season)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="Re-ingest the whole season, not incremental.")
    parser.add_argument("--season", type=int, default=None, help="Season (starting year) to ingest.")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    args = _parse_args()
    run(full=args.full, cli_season=args.season)
