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
            "G", "Cmp/Att", "Pass Yds", "Pass TD", "INT",
            "Car", "Rush Yds", "Rush TD", "Rec/Tgt", "Rec Yds", "Rec TD",
            "Tackles", "Sacks", "Def INT",
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
                                colors: [.clear, GridironPalette.canvas.opacity(0.9)],
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
                            .font(GridironType.cardTitle)
                            .foregroundStyle(GridironPalette.ink)

                        Text("StatScout+ unlocks side-by-side player comparisons across every metric. See who leads in EPA, passing efficiency, separation, and more.")
                            .font(GridironType.small)
                            .foregroundStyle(GridironPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            showingTrial = true
                        } label: {
                            Text(store.paywallBlurCTA)
                                .font(GridironType.bodyBold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(GridironPalette.turf)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        if let subtext = store.paywallBlurSubtext {
                            Text(subtext)
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.inkTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                            .fill(GridironPalette.surface)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(GridironPalette.divider)
                            .frame(height: GridironGeo.hairline)
                    }
                    .offset(y: -8)
                }
                .background(GridironPalette.canvas.ignoresSafeArea())
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
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.turf)
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
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationTitle("Player Comparison")
        .navigationBarTitleDisplayMode(.inline)
        // Match the midnight bar on the profile it is pushed from. The stack's
        // dark toolbar scheme otherwise draws white status text on the canvas.
        .toolbarBackground(GridironPalette.midnight, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var standardStatsCard: some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: "SEASON TOTALS")

            HStack(spacing: 8) {
                Text("STAT")
                    .frame(width: 82, alignment: .leading)
                Text(a.name.split(separator: " ").last.map(String.init) ?? "A")
                    .frame(maxWidth: .infinity)
                Text(b.name.split(separator: " ").last.map(String.init) ?? "B")
                    .frame(maxWidth: .infinity)
            }
            .font(GridironType.micro)
            .foregroundStyle(GridironPalette.inkTertiary)
            .frame(height: GridironGeo.rowHeightHeader)
            .padding(.horizontal, GridironGeo.padInline)
            .background(GridironPalette.surfaceAlt)

            ForEach(Array(standardComparison.enumerated()), id: \.element.label) { index, item in
                let winner = StandardStatSemantics.winner(
                    label: item.label,
                    left: item.a,
                    right: item.b
                )
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.ink)
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
                .frame(height: GridironGeo.rowHeight)
                .padding(.horizontal, GridironGeo.padInline)
                .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
                .overlay(
                    Rectangle()
                        .fill(GridironPalette.divider)
                        .frame(height: GridironGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
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
                .font(GridironType.statMed)
                .foregroundStyle(
                    value == nil
                        ? GridironPalette.inkTertiary
                        : (isWinner ? GridironPalette.turf : GridironPalette.inkSecondary)
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
                        .foregroundStyle(GridironPalette.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(GridironPalette.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(GridironPalette.hairline, lineWidth: 0.5))
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
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(displayTeamAbbr(player.team)) · \(player.displayPosition)")
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
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
                    GridironInlinePill(
                        systemImage: nil,
                        title: "\(player.season.map(SeasonLabel.text) ?? "-") · \(player.seasonPhase.label)",
                        compressible: true
                    )
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Season and season type for \(player.name)")

                Button {
                    picker = target
                } label: {
                    GridironInlinePill(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Change"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change \(target == .a ? "first" : "second") player")
            } else if let season = player.season {
                Text(SeasonLabel.text(season))
                    .font(GridironType.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(GridironPalette.midnight)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
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
                : "No \(SeasonLabel.text(season)) \(phase.label.lowercased()) data for \(current.name)."
            Task { await catalog.loadHistory?() }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func categoryCard(category: MetricCategory, metrics: [(label: String, a: Metric?, b: Metric?)]) -> some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: category.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(width: 72, alignment: .leading)
                Text(a.name.split(separator: " ").last.map(String.init) ?? "A")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(b.name.split(separator: " ").last.map(String.init) ?? "B")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: GridironGeo.rowHeightHeader)
            .padding(.horizontal, GridironGeo.padInline)
            .background(GridironPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.ink)
                        .frame(width: 72, alignment: .leading)

                    metricValueCell(metric: item.a, other: item.b)
                    metricValueCell(metric: item.b, other: item.a)
                }
                .frame(height: 60)
                .padding(.horizontal, GridironGeo.padInline)
                .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private func metricValueCell(metric: Metric?, other: Metric?) -> some View {
        Group {
            if let m = metric, m.percentile > 0 || !m.value.isEmpty {
                let hasValue = !m.value.isEmpty
                let comparable = other.map { $0.percentile > 0 || !$0.value.isEmpty } ?? false
                let isWinner = comparable && (other.map { m.percentile > $0.percentile } ?? false)
                let pctTextColor = GridironPalette.textColor(forPercentile: m.percentile)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if isWinner {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                                .accessibilityHidden(true)
                        }
                        Text(hasValue ? m.value : "\(m.percentile)")
                            .font(GridironType.statMed)
                            .foregroundStyle(pctTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(hasValue ? "" : "PERCENTILE")
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
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
                    .font(GridironType.statSmall)
                    .foregroundStyle(GridironPalette.inkTertiary)
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
