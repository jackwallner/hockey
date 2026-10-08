import XCTest
@testable import Gridiron_StatScout

/// Guards the copy App Review rejected 1.0 (19) over, Guideline 3.1.2(c):
///
/// > The auto-renewable subscription promotes the free trial, introductory
/// > pricing, or introductory period for the subscription more clearly and
/// > conspicuously than the billed amount.
///
/// The price was never missing. It was outranked: the cited sheet's button read
/// "Start 7-day free trial" in the largest, highest-contrast type on the
/// screen, while "$9.99 / year" sat in grey micro text beneath it, and the
/// disclosure led with the trial as well.
///
/// The fix applies to every one-tap transactional surface and demotes the trial
/// rather than deleting it. `.billedAmountFirst` puts the price on the button's
/// primary line and keeps the trial on a subordinate one beneath it, in micro.
/// The old trial-first ordering remains testable but is never the live default.
///
/// `PaywallView` is the deliberate exception, and it clears the guideline a
/// different way: its button names no price *and* no trial-versus-price
/// ordering to get wrong, because the selected plan card carries the billed
/// amount in `statLarge`/`ink` immediately above it and the disclosure leads
/// with the same amount immediately below. See `planPickerCTALabel`.
final class PriceDisclosureTests: XCTestCase {

    private let renewSentence = "Auto-renews unless cancelled at least 24 hours before the end of the current period."
    private let cancelSentence = "Manage or cancel in Settings › Apple ID › Subscriptions."

    // MARK: - Every purchase surface: billed amount first

    func testCitedSheetCTANamesTheBilledAmountAndNotTheTrial() {
        let label = StoreService.directCTALabel(
            price: "$9.99 / year", trial: "7-day free trial",
            isWinback: false, emphasis: .billedAmountFirst
        )
        XCTAssertEqual(label, "Subscribe for $9.99 / year")
        XCTAssertFalse(label.lowercased().contains("trial"), "The cited CTA must not promote the trial: \(label)")
        XCTAssertFalse(label.lowercased().contains("free"), "The cited CTA must not promote the trial: \(label)")
    }

    /// The trial is still pitched on the cited sheet, one rank down. Losing
    /// this line would clear 3.1.2(c) by giving up the offer, which is not the
    /// trade being made.
    func testCitedSheetStillSellsTheTrialOnASubordinateLine() {
        let subline = StoreService.directCTATrialSubline(
            trial: "7-day free trial", isWinback: false, emphasis: .billedAmountFirst
        )
        XCTAssertEqual(subline, "Starts with a 7-day free trial")
    }

    /// The subordinate line belongs to the cited emphasis alone. On every other
    /// surface the trial is already the button's primary label, and a second
    /// copy underneath would be the same offer twice.
    func testTrialSublineOnlyExistsWhereThePriceLeads() {
        XCTAssertNil(
            StoreService.directCTATrialSubline(
                trial: "7-day free trial", isWinback: false, emphasis: .trialFirst
            )
        )
        XCTAssertNil(
            StoreService.directCTATrialSubline(
                trial: nil, isWinback: false, emphasis: .billedAmountFirst
            ),
            "Nothing to name when there is no trial"
        )
        XCTAssertNil(
            StoreService.directCTATrialSubline(
                trial: "7-day free trial", isWinback: true, emphasis: .billedAmountFirst
            ),
            "A win-back has already used the trial"
        )
    }

    /// The whole rejection was about which element is louder, so pin the pair:
    /// the price is on the primary line, the trial only on the secondary one.
    func testTheCitedButtonRanksThePriceAboveTheTrial() {
        let label = StoreService.directCTALabel(
            price: "$9.99 / year", trial: "7-day free trial",
            isWinback: false, emphasis: .billedAmountFirst
        )
        let subline = StoreService.directCTATrialSubline(
            trial: "7-day free trial", isWinback: false, emphasis: .billedAmountFirst
        )
        XCTAssertTrue(label.contains("$9.99 / year"))
        XCTAssertFalse(subline?.contains("$9.99") ?? false, "The price belongs on the primary line only")
        XCTAssertTrue(subline?.lowercased().contains("free trial") ?? false)
    }

    func testCitedSheetDisclosureLeadsWithTheBilledAmount() {
        let text = StoreService.disclosureText(
            price: "$9.99 / year", isSubscription: true,
            trial: "7-day free trial", emphasis: .billedAmountFirst
        )
        XCTAssertEqual(
            text,
            "$9.99 / year, billed after a 7-day free trial. \(renewSentence) \(cancelSentence)"
        )
        XCTAssertLessThan(
            text.range(of: "$9.99 / year")!.lowerBound,
            text.range(of: "7-day free trial")!.lowerBound,
            "The trial must be subordinate in position"
        )
    }

