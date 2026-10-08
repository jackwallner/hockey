import SwiftUI

/// Last 7 / 15 / 30 day rolling form for a single player. Pro-gated: free
/// users see a blurred static teaser and an upgrade CTA - no game-log fetch.
/// Pro users load game logs once, then compute window aggregates client-side
/// so we don't pay a round-trip when the user switches windows.
struct RecentFormCard: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let season: Int
    /// League pool used to build the value→percentile curve so the recent bar
    /// sits on the same ruler as the season bar. Filtered to the player's type
    /// at curve-build time.
    let leaguePlayers: [Player]
    /// (playerId, season, phase).
    let fetchGameLogs: ((Int, Int, SeasonPhase) async throws -> [PlayerGameLog])?
    /// Changes after a validated publisher revision, so a retained profile
    /// cannot keep showing the previous game set.
    var freshnessRevision: String? = nil
    var freshnessStatus: DataFreshnessStatus? = nil
    let onUpgradeTap: () -> Void

    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var windowGames: Int = 5
    @State private var curves: LeaguePercentileCurves?

    /// The phase the card's games come from - the profile is scoped to
    /// whichever phase the user arrived on, and the player row carries it.
    private var seasonPhase: SeasonPhase { player.seasonPhase }

    private var category: MetricCategory { player.primaryCategory }
    private var isDefense: Bool { category == .defense }

    /// Smallest play count we'll consider trustworthy. Anything below shows the
    /// numbers but tags them as "small sample".
    private var smallSamplePlaysThreshold: Int { 10 }

    private var windowLogs: [PlayerGameLog] {
        Array(logs.sorted { $0.gameDate > $1.gameDate }.prefix(windowGames))
    }

    private var window: RecentFormWindow? {
        guard !windowLogs.isEmpty else { return nil }
        return RecentFormWindow.build(
            label: "Last \(windowGames)",
            span: windowGames,
            logs: windowLogs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(player.playerId)-\(season)-\(seasonPhase.rawValue)-\(freshnessRevision ?? "none")") {
            await load()
        }
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
    }

    private func rebuildCurves() {
        guard store.isPro else { return }
        curves = LeaguePercentileCurves(
            players: leaguePlayers,
            categories: [category],
            labels: category.metricPriorityOrder
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GridironPalette.turf)
                Text("RECENT FORM")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkSecondary)
                Spacer()
                if !store.isPro {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("STATSCOUT+")
                            .font(GridironType.micro)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(GridironPalette.midnight)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.yellow)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, GridironGeo.padInline)
            .padding(.top, 12)

            windowPicker
                .padding(.horizontal, GridironGeo.padInline)
                .padding(.bottom, 10)
        }
        .background(GridironPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
            alignment: .bottom
        )
    }

    private var windowPicker: some View {
        GridironSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: Binding(
                get: { RecentWindow(rawValue: windowGames) ?? .three },
                set: { windowGames = $0.rawValue }
            )
        )
    }

    @ViewBuilder
    private var content: some View {
        if store.isPro {
            proContent
        } else {
            ZStack(alignment: .bottom) {
                teaserBody
                    .blur(radius: 8)
                    .disabled(true)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See last 3 / 5 / 8 game form for any player",
                    trigger: .recentForm
                )
            }
        }
    }

    /// Static, non-fetching preview for free users. No game logs are loaded.
    /// These are illustrative bars in the season percentile format so the blur
    /// reads as "real recent-form bars" without paying the network/battery cost.
    private var teaserBody: some View {
        let sample: [Metric] = isDefense
            ? [
                Metric(id: "t_tackles", label: "Tackles", value: "22", percentile: 94, category: .defense),
                Metric(id: "t_sacks",   label: "Sacks",   value: "3",  percentile: 88, category: .defense),
                Metric(id: "t_int",     label: "INT",     value: "1",  percentile: 81, category: .defense),
                Metric(id: "t_pd",      label: "PD",      value: "4",  percentile: 76, category: .defense),
            ]
            : [
                Metric(id: "t_yds", label: "Rec Yds", value: "312", percentile: 94, category: category),
                Metric(id: "t_rec", label: "Rec",     value: "24",  percentile: 88, category: category),
                Metric(id: "t_td",  label: "Rec TD",  value: "3",   percentile: 81, category: category),
                Metric(id: "t_yac", label: "YAC",     value: "6.1", percentile: 76, category: category),
            ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "G", value: "3")
                summaryStat(label: "Plays", value: "48")
                if !isDefense { summaryStat(label: "Touches", value: "31") }
                Spacer(minLength: 0)
            }
            .padding(GridironGeo.padInline)

            metricBarList(sample)
        }
    }

    @ViewBuilder
    private var proContent: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
                Text("Loading recent games…")
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let err = loadError {
            InlineLoadError(message: err) { await load() }
        } else if let w = window {
            statsBody(window: w)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(GridironPalette.inkTertiary)
                Text(emptyStateText)
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private var emptyStateText: String {
        switch freshnessStatus {
        case .pending, .partial, .checking:
            return "Recent game data is still arriving"
        case .offline, .failed:
            return "Recent game data is unavailable right now"
        default:
            return "No games in the last \(windowGames) games"
        }
    }

    private func statsBody(window w: RecentFormWindow) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "G", value: "\(w.games)")
                summaryStat(label: "Plays", value: "\(w.plays)")
                if !isDefense {
                    summaryStat(label: "Touches", value: "\(w.touches)")
                }
                Spacer(minLength: 0)
                if w.plays < smallSamplePlaysThreshold {
                    Text("SMALL SAMPLE")
                        .font(GridironType.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GridironPalette.inkTertiary)
                        .clipShape(Capsule())
                }
            }
            .padding(GridironGeo.padInline)

            metricBarList(recentMetricRows(window: w))
        }
    }

    /// Recent-window metrics rendered with the exact same `MetricBar` row used
    /// on the season percentile card - same label/bar/value layout and the same
    /// alternating row backgrounds - so recent form reads on the identical ruler.
    private func metricBarList(_ rows: [Metric]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                MetricBar(metric: metric)
                    .padding(.horizontal, GridironGeo.padCard)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
                    .overlay(
                        Rectangle()
                            .fill(GridironPalette.divider)
                            .frame(height: GridironGeo.hairline),
                        alignment: .bottom
                    )
            }
        }
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
            Text(value)
                .font(GridironType.bodyBold)
                .foregroundStyle(GridironPalette.ink)
        }
    }

    /// Recent-window metrics mapped to `Metric` so they render with the season
    /// `MetricBar`. The percentile is interpolated from the league season curve
    /// (so the recent bar sits on the same ruler as the season card); the value
    /// is the recent-window number. Skips metrics with no window data or no
    /// curve so we never draw a bar we can't place.
    /// Per-game log keys mapped to the season metric label they overlay.
    private func recentSpecs(for category: MetricCategory) -> [(key: String, label: String, seasonLabel: String, format: String)] {
        switch category {
        case .passing:
            return [
                ("passing_yards", "Pass Yds", "Pass Yds", "%.0f"),
                ("passing_tds",   "Pass TD",  "Pass TD",  "%.0f"),
            ]
        case .rushing:
            return [
                ("rushing_yards", "Rush Yds", "Rush Yds", "%.0f"),
                ("rushing_tds",   "Rush TD",  "Rush TD",  "%.0f"),
            ]
        case .receiving:
            return [
                ("receiving_yards", "Rec Yds", "Rec Yds", "%.0f"),
                ("receptions",      "Rec",     "Rec",     "%.0f"),
                ("receiving_tds",   "Rec TD",  "Rec TD",  "%.0f"),
            ]
        case .defense:
            return [
                ("tackles",           "Tackles", "Tackles", "%.0f"),
                ("def_sacks",         "Sacks",   "Sacks",   "%.1f"),
                ("def_interceptions", "INT",     "INT",     "%.0f"),
            ]
        }
    }

    private func recentMetricRows(window w: RecentFormWindow) -> [Metric] {
        let specs: [(key: String, label: String, seasonLabel: String, format: String)] = recentSpecs(for: category)

        return specs.compactMap { spec -> Metric? in
            guard let v = w.metrics[spec.key],
                  let pct = curves?.curve(for: spec.seasonLabel)?.percentile(for: v) else { return nil }
            return Metric(
                id: spec.key,
                label: spec.label,
                value: String(format: spec.format, v),
                percentile: pct,
                category: category
            )
        }
    }

    private func load() async {
        // Free users see a static teaser - no game-log fetch, no battery cost.
        guard store.isPro, let fetch = fetchGameLogs else { return }
        loading = true
        loadError = nil
        do {
            let result = try await fetch(player.playerId, season, seasonPhase)
            logs = result
        } catch {
            if !isTaskCancellation(error) {
                loadError = "Couldn't load recent games."
            }
        }
        loading = false
    }
}
