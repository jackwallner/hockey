# State machine fixes, 2026-11-06

Fixes for the claims the [review](state-machines-2026-11-06-review.md) of the [state machine audit](state-machines-2026-11-06.md) confirmed, in the review's ranked order, against base `79a640a`.

**Summary: 3 claims in scope (B2 CONFIRMED, B3 and B4 CONFIRMED-MINOR). 3 fixed, 0 held, 0 skipped. B1 (NOT A BUG) and the 5 product calls left alone.**

| Id | Status | Commit | Regression test (`StatScoutTests/StateMachineRegressionTests.swift`) | What changed |
|---|---|---|---|---|
| B2 | fixed | `70ab256` | `testGamePageOpenedBeforePuckDropGetsTheScore`, `testTeamCardOpenedBeforePuckDropGetsTheScore`, `testGamesTabPushedPageWithAnotherGameLiveGetsTheScore` (controls: `testGamePageOpenedMidGamePolls`, `testTeamCardMidGamePolls`) | The game page and team card shared a poll that returned at its first check when the game had not started. Both now call `DashboardViewModel.pollLiveScore(for:)`, which sleeps until puck drop (re-reading the game each pass, at most 600 s per sleep), then reads the scoreboard every 30 s until the final posts. Covers the Games tab route too, where the slate's own poll stops under the pushed page |
| B3 | fixed | `a5301d0` | `testSupersededRecentFormLoadDoesNotClearTheNewLoadsSpinner`, `testSupersedeWithOuterTaskCancelledAndOldRequestAnswering` (control: `testSingleRecentFormLoadShowsSpinnerThenClears`) | The superseded load's `defer` cleared the loading flag and task entry the new load owned under the same window key. Cleanup now runs after the task finishes and only while `recentFormTasks[key]` is still that load's task, so the spinner holds and a third caller joins the in-flight load instead of starting a duplicate |
| B4 | fixed | `6ab4ca7` | `testTrendsDropsALockedSeasonWhenProLapses` | Trends keeps its own `selectedSeason`, which the view model's lapse clamp never reached. `HotColdView` now moves to the live season when `isPro` changes and its season is locked. `HotColdView.init` gained an optional `season:` (default unchanged) so the test can open Trends on the prior season, the seam the review said was missing |

Tests landed in `2371bf7`. They reuse the review's appendix checks (which the review called sound) for B2 and B3, and the audit's repro B3 tests. The audit's B1 repro test is not kept: the review rated B1 not a bug and the test calls `apply` with invented dates.

## Held for Jack

None.

## Skipped

None.

Note on B4: the fix moves only Trends' in-memory season (`@State`, never persisted) and reacts to whatever `isPro` the app already applies, the same signal the existing view model clamp uses. It changes no stored setting and does not change how membership is judged or when a paywall appears.

## Test results

| Run | Tree | Result |
|---|---|---|
| `hockey@20261106-195943-e9b4-claude-mbpro2a59-1106-200145-4639`, GitHub run 42336602580 | this branch, full suite (`gh-sim test --scheme StatScout --testarg -test-timeouts-enabled --testarg YES`) | Passed: 283 passed, 0 failed, 0 skipped. All 9 `StateMachineRegressionTests` pass |
| `hockey-base-e9b4-mbpro2a59-1106-205215-10852`, GitHub run 42340304743 | `79a640a` plus only the regression test file and the `HotColdView` `season:` init seam, `--only StatScoutTests/StateMachineRegressionTests` | 6 failed, 3 passed, as intended: every B2, B3 and B4 regression test fails (B2 pages read the scoreboard 0 times after puck drop; B3 flag lost and a third request started; B4 never loads the live season), the 3 controls pass |

No test newly fails. Nothing failed on the full run, so no test needed a base comparison. The repro suite was never added to the test target.
