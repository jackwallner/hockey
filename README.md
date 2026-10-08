# Gridiron StatScout

Gridiron StatScout is a native SwiftUI iOS app for NFL fans and media to view mobile-friendly player percentile pages (passing / rushing / receiving / defense) from a nightly refreshed advanced-metrics data feed. Unaffiliated with the NFL.

## Stack

- **iOS app:** SwiftUI, iOS 17+
- **Project generation:** XcodeGen
- **Database/API:** Supabase Postgres + generated REST API
- **Nightly refresh:** GitHub Actions scheduled Python job
- **Ingestion:** Python + `nflreadpy` (nflverse) within-category percentile rankings

## Project layout

```text
StatScout/                  SwiftUI source
backend/                    Nightly ingestion job
supabase/schema.sql         Supabase database schema and RLS policy
.github/workflows/          Scheduled refresh workflow
project.yml                 XcodeGen project definition
```

## Run the iOS app

1. Install XcodeGen if needed:

   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:

   ```bash
   xcodegen generate
   ```

3. Open `StatScout.xcodeproj` in Xcode.

4. Run the `StatScout` scheme on an iPhone simulator.

The app loads real data through `StatcastAPI` using Supabase REST. Previews and unit tests use `PreviewStatcastAPI` with sample data. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as build settings or in `Info.plist` variables.

## Set up Supabase

1. Create a free Supabase project.
2. Open the SQL editor.
3. Run `supabase/schema.sql`.
4. Copy your project URL, anon key, and service role key.

The table is `public.player_snapshots`. Public read access is enabled through RLS for app consumption. Writes should use only the service role key from GitHub Actions secrets.

## Configure GitHub Actions

Add these repository secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY` (used by iOS build; rotate the old key immediately if it was ever committed)

Optional repository variable:

- `STATCAST_SEASON`

The workflow runs daily at `14:00 UTC` (10:00 EDT) and can also be run manually from GitHub Actions.

## Next production steps

- Add team/position enrichment to the percentile snapshot rows.
- Add dedicated player search/profile navigation around percentile cards.
- Add cached local persistence in the iOS app.
- Add push alerts for major percentile movers.
- Add share cards for media-friendly player insights.
