---
paths:
  - "android/**"
  - "docs/android-*.html"
  - "scripts/play_screenshot_compositor.py"
  - "scripts/play-products.py"
  - "scripts/play-upload.sh"
  - "scripts/sync-android-historical.py"
  - "scripts/make_android_icon.py"
---

# Hockey StatScout Android rules

## Identity and products

- Native Android code is in `android/`, a screen-for-screen port of the iOS app
  (same copy, tokens, flows, product IDs). It started as a copy of
  `~/football/android`; everything NFL was replaced with the hockey iOS app as
  the spec. When iOS changes, port the change.
- Package `com.jackwallner.hockey`, Play name "Hockey Edge: Puck StatScout",
  launcher label "StatScout", paid tier "StatScout+". Feedback and Play contact
  email `jackwallner+bb@gmail.com`.
- Products (same IDs as iOS): subscriptions `com.jackwallner.hockey.pro.monthly`
  and `com.jackwallner.hockey.pro.yearly` (base plans `monthly` / `yearly`,
  7-day `trial-7d` new-customer offer), lifetime one-time product
  `com.jackwallner.hockey.pro`. Android US ladder $1.49 / $7.99 / $15.99, about
  20% under iOS; local prices are Play's conversion plus the fleet PPP curve.
  Never put prices in listing copy or app literals.
- RevenueCat project `proj5c659dbc`: Test Store app `app7a412ed16b` (Debug key
  `test_tMaO...`; the `test_FtMV...` key belongs to Football Next, never use it
  here), Play app `app9c64bbc0e4` (`goog_` key, release only), entitlement
  `pro` (`entlad14b37690`). The app reads offering `android`
  (`ofrng34a6ee42c7`, not current; iOS keeps `default`) with `$rc_monthly`,
  `$rc_annual`, `$rc_lifetime`, each holding the Play product
  (`...monthly:monthly`, `...yearly:yearly`, `...pro`) and the Test Store twin.
- Season model matches iOS: the live season is free and default; older seasons
  and All Time are StatScout+.
- Play reviewers unlock StatScout+ with a code (long-press Settings > App
  Version). Only its SHA-256 is in the build (`PLAY_REVIEW_CODE_SHA256` in
  `local.properties`); the code is `HOCKEY_PLAY_REVIEW_CODE` in
  `~/.hockey_credentials` and goes in Play Console App access. Never commit it.
- No deep link and no URL scheme: iOS has none.

## Deliberate differences from iOS

- Leaderboards use competition ranks (`competitionRanks`): tied values share a
  rank (1, 2, 2, 4). iOS numbers rows by position.
- Team recent-form windows count distinct game dates, not log rows, so a
  window holding one row per player per game still says "4 games".
- Live and history loads merge at ingest time on the main thread
  (`DashboardViewModel.ingestPlayers(mergePlayers(...))`), so whichever lands
  second never drops the other's seasons.
- Projections, recent form and the schedule are fetched with `paged { offset }`
  because PostgREST caps a response at 1,000 rows.
- `selectSeason` starts the historical load when a past season is picked,
  instead of waiting for the screen to ask.
- Recent controls are hidden for seasons without per-game history
  (`supportsRecentForm`, 2025-26 on), rather than showing an empty window.
- Purchase copy names Google Play and has no "24 hours before the end of the
  period" clause (Play has no such rule). `PriceDisclosureTest` pins it.
- The percentile legend says Red / Blue; iOS still says Green / Rust there,
  which is an iOS bug to fix on that side.
- Comparison headers keep the `surname` helper; the locked-compare overlay perk
  list is not ported (football Android omitted it too).
- Review prompt: same gates as iOS (second launch on, onboarding done, 30-day
  cooldown, Settings "Rate StatScout" ends the asks, "Send Feedback" never
  does), via `launchReviewFlow` only when the window has focus.

## Build

