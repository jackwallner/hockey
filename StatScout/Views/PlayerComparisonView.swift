import SwiftUI

struct ComparisonRoute: Hashable, Identifiable {
    let playerA: Player
    let playerB: Player
    var id: String { "\(playerA.id)-vs-\(playerB.id)" }
}

struct ComparisonCatalog {
    var seasons: [Int] = []
    var defaultPhase: SeasonPhase = .regular
    var roster: (Int, SeasonPhase) -> [Player] = { _, _ in [] }
    var resolve: (Player, Int, SeasonPhase) -> Player? = { player, season, phase in
        player.season == season && player.seasonPhase == phase ? player : nil
    }
    var isSeasonLocked: (Int) -> Bool = { _ in false }
    var isLoadingHistory: Bool = false
    var loadHistory: (() async -> Void)? = nil

    init(
        seasons: [Int] = [],
        defaultPhase: SeasonPhase = .regular,
        roster: @escaping (Int, SeasonPhase) -> [Player] = { _, _ in [] },
        resolve: @escaping (Player, Int, SeasonPhase) -> Player? = { player, season, phase in
            player.season == season && player.seasonPhase == phase ? player : nil
        },
        isSeasonLocked: @escaping (Int) -> Bool = { _ in false },
        isLoadingHistory: Bool = false,
        loadHistory: (() async -> Void)? = nil
    ) {
        self.seasons = seasons
        self.defaultPhase = defaultPhase
        self.roster = roster
        self.resolve = resolve
        self.isSeasonLocked = isSeasonLocked
        self.isLoadingHistory = isLoadingHistory
        self.loadHistory = loadHistory
    }

    @MainActor
    init(
        viewModel: DashboardViewModel,
        defaultPhase: SeasonPhase? = nil
    ) {
        let phase = defaultPhase ?? viewModel.selectedPhase
        self.init(
            seasons: viewModel.availableSeasons,
            defaultPhase: phase,
            roster: { season, phase in
                viewModel.players(forSeason: season, phase: phase)
                    .sorted { $0.name < $1.name }
            },
            resolve: { player, season, phase in
                if player.season == season,
                   player.seasonPhase == phase {
                    return player
                }
                return viewModel.playerHistories[player.playerId]?.first {
                    $0.season == season && $0.seasonPhase == phase
                }
            },
            isSeasonLocked: { viewModel.isSeasonLocked($0) },
            isLoadingHistory: viewModel.isHistoricalLoading,
            loadHistory: { await viewModel.loadHistoricalIfNeeded() }
        )
    }
}

struct PlayerComparisonView: View {
    @EnvironmentObject private var store: StoreService
    let playerA: Player
    let playerB: Player
    var catalog: ComparisonCatalog? = nil

    private enum PickerTarget: Identifiable {
        case a, b
        var id: Int { hashValue }
    }

    @State private var showingTrial = false
    @State private var overrideA: Player?
    @State private var overrideB: Player?
    @State private var picker: PickerTarget?
    @State private var note: String?

    private var a: Player { overrideA ?? playerA }
    private var b: Player { overrideB ?? playerB }

    private var comparisonMetrics: [(label: String, category: MetricCategory, a: Metric?, b: Metric?)] {
        var seen = Set<String>()
        var result: [(label: String, category: MetricCategory, a: Metric?, b: Metric?)] = []
        let allMetrics = a.metrics + b.metrics
        for metric in allMetrics {
            let key = "\(metric.label)|\(metric.category.rawValue)"
            guard seen.insert(key).inserted else { continue }
            let left = a.metrics.first { $0.label == metric.label && $0.category == metric.category }
            let right = b.metrics.first { $0.label == metric.label && $0.category == metric.category }
            result.append((metric.label, metric.category, left, right))
        }
        return result.sorted { $0.category == $1.category
            ? $0.category.sortMetrics($0.label, $1.label)
            : MetricCategory.allCases.firstIndex(of: $0.category)! < MetricCategory.allCases.firstIndex(of: $1.category)!
        }
    }

