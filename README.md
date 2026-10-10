# Hockey Edge: Puck StatScout

A SwiftUI iPhone app that ranks NHL players by expected goals and shows each
one as NHL EDGE-style percentile bars (red hot, blue cold, ranked among
forwards, defensemen or goalies). Expected goals and shot data come from
MoneyPuck.com; schedules, box scores and bios are public NHL data.
Unaffiliated with the NHL, the NHLPA or MoneyPuck.

[App Store page](https://jackwallner.github.io/hockey/) ·
[Privacy](https://jackwallner.github.io/hockey/privacy-policy.html) ·
[Support](https://jackwallner.github.io/hockey/support.html)

## Stack

- **iOS app:** SwiftUI, iOS 17+, generated with XcodeGen (`project.yml`)
- **Data:** Supabase Postgres, read by the app over the REST API
- **Refresh:** event-aware GitHub Actions jobs (`backend/`, `.github/workflows/`)
  that pull MoneyPuck and the NHL web API after games finish

## Layout

```text
StatScout/        SwiftUI source (scheme and target keep the StatScout name)
backend/          Python ingestion, rollups and refresh scheduling
supabase/         Schema and migrations
project-docs/     Architecture notes, including the data contract
```

## Build

```bash
brew install xcodegen
xcodegen generate
open StatScout.xcodeproj
```

Run the `StatScout` scheme. Previews and unit tests use sample data; real
data needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` build settings.

Metrics, categories, cohorts and seasons follow
`project-docs/architecture/HOCKEY_CONTRACT.md`.
