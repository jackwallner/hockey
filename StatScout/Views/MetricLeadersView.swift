import SwiftUI

typealias MetricLeaderEntry = (label: String, category: MetricCategory, best: (player: Player, percentile: Int, actualValue: String)?, worst: (player: Player, percentile: Int, actualValue: String)?)

struct MetricLeadersView: View {
    @EnvironmentObject private var store: StoreService
    let metrics: [MetricLeaderEntry]

    private var groupedByCategory: [(MetricCategory, [MetricLeaderEntry])] {
        let grouped = Dictionary(grouping: metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if metrics.isEmpty {
                    ContentUnavailableView {
                        Label("No metric data", systemImage: "chart.bar")
                    } description: {
                        Text("No metrics are available for the current season.")
                    }
                    .padding(.vertical, 48)
                } else {
                    VStack(spacing: 12) {
                        ForEach(groupedByCategory, id: \.0) { group in
                            categoryCard(group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Many metrics (xISO, xOBP, Hard-Hit%, Arm Strength, Squared-Up%) ship a
    /// valid Gridiron percentile but a blank value string. Rather than render an
    /// empty cell, fall back to the percentile so the row still carries signal.
    private func displayValue(_ raw: String, percentile: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "\(percentile.ordinal) pct" : trimmed
    }

    private func categoryCard(_ group: (MetricCategory, [MetricLeaderEntry])) -> some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: group.0.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(width: 88, alignment: .leading)
                Text("BEST")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("WORST")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: GridironGeo.rowHeightHeader)
            .padding(.horizontal, GridironGeo.padInline)
            .background(GridironPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(group.1.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    NavigationLink(value: MetricRoute(label: item.label, category: item.category)) {
                        HStack(spacing: 2) {
                            Text(item.label)
                                .font(GridironType.smallBold)
                                .foregroundStyle(GridironPalette.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                        .frame(width: 88, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if let best = item.best {
                        NavigationLink(value: best.player) {
                            HStack(spacing: 6) {
                                PlayerHeadshot(team: best.player.team, initials: best.player.initials, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(best.player.name)
                                        .font(GridironType.smallBold)
                                        .foregroundStyle(GridironPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(displayValue(best.actualValue, percentile: best.percentile))
                                        .font(GridironType.statSmall)
                                        .foregroundStyle(GridironPalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("No qualified players")
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }

                    if let worst = item.worst {
                        NavigationLink(value: worst.player) {
                            HStack(spacing: 6) {
                                PlayerHeadshot(team: worst.player.team, initials: worst.player.initials, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(worst.player.name)
                                        .font(GridironType.smallBold)
                                        .foregroundStyle(GridironPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(displayValue(worst.actualValue, percentile: worst.percentile))
                                        .font(GridironType.statSmall)
                                        .foregroundStyle(GridironPalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Only qualifier")
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .frame(height: GridironGeo.rowHeight)
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
}

#Preview {
    NavigationStack {
        MetricLeadersView(metrics: [])
            .environmentObject(StoreService.shared)
    }
}
