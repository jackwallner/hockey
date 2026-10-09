import XCTest

/// The App Review screenshot for the in-app purchases: the real paywall with
/// the yearly plan selected, the three plan cards, the purchase button and the
/// auto-renew disclosure on screen together.
///
/// The paywall is rendered by the app's own `-PaywallSnapshot yearly` harness
/// (the real `PaywallView`, with packages priced from `StatScout.storekit`: no
/// RevenueCat configure on a simulator, no network, no charge).
@MainActor
final class StatScoutPaywallReviewUITests: XCTestCase {
    func testCapturePaywallReview() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments = ["-PaywallSnapshot", "yearly", "-ResetUITestState"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App should launch in the foreground")

        for price in ["$9.99", "$1.99", "$19.99"] {
            let element = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", price, price)
            ).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 60), "\(price) should be on the paywall")
        }
        // The plan cards, the purchase button and the auto-renew disclosure
        // under it share one frame: drag the page up until the disclosure is
        // clear of the bottom edge.
        let disclosure = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "renew")
        ).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 30), "The price disclosure should be on the paywall")
        var steps = 0
        var stalls = 0
        var last = disclosure.frame.maxY
        while disclosure.frame.maxY > 850, steps < 40, stalls < 2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
            steps += 1
            let now = disclosure.frame.maxY
            stalls = abs(now - last) < 1 ? stalls + 1 : 0
            last = now
        }
        let yearly = app.staticTexts["$9.99 / year"].firstMatch
        XCTAssertTrue(yearly.exists && yearly.frame.minY > 60, "The yearly plan card should still be on screen")
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paywall-review"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
