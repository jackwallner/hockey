import SwiftUI
@preconcurrency import RevenueCat

enum PaywallTrigger: Identifiable, Hashable {
    var id: Self { self }

    case pastSeason
    /// A specific locked year the user reached for. Naming the year they were
    /// curious about converts better than a generic "unlock more" pitch, so the
    /// season menus route through this rather than `.pastSeason`.
    case lockedSeason(Int)
    case yearCompare
    case playerComparison
    case onboarding
    case activation
    case upgrade
    case pastSeasonsLoad
    case teamView
    case winback
    /// Soft, half-sheet trial pitch shown on a free user's first player open.
    /// Distinct from the old `.activation` full-PaywallView popup (removed for
    /// being too intrusive), this routes through TrialPitchSheet, which is
    /// native/intentional, dismissible with "Maybe later", and gated by
    /// PaywallGate so it caps at 2 per session.
    case playerScouting
    /// Soft pitch from the blurred Recent Form teaser on the leaderboard.
    case recentForm
    /// Best & Worst, reached from the Stats tab's View menu.
    case bestWorst
    /// Player-level advanced tables on a game's box score.
    case advancedBoxScore

    var icon: String {
        switch self {
        case .pastSeason:        return "calendar.badge.clock"
        case .lockedSeason:      return "calendar.badge.clock"
        case .yearCompare:       return "arrow.left.arrow.right.circle.fill"
        case .playerComparison:  return "person.2.fill"
        case .onboarding:        return "crown.fill"
        case .activation:        return "crown.fill"
        case .upgrade:           return "crown.fill"
        case .pastSeasonsLoad:   return "clock.arrow.circlepath"
        case .teamView:          return "shield.lefthalf.filled"
        case .winback:           return "arrow.counterclockwise.circle.fill"
        case .playerScouting:    return "binoculars.fill"
        case .recentForm:        return "flame.fill"
        case .bestWorst:         return "arrow.up.arrow.down"
        case .advancedBoxScore:  return "hockey.puck.fill"
        }
    }

    var title: String {
        switch self {
        case .pastSeason:        return "Unlock Past Seasons"
        case .lockedSeason(let year): return year == SeasonLabel.allTime ? "Unlock All Time" : "Unlock \(SeasonLabel.display(year))"
        case .yearCompare:       return "Year-over-Year Comparison"
        case .playerComparison:  return "Player Comparison"
        case .onboarding:        return "Scout Like a GM"
        case .activation:        return "Get the Full Picture"
        case .upgrade:           return "Scout Every Player"
        case .pastSeasonsLoad:   return "Load Past Seasons"
        case .teamView:          return "Team Insights"
        case .winback:           return "Welcome Back"
        case .playerScouting:    return "Full Player Scouting"
        case .recentForm:        return "Recent Form"
        case .bestWorst:         return "Best & Worst"
        case .advancedBoxScore:  return "Advanced Box Scores"
        }
    }

    var subtitle: String {
        switch self {
        case .pastSeason:
            return "Track how every player ranked since 2008-09, plus the year-over-year trends behind today's leaders."
        case .lockedSeason(let year):
            return "See every player's \(SeasonLabel.display(year)) percentile rankings, and how they stack up against any other season."
        case .yearCompare:
            return "Compare any player's percentile rankings across any two seasons. See what changed, what held, and where they're headed."
        case .playerComparison:
            return "Stack any two players head-to-head across every NHL metric: ixG, GAx, xGF%, GSAx and more."
        case .onboarding:
            return "The Trends board, recent form, head-to-head matchups, and every season back to 2008-09. The full NHL picture on every player."
        case .activation:
            return "The Trends board, recent form, head-to-head matchups, and every season back to 2008-09. The full NHL picture on every player."
        case .upgrade:
            return "The Trends board, recent form, head-to-head matchups, and every season back to 2008-09. The full NHL picture on every player."
        case .pastSeasonsLoad:
            return "Load historical data to explore past seasons, year-over-year trends, and more."
        case .teamView:
            return "Advanced and standard stats for every club, a roster you can rank by any metric over any window, and side-by-side comparisons for every squad."
        case .winback:
            return "Your StatScout+ access has lapsed. Pick it back up to get the Trends board, recent form, head-to-head matchups, and every past season."
        case .playerScouting:
            return "Last 2 / 4 / 8 week form, head-to-head matchups, every roster. The full picture, not just season totals."
        case .recentForm:
            return "Every player's last 2 / 4 / 8 week form. Catch hot streaks and slumps before the season totals catch up."
        case .bestWorst:
            return "The league leader and the league trailer on every NHL metric, side by side, in one board."
        case .advancedBoxScore:
            return "Every player in every game: expected goals, high-danger chances and the xG race, beside the box score."
        }
    }

