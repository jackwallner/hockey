VERDICT: PASS

# State machine fixes verification, 2026-11-06

Independent check of the [fixes](state-machines-2026-11-06-fixes.md) for the [review](state-machines-2026-11-06-review.md) of the [state machine audit](state-machines-2026-11-06.md). Whole change read: `git diff 79a640a..a5988dd` (fix commits `70ab256`, `a5301d0`, `6ab4ca7`, tests `2371bf7`, docs `2497100`; `a5988dd` is an empty snapshot commit). No app code or tests were changed.

Line numbers below are at `a5988dd`.

## Fixes

| Id | Works | Regression check | Evidence |
|---|---|---|---|
| B2 | yes | none found | Route: Games tab > Upcoming row > game page, or Teams > team > `TeamGameCard`, opened before puck drop. Both views now call `DashboardViewModel.pollLiveScore(for:)` (GameDetailView.swift:44, GameCards.swift:27-29). It re-reads the game each pass, sleeps until puck drop while `.upcoming` (clamped 1 to 600 s, `try? Task.sleep` so a cancel ends it), then calls `refreshLiveScores` every 30 s and returns once the schedule shows a final (DashboardViewModel.swift:461-472). `Game.status` is clock-based, `upcoming` exactly when `now < kickoff` or no kickoff (Game.swift:175-182), so the loop leaves `upcoming` at puck drop. In-progress, awaiting-score and final behaviour is unchanged from the old view-local loops: they polled the same two states and returned on final. Tests host the real `GameDetailView`, `TeamGameCard` and the Games tab composition (`GamesView` plus pushed `GameDetailView`). With the fix reverted they fail on the claim asserts (0 scoreboard reads after puck drop, 1 read and no growth under the pushed page) |
| B3 | yes | none found | Route: Trends, a season or season type change during the first load. The cleanup moved out of the task's `defer` into the caller after `await task.value`, guarded by `recentFormTasks[key] == task` (DashboardViewModel.swift:823-829). A superseded caller therefore leaves the new load's flag and task entry alone, and a third caller joins the in-flight task through `if let inFlight` (790-793). `await task.value` on an unstructured task waits whatever the caller's cancellation, so the owning caller always cleans up. Every other writer was walked: context change (780-787) and `invalidateRecentFormCache` (746-753) clear flags and entries themselves, so the guarded cleanup correctly does nothing afterwards. `reloadRecentForm` (756-768, the Trends retry at HotColdView.swift:349) removes the entry and immediately starts a new owner. A failed fetch still clears the flag and entry so the next caller retries. Callers: HotColdView.swift:200, 349; TeamView.swift:291. With the fix reverted both supersede tests fail on the claim asserts (flag false while the new request is out; 3 requests where 2 are expected) |
| B4 | yes | none found | Route: Pro or trial user on Trends with the previous season selected, entitlement lapses in a live process. `HotColdView` now has `.onChange(of: viewModel.isPro)` that moves `selectedSeason` to `recentFormSeason` when it is locked (HotColdView.swift:213-217). `isPro` is the observed view model property written only by `applyProState` (DashboardViewModel.swift:180-183), which `StatScoutApp` drives from `store.isPro` (StatScoutApp.swift:134, 150-151), the same signal as the existing view model clamp. The new season changes the `.task` id (HotColdView.swift:196-205), so the live board loads, gated by `isActive` as before. A free-to-Pro flip is a no-op (the live season is never locked). The `season:` init parameter (HotColdView.swift:32, 39) defaults to nil and the only production caller (RootTabView.swift:233) does not pass it. With the fix reverted (seam kept) the test fails on "after a lapse Trends moves to the live season" |

## Disputed

The fixes doc has no "Disputed" section, so there is nothing to rule on. It lists B1 (review: NOT A BUG) and the five product calls as left alone. That is correct: none is an in-scope claim.

## Regression sweep (check 2)

- Callers of every changed symbol: `pollLiveScore` (GameDetailView.swift:44, GameCards.swift:28), `refreshLiveScores` (unchanged; also GamesView.swift:90), `loadRecentFormIfNeeded`/`reloadRecentForm` (HotColdView.swift:200, 349, TeamView.swift:291), `recentFormLoadingWindows`/`isRecentFormLoading` readers (HotColdView.swift:337, 451, 454), `HotColdView.init` (RootTabView.swift:233). Each still sees the same states as before on every path except the three bug paths.
- Audit transition tables. SM7 `inProgress -> final`: the loop returns on final, and `liveScore(for:)` still hides finals (I22). `upcoming (page open) -> kickoff`: now polls (I21 holds). SM6: `loading(2026) -> call 2025` now keeps I18 and I20. `loaded(2026) -> other consumer loads 2025` (Team page roster) still clears the cache and owns the new load. `revision adopted` still empties via `invalidateRecentFormCache` (I15). SM4: `Pro, 2025 -> isPro false` now holds I11. `free taps locked season` still opens the pitch without changing the season (I12, `selectSeason` untouched).
- Stored data after upgrade: none touched. `selectedSeason` is `@State`. No `UserDefaults`, `@AppStorage`, cache or Codable format changed.
- Widgets, watch, notifications: the project has only the app, unit test and UI test targets (project.yml). No such surface exists.
- Entitlements and trials: B4 only reads `isPro`. How it is judged, the paywall, pitch triggers and onboarding are untouched. Nothing is torn down on an inferred state: the change moves an in-memory board selection, the same as the existing view model clamp, and never clears a stored setting.
- Undo and edit paths: none in the touched code.
- Day and time zone: `Game.status` compares absolute dates, so the puck-drop sleep is zone-independent. `Task.sleep(for:)` uses the continuous clock, so a page left suspended across puck drop wakes on resume. A game with no kickoff wakes every 600 s and makes no network call.
- Localized text: no strings changed.
- iPhone Duo layouts: no layout changed (only modifiers and task bodies).
- Cost: a page held on an upcoming game now keeps one sleeping task with no network until puck drop. Polling while live is the same 30 s cadence as before.

