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

## Current release, 2026-09-28

- App Store version 1.2.2 (build 53) is `READY_FOR_SALE`. Approved, then released
  manually on 2026-09-28 via `POST /v1/appStoreVersionReleaseRequests` after
  testing against live week 3 data.
- App Store version 1.2.1 is superseded.
- TestFlight build 53 is `VALID` and attached to 1.2.2. Build 52 was first
  submitted on 2026-09-27, then pulled the same day for a fix (a passer's 0 INT
  showed as "Not ranked") and 1.2.2 was resubmitted with build 53.
- All 50 version localizations have What's New copy. The full release notes are
  in en-US; the other locales use translated summaries.

## Pending release, 2026-09-29

- App Store version 1.2.3 (build 55) is `WAITING_FOR_REVIEW`. Build 55 is
  `VALID` and attached. Submitted through `submit_review` on 2026-09-29 with
  manual release (`automatic_release: false`).
- Fixes position-board defaults: QB Pass Yds, RB Rush Yds, WR/TE Rec Yds, and
  DEF Tackles. A stat carries across positions only when the user selected it.
- All 50 version localizations have updated What's New copy. Existing
  promotional text was preserved.
- Version 1.2.2 (build 53) remains live until 1.2.3 is approved and manually
  released.

The `submit_review` lane uses `automatic_release: false`. `Deliverfile` lists
the locales currently accepted by Fastlane. The 11 retired App Store locales
are handled by the `fill_deprecated_locales` lane.

## Draft version helper

`ASC_DRAFT_VERSION` is the version to bump from, not the target version. For
example, with 1.2.1 live, setting `ASC_DRAFT_VERSION=1.2.1` creates 1.2.2 when
there is no editable draft. `scripts/asc_lib.py` reuses an editable draft and
bumps an existing live version instead of returning it.

If an editable draft's `versionString` is wrong, it can be patched with
`PATCH /appStoreVersions/{id}`. A draft cannot be deleted once a build exists
for its platform (409 `STATE_ERROR`).

## TestFlight build number

`scripts/testflight.sh` increments `CURRENT_PROJECT_VERSION`, regenerates the
XcodeGen project, archives, then uploads. After a successful upload, commit the
updated build number in both `project.yml` and `StatScout.xcodeproj` in a
separate `chore:` commit. That build-number-only push does not need another
TestFlight build.

Before editing `fastlane/metadata/`, run
`./scripts/pull-appstore-metadata.sh` and compare the pull with its timestamped
backup. Do not run the full metadata uploader when changing only one version's
What's New text.
