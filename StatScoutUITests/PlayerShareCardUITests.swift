import XCTest

/// Runs on the DEBUG fixture provider, so it needs no network.
@MainActor
final class PlayerShareCardUITests: XCTestCase {
    private let fixturePlayer = "Callum Therrien"

    func testShareButtonOpensShareSheetWithCard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScreenshotData",
            "-hasCompletedOnboarding", "YES",
            "-stats.board", "advanced",
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
            "-profileOpenCount", "0",
            "-StartTab", "stats",
        ]
        app.launch()

        let row = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(fixturePlayer),.*")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Fixture row should load")
        row.tap()

        let share = app.buttons["sharePlayerCard"]
        XCTAssertTrue(share.waitForExistence(timeout: 20), "Profile should offer a share button")
        // A free user's first profile can open under the trial pitch.
        let maybeLater = app.buttons["Maybe later"]
        if maybeLater.waitForExistence(timeout: 5) {
            maybeLater.tap()
            sleep(1)
        }
        attach("profile")
        share.tap()

        let sheet = app.otherElements["ActivityListView"].firstMatch
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10) || copy.waitForExistence(timeout: 5), "Share sheet should appear")
        sleep(2)
        attach("share-sheet")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
