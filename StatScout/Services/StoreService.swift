import Foundation
import os
@preconcurrency import RevenueCat

enum StatScoutProduct {
    static let lifetime = "com.jackwallner.football.pro"
    static let yearly = "com.jackwallner.football.pro.yearly"
    static let monthly = "com.jackwallner.football.pro.monthly"
    static let all: [String] = [yearly, monthly, lifetime]

    static func packageType(for identifier: String) -> PackageType? {
        switch identifier {
        case yearly: return .annual
        case monthly: return .monthly
        case lifetime: return .lifetime
        default: return nil
        }
    }

    static func packageIdentifier(for identifier: String) -> String? {
        switch identifier {
        case yearly: return "$rc_annual"
        case monthly: return "$rc_monthly"
        case lifetime: return "$rc_lifetime"
        default: return nil
        }
    }
}

enum RevenueCatConfig {
    // RevenueCat "Football" project (proj9c303632), App Store app app039a312379.
    // Public SDK key (appl_...) - used only in device Release / TestFlight / App
    // Store builds; simulator runs skip Purchases.configure (see configureIfNeeded).
    static let apiKey = "appl_ivmIolnYwgJaeylzJwULBKiNrIx"
    static let proEntitlement = "Football Pro"
    static let fallbackEntitlement = "pro"
}

enum StatScoutSeason {
    /// The season the nightly pipeline is currently writing. Single source of
    /// truth for the current/historical split - the API filters, the two-tier
    /// cache partition, and the free-tier gate all read this.
    ///
    /// Derived from the calendar rather than pinned to a literal, using the
    /// same rule `backend/ingest.py::resolve_season` uses: an NFL season is
    /// named for the year it kicks off in, so anything from September on
    /// belongs to this year and anything before it to last year. A hard-coded
    /// year meant a shipped build stopped seeing new data the moment the next
    /// season started, and only a new App Store release could fix it - the
    /// pipeline would be writing 2026 rows that no installed copy would ask
    /// for.
    ///
    /// Floored at 2025 so this can never resolve to a season older than the
    /// one the app shipped with, whatever the device clock says.
    static let current: Int = {
        let now = Calendar.current.dateComponents([.year, .month], from: .now)
        guard let year = now.year, let month = now.month else { return 2025 }
        return max(2025, month >= 9 ? year : year - 1)
    }()

    /// The only season available without Pro, and the one every screen opens on.
    ///
    /// Always the calendar's season, the same model as baseball StatScout: the
    /// moment a season starts it is the free, default year, and every season
    /// before it is StatScout+. It used to trail the data instead, holding the
    /// app on last season until the new one had a full slate, which left 2026
    /// invisible (and 2025 free) after the opener had already been played.
    static let free = current

    /// Oldest season with per-game history, and so the floor for Recent Form.
    ///
    /// `player_game_logs` and the rollup built from it were purged back to 2025
    /// once; nothing older exists to rank. Without this floor, "the live season
    /// and the one before it" resolves to a year with no rows the moment the
    /// live season is the oldest one there is, and Trends offers a menu entry
    /// that can only ever draw an empty board.
    static let earliestRecentForm = 2025

    /// Oldest season in the dataset. nflverse player stats run back to 1999;
    /// StatScout starts at 2000 for a clean round-number historical range.
    /// The bundled players-historical.plist ships all of it, so the season
    /// menus can list every year without waiting on a fetch.
    static let earliest = 2000
    /// Sentinel season for the career / all-time rollup.
    ///
    /// The pipeline writes one extra snapshot per player under `season = 0`,
    /// aggregating every year from `earliest` to `current`, with percentiles
    /// ranked inside that career cohort. Modelling it as just another season
    /// rather than a parallel mode is what keeps it working everywhere for
    /// free: the leaderboards, Teams, Compare and the player page all key off
    /// `selectedSeason` and need no all-time branch of their own.
    ///
    /// Zero (rather than, say, 9999) because it sorts below every real year, so
    /// nothing that clamps to a min/max can mistake it for a future season.
    static let allTime = 0

    static func isAllTime(_ season: Int) -> Bool { season == allTime }

