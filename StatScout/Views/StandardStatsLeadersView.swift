import SwiftUI

/// Traditional leaderboard with the same position tabs and control vocabulary
/// as the Advanced board.
struct StandardStatsLeadersView: View {
    let players: [Player]
    @Binding var selectedStat: String
    @Binding var selectedPosition: PlayerPositionGroup
    @Binding var sortDescending: Bool
    var season: Int? = nil
    var boardBindings: StatsBoardBindings? = nil
    var viewModel: DashboardViewModel? = nil
    @State private var isSearching = false
    @State private var searchText = ""

    private var availableStats: [String] {
        StandardStatCatalog.stats(for: selectedPosition)
    }

    private var filteredPlayers: [Player] {
        players.filter { player in
            player.positionGroup == selectedPosition
                && numericStat(for: player) != nil
        }
    }

    private var sortedPlayers: [Player] {
        filteredPlayers.sorted { first, second in
            let firstValue = numericStat(for: first) ?? 0
            let secondValue = numericStat(for: second) ?? 0
            if firstValue != secondValue {
                return sortDescending
                    ? firstValue > secondValue
                    : firstValue < secondValue
            }
            return games(for: first) > games(for: second)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            positionSelector
            controlRow
            if isSearching {
                HStack(spacing: 8) {
                    SearchField(text: $searchText, focusOnAppear: true)
                    Button("Cancel") {
                        isSearching = false
                        searchText = ""
                    }
                    .font(RinkType.small)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            ScrollView {
                VStack(spacing: 0) {
                leadersList
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                if let pendingNote {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .semibold))
                        Text(pendingNote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 88)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await viewModel?.load() }
        }
        .background(RinkPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPosition) { _, next in
            guard !StandardStatCatalog.stats(for: next).contains(selectedStat) else {
                return
            }
            selectedStat = StandardStatCatalog.defaultStat(for: next)
            sortDescending = StandardStatCatalog.defaultDescending(
                for: selectedStat,
                position: next
            )
        }
    }

    private var positionSelector: some View {
        PositionTabs(selection: $selectedPosition)
            .padding(.top, 8)
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let boardBindings, let viewModel {
                        StatsBoardStatPicker(
                            viewModel: viewModel,
                            bindings: boardBindings
                        )
                    } else {
                        statMenu
                    }

                    SortDirectionButton(
                        descending: sortDescending,
                        statLabel: selectedStat
                    ) {
                        sortDescending.toggle()
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            Button {
                isSearching.toggle()
                if !isSearching { searchText = "" }
            } label: {
                RinkChip(systemImage: "magnifyingglass", isActive: isSearching)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search players or teams")

            if let boardBindings, let viewModel {
                StatsViewMenu(
                    viewModel: viewModel,
                    board: boardBindings.$board
                )
                .fixedSize()
            }
        }
        .padding(.trailing, 12)
        .frame(height: RinkControl.height + 2)
        .padding(.top, RinkGeo.controlRowGap)
    }

    private var statMenu: some View {
        StatPickerMenu(
            standard: availableStats.map {
                .init(id: $0, label: $0, isSelected: $0 == selectedStat)
            },
            activeLabel: selectedStat,
            onSelectStandard: { option in
                selectedStat = option.id
                sortDescending = StandardStatCatalog.defaultDescending(
                    for: option.id,
                    position: selectedPosition
                )
            }
        )
    }

    private var leadersList: some View {
        LazyVStack(spacing: 0) {
            Button {
                sortDescending.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 0) {
                    Text("RANK")
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .frame(width: 42, alignment: .leading)
                    // Says who is on the list where the list is read. The rule
                    // otherwise lives only in the View menu, and "leaders" with
                    // no minimum on opening night reads like a ranking of the best.
                    Text(sampleLabel)
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("TEAM")
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .frame(width: 44, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(selectedStat.uppercased())
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.turf)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(RinkPalette.turf)
                    }
                    .frame(width: 100, alignment: .trailing)
                }
                .frame(height: RinkGeo.rowHeightHeader)
                .padding(.horizontal, RinkGeo.padInline)
                .background(RinkPalette.surfaceAlt)
                .overlay(
                    Rectangle()
                        .fill(RinkPalette.divider)
                        .frame(height: RinkGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)

            if viewModel?.isLoading == true && players.isEmpty {
                ProgressView("Loading player stats")
                    .padding(.vertical, 48)
            } else if sortedPlayers.isEmpty {
                ContentUnavailableView {
                    Label("No data available", systemImage: "chart.bar")
                } description: {
                    Text("No \(selectedPosition.displayName.lowercased()) have \(selectedStat) data for this season.")
                }
                .padding(.vertical, 48)
                .background(RinkPalette.surface)
            } else {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let ranked = Array(sortedPlayers.enumerated()).filter { _, player in
                    query.isEmpty || player.name.localizedCaseInsensitiveContains(query)
                        || player.team.localizedCaseInsensitiveContains(query)
                        || teamFullName(player.team).localizedCaseInsensitiveContains(query)
                }
                let peerValues = filteredPlayers.compactMap { standardStat(for: $0)?.value }
                if ranked.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.vertical, 24)
                }
                ForEach(ranked, id: \.element.id) { index, player in
                    playerRow(rank: index + 1, player: player, peerValues: peerValues)
                }
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private func playerRow(rank: Int, player: Player, peerValues: [String]) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 0) {
                Text("\(rank)")
                    .font(RinkType.statSmall)
                    .foregroundStyle(RinkPalette.inkSecondary)
                    .frame(width: 36, alignment: .leading)

                HStack(spacing: 10) {
                    PlayerHeadshot(
                        team: player.team,
                        initials: player.initials,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(RinkType.bodyBold)
                            .foregroundStyle(RinkPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .truncationMode(.tail)
                        Text([player.displayPosition, volumeText(for: player)].compactMap { $0 }.joined(separator: " · "))
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    TeamColorDot(abbr: player.team, size: 6)
                    Text(displayTeamAbbr(player.team))
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.inkSecondary)
                }
                .frame(width: 44, alignment: .leading)

                let pct = percentile(for: player, peerValues: peerValues)
                // A zero count has no honest rank; see `Metric.isUnranked`.
                // Not for a lower-is-better count: a skater's 0 PIM is the
                // best line on the board, not an absence.
                let isZero = numericStat(for: player) == 0
                    && StandardStatSemantics.higherIsBetter(label: selectedStat)
                HStack(spacing: 8) {
                    if isZero {
                        Color.clear.frame(width: 34, height: 7)
                    } else {
                        PercentileBarMini(percentile: pct)
                            .frame(width: 34)
                    }
                    Text(statDisplay(for: player))
                        .font(RinkType.statMed)
                        .foregroundStyle(isZero ? RinkPalette.inkTertiary : RinkPalette.turf)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 58, alignment: .trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isZero
                        ? "\(selectedStat): \(statDisplay(for: player)), not ranked"
                        : "\(selectedStat): \(statDisplay(for: player)), \(pct.ordinalString) percentile"
                )
            }
            .frame(height: RinkGeo.rowHeight)
            .padding(.horizontal, RinkGeo.padInline)
            .background(
                rank.isMultiple(of: 2)
                    ? RinkPalette.surfaceAlt
                    : RinkPalette.surface
            )
            .overlay(
                Rectangle()
                    .fill(RinkPalette.divider)
                    .frame(height: RinkGeo.hairline),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }

    /// Case-insensitive on purpose.
    ///
    /// Callers reach this board from several places and one of them displays its
    /// stat names in caps. An exact match meant a casing difference emptied the
    /// whole board and reported it as "no data for this season", which reads as
    /// a fact about the league rather than a mismatch between two strings. The
    /// route now passes the data's own spelling, and this makes a future one
    /// harmless instead of silent.
    private func standardStat(for player: Player) -> StandardStat? {
        player.standardStats?.first {
            $0.label.compare(selectedStat, options: .caseInsensitive) == .orderedSame
        }
    }

    private var sampleLabel: String {
        guard let viewModel else { return "PLAYER" }
        return viewModel.qualifierLevel == .qualified ? "QUALIFIED PLAYERS" : "ALL PLAYERS"
    }

    /// The live season while the NHL summary or MoneyPuck's files are still
    /// catching up: this board is made of the summary's counting stats, and it
    /// should say why a number looks short.
    private var pendingNote: String? {
        guard let viewModel,
              viewModel.selectedSeason == viewModel.freeSeason,
              viewModel.selectedPhase == .regular else { return nil }
        return MetricCoverage.pendingNote(
            shotsStatus: viewModel.dataFreshness?.shotsStatus,
            summaryStatus: viewModel.dataFreshness?.summaryStatus
        )
    }

    /// The volume behind the headline number: games played, and for a rate
    /// stat the ice time or shots behind it. A .940 save percentage means
    /// little over a single start.
    private func volumeText(for player: Player) -> String? {
        let stats = player.standardStats ?? []
        func value(_ label: String) -> String? {
            stats.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }?.value
        }
        let stat = selectedStat.uppercased()
        if ["SV%", "GAA"].contains(stat), let shots = value("SA") {
            return "\(shots) SA"
        }
        if stat == "SH%", let shots = value("SOG") {
            return "\(shots) SOG"
        }
        guard stat != "GP", let games = value("GP") else { return nil }
        return games == "1" ? "1 game" : "\(games) GP"
    }

    private func numericStat(for player: Player) -> Double? {
        guard let stat = standardStat(for: player) else { return nil }
        // Via the shared semantics so a paired value (Cmp/Att, Rec/Tgt) sorts
        // on its rate rather than on the count in front of the slash.
        return StandardStatSemantics.numericValue(label: stat.label, value: stat.value)
    }

    /// Every row on this board has the stat it is ranked by - that is the
    /// filter - so every row can carry a percentile, drawn against the same
    /// position cohort the profile's traditional bars use.
    ///
    /// The cohort is passed in rather than recomputed per row: `filteredPlayers`
    /// walks the whole season pool, and a fifty-row board asking for it twice a
    /// row walked it a hundred times per redraw.
    private func percentile(for player: Player, peerValues: [String]) -> Int {
        guard let stat = standardStat(for: player) else { return 50 }
        return StandardStatSemantics.percentile(
            label: stat.label,
            value: stat.value,
            peerValues: peerValues
        )
    }

    private func statDisplay(for player: Player) -> String {
        standardStat(for: player)?.value ?? "-"
    }

    private func games(for player: Player) -> Double {
        guard let value = player.standardStats?.first(where: {
            $0.label == "GP"
        })?.value else { return 0 }
        return DashboardViewModel.rawNumeric(value) ?? 0
    }
}

/// Standalone traditional-stat drill-down reached from a player or team page.
struct StandardStatsLeaderboardScreen: View {
    let players: [Player]
    var season: Int? = nil
    @State private var stat: String
    @State private var position: PlayerPositionGroup
    @State private var sortDescending: Bool

    init(
        players: [Player],
        initialStat: String = "P",
        initialPosition: PlayerPositionGroup = .forward,
        season: Int? = nil
    ) {
        self.players = players
        self.season = season
        _stat = State(initialValue: initialStat)
        _position = State(initialValue: initialPosition)
        _sortDescending = State(
            initialValue: StandardStatCatalog.defaultDescending(
                for: initialStat,
                position: initialPosition
            )
        )
    }

    var body: some View {
        StandardStatsLeadersView(
            players: players,
            selectedStat: $stat,
            selectedPosition: $position,
            sortDescending: $sortDescending,
            season: season
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StandardStatsLeaderboardScreen(players: SampleData.players)
            .environmentObject(StoreService.shared)
            .navigationTitle("Standard Stats")
    }
}
#endif
