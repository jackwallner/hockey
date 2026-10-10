---
paths:
  - "project.yml"
  - "fastlane/**/*"
  - "scripts/asc-*.py"
  - "scripts/asc-*.sh"
  - "scripts/asc_lib.py"
  - "scripts/testflight.sh"
---

# App Store release workflow

## Current state, 2026-10-10

- Version 1.0 (build 3, iPhone-only) submitted for review 2026-10-10 with
  release type MANUAL, together with the subscription group, both
  subscriptions and the lifetime IAP (review submission
  `00b6f7b9-26e8-461f-9b59-840908a96cd4`, five items). Release it manually
  once approved.
- Store name "Hockey Next: xG StatScout", 39 locales, 8 screenshots, price
  Free in 175 territories, App Privacy "Data Not Collected" (published).
- Products: `com.jackwallner.hockey.pro.yearly` ($9.99/yr, 1-week trial),
  `com.jackwallner.hockey.pro.monthly` ($1.99/mo, 1-week trial),
  `com.jackwallner.hockey.pro` ($19.99 lifetime), subs `6820647519` /
  `6820648105`, lifetime `6820649135`, PPP via `~/ios/pricing/plan_hockey.py`.
  RevenueCat `proj5c659dbc` has the fleet IAP key K968FW2N5M and ASC key
  27M3333KDW (set over the RC v2 API, `rc api POST /projects/<p>/apps/<a>`).
- Later products submit standalone over the API now that the first IAPs rode
  with a version.

The `submit_review` lane uses `automatic_release: false`. `Deliverfile` lists
the locales currently accepted by Fastlane; all 39 locales are listed.

## Draft version helper

`ASC_DRAFT_VERSION` is the version to bump from, not the target version.
`scripts/asc_lib.py` reuses an editable draft and bumps an existing live
version instead of returning it.

## TestFlight build number

`scripts/testflight.sh` increments `CURRENT_PROJECT_VERSION`, regenerates the
XcodeGen project, archives, then uploads. After a successful upload, commit the
updated build number in both `project.yml` and `StatScout.xcodeproj` in a
separate `chore:` commit. That build-number-only push does not need another
TestFlight build.

Before editing `fastlane/metadata/`, run
`./scripts/pull-appstore-metadata.sh` and compare the pull with its timestamped
backup.
