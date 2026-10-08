import SwiftUI

struct PlayerProfileView: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let history: [Player]
    var allPlayers: [Player] = []
    /// The live season as the loaded data sees it, not as the calendar does.
    /// Drives the free-tier lock on the season menu and whether Recent form is
    /// offered at all, both of which have to agree with the rest of the app
    /// once a new season is named but hasn't been ingested yet.
    var currentSeason: Int = StatScoutSeason.current
    /// Seasons Recent form is offered for, from
    /// `DashboardViewModel.recentFormSeasons`. Nil means "just `currentSeason`",
    /// which is the previews-and-tests path.
    var recentFormSeasons: [Int]?
    var isHistoricalLoading = false
    var hasLoadedHistorical = true
    var historicalLoadingMessage = "Loading past seasons…"
    var historicalLoadingProgress = 0.12
    var loadHistorical: (() async -> Void)?
    /// This player's own per-game rows. Both recent-form cards on this page read
    /// them; the league's pre-aggregated week rollup is deliberately not wired
    /// in here, because a page about one player should count his games, not the
    /// league's weeks. See `standardRecentKeys`.
    /// (playerId, season, phase). The phase is part of the request, not a
    /// post-filter: see `PlayerGameLog.seasonPhase`.
    var fetchGameLogs: ((Int, Int, SeasonPhase) async throws -> [PlayerGameLog])?
    /// Shared freshness state from the tab root. Optional keeps previews and
    /// standalone tests lightweight while production profiles share one cache
    /// revision with Trends and Teams.
    var freshnessViewModel: DashboardViewModel? = nil
    var comparisonCatalog: ComparisonCatalog?
    @State private var showPercentileInfo = false
    @State private var selectedTab: PlayerStatTab = .advanced
    @State private var selectedPercentileSeason: Int? = nil
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingPlayerPicker = false
    @State private var comparisonRoute: ComparisonRoute?
    // Contextual trial pitches (compare, recent form, year compare, first-open)
    // all route through the low-friction TrialPitchSheet - its CTA starts the
    // yearly trial directly. PaywallView stays for the deliberate upsell card.
    @State private var trialPitchTrigger: PaywallTrigger?
    @State private var formDisplayMode: FormDisplayMode = .season
    @State private var recentWindowGames: Int = 5
    @State private var recentLogs: [PlayerGameLog] = []
    /// "<playerId>-<season>" the loaded logs belong to, so two cards asking for
    /// the same season share one fetch.
    @State private var recentLogsKey: String?
    @State private var recentLoading = false
    @State private var recentLoadingKey: String?
    @State private var recentLoadError: String?
    @State private var recentCurves: LeaguePercentileCurves?
    @State private var standardMode: FormDisplayMode = .season
    @State private var standardWindow: RecentWindow = .five
    @State private var favorites = FavoritesStore.shared

    private let profileOpenCountKey = "profileOpenCount"

    enum FormDisplayMode: String, CaseIterable {
        case season = "Season"
        case recent = "Recent"
        case both = "Both"
    }

    enum PlayerStatTab: String, CaseIterable {
        case advanced = "Advanced"
        case standard = "Standard"
        case yearCompare = "Year Compare"
    }

    private var availablePercentileSeasons: [Int] {
        let fromHistory = phaseHistory.compactMap(\.season)
        var set = Set(fromHistory)
        if let s = player.season { set.insert(s) }
        return Array(set).sorted(by: >)
    }

    private var activeSeason: Int? {
        selectedPercentileSeason ?? player.season
    }

    private var displayedPlayer: Player {
        guard let season = activeSeason else { return player }
        return phaseHistory.first { $0.season == season } ?? player
    }

    private var phaseHistory: [Player] {
        history.filter { $0.seasonPhase == player.seasonPhase }
    }

    /// The league cohort every percentile, curve and comparison on this page is
    /// measured against, for the season the selector is actually on.
    ///
    /// `allPlayers` is handed in once, for the season the profile was opened
    /// in. The season selector moved `displayedPlayer`'s numbers but not the
    /// field they were ranked inside, so a 2022 line was being scored against
    /// the 2026 league. Falls back to the injected array whenever there is no
    /// view model (previews and tests) or the selector hasn't moved.
    private var cohortPlayers: [Player] {
        guard let season = activeSeason,
              season != player.season,
              let freshnessViewModel
        else { return allPlayers }
        let cohort = freshnessViewModel.players(forSeason: season, phase: activePhase)
        return cohort.isEmpty ? allPlayers : cohort
    }

    /// The phase this profile is reading, for the game-log fetch and its cache
    /// key. The season selector moves within a phase, never across one.
    private var activePhase: SeasonPhase { player.seasonPhase }

    /// Season *and* phase.
    ///
    /// The profile is scoped to whichever phase you arrived from, and the two
    /// sets of numbers are wildly different - a quarterback's CPOE can be +3.2
    /// across a season and -7.9 over one playoff game, and "G" drops from
    /// seventeen to one. Every header here said only "2025", so nothing on the
    /// page told you which of the two you were reading, and the one-and-done
    /// playoff line looked like a catastrophic season.
    private var seasonLabel: String {
        guard let season = activeSeason else { return "-" }
        return SeasonLabel.text(season, phase: player.seasonPhase)
    }

    private var profileMetricKind: MetricKind {
        displayedPlayer.positionGroup == .defense ? .traditional : .advanced
    }

    private var groupedMetrics: [(family: MetricFamily, metrics: [Metric])] {
        let eligible = displayedPlayer.metrics(kind: profileMetricKind)
        let grouped = Dictionary(grouping: eligible) { metric in
            FootballMetricRegistry.definition(for: metric.label, category: metric.category)?.family ?? .production
        }
        return MetricFamily.allCases.compactMap { family in
            guard let metrics = grouped[family], !metrics.isEmpty else { return nil }
            return (family: family, metrics: FootballMetricRegistry.sorted(metrics))
        }
    }


    /// Players eligible for comparison: same position group, sorted by overall
    /// percentile proximity to the current player so the closest match is first.
    private var comparablePlayers: [Player] {
        let myType = displayedPlayer.playerType?.lowercased()
        let pool = cohortPlayers.filter { other in
            guard other.playerId != player.playerId else { return false }
            guard let myType else { return true }
            return other.playerType?.lowercased() == myType
        }
        let mine = displayedPlayer.overallPercentile
        return pool.sorted { a, b in
            abs(a.overallPercentile - mine) < abs(b.overallPercentile - mine)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // `displayedPlayer`, so a player who changed clubs wears the
                // team he actually played for in the season on screen rather
                // than the one from whichever season you opened the page in.
                PlayerIdentityStrip(
                    player: displayedPlayer,
                    profile: liveProfile,
                    injury: freshnessViewModel?.injuryReport(for: displayedPlayer)
                )

                if let freshnessViewModel {
                    DataFreshnessView(
                        viewModel: freshnessViewModel,
                        season: activeSeason ?? player.season,
                        phase: activePhase
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    if let season = activeSeason ?? player.season,
                       (recentFormSeasons ?? [currentSeason]).contains(season) {
                        PlayerLastGameCard(
                            viewModel: freshnessViewModel,
                            player: displayedPlayer,
                            season: season,
                            phase: activePhase
                        )
                        .padding(.horizontal, 12)
                    }
                }

                tabSelector
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                switch selectedTab {
                case .advanced:
                    advancedContent
                case .standard:
                    standardContent
                case .yearCompare:
                    yearCompareContent
                }

                StatGlossaryLink()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            await refreshProfile()
        }
        .background(GridironPalette.canvas.ignoresSafeArea())
        // First-tap activation: profile renders immediately (no full-screen
        // paywall blocking it), and a native half-sheet TrialPitchSheet
        // floats on top with a "Maybe later" dismiss. PaywallGate caps this
        // at 2 per session so repeat taps don't re-prompt. The old full-page
        // .activation PaywallView was removed for being too intrusive - this
        // is the Vitals-style soft pitch that replaced it.
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { compareButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                ToolbarItem(placement: .topBarTrailing) { compareButton }
            }
        }
        .sheet(isPresented: $showPercentileInfo) {
            PercentileInfoSheet()
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerSheet(players: comparablePlayers) { selected in
                comparisonRoute = ComparisonRoute(playerA: displayedPlayer, playerB: selected)
            }
        }
        .sheet(item: $trialPitchTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(
                playerA: route.playerA,
                playerB: route.playerB,
                catalog: comparisonCatalog
            )
        }
        .onAppear {
            // Defer the first-impression pitch: a user verifying one stat from a
            // group chat shouldn't hit a subscription story before scrolling a
            // single row. Show it from the *second* profile open onward (Pro-only
            // controls - Recent Form, past seasons, Compare - still pitch on tap).
            let opens = UserDefaults.standard.integer(forKey: profileOpenCountKey) + 1
            UserDefaults.standard.set(opens, forKey: profileOpenCountKey)
            if !store.isPro, opens >= 2, PaywallGate.shared.shouldPresent(.playerScouting) {
                trialPitchTrigger = .playerScouting
            } else if opens >= 3 {
                // Third+ profile visit = engaged browsing. Never on a visit that
                // just showed the pitch, or "Enjoying StatScout?" lands the
                // moment the user dismisses a subscription sheet.
                ReviewPromptTracker.recordPositiveMoment()
            }
        }
    }

    /// Following a player is free. It's the signal the Trends tab and the
    /// review funnel read from, so gating it would suppress the thing we most
    /// want people to do.
    private var favoriteButton: some View {
        let isFavorite = favorites.isFavorite(playerId: player.playerId)
        return Button {
            favorites.toggleFavorite(playerId: player.playerId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : .white)
        }
        .accessibilityLabel(isFavorite ? "Unfollow \(player.name)" : "Follow \(player.name)")
    }

    private var compareButton: some View {
        Button {
            if store.isPro {
                showingPlayerPicker = true
            } else {
                trialPitchTrigger = .playerComparison
            }
        } label: {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Compare with another player")
    }

    private var tabSelector: some View {
        HStack(spacing: 8) {
            advancedTabButton
            standardTabButton
            yearCompareTabButton
        }
    }

    private var advancedTabButton: some View {
        let isSelected = selectedTab == .advanced
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .advanced
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.advanced.rawValue)
                .font(GridironType.bodyBold)
                .foregroundStyle(isSelected ? .white : GridironPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? GridironPalette.turf : GridironPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var standardTabButton: some View {
        let isSelected = selectedTab == .standard
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .standard
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.standard.rawValue)
                .font(GridironType.bodyBold)
                .foregroundStyle(isSelected ? .white : GridironPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? GridironPalette.turf : GridironPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var yearCompareTabButton: some View {
        let isSelected = selectedTab == .yearCompare
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .yearCompare
            }
            if store.isPro, !hasLoadedHistorical, !isHistoricalLoading {
                Task { await loadHistorical?() }
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.yearCompare.rawValue)
                .font(GridironType.bodyBold)
                .foregroundStyle(isSelected ? .white : GridironPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? GridironPalette.turf : GridironPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    /// Bio, contract and snaps, for the live season's page only: a 2026
    /// contract says nothing about what a player cost in 2019.
    private var liveProfile: PlayerProfile? {
        freshnessViewModel?.profile(for: displayedPlayer)
    }

    @ViewBuilder
    private var contractValueCard: some View {
        if let profile = liveProfile, profile.contractLabel != nil, let freshnessViewModel {
            ContractValueCard(
                player: displayedPlayer,
                profile: profile,
                value: freshnessViewModel.contractValue(for: displayedPlayer),
                coverage: freshnessViewModel.dataCoverage?.week.map { "through Week \($0)" }
            )
        }
    }

    /// Defensive pages on the live season, while PFR's advanced table is out.
    private var defensivePendingNote: String? {
        guard displayedPlayer.positionGroup == .defense,
              let freshnessViewModel,
              displayedPlayer.season == freshnessViewModel.freeSeason,
              displayedPlayer.seasonPhase == .regular else { return nil }
        return MetricCoverage.pendingNote(
            category: .defense,
            advancedDefenseStatus: freshnessViewModel.dataFreshness?.advancedDefenseStatus,
            nextGenStatus: nil
        )
    }

    private var advancedContent: some View {
        VStack(spacing: 12) {
            // No headline card. It printed the player's top advanced metric
            // (EPA/Play for a quarterback) above a card whose first row is that
            // same metric, with the same value and the same colour - two
            // identical numbers a centimetre apart, and the top one had no bar
            // to read it against. Its season picker was a duplicate too: the
            // percentile card's own section bar carries one.
            percentileRankingsCard

            if let note = defensivePendingNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            contractValueCard

            if !store.isPro {
                RecentFormCard(
                    player: player,
                    season: activeSeason ?? player.season ?? Calendar.current.component(.year, from: .now),
                    leaguePlayers: cohortPlayers,
                    fetchGameLogs: fetchGameLogs,
                    freshnessRevision: freshnessViewModel?.freshnessRevision,
                    freshnessStatus: freshnessViewModel?.freshnessStatus,
                    onUpgradeTap: { trialPitchTrigger = .recentForm }
                )
                proUpsellCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var yearCompareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YEAR-OVER-YEAR")
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                    Text("Compare how this profile changed by season.")
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkSecondary)
                }
                Spacer()
                Button("Compare") {
                    selectedTab = .yearCompare
                    if store.isPro, !hasLoadedHistorical, !isHistoricalLoading {
                        Task { await loadHistorical?() }
                    }
                    if !store.isPro { trialPitchTrigger = .yearCompare }
                }
                .font(GridironType.smallBold)
                .buttonStyle(.bordered)
                .tint(GridironPalette.midnight)
            }
            if selectedTab == .yearCompare, store.isPro {
                yearCompareContent
            }
        }
        .padding(16)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: GridironGeo.radiusCard).stroke(GridironPalette.hairline, lineWidth: 0.5))
    }

    private var proUpsellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)
                Text("StatScout+")
                    .font(GridironType.smallBold)
                    .foregroundStyle(GridironPalette.ink)
            }

            Text("Get the full scouting picture on \(player.name).")
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                proPerk("chart.line.uptrend.xyaxis", "Year-over-year trends across every metric")
                proPerk("person.2.fill", "Head-to-head comparisons vs any player")
                proPerk("calendar.badge.clock", "Every past season, not just this one")
                proPerk("arrow.down.circle.fill", "Saved offline - works on the road")
            }

            Button {
                paywallTrigger = store.defaultUpgradeTrigger
            } label: {
                HStack(spacing: 6) {
                    Text(store.paywallBlurCTA)
                        .font(GridironType.bodyBold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(GridironPalette.turf)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let subtext = store.paywallBlurSubtext {
                Text(subtext)
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private func proPerk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GridironPalette.turf)
                .frame(width: 16)
            Text(text)
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var standardContent: some View {
        VStack(spacing: 12) {
            standardStatsGridCard
            if let freshnessViewModel,
               let season = activeSeason ?? player.season,
               (recentFormSeasons ?? [currentSeason]).contains(season) {
                PlayerGameLogCard(
                    viewModel: freshnessViewModel,
                    player: displayedPlayer,
                    season: season,
                    phase: activePhase
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var yearCompareContent: some View {
        if store.isPro {
            if isHistoricalLoading {
                historicalLoadingCard
            } else if !hasLoadedHistorical, loadHistorical != nil {
                loadHistoricalCard
            } else if history.count < 2 {
                ContentUnavailableView {
                    Label("Not enough history", systemImage: "calendar.badge.clock")
                } description: {
                    Text("\(player.name) doesn't have multiple seasons of data to compare.")
                }
                .padding(.vertical, 48)
            } else {
                YearComparisonView(history: phaseHistory)
            }
        } else {
            YearComparePreview(playerName: player.name) {
                trialPitchTrigger = .yearCompare
            }
        }
    }

    private var historicalLoadingCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: min(max(historicalLoadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(GridironPalette.turf)
            Text(historicalLoadingMessage)
                .font(GridironType.bodyBold)
                .foregroundStyle(GridironPalette.ink)
            Text("\(Int(min(max(historicalLoadingProgress, 0), 1) * 100))%")
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var loadHistoricalCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(GridironPalette.turf)
            Text("Load past seasons")
                .font(GridironType.bodyBold)
                .foregroundStyle(GridironPalette.ink)
            Text("Year Compare loads historical data only when you need it.")
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Load History") {
                Task { await loadHistorical?() }
            }
            .buttonStyle(.borderedProminent)
            .tint(GridironPalette.turf)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Cards

    private var seasonMenu: some View {
        let seasons = availablePercentileSeasons
        return Group {
            if seasons.count > 1 {
                Menu {
                    ForEach(seasons, id: \.self) { season in
                        let isLocked = season != currentSeason && !store.isPro
                        Button {
                            if isLocked {
                                // Explicit tap on a locked season - always answer it.
                                // PaywallGate only caps automatic pop-ups.
                                trialPitchTrigger = .pastSeason
                            } else {
                                selectedPercentileSeason = season
                            }
                        } label: {
                            HStack {
                                Text(SeasonLabel.text(season))
                                if isLocked {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.yellow)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(seasonLabel)
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(GridironPalette.inkSecondary)
                    }
                }
                .menuOrder(.fixed)
            } else {
                Text(seasonLabel)
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var formModePicker: some View {
        HStack(spacing: 6) {
            ForEach(FormDisplayMode.allCases, id: \.self) { mode in
                Button {
                    formDisplayMode = mode
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(mode.rawValue)
                        .font(GridironType.smallBold)
                        .foregroundStyle(formDisplayMode == mode ? .white : GridironPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(formDisplayMode == mode ? GridironPalette.turf : GridironPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(GridironPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.vertical, 10)
        .background(GridironPalette.surfaceAlt)
    }

    private var percentileRankingsCard: some View {
        VStack(spacing: 0) {
            GridironSectionBar(
                title: displayedPlayer.positionGroup == .defense ? "PRODUCTION PERCENTILES" : "ADVANCED PERCENTILES",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        seasonMenu
                        Button(action: { showPercentileInfo = true }) {
                            Text("ⓘ")
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.linkBlue)
                        }
                        .buttonStyle(.plain)
                    }
                )
            )

            // Recent mode only makes sense for the live season - game logs are
            // only fetched for the current season, so on a historical season it
            // would always read "No games".
            if store.isPro, supportsRecentForm {
                formModePicker
            }

            if formDisplayMode != .season, store.isPro, supportsRecentForm {
                recentWindowPicker
                if recentLoading {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.75)
                        Text("Loading recent games…")
                            .font(GridironType.small)
                            .foregroundStyle(GridironPalette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else if let recentLoadError {
                    Text(recentLoadError)
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if recentWindow == nil {
                    Text(recentEmptyStateText)
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }

            if groupedMetrics.isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "No metrics available",
                    description: "Percentile rankings are not available for this player in the \(seasonLabel) season."
                )
                .padding(.vertical, 24)
            } else {
                ForEach(groupedMetrics, id: \.family) { group in
                    let rows = displayedMetrics(in: group.metrics)
                    if !rows.isEmpty {
                        GridironSubSectionBar(
                            title: group.family.rawValue.uppercased()
                        )

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                            percentileMetricRow(metric: metric, index: index)
                        }
                    }
                }
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(formDisplayMode)-\(recentWindowGames)-\(player.playerId)-\(activeSeason ?? 0)-\(store.isPro)-\(freshnessViewModel?.freshnessRevision ?? "none")") {
            guard store.isPro, effectiveFormDisplayMode != .season else { return }
            rebuildRecentCurves()
            await loadRecentLogs()
        }
        .onAppear { rebuildRecentCurves() }
        .onChange(of: allPlayers.count) { _, _ in rebuildRecentCurves() }
        .onChange(of: activeSeason) { _, _ in rebuildRecentCurves() }
    }

    private var category: MetricCategory { displayedPlayer.primaryCategory }

    /// Recent-form is anchored to the current season's game logs, so it's only
    /// meaningful while viewing the current season. Historical seasons render
    /// season bars only.
    /// Whether Recent / Both are offered for the season on screen.
    ///
    /// Was "is this the live season", which stopped being the rule when Recent
    /// form was widened to the live season *and the one before it*. Trends and
    /// Teams both moved to `DashboardViewModel.recentFormSeasons`; this page did
    /// not, so from the first 2026 game onwards a subscriber opening a 2025
    /// profile would have found no Recent control on a season whose game logs
    /// are right there, and which the Trends board two taps away still ranks.
    ///
    /// Falls back to the single-season rule when no list is supplied, which is
    /// the previews-and-tests path.
    private var supportsRecentForm: Bool {
        let season = activeSeason ?? currentSeason
        guard let recentFormSeasons else { return season == currentSeason }
        return recentFormSeasons.contains(season)
    }

    private var recentEmptyStateText: String {
        switch freshnessViewModel?.freshnessStatus {
        case .pending, .partial, .checking:
            return "Recent game data is still arriving"
        case .offline, .failed:
            return "Recent game data is unavailable right now"
        default:
            return "No games in the last \(recentWindowGames) games"
        }
    }

    /// The mode rows actually render in - forced back to `.season` on a
    /// historical season so a user who toggled Recent/Both doesn't see stale
    /// current-season windows against past-season bars.
    private var effectiveFormDisplayMode: FormDisplayMode {
        supportsRecentForm ? formDisplayMode : .season
    }

    private var recentWindow: RecentFormWindow? {
        let windowLogs = Array(recentLogs.sorted { $0.gameDate > $1.gameDate }.prefix(recentWindowGames))
        guard !windowLogs.isEmpty else { return nil }
        return RecentFormWindow.build(label: "Last \(recentWindowGames)", span: recentWindowGames, logs: windowLogs)
    }

    private var recentWindowPicker: some View {
        GridironSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: Binding(
                get: { RecentWindow(rawValue: recentWindowGames) ?? .three },
                set: { recentWindowGames = $0.rawValue }
            )
        )
    }

    private func displayedMetrics(in metrics: [Metric]) -> [Metric] {
        guard effectiveFormDisplayMode == .recent, store.isPro else { return metrics }
        // Recent mode: show every season bar - metrics with window data render the
        // recent value, the rest fall back to the season bar (handled in
        // `percentileMetricRow`). Additionally inject a stub for any game-log spec
        // the season snapshot omits (Gridiron sometimes drops e.g. Hard-Hit%) so its
        // recent bar still appears even with no season row to hang it on.
        let targetCategory: MetricCategory = category
        guard metrics.first?.category == targetCategory else { return metrics }
        let existing = Set(metrics.map { $0.label })
        let stubs: [Metric] = recentSpecs.compactMap { spec in
            guard !existing.contains(spec.label) else { return nil }
            let stub = Metric(
                id: "recent-stub-\(spec.label)",
                label: spec.label,
                value: "",
                percentile: 0,
                category: targetCategory
            )
            return recentMetric(for: stub) != nil ? stub : nil
        }
        return metrics + stubs
    }

    /// One metric the last-N-games window can reconstruct, and how.
    ///
    /// `value` takes the summed game-log metrics for the window. Rates are
    /// recomputed from their own summed numerator and denominator rather than
    /// averaged across games: a quarterback who went 1-for-4 in a blowout and
    /// 30-for-40 the week after has a two-game completion rate of 31/44, not the
    /// mean of 25% and 75%. That is the same rule the backend rollup follows,
    /// and it is why the game log stores counts instead of pre-divided rates.
    private struct RecentSpec {
        let label: String
        let format: String
        let value: ([String: Double]) -> Double?
    }

    private static func total(_ key: String, _ label: String, _ format: String = "%.0f") -> RecentSpec {
        RecentSpec(label: label, format: format) { $0[key] }
    }

    /// A rate, from sums. Nil when the denominator is absent or zero, so an
    /// inactive stretch reads as "no data" instead of as a divide-by-zero 0.0.
    private static func rate(
        _ label: String,
        _ format: String,
        numerator: String,
        over denominators: [String],
        scale: Double = 1
    ) -> RecentSpec {
        RecentSpec(label: label, format: format) { m in
            let den = denominators.reduce(0.0) { $0 + (m[$1] ?? 0) }
            guard den > 0, let num = m[numerator] else { return nil }
            return num / den * scale
        }
    }

    /// Deliberately partial.
    ///
    /// Only metrics the per-game log can rebuild *exactly* are listed. The ones
    /// left out - Aggressiveness, Intended Air Yds, CPOE, Time to Throw,
    /// Separation, YAC+, Explosive%, Target Share, WOPR - are either Next Gen
    /// Stats season aggregates published with no per-game denominator, or need a
    /// team total the player's own rows do not carry. Averaging their per-game
    /// figures would produce an average of averages and quietly present it as a
    /// window rate, so they get no recent bar and the Both view says so out loud
    /// rather than silently showing one line where two belong.
    private var recentSpecs: [RecentSpec] {
        switch category {
        case .passing:
            return [
                Self.total("passing_yards", "Pass Yds"),
                Self.total("passing_tds", "Pass TD"),
                Self.rate("Cmp%", "%.1f%%", numerator: "completions", over: ["attempts"], scale: 100),
                Self.rate("Y/A", "%.1f", numerator: "passing_yards", over: ["attempts"]),
                Self.rate("INT%", "%.1f%%", numerator: "interceptions", over: ["attempts"], scale: 100),
                // EPA/Play is per dropback: attempts plus sacks, matching the
                // registry's own definition of the season metric.
                Self.rate("EPA/Play", "%.2f", numerator: "passing_epa", over: ["attempts", "sacks_suffered"]),
                Self.rate("Sack%", "%.1f%%", numerator: "sacks_suffered", over: ["attempts", "sacks_suffered"], scale: 100),
            ]
        case .rushing:
            return [
                Self.total("rushing_yards", "Rush Yds"),
                Self.total("rushing_tds", "Rush TD"),
                Self.total("rushing_first_downs", "Rush 1D"),
                Self.total("rushing_epa", "Rush EPA", "%.1f"),
                Self.total("rush_yoe", "RYOE", "%.1f"),
                Self.rate("Y/C", "%.1f", numerator: "rushing_yards", over: ["carries"]),
                Self.rate("EPA/Rush", "%.2f", numerator: "rushing_epa", over: ["carries"]),
                Self.rate("Fumble%", "%.1f%%", numerator: "rushing_fumbles", over: ["carries"], scale: 100),
            ]
        case .receiving:
            return [
                Self.total("receiving_yards", "Rec Yds"),
                Self.total("receptions", "Rec"),
                Self.total("receiving_tds", "Rec TD"),
                Self.total("receiving_yac", "YAC"),
                Self.total("receiving_epa", "Rec EPA", "%.1f"),
                Self.rate("Catch%", "%.1f%%", numerator: "receptions", over: ["targets"], scale: 100),
                Self.rate("EPA/Tgt", "%.2f", numerator: "receiving_epa", over: ["targets"]),
                Self.rate("RACR", "%.2f", numerator: "receiving_yards", over: ["receiving_air_yards"]),
            ]
        case .defense:
            return [
                Self.total("tackles", "Tackles"),
                Self.total("def_sacks", "Sacks", "%.1f"),
                Self.total("def_interceptions", "INT"),
                Self.total("def_pass_defended", "PD"),
                Self.total("def_tackles_for_loss", "TFL"),
                Self.total("def_qb_hits", "QB Hits"),
                Self.total("def_fumbles_forced", "FF"),
            ]
        }
    }

    @ViewBuilder
    private func percentileMetricRow(metric: Metric, index: Int) -> some View {
        let recentMetric = recentMetric(for: metric)
        let rowBackground = index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt

        switch effectiveFormDisplayMode {
        case .season:
            NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason, phase: activePhase)) {
                MetricBar(metric: metric)
                    .padding(.horizontal, GridironGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                        alignment: .bottom
                    )
            }
            .buttonStyle(.plain)
        case .recent:
            if let recentMetric {
                MetricBar(metric: recentMetric)
                    .padding(.horizontal, GridironGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                        alignment: .bottom
                    )
            } else if !metric.id.hasPrefix("recent-stub-") {
                // No game-log data for this metric - fall back to the season bar
                // so the recent view still shows every percentile bar.
                NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason, phase: activePhase)) {
                    MetricBar(metric: metric)
                        .padding(.horizontal, GridironGeo.padCard)
                        .padding(.vertical, 12)
                        .background(rowBackground)
                        .overlay(
                            Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        case .both:
            NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason, phase: activePhase)) {
                DualMetricBar(
                    season: metric,
                    recent: recentMetric,
                    recentCaption: "Last \(recentWindowGames)"
                )
                .padding(.horizontal, GridironGeo.padCard)
                .padding(.vertical, 12)
                .background(rowBackground)
                .overlay(
                    Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func recentMetric(for seasonMetric: Metric) -> Metric? {
        guard let w = recentWindow,
              let spec = recentSpecs.first(where: { $0.label == seasonMetric.label }),
              let v = spec.value(w.metrics),
              let pct = recentCurves?.curve(for: spec.label)?.percentile(for: v) else { return nil }
        return Metric(
            id: "recent-\(spec.label)",
            label: seasonMetric.label,
            value: String(format: spec.format, v),
            percentile: pct,
            category: seasonMetric.category
        )
    }

    private func rebuildRecentCurves() {
        recentCurves = LeaguePercentileCurves(
            players: cohortPlayers,
            categories: [category],
            labels: category.metricPriorityOrder
        )
    }

    private func loadRecentLogs() async {
        guard store.isPro, let fetch = fetchGameLogs,
              let season = activeSeason ?? player.season else { return }
        // Two cards want these logs now (percentiles and standard stats) and
        // each has its own task, so remember what is already in hand rather
        // than refetching the same season the moment the user switches tabs.
        // The phase belongs in the key. Without it, opening a player's regular
        // season and then his playoffs reused the first fetch's games under the
        // second heading - the cache said "same player, same season, already have
        // it" about two different sets of football.
        let key = "\(player.playerId)-\(season)-\(activePhase.rawValue)-\(freshnessViewModel?.freshnessRevision ?? "none")"
        if recentLogsKey == key, !recentLogs.isEmpty { return }
        // Both cards ask at once; share one request per key. A different key
        // (the season or phase changed mid-load) gets its own request, and the
        // stale one discards its result instead of labelling last season's
        // games with this season's heading.
        guard recentLoadingKey != key else { return }
        recentLoadingKey = key
        recentLoading = true
        recentLoadError = nil
        do {
            let logs = try await fetch(player.playerId, season, activePhase)
            guard recentLoadingKey == key else { return }
            recentLogs = logs
            recentLogsKey = key
        } catch {
            guard recentLoadingKey == key else { return }
            // Distinguish "no games" from "fetch failed" - otherwise a network
            // error renders as an honest-looking "No games in the last N days".
            if !isTaskCancellation(error), recentLogs.isEmpty || recentLogsKey != key {
                recentLogs = []
                recentLogsKey = nil
                recentLoadError = "Couldn't load recent games. Check your connection and try again."
            }
        }
        recentLoadingKey = nil
        recentLoading = false
    }

    private func refreshProfile() async {
        guard let freshnessViewModel else { return }
        // Keep existing rows visible while the shared revision check runs. The
        // task IDs will fetch them again only when a new revision is accepted.
        await freshnessViewModel.load()
        recentLogsKey = nil
        if store.isPro,
           effectiveFormDisplayMode != .season || effectiveStandardMode != .season {
            await loadRecentLogs()
        }
    }

    /// Which of the four boards a traditional stat belongs to, so tapping a row
    /// opens the leaderboard that actually lists it. Without this a running
    /// back's Rec Yds row pushed the Passing board, which has no Rec Yds column.
    private static func standardCategory(for label: String, fallback: StandardStatCategory) -> StandardStatCategory {
        switch label.uppercased() {
        case "PASS YDS", "PASS TD", "INT", "CMP/ATT": return .passing
        case "CAR", "RUSH YDS", "RUSH TD":            return .rushing
        case "REC/TGT", "REC YDS", "REC TD":          return .receiving
        case "TACKLES", "SACKS", "DEF INT":           return .defense
        default:                                      return fallback
        }
    }

    private var standardFallbackCategory: StandardStatCategory {
        switch displayedPlayer.playerType?.lowercased() {
        case "qb":  return .passing
        case "rb":  return .rushing
        case "wr", "te": return .receiving
        default:    return .defense
        }
    }

    /// Counting stats. Ranking these is honest but playing-time driven, a
    /// backup's 2 rushing touchdowns isn't a talent signal, so they're grouped
    /// separately from the rate stats and captioned as volume.
    ///
    /// Football's traditional line is almost entirely counting stats, unlike
    /// baseball's, so in practice the RATE group is usually empty and the
    /// sub-section bars are only drawn when both groups have something in them.
    ///
    /// "Tgt Allowed" belongs here with the other counts: the pipeline emits it
    /// as the volume behind a defender's coverage rates, and leaving it out put
    /// a raw target count under the RATE heading.
    private static let countingStats: Set<String> = [
        "G", "PASS YDS", "PASS TD", "INT", "CAR", "RUSH YDS", "RUSH TD",
        "REC", "REC YDS", "REC TD", "TACKLES", "SACKS", "DEF INT",
        "TGT ALLOWED",
    ]

    /// Percentile rank for a traditional stat against the league.
    ///
    /// The pipeline publishes percentiles for the advanced metrics but not for
    /// the traditional line, so these are computed here: a player's position in
    /// the distribution of every same-position player who has the stat. Returns
    /// a midpoint percentile for every existing value, even when only a small
    /// early-season cohort has played.
    private func standardStatPercentile(
        label: String,
        value: String
    ) -> Int {
        StandardStatSemantics.percentile(
            label: label,
            value: value,
            peerValues: peerValues(forStat: label)
        )
    }

    /// Same-position players' values for one traditional stat.
    ///
    /// Kept as its own step so the season and recent rows of a card share the
    /// walk over `allPlayers` for a given stat instead of each row starting it
    /// again.
    private func peerValues(forStat label: String) -> [String] {
        let key = label.uppercased()
        let group = displayedPlayer.positionGroup
        return cohortPlayers.compactMap { other in
            guard other.positionGroup == group,
                  let stat = other.standardStats?.first(where: { $0.label.uppercased() == key })
            else { return nil }
            return stat.value
        }
    }

    /// The data's own spelling of a stat, given the uppercased one this card
    /// displays.
    ///
    /// These rows are shown in caps ("PASS YDS") but the stored labels are
    /// title-case ("Pass Yds"), and the leaderboard a row pushes to filters on
    /// an exact match. Routing with the display label therefore sent every
    /// single traditional stat, for every position, to a board that matched
    /// nothing and rendered "No QB players have PASS YDS data for this season"
    /// - a stat the very same board lists correctly when reached from the View
    /// menu. Case was the whole of it.
    private func standardStatKey(for displayLabel: String) -> String {
        (displayedPlayer.standardStats ?? [])
            .first { $0.label.uppercased() == displayLabel }?.label ?? displayLabel
    }

    /// Standard stats rendered as the same `Metric` the percentile card uses, so
    /// both tabs read on one ruler. Composite values such as Cmp/Att and Rec/Tgt
    /// rank by their rate rather than by the leading count.
    private func standardMetrics(counting: Bool) -> [Metric] {
        (displayedPlayer.standardStats ?? [])
            .filter { Self.countingStats.contains($0.label.uppercased()) == counting }
            .map { stat in
                let pct = standardStatPercentile(label: stat.label, value: stat.value)
                return Metric(
                    id: "std-\(stat.label)",
                    label: stat.label.uppercased(),
                    value: stat.value,
                    percentile: pct,
                    category: Self.standardCategory(for: stat.label, fallback: standardFallbackCategory).metricCategory,
                    // A zero count has no honest rank, same rule as the feed's
                    // metrics (`Metric.isUnranked`), except where fewer is
                    // better: a passer's 0 INT ranks at the top.
                    rankable: counting
                        && StandardStatSemantics.higherIsBetter(label: stat.label)
                        && metricNumericValue(stat.value) == 0 ? false : nil
                )
            }
    }

    /// Traditional stat label to its per-game log key. Games played and the
    /// composite Cmp/Att and Rec/Tgt lines have no single-number window
    /// counterpart, so they keep their season row alone.
    ///
    /// These are `player_game_logs` keys, not `player_recent_form` ones, and the
    /// difference is the point. The rollup this card used to read is keyed by
    /// *league weeks*: picking "5 games" served the last five weeks of the
    /// season, so a player who was inactive for two of them got a five-game
    /// label over a three-game total, and a player on bye got a window that
    /// quietly skipped a week. The percentile card on the next tab was already
    /// summing this player's own last N game logs; the two cards disagreed
    /// about what "last 5" meant. Now they don't.
    private static let standardRecentKeys: [String: String] = [
        "PASS YDS": "passing_yards", "PASS TD": "passing_tds", "INT": "interceptions",
        "CAR": "carries", "RUSH YDS": "rushing_yards", "RUSH TD": "rushing_tds",
        "REC": "receptions", "REC YDS": "receiving_yards", "REC TD": "receiving_tds",
        "TACKLES": "tackles", "SACKS": "def_sacks", "DEF INT": "def_interceptions",
    ]

    /// This player's own last N games, summed. Same `recentLogs` the percentile
    /// card reads, so both tabs answer "last 5 games" with the same five games.
    private var standardRecentWindow: RecentFormWindow? {
        let span = standardWindow.rawValue
        let windowLogs = Array(
            recentLogs.sorted { $0.gameDate > $1.gameDate }.prefix(span)
        )
        guard !windowLogs.isEmpty else { return nil }
        return RecentFormWindow.build(label: "Last \(span)", span: span, logs: windowLogs)
    }

    /// What the recent column is actually made of. See
    /// `RecentFormWindow.caption`.
    private var standardRecentCaption: String {
        guard let games = standardRecentWindow?.games else {
            return standardWindow.segmentLabel
        }
        return RecentFormWindow.caption(games: games, span: standardWindow.rawValue)
    }

    /// The recent-window version of one traditional stat, or nil when the window
    /// has no figure for it. Percentile comes from the same league season
    /// distribution the season row uses, so both sit on one ruler.
    private func recentStandardMetric(for seasonMetric: Metric) -> Metric? {
        guard let key = Self.standardRecentKeys[seasonMetric.label],
              let value = standardRecentWindow?.metrics[key] else { return nil }
        let text = seasonMetric.label == "SACKS"
            ? String(format: "%.1f", value)
            : Int(value.rounded()).formatted(.number.grouping(.automatic))
        return Metric(
            id: "std-recent-\(seasonMetric.label)",
            label: seasonMetric.label,
            value: text,
            percentile: standardStatPercentile(
                label: seasonMetric.label,
                value: text
            ),
            category: seasonMetric.category
        )
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            // The season already appears in the picker on the right; printing
            // it in the title too was saying it twice.
            GridironSectionBar(
                title: "STANDARD STATS",
                trailing: AnyView(seasonMenu)
            )

            // Recent only means something on the season the rollup covers; on a
            // past season the window would always be empty.
            if supportsRecentForm {
                standardModePicker
                if effectiveStandardMode != .season {
                    standardWindowPicker
                }
            }

            if (displayedPlayer.standardStats ?? []).isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "Standard stats unavailable",
                    description: "Traditional stats are not available for this player."
                )
                .padding(.vertical, 24)
            } else {
                let rates = standardMetrics(counting: false)
                let counts = standardMetrics(counting: true)
                // Only worth labelling the two groups when there are two of
                // them. A football line is usually all volume, and a lone
                // "VOLUME" bar above every row says nothing.
                let labelled = !rates.isEmpty && !counts.isEmpty

                if !rates.isEmpty {
                    if labelled { GridironSubSectionBar(title: "RATE") }
                    standardRows(rates)
                }
                if !counts.isEmpty {
                    if labelled { GridironSubSectionBar(title: "VOLUME") }
                    standardRows(counts, startingIndex: rates.count)
                }
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        // Standard Stats is its own tab, so the percentile card's loader never
        // runs while you are looking at this one. Without this the Recent /
        // Both modes rendered season numbers under a "5 games" caption until
        // you happened to visit the other tab first.
        .task(id: "std-\(standardMode)-\(standardWindow.rawValue)-\(player.playerId)-\(activeSeason ?? 0)-\(store.isPro)-\(freshnessViewModel?.freshnessRevision ?? "none")") {
            guard store.isPro, effectiveStandardMode != .season else { return }
            await loadRecentLogs()
        }
    }

    private var effectiveStandardMode: FormDisplayMode {
        (store.isPro && supportsRecentForm) ? standardMode : .season
    }

    private var standardModePicker: some View {
        GridironSegmented(
            segments: FormDisplayMode.allCases.map {
                .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 != .season)
            },
            selection: $standardMode,
            onLockedTap: { _ in trialPitchTrigger = .recentForm }
        )
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.vertical, 10)
        .background(GridironPalette.surfaceAlt)
    }

    private var standardWindowPicker: some View {
        GridironSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: $standardWindow
        )
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.bottom, 8)
        .background(GridironPalette.surfaceAlt)
    }

    @ViewBuilder
    private func standardRows(_ metrics: [Metric], startingIndex: Int = 0) -> some View {
        ForEach(Array(metrics.enumerated()), id: \.element.id) { offset, metric in
            let recent = recentStandardMetric(for: metric)
            let background = (startingIndex + offset) % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt

            NavigationLink(value: StandardStatRoute(
                stat: standardStatKey(for: metric.label),
                category: Self.standardCategory(for: metric.label, fallback: standardFallbackCategory),
                season: activeSeason,
                phase: activePhase
            )) {
                Group {
                    switch effectiveStandardMode {
                    case .season:
                        MetricBar(metric: metric)
                    case .recent:
                        // No recent figure for this stat, fall back to season
                        // rather than dropping the row, matching the percentile
                        // card's behaviour.
                        MetricBar(metric: recent ?? metric)
                    case .both:
                        DualMetricBar(
                            season: metric,
                            recent: recent,
                            recentCaption: standardRecentCaption
                        )
                    }
                }
                .padding(.horizontal, GridironGeo.padCard)
                .padding(.vertical, 12)
                .background(background)
                .overlay(
                    Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
        }
    }

}

struct PercentileInfoSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Percentile Rankings")
                        .font(GridironType.playerName)
                        .foregroundStyle(GridironPalette.ink)

                    Text("Percentile rankings compare a player to others at the same position. A 90th percentile means the player ranks in the top 10% of the league for that metric.")
                        .font(GridironType.body)
                        .foregroundStyle(GridironPalette.inkSecondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Elite (75-100): Green bars", systemImage: "flame.fill")
                            .font(GridironType.bodyBold)
                            .foregroundStyle(GridironPalette.performanceHigh)
                        Label("Average (25-75): Charcoal bars", systemImage: "minus")
                            .font(GridironType.bodyBold)
                            .foregroundStyle(GridironPalette.inkSecondary)
                        Label("Below Average (0-25): Rust bars", systemImage: "snowflake")
                            .font(GridironType.bodyBold)
                            .foregroundStyle(GridironPalette.performanceLow)
                    }
                    .padding(.vertical, 8)

                    Text("Stats update after new source data is validated. Advanced metrics may arrive later than game totals. Not every metric is tracked for every player.")
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkTertiary)
                }
                .padding(24)
            }
            .background(GridironPalette.canvas.ignoresSafeArea())
            .navigationTitle("About Percentiles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlayerPickerSheet: View {
    let players: [Player]
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredPlayers: [Player] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.team.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredPlayers) { player in
                Button {
                    dismiss()
                    onSelect(player)
                } label: {
                    HStack(spacing: 12) {
                        PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(GridironType.bodyBold)
                                .foregroundStyle(GridironPalette.ink)
                            Text("\(player.team) · \(player.displayPosition)")
                                .font(GridironType.small)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
            .navigationTitle("Compare With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerProfileView(player: SampleData.players[0], history: [SampleData.players[0]])
            .environmentObject(StoreService.shared)
    }
}
#endif
