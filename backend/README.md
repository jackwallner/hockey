# Backend ingestion (NHL)

Python pipeline that turns MoneyPuck and NHL data into Supabase rows for the
iOS app. The contract is `project-docs/architecture/HOCKEY_CONTRACT.md`;
implementation notes are in `.claude/rules/backend-pipeline.md`.

Status: snapshots, the historical backfill, the career rollup and the
historical bundle export are implemented. Game logs, Recent Form, the source
probe, the event-aware refresh, game details and enrichment are ported in a
later pass (their sections below are marked and still describe the football
chassis in code).

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

Tests:

```bash
backend/.venv/bin/python -m pytest backend/tests/test_ingest.py backend/tests/test_rollup_all_time.py scripts/tests -q
```

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

## Ported in a later pass

Everything below this line still describes the football implementation in the
code and is rewritten as each hockey port lands.

- **Game logs** (`ingest_game_logs.py`): per-player-per-game rows from the NHL
  boxscore joined with the MoneyPuck shots file.
- **Recent Form** (`rollup_recent_form.py`): league-anchored 2/4/8-week
  windows.
- **Probe and event-aware refresh** (`source_probe.py`, `refresh.py`,
  `refresh_schedule.py`): fingerprints MoneyPuck `skaters.csv`, `goalies.csv`,
  `teams.csv` and `shots_<season>.zip`, then publishes snapshots, game logs
  and Recent Form atomically through `publish_data_refresh`.
  `refresh.py` must adapt to the new `ingest.build_agg_for_season` signature
  (see the docstring at the top of `backend/ingest.py`).
- **Freshness status**: `GET /rest/v1/data_refresh_status?select=*&limit=1`.
  Besides the football columns it now exposes `shots_status` (MoneyPuck shots
  file) and `summary_status` (NHL stats summary); `ngs_status` and
  `pfr_status` stay `unknown`.
- **Game details and enrichment** (`ingest_game_details.py`,
  `ingest_enrichment.py`, `team_ratings.py`): cumulative xG race, player
  profiles, team ratings and projections.
