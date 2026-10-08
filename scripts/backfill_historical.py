#!/usr/bin/env python3
"""Backfill and validate Gridiron StatScout season snapshots from 2000 onward."""

import argparse
import os
import subprocess
import sys
from collections import Counter
from typing import Any

from supabase import create_client

OLDEST_SUPPORTED_SEASON = 2000
DEFAULT_CURRENT_SEASON = 2025
REQUIRED_TYPES = {"qb", "rb", "wr", "te", "def"}
MINIMUM_TEAMS = 30
MINIMUM_ROWS = 150


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
    if len(teams) < MINIMUM_TEAMS:
        errors.append(f"only {len(teams)} teams")

    player_types = {
        str(row.get("player_type") or "").lower()
        for row in regular
    }
    missing_types = REQUIRED_TYPES - player_types
    if missing_types:
        errors.append(f"missing player types: {sorted(missing_types)}")

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
        default=int(os.environ.get("STATCAST_SEASON", DEFAULT_CURRENT_SEASON)),
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
