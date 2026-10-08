import RevenueCat
import StoreKit
import StoreKitTest
import XCTest
@testable import Gridiron_StatScout

/// The purchase flow, run against a real StoreKit implementation.
///
/// Every other price test in this repo asserts our copy functions against
/// hand-typed fixtures: feed in "$9.99 / year" and "7-day free trial", check
/// the sentence that comes out. That proves the formatting and nothing about
/// whether the store ever produces those two strings. The 1.0 (19) rejection
/// was a copy problem, and the copy is assembled from store data, so the half
/// that was never covered is the half that shipped the bug.
///
/// `SKTestSession` closes it. It serves `StatScout.storekit` from the test
/// bundle, so `Product.products(for:)` returns real `Product` values with real
/// prices and a real introductory offer, and the copy below is built from those
/// rather than from strings someone typed into a test. No App Store account, no
/// sandbox login, no network, no charge.
///
/// Three things this deliberately does not cover:
///
/// - **Transactions.** Every *mutating* `SKTestSession` call on the agent-sim
///   pool fails with `SKInternalErrorDomain Code=3` ("Error saving
///   configuration file"), and `buyProduct` then fails "in off-device buy
///   mode". Reads work, writes do not, with or without the scheme's StoreKit
///   configuration and with or without the config in the app bundle - all three
///   were tried (2026-08-07). StoreKit 2's `product.purchase()` hangs instead,
///   waiting on a confirmation sheet that never appears in a test host. So an
///   actual purchase still has to happen on a device, and that check stays on
///   Jack's pre-submission list.
/// - **RevenueCat's backend.** `configureIfNeeded()` returns false on the
///   simulator on purpose (the prod `appl_` key would invent customers in the
///   live charts), so entitlement sync and receipt validation are not exercised
///   here. What is exercised is everything between StoreKit and the label on
///   the button, which is where the rejection lived.
/// - **The UI-test runner**, which reports "application is not running" on the
///   shared pool. `SKTestSession` loads the configuration itself rather than
///   relying on the scheme, which is what lets this run as a plain unit test.
final class StoreKitPurchaseTests: XCTestCase {

    private var session: SKTestSession!