    /// RevenueCat custom-paywall impression id for this entry point.
    var paywallImpressionId: String {
        switch self {
        case .pastSeason:        return "statscout_paywall_past_season"
        case .lockedSeason:      return "statscout_paywall_locked_season"
        case .yearCompare:       return "statscout_paywall_year_compare"
        case .playerComparison:  return "statscout_paywall_player_comparison"
        case .onboarding:        return "statscout_paywall_onboarding"
        case .activation:        return "statscout_paywall_activation"
        case .upgrade:           return "statscout_paywall_upgrade"
        case .pastSeasonsLoad:   return "statscout_paywall_past_seasons_load"
        case .teamView:          return "statscout_paywall_team_view"
        case .winback:           return "statscout_paywall_winback"
        case .playerScouting:    return "statscout_paywall_player_scouting"
        case .recentForm:        return "statscout_paywall_recent_form"
        case .bestWorst:         return "statscout_paywall_best_worst"
        case .advancedBoxScore:  return "statscout_paywall_advanced_box_score"
        }
    }

    /// What the subscription actually opens, kept in step with the app. The
    /// Trends board and the team Advanced / Standard windows shipped after this
    /// list was written and went unmentioned, so the pitch was selling less
    /// than the product does.
    private static let proFeatures: [(icon: String, title: String)] = [
        ("flame.fill", "The Trends board: who's heating up and cooling off, league-wide"),
        ("chart.bar.fill", "Last 2 / 4 / 8 week form on any player, team or leaderboard"),
        ("person.2.fill", "Head-to-head: any two players, every metric"),
        ("shield.lefthalf.filled", "Team scouting: advanced and standard, season or recent"),
        ("hockey.puck.fill", "Every player's line in every box score: ixG, GAx and goalie GSAx"),
        ("calendar.badge.clock", "Every season back to 2008-09 plus year\u{2011}over\u{2011}year trends")
    ]

    var features: [(icon: String, title: String)] {
        Self.proFeatures
    }
}

/// Native StatScout+ paywall. Purchases flow through `StoreService.purchase`
/// → `Purchases.shared.purchase` so RevenueCat records transactions unchanged.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var hasDismissed = false

    init(trigger: PaywallTrigger = .upgrade) {
        self.trigger = trigger
    }

    var body: some View {
        ZStack {
            RinkPalette.canvas.ignoresSafeArea()

            if store.isLoadingProducts && store.products.isEmpty {
                loadingState
            } else if store.products.isEmpty {
                emptyState
            } else {
                content
            }

            // The hero scrolls up under the status bar; this keeps the clock and
            // battery on a solid midnight strip instead of over the headline.
            VStack {
                RinkPalette.midnight
                    .frame(height: 0)
                    .background(RinkPalette.midnight.ignoresSafeArea(edges: .top))
                Spacer()
            }
            .allowsHitTesting(false)

            closeButton
        }
        .onAppear { PaywallGate.shared.markPresented(trigger) }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismissOnce() }
        }
        .task {
            store.trackPaywallImpression(id: trigger.paywallImpressionId)
            if store.products.isEmpty { await store.fetchProducts() }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: store.products.count) { _, _ in selectDefaultPackageIfNeeded() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(RinkPalette.turf)
            Text("Loading plans…")
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(RinkPalette.inkTertiary)
            Text("Couldn't Load Plans")
                .font(RinkType.cardTitle)
                .foregroundStyle(RinkPalette.inkSecondary)
            Text(store.lastError ?? "Check your connection and try again.")
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task {
                    await store.fetchProducts()
                    selectDefaultPackageIfNeeded()
                }
            }
            .font(RinkType.bodyBold)
            .foregroundStyle(RinkPalette.turf)
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    heroHeader

                    VStack(spacing: 16) {
                        featureList
                        trustRow
                        planCards
                        purchaseSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: 680)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // Bold midnight hero: the entry-point icon over a faint percentile-bar motif,
    // a "Pro" eyebrow, the benefit headline, and the emotional subtitle. Sells
    // the upgrade before any pricing, pricing/feature density comes below.
    private var heroHeader: some View {
        ZStack {
            LinearGradient(
                colors: [RinkPalette.midnight, RinkPalette.midnight.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            PaywallBarBackdrop()
                .opacity(0.16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 70, height: 70)
                    Image(systemName: trigger.icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("STATSCOUT+")
                    .font(RinkType.micro)
                    .foregroundStyle(.white.opacity(0.65))

                Text(trigger.title)
                    .font(RinkType.playerName)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                Text(trigger.subtitle)
                    .font(RinkType.small)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                    .padding(.horizontal, 22)
            }
            .padding(.top, 64)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(trigger.features, id: \.title) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RinkPalette.turf)
                        .frame(width: 26)
                    Text(feature.title)
                        .font(RinkType.body)
                        .foregroundStyle(RinkPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Reassurance + real credibility, MoneyPuck's expected goals model is the source
    // of truth for these percentiles, which is the actual moat. No fabricated ratings
    // or user counts.
    private var trustRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("MoneyPuck expected goals")
                    .font(RinkType.smallBold)
            }
            Text("·")
                .font(RinkType.smallBold)
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Cancel anytime")
                    .font(RinkType.smallBold)
            }
        }
        .foregroundStyle(RinkPalette.inkTertiary)
        .frame(maxWidth: .infinity)
    }

    private var planCards: some View {
        VStack(spacing: 8) {
            ForEach(store.products, id: \.identifier) { package in
                PaywallPlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: store.isEligibleForIntroOffer(package),
                    isMostPopular: package.productKind == .yearly,
                    savingsPercent: package.productKind == .yearly
                        ? store.yearlySavingsPercent(yearly: package)
                        : nil,
                    perMonthLabel: package.productKind == .yearly
                        ? package.monthlyEquivalentLabel
                        : nil,
                    monthlyAnchorLabel: package.productKind == .yearly
                        ? store.monthlyAnchorPriceLabel
                        : nil
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            Button(action: startPurchase) {
                ZStack {
                    Text(ctaTitle)
                        .font(RinkType.bodyBold)
                        .foregroundStyle(.white)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(RinkPalette.turf)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPackage == nil)

            if let disclosure = disclosureText {
                Text(disclosure)
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.turf)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: startRestore) {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(RinkType.smallBold)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)

            HStack(spacing: 12) {
                Link("Terms", destination: StatScoutLegal.termsURL)
                Link("Privacy", destination: StatScoutLegal.privacyURL)
            }
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismissOnce() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Spacer()
        }
    }

    // MARK: - Copy

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        return store.planPickerCTALabel(for: package)
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button. Shared with every
    /// one-tap CTA in the app, so the plan picker and the pop-ups state the same
    /// terms for the same plan.
    private var disclosureText: String? {
        selectedPackage.map { store.disclosureText(for: $0, emphasis: .billedAmountFirst) }
    }

    // MARK: - Actions

    private func selectDefaultPackageIfNeeded() {
        #if DEBUG
        if let mode = PaywallScreenshotMode.current, !store.products.isEmpty {
            switch mode {
            case .monthly:
                selectedPackage = store.products.first { $0.productKind == .monthly }
            case .lifetime:
                selectedPackage = store.products.first { $0.productKind == .lifetime }
            case .yearly, .trial, .onboarding:
                selectedPackage = store.products.first { $0.productKind == .yearly }
            }
            return
        }
        #endif
        guard selectedPackage == nil, !store.products.isEmpty else { return }
        selectedPackage = store.products.first { $0.productKind == .yearly }
            ?? store.products.first
    }

    private func startPurchase() {
        guard let package = selectedPackage else { return }
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(package) {
                case .purchased:
                    break
                case .pending:
                    // Ask-to-Buy / deferred payment: nothing is unlocked yet and
                    // no error occurred - tell the user instead of going silent.
                    restoreMessage = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
                case .cancelled:
                    errorMessage = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                errorMessage = store.lastError ?? "Couldn't complete the purchase. Please try again."
            }
        }
    }

    private func startRestore() {
        errorMessage = nil
        restoreMessage = nil
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await store.restorePurchases()
            if !store.isPro {
                restoreMessage = store.lastError ?? "No active StatScout+ purchase was found for this Apple ID."
            }
        }
    }

    private func dismissOnce() {
        guard !hasDismissed else { return }
        hasDismissed = true
        dismiss()
    }
}

