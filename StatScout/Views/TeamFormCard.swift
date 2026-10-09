import SwiftUI

/// Team "percentile rankings" card - the team-level analogue of the player
/// profile's percentile card. Aggregates the roster into one synthetic
/// "team-as-a-player" and renders its profile as percentile bars on the league
/// ruler, with a Season / Recent toggle that mirrors the player page:
///
/// - **Season**: mean of every roster metric for the active cohort (forwards,
///   defensemen or goalies), placed on the league curve. Tapping a bar opens
///   that metric's leaderboard.
/// - **Recent**: the rate metrics rebuilt over the last 2 / 4 / 8 weeks of game
///   logs. Pro-gated with the standard blur + CTA, identical to the player card.
///
/// This replaces the old split between a season "team average" card and a
/// separate "team recent form" card, which read as two disconnected modules.
struct TeamRankingsCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    /// Which half of the year the roster's numbers come from. The rolling window
    /// is built from game logs, and those have to be filtered to the same phase
    /// the season bars are showing - a playoff club's five most recent games are
    /// its playoff games, so an unfiltered window put June playoff hockey under a
    /// "Regular Season" heading.
    var seasonPhase: SeasonPhase = .regular
    /// The roster for this team/season.
    let players: [Player]
    /// League pool used to build the value→percentile curve so the team bar sits
    /// on the same ruler as individual players' bars. Filtered per side at
    /// curve-build time.
    let leaguePlayers: [Player]
    /// (team, season, phase, since).
    let fetchTeamGameLogs: ((String, Int, SeasonPhase, Date) async throws -> [PlayerGameLog])?
    /// Changes after a validated publisher revision, so a retained team page
    /// cannot keep showing logs from the previous game set.
    var freshnessRevision: String? = nil
    var freshnessStatus: DataFreshnessStatus? = nil
    /// False on a historical season: rolling windows are built from per-game
    /// logs, and those are only kept for the live season now, so Recent/Both
    /// are hidden rather than offered and left to come back empty.
    var supportsRecent: Bool = true
    let onUpgradeTap: () -> Void

    @State private var side: PlayerPositionGroup = .forward
    @State private var mode: Mode = .season
    @State private var windowWeeks: Int = 4
    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var curves: LeaguePercentileCurves?

    enum Mode: String, CaseIterable, Identifiable {
        case season = "Season", recent = "Recent", both = "Both"
        var id: String { rawValue }
        var usesRecent: Bool { self != .season }
    }

    /// The mode actually rendered. `mode` is view state and the season is a
    /// parameter, so a user who picked Recent on the live season and then walked
    /// back to 2018 would otherwise sit in front of a permanently empty window.
    private var effectiveMode: Mode { supportsRecent ? mode : .season }

    /// Smallest team-window ice time (minutes) we'll treat as trustworthy -
    /// below this we flag the window as a small sample.
    private let smallSamplePlaysThreshold = 200

    var body: some View {
        VStack(spacing: 0) {
            RinkSectionBar(
                title: "TEAM ADVANCED STATS",
                trailing: store.isPro ? nil : AnyView(proBadge)
            )

            RinkPickerRow {
                sidePicker.segmentCount(PlayerPositionGroup.allCases.count)
                modePicker.segmentCount(Mode.allCases.count)
            }
            .padding(.horizontal, RinkGeo.padInline)
            .padding(.vertical, 8)
            .background(RinkPalette.surfaceAlt)

            if effectiveMode.usesRecent {
                windowPicker
            }

            switch effectiveMode {
            case .season: seasonBars
            case .recent: recentSection
            case .both: bothSection
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(seasonPhase.rawValue)-\(effectiveMode.rawValue)-\(store.isPro)-\(freshnessRevision ?? "none")") {
            if effectiveMode.usesRecent, store.isPro { await load() }
        }
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
        .onChange(of: side) { _, _ in rebuildCurves() }
    }

    private var proBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
            Text("STATSCOUT+")
                .font(RinkType.micro)
                .fontWeight(.bold)
        }
        .foregroundStyle(RinkPalette.midnight)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.yellow)
        .clipShape(Capsule())
    }

    // MARK: - Pickers

    private var sidePicker: some View {
        RinkSegmented(
            segments: PlayerPositionGroup.allCases.map { .init(value: $0, label: $0.pickerLabel) },
            selection: $side
        )
    }

    @ViewBuilder
    private var modePicker: some View {
        if supportsRecent {
            RinkSegmented(
                segments: Mode.allCases.map {
                    .init(
                        value: $0,
                        label: $0.rawValue,
                        isLocked: !store.isPro && $0 != .season
                    )
                },
                selection: $mode,
                onLockedTap: { _ in onUpgradeTap() }
            )
        }
    }

    private var bothSection: some View {
        let seasonRows = aggregateSeasonRows()
        let recentRows: [String: Metric] = {
            guard let window = recentWindow else { return [:] }
            let pairs = seasonRows.compactMap { row -> (String, Metric)? in
                guard let recent = recentMetric(
                    forSeasonLabel: row.label,
                    window: window
                ) else { return nil }
                return (row.label, recent)
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }()

        return VStack(spacing: 0) {
            if loading {
                loadingRow
            } else if let loadError {
                InlineLoadError(message: loadError) { await load() }
            } else {
                ForEach(Array(seasonRows.enumerated()), id: \.element.id) { index, metric in
                    DualMetricBar(
                        season: metric,
                        recent: recentRows[metric.label],
                        recentCaption: "Last \(windowWeeks)W"
                    )
                    .padding(.horizontal, RinkGeo.padCard)
                    .padding(.vertical, 10)
                    .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.75)
            Text("Loading recent games…")
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var windowPicker: some View {
        RinkSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: Binding(
                get: { RecentWindow(rawValue: windowWeeks) ?? .four },
                set: { windowWeeks = $0.rawValue }
            )
        )
        .padding(.horizontal, RinkGeo.padInline)
        .padding(.bottom, 8)
        .background(RinkPalette.surfaceAlt)
    }

    // MARK: - Season

    @ViewBuilder
    private var seasonBars: some View {
        let rows = aggregateSeasonRows()
        if rows.isEmpty {
            emptyAggregate
        } else {
            RinkSubSectionBar(title: side.displayName.uppercased())

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                    NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
                        MetricBar(metric: metric)
                            .padding(.horizontal, RinkGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                            .overlay(
                                Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                                alignment: .bottom
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("See the league leaderboard for \(metric.label)")
                }
            }

            weightedCaption
        }
    }

    /// One bar per roster metric - roster mean placed on the league curve. Each
    /// bar keeps its own metric category (Scoring / Shot Quality / Play
    /// Driving / Goaltending) so the leaderboard link routes correctly.
    private func aggregateSeasonRows() -> [Metric] {
        let cats = side.categories
        let pool = players.filter { $0.positionGroup == side }
        guard !pool.isEmpty, let curves else { return [] }

        // Ordered (label, category) pairs present on the roster.
        var pairs: [(label: String, category: MetricCategory)] = []
        var seen = Set<String>()
        for cat in cats {
            let present = Set(pool.flatMap { p in p.metrics.filter { $0.category == cat }.map(\.label) })
            for label in cat.metricPriorityOrder where present.contains(label) {
                if seen.insert(label).inserted { pairs.append((label, cat)) }
            }
        }

        return pairs.compactMap { pair -> Metric? in
            var sum = 0.0
            var count = 0.0
            for player in pool {
                guard let m = player.metrics.first(where: { $0.label == pair.label && $0.category == pair.category }),
                      let v = DashboardViewModel.rawNumeric(m.value) else { continue }
                sum += v
                count += 1
            }
            guard count > 0 else { return nil }
            let avg = sum / count
            guard let pct = curves.curve(for: pair.label)?.percentile(for: avg) else { return nil }
            return Metric(
                id: "teamavg-\(pair.label)",
                label: pair.label,
                value: formattedValue(avg, label: pair.label),
                percentile: pct,
                category: pair.category
            )
        }
    }

    private func formattedValue(_ v: Double, label: String) -> String {
        if label.hasSuffix("SV%") { return RecentMetricKey.savePercentage(v) }
        if label.hasSuffix("%") { return String(format: "%.1f%%", v) }
        if abs(v) >= 100 { return String(format: "%.0f", v) }
        return String(format: "%.\(max(RecentMetricKey.decimals(for: label), 1))f", v)
    }

    // MARK: - Recent

    private var sideLogs: [PlayerGameLog] {
        let onSide = logs.filter { $0.playerType.lowercased() == side.rawValue.lowercased() }
        return RecentFormWindow.logs(onSide, weeks: windowWeeks)
    }

    private var recentWindow: RecentFormWindow? {
        guard !sideLogs.isEmpty else { return nil }
        return RecentFormWindow.build(label: "Last \(windowWeeks) weeks", span: windowWeeks, logs: sideLogs)
    }

    /// Distinct game dates in the window: the club's games, not player rows.
    private var teamGames: Int {
        Set(sideLogs.map { Calendar.current.startOfDay(for: $0.gameDate) }).count
    }

    @ViewBuilder
    private var recentSection: some View {
        if store.isPro {
            recentBars
        } else {
            ZStack(alignment: .bottom) {
                recentTeaser
                    .blur(radius: 8)
                    .disabled(true)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See every team's last 2 / 4 / 8 week form",
                    trigger: .teamView
                )
            }
        }
    }

    /// Static, non-fetching preview for free users - illustrative team bars in
    /// the recent-form layout. No game logs are fetched (no network/battery cost)
    /// and no real team data is shown, so the blur can't be read through to leak
    /// the actual recent numbers.
    private var recentTeaser: some View {
        let sample: [Metric] = side == .goalie
            ? [
                Metric(id: "tt_sv", label: "SV%", value: ".918", percentile: 84, category: .goaltending),
                Metric(id: "tt_gsax", label: "GSAx/60", value: "0.21", percentile: 77, category: .goaltending),
                Metric(id: "tt_gaa", label: "GAA", value: "2.48", percentile: 71, category: .goaltending),
                Metric(id: "tt_hd", label: "HD SV%", value: ".842", percentile: 66, category: .goaltending),
            ]
            : [
                Metric(id: "tt_p60", label: "P/60", value: "2.41", percentile: 84, category: .scoring),
                Metric(id: "tt_ixg", label: "ixG/60", value: "0.88", percentile: 77, category: .shotQuality),
                Metric(id: "tt_sh60", label: "Shots/60", value: "11.9", percentile: 71, category: .shotQuality),
                Metric(id: "tt_shp", label: "Sh%", value: "10.4%", percentile: 66, category: .scoring),
            ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "GP", value: "7")
                summaryStat(label: "TOI", value: "1,420")
                summaryStat(label: side == .goalie ? "SA" : "Shot Att", value: side == .goalie ? "198" : "412")
                Spacer(minLength: 0)
            }
            .padding(RinkGeo.padInline)

            RinkSubSectionBar(title: side.displayName.uppercased())
            VStack(spacing: 0) {
                ForEach(Array(sample.enumerated()), id: \.element.id) { index, metric in
                    MetricBar(metric: metric)
                        .padding(.horizontal, RinkGeo.padCard)
                        .padding(.vertical, 12)
                        .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                            alignment: .bottom
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var recentBars: some View {
        if loading {
            loadingRow
        } else if let err = loadError {
            InlineLoadError(message: err) { await load() }
        } else if let w = recentWindow {
            recentSummaryRow(w)
            let rows = recentDisplayRows(window: w)
            if !rows.isEmpty {
                RinkSubSectionBar(title: side.displayName.uppercased())
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                        MetricBar(metric: metric)
                            .padding(.horizontal, RinkGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                            .overlay(
                                Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                                alignment: .bottom
                            )
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(RinkPalette.inkTertiary)
                Text(emptyStateText)
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private var emptyStateText: String {
        switch freshnessStatus {
        case .pending, .partial, .checking:
            return "Recent team data is still arriving"
        case .offline, .failed:
            return "Recent team data is unavailable right now"
        default:
            return "No \(side.displayName.lowercased()) data in the last \(windowWeeks) weeks"
        }
    }

    private func recentSummaryRow(_ w: RecentFormWindow) -> some View {
        HStack(spacing: 12) {
            summaryStat(label: "GP", value: "\(teamGames)")
            summaryStat(label: "TOI", value: w.plays.formatted(.number.grouping(.automatic)))
            summaryStat(label: side == .goalie ? "SA" : "Shot Att", value: "\(w.touches)")
            Spacer(minLength: 0)
            if w.plays < smallSamplePlaysThreshold {
                Text("SMALL SAMPLE")
                    .font(RinkType.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RinkPalette.inkTertiary)
                    .clipShape(Capsule())
            }
        }
        .padding(RinkGeo.padInline)
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
            Text(value)
                .font(RinkType.bodyBold)
                .foregroundStyle(RinkPalette.ink)
        }
    }

    /// The metric category a season label belongs to.
    private func category(forLabel label: String) -> MetricCategory {
        for cat in side.categories where cat.metricPriorityOrder.contains(label) {
            return cat
        }
        return side.primaryCategory
    }

    /// Recent mode mirrors the season list: every season aggregate bar is shown.
    /// Metrics the window can rebuild render the recent value (re-placed on the
    /// league curve); the rest fall back to their season aggregate bar.
    private func recentDisplayRows(window w: RecentFormWindow) -> [Metric] {
        aggregateSeasonRows().map { recentMetric(forSeasonLabel: $0.label, window: w) ?? $0 }
    }

    /// The recent-window bar for a given season label, or nil if the window
    /// cannot rebuild it (caller falls back to the season aggregate bar).
    private func recentMetric(forSeasonLabel label: String, window w: RecentFormWindow) -> Metric? {
        guard let v = w.value(forSeasonLabel: label),
              let pct = curves?.curve(for: label)?.percentile(for: v) else { return nil }
        return Metric(
            id: "team-recent-\(label)",
            label: label,
            value: RecentMetricKey.format(v, label: label),
            percentile: pct,
            category: category(forLabel: label)
        )
    }

    private func load() async {
        // Free users see a static teaser - never fetch real team game logs.
        guard store.isPro, let fetch = fetchTeamGameLogs else { return }
        loading = true
        loadError = nil
        do {
            // Pull a wide window (the last ~120 days of the season) so the client
            // can slice the most recent 2 / 4 / 8 weeks out of it. Anchored to the
            // season's own end, not to today - see `gameLogWindowStart`.
            let since = StatScoutSeason.gameLogWindowStart(season: season)
            logs = try await fetch(team, season, seasonPhase, since)
        } catch {
            if !isTaskCancellation(error) {
                loadError = "Couldn't load team form. Check your connection and try again."
            }
        }
        loading = false
    }

    // MARK: - Shared bits

    private var emptyAggregate: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22))
                .foregroundStyle(RinkPalette.inkTertiary)
            Text(players.isEmpty
                 ? "No games played yet this season"
                 : "Not enough \(side.displayName.lowercased()) data to aggregate")
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var weightedCaption: some View {
        Text("Season to date, averaged across the \(side.displayName.lowercased()) on the roster")
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RinkGeo.padCard)
            .padding(.vertical, 10)
    }

    private func rebuildCurves() {
        let rosterLabels = players.flatMap { $0.metrics.map(\.label) }
        let recentLabels = side.categories.flatMap { $0.metricPriorityOrder }
        let labels = Array(Set(rosterLabels + recentLabels))
        curves = LeaguePercentileCurves(
            players: leaguePlayers.filter { $0.positionGroup == side },
            categories: side.categories,
            labels: labels
        )
    }
}