    /// Start date for a rolling game-log window on `season`.
    ///
    /// The team cards slice the last 3 / 5 / 8 games out of a wide pull of game
    /// logs, and they used to ask for "the last 120 days" measured from *today*.
    /// That only works while the season is being played. An NFL season ends in
    /// February and the next does not kick off until September, so from roughly
    /// March onward the window reached back into an empty stretch of calendar,
    /// the fetch returned nothing, and every Recent control on a team page
    /// answered "No offense data in the last 5 games" - for the season the app
    /// was otherwise happily showing season totals for. The same held for any
    /// past season all year round.
    ///
    /// So the window is anchored to the end of the season rather than to now:
    /// whichever of the two is earlier. A season named `N` runs from September
    /// `N` to mid-February `N + 1`, so the anchor is capped at 1 March `N + 1`,
    /// safely past the last possible game and cheap to compute without asking
    /// the database when the season actually finished. `days` stays the payload
    /// budget it always was - about a season's worth of weeks, enough to slice
    /// the longest window from.
    static func gameLogWindowStart(season: Int, days: Int = 120, now: Date = .now) -> Date {
        let calendar = Calendar.current
        let seasonEnd = calendar.date(from: DateComponents(year: season + 1, month: 3, day: 1)) ?? now
        let anchor = min(now, seasonEnd)
        return calendar.date(byAdding: .day, value: -days, to: anchor) ?? anchor
    }
}

/// How a season reads in the UI. One place, because the sentinel has to render
/// as "All Time" in the menu, the nav pill, page titles and share text alike -
/// and `String(0)` leaking into any one of them is an obvious bug.
enum SeasonLabel {
    /// "All since 2000" rather than "All Time".
    ///
    /// The rollup covers `earliest` onward, and nflverse only publishes player
    /// stats back to 1999 - so "All Time" claimed a century of football the
    /// data does not have, and put Jim Brown's absence down to a bug rather
    /// than to a start date. Naming the start date is both honest and more
    /// useful: it tells you what you are about to compare against.
    static func text(_ season: Int) -> String {
        StatScoutSeason.isAllTime(season)
            ? "All since \(StatScoutSeason.earliest)"
            : String(season)
    }

    /// Longer form for prose and subtitles ("2024 Regular Season").
    static func text(_ season: Int, phase: SeasonPhase) -> String {
        StatScoutSeason.isAllTime(season)
            ? text(season) + " · " + phase.label
            : String(season) + " " + phase.label
    }
}

enum StatScoutLegal {
    /// Apple's standard EULA - required on the paywall unless a custom one is hosted.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://jackwallner.github.io/football/privacy-policy.html")!
}

/// Session-scoped cap so the same contextual paywall can't be re-presented
/// endlessly as a user pokes at locked features. Resets on app relaunch.
@MainActor
final class PaywallGate: ObservableObject {
    static let shared = PaywallGate()
    private var presentedCount: [PaywallTrigger: Int] = [:]
    private let maxPerTrigger = 2

    /// Returns true if the paywall for this trigger may still be shown.
    /// User-explicit entry points (Settings, toolbar) should bypass this.
    func shouldPresent(_ trigger: PaywallTrigger) -> Bool {
        presentedCount[trigger, default: 0] < maxPerTrigger
    }

    func markPresented(_ trigger: PaywallTrigger) {
        presentedCount[trigger, default: 0] += 1
    }
}

/// Which part of an introductory offer gets the primary visual position.
/// Every live purchase surface uses `billedAmountFirst` for Guideline 3.1.2(c).
/// `trialFirst` remains only so the pure formatting helpers can guard against a
/// future regression in tests.
enum PriceEmphasis {
    case trialFirst
    case billedAmountFirst
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

/// Result of a one-tap CTA that transacts the yearly plan in place.
///
/// `.needsPlanPicker` is the only case that may open `PaywallView`: it means
/// the offering never loaded, so there is nothing to buy and the plan picker's
/// retry/empty state is the honest answer. Every other case is handled inline.
enum DirectPurchaseOutcome: Equatable {
    case unlocked
    case pending
    case cancelled
    case failed(String)
    case needsPlanPicker
}

enum StoreServiceError: LocalizedError {
    case purchasesUnavailableInSimulator

