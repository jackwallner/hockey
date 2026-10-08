---
paths:
  - "backend/**/*"
  - "supabase/**/*"
  - "scripts/export_historical.py"
  - "scripts/backfill_historical.py"
---

# Hockey StatScout: backend and data pipeline

The contract (sources, schema, metric catalog, qualification, season rules) is `project-docs/architecture/HOCKEY_CONTRACT.md`. This file records what is implemented. Sections marked "ported in a later pass" still describe the football chassis in the code and are being converted.

## Implemented: snapshots, history, career

- **Sources** (keyless, cloud-IP friendly): MoneyPuck season summary CSVs `https://moneypuck.com/moneypuck/playerData/seasonSummary/<season>/<regular|playoffs>/<skaters|goalies>.csv` (five situation rows per player: `all`, `5on5`, `5on4`, `4on5`, `other`; icetime in seconds) and the NHL stats REST `https://api.nhle.com/stats/rest/en/<skater|goalie>/summary` (`limit=100`, `start=`, `sort=playerId`, `cayenneExp=seasonId=<YYYY(YYYY+1)> and gameTypeId=<2|3>`) for +/-, PPG, PPP, SHG, GWG, W/L/OT, SO, GS and shooting hand. `SOURCE = "moneypuck"`. Requests carry the User-Agent `Hockey StatScout (jackwallner+bb@gmail.com)`, one GET per file, 0.3 s pause.
- **Headshots**: `image_url` = `https://assets.nhle.com/mugs/nhl/<seasonId>/<TEAM>/<playerId>.png` (200 only for the right team; a wrong team returns a 302). No landing-endpoint calls. The historical bundle strips `image_url`.
- **Caching**: finished seasons are cached in `backend/.cache/` (gitignored) keyed by URL and query; the live season never reads the cache. `HOCKEY_NO_CACHE=1` disables it. The backfill fills it and the career rollup reuses it.
- **Season rule**: label = start year (2026 = 2026-27), `season = year if month >= 9 else year - 1`; `STATCAST_SEASON` overrides; floor 2008. NHL `seasonId` = `f"{season}{season+1}"`. Career rollup is season `0`. `season_type` is `REG` or `POST`; preseason is ignored.
- **Tables**: `player_snapshots` PK `(id, season, season_type)`, `id` = NHL player id, `player_type` in `f` / `d` / `g`, `position` keeps the raw code (C, L, R, D, G), `handedness` = NHL `shootsCatches`. Metric id = `<category-slug>-<pid>-<mid>`. `player_game_logs`, `player_recent_form`, `games`, `game_details`, `team_ratings`, `game_projections` exist in the schema but their writers are ported in a later pass.
- **Categories** (jsonb `metrics[].category`, exact strings): `Scoring` (f, d), `Shot Quality` (f, d), `Play Driving` (f, d), `Goaltending` (g). Formats include `sv3` (`.915`) and `dec3`. Percentiles are ranked inside the cohort (forwards vs forwards, defensemen vs defensemen, goalies vs goalies), inverted metrics rank lower raw values higher.
- **All rates come from summed counts** (never MoneyPuck's rounded percentage columns), so a season and the career rollup share one code path: `ingest.build_agg` over raw frames, then `ingest.build_snapshot_rows`.
- **Qualification** (one `QUAL_*` block at the top of `backend/ingest.py`): REG skaters `icetime >= 200 min` at `all` (Play Driving also `5on5 >= 150 min`), goalies `>= 600 min` or `>= 10 GP`; POST skaters 4 GP, goalies 2 GP; career skaters 300 GP, goalies 100 GP; career POST 50 / 25 GP (the contract is silent, these are our choice). Live season: bars scale by `qual_scale` = median club games / 82 (floor 0.1), every player with volume ships, each metric carries `qualified`. Finished seasons never scale, including the 2012-13 and 2019-20 short ones.
- **Supabase**: project ref `swlalptdamfccgjmpbyb` (football Supabase account, second free slot). Creds in `~/.hockey_credentials` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF`). Apply SQL with `PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "host=db.$SUPABASE_PROJECT_REF.supabase.co user=postgres dbname=postgres sslmode=require" -f <file>`; the Management API token does not reach this account. Migrations are applied in filename order; `20261008000000_hockey_schema.sql` adds the `player_profiles` columns (birthplace, toi_seconds, toi_per_gp, pp_toi_seconds, pk_toi_seconds, toi_share), `shots_status` / `summary_status` on `data_refresh_state` and `data_refresh_runs`, and re-creates `data_refresh_status` with them after the existing columns (`ngs_status` / `pfr_status` kept, left `unknown`). The `publish_data_refresh` / `update_data_refresh_build` RPCs do not write the new status columns yet (refresh pass).
- **Python**: `python3 -m venv backend/.venv && backend/.venv/bin/pip install -r backend/requirements.txt`. Tests: `backend/.venv/bin/python -m pytest backend/tests/test_ingest.py backend/tests/test_rollup_all_time.py scripts/tests -q` (root `pytest.ini` puts `backend/` on the path; CI also sets `PYTHONPATH=backend`).
- **Backfill**: `source ~/.hockey_credentials && backend/.venv/bin/python scripts/backfill_historical.py` (2008 through the last complete season, REG and POST, then validates each season: row floor, no duplicate keys, team count by league size, f/d/g present, the four category strings only). `--validate-only` audits without ingesting. Then `backend/.venv/bin/python backend/ingest.py --season <live> --season-type all` and `backend/.venv/bin/python backend/rollup_all_time.py`.
- **Historical bundle**: `StatScout/Data/players-historical.plist` = seasons 2008..last complete plus the season-0 career rollup, regenerated with `source ~/.hockey_credentials && backend/.venv/bin/python scripts/export_historical.py --historical-only` (writes the JSON, then `swift scripts/convert_historical_to_plist.swift`). Past seasons are the only thing the bundle provides, so a season missing here is missing from the app. Always pass `--historical-only`; no current-season snapshot ships in the bundle. Ahead of a September rollover fold the outgoing season in early with `STATCAST_SEASON=<next>`.

## Ported in a later pass

These sections describe the football implementation still present in the code and are replaced as each hockey port lands.

- **Game logs** (`ingest_game_logs.py`, NHL boxscore + MoneyPuck shots): per contract.
- **Recent form** (`rollup_recent_form.py`): 2/4/8-week windows per contract.
- **Probe and refresh** (`source_probe.py`, `refresh.py`, `refresh_schedule.py`, workflows): event-aware, atomic publication via the `publish_data_refresh` RPC; the planner and the self-scheduled `refresh-timer.yml` chain. `refresh.py` must adapt to the new `ingest.build_agg_for_season` signature (see the docstring at the top of `backend/ingest.py`).
- **Game details and enrichment** (`ingest_game_details.py`, `ingest_enrichment.py`, `team_ratings.py`): cumulative xG race, player profiles, team ratings, projections.
- **Pruning** (`prune_history.py`): manual tool only, unchanged.
