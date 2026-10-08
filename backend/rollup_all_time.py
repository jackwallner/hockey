"""
Career ("All Time") rollup.

Writes one extra ``player_snapshots`` row per player under the sentinel season
``0``, aggregating every year from ``OLDEST_SUPPORTED_SEASON`` to the current
season into a single career line, with percentiles ranked inside the career
cohort rather than against any one season.

Why a stored row rather than an app-side mode: the leaderboards, Teams, Compare
and the player page all read from ``selectedSeason``, so modelling the career
view as just another season means every one of them gets it with no all-time
branch of its own - and the numbers are computed once here instead of on every
device. It also means the formatting, the qualification thresholds and the
percentile logic are literally the same code that produces a normal season,
which is the only way the two can't drift.

This deliberately re-reads the weekly feed rather than summing the season
snapshots already in Supabase. Snapshots hold *formatted* values ("6.2%") for
*qualified* players only, so summing them would compound rounding and silently
drop every season a player fell short of the cut - a career total that omits a
player's rookie year is worse than no career total.

Usage:
  python backend/rollup_all_time.py                 # 2000..current
  python backend/rollup_all_time.py --from 2010     # narrower window
  python backend/rollup_all_time.py --dry-run       # build, don't write

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

import argparse
import logging
import os
import sys
from datetime import datetime, timezone

import nflreadpy as nfl
import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

from ingest import (
    ALL_TIME_SEASON,
    NGS_FIRST_SEASON,
    OLDEST_SUPPORTED_SEASON,
    PFR_DEF_FIRST_SEASON,
    _to_pandas,
    aggregate_seasons,
    apply_def_rate_thresholds,
    build_snapshot_rows,
    chunks,
    load_headshots,
    load_pfr_defense,
    merge_ngs,
    resolve_season,
)

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)


def load_all_weekly(first: int, last: int) -> pd.DataFrame:
    """Weekly player stats for the whole range, concatenated.

    Seasons are fetched one at a time rather than in a single call so a gap in
    one year can't take the whole rollup down, and so progress is visible in the
    log - this walks twenty-odd seasons.
    """
    frames: list[pd.DataFrame] = []
    for season in range(first, last + 1):
        try:
            frame = _to_pandas(nfl.load_player_stats([season]))
        except Exception:
            logger.exception("Failed to load weekly stats for %s; skipping.", season)
            continue
        if frame is None or frame.empty:
            logger.warning("No weekly rows for %s.", season)
            continue
        logger.info("Loaded %s: %d weekly rows", season, len(frame))
        frames.append(frame)
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def build_career_agg(
    first: int,
    last: int,
    season_type: str = "REG",
) -> pd.DataFrame:
    """Aggregate the full range into one career row per player."""
    weekly = load_all_weekly(first, last)
    if weekly.empty:
        return weekly

    # `aggregate_seasons` filters to one season, so the career pass runs with the
    # season column overwritten to the sentinel. Everything downstream of that
    # filter - the sums, the derived rates, the targets-reliability detection -
    # is season-agnostic and works unchanged over the pooled rows.
    weekly = weekly.copy()
    weekly["season"] = ALL_TIME_SEASON
    agg = aggregate_seasons(weekly, ALL_TIME_SEASON, season_type)
    if agg.empty:
        return agg
    logger.info("Career aggregate: %d players", len(agg))

    # Next Gen Stats and PFR advanced defence only exist for part of the range,
    # so a career figure from them would silently mean "since 2016" / "since
    # 2018" while sitting next to a genuine career total. Summing NGS counting
    # stats across seasons is fine (RYOE is yardage); the averages are pooled by
    # the same volume weighting a single season uses.
    ngs_first = max(first, NGS_FIRST_SEASON)
    if ngs_first <= last and season_type == "REG":
        agg = _merge_career_ngs(agg, ngs_first, last)

    pfr_first = max(first, PFR_DEF_FIRST_SEASON)
    if pfr_first <= last and season_type == "REG":
        agg = _merge_career_pfr_defense(agg, pfr_first, last)

    headshots = load_headshots()
    agg["image_url"] = [headshots.get(int(pid)) for pid in agg.index]
    return agg


def _merge_career_ngs(agg: pd.DataFrame, first: int, last: int) -> pd.DataFrame:
    """Pool per-season NGS rows into one career row, then merge as usual."""
    frames: dict[str, list[pd.DataFrame]] = {"passing": [], "rushing": [], "receiving": []}
    for season in range(first, last + 1):
        for stat_type in frames:
            try:
                frame = _to_pandas(nfl.load_nextgen_stats([season], stat_type=stat_type))
            except Exception:
                logger.exception("Failed NGS %s %s; skipping.", stat_type, season)
                continue
            if frame is not None and not frame.empty:
                frames[stat_type].append(frame)

    # Which NGS column each per-season average should be weighted by, and which
    # columns are totals to be added rather than averaged. Getting this wrong is
    # not a rounding difference: RYOE is a *yardage total*, so averaging it across
    # eight seasons reports one season's worth of yards as a career figure.
    weights = {"passing": "attempts", "rushing": "rush_attempts", "receiving": "targets"}
    totals = {"rush_yards_over_expected", "expected_rush_yards", "rush_yards",
              "rush_attempts", "rush_touchdowns", "attempts", "pass_yards",
              "pass_touchdowns", "interceptions", "completions", "receptions",
              "targets", "yards", "rec_touchdowns"}

    def pooled(stat_type: str) -> pd.DataFrame:
        parts = frames[stat_type]
        if not parts:
            return pd.DataFrame()
        out = pd.concat(parts, ignore_index=True)
        # merge_ngs selects on (season, season_type, week == 0); the season-level
        # NGS rows are already the week-0 summaries, so relabelling the season is
        # all that is needed for it to see them as one cohort.
        out = out[out["week"] == 0].copy()
        out["season"] = ALL_TIME_SEASON

        weight_col = weights[stat_type]
        numeric = [c for c in out.select_dtypes(include="number").columns
                   if c not in {"season", "week"}]
        keys = ["player_gsis_id", "season", "season_type"]

        grouped = out.groupby(keys, as_index=False)[
            [c for c in numeric if c in totals]
        ].sum(min_count=1)

        averaged = [c for c in numeric if c not in totals]
        if averaged and weight_col in out.columns:
            w = out[keys + averaged + [weight_col]].copy()
            w[weight_col] = pd.to_numeric(w[weight_col], errors="coerce")
            w = w[w[weight_col] > 0]
            if not w.empty:
                for column in averaged:
                    w["_p"] = pd.to_numeric(w[column], errors="coerce") * w[weight_col]
                    sums = w.groupby(keys, as_index=False)[["_p", weight_col]].sum()
                    sums[column] = sums["_p"] / sums[weight_col].replace(0, pd.NA)
                    grouped = grouped.merge(sums[keys + [column]], on=keys, how="left")

        grouped["week"] = 0
        return grouped

    return merge_ngs(
        agg,
        pooled("passing"),
        pooled("rushing"),
        pooled("receiving"),
        ALL_TIME_SEASON,
        "REG",
    )


def _merge_career_pfr_defense(agg: pd.DataFrame, first: int, last: int) -> pd.DataFrame:
    """Sum career pressures and volume-weight career coverage rates."""
    parts = [load_pfr_defense(season) for season in range(first, last + 1)]
    parts = [p for p in parts if p is not None and not p.empty]
    if not parts:
        return agg

    stacked = pd.concat(parts)
    stacked.index.name = "pid"
    stacked = stacked.reset_index()

    counting = ["def_pressures", "def_hurries", "def_qb_knockdowns",
                "def_targets_allowed", "def_combined_tackles"]
    rate_weights = {
        "def_cmp_pct_allowed": "def_targets_allowed",
        "def_yds_per_tgt_allowed": "def_targets_allowed",
        "def_rating_allowed": "def_targets_allowed",
        "def_missed_tkl_pct": "def_combined_tackles",
    }

    out = pd.DataFrame(index=sorted(stacked["pid"].unique()))
    out.index.name = "pid"
    for column in counting:
        if column in stacked.columns:
            out[column] = stacked.groupby("pid")[column].sum(min_count=1)
    for column, weight_col in rate_weights.items():
        if column not in stacked.columns or weight_col not in stacked.columns:
            continue
        w = stacked[["pid", column, weight_col]].dropna()
        w = w[w[weight_col] > 0]
        if w.empty:
            continue
        product = (w[column] * w[weight_col]).groupby(w["pid"]).sum()
        weight = w[weight_col].groupby(w["pid"]).sum()
        out[column] = product / weight.replace(0, pd.NA)

    # `load_pfr_defense` returns PFR's raw fractions; the ×100 scaling normally
    # happens inside `merge_pfr_defense`. Pooling bypasses that, so scale here and
    # then apply the same volume cut a single season gets.
    for column in ("def_cmp_pct_allowed", "def_missed_tkl_pct"):
        if column in out.columns:
            out[column] = pd.to_numeric(out[column], errors="coerce") * 100

    agg = agg.drop(columns=[c for c in out.columns if c in agg.columns], errors="ignore")
    agg = agg.join(out, how="left")
    return apply_def_rate_thresholds(agg)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from",
        dest="first",
        type=int,
        default=OLDEST_SUPPORTED_SEASON,
        help=f"Oldest season to include (default {OLDEST_SUPPORTED_SEASON}).",
    )
    parser.add_argument("--to", dest="last", type=int, default=None, help="Newest season to include.")
    parser.add_argument(
        "--season-type",
        choices=("REG", "POST", "all"),
        default="all",
        help="Phase(s) to roll up. Career playoffs are their own cohort.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Build rows without writing.")
    args = parser.parse_args()

    last = args.last or resolve_season(None)
    first = max(args.first, OLDEST_SUPPORTED_SEASON)
    if first > last:
        logger.error("Empty range: %s..%s", first, last)
        sys.exit(1)

    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not args.dry_run and (not url or not key):
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    now = datetime.now(UTC)
    phases = ("REG", "POST") if args.season_type == "all" else (args.season_type,)
    logger.info("=== Career rollup %s..%s (%s) ===", first, last, ", ".join(phases))

    client = None if args.dry_run else create_client(url, key)

    for phase in phases:
        agg = build_career_agg(first, last, phase)
        if agg.empty:
            logger.warning("No career aggregate for %s.", phase)
            continue

        rows = build_snapshot_rows(agg, ALL_TIME_SEASON, now, phase)
        if not rows:
            logger.warning("No career rows built for %s.", phase)
            continue
        logger.info("Built %d career %s rows.", len(rows), phase)

        if args.dry_run:
            sample = rows[0]
            logger.info(
                "Dry run sample: %s (%s) metrics=%d standard=%d",
                sample["name"],
                sample["player_type"],
                len(sample["metrics"]),
                len(sample["standard_stats"]),
            )
            continue

        for i, batch in enumerate(chunks(rows, 150)):
            logger.info("Upserting career batch %d (%d rows) for %s...", i + 1, len(batch), phase)
            client.table("player_snapshots").upsert(
                batch,
                on_conflict="id,season,season_type",
            ).execute()

        # Prune players who no longer qualify for the career cohort, the same way
        # the per-season ingest does, so a threshold change can't leave orphans.
        kept = {row["id"] for row in rows}
        existing = (
            client.table("player_snapshots")
            .select("id")
            .eq("season", ALL_TIME_SEASON)
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
                .eq("season", ALL_TIME_SEASON)
                .eq("season_type", phase)
                .execute()
            )
        logger.info("Upserted %d, pruned %d career %s rows.", len(rows), len(orphans), phase)


if __name__ == "__main__":
    main()
