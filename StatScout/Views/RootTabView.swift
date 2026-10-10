import StoreKit
import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct MetricRoute: Hashable {
    let label: String
    let category: MetricCategory
    /// Which season's leaderboard to open. The player profile has its own
    /// season selector, so a route from a 2022 profile has to carry 2022,
    /// otherwise tapping Cmp% there opened the current-season leaderboard.
    var season: Int? = nil
    /// Which half of that year. A profile is scoped to the phase you arrived
    /// from and its season selector never crosses one, so a route from a
    /// playoff profile has to carry `.postseason`: the season alone resolved
    /// against whatever the tab's phase happened to be, which landed a playoff
    /// drill-down on the regular-season board under a playoff heading.
    var phase: SeasonPhase? = nil
}

/// Drill-down from a traditional stat row to its league leaderboard.
struct StandardStatRoute: Hashable {
    let stat: String
    let position: PlayerPositionGroup
    var season: Int? = nil
    /// See `MetricRoute.phase`.
    var phase: SeasonPhase? = nil
}

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService
    @Environment(\.requestReview) private var requestReview
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var viewModel: DashboardViewModel
    @State private var selection = 0
    @State private var showReviewPrompt = false
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false
    @State private var pendingNativeReviewAfterDismiss = false
    // Owned here so TeamsView can auto-push the favorite team and the user can
    // still pop back to the list.
    @State private var teamsPath = NavigationPath()

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        tabView
            .tint(RinkPalette.turf)
            .sheet(isPresented: $showReviewPrompt, onDismiss: {
            // "Maybe later" already recorded a soft defer; calling markShown
            // here would clear it and apply the full 120-day cooldown to a
            // user who most likely never saw Apple's prompt at all.
            if pendingNativeReviewAfterDismiss {
                pendingNativeReviewAfterDismiss = false
                ReviewPromptTracker.markSoftDeferred()
                requestReview()
            } else if !ReviewPromptTracker.isSoftDeferred {
                ReviewPromptTracker.markShown()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptInitialStep, onFinish: handleReviewPromptFinish)
        }
        .onReceive(NotificationCenter.default.publisher(for: .statscoutPositiveMomentForReview)) { _ in
            scheduleReviewPromptAfterPositiveMoment()
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            guard !showReviewPrompt else { return }
            switch presentation {
            case .enjoymentPrompt:
                presentReviewPrompt(step: .enjoyment)
            case .feedbackOnly:
                presentReviewPrompt(step: .feedback)
            }
        }
    }

    private func scheduleReviewPromptAfterPositiveMoment() {
        guard ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding),
              !reviewPromptShownThisSession,
              !showReviewPrompt
        else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !showReviewPrompt,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding)
            else { return }
            ReviewPromptTracker.consumePendingPositiveMoment()
            reviewPromptInitialStep = .enjoyment
            reviewPromptShownThisSession = true
            showReviewPrompt = true
        }
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        showReviewPrompt = false
        if outcome == .enjoyedMaybeLater {
            pendingNativeReviewAfterDismiss = true
        }
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    /// Hand-rolled tab bar rather than a `TabView`.
    ///
    /// On iOS 26 a `TabView` always draws its own Liquid Glass platter, and
    /// `.toolbarBackground(.hidden, for: .tabBar)` is a no-op against it, which
    /// is what made the bar read as a grey box sitting on the canvas. Owning the
    /// bar means there is no system background to fight.
    ///
    /// Tabs live in a `ZStack` and toggle visibility rather than being swapped,
    /// so each one's navigation stack and scroll position survive switching
    /// away and back. Inactive tabs are hidden from VoiceOver too: at
    /// `opacity(0)` they are still perfectly reachable via the rotor.
    private var tabView: some View {
        ZStack(alignment: .bottom) {
            ForEach(Tab.allCases) { tab in
                tabContent(tab)
                    .frame(maxWidth: 900, maxHeight: .infinity)
                    .opacity(selection == tab.rawValue ? 1 : 0)
                    .allowsHitTesting(selection == tab.rawValue)
                    .accessibilityHidden(selection != tab.rawValue)
            }

            floatingTabBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RinkPalette.canvas.ignoresSafeArea())
        .ignoresSafeArea(edges: .bottom)
        #if DEBUG
        .onAppear {
            if let tab = Tab.launchArgument { selection = tab.rawValue }
        }
        #endif
    }

    private enum Tab: Int, CaseIterable, Identifiable {
        case stats, games, trends, teams, compare

        var id: Int { rawValue }

        #if DEBUG
        /// Launch with `-StartTab trends|teams|compare` to open straight on a
        /// tab. The Pro gates live two and four tabs in, and the UI-test runner
        /// cannot reliably drive this app to them on the shared simulator pool
        /// (it reports the app as not running while a plain `simctl launch` of
        /// the same build is perfectly healthy). Screenshotting a gate is the
        /// only way to see its price copy, so the way in has to not depend on
        /// synthesised taps. Compiled out of Release.
        static var launchArgument: Tab? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-StartTab"),
                  index + 1 < arguments.count else { return nil }
            return allCases.first { $0.title.lowercased() == arguments[index + 1].lowercased() }
        }
        #endif

        var title: String {
            switch self {
            case .games: return "Games"
            case .stats: return "Stats"
            case .trends: return "Trends"
            case .teams: return "Teams"
            case .compare: return "Compare"
            }
        }

        var icon: String {
            switch self {
            case .games: return "hockey.puck.fill"
            case .stats: return "chart.bar.fill"
            case .trends: return "flame.fill"
            case .teams: return "shield.lefthalf.filled"
            case .compare: return "arrow.left.arrow.right"
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .games: gamesTab
        case .stats: statsTab
        case .trends: trendsTab
        case .teams: teamsTab
        case .compare: compareTab
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                TabBarButton(
                    icon: tab.icon,
                    label: tab.title,
                    isSelected: selection == tab.rawValue
                ) {
                    guard selection != tab.rawValue else { return }
                    selection = tab.rawValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Near-opaque: the old 0.8 ultra-thin material let the two rows
        // under it read through and collide with the tab labels on every
        // board. It still floats; it just no longer shares its pixels.
        .background {
            Capsule().fill(.regularMaterial)
            Capsule().fill(RinkPalette.surface.opacity(0.9))
        }
        .overlay(Capsule().stroke(RinkPalette.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.bottom, 12)
    }

    private var gamesTab: some View {
        NavigationStack {
            GamesView(
                viewModel: viewModel,
                isActive: selection == Tab.games.rawValue
            )
                .navigationTitle("Games · \(SeasonLabel.display(viewModel.freeSeason))")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(RinkNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var statsTab: some View {
        NavigationStack {
            StatsView(viewModel: viewModel)
                // Title and season pills come from SeasonPhaseNavBar.
                .modifier(RinkNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var trendsTab: some View {
        NavigationStack {
            HotColdView(
                viewModel: viewModel,
                isActive: selection == Tab.trends.rawValue
            )
                // Title and season pills come from SeasonPhaseNavBar.
                .modifier(RinkNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack(path: $teamsPath) {
            TeamsView(viewModel: viewModel, path: $teamsPath)
                // Title and season pills come from SeasonPhaseNavBar.
                .modifier(RinkNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var compareTab: some View {
        NavigationStack {
            // CompareView pushes its own comparisons with item-based
            // destinations, which never collide with the type-based ones in
            // StandardDestinations. The full set is needed because a profile
            // opened here links onward to metric, stat, team and game pages.
            CompareView(
                viewModel: viewModel,
                isActive: selection == Tab.compare.rawValue
            )
                .navigationTitle("Compare")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(RinkNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

}

/// One item in the hand-rolled floating tab bar. The selected pill uses the
/// turf green at low opacity rather than a filled capsule so the bar stays
/// light over whatever content scrolls beneath it.
private struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    // Symbols differ in height; a fixed slot keeps the five
                    // labels on one baseline.
                    .frame(height: 24)
                Text(label)
                    .font(RinkType.smallBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? RinkPalette.turf : RinkPalette.inkSecondary)
            .frame(width: 68, height: 52)
            .background(
                isSelected ? RinkPalette.turf.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

private struct RinkNavBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(RinkPalette.midnight, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Trailing toolbar group shared by the four home tabs: a settings gear, then
/// the upgrade CTA when the user isn't subscribed.
///
/// The gear is the only entry point to Settings that isn't buried; it used to
/// live only in a link under the bottom of the leaderboard, which nobody
/// scrolls to. Trailing rather than leading because Stats already owns the
/// leading slot with its season pill, and a control that moves between tabs
/// isn't an anchor.
private struct HomeTabToolbar: ViewModifier {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    var dataCoverage: DataCoverage?
    /// Owned per tab, not shared. All four tabs stay alive in the ZStack, so a
    /// single shared flag would push Settings onto all four stacks at once.
    @State private var showingSettings = false
    @State private var paywallTrigger: PaywallTrigger?

    /// Yellow crown + short action verb on a filled pill. The old version was
    /// a bare yellow "Pro" label that read as a status badge rather than a
    /// button, tap-through rates were correspondingly weak. The verb makes
    /// the CTA unambiguous, and the trial-aware label appears when an intro
    /// offer is available.
    private var ctaLabel: String { store.upgradeCTALabel }

    private var upgradeButton: some View {
        Button {
            paywallTrigger = store.defaultUpgradeTrigger
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(ctaLabel)
                    .font(RinkType.micro)
                    .fontWeight(.bold)
            }
            .foregroundStyle(RinkPalette.midnight)
            // Tight, because the season pill next to it now spells out
            // "Regular Season" and the bar has no slack left. Trimming padding
            // here is far cheaper than losing the verb: a bare crown reads as a
            // status badge, which is exactly what this button used to be and
            // why it was rewritten.
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.yellow)
            .clipShape(Capsule())
            .fixedSize()
        }
        .accessibilityLabel("\(ctaLabel), unlock all features")
    }

    /// Outline cog, no filled circle behind it. The Liquid Glass container
    /// gave it a pale disc that made a secondary control louder than the
    /// content it sits above.
    private var settingsButton: some View {
        Button {
            showingSettings = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
        .accessibilityLabel("Settings")
    }

    /// Gear then CTA, in the order they were declared as separate items.
    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 10) {
            settingsButton
            if !store.isPro {
                upgradeButton
            }
        }
    }

    func body(content: Content) -> some View {
        content
            // A push rather than a bottom sheet: Settings is a place in the
            // app, not a modal interruption over what you were reading.
            .navigationDestination(isPresented: $showingSettings) {
                AboutView(
                    lastUpdated: lastUpdated,
                    dataCoverage: dataCoverage,
                    onRequestReview: {
                        showingSettings = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                        }
                    }
                )
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(RinkNavBar())
            }
            .toolbar {
                // One trailing item holding both controls, not two items.
                //
                // Two separate `ToolbarItem`s are a group iOS may collapse into
                // a "..." overflow, and it decides that from its own layout
                // arithmetic rather than from the space actually free: widening
                // the season pill to spell out "Regular Season" tipped it, and
                // the CTA vanished into the menu with a hundred and twenty
                // points of empty bar still sitting between the pill and the
                // gear. Trimming the pill did not bring it back, because width
                // was never really the trigger.
                //
                // A single item cannot be split, so both stay visible and the
                // spacing between them is ours. Same reasoning as the leading
                // pill above.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { trailingControls }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { trailingControls }
                }
            }
            // The one place that opens the full plan picker. Every other pitch
            // in the app interrupts something the user reached for, so it stays
            // a half sheet; this pill is the user going looking for the offer,
            // and someone who taps it wants to see what the plans cost.
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
    }
}

/// The player-profile, game and schedule routes, the part of
/// `StandardDestinations` every stack that shows a player or a game needs.
struct PlayerProfileDestination: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Player.self) { player in
                let history = viewModel.playerHistories[player.playerId] ?? []
                let seasonPlayer = history.first {
                    $0.season == player.season
                        && $0.seasonPhase == player.seasonPhase
                } ?? player
                let profileSeason = seasonPlayer.season ?? viewModel.selectedSeason
                let profilePhase = seasonPlayer.seasonPhase
                PlayerProfileView(
                    player: seasonPlayer,
                    history: history,
                    allPlayers: viewModel.players(
                        forSeason: profileSeason,
                        phase: profilePhase
                    ),
                    currentSeason: viewModel.freeSeason,
                    recentFormSeasons: viewModel.recentFormSeasons,
                    isHistoricalLoading: viewModel.isHistoricalLoading,
                    hasLoadedHistorical: viewModel.hasLoadedHistorical,
                    historicalLoadingMessage: viewModel.loadingMessage,
                    historicalLoadingProgress: viewModel.loadingProgress,
                    loadHistorical: { await viewModel.loadHistoricalIfNeeded() },
                    fetchGameLogs: { id, season, phase in
                        try await viewModel.fetchGameLogs(
                            playerId: id,
                            season: season,
                            seasonPhase: phase
                        )
                    },
                    freshnessViewModel: viewModel,
                    comparisonCatalog: ComparisonCatalog(
                        viewModel: viewModel,
                        defaultPhase: profilePhase
                    )
                )
                    .modifier(RinkNavBar())
            }
            .navigationDestination(for: GameRoute.self) { route in
                GameDetailView(viewModel: viewModel, gameId: route.gameId)
                    .modifier(RinkNavBar())
            }
            .navigationDestination(for: TeamScheduleRoute.self) { route in
                TeamScheduleView(viewModel: viewModel, team: route.team)
                    .modifier(RinkNavBar())
            }
    }
}

private struct StandardDestinations: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .modifier(PlayerProfileDestination(viewModel: viewModel))
            .navigationDestination(for: TeamDestination.self) { dest in
                TeamView(
                    team: dest.abbr,
                    viewModel: viewModel,
                    fetchTeamGameLogs: { team, season, phase, since in
                        try await viewModel.fetchTeamGameLogs(
                            team: team,
                            season: season,
                            seasonPhase: phase,
                            sinceDate: since
                        )
                    }
                )
                    .modifier(RinkNavBar())
            }
            .navigationDestination(for: MetricRoute.self) { route in
                let season = route.season ?? viewModel.selectedSeason
                let phase = route.phase ?? viewModel.selectedPhase
                MetricRankingView(
                    metricLabel: route.label,
                    metricCategory: route.category,
                    players: viewModel.players(forSeason: season, phase: phase),
                    season: season,
                    viewModel: viewModel
                )
                    .modifier(RinkNavBar())
            }
            .navigationDestination(for: StandardStatRoute.self) { route in
                let season = route.season ?? viewModel.selectedSeason
                let phase = route.phase ?? viewModel.selectedPhase
                StandardStatsLeaderboardScreen(
                    players: viewModel.players(forSeason: season, phase: phase),
                    initialStat: route.stat,
                    initialPosition: route.position,
                    season: season
                )
                    // The phase only earns title space when it isn't the
                    // default: an inline title is tight, and "P · 2024-25
                    // regular season" sweeps into a truncation that "P ·
                    // 2024-25 playoffs" is worth paying for.
                    .navigationTitle(
                        route.stat + " · " + (phase == .regular
                            ? SeasonLabel.display(season)
                            : SeasonLabel.display(season, phase: phase))
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(RinkNavBar())
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                PlayerComparisonView(
                    playerA: route.playerA,
                    playerB: route.playerB,
                    catalog: ComparisonCatalog(
                        viewModel: viewModel,
                        defaultPhase: route.playerA.seasonPhase
                    )
                )
                    .modifier(RinkNavBar())
            }
    }
}
