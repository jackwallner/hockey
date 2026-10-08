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
        .background(RinkPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Many metrics (xISO, xOBP, Hard-Hit%, Arm Strength, Squared-Up%) ship a
    /// valid Rink percentile but a blank value string. Rather than render an
    /// empty cell, fall back to the percentile so the row still carries signal.
    private func displayValue(_ raw: String, percentile: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "\(percentile.ordinal) pct" : trimmed
    }

    private func categoryCard(_ group: (MetricCategory, [MetricLeaderEntry])) -> some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: group.0.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(width: 88, alignment: .leading)
                Text("BEST")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("WORST")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: RinkGeo.rowHeightHeader)
            .padding(.horizontal, RinkGeo.padInline)
            .background(RinkPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(group.1.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    NavigationLink(value: MetricRoute(label: item.label, category: item.category)) {
                        HStack(spacing: 2) {
                            Text(item.label)
                                .font(RinkType.smallBold)
                                .foregroundStyle(RinkPalette.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(RinkPalette.inkTertiary)
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
                                        .font(RinkType.smallBold)
                                        .foregroundStyle(RinkPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(displayValue(best.actualValue, percentile: best.percentile))
                                        .font(RinkType.statSmall)
                                        .foregroundStyle(RinkPalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("No qualified players")
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }

                    if let worst = item.worst {
                        NavigationLink(value: worst.player) {
                            HStack(spacing: 6) {
                                PlayerHeadshot(team: worst.player.team, initials: worst.player.initials, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(worst.player.name)
                                        .font(RinkType.smallBold)
                                        .foregroundStyle(RinkPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(displayValue(worst.actualValue, percentile: worst.percentile))
                                        .font(RinkType.statSmall)
                                        .foregroundStyle(RinkPalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Only qualifier")
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .frame(height: RinkGeo.rowHeight)
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
}

#Preview {
    NavigationStack {
        MetricLeadersView(metrics: [])
            .environmentObject(StoreService.shared)
    }
}
