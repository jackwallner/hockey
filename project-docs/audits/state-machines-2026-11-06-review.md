# State machine audit review, 2026-11-06

Independent review of [state-machines-2026-11-06.md](state-machines-2026-11-06.md) and its [repro suite](state-machines-2026-11-06-repro.swift). Every claim was rechecked against the code at `8f2d4e3` (working tree clean, nothing to stash). No app code was changed.

**Summary: 4 claims. 1 CONFIRMED (B2), 2 CONFIRMED-MINOR (B3, B4), 1 NOT A BUG (B1), 0 UNVERIFIED. False-positive rate 1 of 4 (25%). Of the 5 product calls, none is a bug; 1 (PC4) reads a promise into a comment that does not make one.**

## Test runs

One gh-sim run held both the audit's repro suite (rerun once, unchanged) and this review's own checks: `hockey@20261106-133601-2f57-claude-mbprof0dc-1106-134352-4132`, GitHub run 42299119837, Xcode 27.1, iPhone 17 simulator, iOS 27.2.

| Suite / test | Result | What it shows |
|---|---|---|
| Repro `testControlNewerInactiveInfoRevokesPro` | passed 0.179 s | same as recorded |
| Repro `testStaleInactiveCustomerInfoDoesNotRevokeNewerActiveInfo` | failed, lines 70 and 71 (as run) | same as recorded: `apply` keeps whatever it is handed last |
| Repro `testControlSingleRecentFormLoadShowsSpinnerThenClears` | passed 0.115 s | same as recorded |
| Repro `testSupersededRecentFormLoadDoesNotClearTheNewLoadsSpinner` | failed, line 122 (as run) | same as recorded |
| Review `testB2ControlGamePageOpenedMidGamePolls` | passed 0.228 s | a hosted `GameDetailView` for a game already under way reads the scoreboard at once |
| Review `testB2GamePageOpenedBeforePuckDropGetsTheScore` | failed 40.1 s | page opened 5 s before puck drop: 0 scoreboard reads in the 35 s after it, no live score |
| Review `testB2ControlTeamCardMidGamePolls` | passed 0.159 s | a hosted `TeamGameCard` polls a game under way |
| Review `testB2TeamCardOpenedBeforePuckDropGetsTheScore` | failed 40.1 s | same failure on the team page card |
| Review `testB2GamesTabPushedPageWithAnotherGameLive` | failed 41.4 s | Games tab composition with another game live: the slate's own 30 s poll made 1 read, then stopped when the page was pushed (`liveCallsAfterPush=1 liveCallsAtEnd=1`), so it does not rescue the pushed page |
| Review `testB3SupersedeWithOuterTaskCancelledAndOldRequestAnswering` | failed (both claim asserts) | UI-faithful B3: outer `.task` cancelled first, old request answers after 0.3 s and ignores cancellation. Flag still lost; a third caller starts a duplicate request (3 requests, expected 2) |

All `precondition:` asserts held. The run was cancelled after the last test hung at its final `await`: the first version of this review's fake overwrote a held continuation once the duplicate request fired, so the second load never resumed. Every assertion had already been recorded. The appendix holds the corrected file (continuations kept in a list, bounded final wait), which differs from the run only in that teardown. Two other runs were cancelled while still queued (42298167533, 42310728096) and produced nothing. Both test files were removed from `StatScoutTests/` afterwards.

## Verdicts

