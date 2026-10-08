import XCTest
import Foundation
@testable import Gridiron_StatScout
/// The fleet paywall record, checked in this app's own build.
///
/// The `rc-funnel-probe` run proves an impression reaches RevenueCat. These
/// prove what is underneath it: the counts, the conversion freeze, RevenueCat's
/// silent 40-character key limit, and the rule that nothing here may carry free
/// text or health data. Every assertion is a claim that will be read off a
/// customer record later, so a wrong value is worse than no value.

final class PaywallFunnelTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite per test. These counters outlive a launch and would
        // otherwise carry between tests and into the real container.
        let name = "conv.tests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: name)!
        ConversionDiagnostics.defaultsOverride = suite
    }

    override func tearDown() {
        ConversionDiagnostics.defaultsOverride = nil
        suite = nil
        super.tearDown()
    }

    func testCountsPitchesPerSurfaceAndInTotal() {
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_recent_form")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["pitch_views_total"], "3")
        XCTAssertEqual(attributes["pitch_views_upgrade"], "2")
        XCTAssertEqual(attributes["pitch_last"], "recent_form")
    }

    func testNoAttributesBeforeAnyPitchIsSeen() {
        // Someone never shown a paywall has nothing to say about paywalls.
        // Zeros would make them look like a funnel failure.
        ConversionDiagnostics.recordAppOpen()
        XCTAssertTrue(ConversionDiagnostics.subscriberAttributes.isEmpty)
    }

    func testRecordsHowEarlyTheFirstPitchArrived() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["opens_before_first_pitch"], "2")
        XCTAssertEqual(attributes["days_since_install"], "0")
    }

    func testTheEarlinessPairIsFrozenOnTheFirstPitchOnly() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_recent_form")

        XCTAssertEqual(
            ConversionDiagnostics.subscriberAttributes["opens_before_first_pitch"],
            "1"
        )
    }

    func testAnInstallThatPredatesThisCodeReportsNoAge() {
        // No recorded app open, so no install stamp. Absent is the honest
        // answer; zero would claim they were asked on their first day.
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        XCTAssertNil(ConversionDiagnostics.subscriberAttributes["days_since_install"])
        XCTAssertNotNil(ConversionDiagnostics.subscriberAttributes["pitch_views_total"])
    }

    func testConversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_recent_form")
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true, offeringID: "default")
        // A pitch after the sale must not rewrite how they converted.
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_surface"], "recent_form")
        XCTAssertEqual(attributes["pitch_views_at_convert"], "2")
        XCTAssertEqual(attributes["converted_plan"], "yearly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
        XCTAssertEqual(attributes["converted_offering"], "default")
    }

    func testOnlyTheFirstConversionIsRecorded() {
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: true)
        // A renewal or plan change is not a new answer to what sold them.
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: false)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_plan"], "monthly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
    }

    func testAttributeKeysStayInsideRevenueCatsLimit() {
        // RevenueCat drops a key over 40 characters, silently.
        let long = String(repeating: "a", count: 80)
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_\(long)")
        for key in ConversionDiagnostics.subscriberAttributes.keys {
            XCTAssertLessThanOrEqual(key.count, 40, "attribute key too long: \(key)")
        }
    }

    func testNoAttributeCarriesFreeTextOrHealthData() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "statscout_paywall_upgrade")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)

        for (key, value) in ConversionDiagnostics.subscriberAttributes {
            XCTAssertFalse(value.contains(" "), "\(key) looks like free text: \(value)")
            XCTAssertLessThanOrEqual(value.count, 64, "\(key) is too long to be a label")
        }
    }
}
