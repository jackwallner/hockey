# State machine audit, 2026-11-06

Scope: the iOS app (`StatScout/`), committed code at `9d544cb` (working tree was clean, so `git stash -u` had nothing to stash). The repo has no widget, watch, notification or reminder code, and no backend function that the app's entitlements depend on (entitlements come only from RevenueCat; the Supabase code is data pipeline). Android is out of scope. Nothing was fixed.

**Summary: 4 bugs. 2 proved by test (B1 mechanism, B3), 2 code path only (B2, B4). 5 product calls (not counted).**

Test run: `gh-sim test --scheme StatScout --only StatScoutTests/StateMachineAuditRepro`, run `hockey@20261106-114448-3dc4-claude-imac7aa6-1106-125516-16156`, GitHub run 42292416381, Xcode 27.1, iPhone 17 simulator, iOS 27.2. Result: 4 tests, 2 passed (the controls), 2 failed (the claims). Suite: `state-machines-2026-11-06-repro.swift` (this folder).

## Existing test seams (checked before marking anything code path)

| Seam | Where | Used |
|---|---|---|
| `StoreService.shared.apply(customerInfo:)` is internal, so `@testable` reaches it | StoreService.swift:840 | yes, B1 |
| `CustomerInfo` / `EntitlementInfo` / `EntitlementInfos` are constructible (same RevenueCat 5.94.0 pin as the other fleet apps' fixtures) | `customerInfo(active:requestDate:)` in the repro | yes, B1 |
| `StatcastProviding` protocol, `DashboardViewModel(provider:cache:)` | StatcastAPI.swift:11, DashboardViewModel.swift:357 | yes, B3 (gated provider that honours cancellation) |
| `now:` parameters on `Game.status`, `GameDay.current`, `refreshLiveScores`, `ReviewPromptTracker.*` | Game.swift, DashboardViewModel.swift:443 | considered for B2, not enough (see B2) |
| `ConversionDiagnostics.defaultsOverride`, `FavoritesStore(defaults:)`, `DataFreshnessCache(defaults:)` | ConversionDiagnostics.swift:36 etc. | not needed |
| `NSTimeZone.default` / explicit `Calendar` on `GameDay.days`, `GameDay.current` | Game.swift | considered, no bug found |
| Notification scheduler | none exists in the app | n/a |
| `StoreService.purchase`, `restorePurchases`, `fetchProducts` | call `Purchases.shared`, `configureIfNeeded()` returns false on simulator | cannot run; the purchase flow is covered through `apply` |
| View `@State` (`HotColdView`, `GameDetailView`, `PlusDirectCTA`, `TeamGameCard`) | private to views, no view-inspection library in the repo | cannot run, so B2 and B4 are code path |

## Bugs, ranked by impact (users reached times cost)

| Id | Bug | What the user sees | Promise | User route | Impact | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B2 | The live-score poll on a game page or team card exits at its first check when the game has not started, and never restarts | Page opened before puck drop never gets a score. After the schedule reloads the body says "Game in progress. The score and the shot breakdown post when the game goes final." for the whole game | `/// Keeps the running score fresh while the game is under way.` (GameDetailView.swift:53, GameCards.swift:31) and the Games tab footnote "Live scores update every thirty seconds." (GamesView.swift:167) | Teams tab > a team (TeamView) > "TeamGameCard" next game, or Games tab > Upcoming row > game page. Open it before kickoff, stay (or leave the app suspended and return) past kickoff | Any fan who holds a game page or team page across puck drop. Every game day, all users, no Pro or trial dependence. Cost is a missing score for the rest of the game; backing out and reopening fixes it. Games tab itself is not affected (its poll sleeps at most 600 s, then runs) | Code path (see below) | GameDetailView.swift:44, 54-60; GameCards.swift:25, 32-39; only other caller GamesView.swift:90 |
| B1 | `StoreService.apply(customerInfo:)` has no ordering check, so an older RevenueCat answer delivered after a newer one overwrites it | A user who just paid sees Settings "Free Version", "Try Free" pills and locked boards again until the next foreground refresh or SDK push | `Text(store.isPro ? "StatScout+ Unlocked" : "Free Version")` / "All StatScout+ features are active." (SettingsView.swift:96, 106) | Onboarding last page > "Start 7-day free trial" (OnboardingCards.buyMonthly, StatScoutApp.swift) or any `PlusDirectCTA` > confirm Apple sheet. Needs a customerInfo request that began before the purchase and returns after it: the launch `.fetchCurrent` (StoreService.swift:673) on a slow connection, or the `willEnterForeground` refresh (StatScoutApp.swift:76, 88), or the delegate hop (StoreService.swift:940) | Rare: only buyers on a slow or flaky network who purchase while an earlier customerInfo request is still outstanding. Cost per hit is high (paid, looks unpaid), self-heals on next foreground | Test: `testStaleInactiveCustomerInfoDoesNotRevokeNewerActiveInfo` fails. The overlap itself is code path | StoreService.swift:840-850 |
| B3 | `loadRecentFormIfNeeded` supersedes an in-flight load for the same window by cancelling it, but the cancelled load's `defer` removes the new load's loading flag and task entry | Trends board shows "No movement to rank yet / Nobody's ... doesn't have a prior window to compare against yet" (Pro) or "No movement to rank yet" in the free leader row, instead of a spinner, until the new fetch lands | `Text(viewModel.isRecentFormLoading ? "Loading the board…" : "No movement to rank yet")` (HotColdView.swift:449) and the Pro branch that shows a spinner only while loading (HotColdView.swift:332) | Trends tab > open (first load starts) > top-left season pill > choose the other season (Pro) or Season type > Playoffs (free or Pro) before the first request returns | Every Trends user who changes the season or season type within roughly the first second of a load, plus slow-network users for longer. Cost: a few seconds of a false empty state, self-heals when the fetch lands | Test: `testSupersededRecentFormLoadDoesNotClearTheNewLoadsSpinner` fails, control passes | DashboardViewModel.swift:764-784, 810 |
| B4 | Trends keeps its own `@State selectedSeason`, so when Pro lapses mid-session on the previous season the locked board still shows and loads that season | Free user sees the real 2025-26 league leader row under a crowned (locked) pill, and the pill still reads the locked season | `/// Two seasons are offered, and the older one is Pro: the free tier is pinned to the live season everywhere, Trends included.` (HotColdView.swift:281) | Pro user on Trends > pill > previous season > subscription or trial ends while the app stays alive > foreground (`apply` flips `isPro`) > Trends tab | Very rare: needs a lapse inside a live process with the previous season selected on Trends. Cost: one teaser row of a locked season | Code path | HotColdView.swift:28, 39, 210, 382-455; `applyProState` only clamps `viewModel.selectedSeason` (DashboardViewModel.swift:180-190) |

### B1 evidence (recorded values)

```
testControlNewerInactiveInfoRevokesPro  passed (0.178 s)
testStaleInactiveCustomerInfoDoesNotRevokeNewerActiveInfo  failed (0.719 s)
  repro (as run) line 70: XCTAssertTrue failed - an older answer overwrote a newer one and locked a paying user out
  repro (as run) line 71: XCTAssertEqual failed: ("Optional(2027-01-15 07:59:00 +0000)") is not equal to ("Optional(2027-01-15 08:00:00 +0000)") - the stored info went backwards in time
```

Preconditions (`isPro` true after the purchase result, stored `requestDate == t0`, stale answer is older, stale answer has no Pro entitlement) all held, because the failures are the claim assertions and not the `precondition:` ones. Line numbers in the run output refer to the file as run, which is the saved copy minus its 3 line header (run 70, 71, 122 are saved 73, 74, 125). The control shows `apply` does revoke Pro for a genuinely newer inactive answer, so the fix is an ordering check, not "never downgrade".

What the test does not prove: that two answers actually overlap in the field. The three sources (launch fetch, foreground fetch, delegate `Task { @MainActor }` hop) are unordered with respect to each other and to a purchase. What would settle it: a `RevenueCatClient`-style seam over `Purchases.shared` (the sibling fleet apps have one) so a test can delay one customerInfo response past a purchase; or a Test Store run with a throttled network.

### B3 evidence (recorded values)

```
testControlSingleRecentFormLoadShowsSpinnerThenClears  passed (0.164 s)
testSupersededRecentFormLoadDoesNotClearTheNewLoadsSpinner  failed (0.419 s)
  repro (as run) line 122: XCTAssertTrue failed - the 2025 load is still in flight but the board is not loading
```

Preconditions that held (the `precondition:` assertions): `recentWindow == .two`; first load in flight and `isRecentFormLoading` true; provider saw requests `[2026, 2025]` in that order; exactly one request (2025) still outstanding after 300 ms; no 2025 rows landed. Mechanism: the second call changes `recentFormContext`, cancels the first task and clears `recentFormTasks` and `recentFormLoadingWindows` (lines 764-766), inserts its own flag (778) and task (810); when the cancelled first task unwinds, its `defer` (783-784) removes the flag and task entry for the same window key.

Secondary effect, not separately tested: with the task entry gone, a third `loadRecentFormIfNeeded` for that window (the view's `.task(id:)` re-running) does not find the in-flight task (line 773) and starts a duplicate request.

### B2 evidence (code path, not proved)

`GameDetailView.pollLiveScore` (lines 54-60) and `TeamGameCard.pollLiveScore` (GameCards.swift:32-39) begin each iteration with `guard ... [.inProgress, .awaitingScore].contains(game.status()) else { return }`. Both are started by `.task(id: gameId)` / `.task(id: currentGame?.id)`, which runs once per id. `Game.status()` is `.upcoming` before `kickoff` (Game.swift, `status(now:)`), so a page opened before kickoff returns at the first check and nothing restarts it: the id does not change at kickoff. `refreshLiveScores` has exactly three callers (GameDetailView.swift:57, GameCards.swift:36, GamesView.swift:90), and `liveScores` is only filled by it (DashboardViewModel.swift:443-456). The foreground refresh (`refreshOnForeground`) reloads the schedule, so the page re-renders into the "Game in progress" notice, but it never fetches live scores.

Why it is not a test: `pollLiveScore` is a private method of a SwiftUI view; the repo has no view-inspection or UI-test harness that can hold a fixture game across a kickoff (the pool UI runner is documented as unreliable in StoreKitPurchaseTests.swift). The pieces that can run (`Game.status(now:)` before and after kickoff, `refreshLiveScores(now:)`) behave correctly, so a unit test would pass and prove nothing about the loop. What would settle it: a UI test or `gh-sim launch` with a fixture game whose kickoff is 20 s after launch, open its page, wait 90 s, assert a score element; or move the loop into the view model with an injected clock and test that.

### B4 evidence (code path, not proved)

`HotColdView` copies the season at init (`_selectedSeason = State(initialValue: viewModel.recentFormSeason)`, line 39) and only resets it when the live season moves (line 210). `ContentView` pushes the lapse in through `viewModel.applyProState(false)` (StatScoutApp.swift:151), which clamps `viewModel.selectedSeason` only. The free branch (`lockedContent`, line 382) loads and draws `leaderRow` from `selectedSeason` (lines 192-195, 439). What would settle it: a view-level test that sets `isPro` false with the view holding a locked season, or moving the clamp into one shared place.

## Product calls (no citation, not counted)

1. **Season flips on 1 September, six weeks before puck drop.** `StatScoutSeason.free` becomes the new season from 1 September (StoreService.swift:55, 75), so from then until the first game free users default to an empty board while last season is Pro. Documented intent ("the moment a season starts it is the free, default year"), but the NHL season starts in October.
2. **`StatScoutSeason.current` is a `static let`**, fixed for the life of the process, and uses the device zone while the backend uses UTC (`backend/ingest.py:73`). Around 1 September a device east or west of UTC flips up to about a day apart from the pipeline. A process that survives the flip keeps the old season until relaunch.
3. **"Best & Worst (StatScout+)" is selectable by free users** and the choice is persisted in `@AppStorage("stats.board")`, so the Stats tab can cold-launch onto a blurred gate. It also blurs real rows (HotColdView does not: "everything under row one stays invented").
4. **Trends keeps its own season type.** `HotColdView` copies `viewModel.selectedPhase` once at launch, so choosing Playoffs on Stats does not carry to Trends, against the TeamsView comment "so the season you are reading never moves when you change tabs" (TeamsView.swift:125). Season is deliberately decoupled (HotColdView.swift:32); season type is not mentioned.
5. **No guard against buying while already Pro.** `purchaseInFlight` is written (StoreService.swift:732) and never read, and `purchase` does not check `isPro`. Entry points are hidden for Pro users, so it needs the entitlement to arrive while a pitch is up; the sibling apps added a guard.

Checked and not bugs: the offline cold launch of a paying user (RevenueCat sends cached info to the delegate when it is set, StoreService.swift:921/932); `fetchProducts` overlap (the calls coalesce in the SDK); `TeamStandardCard.load` leaving `loading` true on cancel (the next task always resets it before the card is visible); `GameDay.id` formatting in UTC (still unique per local day); `FollowPlayersSheet` count (hides followed players that have no row in the selected phase, but the same screen's footer says so).

## Related fixes, in order

1. B1: apply a customerInfo only if its `requestDate` is not older than the stored one (and keep the delegate hop from reordering by comparing at apply time). Add the `RevenueCatClient` seam so the overlap itself can be tested. Product call 5 (a purchase guard) belongs in the same change.
2. B3: key the `defer` cleanup on task identity (only remove the entry if it still points at this task), or do the cleanup in the caller after `await task.value`. One fix also removes the duplicate-request effect.
3. B2: restart the poll when the game's status changes, for example key `.task` on `game.status()` as well as the id, or poll on a slow cadence until the game is final. Apply the same change to `TeamGameCard`.
4. B4: move the lock clamp into one place that Trends, Compare and Teams all read (Compare's `seasonA/B` have the same shape but are blurred behind the gate, so no data leaks there).

## State machines

Legend for the invariants listed with each machine: a transition row names the invariant it breaks as `breaks Ix`.

### SM1 Entitlement (`StoreService`, `CustomerInfo`)

States: `unresolved` (isPro false, customerInfo nil, every launch until RevenueCat answers), `free` (customerInfo present, no pro), `trial` / `pro` (active entitlement, one state for the app), `lapsed` (derived: not Pro and an expired entitlement exists, `isLapsed`), plus the transient `purchasing`, `restoring`.

Invariants:
- I1: `isPro == customerInfo.hasProEntitlement` after every `apply`.
- I2: `customerInfo` never moves to an older `requestDate`.
- I3: simulator and Debug builds never configure the production key (`configureIfNeeded`, StoreService.swift:900-935).
- I4: an `unresolved` store shows free copy, never a lock for a paying user once cached info exists (the SDK delegate supplies it).
- I5: `lastError` set by one operation is cleared by the next success.

| From | Event | To | Notes |
|---|---|---|---|
| unresolved | `start()` fetchCurrent / delegate cached info | free or pro | cached info arrives through the delegate (I4) |
| free | purchase returns entitlement | pro | `ConversionDiagnostics.recordConversion` once |
| free | purchase returns no entitlement, not cancelled | free (pending) | UI message only, no persisted state |
| pro | foreground / delegate older answer | free | breaks I2, B1 |
| pro | newer inactive answer | free (lapsed) | correct, control test |
| free | restore | pro or free with `lastError` | I5 holds |
| any | `updateCustomerProductStatus` fails | unchanged, `lastError` set | I5: cleared on next success |
| pro | `purchase()` called | pro | nothing refuses it (product call 5) |

### SM2 Purchase surfaces (`PaywallView`, `PlusDirectCTA`, onboarding `buyMonthly`, `TrialPitchSheet`)

States per surface: `idle`, `purchasing`, then `unlocked` | `cancelled` | `pending` | `failed(message)` | `needsPlanPicker`. All state is view `@State`. Invariants: I6 `pending` never unlocks (holds: `.pending` needs no entitlement and `isPro` stays false); I7 the CTA label, price line and disclosure describe the plan actually bought (holds: `purchaseYearlyDirect` buys `yearlyPackage`, which is what the label and disclosure read; the winback label hides a trial the disclosure may still show only if StoreKit reports the user eligible, which StoreKit does not for a lapsed subscriber); I8 a sheet over the purchase surface dismisses when `isPro` flips (holds in `PaywallView`, `TrialPitchSheet`, `OnboardingCards`).
No bad transitions found. `pending` is shown once and lost when the sheet closes, which is acceptable because the delegate unlocks later.

### SM3 Pitch frequency (`PaywallGate`, `profileOpenCountKey`, `hasCountedOpen`)

States: per trigger session count 0, 1, 2 (cap `maxPerTrigger`, memory only), persisted profile-open counter, per-view `hasCountedOpen`. Auto pitch fires for `!isPro`, opens >= 2, count < 2. Invariants: I9 at most two automatic pitches per trigger per launch (holds, `markPresented` runs in both sheets); I10 a Pro user is never auto-pitched (holds once `isPro` has resolved; the unresolved window is covered by I4).

### SM4 Season, season type and Pro lock (`DashboardViewModel.selectedSeason/selectedPhase/isPro`, view copies)

States: `selectedSeason` x `selectedPhase` in the view model (shared by Stats, Teams, Games title, team pages); private copies in `HotColdView` (season, phase) and `CompareView` (season A/B, phase A/B, team seasons), made once at construction because all five tabs are mounted from launch (RootTabView.swift, `tabView`).
Invariants: I11 a free user is never left on a locked season (holds for the view model via `clampSelectedSeason`; fails for the Trends copy, B4); I12 menu taps on a locked season open a pitch and do not change the season (holds in Stats, Teams, Trends, Team page); I13 changing the season loads the history it needs (holds in `selectSeason`; the Team page and Teams "Show" button assign `selectedSeason` directly, which is safe because `ContentView.task(id: isPro)` already loads history for Pro).

| From | Event | To | Notes |
|---|---|---|---|
| Pro, season 2025 | `isPro` -> false | viewModel clamps to live; Trends copy stays 2025 | breaks I11, B4 |
| any | Stats picks Playoffs | viewModel phase changes, Trends/Compare copies unchanged | product call 4 |
| free | taps locked season | pitch, season unchanged | I12 |

### SM5 Data load and freshness (`loadTask`, `freshnessCheckTask`, `displayedDataRevision`, `lastFetchFailed`, `DataFreshnessCache`)

States: `idle`, `checking`, `loading`, `loaded(revision)`, `failed(saved data shown)`, `pendingRevision` (server revision ahead of displayed). Single-flight on both tasks. Invariants: I14 a revision is adopted only when the start and end status reads agree (holds, `revisionDrifted`); I15 recent-form cache is cleared only after a new revision is adopted (holds, `adoptLoadedRevision`); I16 a failed load keeps the previous rows (holds); I17 a persisted `displayedDataRevision` does not claim data that the disk cache no longer holds (can be false after the OS purges Caches while UserDefaults survives, but the next load always refetches current players, so the only effect is the freshness caption; not a bug).
Transitions are all single-flight with `defer` cleanup; no bad transition found. A failed load re-triggers a full load on every 5 minute poll while the server revision differs from the displayed one, which is intended retry.

### SM6 Recent form cache (`recentFormContext`, `recentFormTasks`, `recentFormLoadingWindows`, `recentFormByWindow`)

States per window: `empty`, `loading(task)`, `loaded`, `error`. One shared context key `"season-phase"`; a different context clears every window. Consumers with different contexts: Trends (own season and phase), Team page roster (`viewModel.selectedSeason/Phase`). Invariants: I18 `isRecentFormLoading` is true exactly while a task for the window is in flight; I19 an older response never lands in a newer context (holds: context compare before write); I20 one task per window.

| From | Event | To | Notes |
|---|---|---|---|
| loading(2026) | call with 2025 | loading(2025), old task cancelled | cancelled task's `defer` clears flag and task entry, breaks I18 and I20, B3 |
| loaded(2026) | other consumer loads 2025 | empty(2026) | by design; the Trends `.task` restarts when its view reappears after a push, and on tab change via `isActive` in its id, so the board reloads |
| loaded | revision adopted | empty | I15 |

### SM7 Games and live scores (`games`, `liveScores`, `GameStatus`, `GameDay`, pollers)

`GameStatus` is derived from the clock only: `upcoming` -> `inProgress` (at kickoff) -> `awaitingScore` (3.25 h later) -> `final` (scores posted). Live scores come from the NHL scoreboard through `refreshLiveScores`. Invariants: I21 while a game is `inProgress` or `awaitingScore`, something polls its score every 30 s (holds on the Games tab; fails on a game page or team card opened before kickoff, B2); I22 a game with a posted final never shows a live score (holds, `liveScore(for:)` returns nil for finals); I23 the "current day" follows the clock and zone (holds: `GameDay.current` is recomputed each read; the 14:00 rule and `startOfDay` use the passed calendar; a zone change makes `GameDay.id` strings differ, so a pinned day falls back to the current day, which is a reasonable reset).

| From | Event | To | Notes |
|---|---|---|---|
| upcoming (page open) | kickoff passes | inProgress, no poller | breaks I21, B2 |
| inProgress | schedule shows final | final, poller exits, live score hidden | I22 |
| any | schedule fetch fails | keeps last schedule | by design |

### SM8 Review prompt (`ReviewPromptTracker`, `RootTabView.scheduleReviewRequestAfterPositiveMoment`)

States: launch count, first open, last shown, outcome (`nil` | `openedWriteReview` | `submittedFeedback`), pending positive moment, `reviewPromptShownThisSession`. Invariants: I24 no passive ask before the second launch or before onboarding (holds); I25 30 day cooldown from `lastShownDate` (holds; a `lastShownDate` set in the future by a clock change blocks until the clock catches up, which is a clock edge, not counted); I26 `openedWriteReview` ends passive asks and `submittedFeedback` never does (holds, tests exist); I27 nothing is asked over a presented sheet (holds via `isScreenClear`; the moment stays pending).

### SM9 Onboarding (`hasCompletedOnboarding`)

States: `showing(page 0...2)` -> `done`. Exits: Skip, Get Started, purchase success (`isPro` flips), restore success. Invariant I28: once `done`, never shown again (holds; `@AppStorage`). A pending Ask to Buy leaves onboarding up with a message, and approval later flips `isPro` and completes it. No bad transition.

### SM10 Following (`FavoritesStore`)

State: ordered `[playerId]` plus optional team, written through to `UserDefaults` on every change. Single shared instance. Invariants: I29 the stored list equals the in-memory list (holds); I30 a followed id is removable from some screen (holds: the player profile star and the Following list remove it; the Manage sheet only lists players present in the selected season and phase, so a followed player without a row there is removed from their profile or by changing the season type).

### SM11 Player cache provenance (`TwoTierPlayerCache`)

States: no snapshot, snapshot without marker (discarded once), snapshot with marker (kept whatever its age), historical plist (disk copy, else bundled archive). Invariants: I31 a snapshot of unknown origin never populates the live board (holds, `loadCurrentPlayers`); I32 saving the live season never overwrites the permanent historical copy (holds as long as the live feed returns only the live season; `savePlayers` would replace the historical plist with whatever historical rows it is handed, and the one caller passes live rows only).

### SM12 Stats board mode (`@AppStorage("stats.board")`, `fellBackFromAdvanced`)

States: `advanced` | `standard` | `bestWorst` (persisted), plus a transient fallback flag when a cohort has no advanced line. Invariant I33: a persisted mode is always valid for the current entitlement (fails by design for `bestWorst`, which free users can persist, product call 3).