    /// No branch of the cited emphasis may omit the price or advertise a trial.
    func testBilledAmountFirstNeverPromotesTheTrial() {
        for price in ["$9.99 / year", "$1.99 / month"] {
            for trial in [nil, "7-day free trial"] {
                for isWinback in [false, true] {
                    let label = StoreService.directCTALabel(
                        price: price, trial: trial, isWinback: isWinback, emphasis: .billedAmountFirst
                    )
                    XCTAssertTrue(label.contains(price), "\"\(label)\" omits the billed amount")
                    XCTAssertFalse(
                        label.lowercased().contains("free") || label.lowercased().contains("trial"),
                        "\"\(label)\" promotes the trial in the most prominent element on screen"
                    )
                }
            }
        }
    }

    // MARK: - The plan picker's own button

    /// The plan picker states the action, not the offer. Naming neither the
    /// price nor a competing claim is what keeps it outside 3.1.2(c): there is
    /// no ordering to get wrong when the button advertises no amount at all.
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

    /// No branch may carry a currency amount. The billed amount belongs to the
    /// plan card and the disclosure, both of which render it larger than this
    /// button's own type.
    func testPlanPickerCTANeverCarriesAPrice() {
        for isLifetime in [true, false] {
            for trialEligible in [true, false] {
                let label = StoreService.planPickerCTALabel(
                    isLifetime: isLifetime, trialEligible: trialEligible
                )
                XCTAssertFalse(
                    label.contains(where: { $0.isNumber }) || label.contains("$"),
                    "\"\(label)\" states an amount the plan card already ranks above it"
                )
            }
        }
    }

    // MARK: - Trial-first formatting is never the live default

    func testDefaultCopyLeadsWithTheBilledAmountEverywhere() {
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: "7-day free trial", isWinback: false),
            "Subscribe for $9.99 / year"
        )
        XCTAssertEqual(
            StoreService.directCTALabel(price: "$9.99 / year", trial: nil, isWinback: false),
            "Subscribe for $9.99 / year"
        )
        XCTAssertEqual(
            StoreService.disclosureText(price: "$9.99 / year", isSubscription: true, trial: "7-day free trial"),
            "$9.99 / year, billed after a 7-day free trial. \(renewSentence) \(cancelSentence)"
        )
    }

    func testTrialFirstFormattingRequiresAnExplicitOptIn() {
        XCTAssertEqual(
            StoreService.directCTALabel(
                price: "$9.99 / year", trial: "7-day free trial",
                isWinback: false, emphasis: .trialFirst
            ),
            "Start 7-day free trial"
        )
    }

    /// A lapsed subscriber has already used the trial, so a win-back never
    /// offers it again whatever the emphasis.
    func testWinbackNeverOffersTheTrial() {
        for emphasis in [PriceEmphasis.trialFirst, .billedAmountFirst] {
            let label = StoreService.directCTALabel(
                price: "$9.99 / year", trial: "7-day free trial", isWinback: true, emphasis: emphasis
            )
            XCTAssertTrue(label.contains("$9.99 / year"), label)
            XCTAssertFalse(label.lowercased().contains("free trial"), label)
        }
    }

    // MARK: - True of both orderings

    func testSubscriptionWithoutATrialAlwaysLeadsWithThePrice() {
        for emphasis in [PriceEmphasis.trialFirst, .billedAmountFirst] {
            let text = StoreService.disclosureText(
                price: "$1.99 / month", isSubscription: true, trial: nil, emphasis: emphasis
            )
            XCTAssertTrue(text.hasPrefix("$1.99 / month."), text)
            XCTAssertTrue(text.contains(renewSentence), text)
            XCTAssertTrue(text.contains(cancelSentence), text)
        }
    }

    /// A non-consumable must not claim to auto-renew, either way.
    func testLifetimeIsNeverDescribedAsASubscription() {
        for emphasis in [PriceEmphasis.trialFirst, .billedAmountFirst] {
            let text = StoreService.disclosureText(
                price: "$19.99", isSubscription: false, trial: nil, emphasis: emphasis
            )
            XCTAssertEqual(text, "$19.99. One-time purchase. Lifetime access, no subscription.")
            XCTAssertFalse(text.contains("Auto-renews"), text)
        }
    }

    /// Whatever the emphasis, the price and the renewal terms are both present.
    func testEveryDisclosureStatesThePriceAndTheTerms() {
        let cases: [(price: String, isSubscription: Bool, trial: String?)] = [
            ("$9.99 / year", true, "7-day free trial"),
            ("$9.99 / year", true, nil),
            ("$1.99 / month", true, "3-day free trial"),
            ("$19.99", false, nil)
        ]
        for c in cases {
            for emphasis in [PriceEmphasis.trialFirst, .billedAmountFirst] {
                let text = StoreService.disclosureText(
                    price: c.price, isSubscription: c.isSubscription, trial: c.trial, emphasis: emphasis
                )
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
