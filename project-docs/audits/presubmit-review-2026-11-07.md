# Pre-submit review, 1.0.3 (build 17), 2026-11-07

Scope: app changes from the live App Store version to `main`.

- Live: 1.0.2 build 16 (`READY_FOR_SALE` in ASC), tree at `5d6531e` (chore: bump build 15 to 16).
- Candidate: 1.0.3 build 17 (`PREPARE_FOR_SUBMISSION`), `e3cb119`.
- App source diff: `DashboardViewModel.swift`, `GameCards.swift`, `GameDetailView.swift`,
  `HotColdView.swift` (plus the version and build bump in `project.yml`). These are the three
  state machine fixes from the 2026-11-06 audit (live score polling before puck drop, superseded
  recent form load clearing the new spinner, Trends staying on a locked season after a Pro lapse).

Checked, in order: crashes and data loss, purchase and paywall paths, state bugs, App Review risks.

## Findings

| Severity | File:line | What happens | Status |
|---|---|---|---|
| P2 | StatScout/ViewModels/DashboardViewModel.swift:461 | `pollLiveScore` keeps a game page or team card loop alive while the game is upcoming, waking at most every 10 minutes with no network call, and then reads the scoreboard every 30s until the schedule posts a final. A game stuck in `awaitingScore` (final not yet in the schedule) keeps polling while the page is open. Bounded by the view's `.task` lifetime, cancels cleanly, and matches 1.0.2's behavior once the game has started. | Not fixed (not broken) |
| P2 | StatScout/Views/GameCards.swift:28, StatScout/Views/GameDetailView.swift:44 | Each visible team card and game page runs its own poll, so several on screen at once each call `refreshLiveScores` (duplicate scoreboard reads). Same as 1.0.2; results are idempotent. | Not fixed (not broken) |

No P0 or P1 findings.

## Verified as correct

- `DashboardViewModel.swift:827` superseded load guard: `Task` is `Equatable`; every path that
  replaces or cancels a window's task (`reloadRecentForm`, the context reset, the season reset at
  line 747) either installs a new task under the key or clears `recentFormLoadingWindows` itself, so
  no spinner is left stuck and no new load is cleared by an old one. The awaiting caller always
  resumes because the inner task is unstructured, so cleanup cannot be skipped by outer cancellation.
- `HotColdView.swift:215` lapse handler only moves off a season `isSeasonLocked` reports, and
  `recentFormSeason` (the free season) is never locked, so it cannot loop or lock out Pro users.
  The new `season:` init parameter defaults to `nil` and the only app call site (`RootTabView.swift:233`)
  does not pass it, so app behavior is unchanged.
- `pollLiveScore` is on the main actor (class is `@MainActor`), takes a non-escaping closure that
  re-reads the game from the view model each pass, and swallows sleep cancellation then exits on
  `Task.isCancelled`. No force unwraps or indexing in the diff.
- No purchase, paywall, entitlement, onboarding, persistence, notification, widget or string
  changes in scope. Spot check of the whole app: paywall and trial sheet both carry Terms and
  Privacy links (`PaywallView.swift:438`, `TrialPitchSheet.swift:215`); no hard-coded prices,
  other-platform links or placeholder copy in Swift strings.
- Regression tests for all three changes exist in `StatScoutTests/StateMachineRegressionTests.swift`.

## Tests

`gh-sim test --scheme StatScout` on `e3cb119`: see the commit that records the result below.
