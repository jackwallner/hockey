"""Drop per-game history down to the newest few seasons. Run by hand.

`player_game_logs` and the `player_recent_form` rollup built from it were the
two biggest tables in the database by a wide margin - 245 MB and 112 MB against
74 MB for every season snapshot ever ingested - because they hold one row per
player per game rather than one per player per season. All of that weight was
paying for a feature the app offers on the newest seasons only: a "last 3
games" board for 2017 is a curiosity, and nobody was opening it.

Season snapshots are never touched. Those are the whole app (percentiles,
leaderboards, Compare, the All Time rollup) and every year of them together is
smaller than one year of game logs.

**Not wired into the nightly workflow.** The one-off purge already took these
tables to a single season, and nothing in the pipeline writes an older one -
both `ingest_game_logs.py` and `rollup_recent_form.py` run against the resolved
current season. At roughly 26 MB a season the tables cannot threaten the 500 MB
budget for years, so this runs when an offseason decides it should, not every
night. Nightly it would only ever be a no-op with a delete attached.

`--keep` defaults to **two** seasons because that is what the app offers Recent
Form on: the live season and the one before it (`DashboardViewModel`'s
`recentFormSeasons`). Pruning to one would empty Trends for last season.

The cut is "older than the Nth-newest season present in the table", not a
calendar date, so it never anchors to a season the database has no rows for,
and running it twice is a no-op.

Deleting is cheap to undo if a historical window is ever wanted again: game
logs re-ingest from nflverse with
`python backend/ingest_game_logs.py --season N --full`, and the rollup rebuilds
with `python backend/rollup_recent_form.py --season N`.

Note that DELETE alone does not shrink the database on disk - it marks rows
dead and leaves the space for reuse. Reclaiming it for real needs a
`VACUUM FULL` over psql.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import argparse
import logging
import os
import sys
from typing import Optional

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Both tables are pruned to the same season so a window and the logs behind it
# can never disagree about which years exist.
TABLES = ("player_game_logs", "player_recent_form")

# Seasons Recent Form is offered on, and so the floor for any prune: the live
# season and the one before it. Mirrors DashboardViewModel.recentFormSeasons.
DEFAULT_KEEP = 2


def newest_season(client, table: str, below: Optional[int] = None) -> Optional[int]:
    """The highest season present (strictly below `below`), or None if there is none."""
    query = client.table(table).select("season").order("season", desc=True).limit(1)
    if below is not None:
        query = query.lt("season", below)
    rows = query.execute().data or []
    return int(rows[0]["season"]) if rows else None


def oldest_kept_season(client, table: str, keep: int) -> Optional[int]:
    """The oldest season to keep: the `keep`-th newest present, or the oldest there is.

    Walked one query at a time rather than read off a DISTINCT, which PostgREST
    does not offer. `keep` is a small number, so this is two round trips.
    """
    season = newest_season(client, table)
    if season is None:
        return None
    for _ in range(max(keep, 1) - 1):
        older = newest_season(client, table, below=season)
        if older is None:
            return season
        season = older
    return season


def count_older_than(client, table: str, season: int) -> int:
    response = (
        client.table(table)
        .select("season", count="exact")
        .lt("season", season)
        .limit(1)
        .execute()
    )
    return response.count or 0


def prune(client, table: str, dry_run: bool, keep_seasons: int = DEFAULT_KEEP) -> int:
    keep = oldest_kept_season(client, table, keep_seasons)
    if keep is None:
        logger.info("%s is empty; nothing to prune.", table)
        return 0

    stale = count_older_than(client, table, keep)
    if stale == 0:
        logger.info("%s: already at %d only.", table, keep)
        return 0

    if dry_run:
        logger.info("%s: would delete %d rows older than %d.", table, stale, keep)
        return stale

    logger.info("%s: deleting %d rows older than %d...", table, stale, keep)
    client.table(table).delete().lt("season", keep).execute()
    remaining = count_older_than(client, table, keep)
    if remaining:
        # PostgREST caps a single delete; loop until the tail is gone rather
        # than reporting success over rows that are still there.
        logger.info("%s: %d rows left, continuing...", table, remaining)
        while remaining:
            client.table(table).delete().lt("season", keep).execute()
            after = count_older_than(client, table, keep)
            if after == remaining:
                raise RuntimeError(
                    f"{table}: delete stopped making progress with {after} rows left"
                )
            remaining = after
    logger.info("%s: pruned to %d.", table, keep)
    return stale


def run(dry_run: bool = False, keep_seasons: int = DEFAULT_KEEP) -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise SystemExit("error: set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")
    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    total = sum(prune(client, table, dry_run, keep_seasons) for table in TABLES)
    logger.info("%s %d rows.", "Would delete" if dry_run else "Deleted", total)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would be deleted without deleting it.",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=DEFAULT_KEEP,
        help=(
            "Seasons to keep, newest first (default: %(default)s). "
            "Below 2 empties Recent Form for last season."
        ),
    )
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    run(dry_run=args.dry_run, keep_seasons=args.keep)


if __name__ == "__main__":
    main()
