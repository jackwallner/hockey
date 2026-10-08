import XCTest
@testable import Gridiron_StatScout

final class DataFreshnessTests: XCTestCase {
    func testProductionStatusDecodesCoverageAndPendingEnrichment() throws {
        let json = """
        {"status":"degraded","refresh_id":"v2","source_published_at":"2026-09-12T12:00:00Z",
         "published_at":"2026-09-12T12:05:00Z","last_checked_at":"2026-09-12T12:10:00Z",
         "max_game_date":"2026-09-10","max_week":1,"observed_games":2,"expected_games":2,"season_type":"REG"}
        """
        let status = try JSONDecoder.statScout.decode(DataFreshness.self, from: Data(json.utf8))
        XCTAssertEqual(status.status, .partial)
        XCTAssertEqual(status.revision, "v2")
        XCTAssertEqual(status.coverage?.week, 1)
        XCTAssertEqual(status.coverage?.gamesIncluded, 2)
        XCTAssertNotEqual(status.sourcePublishedAt, status.checkedAt)
    }

    @MainActor
    func testPublishedCoreRevisionIsAdoptedWithAdvancedMetricsPending() async {
        let provider = RevisionProvider(revisions: ["v1", "v1"], status: .partial)
        let model = DashboardViewModel(provider: provider)
        await model.load()
        XCTAssertEqual(model.freshnessRevision, "v1")
        XCTAssertEqual(model.freshnessStatus, .partial)
        XCTAssertEqual(model.dataCoverage?.gamesIncluded, 2)
    }

    @MainActor
    func testRevisionChangeDuringFetchDoesNotAdoptMixedData() async {
        let provider = RevisionProvider(revisions: ["v1", "v2"])
        let model = DashboardViewModel(provider: provider)
        await model.load()
        XCTAssertNil(model.freshnessRevision)
        XCTAssertTrue(model.players.isEmpty)
        XCTAssertNil(model.freshnessForDisplay?.coverage)
    }

    @MainActor
    func testFailedFirstStatusReadStillShowsPlayers() async {
        let provider = RevisionProvider(revisions: ["v1", "v1"], failFirstCheck: true)
        let model = DashboardViewModel(provider: provider)
        await model.load()
        XCTAssertFalse(model.players.isEmpty)
    }

    @MainActor
    func testEquivalentRefreshRequestsShareOnePlayerFetch() async {
        let provider = RevisionProvider(revisions: ["v1", "v1"])
        let model = DashboardViewModel(provider: provider)
        async let first: Void = model.load()
        async let second: Void = model.load()
        _ = await (first, second)
        let count = await provider.playerFetches
        XCTAssertEqual(count, 1)
    }
}

private actor RevisionProvider: StatcastProviding {
    let revisions: [String]
    let status: DataFreshnessStatus
    var checks = 0
    private(set) var playerFetches = 0
    let failFirstCheck: Bool
    init(revisions: [String], status: DataFreshnessStatus = .ready, failFirstCheck: Bool = false) {
        self.revisions = revisions
        self.status = status
        self.failFirstCheck = failFirstCheck
    }
    func fetchDataFreshness(season: Int) async throws -> DataFreshness? {
        if failFirstCheck, checks == 0 {
            checks += 1
            throw URLError(.notConnectedToInternet)
        }
        let revision = revisions[min(checks, revisions.count - 1)]
        checks += 1
        return DataFreshness(status: status, revision: revision,
            coverage: DataCoverage(asOf: Date(timeIntervalSince1970: 1000), week: 1,
                phase: .regular, gamesIncluded: 2, expectedGames: 2))
    }
    func fetchCurrentPlayers() async throws -> [Player] {
        playerFetches += 1
        try await Task.sleep(for: .milliseconds(20))
        return [Player(playerId: 1, name: "Fixture", team: "SEA", position: "QB", handedness: "",
            updatedAt: Date(timeIntervalSince1970: 1000), season: StatScoutSeason.current,
            playerType: "qb", metrics: [], standardStats: [], games: [])]
    }
    func fetchPlayers() async throws -> [Player] { try await fetchCurrentPlayers() }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
}

final class DataFreshnessCaptionTests: XCTestCase {
    func testShortAgeStaysCompact() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(5), now: now), "just now")
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(-59), now: now), "just now")
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(-600), now: now), "10m ago")
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(-7_200), now: now), "2h ago")
    }
}