    var errorDescription: String? {
        switch self {
        case .purchasesUnavailableInSimulator:
            return "Purchases are unavailable in simulator builds."
        }
    }
}

enum RCProductKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension RCProductKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains(StatScoutProduct.lifetime.lowercased()) }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains(StatScoutProduct.yearly.lowercased()) || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains(StatScoutProduct.monthly.lowercased()) }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var productKind: RCProductKind {
        RCProductKind(package: self)
    }

    var displayName: String {
        switch productKind {
        case .lifetime: return "Lifetime"
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .other: return storeProduct.localizedTitle
        }
    }

    var priceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        } else {
            return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
        }
    }

    /// Localized per-month price for any recurring package. For a yearly
    /// product priced at $29.99/yr this returns "$2.50". Lifetime / non-
    /// recurring products return nil. Used on the paywall plan card so the
    /// annual price doesn't look like sticker shock next to monthly.
    var monthlyEquivalentLabel: String? {
        guard let period = storeProduct.subscriptionPeriod else { return nil }
        let monthsDecimal: Decimal
        switch period.unit {
        case .day:   monthsDecimal = Decimal(period.value) / Decimal(30)
        case .week:  monthsDecimal = Decimal(period.value) * Decimal(7) / Decimal(30)
        case .month: monthsDecimal = Decimal(period.value)
        case .year:  monthsDecimal = Decimal(period.value) * Decimal(12)
        @unknown default: return nil
        }
        // Only show /mo breakdown for periods that are not already monthly.
        // Showing "$4.99/mo" under a "$4.99/month" price is noise.
        guard monthsDecimal > 1 else { return nil }
        let perMonth = storeProduct.price / monthsDecimal
        let formatter = storeProduct.priceFormatter ?? Self.defaultCurrencyFormatter(currencyCode: storeProduct.currencyCode)
        return formatter.string(from: perMonth as NSDecimalNumber)
    }

    /// Compact "/mo" label suitable for a strike-through anchor on the yearly
    /// card. Returns the package's localized monthly price (per-month for an
    /// annual product, the price itself for a true monthly product).
    var monthlyEquivalentAnchorLabel: String? {
        switch productKind {
        case .monthly:
            return "\(storeProduct.localizedPriceString)/mo"
        case .yearly, .lifetime, .other:
            guard let perMonth = monthlyEquivalentLabel else { return nil }
            return "\(perMonth)/mo"
        }
    }

    private static func defaultCurrencyFormatter(currencyCode: String?) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        if let code = currencyCode { f.currencyCode = code }
        return f
    }

    var introOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.unit == .week {
            return "\(period.value * 7)-day free trial"
        } else {
            return "\(period.value)-\(unit.dropLast(period.value == 1 ? 0 : 1)) free trial"
        }
    }
}

extension CustomerInfo {
    var hasProEntitlement: Bool {
        let active = entitlements.active
        if active[RevenueCatConfig.proEntitlement]?.isActive == true
            || active[RevenueCatConfig.fallbackEntitlement]?.isActive == true {
            return true
        }
        // Belt-and-suspenders: if the entitlement mapping on the dashboard is
        // missing or mis-named, fall back to product ownership. Lifetime is a
        // non-consumable; recurring products show up under activeSubscriptions.
        if nonSubscriptions.contains(where: { $0.productIdentifier == StatScoutProduct.lifetime }) {
            return true
        }
        let recurring: Set<String> = [StatScoutProduct.yearly, StatScoutProduct.monthly]
        if !activeSubscriptions.intersection(recurring).isEmpty {
            return true
        }
        return false
    }
}