    private let renewSentence = "Auto-renews unless cancelled at least 24 hours before the end of the current period."
    private let cancelSentence = "Manage or cancel in Settings › Apple ID › Subscriptions."

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Loaded by URL out of the *test* bundle. The `configurationFileNamed:`
        // initializer looks in the application bundle, and the config ships
        // with the tests rather than the app.
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "StatScout", withExtension: "storekit"),
            "StatScout.storekit is missing from the test bundle's resources"
        )
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        // Headless: no confirm sheet, no Ask to Buy prompt.
        session.disableDialogs = true
        session.askToBuyEnabled = false
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func storeProducts() async throws -> [String: Product] {
        let products = try await Product.products(for: StatScoutProduct.all)
        return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    /// The same mapping `StoreService.fetchDirectPackages()` performs, so these
    /// assertions run over the type the paywall actually reads.
    private func package(for identifier: String) async throws -> Package {
        let products = try await storeProducts()
        let product = try XCTUnwrap(products[identifier], "\(identifier) is not in the catalog")
        return Package(
            identifier: try XCTUnwrap(StatScoutProduct.packageIdentifier(for: identifier)),
            packageType: try XCTUnwrap(StatScoutProduct.packageType(for: identifier)),
            storeProduct: StoreProduct(sk2Product: product),
            offeringIdentifier: "default",
            webCheckoutUrl: nil
        )
    }

    // MARK: - Catalog

    func testTheStoreSellsExactlyTheThreePlansTheAppOffers() async throws {
        let products = try await storeProducts()
        XCTAssertEqual(Set(products.keys), Set(StatScoutProduct.all))
        XCTAssertEqual(products[StatScoutProduct.yearly]?.displayPrice, "$9.99")
        XCTAssertEqual(products[StatScoutProduct.monthly]?.displayPrice, "$1.99")
        XCTAssertEqual(products[StatScoutProduct.lifetime]?.displayPrice, "$19.99")
        XCTAssertEqual(products[StatScoutProduct.lifetime]?.type, .nonConsumable)
    }

    /// Both subscriptions carry the trial, which is what lets onboarding pitch
    /// the monthly plan and the in-app sheets pitch the yearly one without
    /// either promising a trial the store would refuse.
    func testBothSubscriptionsOfferTheSevenDayTrial() async throws {
        let products = try await storeProducts()
        for identifier in [StatScoutProduct.yearly, StatScoutProduct.monthly] {
            let subscription = try XCTUnwrap(products[identifier]?.subscription)
            let offer = try XCTUnwrap(subscription.introductoryOffer, "\(identifier) has no intro offer")
            XCTAssertEqual(offer.paymentMode, .freeTrial)
            // StoreKit normalizes the configured P1W to 7 days rather than 1
            // week, so assert the duration, not the unit it chose to express it
            // in. `introOfferLabel` handles both spellings and says "7-day free
            // trial" either way - see the copy tests below.
            let days = offer.period.unit == .day ? offer.period.value : offer.period.value * 7
            XCTAssertEqual(days, 7, "\(identifier) trial is not seven days")
        }
    }

    // MARK: - The copy App Review reads, built from real store data

    /// The end of the 3.1.2(c) chain: real `Product` → `StoreProduct` →
    /// `Package` → the two strings on the button and the disclosure under it.
    /// If StoreKit ever returns something other than a $9.99 yearly with a
    /// one-week trial, this fails here instead of in App Review.
    func testTheCitedSheetsCopyIsRightAgainstRealStoreData() async throws {
        let yearly = try await package(for: StatScoutProduct.yearly)

        XCTAssertEqual(yearly.priceLabel, "$9.99 / year")
        XCTAssertEqual(yearly.introOfferLabel, "7-day free trial")

        XCTAssertEqual(
            StoreService.directCTALabel(
                price: yearly.priceLabel, trial: yearly.introOfferLabel,
                isWinback: false, emphasis: .billedAmountFirst
            ),
            "Subscribe for $9.99 / year"
        )
        XCTAssertEqual(
            StoreService.directCTATrialSubline(
                trial: yearly.introOfferLabel, isWinback: false, emphasis: .billedAmountFirst
            ),
            "Starts with a 7-day free trial"
        )
        XCTAssertEqual(
            StoreService.disclosureText(
                price: yearly.priceLabel, isSubscription: true,
                trial: yearly.introOfferLabel, emphasis: .billedAmountFirst
            ),
            "$9.99 / year, billed after a 7-day free trial. \(renewSentence) \(cancelSentence)"
        )
    }

    /// Every purchase surface uses the same billed-amount-first default against
    /// the same real product.
    func testEverySurfaceCopyIsRightAgainstRealStoreData() async throws {
        let yearly = try await package(for: StatScoutProduct.yearly)
        XCTAssertEqual(
            StoreService.directCTALabel(
                price: yearly.priceLabel, trial: yearly.introOfferLabel, isWinback: false
            ),
            "Subscribe for $9.99 / year"
        )
    }

    /// A non-consumable has no period, so it must not pick up "/ year" or an
    /// auto-renew sentence.
    func testTheLifetimePlanIsNeverDescribedAsRenewing() async throws {
        let lifetime = try await package(for: StatScoutProduct.lifetime)
        XCTAssertEqual(lifetime.priceLabel, "$19.99")
        XCTAssertNil(lifetime.introOfferLabel)
        let text = StoreService.disclosureText(
            price: lifetime.priceLabel, isSubscription: false, trial: nil
        )
        XCTAssertEqual(text, "$19.99. One-time purchase. Lifetime access, no subscription.")
        XCTAssertFalse(text.contains("Auto-renews"))
    }

    // MARK: - Ineligibility, which is what a real purchase produces

    /// A returning user the store will not give a trial to must not be shown
    /// one. The purchase that produces that state cannot be simulated here (see
    /// the note at the top), so this pins the copy for the state itself: the
    /// store says "no trial", and the sheet drops the promise without losing
    /// the price.
    func testWhenTheStoreWithholdsTheTrialTheSheetStopsPromisingOne() async throws {
        let yearly = try await package(for: StatScoutProduct.yearly)
        XCTAssertEqual(
            StoreService.directCTALabel(
                price: yearly.priceLabel, trial: nil, isWinback: false, emphasis: .billedAmountFirst
            ),
            "Subscribe for $9.99 / year"
        )
        XCTAssertNil(
            StoreService.directCTATrialSubline(
                trial: nil, isWinback: false, emphasis: .billedAmountFirst
            )
        )
        XCTAssertEqual(
            StoreService.disclosureText(
                price: yearly.priceLabel, isSubscription: true, trial: nil, emphasis: .billedAmountFirst
            ),
            "$9.99 / year. \(renewSentence) \(cancelSentence)"
        )
    }

    /// A lapsed subscriber has already spent the trial, so the win-back offer
    /// never mentions one whatever the store reports about eligibility.
    func testTheWinbackOfferNeverPromisesATrialTheUserHasSpent() async throws {
        let yearly = try await package(for: StatScoutProduct.yearly)
        let label = StoreService.directCTALabel(
            price: yearly.priceLabel, trial: yearly.introOfferLabel,
            isWinback: true, emphasis: .billedAmountFirst
        )
        XCTAssertEqual(label, "Restart for $9.99 / year")
        XCTAssertNil(
            StoreService.directCTATrialSubline(
                trial: yearly.introOfferLabel, isWinback: true, emphasis: .billedAmountFirst
            )
        )
    }

    /// A fresh tester is eligible for the intro offer. This is the input that
    /// decides whether the trial copy renders at all, read from StoreKit rather
    /// than assumed.
    func testAFreshUserIsEligibleForTheIntroductoryOffer() async throws {
        let products = try await storeProducts()
        let yearly = try XCTUnwrap(products[StatScoutProduct.yearly]?.subscription)
        let eligible = await yearly.isEligibleForIntroOffer
        XCTAssertTrue(eligible, "A user with no purchase history should be offered the trial")
    }
}