- JDK 17, checked-in Gradle wrapper, AGP 9.4.1, minSdk 26, target/compile 36.
- `android/local.properties` (ignored) holds `REVENUECAT_TEST_KEY`,
  `REVENUECAT_PLAY_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (same Supabase
  project as iOS), `PLAY_REVIEW_CODE_SHA256` and `PLAY_UPLOAD_*` (upload
  keystore `~/.android/keystores/hockey-upload.p12`, alias `upload`, password
  `HOCKEY_PLAY_UPLOAD_PASSWORD` in `~/.hockey_credentials`). Release builds
  fail without them. Upload cert SHA-256
  `8B:93:98:8A:EC:B9:51:5E:8B:BD:EB:A7:11:F2:38:05:8F:57:21:6B:A4:7B:73:18:CA:73:F6:98:71:38:92:49`.
- `qa` build type: R8 release config, debug signing, no RevenueCat key; use it
  for emulator speed checks (Debug parses the feed far slower).
- `scripts/sync-android-historical.py` regenerates
  `app/src/main/assets/players-historical.bin` (gzip JSON, about 4.6 MB) from
  `StatScout/Data/players-historical.json`. Never name an asset `.gz`: the
  packager inflates it and drops the extension, so past seasons vanish.
- `scripts/make_android_icon.py` derives the adaptive icon layers and
  `play-assets/icon-512.png` from the iOS AppIcon.
- Increment `versionCode` on every Play upload. 1.0.1 is versionCode 1.
- `scripts/play-upload.sh [validate|internal|internal-draft|production-draft]`
  and `scripts/play-products.py [--dry-run]` need `PLAY_SERVICE_ACCOUNT_JSON`.
  Neither has been run yet.

## Emulator (remote MacBook Pro only)

Follow the `android-dev` skill's Remote MacBook Pro section. Host
`jackwallner@192.168.4.25` (strict host keys), SDK
`/Users/jackwallner/Library/Android/sdk`. The Pro has no cmdline-tools. Build and
test with `fm-gradle <tasks>` from `android/` (jmbp is the Pro), never
`./gradlew` on the Air. It syncs the source with a debug-only
`local.properties` (no Play key or upload secrets), uses the Pro's JDK 17 and
forwards `ANDROID_SERIAL`, so connected tests need no hand sync. Create the
temporary AVD `hockey_agent_test` by hand (`.ini` plus a `config.ini` cloned
from another agent AVD, `android-36` `google_apis_playstore` x86_64,
1080x2400), boot it headless on port 5562 (`emulator-5562`), and delete only
it (and `~/hockey-agent-test`) afterwards with `adb -s emulator-5562 emu kill`.
Run connected tests from `android/` with
`ANDROID_SERIAL=emulator-5562 fm-gradle --max-workers=2 connectedDebugAndroidTest`.
Never touch `small_phone` or other agents' AVDs.

Debug launch extras (`DebugLaunchOptions`, debug builds only): `resetAll`,
`onboarded`, `forcePro`, `previewStore`, `previewTrialUsed`, `tab`,
`onboardingPage`, `uiTest`, `statsBoard`, and `screenshotData` (the fictional
iOS fixture feed, `ScreenshotFixtureApi` plus `FixtureGames`), with
`fixtureFresh` and `fixtureSlate` as on iOS.

## Store assets

`StoreScreenshotTest` (excluded from the connected suite; run it with `am instrument -e class com.jackwallner.hockey.StoreScreenshotTest`) writes the seven raw
1080x2400 captures to `/sdcard/Android/data/com.jackwallner.hockey/files/screens/`
with System UI demo mode on. Pull them into `android/play-assets/raw/` and run
`python3 scripts/play_screenshot_compositor.py` for the 1080x1920 frames (App
Store headlines) and the 1024x500 feature graphic. Listing text and the
changelog are in `android/play-assets/metadata/android/en-US/` (English only).
Privacy and terms pages are `docs/android-privacy.html` and
`docs/android-terms.html` on GitHub Pages.

## Play state (2026-10-17)

Ready to send (verified 2026-10-17): review code saved in App access, RevenueCat
Play credentials set. Only Send for review remains, in this app's pacing slot.

Staged, not sent for review. Play app id `4972606717178959857` (E3 Apps). versionCode 1
(1.0.1) uploaded with `~/docs/android/tools/play_stage.py`; listing, icon,
feature graphic and 7 screenshots committed by API; draft releases on
internal and production, production targets all 178 countries. Products from
`scripts/play-products.py` are active (two subscriptions with `trial-7d`, one
lifetime). App content is complete: privacy policy, no ads, no ad ID, not a
government app, no financial features, App access (instructions only),
18 and over, data safety (RevenueCat: purchase history, app interactions,
device IDs), IARC, category Sports. IARC answered as not educational (Brazil ClassInd shows 14+ for that combination). Publishing overview shows
"Submit 11 changes for review".

Left for Jack: paste `HOCKEY_PLAY_REVIEW_CODE` from `~/.hockey_credentials`
into App access > StatScout+ review unlock > Password, then press Send for review
when this app's pacing slot comes. Review codes: `~/docs/android/tools/play_handoff.py review-codes`. RevenueCat Play
credentials were uploaded with `play_handoff.py rc-credentials --apply`
on  2026-10-17. The RevenueCat service account already has
account-wide Play permissions, so no per-app grant is needed.
