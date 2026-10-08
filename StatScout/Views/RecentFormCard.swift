import SwiftUI

/// Last 2 / 4 / 8 week rolling form for a single player. Pro-gated: free
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
    @State private var windowWeeks: Int = 4
    @State private var curves: LeaguePercentileCurves?

    /// The phase the card's games come from - the profile is scoped to
    /// whichever phase the user arrived on, and the player row carries it.
    private var seasonPhase: SeasonPhase { player.seasonPhase }

    private var isGoalie: Bool { player.isGoalie }

    /// Smallest ice time (minutes) we'll consider trustworthy. Anything below
    /// shows the numbers but tags them as "small sample".
    private var smallSamplePlaysThreshold: Int { isGoalie ? 100 : 60 }

    private var windowLogs: [PlayerGameLog] {
        RecentFormWindow.logs(logs, weeks: windowWeeks)
    }

    private var window: RecentFormWindow? {
        guard !windowLogs.isEmpty else { return nil }
        return RecentFormWindow.build(
            label: "Last \(windowWeeks) weeks",
            span: windowWeeks,
            logs: windowLogs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
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
            players: leaguePlayers.filter { $0.positionGroup == player.positionGroup },
            categories: isGoalie ? [.goaltending] : [.scoring, .shotQuality],
            labels: RecentFormWindow.recentLabels(goalie: isGoalie)
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RinkPalette.turf)
                Text("RECENT FORM")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkSecondary)
                Spacer()
                if !store.isPro {
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
            }
            .padding(.horizontal, RinkGeo.padInline)
            .padding(.top, 12)

            windowPicker
                .padding(.horizontal, RinkGeo.padInline)
                .padding(.bottom, 10)
        }
        .background(RinkPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
            alignment: .bottom
        )
    }

    private var windowPicker: some View {
        RinkSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: Binding(
                get: { RecentWindow(rawValue: windowWeeks) ?? .four },
                set: { windowWeeks = $0.rawValue }
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
                    headline: "See last 2 / 4 / 8 week form for any player",
                    trigger: .recentForm
                )
            }
        }
    }

    /// Static, non-fetching preview for free users. No game logs are loaded.
    /// These are illustrative bars in the season percentile format so the blur
    /// reads as "real recent-form bars" without paying the network/battery cost.
    private var teaserBody: some View {
        let sample: [Metric] = isGoalie
            ? [
                Metric(id: "t_sv", label: "SV%", value: ".931", percentile: 94, category: .goaltending),
                Metric(id: "t_gsax", label: "GSAx/60", value: "0.42", percentile: 88, category: .goaltending),
                Metric(id: "t_gaa", label: "GAA", value: "2.14", percentile: 81, category: .goaltending),
                Metric(id: "t_hd", label: "HD SV%", value: ".858", percentile: 76, category: .goaltending),
            ]
            : [
                Metric(id: "t_p60", label: "P/60", value: "3.42", percentile: 94, category: .scoring),
                Metric(id: "t_ixg", label: "ixG/60", value: "1.08", percentile: 88, category: .shotQuality),
                Metric(id: "t_sh60", label: "Shots/60", value: "14.2", percentile: 81, category: .shotQuality),
                Metric(id: "t_shp", label: "Sh%", value: "14.8%", percentile: 76, category: .scoring),
            ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "GP", value: "7")
                summaryStat(label: "TOI", value: isGoalie ? "420" : "148")
                summaryStat(label: isGoalie ? "SA" : "Shot Att", value: isGoalie ? "198" : "52")
                Spacer(minLength: 0)
            }
            .padding(RinkGeo.padInline)

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
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
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
            return "Recent game data is still arriving"
        case .offline, .failed:
            return "Recent game data is unavailable right now"
        default:
            return "No games in the last \(windowWeeks) weeks"
        }
    }

    private func statsBody(window w: RecentFormWindow) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "GP", value: "\(w.games)")
                summaryStat(label: "TOI", value: "\(w.plays)")
                summaryStat(label: isGoalie ? "SA" : "Shot Att", value: "\(w.touches)")
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
                    .padding(.horizontal, RinkGeo.padCard)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                    .overlay(
                        Rectangle()
                            .fill(RinkPalette.divider)
                            .frame(height: RinkGeo.hairline),
                        alignment: .bottom
                    )
            }
        }
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

    /// Recent-window rates mapped to `Metric` so they render with the season
    /// `MetricBar`. The percentile is interpolated from the league season curve
    /// (so the recent bar sits on the same ruler as the season card); the value
    /// is rebuilt from the window's summed counts. Skips metrics with no window
    /// data or no curve so we never draw a bar we can't place.
    private func recentMetricRows(window w: RecentFormWindow) -> [Metric] {
        RecentFormWindow.recentLabels(goalie: isGoalie).compactMap { label -> Metric? in
            guard let v = w.value(forSeasonLabel: label),
                  let pct = curves?.curve(for: label)?.percentile(for: v) else { return nil }
            return Metric(
                id: "recent-\(label)",
                label: label,
                value: RecentMetricKey.format(v, label: label),
                percentile: pct,
                category: Self.category(of: label, goalie: isGoalie)
            )
        }
    }

    private static func category(of label: String, goalie: Bool) -> MetricCategory {
        if goalie { return .goaltending }
        return ["ixG/60", "Shots/60"].contains(label) ? .shotQuality : .scoring
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
