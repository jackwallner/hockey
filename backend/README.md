# Backend ingestion (NHL)

Python pipeline that turns MoneyPuck and NHL data into Supabase rows for the
iOS app. The contract is `project-docs/architecture/HOCKEY_CONTRACT.md`;
implementation notes are in `.claude/rules/backend-pipeline.md`.

Status: snapshots, the historical backfill, the career rollup, the historical
bundle export, the games sync, game logs, Recent Form, the source probe and the
event-aware refresh are implemented. Game details and enrichment are ported in
a later pass (the last section; the code still describes the football chassis).

## Local setup

```bash
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements.txt
source ~/.hockey_credentials   # SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ...
```

Run a season snapshot ingest (REG and POST are ranked separately):

```bash
backend/.venv/bin/python backend/ingest.py --season 2025 --season-type all
```

Backfill and validate every supported snapshot season (2008 through the last
complete season), then the live season and the career rollup:

```bash
backend/.venv/bin/python scripts/backfill_historical.py
backend/.venv/bin/python backend/ingest.py --season 2026 --season-type all
backend/.venv/bin/python backend/rollup_all_time.py
```

Use `--validate-only` on the backfill to audit existing Supabase rows without
re-ingesting. Finished-season downloads are cached in `backend/.cache/`
(gitignored); set `HOCKEY_NO_CACHE=1` to bypass it.

Regenerate the bundled history (`StatScout/Data/players-historical.plist`):

```bash
backend/.venv/bin/python scripts/export_historical.py --historical-only
```

Games, game logs and Recent Form (run in this order; the game logs need the
games table and the snapshots):

```bash
backend/.venv/bin/python backend/sync_games.py --season 2026        # live + previous season
backend/.venv/bin/python backend/ingest_game_logs.py --season 2025 --full   # ~35 min for a season
backend/.venv/bin/python backend/ingest_game_logs.py --season 2026  # new finals only
backend/.venv/bin/python backend/rollup_recent_form.py --season 2026
```

The refresh path the workflow uses (a probe creates the refresh id, then the
refresh builds and publishes atomically; a second run with no new data ends as
`unchanged`):

```bash
backend/.venv/bin/python backend/source_probe.py --force --json
backend/.venv/bin/python backend/refresh.py --refresh-id <id> --season 2026
```

Tests (the two football-era files, `test_enrichment.py` and
`test_game_details.py`, fail until the enrichment and game-details port):

```bash
backend/.venv/bin/python -m pytest backend/tests -q \
  --ignore=backend/tests/test_enrichment.py --ignore=backend/tests/test_game_details.py
```

The SQL fixtures `backend/tests/publisher_integration.sql` and
`unchanged_integration.sql` run against a disposable Postgres with every
migration applied (create the roles `anon`, `authenticated`, `service_role` and
`pgcrypto` first).

## Season rule