/// Faint percentile-bar motif behind the hero - ties the paywall to the
/// app's advanced-stats leaderboard visual language without competing with the copy.
private struct PaywallBarBackdrop: View {
    private let percentiles: [Int] = [94, 81, 67, 52, 38, 88, 73, 60, 45, 83, 70]

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(percentiles.enumerated()), id: \.offset) { _, pct in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 13, height: CGFloat(pct) * 1.05)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

private struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let showsTrialBadge: Bool
    let isMostPopular: Bool
    /// Integer savings vs. 12× monthly (yearly only) - drives the SAVE X% chip.
    let savingsPercent: Int?
    /// Per-month breakdown for an annual plan, e.g. "$2.50".
    let perMonthLabel: String?
    /// Strike-through monthly anchor, e.g. "$4.99/mo".
    let monthlyAnchorLabel: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? RinkPalette.turf : RinkPalette.hairline, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(RinkPalette.turf)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.displayName)
                            .font(RinkType.bodyBold)
                            .foregroundStyle(RinkPalette.ink)
                        if let savingsPercent {
                            Text("SAVE \(savingsPercent)%")
                                .font(RinkType.micro)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RinkPalette.turf, in: Capsule())
                        }
                    }
                    if isMostPopular {
                        Text("Best value")
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(package.priceLabel)
                        .font(RinkType.cardTitle)
                        .foregroundStyle(RinkPalette.ink)
                    if let perMonthLabel {
                        HStack(spacing: 5) {
                            if let monthlyAnchorLabel, savingsPercent != nil {
                                Text(monthlyAnchorLabel)
                                    .font(RinkType.micro)
                                    .foregroundStyle(RinkPalette.inkTertiary)
                                    .strikethrough(true, color: RinkPalette.inkTertiary)
                            }
                            Text("\(perMonthLabel)/mo")
                                .font(RinkType.micro)
                                .foregroundStyle(RinkPalette.inkTertiary)
                        }
                    }
                    if showsTrialBadge, let trial = package.introOfferLabel {
                        Text(trial.capitalized)
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay {
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(isSelected ? RinkPalette.turf : RinkPalette.hairline, lineWidth: isSelected ? 2 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
