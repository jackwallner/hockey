# Gridiron StatScout Project Guide

Gridiron StatScout: NFL advanced-stats percentiles / player-comparison app (iOS).
XcodeGen project/scheme: `StatScout` (names kept to minimize churn), sim lease
owner `football`. Bundle id `com.jackwallner.football`, product name "Gridiron StatScout".

**App Store name:** **"Football Next: StatScout"** (ASC app `6792930447`), chosen
for ASO. In-app it is still `PRODUCT_NAME: "Gridiron StatScout"`, home-screen
`StatScout`, paid tier `StatScout+`.
ASO plan: `project-docs/marketing/aso-plan.md` · `docs/astro-aso-setup.md` · `docs/localization-aso.md`.

**This repo is NOT the fastlane template canonical source.** That lives in the
baseball StatScout repo. Metadata/screenshots here are app-specific.

**App Store release workflow and current state:** `.claude/rules/app-store-release.md`.

**App Store reviews:** enjoyment funnel in `StatScout/Services/ReviewPromptTracker.swift`
(passive triggers: 3rd+ player profile open, Pro player comparison). feedback
`jackwallner+bb@gmail.com`.

## Backend / data pipeline (NFL)

StatScout is backed by a Supabase NFL dataset fed by a nightly pipeline (already live).

- **Supabase** is a separate account from the other apps: the Management API /
  CLI token does not reach it, so apply schema with `psql` using
  `SUPABASE_DB_PASSWORD`. Creds are in `~/.football_credentials`.
- The historical plist is the only source of past seasons in the app, and
  `backend/prune_history.py` is a manual tool, never a nightly step.
- Data source, tables, categories, refresh workflows, the Recent Form window,
  pruning, and regenerating the historical bundle are in
  `.claude/rules/backend-pipeline.md`, which loads when you read a matching file;
  Codex and other agents should open it directly. The duplicate-screenshot history is
  in `.claude/rules/screenshot-history.md`.
- **TestFlight upload** sources the creds first: `source ~/.football_credentials && bash scripts/testflight.sh`.

---
Shared iOS conventions (build, simulator, release scripts, ASC key, review funnel, signing, gotchas):
the global agent rules + the `ios-dev` skill.
