"""
Career ("All Time") rollup.

Writes one extra ``player_snapshots`` row per player under the sentinel season
``0``, aggregating every year from ``OLDEST_SUPPORTED_SEASON`` to the current
season into a single career line, with percentiles ranked inside the career
cohort (forwards, defensemen, goalies) rather than against any one season.

Why a stored row rather than an app-side mode: the leaderboards, Teams, Compare
and the player page all read from ``selectedSeason``, so modelling the career
view as just another season means every one of them gets it with no all-time
branch of its own, and the numbers are computed once here instead of on every
device. It also means the formatting, the qualification thresholds and the
percentile logic are literally the same code that produces a normal season.

This re-reads the MoneyPuck season files rather than summing the season
snapshots already in Supabase. Snapshots hold *formatted* values for
*qualified* players only, so summing them would compound rounding and drop
every season a player fell short of the cut. The MoneyPuck columns are all
additive (counts and ice time), so the career pass is the single-season pass
over the concatenated raw rows: ``ingest.build_agg``. Finished seasons come
from the same on-disk cache the backfill fills, so a rollup right after a
backfill downloads nothing.

Usage:
  python backend/rollup_all_time.py                 # 2008..current
  python backend/rollup_all_time.py --from 2015     # narrower window
  python backend/rollup_all_time.py --dry-run       # build, don't write

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

import argparse
import logging
import os
import sys
from datetime import datetime, timezone

import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

from ingest import (
    ALL_TIME_SEASON,
    DEFAULT_SEASON,
    OLDEST_SUPPORTED_SEASON,
    build_agg,
    build_snapshot_rows,
    load_season_sources,
    prune_orphans,
    resolve_season,
    upsert_rows,
)

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)


def concat_frames(frames: list[pd.DataFrame]) -> pd.DataFrame:
    frames = [f for f in frames if f is not None and not f.empty]
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def load_range(first: int, last: int, season_type: str) -> tuple[pd.DataFrame, ...]:
    """Raw MoneyPuck and NHL summary frames for the whole range, concatenated.

    A season that fails to download raises: a career total that silently omits
    a season is worse than no career total. A phase with no file (404) is empty
    and skipped.
    """
    parts: list[list[pd.DataFrame]] = [[], [], [], []]
    for season in range(first, last + 1):
        frames = load_season_sources(season, season_type, cache=season < DEFAULT_SEASON)
        for bucket, frame in zip(parts, frames):
            bucket.append(frame)
        logger.info("Loaded %s %s", season, season_type)
    return tuple(concat_frames(bucket) for bucket in parts)


def build_career_agg(first: int, last: int, season_type: str = "REG") -> pd.DataFrame:
    """Aggregate the full range into one career row per player."""
    skaters, goalies, sk_sum, g_sum = load_range(first, last, season_type)
    agg = build_agg(skaters, goalies, sk_sum, g_sum)
    logger.info("Career aggregate (%s): %d players", season_type, len(agg))
    return agg


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)

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
                sample["name"], sample["player_type"],
                len(sample["metrics"]), len(sample["standard_stats"]),
            )
            continue

        upsert_rows(client, rows)
        # Prune players who no longer qualify for the career cohort so a
        # threshold change can't leave orphans.
        pruned = prune_orphans(client, rows, ALL_TIME_SEASON, phase)
        logger.info("Upserted %d, pruned %d career %s rows.", len(rows), pruned, phase)


if __name__ == "__main__":
    main()
