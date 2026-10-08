#!/usr/bin/env python3
"""Backfill and validate Hockey StatScout season snapshots from 2008 (MoneyPuck's floor) onward.

Runs backend/ingest.py once per season for both phases (REG and POST), then
validates what landed in Supabase. Finished seasons are cached in
backend/.cache/, so a re-run or the career rollup downloads nothing twice.
"""

import argparse
import os
import subprocess
import sys
from collections import Counter
from datetime import date
from typing import Any

from supabase import create_client

OLDEST_SUPPORTED_SEASON = 2008
REQUIRED_TYPES = {"f", "d", "g"}
CATEGORIES = {"Scoring", "Shot Quality", "Play Driving", "Goaltending"}
MINIMUM_ROWS = 150


def last_complete_season() -> int:
    """The newest finished season: the live season is the one in progress."""
    today = date.today()
    return (today.year if today.month >= 9 else today.year - 1) - 1


def minimum_teams(season: int) -> int:
    """League size that season: 30 to 2016-17, 31 with Vegas, 32 with Seattle."""
    if season >= 2021:
        return 32
    return 31 if season >= 2017 else 30


def fetch_season(client: Any, season: int) -> list[dict]:
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        page = (
            client.table("player_snapshots")
            .select("id,season,season_type,team,player_type,metrics")
            .eq("season", season)
            .order("id")
            .order("season_type")
            .range(offset, offset + page_size - 1)
            .execute()
            .data
        )
        rows.extend(page)
        if len(page) < page_size:
            return rows
        offset += page_size


def validate_season(rows: list[dict], season: int) -> list[str]:
    errors: list[str] = []
    if len(rows) < MINIMUM_ROWS:
        errors.append(f"only {len(rows)} snapshots")

    seasons = {row.get("season") for row in rows}
    if seasons != {season}:
        errors.append(f"unexpected season values: {sorted(seasons, key=str)}")

    keys = [
        (row.get("id"), row.get("season"), row.get("season_type"))
        for row in rows
    ]
    if len(keys) != len(set(keys)):
        errors.append("duplicate player-season keys")

    regular = [row for row in rows if row.get("season_type", "REG") == "REG"]
    teams = {row.get("team") for row in regular if row.get("team")}
    if len(teams) < minimum_teams(season):
        errors.append(f"only {len(teams)} teams")

    player_types = {
        str(row.get("player_type") or "").lower()
        for row in regular
    }
    missing_types = REQUIRED_TYPES - player_types
    if missing_types:
        errors.append(f"missing player types: {sorted(missing_types)}")

    bad_types = {row.get("player_type") for row in rows} - REQUIRED_TYPES
    if bad_types:
        errors.append(f"unexpected player types: {sorted(bad_types, key=str)}")

    bad_categories = {
        metric.get("category")
        for row in rows
        for metric in row.get("metrics", [])
    } - CATEGORIES
    if bad_categories:
        errors.append(f"unexpected categories: {sorted(bad_categories, key=str)}")

    empty_metrics = [row.get("id") for row in rows if not row.get("metrics")]
    if empty_metrics:
        errors.append(f"{len(empty_metrics)} rows have no metrics")

    blank_values = [
        (row.get("id"), metric.get("label"))
        for row in rows
        for metric in row.get("metrics", [])
        if str(metric.get("value") or "").strip() == ""
    ]
    if blank_values:
        errors.append(f"{len(blank_values)} metrics have blank values")

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=int, default=OLDEST_SUPPORTED_SEASON)
    parser.add_argument(
        "--end",
        type=int,
        default=int(os.environ.get("STATCAST_SEASON") or last_complete_season()),
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate existing Supabase snapshots without running ingestion.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.start < OLDEST_SUPPORTED_SEASON or args.end < args.start:
        raise SystemExit(
            f"Season range must be within {OLDEST_SUPPORTED_SEASON}+ and ordered oldest to newest."
        )

    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.")

    client = create_client(url, key)
    backend_ingest = os.path.join("backend", "ingest.py")

    for season in range(args.start, args.end + 1):
        print(f"\n=== {season} ===", flush=True)
        if not args.validate_only:
            subprocess.run(
                [
                    sys.executable,
                    backend_ingest,
                    "--season",
                    str(season),
                    "--season-type",
                    "all",
                ],
                check=True,
            )

        rows = fetch_season(client, season)
        errors = validate_season(rows, season)
        if errors:
            joined = "; ".join(errors)
            raise SystemExit(f"Validation failed for {season}: {joined}")

        counts = Counter(str(row.get("player_type") or "unknown") for row in rows)
        teams = {row.get("team") for row in rows if row.get("team")}
        print(
            f"Validated {len(rows)} snapshots, {len(teams)} teams, "
            f"types={dict(sorted(counts.items()))}",
            flush=True,
        )


if __name__ == "__main__":
    main()
