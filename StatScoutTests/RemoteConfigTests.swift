import XCTest
@testable import Hockey_StatScout

final class RemoteConfigTests: XCTestCase {
    // MARK: - Reader

    func testMissingMetadataIsControl() {
        XCTAssertEqual(TrialCTA.from(metadata: nil), .control)
        XCTAssertEqual(TrialCTA.from(metadata: [:]), .control)
    }

    func testNonStringValueIsControl() {
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": 3]), .control)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": ["my"]]), .control)
    }

    func testUnknownValueIsControl() {
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "our"]), .control)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": ""]), .control)
    }

    func testEachKnownValueIsItsArm() {
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "seven_day"]), .control)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "my"]), .my)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "your"]), .your)
    }

    // MARK: - Titles

    func testEachArmsTitleOnEachSurface() {
        XCTAssertEqual(TrialCTA.control.title(.direct, trial: "7-day free trial"), "Start 7-day free trial")
        XCTAssertEqual(TrialCTA.control.title(.planPicker), "Start Free Trial")
        XCTAssertEqual(TrialCTA.my.title(.direct), "Start my free trial")
        XCTAssertEqual(TrialCTA.my.title(.planPicker), "Start My Free Trial")
        XCTAssertEqual(TrialCTA.your.title(.direct), "Start your free trial")
        XCTAssertEqual(TrialCTA.your.title(.planPicker), "Start Your Free Trial")
    }

    /// The control must read exactly as the buttons did before the reader.
    func testControlMatchesThePreChangeCopy() {
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: "7-day free trial", isWinback: false),
            "Start 7-day free trial"
        )
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: "3-day free trial", isWinback: false),
            "Start 3-day free trial"
        )
        XCTAssertEqual(
            StoreService.planPickerCTALabel(isLifetime: false, trialEligible: true),
            "Start Free Trial"
        )
    }

    func testArmsReachTheRealButtons() {
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: "7-day free trial", isWinback: false, cta: .my),
            "Start my free trial"
        )
        XCTAssertEqual(
            StoreService.planPickerCTALabel(isLifetime: false, trialEligible: true, cta: .your),
            "Start Your Free Trial"
        )
    }

    /// An account that already used its trial (3.1.2) never reads a trial
    /// promise, whatever the arm.
    func testIneligibleWordingIgnoresTheArm() {
        for arm in TrialCTA.allCases {
            XCTAssertEqual(
                StoreService.directCTALabel(price: "$9.99 / year", trial: nil, isWinback: false, cta: arm),
                "Try StatScout+ for $9.99 / year"
            )
            XCTAssertEqual(
                StoreService.directCTALabel(price: "$9.99 / year", trial: "7-day free trial", isWinback: true, cta: arm),
                "Restart StatScout+ for $9.99 / year"
            )
            XCTAssertEqual(
                StoreService.planPickerCTALabel(isLifetime: false, trialEligible: false, cta: arm),
                "Subscribe"
            )
            XCTAssertEqual(
                StoreService.planPickerCTALabel(isLifetime: true, trialEligible: true, cta: arm),
                "Unlock Lifetime"
            )
        }
    }

    // MARK: - Switches

    func testRatingPromptIsOnByDefault() {
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: nil))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
    }

    func testRatingPromptIsOffOnlyForOff() {
        XCTAssertFalse(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
    }
}
