import SwiftUI
import RevenueCat

@main
struct StatScoutApp: App {
    private let api: (any StatcastProviding)?
    @StateObject private var store = StoreService.shared

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ResetUITestState"),
           let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        #endif
        ReviewPromptTracker.recordAppLaunch()
        ConversionDiagnostics.recordAppOpen()
        #if DEBUG
        if RevenueCatProbe.isEnabled {
            // Same entry point the real paywall screens call, so what this
            // proves is the actual path and not a parallel one.
            StoreService.shared.trackPaywallImpression(id: RevenueCatProbe.impressionID)
            if RevenueCatProbe.wantsPurchase {
                Task {
                    await StoreService.shared.fetchProducts()
                    guard let package = StoreService.shared.currentOffering?.availablePackages.first else { return }
                    _ = try? await StoreService.shared.purchase(package)
                }
            }
        }
        #endif
        #if DEBUG
        if ScreenshotFixtureAPI.isEnabled {
            ScreenshotFixtureAPI.prepareUserDefaults()
            self.api = ScreenshotFixtureAPI()
            StoreService.shared.start()
            return
        }
        #endif
        guard let urlString = Self.configValue(for: "SUPABASE_URL"),
              let url = URL(string: urlString),
              let key = Self.configValue(for: "SUPABASE_ANON_KEY") else {
            #if targetEnvironment(simulator)
            self.api = OfflineStatcastAPI()
            StoreService.shared.start()
            return
            #else
            self.api = nil
            return
            #endif
        }
        self.api = StatcastAPI(baseURL: url, apiKey: key)
        StoreService.shared.start()
    }

    private static func configValue(for key: String) -> String? {
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !plistValue.isEmpty,
           !plistValue.hasPrefix("$(") {
            return plistValue
        }
        return ProcessInfo.processInfo.environment[key]
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let mode = PaywallScreenshotMode.current {
                PaywallScreenshotHarness(mode: mode)
                    .environmentObject(store)
                    .preferredColorScheme(.light)
            } else if let api {
                ContentView(api: api)
                    .environmentObject(store)
                    .preferredColorScheme(.light)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        Task { await store.updateCustomerProductStatus() }
                    }
            } else {
                ConfigMissingView()
                    .preferredColorScheme(.light)
            }
            #else
            if let api {
                ContentView(api: api)
                    .environmentObject(store)
                    .preferredColorScheme(.light)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        Task { await store.updateCustomerProductStatus() }
                    }
            } else {
                ConfigMissingView()
                    .preferredColorScheme(.light)
            }
            #endif
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService

    @State private var viewModel: DashboardViewModel

    init(api: any StatcastProviding) {
        let cache: PlayerCaching?
        #if DEBUG
        cache = ScreenshotFixtureAPI.isEnabled ? nil : TwoTierPlayerCache()
        #else
        cache = TwoTierPlayerCache()
        #endif
        _viewModel = State(initialValue: DashboardViewModel(provider: api, cache: cache))
    }

    var body: some View {
        ZStack {
            RootTabView(viewModel: viewModel)
                .disabled(!hasCompletedOnboarding)
                .allowsHitTesting(hasCompletedOnboarding)

            if !hasCompletedOnboarding {
                OnboardingCards(viewModel: viewModel, hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .task(id: store.isPro) {
            guard store.isPro else { return }
            await viewModel.loadHistoricalIfNeeded()
        }
        .onAppear { viewModel.applyProState(store.isPro) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshOnForeground() }
        }
        // Foreground checks alone left an open app on Saturday's numbers all
        // Sunday. While the app is active, ask the status endpoint every two
        // minutes (one tiny row, throttled inside) and reload when a new
        // revision is published, so percentiles and boards update in place.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                await viewModel.refreshOnForeground()
            }
        }
        .onChange(of: store.isPro) { _, isPro in
            viewModel.applyProState(isPro)
        }
    }
}

struct BulletItem: Identifiable {
    let id = UUID()
    let text: String
    let icon: String
    let color: Color
}

