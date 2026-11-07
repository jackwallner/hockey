import SwiftUI
import UIKit
import XCTest
@testable import Hockey_StatScout

/// Regression tests for the 2026-11-06 state machine review
/// (project-docs/audits/state-machines-2026-11-06-review.md). The B2 and B4
/// tests host the real views in a window so their `.task` modifiers run.
@MainActor
final class StateMachineRegressionTests: XCTestCase {
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

    // MARK: - B2: live score on a page opened before puck drop

    func testGamePageOpenedMidGamePolls() async throws {
        let g = game("live", kickoff: Date().addingTimeInterval(-600))
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        XCTAssertEqual(vm.games.count, 1, "precondition: schedule loaded")
        try host(NavigationStack { GameDetailView(viewModel: vm, gameId: g.id) })
        await waitFor(10) { provider.liveCalls > 0 }
        XCTAssertGreaterThan(provider.liveCalls, 0)
        XCTAssertNotNil(vm.liveScore(for: g))
    }

    func testGamePageOpenedBeforePuckDropGetsTheScore() async throws {
        let kickoff = Date().addingTimeInterval(3)
        let g = game("soon", kickoff: kickoff)
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        try host(NavigationStack { GameDetailView(viewModel: vm, gameId: g.id) })
        await sleep(1)
        XCTAssertEqual(g.status(), .upcoming, "precondition: the page opened before puck drop")
        XCTAssertEqual(provider.liveCalls, 0, "precondition: no scoreboard read before puck drop")
        await waitFor(kickoff.timeIntervalSinceNow + 10) { provider.liveCalls > 0 }
        XCTAssertEqual(g.status(), .inProgress, "precondition: the game is under way")
        XCTAssertGreaterThan(provider.liveCalls, 0, "a page held across puck drop reads the scoreboard")
        XCTAssertNotNil(vm.liveScore(for: g), "a page held across puck drop shows the running score")
    }

    func testTeamCardMidGamePolls() async throws {
        let g = game("live", kickoff: Date().addingTimeInterval(-600))
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        XCTAssertNotNil(vm.currentGameDay, "precondition: the card has a game day")
        try host(NavigationStack { ScrollView { TeamGameCard(viewModel: vm, team: "SEA") } })
        await waitFor(10) { provider.liveCalls > 0 }
        XCTAssertGreaterThan(provider.liveCalls, 0)
    }

    func testTeamCardOpenedBeforePuckDropGetsTheScore() async throws {
        let kickoff = Date().addingTimeInterval(3)
        let g = game("soon", kickoff: kickoff)
        let provider = LiveCountingProvider(games: [g])
        let vm = await model(provider: provider)
        XCTAssertNotNil(vm.currentGameDay, "precondition: the card has a game day")
        XCTAssertEqual(vm.currentGame(forTeam: "SEA")?.id, g.id, "precondition: the card shows this game")
        try host(NavigationStack { ScrollView { TeamGameCard(viewModel: vm, team: "SEA") } })
        await sleep(1)
        XCTAssertEqual(provider.liveCalls, 0, "precondition: no scoreboard read before puck drop")
        await waitFor(kickoff.timeIntervalSinceNow + 10) { provider.liveCalls > 0 }
        XCTAssertEqual(g.status(), .inProgress, "precondition: the game is under way")
        XCTAssertGreaterThan(provider.liveCalls, 0, "a team card held across puck drop reads the scoreboard")
        XCTAssertNotNil(vm.liveScore(for: g))
    }

    /// Games tab: the slate's poll stops once a game page is pushed over it,
    /// so the pushed page has to keep its own score fresh.
    func testGamesTabPushedPageWithAnotherGameLiveGetsTheScore() async throws {
        let kickoff = Date().addingTimeInterval(4)
        let live = game("live", kickoff: Date().addingTimeInterval(-600), away: "BOS", home: "TOR")
        let soon = game("soon", kickoff: kickoff)
        let provider = LiveCountingProvider(games: [live, soon])
        let vm = await model(provider: provider)
        let router = RegressionRouter()
        try host(GamesTabHarness(viewModel: vm, router: router))
        await waitFor(10) { provider.liveCalls > 0 }
        XCTAssertGreaterThan(provider.liveCalls, 0, "precondition: the slate polls while a game is live")
        router.path = [GameRoute(gameId: soon.id)]
        await sleep(1)
        let afterPush = provider.liveCalls
        await waitFor(kickoff.timeIntervalSinceNow + 10) { vm.liveScore(for: soon) != nil && provider.liveCalls > afterPush }
        XCTAssertEqual(soon.status(), .inProgress, "precondition: the pushed game is under way")
        XCTAssertGreaterThan(provider.liveCalls, afterPush, "the pushed page reads the scoreboard after puck drop")
        XCTAssertNotNil(vm.liveScore(for: soon), "the pushed page shows the running score")
    }

    // MARK: - B3: superseded recent form load

