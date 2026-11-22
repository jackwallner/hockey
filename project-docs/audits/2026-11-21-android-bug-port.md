# Android port of the 2026-11-20 bug fixes

Checked 2026-11-22 on `main`. Each row of
[2026-11-20-bug-fixes.md](2026-11-20-bug-fixes.md) was checked against the
`android/` port by reading the code. Bugs that exist there were fixed with the
smallest change that matches the iOS behavior.

Unit run (`fm-gradle testDebugUnitTest`, GitHub Linux) on the tree of HEAD
`58c6119`: `hockey-mbairfcc1-1122-103054-13294`, **242 passed, 0 failed.**

An earlier run on the same fixes (`hockey-mbairfcc1-1122-102428-2330`) failed
`DashboardViewModelTest.loadNeverSnapsAwayFromTheLiveSeason`: that test pinned
the old calendar-only free season. It now gives the live season a row, as the
iOS test does. Every other new test calls an API the fix adds, so none of them
compiles on the old code. No emulator run; the Compose wiring was checked by
reading the code.

| iOS bug | Android verdict | Commit | Test | Notes |
|---|---|---|---|---|
| B1 Free users get an empty Stats board with last season locked from 1 Sep until October | ported | 2a64cfb | `DashboardViewModelTest.lastSeasonStaysFreeUntilTheNewSeasonHasRows`, `theBoardFollowsTheNewSeasonWhenItsFirstRowsLand`, `preseasonFreeUserOpensOnLastSeasonFromSavedData` | `freeSeason` is the live season only once it has rows; before that last season stays free. Games, standings, power ratings and the freshness check read the calendar season (`scheduleSeason`) |
| B2 A failed first load on the default board reads "No data available" with no Retry | ported | 74e55ee | `DashboardViewModelTest.aFailedFirstLoadReadsAsAFailureNotAnEmptyBoard` | `emptyBoardState` decides what an empty board says. The standard leaders board now shows the same loading and failure states (with Retry) as the other boards |
| B3 Recent Form range shows the day before on Central, Mountain and Pacific phones | ported | 67e6e05 | `BugCatalogRegressionTest.recentFormRangeReadsTheFeedsDatesOnAnyPhone`, `openingNightIsTheSchedulesEasternDate` | `as_of` is parsed as Eastern midnight, and the range label and opening night use Eastern dates |
| B4 Restore Purchases replaced by "Starting up…" on the last onboarding page | ported | 0c5da3d | `BugCatalogRegressionTest.onboardingOfferPageOffersRestoreBeforeDataLoads` | `onboardingFooter` gives a free user Restore whether or not data has loaded |
| B5 Settings shows a stale store error under "StatScout+ Unlocked"; Restore gives no feedback | ported | 58c6119 | none | Settings shows only the result of a restore started there, and the row reads "Restoring…" with a spinner while it runs. Screen state only, so there is no unit test; checked by reading the code |
| B6 Follow Players hides followed players with no row in the selected season | ported | eaf3b27 | `BugCatalogRegressionTest.followPlayersListsEveryFollowedPlayerOnAnySeason` | `followedPlayers` falls back to the player's newest row |
| B7 Hidden locked tabs count as paywall views at launch; onboarding purchases credited to them | ported | 02dcdca | `BugCatalogRegressionTest.hiddenTabsDoNotCountAsPaywallViews` | Every tab composes at launch on Android too. A gate counts only on the selected tab (`LocalIsSelectedTab`), once per session, and the onboarding offer logs its own view |
| B8 Onboarding buy page and trial sheet truncate at the largest text size | not applicable | | | iOS Dynamic Type accessibility sizes. Android font scale stops at 2x |
| B9 UK, Ireland and Portugal lose a Games day on the spring clock change | already fine | | | `GameDay.id` is built from the Eastern `LocalDate` (`"${phase.raw}-$date"`), not from a phone-zone timestamp, so two days never share an id |
| B10 Recent windows gain a day around a clock change outside New York's rules | ported | 7ee25a5 | `BugCatalogRegressionTest.trailingWindowIgnoresThePhonesClockChanges` | `RecentFormWindow.logs` counts Eastern days |

Counts: 8 ported, 1 already fine, 1 not applicable.

## Needs Jack

Nothing blocking. Not uploaded to Play; the fixes ship with the next Android
build when you ask for one.
