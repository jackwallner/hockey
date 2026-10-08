# Backend ingestion (NFL)

The backend is serverless and free-tier friendly. GitHub Actions checks the
nflverse release metadata every 30 minutes during the active season and once a
day in the offseason. When a source generation changes, it pulls NFL data via
[`nflreadpy`](https://github.com/nflverse/nflreadpy), computes within-category
percentiles among qualified players, and publishes snapshots, per-game logs,
and Recent Form as one Supabase revision. No API key is required for the data
source.

## Local setup

```bash
python -m venv backend/.venv
source backend/.venv/bin/activate
pip install -r backend/requirements.txt
cp backend/.env.example backend/.env   # fill in SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
```

Run a season snapshot ingest:

```bash
python backend/ingest.py --season 2025 --season-type all
```

Backfill and validate every supported snapshot season (2000 through current):

```bash
python scripts/backfill_historical.py
```

Use `--validate-only` to audit existing Supabase rows without re-ingesting.

Run the per-game logs ingest (Recent Form data):

```bash
python backend/ingest_game_logs.py --season 2025          # incremental
python backend/ingest_game_logs.py --season 2025 --full   # full re-ingest
```

## Event-aware refresh

The production path is `backend/source_probe.py` followed by
`backend/refresh.py`:

1. The probe makes small requests for `timestamp.json` and HEAD metadata for
   `stats_player_week_<season>.parquet`, `games.parquet`, the three NGS assets,
   and `advstats_season_def.parquet`. The weekly player asset is the exact
   input used by both current-season builders.
2. A SHA-256 fingerprint combines each asset's release timestamp, ETag,
   Last-Modified value, length, and HTTP status. `games.parquet` is excluded
   because nflverse republishes it about every 30 minutes without any stat
   change; it still gates readiness and feeds coverage at build time. The last successful
   fingerprint is stored in `data_refresh_state`, so an unchanged probe exits
   without downloading source files or writing player tables.
3. A changed source creates a `data_refresh_runs` row. The builder reads the
   current season in full, stages all three outputs under its `refresh_id`,
   probes the source again, and calls `publish_data_refresh` only after the
   source remained stable.
4. The RPC validates row keys, same-season coverage, and existing game
   identities, then swaps the requested season phases in one transaction. A
   failure leaves the prior serving rows in place. Successful staging payloads
   are removed immediately; run manifests are retained for bounded diagnostics.
5. Before staging, the builder hashes its output without build timestamps. If
   the hash matches the live revision, `mark_data_refresh_unchanged` records
   the new source generation as handled and leaves rows, `refresh_id`, and
   `published_at` alone, so `published_at` means "the stats last changed".

The workflow is serialized with `cancel-in-progress: false`. A manual force
run is available when a source correction does not change release metadata:

```bash
gh workflow run nightly-statcast.yml -f force=true
```

For a credential-free local probe, leave the Supabase variables unset:

```bash
python backend/source_probe.py --season 2026 --json
```

The current-season event path rebuilds the full season because the current
feed is small and a full read catches corrections to earlier games. Direct
`ingest.py` and `ingest_game_logs.py` writes remain useful for explicit
historical backfills, but they are not the atomic current-season path.

## Freshness status contract

After applying
`supabase/migrations/20260912000000_event_aware_refresh.sql`, the app can read
one curated row from the normal Supabase REST endpoint:

```text
GET /rest/v1/data_refresh_status?select=*&limit=1
```

The stable fields are:

- `status`: `unknown`, `source_pending`, `building`, `published`, `degraded`,
  or `failed`.
- `refresh_id`: the last successfully published revision. It stays unchanged
  while a newer attempt is pending or failed.
- `latest_refresh_id`: the in-flight or latest failed attempt when one exists.
- `source_fingerprint`: the generation used by the live revision.
- `source_published_at`: the source timestamp used by the live revision.
- `published_at`: when that revision became live in Supabase.
- `last_checked_at`: when the source was checked most recently.
- `season`, `season_type`, `max_week`, `max_game_date`: coverage and phase
  metadata. During a September rollover, `season` may already be the new
  probe/build target while `refresh_id`, `published_at`, and the coverage
  values still describe the last successful live revision. Use the published
  revision fields when labeling what users are seeing.
- `expected_games`, `observed_games`, `coverage_status`: schedule coverage;
  early valid weeks can be `partial` while a later game is still arriving.
- `ngs_status`, `pfr_status`: `ready`, `pending`, `degraded`, or
  `not_applicable` enrichment state.
- `last_error_code`: a short retry-safe code. Internal error details stay out
  of the public view.

The user-facing distinction is `published_at` versus `last_checked_at`.
`degraded` means core data was published with partial coverage or delayed
optional enrichment. A pending or failed attempt never turns into an empty
serving dataset.

## Refresh runbook

Apply the migration with the Football database credentials before enabling the
workflow:

```bash
source ~/.hockey_credentials
psql "host=db.qwkmpwnhrejsuplcwxrb.supabase.co dbname=postgres user=postgres sslmode=require" \
  -f supabase/migrations/20260912000000_event_aware_refresh.sql
```

For a new source generation, the next scheduled probe creates and runs the
refresh automatically. If a run fails, inspect the GitHub log and the status
row, then use the force dispatch if the source metadata is unchanged. The
failed run's staging payload is discarded by the failure RPC, and the next
attempt can reuse the same source generation safely. A source outage is
recorded as `source_pending` and retried by the next probe.

Do not manually delete `data_refresh_state` or the live player tables while
investigating. The migration keeps old run manifests for bounded diagnostics,
and the publisher removes successful payloads after the atomic swap.

## Season rule

NFL season label = starting year. `season = year if month >= 9 else year - 1`
(UTC). `STATCAST_SEASON` env var (kept for workflow compatibility) overrides;
`--season N` overrides both.

## Data contract

The iOS app reads `player_snapshots` via Supabase REST. Each row has
PK `(id, season, season_type)`:

- `id`: bigint from the nflverse GSIS id (`"00-0034796"` -> `34796`)
- `season_type`: `REG` or `POST`; each phase is aggregated and ranked separately
- `name`, `team`, `position`, `player_type` (`qb`/`rb`/`wr`/`te`/`def`/`k`)
- `handedness` (always `""` for NFL), `image_url` (nflverse headshot)
- `metrics`: JSON array of `{id, label, value, percentile, category}` where
  `category` is `Passing` / `Rushing` / `Receiving` / `Defense`
- `standard_stats`: JSON array of `{id, label, value}` counting totals
- `games`: JSON array (currently empty `[]`)

Percentiles are computed within `(season, season_type, category)` among **qualified**
players (Passing >= 150 attempts, Rushing >= 80 carries, Receiving >= 40
targets, Defense >= 8 games). Inverted metrics (INT%, Sack%, Fumble%) rank
lower raw values higher. Postseason uses smaller phase-appropriate qualification
floors. For 2003 through 2008, nflverse targets are unavailable, so receiving
qualification falls back to receptions and target-derived metrics are omitted.

`player_game_logs` (PK `(player_id, season, season_type, game_date, player_type)`) holds one
row per player per game with `plays`, `touches`, and a flat `metrics` jsonb of
per-game raw stats. `player_recent_form` stores league-anchored 3/5/8-week
aggregates for Trends.

## Data sources (nflreadpy)

- `load_player_stats([season])` — weekly box-score rows, split into REG and POST.
- `load_nextgen_stats(stat_type=...)` — season-level Next Gen Stats (week 0
  rows): CPOE, time-to-throw, aggressiveness, RYOE, separation, YAC+.
- `load_schedules([season])` — `game_id` -> `gameday` for per-game dates.
- `load_players()` — headshot URLs.
