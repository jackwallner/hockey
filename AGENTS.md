# Hockey Next: StatScout Project Guide

Hockey Next: StatScout: NHL expected-goals percentiles / player-comparison app
(iOS). XcodeGen project/scheme: `StatScout` (kept from the football fork to
minimize churn), sim lease owner `hockey`. Bundle id `com.jackwallner.hockey`,
product name "Hockey StatScout", home-screen `StatScout`, paid tier `StatScout+`.

**App Store name:** **"Hockey Next: StatScout"** (ASC app `6820644691`), subtitle
"Advanced NHL Stats & Analytics". Feedback `jackwallner+bb@gmail.com`.
RevenueCat project `proj5c659dbc`, app `app5504632e55`, entitlement `pro`.

**Design target:** NHL EDGE percentile bars (red hot, blue cold, "among
forwards / defensemen / goalies") carrying MoneyPuck's expected-goals model.
The contract every piece of the app and backend follows is
`project-docs/architecture/HOCKEY_CONTRACT.md`. Read it before touching
metrics, categories, cohorts, seasons or the data pipeline.

**This repo is NOT the fastlane template canonical source.** That lives in the
baseball StatScout repo. Metadata/screenshots here are app-specific.

**App Store reviews:** enjoyment funnel in `StatScout/Services/ReviewPromptTracker.swift`
(passive triggers: 3rd+ player profile open, Pro player comparison).

## Rules that hold everywhere
- Seasons are start years (2026 = 2026-27). Every label goes through
  `SeasonLabel.display`. Career rollup is season 0.
- `player_type` is `f` / `d` / `g`. Categories are exactly `Scoring`,
  `Shot Quality`, `Play Driving`, `Goaltending`. Skaters never compare
  head-to-head with goalies.
- Save percentages render as `.915` (`sv3`), never `91.5%`.
- MoneyPuck attribution stays in Settings and the About page.
- Never commit the review phone; it is read from `ASC_REVIEW_PHONE` in
  `~/.hockey_credentials`.

## Backend / data pipeline (NHL)

StatScout is backed by a Supabase NHL dataset (MoneyPuck + NHL web API) fed by
an event-aware GitHub Actions refresh.

- **Supabase** lives in the football Supabase account (project ref
  `swlalptdamfccgjmpbyb`): the Management API / CLI token does not reach it, so
  apply schema with `psql` using `SUPABASE_DB_PASSWORD`. Creds are in
  `~/.hockey_credentials`.
- Sources, tables, categories, refresh workflows, the Recent Form windows and
  the historical bundle are in `.claude/rules/backend-pipeline.md`, which
  loads when you read a matching file; Codex and other agents should open it
  directly.
- **TestFlight upload** sources the creds first: `source ~/.hockey_credentials && bash scripts/testflight.sh`.

## Deep notes (load on demand)

| File | Covers | Read when |
|---|---|---|
| `.claude/rules/backend-pipeline.md` | sources, schema, refresh cadence, bundle regeneration | backend/, supabase/, data scripts |
| `.claude/rules/app-store-release.md` | release state, draft-version helper, build numbers | project.yml, fastlane/, scripts/asc-* |
| `.claude/rules/screenshot-history.md` | duplicate-screenshot history (inherited) | screenshot uploads |

---
Shared iOS conventions (build, simulator, release scripts, ASC key, review funnel, signing, gotchas):
the global agent rules + the `ios-dev` skill.
