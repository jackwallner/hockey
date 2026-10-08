import SwiftUI

struct MetricRankingView: View {
    let metricLabel: String
    let metricCategory: MetricCategory
    let players: [Player]
    let season: Int?
    /// Supplies qualification and volume; nil in previews.
    var viewModel: DashboardViewModel? = nil
    @State private var sortDescending: Bool

    init(metricLabel: String, metricCategory: MetricCategory, players: [Player], season: Int?, viewModel: DashboardViewModel? = nil) {
        self.metricLabel = metricLabel
        self.metricCategory = metricCategory
        self.players = players
        self.season = season
        self.viewModel = viewModel
        // Default to "best first" for the active metric (descending for
        // higher-is-better, ascending for pitcher xwOBA / ERA / WHIP / etc.).
        // User can still flip via the header chevron.
        _sortDescending = State(initialValue: DashboardViewModel.defaultSortDescending(label: metricLabel, category: metricCategory))
    }

    private var rankedPlayers: [Player] {
        let sorted = players
            .filter { player in
                player.metrics.contains {
                    $0.label == metricLabel && $0.category == metricCategory
                }
            }
            .sorted(
                by: DashboardViewModel.metricComparator(
                    label: metricLabel,
                    category: metricCategory,
                    descending: sortDescending
                )
            )
        // Same rule as the Stats board: small samples stay listed, below.
        return sorted.filter { !isSmallSample($0) } + sorted.filter(isSmallSample)
    }

    private func isSmallSample(_ player: Player) -> Bool {
        guard let metric = player.metrics.first(where: { $0.label == metricLabel && $0.category == metricCategory })
        else { return false }
        return viewModel.map { !$0.isQualified(player, metric: metric) } ?? metric.isSmallSample
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RinkSectionBar(
                    title: "\(metricLabel) · \(metricCategory.rawValue)",
                    trailing: AnyView(
                        HStack(spacing: 12) {
                            if let season {
                                Text(SeasonLabel.text(season))
                                    .font(RinkType.micro)
                                    .foregroundStyle(RinkPalette.inkSecondary)
                            }
                            Button(action: {
                                sortDescending.toggle()
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }) {
                                HStack(spacing: 4) {
                                    Text(metricLabel)
                                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                                }
                                .font(RinkType.micro)
                                .foregroundStyle(RinkPalette.inkSecondary)
                            }
                        }
                    )
                )

                if rankedPlayers.isEmpty {
                    ContentUnavailableView {
                        Label("No rankings found", systemImage: "chart.bar")
                    } description: {
                        Text("No players have the \(metricLabel) metric for this season.")
                    }
                    .padding(.vertical, 24)
                } else {
                    // Sorted by raw stat value - header carries the metric label
                    // (e.g. "xwOBA") so the column matches what's in each row.
                    LeaderboardTableHeader(sortDescending: sortDescending, sortLabel: metricLabel)
                    ForEach(Array(rankedPlayers.enumerated()), id: \.element.id) { index, player in
                        NavigationLink(value: player) {
                            LeaderboardTableRow(
                                rank: index + 1,
                                player: player,
                                metricLabel: metricLabel,
                                metricCategory: metricCategory,
                                volume: viewModel?.volumeCaption(for: player, category: metricCategory)
                                    ?? player.volumeCaption(for: metricCategory),
                                isSmallSample: isSmallSample(player)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(RinkPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RinkPalette.canvas.ignoresSafeArea())
        .navigationTitle("\(metricLabel) · \(metricCategory.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricPercentile(for player: Player) -> Int {
        player.metrics.first { $0.label == metricLabel && $0.category == metricCategory }?.percentile ?? 0
    }

}

#if DEBUG
#Preview {
    NavigationStack {
        MetricRankingView(metricLabel: "Pass Yds", metricCategory: .passing, players: SampleData.players, season: 2025)
    }
}
#endif