    private var groupedComparison: [(MetricCategory, [(label: String, a: Metric?, b: Metric?)])] {
        let grouped = Dictionary(grouping: comparisonMetrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            let mapped = items.map { (label: $0.label, a: $0.a, b: $0.b) }
            return (cat, mapped)
        }
    }

    private var standardComparison: [(label: String, a: String?, b: String?)] {
        let left = Dictionary(
            uniqueKeysWithValues: (a.standardStats ?? []).map { ($0.label, $0.value) }
        )
        let right = Dictionary(
            uniqueKeysWithValues: (b.standardStats ?? []).map { ($0.label, $0.value) }
        )
        let preferredOrder = [
            "GP", "G", "A", "P", "+/-", "PIM", "PPG", "PPP", "SHG", "GWG", "SOG",
            "Sh%", "TOI/GP", "Hits", "Blk", "FO%",
            "GS", "W", "L", "OT", "GAA", "SV%", "SO", "SA", "SV",
        ]
        return Set(left.keys).union(right.keys)
            .sorted {
                let first = preferredOrder.firstIndex(of: $0) ?? preferredOrder.count
                let second = preferredOrder.firstIndex(of: $1) ?? preferredOrder.count
                return first == second ? $0 < $1 : first < second
            }
            .map { (label: $0, a: left[$0], b: right[$0]) }
    }