struct OnboardingCards: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var paywallTrigger: PaywallTrigger?
    @State private var isStartingTrial = false
    @State private var trialError: String?
    @State private var isRestoring = false

    private var isLastPage: Bool { currentPage == pages.count - 1 }
    private var dataReady: Bool { viewModel.isReady }
    private var showsUpsellBlock: Bool { isLastPage && !store.isPro }

    /// The label on the onboarding CTA and the disclosure above it are one
    /// decision, not two.
    ///
    /// This button transacts: tapping it puts Apple's confirm sheet on screen
    /// and charges the monthly plan. So it may only read as a purchase when
    /// there is a loaded package to name a price from, and the full auto-renew
    /// terms have to be on screen with it. Deriving both from the same optional
    /// is what stops them drifting apart, which is how this shipped wrong once:
    /// a hard-coded "Continue with StatScout+" over a disclosure that is nil
    /// until products load is a paid button with no price anywhere near it.
    ///
    /// The billed amount leads here too, so every transactional surface follows
    /// the same App Store pricing hierarchy.
    private var monthlyOffer: (label: String, disclosure: String)? {
        guard store.monthlyPackage != nil,
              let disclosure = store.onboardingMonthlyDisclosureText else { return nil }
        return (store.onboardingMonthlyCTALabel, disclosure)
    }

    /// Falls back to a label that promises nothing, because with no package
    /// there is no price to state - and `buyMonthly` sends that tap to the plan
    /// picker rather than to a purchase.
    private var proCTALabel: String {
        monthlyOffer?.label ?? "Upgrade to StatScout+"
    }

    private var trialDisclosure: String? {
        monthlyOffer?.disclosure
    }

    var body: some View {
        ZStack {
            RinkPalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        withAnimation { hasCompletedOnboarding = true }
                    }
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.turf)
                    .padding(.trailing, 20)
                    .opacity(isLastPage ? 0 : 1)
                    .allowsHitTesting(!isLastPage)
                }
                .frame(height: 32)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingCard(
                            icon: page.icon,
                            title: page.title,
                            description: page.description,
                            bullets: page.bullets
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: 700)
        }
        .task {
            if store.currentOffering == nil {
                await store.fetchProducts()
            }
        }
        #if DEBUG
        // Screenshot harness: open on the page that carries the purchase CTA,
        // so the label and its disclosure can be captured without swiping a
        // carousel the runner cannot reliably drive.
        .onAppear {
            if PaywallScreenshotMode.current == .onboarding {
                currentPage = pages.count - 1
            }
        }
        #endif
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro {
                paywallTrigger = nil
                withAnimation { hasCompletedOnboarding = true }
            }
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        // Layout invariant: the primary button and the 24pt footer slot are the
        // ONLY things below the top of this stack that set the button's Y. The
        // button + footer slot are IDENTICAL on every page (Continue and the
        // trial CTA are both a 52pt turf button with the same 24pt slot
        // beneath), and everything else (Get Started, status line, disclosure,
        // Terms/Privacy) lives ABOVE the button where it grows upward. Because
        // the stack is bottom-anchored, that upper content can never move the
        // button, so the primary button is pixel-identical across all pages and
        // the thumb target never shifts between taps.
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                getStartedButton(prominent: false)

                // Reserved fixed-height status line: a restore/purchase result
                // fills this slot in place instead of being inserted, so nothing
                // above the button shifts either.
                Text(trialError ?? " ")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.performanceLow)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32, alignment: .top)

                if let disclosure = trialDisclosure {
                    Text(disclosure)
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Terms/Privacy sit just above the purchase point (this CTA can
                // buy the trial directly, no PaywallView handoff).
                HStack(spacing: 12) {
                    Link("Terms", destination: StatScoutLegal.termsURL)
                    Link("Privacy", destination: StatScoutLegal.privacyURL)
                }
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
            }
            .opacity(showsUpsellBlock ? 1 : 0)
            .allowsHitTesting(showsUpsellBlock)
            .accessibilityHidden(!showsUpsellBlock)

            // --- Primary button: identical 52pt turf slot on every page ---
            if isLastPage {
                if store.isPro {
                    getStartedButton(prominent: true)
                } else {
                    Button {
                        buyMonthly()
                    } label: {
                        ZStack {
                            Text(proCTALabel)
                                .opacity(isStartingTrial ? 0 : 1)
                            if isStartingTrial {
                                ProgressView().tint(.white)
                            }
                        }
                        .font(RinkType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RinkPalette.turf)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingTrial)
                }
            } else {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Continue")
                        .font(RinkType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RinkPalette.turf)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            // --- Fixed 24pt footer slot BELOW the button, identical every page.
            // On the last page it carries Restore (or the loading state); on the
            // others it is empty. Its constant height is what keeps the button's
            // bottom edge, and therefore its Y, pinned across pages.
            Group {
                if isLastPage, !dataReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(RinkPalette.inkSecondary)
                            .scaleEffect(0.7)
                        Text(viewModel.loadingMessage)
                            .font(RinkType.micro)
                    }
                    .foregroundStyle(RinkPalette.inkSecondary)
                } else if isLastPage && !store.isPro {
                    Button {
                        // Surface the outcome through the same trialError line the
                        // purchase CTA uses, a restore that silently does nothing
                        // reads as a dead button. Success flips isPro, which
                        // finishes onboarding via onChange.
                        isRestoring = true
                        Task { @MainActor in
                            defer { isRestoring = false }
                            await store.restorePurchases()
                            if !store.isPro {
                                trialError = store.lastError ?? "No active StatScout+ purchase was found for this Apple ID."
                            }
                        }
                    } label: {
                        Text(isRestoring ? "Restoring…" : "Restore Purchases")
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)
                } else {
                    Color.clear
                }
            }
            .frame(height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    /// "Get Started" dismisses onboarding into the free tier. `prominent` is the
    /// solo state (Pro users, where it's the only, and primary, action, a filled
    /// button); otherwise it's a de-emphasized, borderless text link that sits
    /// above the turf trial CTA so it never competes for the tap.
    private func getStartedButton(prominent: Bool) -> some View {
        Button {
            withAnimation { hasCompletedOnboarding = true }
        } label: {
            if prominent {
                Text("Get Started")
                    .font(RinkType.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RinkPalette.turf)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                // Borderless free-tier exit: same text as the boxed version,
                // just no box. Keeps it legible and compliant (the free path
                // must stay clearly visible) while the turf trial button is the
                // prominent action.
                Text("Get Started")
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
        }
        .buttonStyle(.plain)
    }

    // One-tap conversion: buy the monthly plan in place, trial when eligible,
    // straight purchase otherwise, never a second paywall. PaywallView is only
    // the emergency fallback when products didn't load. Success flips
    // store.isPro, which finishes onboarding via the onChange handler.
    private func buyMonthly() {
        guard let monthly = store.monthlyPackage else {
            paywallTrigger = .onboarding
            return
        }
        trialError = nil
        isStartingTrial = true
        Task { @MainActor in
            defer { isStartingTrial = false }
            do {
                switch try await store.purchase(monthly) {
                case .purchased:
                    break
                case .pending:
                    // Ask-to-Buy / deferred payment: onboarding stays up because
                    // isPro hasn't flipped, explain instead of appearing dead.
                    trialError = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
                case .cancelled:
                    trialError = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                trialError = store.lastError ?? "Couldn't complete the purchase. Please try again."
            }
        }
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "hockey.puck.fill",
            title: "Your Pocket\nScout",
            description: "NHL percentile rankings built for a fast mobile view. Every skater and goalie, every metric, updated after every night's games.",
            bullets: [
                BulletItem(text: "Every player ranked from opening night", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "ixG, GAx, xGF%, GSAx, and more", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "Fresh stats soon after every game", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "No account or sign-up", icon: "checkmark.circle.fill", color: RinkPalette.turf)
            ]
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Find Insights\nFast",
            description: "Scores, leaders and movement across the league in seconds, with the numbers behind every game.",
            bullets: [
                BulletItem(text: "Games: scores and box scores", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "Stats: leaders, best and worst", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "Trends: heating up, cooling off", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "Teams: any roster, any season", icon: "checkmark.circle.fill", color: RinkPalette.turf),
                BulletItem(text: "Compare: two players side by side", icon: "checkmark.circle.fill", color: RinkPalette.turf)
            ]
        ),
        OnboardingPage(
            icon: "crown.fill",
            title: "Go Deeper\nwith StatScout+",
            description: "Season numbers tell you who's good. StatScout+ tells you who's good right now, and lets you prove it.",
            bullets: [
                BulletItem(text: "Trends: the league ranked by form", icon: "flame.fill", color: RinkPalette.turf),
                BulletItem(text: "Last 2 / 4 / 8 weeks, any player", icon: "chart.bar.fill", color: RinkPalette.turf),
                BulletItem(text: "Head-to-head on every percentile", icon: "person.2.fill", color: RinkPalette.turf),
                BulletItem(text: "Seasons back to 2008-09, year over year", icon: "calendar.badge.clock", color: RinkPalette.turf)
            ]
        )
    ]
}

struct OnboardingCard: View {
    let icon: String
    let title: String
    let description: String
    let bullets: [BulletItem]

    /// Sized to fit the shortest page slot, which is the last one.
    ///
    /// A `TabView` page gets whatever height is left over, and on the StatScout+
    /// page the block below it is enormous - CTA, price disclosure paragraph,
    /// Terms/Privacy, purchase button, status line, about 440pt of it. The card
    /// wanted more than the ~370pt that leaves, so SwiftUI compressed it: every
    /// one of the four benefit bullets collapsed to a single truncated line
    /// ("The Trends board: the league ranked by…") and the page-index dots landed
    /// on top of the fourth. The one screen whose entire job is to say what
    /// StatScout+ is could not say any of it.
    ///
    /// So the art is smaller, the rhythm is tighter, the bullets are short enough
    /// to set on one line at the default text size, and they wrap rather than
    /// truncate if a larger one pushes them over. Losing 20pt of illustration is
    /// nothing next to losing the copy.
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ZStack {
                StatcastBarBackdrop()
                    .frame(width: 200, height: 104)
                ZStack {
                    Circle()
                        .fill(RinkPalette.midnight)
                        .frame(width: 84, height: 84)
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: RinkPalette.midnight.opacity(0.25), radius: 12, y: 4)
            }

            Text(title)
                .font(RinkType.playerName)
                .foregroundStyle(RinkPalette.ink)
                .multilineTextAlignment(.center)

            Text(description)
                .font(RinkType.body)
                .foregroundStyle(RinkPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(bullets) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: bullet.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(bullet.color)
                        Text(bullet.text)
                            .font(RinkType.body)
                            .foregroundStyle(RinkPalette.ink)
                            // Wrap, never truncate. A benefit that ends in an
                            // ellipsis is worse than one set on two lines.
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            // Clears the page-index dots, which the `TabView` draws inside its
            // own bottom edge and so on top of whatever the card put there.
            .padding(.bottom, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let bullets: [BulletItem]
}

private struct StatcastBarBackdrop: View {
    private let percentiles: [Int] = [92, 78, 65, 48, 32, 88, 71, 55, 42, 80]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(percentiles.enumerated()), id: \.offset) { _, pct in
                RoundedRectangle(cornerRadius: 3)
                    .fill(RinkPalette.color(forPercentile: pct).opacity(0.55))
                    .frame(width: 14, height: CGFloat(pct) * 1.1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

struct ConfigMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(RinkPalette.turf)
            Text("StatScout can't load")
                .font(RinkType.playerName)
                .foregroundStyle(RinkPalette.ink)
            Text("This build is missing its data-feed configuration. Please install the latest TestFlight build or contact support.")
                .font(RinkType.body)
                .foregroundStyle(RinkPalette.inkSecondary)
                .multilineTextAlignment(.center)
            if let supportURL = URL(string: "https://jackwallner.github.io/hockey/support.html") {
                Link("Contact Support", destination: supportURL)
                    .buttonStyle(.borderedProminent)
                    .tint(RinkPalette.turf)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RinkPalette.canvas.ignoresSafeArea())
    }
}