extension Offering {
    /// Paywall display order: yearly first (conversion default with trial +
    /// savings badge), then monthly (price anchor), then lifetime (commitment).
    var sortedPackages: [Package] {
        let displayOrder: [RCProductKind] = [.yearly, .monthly, .lifetime, .other]
        return availablePackages.sorted {
            let lhs = displayOrder.firstIndex(of: $0.productKind) ?? displayOrder.count
            let rhs = displayOrder.firstIndex(of: $1.productKind) ?? displayOrder.count
            if lhs != rhs { return lhs < rhs }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    var paywallOffering: Offering? {
        offering(identifier: "default") ?? current
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Package] = []
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    #if DEBUG
    /// Local-only StatScout+ override so Pro-gated surfaces (Recent Form,
    /// past seasons, Compare) can be exercised in the simulator, where
    /// RevenueCat is intentionally never configured. Set the
    /// `STATSCOUT_FORCE_PRO=1` environment variable on the scheme/launch.
    @Published private(set) var isPro: Bool = ProcessInfo.processInfo.environment["STATSCOUT_FORCE_PRO"] == "1"
    #else
    @Published private(set) var isPro: Bool = false
    #endif
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var lastError: String?

    /// Per-product intro-offer eligibility. Populated with `fetchProducts` so
    /// trial copy only appears for users StoreKit will actually grant a trial.
    @Published private(set) var introEligibility: [String: Bool] = [:]

    private var paywallImpressionsThisSession: Set<String> = []

    var proPrice: String? {
        products.first(where: { $0.productKind == .lifetime })?.storeProduct.localizedPriceString
    }

    /// CTA label for the blurred contextual paywalls (Year Compare, Player
    /// Compare). The localized yearly amount leads, with any trial shown below
    /// it by the purchase control.
    var paywallBlurCTA: String {
        directCTALabel(for: .upgrade)
    }

    /// The short label every upgrade entry point uses: the nav-bar pill, the
    /// Settings row, the floating tab bar's crown.
    ///
    /// Matches the approved baseball build exactly. These are navigation
    /// affordances that open the offer, not the offer itself, so they sit
    /// outside the purchase flow 3.1.2(c) governs and App Review did not cite
    /// them. The pure helper keeps the trial branch testable without
    /// configuring RevenueCat in Simulator.
    nonisolated static func upgradeCTALabel(trialAvailable: Bool) -> String {
        trialAvailable ? "Try Free" : "Upgrade"
    }

    var isYearlyTrialAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["STATSCOUT_FORCE_TRIAL_CTA"] == "1" {
            return true
        }
        #endif
        guard let yearly = yearlyPackage else { return false }
        return isEligibleForIntroOffer(yearly) && yearly.introOfferLabel != nil
    }

    var upgradeCTALabel: String {
        Self.upgradeCTALabel(trialAvailable: isYearlyTrialAvailable)
    }

    func directCTALabel(for trigger: PaywallTrigger, emphasis: PriceEmphasis = .billedAmountFirst) -> String {
        if let yearly = yearlyPackage {
            return Self.directCTALabel(
                price: yearly.priceLabel,
                trial: isEligibleForIntroOffer(yearly) ? yearly.introOfferLabel : nil,
                isWinback: trigger == .winback,
                emphasis: emphasis
            )
        }
        if let price = proPrice {
            let verb = trigger == .winback ? "Restart" : "Unlock"
            return "\(verb) StatScout+ for \(price)"
        }
        return trigger == .winback ? "Restart StatScout+" : "Unlock StatScout+"
    }

    /// The label on a button that transacts, as a pure function of the offer.
    ///
    /// A win-back never leads with the trial whatever the emphasis: a lapsed
    /// subscriber has already used it, so offering it again is a promise the
    /// App Store will not keep.
    nonisolated static func directCTALabel(
        price: String,
        trial: String?,
        isWinback: Bool,
        emphasis: PriceEmphasis = .billedAmountFirst
    ) -> String {
        if emphasis == .trialFirst, !isWinback, let trial {
            return "Start \(trial)"
        }
        if emphasis == .billedAmountFirst {
            return "\(isWinback ? "Restart" : "Subscribe") for \(price)"
        }
        return "\(isWinback ? "Restart" : "Try") StatScout+ for \(price)"
    }

    /// The plan picker's own button label, which names no price at all.
    ///
    /// `PaywallView` is the one surface where the billed amount is already the
    /// largest, highest-contrast element on screen: the selected plan card
    /// renders it in `statLarge`/`ink` directly above the button, and the
    /// disclosure directly below leads with it. Repeating it inside the button
    /// bought nothing and cost the offer, so the button names the action
    /// instead. Nothing here promotes the trial over a price the button does not
    /// state, which is the ordering 3.1.2(c) governs.
    ///
    /// Matches the approved `Baseball Savvy StatScout` ladder verbatim. Every
    /// other app in the fleet names a price in a purchase button only as the
    /// fallback for a user with no trial left; none do it when a trial applies.
    nonisolated static func planPickerCTALabel(isLifetime: Bool, trialEligible: Bool) -> String {
        if isLifetime { return "Unlock Lifetime" }
        return trialEligible ? "Start Free Trial" : "Subscribe"
    }

    func planPickerCTALabel(for package: Package) -> String {
        Self.planPickerCTALabel(
            isLifetime: package.productKind == .lifetime,
            trialEligible: isEligibleForIntroOffer(package) && package.introOfferLabel != nil
        )
    }

    /// The trial, kept on the button but demoted beneath the billed amount.
    ///
    /// 3.1.2(c) does not forbid selling the free trial, it forbids selling it
    /// *more prominently* than what the user will be charged. So the
    /// `.billedAmountFirst` button carries both: the price on the top line in
    /// the button's own type, this one underneath in micro at reduced opacity.
    /// Dropping the trial from the button entirely would have cleared the
    /// guideline by giving up the pitch, which is a worse trade than sizing it
    /// correctly.
    ///
    /// nil when there is no trial to name, and on a win-back for the same
    /// reason `directCTALabel` never leads with one there.
    func directCTATrialSubline(for trigger: PaywallTrigger, emphasis: PriceEmphasis) -> String? {
        guard let yearly = yearlyPackage else { return nil }
        return Self.directCTATrialSubline(
            trial: isEligibleForIntroOffer(yearly) ? yearly.introOfferLabel : nil,
            isWinback: trigger == .winback,
            emphasis: emphasis
        )
    }

    nonisolated static func directCTATrialSubline(
        trial: String?,
        isWinback: Bool,
        emphasis: PriceEmphasis
    ) -> String? {
        guard emphasis == .billedAmountFirst, !isWinback, let trial else { return nil }
        return "Starts with a \(trial)"
    }

    /// One-line secondary caption shown under the CTA when a trial is offered,
    /// so the price after the trial isn't hidden.
    var paywallBlurSubtext: String? {
        guard let yearly = products.first(where: { $0.productKind == .yearly }),
              isEligibleForIntroOffer(yearly),
              yearly.introOfferLabel != nil else { return nil }
        return "Then \(yearly.priceLabel). Cancel anytime."
    }

    /// The yearly package - the one-tap conversion target for every trial /
    /// teaser pop-up (onboarding, TrialPitchSheet, blur CTAs). Those surfaces
    /// purchase this directly, trial or not; the full `PaywallView` is only the
    /// fallback when this is nil (products not loaded), or for deliberate
    /// upgrade entry points where the user should pick a plan.
    var yearlyPackage: Package? {
        products.first { $0.productKind == .yearly }
    }

    /// Full Apple-3.1.2 auto-renew disclosure for the yearly plan, shown next
    /// to any direct-purchase CTA so the price (and trial terms, when offered)
    /// are present at the point of purchase.
    func yearlyCTADisclosureText(emphasis: PriceEmphasis = .billedAmountFirst) -> String? {
        yearlyPackage.map { disclosureText(for: $0, emphasis: emphasis) }
    }

    var yearlyCTADisclosureText: String? { yearlyCTADisclosureText() }

    /// The disclosure for one package. The plan picker renders this for
    /// whichever plan is selected; every one-tap CTA renders it for the yearly
    /// one. Both go through here so the wording can only ever be wrong once.
    func disclosureText(for package: Package, emphasis: PriceEmphasis = .billedAmountFirst) -> String {
        Self.disclosureText(
            price: package.priceLabel,
            isSubscription: package.productKind != .lifetime,
            trial: isEligibleForIntroOffer(package) ? package.introOfferLabel : nil,
            emphasis: emphasis
        )
    }

    /// The disclosure copy, as a pure function of the facts a purchase point
    /// has to state: what it costs, whether it renews, and what the trial is.
    /// Pure so the exact wording is testable with no RevenueCat, no StoreKit
    /// and no network - see `PriceDisclosureTests`.
    nonisolated static func disclosureText(
        price: String,
        isSubscription: Bool,
        trial: String?,
        emphasis: PriceEmphasis = .billedAmountFirst
    ) -> String {
        guard isSubscription else {
            return "\(price). One-time purchase. Lifetime access, no subscription."
        }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
        guard let trial else { return "\(price). \(renew)" }
        switch emphasis {
        case .trialFirst:
            return "\(trial.capitalized), then \(price). \(renew)"
        case .billedAmountFirst:
            return "\(price), billed after a \(trial). \(renew)"
        }
    }

    /// Onboarding pitches the monthly plan, not the yearly one. The trial is
    /// identical on both, so the smaller number is the smaller commitment to
    /// agree to before the user has seen the app work; the yearly plan is what
    /// `PaywallView` sells, where the savings are visible next to it.
    var onboardingMonthlyCTALabel: String {
        guard let monthly = monthlyPackage else { return "Upgrade to StatScout+" }
        return Self.directCTALabel(
            price: monthly.priceLabel,
            trial: isEligibleForIntroOffer(monthly) ? monthly.introOfferLabel : nil,
            isWinback: false
        )
    }

    /// Full Apple-3.1.2 auto-renew disclosure for the monthly plan, for the
    /// onboarding CTA that buys it directly.
    var onboardingMonthlyDisclosureText: String? {
        monthlyPackage.map { disclosureText(for: $0) }
    }

    /// The monthly package, when present. Used as the anchor when computing
    /// yearly savings % and rendering a strike-through monthly-equivalent price.
    var monthlyPackage: Package? {
        products.first { $0.productKind == .monthly }
    }

    /// Integer savings % the yearly package offers vs. 12× the monthly price.
    /// Returns nil unless both packages are present and the math is favorable.
    func yearlySavingsPercent(yearly: Package) -> Int? {
        guard yearly.productKind == .yearly, let monthly = monthlyPackage else { return nil }
        let yearlyPrice = yearly.storeProduct.price
        let twelveMonths = monthly.storeProduct.price * Decimal(12)
        guard twelveMonths > 0, yearlyPrice < twelveMonths else { return nil }
        let saving = (twelveMonths - yearlyPrice) / twelveMonths * Decimal(100)
        var rounded = Decimal()
        var src = saving
        NSDecimalRound(&rounded, &src, 0, .plain)
        let percent = NSDecimalNumber(decimal: rounded).intValue
        return percent > 0 ? percent : nil
    }

    /// Strike-through anchor price for the yearly card - "$4.99/mo" if a
    /// monthly package exists. Nil when there's nothing to anchor against.
    var monthlyAnchorPriceLabel: String? {
        monthlyPackage?.monthlyEquivalentAnchorLabel
    }

    /// True when this package advertises a free trial and the user is eligible.
    /// Unknown eligibility resolves to true so a transient lookup failure does
    /// not hide a trial the user likely qualifies for (Vitals pattern).
    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.introOfferLabel != nil else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? true
    }