Season label = start year (2026 means 2026-27). `season = year if month >= 9
else year - 1` (UTC). `STATCAST_SEASON` (name kept for workflow compatibility)
overrides; `--season N` overrides both. NHL `seasonId` is `f"{season}{season+1}"`.
Oldest supported season is 2008 (MoneyPuck's floor). The career rollup is
season `0`.

## Data contract

The iOS app reads `player_snapshots` via Supabase REST. Each row has PK
`(id, season, season_type)`:

- `id`: NHL player id (MoneyPuck and the NHL API share it)
- `season_type`: `REG` or `POST`; each phase is aggregated and ranked separately
- `name`, `team`, `position` (C/L/R/D/G), `player_type` (`f` / `d` / `g`),
  `handedness` (NHL `shootsCatches`), `image_url` (NHL mug URL)
- `metrics`: JSON array of `{id, label, value, percentile, category}` where
  `category` is `Scoring` / `Shot Quality` / `Play Driving` / `Goaltending`
- `standard_stats`: JSON array of `{id, label, value}` (skaters: GP, G, A, P,
  +/-, PIM, PPG, PPP, SHG, GWG, SOG, Sh%, TOI/GP, Hits, Blk, FO%; goalies: GP,
  GS, W, L, OT, GAA, SV%, SO, SA, SV)
- `games`: JSON array (currently empty `[]`)

Percentiles are computed within `(season, season_type, category, cohort)`
among qualified players: forwards against forwards, defensemen against
defensemen, goalies against goalies. Regular season skaters need 200 minutes
(Play Driving also 150 minutes at 5-on-5), goalies 600 minutes or 10 games;
postseason 4 / 2 games; career 300 / 100 games. The live season ships every
player with volume and flags each metric with `qualified`, prorated by
`qual_scale` (median club games / 82, floor 0.1). All thresholds are the
`QUAL_*` block at the top of `backend/ingest.py`.

## Data sources

- MoneyPuck `seasonSummary/<season>/<regular|playoffs>/skaters.csv` and
  `goalies.csv`: one file per phase, five situation rows per player.
- NHL stats REST `skater/summary` and `goalie/summary` (paginated 100 at a
  time): +/-, PPG, PPP, SHG, GWG, W/L/OT, SO, GS, shooting hand. When it is
  unavailable the rows fall back to MoneyPuck-derivable standard stats.
- NHL mugs `assets.nhle.com/mugs/nhl/<seasonId>/<TEAM>/<playerId>.png`.

Requests send the User-Agent `Hockey StatScout (jackwallner+bb@gmail.com)`.
Attribution shown in the app: "Expected goals and shot data from
MoneyPuck.com. Schedule, box scores and bios from the NHL."

## Games, game logs and Recent Form

- **Games** (`sync_games.py`): `public.games` from the NHL schedule for the live
  and previous season. `club-schedule-season/<TEAM>/<seasonId>` for 32 clubs is
  the cheapest full walk; one `schedule/<date>` call refreshes live scores.
  Scores only once `gameState` is `FINAL` or `OFF`; preseason and all-star
  games are skipped; playoff `game_type` is `R1`/`R2`/`CF`/`SCF`.
- **Game logs** (`ingest_game_logs.py`): per-player-per-game raw counts from
  the NHL boxscore and play-by-play joined with the MoneyPuck
  `shots_<season>.zip` (ixG, shot attempts, high-danger shots, goalie xGA).
  Incremental by default (finals with no rows yet); `--full` re-ingests. A final
  waits until the shot file contains it.
- **Recent Form** (`rollup_recent_form.py`): league-anchored 2/4/8-week windows
  with the THEN / NOW / delta row shape; rates recomputed from summed counts.

## Probe and event-aware refresh

- `source_probe.py` fingerprints MoneyPuck `skaters.csv`, `goalies.csv`,
  `teams.csv` (regular and, once it exists, playoffs) and `shots_<season>.zip`
  by ETag, Last-Modified and Content-Length with HEAD requests. The NHL
  endpoints are not fingerprinted.
- `refresh_schedule.py` (stdlib only) decides when a probe is worth running:
  every 30 minutes from a game's start + 2.5 h to + 12 h, hourly to + 36 h,
  else every 6 hours in season (October to June) and daily off season. It also
  syncs the schedule every 15 minutes while a game is in progress, else daily.
- `refresh.py` builds snapshots, game logs (new finals only, unioned with the
  published rows) and Recent Form under one refresh id, hashes the output (an
  identical hash ends as `unchanged`), stages it, and publishes atomically with
  `publish_data_refresh`. Coverage is finals in `games` against finals with log
  rows.
- Workflows: `nightly-statcast.yml` ("NHL Refresh"), its self-booked
  `refresh-timer.yml` chain with a 30-minute cron backup in season, `keepalive.yml`
  and `enrichment.yml` (nightly at 11:00 UTC in season).
- **Freshness status**: `GET /rest/v1/data_refresh_status?select=*&limit=1`.
  Besides the football columns it exposes `shots_status` (MoneyPuck shots file)
  and `summary_status` (NHL stats summary); `ngs_status` and `pfr_status` stay
  `unknown`.

## Ported in a later pass

- **Game details and enrichment** (`ingest_game_details.py`,
  `ingest_enrichment.py`, `team_ratings.py`): cumulative xG race, player
  profiles, team ratings and projections still describe the football
  implementation in the code.