## Scope (check 4)

- Only B2, B3 and B4 changed, all CONFIRMED or CONFIRMED-MINOR in the review. No UNVERIFIED claim was fixed. B4 was not run by the review, but its test fails on the base, so it has a failing test either way.
- The only change beyond the bug lines is the `season:` init seam in `HotColdView`, which the review named as missing. It defaults to nil and production does not use it. Not a failure.
- No trial, onboarding, price, paywall or membership change. No backend, App Store Connect or RevenueCat change. No stored format change. Nothing held. Every in-scope claim is in the fixes table.

## Must change

Nothing blocks the fixes. One follow-up for Jack's Mac: `StatScoutTests/StateMachineRegressionTests.swift` is missing from the committed `StatScout.xcodeproj/project.pbxproj`, which otherwise lists every test file. gh-sim runs `xcodegen` on the runner, so the tests ran there, but a local Xcode run from the committed project would silently skip all 9. Run `xcodegen generate` and commit the project. That can't be done on this Linux machine.

## Test results

| Run | Tree | Result |
|---|---|---|
| `hockey@20261106-214451-53fe-claude-imaca906-1106-215303-27211`, GitHub run 42344585384 | HEAD `a5988dd`, full suite, `gh-sim test --scheme StatScout` | Passed: 283 passed, 0 failed, 0 skipped. All 9 `StateMachineRegressionTests` passed. The B4 test ran and did not skip. Matches the fixes doc (283 / 0 / 0) |
| `hockey@20261106-214451-53fe-claude-imaca906-1106-225416-31262`, GitHub run 42349004054 | throwaway `scratch-revert`: HEAD with `a5301d0` and `70ab256` reverted and the B4 `.onChange` removed (init seam kept), tests unchanged. `--only` the 6 fix tests, `-test-timeouts-enabled YES` | 0 passed, 6 failed, as expected. Every failure is a claim assert and no precondition failed: B2 page and team card 0 reads after puck drop, Games tab pushed page 1 read with no growth, B3 flag false (both tests) plus 3 requests instead of 2, B4 never loads the live season. The branch was deleted afterwards |
| two earlier dispatch attempts of the revert run | same | Never ran: `gh-sim: dispatch failed`, HTTP 403 GitHub API rate limit (infrastructure). Retried |

No test newly fails, so no base comparison was needed.

## Screens (check 5)

`gh-sim launch` on HEAD with `-ScreenshotData -FixtureSlate`, run `hockey@20261106-214451-53fe-claude-imaca906-1106-233409-15141`, GitHub run 42351827705. App built, launched and stayed running.

- Trends (`-StartTab Trends`, `HotColdView`): free user on 2026-27 Regular Season. The real leader row (Leo Calloway, 1.87 to 3.70) sits over the blurred board and the Unlock StatScout+ block. Layout is unchanged and the board loaded, with no stuck spinner and no false empty state.
- Teams (`-StartTab Teams`, opens the followed club Seattle): the changed `TeamGameCard` shows "Next game, at NYR, Sun, Nov 8, 7:00 PM" with Your team and Schedule chips. It looks the same as before. Its poll now sleeps until that puck drop instead of returning.
- Games (`-StartTab Games`): slate with 2 in progress and 6 upcoming. Unchanged code, shown as the route into the game page.
- Not reached: `GameDetailView` needs a tap on a game row and there is no launch argument or deep link into it, so no screenshot. Its only change is the `.task` body (GameDetailView.swift:44), with no layout change, and the hosted-view tests cover it.

## Notes

- The review's stale comment (HotColdView.swift:185-190 says the Trends task is "keyed on entitlement", but the id has no `isPro`) is still there. It is harmless and out of scope.
- B2 regression tests use a 3 to 4 s puck drop and a `waitFor` of kickoff + 10 s. That is enough because the sleep targets kickoff + 1 s, and it keeps each test near 4 s on HEAD.
