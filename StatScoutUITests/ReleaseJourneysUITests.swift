import XCTest

/// Release gate journeys (see ~/ios/qa/README.md). They assert reachability
/// and the core loop's outcome; `QA.checkpoint` judges every screen.
///
/// Data is the DEBUG fixture slate (`-ScreenshotData`), so no network is needed
/// for players. RevenueCat is the Test Store key in DEBUG builds, never `appl_`.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private var app: XCUIApplication!
    private let loadTimeout: TimeInterval = 60

    /// Onboarding done, fixture players. `-FixtureKeepState` makes the follow
    /// list survive a relaunch; `-profileOpenCount 0` keeps the trial pitch off
    /// the profile (the argument domain wins over what the app writes back).
    private let returning = [
        "-ScreenshotData",
        "-MockProducts",
        "-FixtureKeepState",
        "-hasCompletedOnboarding", "YES",
        "-stats.board", "advanced",
        "-profileOpenCount", "0",
        "-StartTab", "stats",
    ]

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
    }

    // MARK: - Journeys

    /// Real first run: onboarding pages, the offer on the last page, then the
    /// free tier's first screen.
    func testFirstRunOnboardingToStats() {
        QA.launch(app, arguments: ["-ScreenshotData", "-MockProducts", "-FixtureFresh", "-StartTab", "stats"])
        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 30), "Onboarding should open")
        QA.checkpoint(app, "onboarding-first-page")

        var page = 1
        while continueButton.exists, page < 8 {
            continueButton.tap()
            page += 1
            QA.checkpoint(app, "onboarding-page-\(page)")
        }

        let getStarted = app.buttons["Get Started"].firstMatch
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20), "The last onboarding page should offer Get Started")
        QA.checkpoint(app, "onboarding-offer")
        getStarted.tap()

        XCTAssertTrue(boardLoaded(), "Stats should open after onboarding")
        QA.checkpoint(app, "stats-first-value")
    }

    func testOnboardingSkipReachesStats() {
        QA.launch(app, arguments: ["-ScreenshotData", "-MockProducts", "-FixtureFresh", "-StartTab", "stats"])
        let skip = app.buttons["Skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "Onboarding should offer Skip")
        skip.tap()
        XCTAssertTrue(boardLoaded(), "Stats should open after Skip")
        QA.checkpoint(app, "stats-after-skip")
    }

    /// Upgrade entry: the toolbar crown opens the paywall and Close returns.
    func testPaywallShownAndDismissed() {
        QA.launch(app, arguments: returning)
        XCTAssertTrue(boardLoaded(), "Stats should open")
        let upgrade = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "unlock all features")).firstMatch
        XCTAssertTrue(upgrade.waitForExistence(timeout: 30), "A free user should see the upgrade button")
        QA.checkpoint(app, "stats-free")
        upgrade.tap()

        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20), "The paywall should open with a Close button")
        QA.checkpoint(app, "paywall")
        close.tap()

        XCTAssertTrue(upgrade.waitForExistence(timeout: 10), "Closing the paywall should return to Stats")
    }

    func testReturnVisitAcrossTabs() {
        QA.launch(app, arguments: returning)
        XCTAssertTrue(boardLoaded(), "Stats should open")

        QA.relaunch(app)
        XCTAssertTrue(boardLoaded(), "Stats should reopen without onboarding")
        QA.checkpoint(app, "stats-after-relaunch")

        openTab("Games")
        QA.checkpoint(app, "games")
        openTab("Trends")
        QA.checkpoint(app, "trends")
        openTab("Teams")
        QA.checkpoint(app, "teams")
        openTab("Compare")
        XCTAssertTrue(app.staticTexts["YOUR PLAYERS"].waitForExistence(timeout: 20), "Compare should open")
        QA.checkpoint(app, "compare")
    }

    func testSettingsOpensWithAttribution() {
        QA.launch(app, arguments: returning)
        XCTAssertTrue(boardLoaded(), "Stats should open")
        let gear = app.buttons["Settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "Stats should offer Settings")
        gear.tap()

        XCTAssertTrue(app.staticTexts["REFERENCE"].firstMatch.waitForExistence(timeout: 30), "Settings should open")

        let attribution = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "MoneyPuck")).firstMatch
        var swipes = 0
        while !attribution.exists, swipes < 8 {
            QA.swipe(app.scrollViews.firstMatch, .up)
            swipes += 1
        }
        XCTAssertTrue(attribution.exists, "Settings should carry the MoneyPuck attribution")
        QA.checkpoint(app, "settings-attribution")
    }

    func testInterruptionOnPlayerProfile() {
        QA.launch(app, arguments: returning)
        openProfile("Holloway", as: "Rasmus Holloway")

        QA.interrupt(app)
        XCTAssertEqual(app.state, .runningForeground, "The app should come back to the foreground")
        XCTAssertTrue(followButton("Rasmus Holloway").waitForExistence(timeout: 20), "The profile should survive the interruption")
        QA.checkpoint(app, "profile-after-interrupt")
    }

    /// Core loop: find a player, follow them, see them under YOUR PLAYERS on
    /// Compare, and still be following after the app is killed and reopened.
    func testCoreLoopFollowPlayerSurvivesRelaunch() {
        let name = "Rasmus Holloway"
        QA.launch(app, arguments: returning)
        XCTAssertTrue(boardLoaded(), "Stats should open")

        openProfile("Holloway", as: name, checkpoint: true)
        // Earlier runs share this install; start from not following.
        if unfollow(name).exists {
            unfollow(name).tap()
        }
        let follow = app.buttons["Follow \(name)"].firstMatch
        XCTAssertTrue(follow.waitForExistence(timeout: 10), "An unfollowed player should offer Follow")

        follow.tap()
        XCTAssertTrue(unfollow(name).waitForExistence(timeout: 10), "Following should flip the button to Unfollow")

        openTab("Compare")
        XCTAssertTrue(followedRow(name).waitForExistence(timeout: 20), "\(name) should be listed under YOUR PLAYERS")
        QA.checkpoint(app, "compare-your-players")

        QA.relaunch(app)
        XCTAssertTrue(boardLoaded(), "Stats should reopen after the relaunch")
        openTab("Compare")
        XCTAssertTrue(followedRow(name).waitForExistence(timeout: 20), "\(name) should still be followed after a relaunch")
        QA.checkpoint(app, "compare-your-players-after-relaunch")

        openTab("Stats")
        openProfile("Holloway", as: name)
        XCTAssertTrue(unfollow(name).waitForExistence(timeout: 10), "The profile should still show Unfollow after a relaunch")

        unfollow(name).tap()
        XCTAssertTrue(app.buttons["Follow \(name)"].firstMatch.waitForExistence(timeout: 10), "Unfollow should flip the button back")
    }

    // MARK: - Helpers

    private func boardLoaded() -> Bool {
        app.staticTexts["RANK"].waitForExistence(timeout: loadTimeout)
    }

    private func openTab(_ title: String) {
        let tab = app.buttons.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "\(title) tab should exist")
        tab.tap()
    }

    /// Searches Stats for `query`, opens the matching player and clears the
    /// trial pitch if one covers the profile.
    private func openProfile(_ query: String, as name: String, checkpoint: Bool = false, journey: String = #function) {
        let chip = app.buttons["Search players or teams"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "Stats should offer Search")
        chip.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The search field should open")
        field.typeText(query)

        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Search should find \(name)")
        row.tap()

        let maybeLater = app.buttons["Maybe later"].firstMatch
        if maybeLater.waitForExistence(timeout: 4) {
            QA.checkpoint(app, "trial-pitch", journey: journey)
            maybeLater.tap()
            XCTAssertTrue(maybeLater.waitForNonExistence(timeout: 10), "The trial pitch should dismiss")
        }
        XCTAssertTrue(followButton(name).waitForExistence(timeout: 30), "\(name)'s profile should open")
        if checkpoint { QA.checkpoint(app, "profile", journey: journey) }
    }

    private func unfollow(_ name: String) -> XCUIElement {
        app.buttons["Unfollow \(name)"].firstMatch
    }

    private func followButton(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Follow \(name)", "Unfollow \(name)"])).firstMatch
    }

    private func followedRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
}