    /// Reports a custom-paywall impression to RevenueCat (required for native UI).
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        guard configureIfNeeded() else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_PRO"] == "1" { return }
        #endif
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        ConversionDiagnostics.recordPitchView(impressionID: id)
        syncConversionAttributes()
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    /// Mirrors the on-device paywall record onto the RevenueCat customer.
    ///
    /// Attributes rather than extra impressions: RevenueCat treats every
    /// impression id as a paywall encounter, so funnel steps sent that way would
    /// drive the encounter rate to 100% and destroy the one server-side number
    /// that currently works.
    ///
    /// `configureIfNeeded()` is the load-bearing guard: `Purchases.shared` traps
    /// when RevenueCat was never configured, which is every simulator run.
    ///
    /// `setAttributes` only queues. RevenueCat uploads when the app backgrounds
    /// or folds the queue into the POST that creates a customer, so a probe run
    /// has to background the app before reading anything back.
    func syncConversionAttributes() {
        guard configureIfNeeded() else { return }
        var attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        if let offering = currentOffering?.identifier {
            attributes["offering_id"] = offering
        }
        Purchases.shared.attribution.setAttributes(attributes)
    }

    /// True when the user once held a Pro entitlement that has since expired and
    /// isn't currently active. Used to show a tailored win-back paywall.
    var isLapsed: Bool {
        guard !isPro, let info = customerInfo else { return false }
        return info.entitlements.all.values.contains { entitlement in
            !entitlement.isActive
                && (entitlement.expirationDate.map { $0 < Date() } ?? false)
        }
    }

