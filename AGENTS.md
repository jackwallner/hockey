# Hockey Edge: Puck StatScout Project Guide

Hockey Edge: Puck StatScout: NHL expected-goals percentiles / player-comparison app
(iOS, plus a native Android port in `android/`, see `.claude/rules/android.md`). XcodeGen project/scheme: `StatScout` (kept from the football fork to
minimize churn), sim lease owner `hockey`. Bundle id `com.jackwallner.hockey`,
product name "Hockey StatScout", home-screen `StatScout`, paid tier `StatScout+`.

**App Store name:** **"Hockey Edge: Puck StatScout"** (ASC app `6820644691`), subtitle
"Advanced NHL Stats & Analytics". Feedback `jackwallner+bb@gmail.com`.
RevenueCat project `proj5c659dbc`, app `app5504632e55`, entitlement `pro`.

**Design target:** NHL EDGE percentile bars (red hot, blue cold, "among
forwards / defensemen / goalies") carrying MoneyPuck's expected-goals model.
The contract every piece of the app and backend follows is
`project-docs/architecture/HOCKEY_CONTRACT.md`. Read it before touching
metrics, categories, cohorts, seasons or the data pipeline.

**This repo is NOT the fastlane template canonical source.** That lives in the
baseball StatScout repo. Metadata/screenshots here are app-specific.

**App Store reviews:** system `requestReview()` only, no custom rating question
(App Review 5.6.1). `ReviewPromptTracker` gates it (2nd launch on, onboarding
done, 30-day cooldown stamped when the call is made, Settings "Rate StatScout"
row ends asks; "Send Feedback" never does). The only automatic asks are two
good moments (`ReviewMoment`): following a 3rd player, and a Pro member opening a
player comparison. `requestsReview(after:)` (ReviewRequest.swift) waits ~3s, then
re-checks the view is still on screen and no sheet, alert or paywall is up.
No launch, tab or open-count trigger. Write-review links use ASC ID `6820644691`.
Remote config reads the current offering's metadata (`RemoteConfig.swift`);
wording tests go through offering metadata `trial_cta` (`seven_day` control,
`my`, `your`), and `rating_prompt: off` pauses the star prompt. Switch keys must
be set the same on every offering.

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
| `.claude/rules/android.md` | Android port: products, RevenueCat, signing, deliberate iOS differences, jmbp emulator, Play assets and state | android/, docs/android-*, scripts/play-*, Android scripts |
| `.claude/rules/ipad-layout.md` | iPad column caps, form sheets, nav bar, the iPad UI tour | RootTabView, CompareView, PaywallView, StatScoutIPadUITests |

---
Shared iOS conventions (build, simulator, release scripts, ASC key, review funnel, signing, gotchas):
the global agent rules + the `ios-dev` skill.
