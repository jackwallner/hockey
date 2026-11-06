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