    /// The generic "upgrade" ask, swapped to a win-back variant for lapsed users.
    var defaultUpgradeTrigger: PaywallTrigger {
        isLapsed ? .winback : .upgrade
    }

    private let logger = Logger(subsystem: "com.jackwallner.football", category: "Store")
    private var isConfigured = false

    private override init() {}

    func start() {
        #if DEBUG
        // UI-test / local hook: force Pro so the gated surfaces (Recent Form,
        // Compare) render without a sandbox purchase. Never compiled into Release.
        if ProcessInfo.processInfo.environment["FORCE_PRO"] == "1" {
            isPro = true
            return
        }
        // Launch with `-MockProducts` to run the *whole app* with priced
        // packages on a simulator. RevenueCat is deliberately never configured
        // there, so without this every paywall surface renders with no price
        // and no disclosure, which makes exactly the copy App Review checks the
        // one thing that cannot be checked before upload. Loads the same mock
        // packages the screenshot harness uses: no configure, no StoreKit, no
        // network, so the prod project stays clean.
        if ProcessInfo.processInfo.arguments.contains("-MockProducts") {
            loadScreenshotProducts()
            return
        }
        #endif
        guard configureIfNeeded() else { return }
        Task { await updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        Task { await fetchProducts() }
    }

    func fetchProducts() async {
        guard configureIfNeeded() else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.paywallOffering
            currentOffering = offering
            let offeringPackages = offering?.sortedPackages ?? []
            products = offeringPackages.isEmpty
                ? await fetchDirectPackages()
                : offeringPackages
            lastError = products.isEmpty
                ? "Subscription options are temporarily unavailable. Please try again."
                : nil
            await refreshIntroEligibility()
        } catch {
            logger.error("Offering fetch failed: \(String(describing: error), privacy: .public)")
            products = await fetchDirectPackages()
            lastError = products.isEmpty
                ? "Couldn't load subscription options. Check your connection and try again."
                : nil
            await refreshIntroEligibility()
        }
    }