| Id | Verdict | User route | Impact | Evidence |
|---|---|---|---|---|
| B1 | NOT A BUG | None reachable. The audit's route needs a RevenueCat answer that was requested before a purchase to be delivered after the purchase result. RevenueCat 5.94.0 (the pinned version) prevents that | None in practice. A `requestDate` check in `apply` would be cheap hardening, not a fix | `apply` has no ordering check (StoreService.swift:840-850), but every source is ordered upstream: `getCustomerInfo` and `post(receipt:)` both run on the default lane's `OperationQueue` with `maxConcurrentOperationCount = 1` (purchases-ios 5.94.0 `Backend.swift:286-289`, `CustomerAPI.swift:65, 193`). A GET issued while a receipt POST is pending is attached to that POST's callbacks (`CustomerAPI.swift:64`, `addOrAppendToPostReceiptDataOperation`), so it receives the post-purchase info. GET jitter applies only to a backgrounded app (`OperationDispatcher.swift:28-29`), and a purchase cannot start in the background. The launch fetch (StoreService.swift:673) is enqueued before any purchase and completes first. The Apple sheet alone takes seconds. The delegate hop (StoreService.swift:938-942) carries the same info as the direct `apply` and is enqueued earlier. The repro test calls `apply` directly with invented dates. It shows only that the guard is missing, which nobody disputes, and asserts the auditor's own invariant I2. The cited Settings label (SettingsView.swift:96, 106) just mirrors `isPro` and promises nothing about ordering |
| B2 | CONFIRMED | Any iPhone, free or Pro. Games tab > Upcoming row (or "Your team") > game page, or Teams tab > team > game card. Open before puck drop, then stay on the page or lock the phone and come back after puck drop | Highest in the audit. Any fan who opens a game or team page before a game and comes back to it, any game night. Cost: no running score for the whole game. The header reads "In progress" and the body reads "The score and the shot breakdown post when the game goes final." (GameDetailView.swift:206-208). Pull to refresh does not fix it (it reloads the schedule and the detail, not live scores: GameDetailView.swift:39-42). Switching tabs does not fix it either, because tabs stay mounted in a `ZStack` and never disappear (RootTabView.swift:104-112). Only backing out and reopening fixes it | Proved by the hosted-view tests above. Code: the `guard` returns at the first check (GameDetailView.swift:54-60, GameCards.swift:32-39), and `.task(id: gameId)` / `.task(id: currentGame?.id)` (GameDetailView.swift:44, GameCards.swift:27) do not re-run at puck drop. The promise is real: `/// Keeps the running score fresh while the game is under way.` (GameDetailView.swift:53, GameCards.swift:31). The audit's second citation, the Games tab footnote (GamesView.swift:167), describes the slate, not the game page, so it is weak support. The audit missed that the slate's poll stops under a pushed page, which is why B2 also bites on busy nights from the Games tab |
| B3 | CONFIRMED-MINOR | Any iPhone. Trends tab, as the board's first load runs: pill > Season type > Playoffs (free and Pro: SavantMenus.swift:111-123, HotColdView.swift:182) or pill > the other season (Pro only, HotColdView.swift:284-291). Or flip twice quickly: every flip changes the context, clears the cache and starts a fresh load (DashboardViewModel.swift:764-771), so the second flip lands inside the first flip's load | Low. The tap has to land inside one small request, which needs a slow network or two quick flips. Cost: for the rest of that fetch, the Pro board shows "No movement to rank yet / ... doesn't have a prior window to compare against yet" (HotColdView.swift:332, 360-366) and the free leader row shows "No movement to rank yet" (HotColdView.swift:449) instead of a spinner. It fills once the fetch lands. Side effect: the next caller for that window issues a duplicate request. The audit's "every Trends user who changes within roughly the first second" overstates how often a two-tap menu change beats one request | Repro rerun fails as recorded. This review's variant, which matches the UI (outer task cancelled first, old request answered regardless), fails too and confirms the duplicate request. Mechanism: the cancelled task's `defer` removes the window key that the new load now owns (DashboardViewModel.swift:780-784, set at 778 and 810). The promise is the view's own copy, a spinner while loading, rather than a doc rule |
| B4 | CONFIRMED-MINOR | Any iPhone. Pro or trial user: Trends > pill > previous season. Then the entitlement ends while the process stays alive (trial or subscription expiry, refund), and the app returns to the foreground. `updateCustomerProductStatus` (StatScoutApp.swift:76/88) or the delegate flips `isPro` | Very rare. Needs a lapse inside a live process with the old season selected on Trends. Cost: one real leader row of a season the user no longer has, under a pill showing that locked season. Picking the live season in the pill recovers | Not run: the season can only be set through a SwiftUI `Menu` and there is no seam. The code leaves no doubt, though. `selectedSeason` is written only at HotColdView.swift:39 (init), 211 (live season moved) and 289 (unlocked pick). The view's `@State` survives because tabs are never unmounted (RootTabView.swift:104-112). The lapse reaches only the view model's clamp (StatScoutApp.swift:151, DashboardViewModel.swift:180-190). The locked branch draws and loads from `selectedSeason` (HotColdView.swift:155-166, 196-203, 434-449). The cited rule is a real doc comment: "the free tier is pinned to the live season everywhere, Trends included" (HotColdView.swift:281-283). What would settle it by test: a debug lapse hook plus a UI test, or moving the clamp into the view model |

## What survived, ranked

