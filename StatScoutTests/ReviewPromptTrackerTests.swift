import XCTest
@testable import Hockey_StatScout

/// Gates on the system rating prompt. The tracker persists to
/// `UserDefaults.standard`, so each test snapshots and restores it to leave
/// the simulator install where it was.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private var saved: (Int, Date?, Date?, ReviewPromptOutcome?)!

    override func setUp() async throws {
        saved = (
            ReviewPromptTracker.appLaunchCount,
            ReviewPromptTracker.firstAppOpenDate,
            ReviewPromptTracker.lastShownDate,
            ReviewPromptTracker.outcome
        )
        ReviewPromptTracker.outcome = nil
        ReviewPromptTracker.lastShownDate = nil
    }

    override func tearDown() async throws {
        ReviewPromptTracker.appLaunchCount = saved.0
        ReviewPromptTracker.firstAppOpenDate = saved.1
        ReviewPromptTracker.lastShownDate = saved.2
        ReviewPromptTracker.outcome = saved.3
    }

    func testAsksFromTheSecondLaunch() {
        ReviewPromptTracker.appLaunchCount = 2
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testNeverAsksInTheFirstSession() {
        ReviewPromptTracker.appLaunchCount = 1
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testRequiresFinishedOnboarding() {
        ReviewPromptTracker.appLaunchCount = 9
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: false))
    }

    func testWaitsOutTheCooldown() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-29 * 86_400)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-31 * 86_400)
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testOpeningTheReviewPageEndsTheAsks() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.markOpenedWriteReview()
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-400 * 86_400)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testSendingFeedbackStillLeavesARatingAsk() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.markFeedbackSent()
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testFeedbackAfterWriteReviewKeepsTheStop() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.markOpenedWriteReview()
        ReviewPromptTracker.markFeedbackSent()
        XCTAssertEqual(ReviewPromptTracker.outcome, .openedWriteReview)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    /// The tracker stamps the cooldown when the call is made, so a second
    /// good moment right after it is blocked.
    func testMarkingShownStartsTheCooldown() {
        ReviewPromptTracker.appLaunchCount = 9
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    // MARK: - Good moments

    func testFollowingIsGoodOnlyFromTheThirdPlayer() {
        XCTAssertFalse(ReviewMoment.followedPlayer(followingCount: 1).isGood)
        XCTAssertFalse(ReviewMoment.followedPlayer(followingCount: 2).isGood)
        XCTAssertTrue(ReviewMoment.followedPlayer(followingCount: 3).isGood)
        XCTAssertTrue(ReviewMoment.followedPlayer(followingCount: 8).isGood)
    }

    func testComparisonIsGoodOnlyForAMember() {
        XCTAssertTrue(ReviewMoment.comparedPlayers(isPro: true).isGood)
        XCTAssertFalse(ReviewMoment.comparedPlayers(isPro: false).isGood)
    }
}
