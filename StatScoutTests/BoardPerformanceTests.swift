import XCTest
@testable import Hockey_StatScout

/// Timings against the real bundled history, the load a Pro user carries once
/// they open any past season. Each board read used to rescan every row of every
/// season several times over, which is what made typing in search and
/// switching position stutter.
final class BoardPerformanceTests: XCTestCase {
    @MainActor
    private func loadedViewModel() async throws -> DashboardViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "board-perf-\(UUID().uuidString)")
        let cache = TwoTierPlayerCache(directory: directory)
        // The first read seeds the on-disk cache from the bundle; the second is
        // what every later session pays.
        let seedStart = Date()
        _ = cache.loadHistoricalPlayers()
        print("PERF first history read: \(Int(Date().timeIntervalSince(seedStart) * 1000)) ms")

        let vm = DashboardViewModel(provider: MockProvider(players: []), cache: cache)
        let start = Date()
        await vm.loadHistoricalIfNeeded()
        print("PERF historical load: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        let rows = vm.playerHistories.values.reduce(0) { $0 + $1.count }
        try XCTSkipIf(rows < 10_000, "bundled history missing")
        return vm
    }

    @MainActor
    func testBoardReadsStayCheapWithFullHistory() async throws {
        let vm = try await loadedViewModel()
        vm.isPro = true
        vm.selectSeason(StatScoutSeason.current - 1)

        // One DashboardView body pass reads these, in about this mix.
        let start = Date()
        for query in ["", "c", "co", "con", "conn", "con", "co", "c", ""] {
            vm.searchText = query
            for position in [PlayerPositionGroup.forward, .defense] {
                vm.selectedPosition = position
                _ = vm.currentSortMetric
                _ = vm.currentSortMetricForDisplay
                _ = vm.availableAdvancedSortMetrics
                for _ in 0..<4 { _ = vm.leaderboard }
                _ = vm.seasonPlayers
                _ = vm.availableSeasons
                _ = vm.teamsWithData
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        print("PERF 18 board passes: \(Int(elapsed * 1000)) ms")
        XCTAssertFalse(vm.leaderboard.isEmpty)
        XCTAssertLessThan(elapsed, 1.0, "18 board passes should take well under a second")
    }

    /// The Best/Worst and standard boards re-render on every loading tick too.
    @MainActor
    func testLeaderBoardsStayCheapWithFullHistory() async throws {
        let vm = try await loadedViewModel()
        vm.isPro = true
        vm.selectSeason(StatScoutSeason.current - 1)

        let start = Date()
        for _ in 0..<10 {
            _ = vm.allMetrics
            _ = vm.qualifiedSeasonPlayers
        }
        let elapsed = Date().timeIntervalSince(start)
        print("PERF 10 leader board passes: \(Int(elapsed * 1000)) ms")
        XCTAssertFalse(vm.allMetrics.isEmpty)
        XCTAssertLessThan(elapsed, 0.5, "10 leader board passes should take well under half a second")
    }
}
