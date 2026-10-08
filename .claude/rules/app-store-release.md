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

## Current state, 2026-10-08

- ASC app `6820644691` created 2026-10-08 with version 1.0 in
  `PREPARE_FOR_SUBMISSION`. No build uploaded yet.
- Products: `com.jackwallner.hockey.pro.yearly` ($9.99/yr, 1-week trial),
  `com.jackwallner.hockey.pro.monthly` ($1.99/mo, 1-week trial),
  `com.jackwallner.hockey.pro` ($19.99 lifetime). Created in RevenueCat
  (`proj5c659dbc`) and in ASC on 2026-10-08 (subs `6820647519` monthly,
  `6820648105` yearly, with 1-week FREE_TRIAL intros; lifetime at $19.99 in
  175 territories). PPP ladders still to apply with `~/ios/pricing`.
- The first IAP submission must ride with the version (Guideline 2.1(b)),
  and the "Add for Review" step is UI-only: see the `ios-dev` skill.

The `submit_review` lane uses `automatic_release: false`. `Deliverfile` lists
the locales currently accepted by Fastlane; only en-US metadata exists so far.

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
