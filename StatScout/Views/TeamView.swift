import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    /// Seed roster for previews and tests, used only when there is no view
    /// model. The live roster is derived, see `players`.
    var seedPlayers: [Player] = []
    /// Seed season for previews and tests, used only when there is no view
    /// model. See `displaySeason`.
    var seedSeason: Int? = nil
    var viewModel: DashboardViewModel? = nil
    /// (team, season, phase, since).
    var fetchTeamGameLogs: ((String, Int, SeasonPhase, Date) async throws -> [PlayerGameLog])? = nil
    @State private var selectedTab: TeamTab = .advanced
    @State private var searchText = ""
    @State private var isSearching = false
    // Default to Passing so the roster always shows a meaningful sort metric.
    @State private var selectedCategory: MetricCategory? = .passing
    @State private var sortDescending = true
    @State private var lastDefaultedSortKey: String? = nil
    @State private var showingTrial = false
    @State private var trialTrigger: PaywallTrigger?
    @State private var rosterSide: RosterSide = .offense
    @State private var qualifierLevel: DashboardViewModel.QualifierLevel = .all
    @State private var rosterMode: RosterMode = .season
    @State private var rosterWindow: RecentWindow = .five
    @State private var userSortLabel: String?

    enum TeamTab: String, CaseIterable {
        case advanced = "Advanced"
        case standard = "Standard"
        case roster = "Roster"
    }

    enum RosterMode: String, CaseIterable, Identifiable {
        case season = "Season"
        case recent = "Recent"

        var id: String { rawValue }
    }

    enum RosterSide: String, CaseIterable, Identifiable {
        case offense = "Offense"
        case defense = "Defense"

        var id: String { rawValue }

        var categories: [MetricCategory] {
            switch self {
            case .offense: return [.passing, .rushing, .receiving]
            case .defense: return [.defense]
            }
        }

        func matches(_ player: Player) -> Bool {
            switch player.positionGroup {
            case .defense: return self == .defense
            default: return self == .offense
            }
        }
    }

    /// The roster for the season and phase that are selected *right now*.
    ///
    /// This was a one-time array captured when the page was pushed. The nav-bar
    /// picker here moves `viewModel.selectedSeason`, and `leaguePlayers`
    /// followed it, but the rows, cards, category filters and sort metrics all
    /// kept reading the array from arrival: you picked 2024, the picker said
    /// 2024, the league context was 2024, and the roster underneath was still
    /// whichever season you happened to open the page in.
    private var players: [Player] {
        guard let viewModel else { return seedPlayers }
        return viewModel.players(forTeam: team)
    }

    private var displaySeason: Int {
        viewModel?.selectedSeason
            ?? seedSeason
            ?? seedPlayers.compactMap(\.season).max()
            ?? Calendar.current.component(.year, from: Date())
    }

    private var leaguePlayers: [Player] {
        viewModel?.seasonPlayers ?? []
    }

    /// The phase the whole page is reading. Every roster number already comes
    /// from `seasonPlayers`, which is filtered by it; the cards need it too so
    /// their game-log windows come from the same half of the year.
    private var displayPhase: SeasonPhase {
        viewModel?.selectedPhase ?? .regular
    }

    private var sortMetric: (label: String, category: MetricCategory)? {
        guard let category = selectedCategory else { return nil }
        if let userSortLabel, availableSortLabels.contains(userSortLabel) {
            return (userSortLabel, category)
        }
        for label in priorityMetrics(for: category) {
            if players.contains(where: { p in p.metrics.contains { $0.label == label && $0.category == category } }) {
                return (label, category)
            }
        }
        return nil
    }

    private var availableSortLabels: [String] {
        guard let category = selectedCategory else { return [] }
        let present = Set(players.flatMap { player in
            player.metrics.filter { $0.category == category }.map(\.label)
        })
        let ordered = category.metricPriorityOrder.filter { present.contains($0) }
        return ordered + present.subtracting(category.metricPriorityOrder).sorted()
    }

    private var sortLabel: String {
        if selectedCategory == nil { return "Overall" }
        return sortMetric?.label ?? "Top Category"
    }

    private var rowDisplayMetric: (label: String?, category: MetricCategory?) {
        if let m = sortMetric { return (m.label, m.category) }
        // "All" is the whole roster at once, offence and defence together, so
        // there is no one metric that means the same thing down the column. It
        // used to force Pass Yds, which printed a zero beside every player who
        // isn't a quarterback. Each row shows its own overall percentile
        // instead.
        return (nil, nil)
    }

    private func rawValue(_ player: Player) -> Double? {
        guard let m = sortMetric,
              let metric = player.metrics.first(where: { $0.label == m.label && $0.category == m.category })
        else { return nil }
        return DashboardViewModel.rawNumeric(metric.value)
    }

    private func fallbackPercentile(_ player: Player) -> Int {
        if let category = selectedCategory, let p = player.percentile(for: category) { return p }
        return player.overallPercentile
    }

    private func recentForm(_ player: Player) -> RecentForm? {
        viewModel?.recentForm(for: player.playerId, window: rosterWindow)
    }

    private func recentKey() -> String? {
        guard let label = sortMetric?.label else { return nil }
        return RecentMetricKey.key(for: label)
    }

    private func recentValue(_ player: Player) -> Double? {
        guard let key = recentKey() else { return nil }
        return recentForm(player)?.metrics[key]
    }

    private func recentDelta(_ player: Player) -> Double? {
        guard let key = recentKey() else { return nil }
        return recentForm(player)?.delta[key]
    }

    private func recentValueText(_ player: Player) -> String {
        guard let label = sortMetric?.label, let value = recentValue(player) else {
            return "-"
        }
        return RecentMetricKey.format(value, label: label)
    }

    private var hasRecentData: Bool {
        viewModel?.recentFormByWindow[rosterWindow.rawValue] != nil
    }

    private var isRosterRecent: Bool {
        rosterMode == .recent && store.isPro && supportsRecent
    }

    /// Recent form exists for the live season only: the rolling windows and the
    /// per-game logs behind them are no longer kept for finished seasons, so
    /// every Recent control on this screen is hidden (not locked) on a
    /// historical one. Falls back to the calendar when there is no view model,
    /// which is the previews-and-tests path.
    private var supportsRecent: Bool {
        viewModel.map { $0.supportsRecentForm(displaySeason) }
            ?? (displaySeason == StatScoutSeason.current)
    }

    private var filteredPlayers: [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.displayPosition.localizedCaseInsensitiveContains(searchText)
        }
        let bySide = bySearch.filter { rosterSide.matches($0) }
        let byCategory = bySide.filter { player in
            guard let selectedCategory else { return true }
            return player.metrics.contains { $0.category == selectedCategory }
        }
        let byQualifier = byCategory.filter { isQualified($0) }
        if isRosterRecent, sortMetric != nil {
            return byQualifier.filter { recentValue($0) != nil }.sorted {
                let first = recentValue($0) ?? 0
                let second = recentValue($1) ?? 0
                return sortDescending ? first > second : first < second
            }
        }
        guard let sortMetric else {
            return byQualifier.sorted {
                sortDescending ? fallbackPercentile($0) > fallbackPercentile($1) : fallbackPercentile($0) < fallbackPercentile($1)
            }
        }
        return byQualifier.sorted(by: DashboardViewModel.metricComparator(
            label: sortMetric.label,
            category: sortMetric.category,
            descending: sortDescending
        ))
    }

    private func isQualified(_ player: Player) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            return DashboardViewModel.hasQualifyingMetric(player, in: selectedCategory)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let viewModel {
                    DataFreshnessView(
                        viewModel: viewModel,
                        season: displaySeason,
                        phase: displayPhase
                    )
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    if displaySeason == viewModel.freeSeason {
                        TeamWeekGameCard(viewModel: viewModel, team: team)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
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
                case .roster:
                    rosterContent
                }

                StatGlossaryLink()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                // Lets content scroll under the floating tab bar so the last
                // rows aren't trapped behind it - matches Dashboard.
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(GridironPalette.canvas.ignoresSafeArea())
        .refreshable {
            await viewModel?.load()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { teamSwitcherMenu }
            if let viewModel {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        navSeasonMenu(viewModel: viewModel)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        navSeasonMenu(viewModel: viewModel)
                    }
                }
            }
        }
        .onAppear { applyDefaultDirectionIfMetricChanged() }
        .onChange(of: selectedCategory) { _, _ in
            userSortLabel = nil
            applyDefaultDirectionIfMetricChanged()
        }
        // Season changes through the nav-bar menu rotate the roster data beneath
        // us; re-default the sort direction so the chip never displays a metric
        // the new season doesn't have.
        .onChange(of: displaySeason) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        // Same reasoning for the phase: a playoff roster carries a different set
        // of metrics than the regular season's, so the sort chip has to re-resolve.
        .onChange(of: viewModel?.selectedPhase) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        .task(id: "\(rosterMode.rawValue)-\(rosterWindow.rawValue)-\(displaySeason)-\(viewModel?.selectedPhase.rawValue ?? "")-\(store.isPro)-\(viewModel?.freshnessRevision ?? "none")") {
            guard isRosterRecent else { return }
            await viewModel?.loadRecentFormIfNeeded(window: rosterWindow)
        }
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .teamView)
        }
        .sheet(item: $trialTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    // MARK: - Tabs

    /// Mirrors the player profile's tab selector with equal-width turf controls
    /// that swap the card content below. Two tabs: the team's percentile profile and
    /// its sortable roster.
    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(TeamTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(tab.rawValue)
                        .font(GridironType.smallBold)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white : GridironPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? GridironPalette.turf : GridironPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var advancedContent: some View {
        VStack(spacing: 12) {
            TeamRankingsCard(
                team: team,
                season: displaySeason,
                seasonPhase: displayPhase,
                players: players,
                leaguePlayers: leaguePlayers,
                fetchTeamGameLogs: fetchTeamGameLogs,
                freshnessRevision: viewModel?.freshnessRevision,
                freshnessStatus: viewModel?.freshnessStatus,
                onUpgradeTap: {
                    // Explicit tap, always answer it; the gate only caps
                    // automatic pop-ups.
                    showingTrial = true
                }
            )

        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var standardContent: some View {
        TeamStandardCard(
            team: team,
            season: displaySeason,
            seasonPhase: displayPhase,
            players: players,
            leaguePlayers: leaguePlayers,
            fetchTeamGameLogs: fetchTeamGameLogs,
            supportsRecent: supportsRecent,
            onUpgradeTap: { showingTrial = true }
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var rosterContent: some View {
        VStack(spacing: 0) {
            GridironPickerRow {
                sidePicker.segmentCount(RosterSide.allCases.count)
                rosterModePicker.segmentCount(RosterMode.allCases.count)
            }
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if isRosterRecent {
                GridironSegmented(
                    segments: RecentWindow.allCases.map {
                        .init(value: $0, label: $0.segmentLabel)
                    },
                    selection: $rosterWindow
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if rosterSide.categories.count > 1 {
                GridironTabs(
                    tabs: rosterSide.categories.map(\.rawValue),
                    selected: Binding(
                        get: { (selectedCategory ?? rosterSide.categories[0]).rawValue },
                        set: { rawValue in
                            selectedCategory = MetricCategory.allCases.first {
                                $0.rawValue == rawValue
                            }
                        }
                    )
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if !players.isEmpty {
                sortControlsRow
                if isSearching || !searchText.isEmpty {
                    searchRow
                }
            }

            rosterSection
        }
    }

    private func applyDefaultDirectionIfMetricChanged() {
        let key = sortMetric.map { "\($0.category.rawValue)|\($0.label)" } ?? "-"
        guard key != lastDefaultedSortKey else { return }
        lastDefaultedSortKey = key
        sortDescending = DashboardViewModel.defaultSortDescending(
            label: sortMetric?.label,
            category: sortMetric?.category
        )
    }

    /// Mirrors the Stats tab's sort UI - left-side chip showing the active
    /// metric (tap flips direction), and a magnifying-glass toggle on the right
    /// that expands an inline search row.
    private var sortControlsRow: some View {
        HStack(spacing: 8) {
            Button {
                sortDescending.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Text(sortLabel)
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.ink)
                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GridironPalette.turf)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(GridironPalette.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(GridironPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sorted by \(sortLabel), \(sortDescending ? "highest first" : "lowest first")")
            .accessibilityHint("Tap to flip sort direction")

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
                if !isSearching { searchText = "" }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                let active = isSearching || !searchText.isEmpty
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? .white : GridironPalette.inkSecondary)
                    .frame(width: 30, height: 30)
                    .background(active ? GridironPalette.turf : GridironPalette.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(active ? Color.clear : GridironPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            rosterFiltersMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var sidePicker: some View {
        GridironSegmented(
            segments: RosterSide.allCases.map { .init(value: $0, label: $0.rawValue) },
            selection: $rosterSide
        )
        .onChange(of: rosterSide) { _, side in
            selectedCategory = side.categories[0]
            userSortLabel = nil
        }
    }

    @ViewBuilder
    private var rosterModePicker: some View {
        if supportsRecent {
            GridironSegmented(
                segments: RosterMode.allCases.map {
                    .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 == .recent)
                },
                selection: $rosterMode,
                onLockedTap: { _ in trialTrigger = .recentForm }
            )
        }
    }

    private var rosterFiltersMenu: some View {
        Menu {
            if !availableSortLabels.isEmpty {
                Section("Sort by") {
                    ForEach(availableSortLabels, id: \.self) { label in
                        Button {
                            userSortLabel = label
                            applyDefaultDirectionIfMetricChanged()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            if label == sortMetric?.label {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                }
            }

            Section("Minimum playing time") {
                ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                    Button {
                        qualifierLevel = level
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        let title = "\(level.rawValue) · \(level.description)"
                        if level == qualifierLevel {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }

            Section("Direction") {
                Button {
                    sortDescending = true
                } label: {
                    sortDescending
                        ? Label("Highest first", systemImage: "checkmark")
                        : Label("Highest first", systemImage: "arrow.down")
                }
                Button {
                    sortDescending = false
                } label: {
                    !sortDescending
                        ? Label("Lowest first", systemImage: "checkmark")
                        : Label("Lowest first", systemImage: "arrow.up")
                }
            }
        } label: {
            GridironChip(
                title: "Filters",
                systemImage: "line.3.horizontal.decrease.circle",
                trailing: .chevron,
                isActive: qualifierLevel != .all
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filters")
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            SearchField(text: $searchText, focusOnAppear: true)
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    searchText = ""
                }
            }
            .font(GridironType.small)
            .foregroundStyle(GridironPalette.turf)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var rosterSection: some View {
        VStack(spacing: 0) {
            if players.isEmpty {
                emptyStateView(
                    icon: "person.2.slash",
                    title: "No players tracked",
                    description: "No players are tracked for \(teamFullName(team)) in the \(String(displaySeason)) season."
                )
            } else if filteredPlayers.isEmpty {
                let noCategoryMatch = searchText.isEmpty && selectedCategory != nil
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "No players found",
                    description: noCategoryMatch
                        ? "No players match the selected category for this team."
                        : "Try a different search term."
                )
            } else if isRosterRecent && !hasRecentData {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.75)
                    Text("Loading the last \(rosterWindow.rawValue) games…")
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                Button {
                    sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    LeaderboardTableHeader(
                        sortDescending: sortDescending,
                        sortLabel: isRosterRecent
                            ? "\(sortLabel) · \(rosterWindow.rawValue)G"
                            : sortLabel
                    )
                }
                .buttonStyle(.plain)

                ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player,
                            metricLabel: rowDisplayMetric.label,
                            metricCategory: rowDisplayMetric.category,
                            trendDelta: isRosterRecent ? recentDelta(player) : nil,
                            trendDecimals: rowDisplayMetric.label.map {
                                RecentMetricKey.decimals(for: $0)
                            } ?? 3,
                            valueOverride: isRosterRecent ? recentValueText(player) : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateView(icon: String, title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        }
        .padding(.vertical, 48)
    }

    /// Team name in the nav title doubles as a switcher menu - tap to jump to
    /// any other team without popping back to the Teams list.
    private var teamSwitcherMenu: some View {
        Menu {
            ForEach(allTeams, id: \.self) { abbr in
                NavigationLink(value: TeamDestination(abbr: abbr)) {
                    HStack {
                        Text(teamFullName(abbr))
                        if abbr == team {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(teamFullName(team))
                    .font(GridironType.bodyBold)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Team")
        .accessibilityValue(teamFullName(team))
        .accessibilityHint("Switch to another team")
    }

    private static let allTeamAbbrs: [String] = nflTeamAbbreviations

    private var allTeams: [String] {
        Self.allTeamAbbrs.sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

    /// Season *and* season type, the same one control the Stats / Trends / Teams
    /// bars carry. This was a season-only menu, which left the playoffs
    /// unreachable from the one Teams screen most sessions actually see: every
    /// number on this page is filtered by `selectedPhase`, and the Teams tab
    /// pushes straight into your favorite club on first visit, so the phase
    /// control back on the list was never passed through.
    private func navSeasonMenu(viewModel: DashboardViewModel) -> some View {
        SeasonPhasePicker(
            // A single team page, so no All Time - see
            // `seasonsExcludingAllTime` for why a career row can't be
            // attributed to one franchise.
            seasons: viewModel.seasonsExcludingAllTime,
            selectedSeason: viewModel.selectedSeason,
            selectedPhase: viewModel.selectedPhase,
            isSeasonLocked: { viewModel.isSeasonLocked($0) },
            onSelectSeason: { season in
                if viewModel.isSeasonLocked(season) {
                    trialTrigger = .lockedSeason(season)
                } else {
                    viewModel.selectedSeason = season
                }
            },
            onSelectPhase: { viewModel.selectedPhase = $0 }
        ) {
            // No glyph and the short year alone: the team name in the principal
            // slot is long ("Jacksonville Jaguars"), and spelling the phase out
            // here as well tipped the bar into sweeping the trailing item into a
            // "..." overflow. The pill still says which phase it is, just in the
            // shortest form that reads as a season type.
            GridironNavPill(
                title: SeasonLabel.text(viewModel.selectedSeason)
                    + (viewModel.selectedPhase == .playoffs ? " · Playoffs" : "")
            )
        }
    }

    private func priorityMetrics(for category: MetricCategory) -> [String] {
        switch category {
        case .passing: return ["Pass Yds", "Pass TD", "Rating", "EPA/Play"]
        case .rushing: return ["Rush Yds", "Rush TD", "Y/C", "Rush EPA"]
        case .receiving: return ["Rec Yds", "Rec", "Rec TD", "YAC"]
        case .defense: return ["Tackles", "Sacks", "INT"]
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TeamView(
            team: "KC",
            seedPlayers: SampleData.players.filter { $0.team == "KC" },
            seedSeason: 2025
        )
    }
}
#endif