    private func waitForRequests(_ count: Int, on provider: GatedRecentFormProvider) async throws {
        for _ in 0..<500 {
            if provider.requestedSeasons.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("provider never received \(count) requests")
    }

    func testSingleRecentFormLoadShowsSpinnerThenClears() async throws {
        let provider = GatedRecentFormProvider()
        let vm = DashboardViewModel(provider: provider)
        XCTAssertEqual(vm.recentWindow, .two, "precondition: the board reads the 2 week window")
        let load = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .regular) }
        try await waitForRequests(1, on: provider)
        XCTAssertTrue(vm.isRecentFormLoading)
        provider.releaseAll()
        await load.value
        XCTAssertFalse(vm.isRecentFormLoading)
    }

    /// The cancelled load's cleanup used to clear the new load's loading flag.
    func testSupersededRecentFormLoadDoesNotClearTheNewLoadsSpinner() async throws {
        let provider = GatedRecentFormProvider()
        let vm = DashboardViewModel(provider: provider)
        XCTAssertEqual(vm.recentWindow, .two, "precondition: the board reads the 2 week window")

        let first = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .regular) }
        try await waitForRequests(1, on: provider)
        XCTAssertTrue(vm.isRecentFormLoading, "precondition: first load in flight")

        let second = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2025, phase: .regular) }
        try await waitForRequests(2, on: provider)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(provider.requestedSeasons, [2026, 2025], "precondition: both requests were made in order")
        XCTAssertEqual(provider.outstandingCount, 1, "precondition: only the 2025 request is still outstanding")
        XCTAssertTrue(vm.isRecentFormLoading, "the 2025 load is still in flight, so the board is loading")

        provider.releaseAll()
        await second.value
        await first.value
        XCTAssertFalse(vm.isRecentFormLoading)
    }

    /// The UI order: the Trends `.task` is cancelled before the new one starts,
    /// and the old request answers anyway. The flag holds and a third caller
    /// joins the in-flight load instead of starting a duplicate.
    func testSupersedeWithOuterTaskCancelledAndOldRequestAnswering() async throws {
        let provider = SlowFirstProvider()
        let vm = DashboardViewModel(provider: provider)
        let first = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .regular) }
        await waitFor(5) { provider.requested.count >= 1 }
        XCTAssertTrue(vm.isRecentFormLoading, "precondition: first load in flight")
        first.cancel()
        let second = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .playoffs) }
        await waitFor(5) { provider.requested.count >= 2 }
        await sleep(0.8)
        XCTAssertEqual(provider.requested, ["2026-REG", "2026-POST"], "precondition: both requests made")
        XCTAssertTrue(provider.holdingPlayoffs, "precondition: the playoffs request is still out")
        XCTAssertTrue(vm.isRecentFormLoading, "the playoffs load is in flight, so the board is loading")

        let third = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .playoffs) }
        await sleep(0.5)
        XCTAssertEqual(provider.requested.count, 2, "a third caller joins the in-flight load")
        provider.release()
        await waitFor(3) { !vm.isRecentFormLoading }
        XCTAssertFalse(vm.isRecentFormLoading)
        _ = (second, third)
    }

    // MARK: - B4: Trends season after a lapse

    func testTrendsDropsALockedSeasonWhenProLapses() async throws {
        let provider = RecentFormSeasonProvider()
        let vm = DashboardViewModel(provider: provider)
        vm.applyProState(true)
        let live = vm.recentFormSeason
        let prior = live - 1
        try XCTSkipUnless(vm.supportsRecentForm(prior), "needs two Recent Form seasons")
        XCTAssertFalse(vm.isSeasonLocked(prior), "precondition: Pro unlocks the prior season")

        try host(NavigationStack { HotColdView(viewModel: vm, season: prior) })
        await waitFor(5) { provider.seasons.contains(prior) }
        XCTAssertTrue(provider.seasons.contains(prior), "precondition: Trends loads the prior season")
        XCTAssertFalse(provider.seasons.contains(live), "precondition: the live season has not loaded")

        vm.applyProState(false)
        XCTAssertTrue(vm.isSeasonLocked(prior), "precondition: the lapse locks the prior season")
        await waitFor(5) { provider.seasons.contains(live) }
        XCTAssertTrue(provider.seasons.contains(live), "after a lapse Trends moves to the live season")
    }
}

@Observable
private final class RegressionRouter {
    var path: [GameRoute] = []
}

private struct GamesTabHarness: View {
    let viewModel: DashboardViewModel
    @Bindable var router: RegressionRouter

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

/// Parks `fetchRecentForm` until released, and throws CancellationError when
/// the awaiting task is cancelled, the way a cancelled URLSession request does.
private final class GatedRecentFormProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var seasons: [Int] = []
    private var parked: [Int: CheckedContinuation<[RecentForm], Error>] = [:]

    var requestedSeasons: [Int] { lock.withLock { seasons } }
    var outstandingCount: Int { lock.withLock { parked.count } }

    func releaseAll() {
        let all = lock.withLock { () -> [CheckedContinuation<[RecentForm], Error>] in
            defer { parked.removeAll() }
            return Array(parked.values)
        }
        for continuation in all { continuation.resume(returning: []) }
    }

    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] {
        let index = lock.withLock { () -> Int in
            seasons.append(season)
            return seasons.count - 1
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { parked[index] = continuation }
                if Task.isCancelled { cancel(index) }
            }
        } onCancel: {
            cancel(index)
        }
    }

    private func cancel(_ index: Int) {
        let continuation = lock.withLock { parked.removeValue(forKey: index) }
        continuation?.resume(throwing: CancellationError())
    }

    func fetchPlayers() async throws -> [Player] { [] }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
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

/// Answers every recent form request at once and records the season asked for.
private final class RecentFormSeasonProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [Int] = []

    var seasons: [Int] { lock.withLock { log } }

    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] {
        lock.withLock { log.append(season) }
        return []
    }

    func fetchPlayers() async throws -> [Player] { [] }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}