    private func fetchDirectPackages() async -> [Package] {
        let storeProducts = await Purchases.shared.products(StatScoutProduct.all)
        let packages = storeProducts.compactMap { product -> Package? in
            guard let packageType = StatScoutProduct.packageType(for: product.productIdentifier),
                  let packageIdentifier = StatScoutProduct.packageIdentifier(for: product.productIdentifier) else {
                return nil
            }
            return Package(
                identifier: packageIdentifier,
                packageType: packageType,
                storeProduct: product,
                offeringIdentifier: currentOffering?.identifier ?? "default",
                webCheckoutUrl: nil
            )
        }
        return packages.sorted { lhs, rhs in
            guard let lhsIndex = StatScoutProduct.all.firstIndex(of: lhs.storeProduct.productIdentifier),
                  let rhsIndex = StatScoutProduct.all.firstIndex(of: rhs.storeProduct.productIdentifier) else {
                return lhs.storeProduct.productIdentifier < rhs.storeProduct.productIdentifier
            }
            return lhsIndex < rhsIndex
        }
    }

    @discardableResult
    func purchase(_ product: Package) async throws -> PurchaseState {
        guard configureIfNeeded() else {
            throw StoreServiceError.purchasesUnavailableInSimulator
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let startedTrial = isEligibleForIntroOffer(product)
        let result = try await Purchases.shared.purchase(package: product)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        } else if result.customerInfo.hasProEntitlement {
            ConversionDiagnostics.recordConversion(
                plan: product.storeProduct.productIdentifier,
                startedTrial: startedTrial,
                offeringID: currentOffering?.identifier
            )
            syncConversionAttributes()
            return .purchased
        } else {
            return .pending
        }
    }

    /// The single conversion path behind every pitch in the app.
    ///
    /// A CTA that names an offer ("Start 7-day free trial") has to *be* that
    /// offer: the next thing the user sees is Apple's confirm sheet, never a
    /// second pitch asking them to agree again. Surfaces that used to hand off
    /// to `PaywallView` call this instead; the plan picker is now reachable
    /// only from a deliberate "See all plans" link, or as the fallback when the
    /// offering failed to load and there is genuinely nothing to buy.
    func purchaseYearlyDirect() async -> DirectPurchaseOutcome {
        if yearlyPackage == nil, currentOffering == nil {
            await fetchProducts()
        }
        guard let yearly = yearlyPackage else { return .needsPlanPicker }
        do {
            switch try await purchase(yearly) {
            case .purchased:
                return .unlocked
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            }
        } catch {
            return .failed(lastError ?? "Couldn't complete the purchase. Please try again.")
        }
    }

