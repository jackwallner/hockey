import XCTest
@testable import Hockey_StatScout

/// Guards the copy Guideline 3.1.2(c) governs:
///
/// > The auto-renewable subscription promotes the free trial, introductory
/// > pricing, or introductory period for the subscription more clearly and
/// > conspicuously than the billed amount.
///
/// Every purchase surface follows the approved Baseball Savvy StatScout ladder:
/// the button names the trial when one applies, and the billed amount sits on
/// its own `priceLead` line directly above the button, one type step louder
/// than the button label. These tests pin the strings; the ranking itself lives
/// in the views (`PlusDirectCTA`, `PaywallView.purchaseSection`, onboarding).
final class PriceDisclosureTests: XCTestCase {

    private let renewSentence = "Auto-renews unless cancelled at least 24 hours before the end of the current period."
    private let cancelSentence = "Manage or cancel in Settings › Apple ID › Subscriptions."

    // MARK: - One-tap CTAs (sheet, blur gates, onboarding)

    func testTrialEligibleButtonNamesTheTrial() {
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: "7-day free trial", isWinback: false),
            "Start 7-day free trial"
        )
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$1.99 / month", trial: "7-day free trial", isWinback: false),
            "Start 7-day free trial"
        )
    }

    func testNoTrialLeftNamesThePrice() {
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: nil, isWinback: false),
            "Try StatScout+ for $9.99 / year"
        )
    }

    /// A lapsed subscriber has already used the trial, so a win-back never
    /// offers it again.
    func testWinbackNeverOffersTheTrial() {
        for trial in [nil, "7-day free trial"] {
            let label = StoreService.directCTALabel(price: "$9.99 / year", trial: trial, isWinback: true)
            XCTAssertEqual(label, "Restart StatScout+ for $9.99 / year")
            XCTAssertFalse(label.lowercased().contains("trial"), label)
        }
    }

    // MARK: - The plan picker's own button

    func testPlanPickerCTANamesTheActionNotTheOffer() {
        XCTAssertEqual(
            StoreService.planPickerCTALabel(isLifetime: false, trialEligible: true),
            "Start Free Trial"
        )
        XCTAssertEqual(
            StoreService.planPickerCTALabel(isLifetime: false, trialEligible: false),
            "Subscribe"
        )
        XCTAssertEqual(
            StoreService.planPickerCTALabel(isLifetime: true, trialEligible: false),
            "Unlock Lifetime"
        )
    }

    /// A non-consumable has no introductory offer to start, so eligibility must
    /// never leak a trial promise onto the lifetime button.
    func testLifetimePlanNeverOffersATrial() {
        XCTAssertEqual(
            StoreService.planPickerCTALabel(isLifetime: true, trialEligible: true),
            "Unlock Lifetime"
        )
    }

    /// The billed amount belongs to the `priceLead` line above this button.
    func testPlanPickerCTANeverCarriesAPrice() {
        for isLifetime in [true, false] {
            for trialEligible in [true, false] {
                let label = StoreService.planPickerCTALabel(
                    isLifetime: isLifetime, trialEligible: trialEligible
                )
                XCTAssertFalse(
                    label.contains(where: { $0.isNumber }) || label.contains("$"),
                    "\"\(label)\" states an amount the price line already shows"
                )
            }
        }
    }

    // MARK: - Disclosure

    func testTrialDisclosureNamesTheTrialThenThePrice() {
        XCTAssertEqual(
            StoreService.disclosureText(price: "$9.99 / year", isSubscription: true, trial: "7-day free trial"),
            "7-Day Free Trial, then $9.99 / year. \(renewSentence) \(cancelSentence)"
        )
    }

    func testSubscriptionWithoutATrialLeadsWithThePrice() {
        let text = StoreService.disclosureText(price: "$1.99 / month", isSubscription: true, trial: nil)
        XCTAssertEqual(text, "$1.99 / month. \(renewSentence) \(cancelSentence)")
    }

    /// A non-consumable must not claim to auto-renew.
    func testLifetimeIsNeverDescribedAsASubscription() {
        let text = StoreService.disclosureText(price: "$19.99", isSubscription: false, trial: nil)
        XCTAssertEqual(text, "$19.99. One-time purchase. Lifetime access, no subscription.")
        XCTAssertFalse(text.contains("Auto-renews"), text)
    }

    /// The price and the renewal terms are always present.
    func testEveryDisclosureStatesThePriceAndTheTerms() {
        let cases: [(price: String, isSubscription: Bool, trial: String?)] = [
            ("$9.99 / year", true, "7-day free trial"),
            ("$9.99 / year", true, nil),
            ("$1.99 / month", true, "3-day free trial"),
            ("$19.99", false, nil)
        ]
        for c in cases {
            let text = StoreService.disclosureText(price: c.price, isSubscription: c.isSubscription, trial: c.trial)
            XCTAssertTrue(text.contains(c.price), "\"\(text)\" omits the price")
            if c.isSubscription {
                XCTAssertTrue(text.contains(renewSentence), "\"\(text)\" omits the renewal terms")
                XCTAssertTrue(text.contains(cancelSentence), "\"\(text)\" omits how to cancel")
            }
            if let trial = c.trial {
                XCTAssertTrue(text.lowercased().contains(trial.lowercased()), "\"\(text)\" omits the trial")
            }
        }
    }

    // MARK: - Legal links

    func testLegalLinksResolve() {
        XCTAssertEqual(
            StatScoutLegal.termsURL.absoluteString,
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )
        XCTAssertEqual(StatScoutLegal.privacyURL.scheme, "https")
        XCTAssertFalse(StatScoutLegal.privacyURL.host?.isEmpty ?? true)
    }
}
