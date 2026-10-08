---
paths:
  - "fastlane/**/*"
  - "scripts/asc-*.py"
---

# Gridiron StatScout: the duplicate screenshots fixed in 1.1.0

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here.

**Duplicate screenshots, fixed in 1.1.0** (2026-08-17): live 1.0 shipped the
en-US `APP_IPHONE_67` set with 10 shots (`01_qb_leaders.png` and
`02_player_profile.png` twice) and `APP_IPAD_PRO_3GEN_129` with 2 (the same file
twice), from a partial re-upload — `fastlane/screenshots/en-US` was always clean
at 9 files. ASC refuses `DELETE /appScreenshots/{id}` on a submitted version
(409 `STATE_ERROR`), so it could only be fixed on a draft; the 1.1.0 draft
inherited the dupes and they were deleted there. **Verify after any screenshot
upload** — walk `appScreenshotSets` and compare `sourceFileChecksum`, because a
partial `deliver` run appends rather than replaces and nothing warns you.