1. **B2** (CONFIRMED). The game page and team card never get a live score if they were opened before puck drop. It hits every game night, needs no Pro and lasts all game. The audit ranked it first, correctly.
2. **B3** (CONFIRMED-MINOR). A false empty Trends board for a few seconds after a quick season or season type change, plus one duplicate request. Moves up from third because B1 is out.
3. **B4** (CONFIRMED-MINOR). Trends keeps a locked season after Pro lapses mid-session. One teaser row, very rare.

B1 drops out. The audit ranked it second with "cost per hit is high" while its own evidence section said the overlap was unproven. The SDK rules the overlap out.

## Product calls

| # | Review |
|---|---|
| PC1 September flip | Documented decision, not a bug. StoreService.swift:44-48 states the September rule and its match with `backend/ingest.py:73`, and 68-74 says the live season is free "the moment a season starts" and explains why trailing the data was dropped. Any empty board falls in September, before games exist. Fair as a product question, low priority |
| PC2 `static let` and zone | Accurate (StoreService.swift:55, 63-66) but negligible. The skew is a few hours on one night a year. The floor at 2026 means the first possible flip is September 2027, and the process would have to stay alive across it |
| PC3 Best & Worst persisted | Accurate. It is a deliberate gate: crown label at StatsBoardControls.swift:294, blur and unlock at StatsView.swift:139-156. `@AppStorage("stats.board")` (StatsView.swift:9) does let a free user cold-launch onto the gate, and the blurred rows are real data. The "rows stay invented" rule it cites is local to Trends (HotColdView.swift:380), not app-wide. Valid product call |
| PC4 Trends season type | Overstated. TeamsView.swift:128-129 says the shared header keeps the season you are reading from moving between tabs, which describes the shared modifier, not a sync promise. Trends deliberately keeps its own copies (HotColdView.swift:33-40). A product question at most |
| PC5 no purchase guard | Accurate: `purchaseInFlight` is written (StoreService.swift:732-733) and never read. StoreKit already refuses to rebuy the same active subscription, so the exposure is a cross-grade while Pro, which needs the entitlement to arrive with a pitch on screen. Low |

## Missed state issues (in scope only)

- Part of B2, not counted separately: the Games slate's poll (`GamesView.task(id: isActive)`, GamesView.swift:70-73) stops while a game page is pushed over it, as the test measured. So nothing polls live scores while a fan reads a game page on the Games tab unless that page's own loop is running.
- Stale comment, not a bug: HotColdView.swift:185-190 says the Trends task is "keyed on entitlement", but its id (line 197) has no `isPro`. That is harmless now, because free users load the same rollup.

No other serious state bug turned up in the code read for these claims.

## Method changes that would have prevented the errors

1. **For any ordering or race claim, read the ordering guarantees of the layer that produces the events, at the pinned version, before calling it a bug.** B1's three "unordered" sources run on one serial queue in RevenueCat 5.94.0, which takes ten minutes to check in the SDK source. A missing guard against an event the producer never emits is hardening, not a bug.
2. **Do not count a test that calls a service directly with invented inputs as proof of a user-facing bug.** It proves the mechanism only. Rank a claim by its route evidence, and keep a claim whose route is "code path" below claims whose route is proved.
3. **Before declaring view state untestable, try hosting the real view.** The test bundle is app-hosted, so a `UIHostingController` in a `UIWindow` on the app's scene runs the view's `.task` modifiers against a fake provider. That proved B2 in 40 s per test, and it also measured the slate poll stopping under a push, which the audit had assumed did not matter.
4. **Check recovery paths when stating cost.** The audit said backing out fixes B2 but did not check pull to refresh or tab switches. Neither fixes it, which is part of the real cost.
5. **Read a cited comment for what it governs.** PC4 treated a header layout comment as a sync promise.
6. **Bound every await in repro tests and run with `-test-timeouts-enabled YES`.** This review's first fake hung a GitHub Mac for over an hour after all its assertions had run. Releasing all held continuations and waiting with a deadline avoids that.

## Appendix: review checks

Copy to `StatScoutTests/StateMachineReviewChecks.swift`, run `gh-sim test --scheme StatScout --only StatScoutTests/StateMachineReviewChecks --testarg -test-timeouts-enabled --testarg YES`, then delete the copy. Failing tests are the confirmations. The controls pass.

