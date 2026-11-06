import RevenueCat
import XCTest
@testable import Hockey_StatScout

/// State machine audit 2026-11-06. Failing tests are expected: each failure is
/// a claim in project-docs/audits/state-machines-2026-11-06.md. Every test
/// asserts its own preconditions first, and each claim has a passing control.
@MainActor
final class StateMachineAuditRepro: XCTestCase {

    // MARK: - SM1: entitlement ordering

    private func customerInfo(active: Bool, requestDate: Date) -> CustomerInfo {
        let identifier = RevenueCatConfig.proEntitlement
        let entitlement = EntitlementInfo(
            identifier: identifier,
            isActive: active,
            willRenew: active,
            periodType: .normal,
            latestPurchaseDate: requestDate,
            originalPurchaseDate: requestDate,
            expirationDate: requestDate.addingTimeInterval(active ? 86_400 : -86_400),
            store: .appStore,
            productIdentifier: StatScoutProduct.monthly,
            isSandbox: true,
            ownershipType: .purchased
        )
        return CustomerInfo(
            entitlements: EntitlementInfos(entitlements: [identifier: entitlement]),
            requestDate: requestDate,
            firstSeen: requestDate,
            originalAppUserId: "state-machine-audit"
        )
    }

    override func tearDown() async throws {
        // StoreService.shared is a process singleton; leave it as a fresh install.
        StoreService.shared.apply(customerInfo: customerInfo(active: false, requestDate: .now))
        try await super.tearDown()
    }

    /// Control: a genuinely newer answer from RevenueCat does revoke Pro
    /// (the subscription really expired), so `apply` is not simply sticky.
    func testControlNewerInactiveInfoRevokesPro() {
        let store = StoreService.shared
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.apply(customerInfo: customerInfo(active: true, requestDate: t0))
        XCTAssertTrue(store.isPro, "precondition: active info unlocks Pro")
        store.apply(customerInfo: customerInfo(active: false, requestDate: t0.addingTimeInterval(60)))
        XCTAssertFalse(store.isPro, "a newer inactive answer revokes Pro")
    }

    /// SM1-T1. An answer RevenueCat produced BEFORE the purchase, delivered
    /// after it (a slow launch fetch, a foreground refresh, the delegate hop),
    /// must not take Pro away from someone who just paid.
    func testStaleInactiveCustomerInfoDoesNotRevokeNewerActiveInfo() {
        let store = StoreService.shared
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let purchased = customerInfo(active: true, requestDate: t0)
        let staleFetch = customerInfo(active: false, requestDate: t0.addingTimeInterval(-60))

        store.apply(customerInfo: purchased)
        XCTAssertTrue(store.isPro, "precondition: the purchase result unlocked Pro")
        XCTAssertEqual(store.customerInfo?.requestDate, t0, "precondition: the purchase result is the stored info")
        XCTAssertLessThan(staleFetch.requestDate, purchased.requestDate, "precondition: the second answer is older")
        XCTAssertFalse(staleFetch.hasProEntitlement, "precondition: the older answer says not Pro")

        store.apply(customerInfo: staleFetch)

        XCTAssertTrue(store.isPro, "an older answer overwrote a newer one and locked a paying user out")
        XCTAssertEqual(store.customerInfo?.requestDate, t0, "the stored info went backwards in time")
    }

    // MARK: - SM6: recent form loading flag

    private func waitForRequests(_ count: Int, on provider: GatedRecentFormProvider) async throws {
        for _ in 0..<500 {
            if provider.requestedSeasons.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("provider never received \(count) requests")
    }

    /// Control: one load in flight reads as loading, and stops when it lands.
    func testControlSingleRecentFormLoadShowsSpinnerThenClears() async throws {
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

    /// SM6-T1. Trends: a load for one season is in flight, the user flips the
    /// season (or Regular/Playoffs) pill. The new load is running, so the board
    /// must still say it is loading. The cancelled load's `defer` removes the
    /// new load's loading flag, so the board falls through to the empty state.
    func testSupersededRecentFormLoadDoesNotClearTheNewLoadsSpinner() async throws {
        let provider = GatedRecentFormProvider()
        let vm = DashboardViewModel(provider: provider)
        XCTAssertEqual(vm.recentWindow, .two, "precondition: the board reads the 2 week window")

        let first = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2026, phase: .regular) }
        try await waitForRequests(1, on: provider)
        XCTAssertTrue(vm.isRecentFormLoading, "precondition: first load in flight")

        let second = Task { await vm.loadRecentFormIfNeeded(window: TrendWindow.two, season: 2025, phase: .regular) }
        try await waitForRequests(2, on: provider)
        // Let the cancelled first load unwind completely.
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(provider.requestedSeasons, [2026, 2025], "precondition: both requests were made in order")
        XCTAssertEqual(provider.outstandingCount, 1, "precondition: only the 2025 request is still outstanding")
        XCTAssertTrue(
            vm.recentFormRows(window: .two, playerType: "f", season: 2025, phase: .regular).isEmpty,
            "precondition: nothing has landed for 2025 yet"
        )

        XCTAssertTrue(vm.isRecentFormLoading, "the 2025 load is still in flight but the board is not loading")

        provider.releaseAll()
        await second.value
        await first.value
    }
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