    var body: some View {
        Group {
            if store.isPro {
                comparisonContent
            } else {
                ZStack(alignment: .bottom) {
                    comparisonContent
                        .blur(radius: 8)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, RinkPalette.canvas.opacity(0.9)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .clipped()

                    // CTA overlay
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.yellow)

                        Text("Find the Edge")
                            .font(RinkType.cardTitle)
                            .foregroundStyle(RinkPalette.ink)

                        Text("StatScout+ unlocks side-by-side player comparisons across every metric. See who leads in ixG, xGF%, GSAx, and more.")
                            .font(RinkType.small)
                            .foregroundStyle(RinkPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            showingTrial = true
                        } label: {
                            Text(store.paywallBlurCTA)
                                .font(RinkType.bodyBold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(RinkPalette.turf)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        if let subtext = store.paywallBlurSubtext {
                            Text(subtext)
                                .font(RinkType.micro)
                                .foregroundStyle(RinkPalette.inkTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                            .fill(RinkPalette.surface)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(RinkPalette.divider)
                            .frame(height: RinkGeo.hairline)
                    }
                    .offset(y: -8)
                }
                .background(RinkPalette.canvas.ignoresSafeArea())
                .sheet(isPresented: $showingTrial) {
                    TrialPitchSheet(trigger: .playerComparison)
                }
            }
        }
        .onAppear {
            if store.isPro {
                ReviewPromptTracker.recordPositiveMoment()
            }
        }
        .sheet(item: $picker) { target in
            if let catalog {
                let side = target == .a ? a : b
                let other = target == .a ? b : a
                ComparePlayerPicker(
                    players: catalog.roster(
                        side.season ?? 0,
                        side.seasonPhase
                    ).filter {
                        (
                            $0.playerId != other.playerId
                                || $0.season != other.season
                                || $0.seasonPhase != other.seasonPhase
                        )
                            && $0.canCompareHeadToHead(with: other)
                    },
                    season: side.season,
                    isLoading: catalog.isLoadingHistory
                ) { selected in
                    note = nil
                    if target == .a {
                        overrideA = selected
                    } else {
                        overrideB = selected
                    }
                }
            }
        }
    }

    private var comparisonContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                playerHeadlines
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if let note {
                    Text(note)
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.turf)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }

                if comparisonMetrics.isEmpty && standardComparison.isEmpty {
                    ContentUnavailableView {
                        Label("No comparable stats", systemImage: "chart.bar")
                    } description: {
                        Text("These players don't share any standard or advanced stats.")
                    }
                    .padding(.vertical, 48)
                } else {
                    if !standardComparison.isEmpty {
                        standardStatsCard
                            .padding(.horizontal, 12)
                    }
                    ForEach(groupedComparison, id: \.0) { category, metrics in
                        categoryCard(category: category, metrics: metrics)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RinkPalette.canvas.ignoresSafeArea())
        .navigationTitle("Player Comparison")
        .navigationBarTitleDisplayMode(.inline)
        // Match the midnight bar on the profile it is pushed from. The stack's
        // dark toolbar scheme otherwise draws white status text on the canvas.
        .toolbarBackground(RinkPalette.midnight, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var standardStatsCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "SEASON TOTALS")

            HStack(spacing: 8) {
                Text("STAT")
                    .frame(width: 82, alignment: .leading)
                Text(a.name.split(separator: " ").last.map(String.init) ?? "A")
                    .frame(maxWidth: .infinity)
                Text(b.name.split(separator: " ").last.map(String.init) ?? "B")
                    .frame(maxWidth: .infinity)
            }
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
            .frame(height: RinkGeo.rowHeightHeader)
            .padding(.horizontal, RinkGeo.padInline)
            .background(RinkPalette.surfaceAlt)

            ForEach(Array(standardComparison.enumerated()), id: \.element.label) { index, item in
                let winner = StandardStatSemantics.winner(
                    label: item.label,
                    left: item.a,
                    right: item.b
                )
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(RinkType.smallBold)
                        .foregroundStyle(RinkPalette.ink)
                        .frame(width: 82, alignment: .leading)
                    aggregateValue(item.a, isWinner: winner == .left)
                    aggregateValue(item.b, isWinner: winner == .right)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    standardRowAccessibilityLabel(
                        label: item.label,
                        left: item.a,
                        right: item.b,
                        winner: winner
                    )
                )
                .frame(height: RinkGeo.rowHeight)
                .padding(.horizontal, RinkGeo.padInline)
                .background(index.isMultiple(of: 2) ? RinkPalette.surface : RinkPalette.surfaceAlt)
                .overlay(
                    Rectangle()
                        .fill(RinkPalette.divider)
                        .frame(height: RinkGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    /// Spoken form of one standard-totals row: both numbers and who leads,
    /// because the trophy that carries that on screen is decoration and is
    /// hidden from VoiceOver.
    private func standardRowAccessibilityLabel(
        label: String,
        left: String?,
        right: String?,
        winner: StandardStatSemantics.Winner?
    ) -> String {
        let leftName = a.name
        let rightName = b.name
        var parts = [
            "\(label): \(leftName) \(left ?? "no data"), \(rightName) \(right ?? "no data")"
        ]
        switch winner {
        case .left: parts.append("\(leftName) leads")
        case .right: parts.append("\(rightName) leads")
        case nil: break
        }
        return parts.joined(separator: ", ")
    }

    private func aggregateValue(_ value: String?, isWinner: Bool) -> some View {
        HStack(spacing: 4) {
            if isWinner {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .accessibilityHidden(true)
            }
            Text(value ?? "-")
                .font(RinkType.statMed)
                .foregroundStyle(
                    value == nil
                        ? RinkPalette.inkTertiary
                        : (isWinner ? RinkPalette.turf : RinkPalette.inkSecondary)
                )
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var playerHeadlines: some View {
        HStack(alignment: .top, spacing: 8) {
            playerSummaryCard(player: a, target: .a)
            if catalog != nil {
                Button {
                    let left = a
                    let right = b
                    overrideA = right
                    overrideB = left
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RinkPalette.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(RinkPalette.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(RinkPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 44)
                .accessibilityLabel("Swap sides")
            }
            playerSummaryCard(player: b, target: .b)
        }
    }

    private func playerSummaryCard(player: Player, target: PickerTarget) -> some View {
        VStack(spacing: 8) {
            NavigationLink(value: player) {
                VStack(spacing: 6) {
                    PlayerHeadshot(team: player.team, initials: player.initials, size: 56)
                    Text(player.name)
                        .font(RinkType.smallBold)
                        .foregroundStyle(RinkPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(displayTeamAbbr(player.team)) · \(player.displayPosition)")
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(player.name)'s page")

            if let catalog {
                SeasonPhasePicker(
                    seasons: catalog.seasons,
                    selectedSeason: player.season ?? 0,
                    selectedPhase: player.seasonPhase,
                    isSeasonLocked: { catalog.isSeasonLocked($0) },
                    onSelectSeason: { season in
                        if catalog.isSeasonLocked(season) {
                            showingTrial = true
                        } else {
                            move(
                                target,
                                to: season,
                                phase: player.seasonPhase,
                                catalog: catalog
                            )
                        }
                    },
                    onSelectPhase: { phase in
                        move(
                            target,
                            to: player.season ?? 0,
                            phase: phase,
                            catalog: catalog
                        )
                    }
                ) {
                    RinkInlinePill(
                        systemImage: nil,
                        title: "\(player.season.map(SeasonLabel.display) ?? "-") · \(player.seasonPhase.label)",
                        compressible: true
                    )
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Season and season type for \(player.name)")

                Button {
                    picker = target
                } label: {
                    RinkInlinePill(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Change"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change \(target == .a ? "first" : "second") player")
            } else if let season = player.season {
                Text(SeasonLabel.display(season))
                    .font(RinkType.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RinkPalette.midnight)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private func move(
        _ target: PickerTarget,
        to season: Int,
        phase: SeasonPhase,
        catalog: ComparisonCatalog
    ) {
        let current = target == .a ? a : b
        if let resolved = catalog.resolve(current, season, phase) {
            if target == .a {
                overrideA = resolved
            } else {
                overrideB = resolved
            }
            note = nil
        } else {
            note = catalog.isLoadingHistory
                ? "Loading past seasons…"
                : "No \(SeasonLabel.display(season)) \(phase.label.lowercased()) data for \(current.name)."
            Task { await catalog.loadHistory?() }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func categoryCard(category: MetricCategory, metrics: [(label: String, a: Metric?, b: Metric?)]) -> some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: category.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(width: 72, alignment: .leading)
                Text(a.name.split(separator: " ").last.map(String.init) ?? "A")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(b.name.split(separator: " ").last.map(String.init) ?? "B")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: RinkGeo.rowHeightHeader)
            .padding(.horizontal, RinkGeo.padInline)
            .background(RinkPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(RinkType.smallBold)
                        .foregroundStyle(RinkPalette.ink)
                        .frame(width: 72, alignment: .leading)

                    metricValueCell(metric: item.a, other: item.b)
                    metricValueCell(metric: item.b, other: item.a)
                }
                .frame(height: 60)
                .padding(.horizontal, RinkGeo.padInline)
                .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private func metricValueCell(metric: Metric?, other: Metric?) -> some View {
        Group {
            if let m = metric, m.percentile > 0 || !m.value.isEmpty {
                let hasValue = !m.value.isEmpty
                let comparable = other.map { $0.percentile > 0 || !$0.value.isEmpty } ?? false
                // A tie on the number shown is a tie, whatever the percentiles say.
                let sameShown = hasValue && other?.value == m.value
                let isWinner = comparable && !sameShown && (other.map { m.percentile > $0.percentile } ?? false)
                let pctTextColor = RinkPalette.textColor(forPercentile: m.percentile)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if isWinner {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                                .accessibilityHidden(true)
                        }
                        Text(hasValue ? m.value : "\(m.percentile)")
                            .font(RinkType.statMed)
                            .foregroundStyle(pctTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(hasValue ? "" : "PERCENTILE")
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .frame(height: 10)
                    // The same track-and-fill bar the boards and the profile
                    // use. The hand-rolled rectangle this replaces had no
                    // track, so a low percentile read as a missing bar, and
                    // its `max(8, …)` floor drew a 1st percentile as wide as
                    // a 13th.
                    PercentileBarMini(percentile: m.percentile, height: 5)
                        .frame(maxWidth: 60)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    hasValue
                        ? "\(m.value), \(m.percentile.ordinalString) percentile"
                        : "\(m.percentile.ordinalString) percentile"
                )
            } else {
                Text("-")
                    .font(RinkType.statSmall)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerComparisonView(
            playerA: SampleData.players.first!,
            playerB: SampleData.players.last!
        )
        .environmentObject(StoreService.shared)
    }
}
#endif