```swift
import SwiftUI
import UIKit
import XCTest
@testable import Hockey_StatScout

/// Independent review of the 2026-11-06 state machine audit. Hosts the real
/// views in a window so their `.task` modifiers run, with a fake provider that
/// counts scoreboard reads. Temporary: not part of the shipping test target.
@MainActor
final class StateMachineReviewChecks: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try await super.tearDown()
    }

    private func host<V: View>(_ view: V) throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let windowScene = try XCTUnwrap(scene, "precondition: the test host has a window scene")
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: view.environmentObject(StoreService.shared))
        window.makeKeyAndVisible()
        self.window = window
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func waitFor(_ seconds: Double, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !condition() { await sleep(0.1) }
    }

    private func game(_ id: String, kickoff: Date, away: String = "SEA", home: String = "EDM") -> Game {
        Game(id: id, season: StatScoutSeason.free, week: 1, kickoff: kickoff, awayTeam: away, homeTeam: home)
    }

    private func model(provider: LiveCountingProvider) async -> DashboardViewModel {
        let vm = DashboardViewModel(provider: provider)
        await vm.loadGames(force: true)
        return vm
    }

    // MARK: - B2: game page

    func testB2ControlGamePageOpenedMidGamePolls() async throws {
        let g = game("live", kickoff: Date().addingTimeInterval(-600))
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        XCTAssertEqual(vm.games.count, 1, "precondition: schedule loaded")
        try host(NavigationStack { GameDetailView(viewModel: vm, gameId: g.id) })
        await waitFor(10) { provider.liveCalls > 0 }
        XCTAssertGreaterThan(provider.liveCalls, 0, "control: a page opened mid-game reads the scoreboard")
        XCTAssertNotNil(vm.liveScore(for: g), "control: the running score is on the page")
    }

    func testB2GamePageOpenedBeforePuckDropGetsTheScore() async throws {
        let kickoff = Date().addingTimeInterval(5)
        let g = game("soon", kickoff: kickoff)
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        try host(NavigationStack { GameDetailView(viewModel: vm, gameId: g.id) })
        await sleep(2)
        XCTAssertEqual(g.status(), .upcoming, "precondition: the page opened before puck drop")
        XCTAssertEqual(provider.liveCalls, 0, "precondition: no scoreboard read before puck drop")
        // Past puck drop by more than one full 30 s poll cycle.
        await sleep(kickoff.timeIntervalSinceNow + 35)
        XCTAssertEqual(g.status(), .inProgress, "precondition: the game is under way")
        XCTAssertGreaterThan(provider.liveCalls, 0, "B2: page held across puck drop never reads the scoreboard")
        XCTAssertNotNil(vm.liveScore(for: g), "B2: page held across puck drop has no running score")
    }

    // MARK: - B2: team page card

    func testB2ControlTeamCardMidGamePolls() async throws {
        let g = game("live", kickoff: Date().addingTimeInterval(-600))
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        XCTAssertNotNil(vm.currentGameDay, "precondition: the card has a game day")
        try host(NavigationStack { ScrollView { TeamGameCard(viewModel: vm, team: "SEA") } })
        await waitFor(10) { provider.liveCalls > 0 }
        XCTAssertGreaterThan(provider.liveCalls, 0, "control: the team card polls a game under way")
    }

    func testB2TeamCardOpenedBeforePuckDropGetsTheScore() async throws {
        let kickoff = Date().addingTimeInterval(5)
        let g = game("soon", kickoff: kickoff)
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        XCTAssertNotNil(vm.currentGameDay, "precondition: the card has a game day")
        XCTAssertEqual(vm.currentGame(forTeam: "SEA")?.id, g.id, "precondition: the card shows this game")
        try host(NavigationStack { ScrollView { TeamGameCard(viewModel: vm, team: "SEA") } })
        await sleep(2)
        XCTAssertEqual(provider.liveCalls, 0, "precondition: no scoreboard read before puck drop")
        await sleep(kickoff.timeIntervalSinceNow + 35)
        XCTAssertEqual(g.status(), .inProgress, "precondition: the game is under way")
        XCTAssertGreaterThan(provider.liveCalls, 0, "B2: team card held across puck drop never reads the scoreboard")
    }

    // MARK: - B2: Games tab route, with another game already live

    /// The Games tab composition: the slate's own 30 s poll, then the upcoming
    /// game's page pushed on top. Answers whether the slate's poll keeps
    /// running under the pushed page (it would mask B2 on busy nights).
    func testB2GamesTabPushedPageWithAnotherGameLive() async throws {
        let kickoff = Date().addingTimeInterval(6)
        let live = game("live", kickoff: Date().addingTimeInterval(-600), away: "BOS", home: "TOR")
        let soon = game("soon", kickoff: kickoff)
        let provider = LiveCountingProvider(games: [live, soon])
        let vm = await model(provider: provider)
        let router = ReviewRouter()
        try host(GamesTabHarness(viewModel: vm, router: router))
        await waitFor(10) { provider.liveCalls > 0 }
        XCTAssertGreaterThan(provider.liveCalls, 0, "precondition: the slate polls while a game is live")
        router.path = [GameRoute(gameId: soon.id)]
        await sleep(1)
        let afterPush = provider.liveCalls
        await sleep(kickoff.timeIntervalSinceNow + 35)
        XCTAssertEqual(soon.status(), .inProgress, "precondition: the pushed game is under way")
        print("REVIEW-B2-GAMESTAB liveCallsAfterPush=\(afterPush) liveCallsAtEnd=\(provider.liveCalls)")
        XCTAssertNotNil(vm.liveScore(for: soon), "B2 on the Games tab route: the pushed page has no running score")
    }

    // MARK: - B3: UI-faithful supersede

    /// The Trends `.task(id:)` is cancelled before the new one starts, and a
    /// real URLSession may answer the old request anyway. Neither saves the
    /// new load's flag.
    func testB3SupersedeWithOuterTaskCancelledAndOldRequestAnswering() async throws {
        let provider = SlowFirstProvider()
        let vm = DashboardViewModel(provider: provider)
        let first = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .regular) }
        await waitFor(5) { provider.requested.count >= 1 }
        XCTAssertTrue(vm.isRecentFormLoading, "precondition: first load in flight")
        first.cancel()
        let second = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .playoffs) }
        await waitFor(5) { provider.requested.count >= 2 }
        // The 2026 regular request answers after 0.3 s whatever the cancel.
        await sleep(0.8)
        XCTAssertEqual(provider.requested, ["2026-REG", "2026-POST"], "precondition: both requests made")
        XCTAssertTrue(provider.holdingPlayoffs, "precondition: the playoffs request is still out")
        XCTAssertTrue(vm.isRecentFormLoading, "B3: the playoffs load is in flight but the board is not loading")

        // Secondary claim: the next caller for the window starts a duplicate.
        let third = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .playoffs) }
        await sleep(0.5)
        XCTAssertEqual(provider.requested.count, 2, "B3 secondary: a third caller started a duplicate request")
        provider.release()
        // Bounded: never let a leaked continuation hang the run.
        await waitFor(3) { !vm.isRecentFormLoading }
        _ = (second, third)
    }
}

@Observable
private final class ReviewRouter {
    var path: [GameRoute] = []
}

private struct GamesTabHarness: View {
    let viewModel: DashboardViewModel
    @Bindable var router: ReviewRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            GamesView(viewModel: viewModel, isActive: true)
                .navigationDestination(for: GameRoute.self) { route in
                    GameDetailView(viewModel: viewModel, gameId: route.gameId)
                }
        }
    }
}

/// Returns the schedule it was given and a live score for every game asked
/// about, counting scoreboard reads.
private final class LiveCountingProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let games: [Game]
    private var calls = 0

    init(games: [Game]) { self.games = games }

    var liveCalls: Int { lock.withLock { calls } }

    func fetchGames(season: Int) async throws -> [Game] { games }

    func fetchLiveScores(dates: Set<String>) async -> [String: LiveScore] {
        lock.withLock { calls += 1 }
        return Dictionary(uniqueKeysWithValues: games.map { game in
            (game.id, LiveScore(
                gameId: game.id, awayScore: 1, homeScore: 2, awayShots: 10, homeShots: 12,
                state: "LIVE", period: 1, periodType: "REG", timeRemaining: "12:00", inIntermission: false
            ))
        })
    }

    func fetchPlayers() async throws -> [Player] { [] }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}

/// Answers the regular-season request after 0.3 s and ignores cancellation,
/// like a request already on the wire; holds the playoffs request until released.
private final class SlowFirstProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var held: [CheckedContinuation<[RecentForm], Never>] = []

    var requested: [String] { lock.withLock { log } }
    var holdingPlayoffs: Bool { lock.withLock { !held.isEmpty } }

    func release() {
        let all = lock.withLock { () -> [CheckedContinuation<[RecentForm], Never>] in
            defer { held.removeAll() }
            return held
        }
        for c in all { c.resume(returning: []) }
    }

    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] {
        lock.withLock { log.append("\(season)-\(seasonPhase.rawValue)") }
        if seasonPhase == .regular {
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { continuation.resume(returning: []) }
            }
        }
        return await withCheckedContinuation { continuation in
            lock.withLock { held.append(continuation) }
        }
    }

    func fetchPlayers() async throws -> [Player] { [] }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}
```
