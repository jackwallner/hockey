#!/usr/bin/env python3
"""Export current and historical NFL snapshots from Supabase for the iOS bundle.

Ahead of a September rollover, run this with next season's number to fold the
outgoing season into the historical archive before it becomes historical:

    STATCAST_SEASON=2026 python3 scripts/export_historical.py --historical-only

`--historical-only` is what makes that safe. The current-season export would
otherwise go looking for a season that has not kicked off yet and fail
validation on an empty result. The app tolerates a bundle carrying the still-live
season (`TwoTierPlayerCache.loadHistoricalPlayers` filters it out until the
calendar catches up), so the build can ship months early.
"""

import argparse
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request
from collections import Counter
from datetime import date


def _resolve_season() -> int:
    """The season the pipeline is currently writing.

    Same rule as backend/ingest.py::resolve_season and the app's
    StatScoutSeason.current: an NFL season is named for the year it kicks off
    in, so September onward belongs to this year. This used to fall back to a
    literal 2025, which would have silently exported the 2026 season as
    "historical" and shipped a bundle with no current year in it.
    """
    today = date.today()
    return today.year if today.month >= 9 else today.year - 1


SUPABASE_URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_ANON_KEY"]
CURRENT_SEASON = int(os.environ.get("STATCAST_SEASON") or _resolve_season())
OLDEST_SUPPORTED_SEASON = 2000
# Career rollup sentinel, written by backend/rollup_all_time.py. It ships in the
# historical bundle so "All Time" works on first launch rather than waiting on a
# fetch, the same as every other past season.
ALL_TIME_SEASON = 0
REQUIRED_TYPES = {"qb", "rb", "wr", "te", "def"}

URL = f"{SUPABASE_URL}/rest/v1/player_snapshots"
HEADERS = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Accept": "application/json",
    "Prefer": "count=exact",
}


def fetch_page(query: str, attempts: int = 4) -> list[dict]:
    """One page, retried on transient failure.

    The historical export walks ~34k rows a thousand at a time, so a single
    hiccup from the API used to throw away the whole multi-minute run. Retrying
    the page is cheaper than restarting the export.
    """
    for attempt in range(1, attempts + 1):
        try:
            request = urllib.request.Request(f"{URL}?{query}", headers=HEADERS)
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read())
        except Exception as error:  # noqa: BLE001 - any failure is worth a retry
            if attempt == attempts:
                raise
            delay = 2 ** attempt
            print(f"  page failed ({error}); retrying in {delay}s")
            time.sleep(delay)
    return []


def fetch_all(query_filters: list[tuple[str, str]]) -> list[dict]:
    page_size = 1000
    offset = 0
    players: list[dict] = []

    while True:
        query = urllib.parse.urlencode([
            ("select", "*"),
            *query_filters,
            ("order", "season.asc,season_type.asc,id.asc"),
            ("limit", str(page_size)),
            ("offset", str(offset)),
        ])
        page = fetch_page(query)
        players.extend(page)
        print(f"  fetched {len(page)} rows (total {len(players)})")
        if len(page) < page_size:
            return players
        offset += page_size


def validate_export(
    players: list[dict],
    expected_seasons: set[int],
    require_rate_metrics: bool,
) -> None:
    seasons = {player.get("season") for player in players}
    if seasons != expected_seasons:
        raise RuntimeError(f"Unexpected seasons: {sorted(seasons, key=str)}")

    keys = [
        (
            player.get("id"),
            player.get("season"),
            player.get("season_type", "REG"),
        )
        for player in players
    ]
    if len(keys) != len(set(keys)):
        raise RuntimeError("Duplicate player-season keys in export")

    for season in sorted(expected_seasons):
        season_players = [
            player for player in players
            if player.get("season") == season
            and player.get("season_type", "REG") == "REG"
        ]
        teams = {player.get("team") for player in season_players if player.get("team")}
        types = {str(player.get("player_type") or "").lower() for player in season_players}
        missing_types = REQUIRED_TYPES - types
        # The 30-team floor is a real-season integrity check: a season missing a
        # franchise means a partial ingest. It says nothing about the career
        # rollup, whose cohort is a few hundred players carrying whichever team
        # they last played for, so that one is checked on types and size instead.
        if season == ALL_TIME_SEASON:
            if missing_types or len(season_players) < 100:
                raise RuntimeError(
                    f"Incomplete career rollup: {len(season_players)} players, "
                    f"missing types={sorted(missing_types)}"
                )
        elif season == CURRENT_SEASON:
            # Opening week may contain only one completed game. Require both
            # teams and every position group, without inventing the other games.
            if len(teams) < 2 or len(season_players) < 20 or missing_types:
                raise RuntimeError(
                    f"Incomplete current season: {len(teams)} teams, "
                    f"{len(season_players)} players, missing types={sorted(missing_types)}"
                )
        elif len(teams) < 30 or missing_types:
            raise RuntimeError(
                f"Incomplete {season}: {len(teams)} teams, missing types={sorted(missing_types)}"
            )
        if any(not player.get("metrics") for player in season_players):
            raise RuntimeError(f"Season {season} contains rows without metrics")

    if require_rate_metrics:
        labels = {
            metric.get("label")
            for player in players
            for metric in player.get("metrics", [])
        }
        missing_rates = {"EPA/Play", "EPA/Rush", "EPA/Tgt"} - labels
        if missing_rates:
            raise RuntimeError(f"Missing current rate metrics: {sorted(missing_rates)}")


def export(
    name: str,
    query_filters: list[tuple[str, str]],
    expected_seasons: set[int],
    require_rate_metrics: bool = False,
) -> None:
    filters_description = ", ".join(f"{name}={value}" for name, value in query_filters)
    print(f"\nExporting {name} ({filters_description})...")
    players = fetch_all(query_filters)
    validate_export(players, expected_seasons, require_rate_metrics)
    # The app never renders player photos, and league headshot URLs aren't ours
    # to redistribute in a shipped bundle. `created_at` is pipeline bookkeeping
    # the client has no use for. Drop both rather than baking them into every
    # build. (They stay in Supabase; this only trims the bundled snapshot.)
    for player in players:
        player.pop("image_url", None)
        player.pop("created_at", None)
    output = f"StatScout/Data/{name}.json"
    with open(output, "w") as file:
        json.dump(players, file, separators=(",", ":"))

    teams = {player.get("team") for player in players if player.get("team")}
    types = Counter(player.get("player_type") for player in players if player.get("player_type"))
    print(f"Saved {len(players)} rows, {len(teams)} teams, types={dict(sorted(types.items()))}")
    subprocess.run(
        ["swift", "scripts/convert_historical_to_plist.swift", name],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--historical-only", action="store_true",
        help="Skip the current-season export (for a pre-rollover STATCAST_SEASON).",
    )
    mode.add_argument(
        "--current-only", action="store_true",
        help="Refresh the shipped current snapshot without replacing historical data.",
    )
    args = parser.parse_args()
    os.makedirs("StatScout/Data", exist_ok=True)
    if not args.current_only:
        export(
            "players-historical",
            [("or", f"(season.eq.{ALL_TIME_SEASON},"
              f"and(season.gte.{OLDEST_SUPPORTED_SEASON},season.lt.{CURRENT_SEASON}))")],
            {ALL_TIME_SEASON} | set(range(OLDEST_SUPPORTED_SEASON, CURRENT_SEASON)),
        )
    if not args.historical_only:
        export(
            "players-current", [("season", f"eq.{CURRENT_SEASON}")],
            {CURRENT_SEASON}, require_rate_metrics=True,
        )


if __name__ == "__main__":
    main()