    func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        guard configureIfNeeded() else { return }
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
            apply(customerInfo: info)
            lastError = nil
        } catch {
            logger.error("Customer info refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
    }

    func restorePurchases() async {
        guard configureIfNeeded() else {
            lastError = StoreServiceError.purchasesUnavailableInSimulator.localizedDescription
            return
        }
        lastError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            lastError = isPro ? nil : "No active StatScout+ purchase was found for this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    private func refreshIntroEligibility() async {
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map(\.storeProduct.productIdentifier)
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
    }

    func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let activeKeys = customerInfo.entitlements.active.keys.sorted().joined(separator: ", ")
        let allKeys = customerInfo.entitlements.all.keys.sorted().joined(separator: ", ")
        logger.info("Applied customerInfo - active: [\(activeKeys, privacy: .public)] all: [\(allKeys, privacy: .public)]")
        let hasActiveSubscription = customerInfo.hasProEntitlement
        if isPro != hasActiveSubscription {
            isPro = hasActiveSubscription
            logger.info("isPro updated to \(hasActiveSubscription, privacy: .public)")
        }
    }

    #if DEBUG
    /// Populates `products` with mock packages (RevenueCat `TestStoreProduct`) so
    /// the real PaywallView renders with correct prices/trials for App Store and
    /// App Review screenshots - no `Purchases.configure`, no StoreKit, no network,
    /// so prod RevenueCat stays clean. Used by `PaywallScreenshotHarness`.
    func loadScreenshotProducts() {
        let locale = Locale(identifier: "en_US")
        func weekTrial() -> TestStoreProductDiscount {
            TestStoreProductDiscount(
                identifier: "free_trial", price: 0, localizedPriceString: "$0.00",
                paymentMode: .freeTrial, subscriptionPeriod: .init(value: 1, unit: .week),
                numberOfPeriods: 1, type: .introductory)
        }
        // US prices as configured in App Store Connect (verified 2026-08-11:
        // monthly 1.99, yearly 9.99, lifetime 19.99, both subscriptions with a
        // one-week free trial). The 2026-08-10 fleet raise was rolled back here
        // so 1.0 launches at the prices its listing already quotes; the raise
        // returns with the first update. Mock prices that do not match the real
        // ones make every screenshot taken through this path a picture of copy
        // nobody will ever be shown.
        let monthly = TestStoreProduct(
            localizedTitle: "Gridiron Pro Monthly", price: 1.99, currencyCode: "USD",
            localizedPriceString: "$1.99", productIdentifier: StatScoutProduct.monthly,
            productType: .autoRenewableSubscription, localizedDescription: "Gridiron Pro, billed monthly.",
            subscriptionPeriod: .init(value: 1, unit: .month), introductoryDiscount: weekTrial(), locale: locale)
        let yearly = TestStoreProduct(
            localizedTitle: "Gridiron Pro Yearly", price: 9.99, currencyCode: "USD",
            localizedPriceString: "$9.99", productIdentifier: StatScoutProduct.yearly,
            productType: .autoRenewableSubscription, localizedDescription: "Gridiron Pro, billed yearly.",
            subscriptionPeriod: .init(value: 1, unit: .year), introductoryDiscount: weekTrial(), locale: locale)
        let lifetime = TestStoreProduct(
            localizedTitle: "Gridiron Pro Lifetime", price: 19.99, currencyCode: "USD",
            localizedPriceString: "$19.99", productIdentifier: StatScoutProduct.lifetime,
            productType: .nonConsumable, localizedDescription: "Gridiron Pro, one-time purchase.",
            subscriptionPeriod: nil, introductoryDiscount: nil, locale: locale)
        products = [
            Package(identifier: "$rc_annual", packageType: .annual,
                    storeProduct: yearly.toStoreProduct(), offeringIdentifier: "default", webCheckoutUrl: nil),
            Package(identifier: "$rc_monthly", packageType: .monthly,
                    storeProduct: monthly.toStoreProduct(), offeringIdentifier: "default", webCheckoutUrl: nil),
            Package(identifier: "$rc_lifetime", packageType: .lifetime,
                    storeProduct: lifetime.toStoreProduct(), offeringIdentifier: "default", webCheckoutUrl: nil),
        ]
        introEligibility = [StatScoutProduct.monthly: true, StatScoutProduct.yearly: true]
        isLoadingProducts = false
        lastError = nil
    }
    #endif

    @discardableResult
    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        #if targetEnvironment(simulator)
        // Agent/sim runs must NOT hit the prod RevenueCat project - configuring
        // the prod appl_ key on the simulator creates fake "new customers" in the
        // prod charts (RC has no dashboard switch to exclude sim installs). Skip
        // configure entirely; use StoreKit Testing + a local Pro override for
        // paywall/IAP flows on device-less runs.
        #if DEBUG
        // The one exception, behind a launch argument: the Test Store key is a
        // separate RevenueCat app inside the same project, so a probe run cannot
        // touch App Store customers, revenue or charts. See RevenueCatProbe.
        if RevenueCatProbe.isEnabled {
            Purchases.logLevel = .debug
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: RevenueCatProbe.testStoreKey)
                    .with(appUserID: RevenueCatProbe.appUserID)
                    .build()
            )
            Purchases.shared.delegate = self
            isConfigured = true
            return true
        }
        #endif
        return false
        #else
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
        return true
        #endif
    }
}

extension StoreService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}

#if DEBUG
/// Simulator-only proof path for the fleet-wide funnel attributes.
///
/// Under the normal rules the attributes cannot be verified on a simulator: the
/// production key must never be configured there, so RevenueCat is never
/// configured, so nothing is ever sent, so a physical device is the only
/// witness. The Test Store key is a different RevenueCat app inside the same
/// project, so a probe run cannot touch App Store customers, revenue or charts.
///
/// DEBUG only, and only with the launch argument, so it cannot reach a Release
/// build or an ordinary simulator run.
enum RevenueCatProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobe")
    }

    static let testStoreKey = "test_FtMVMMBAPeuKgtivRHTXSamfcEA"

    static var appUserID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_USER"] ?? "funnel-probe-football"
    }

    /// Also run a purchase against the Test Store, so the `converted_*` half of
    /// the record is exercised and not just the impression half.
    ///
    /// Test Store purchases are simulated by RevenueCat: no StoreKit, no App
    /// Store, no revenue, no real transaction. RevenueCat puts up its own
    /// confirmation sheet, so this needs a UI test to tap it.
    static var wantsPurchase: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobepurchase")
    }

    static var impressionID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_SURFACE"] ?? "statscout_paywall_onboarding"
    }
}
#endif
