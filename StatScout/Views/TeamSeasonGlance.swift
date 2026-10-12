import SwiftUI

/// The six numbers a fan checks first on a club's page, each with its league
/// rank: scoring and keeping it out, shots both ways, special teams and the
/// expected-goals share.
struct TeamSeasonGlance: View {
    @Bindable var viewModel: DashboardViewModel
    let team: String

    private struct Tile: Identifiable {
        let label: String
        let value: String
        let rank: Int
        var id: String { label }
    }

    private var tiles: [Tile] {
        guard let summary = viewModel.teamSummaries[normalizedTeamAbbreviation(team)] else { return [] }
        func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
        func percent(_ value: Double) -> String { (value * 100).formatted(.number.precision(.fractionLength(1))) + "%" }
        var out = [
            Tile(label: "Goals for / GP", value: decimal(summary.goalsFor.value), rank: summary.goalsFor.rank),
            Tile(label: "Goals against / GP", value: decimal(summary.goalsAgainst.value), rank: summary.goalsAgainst.rank),
        ]
        if let pp = summary.powerPlay { out.append(Tile(label: "Power play", value: percent(pp.value), rank: pp.rank)) }
        if let pk = summary.penaltyKill { out.append(Tile(label: "Penalty kill", value: percent(pk.value), rank: pk.rank)) }
        if let xg = summary.expectedGoalsShare { out.append(Tile(label: "xGF%", value: percent(xg.value), rank: xg.rank)) }
        if let shots = summary.shotsFor { out.append(Tile(label: "Shots / GP", value: shots.value.formatted(.number.precision(.fractionLength(1))), rank: shots.rank)) }
        return out
    }

    var body: some View {
        let tiles = tiles
        if !tiles.isEmpty {
            VStack(spacing: 0) {
                RinkSectionBar(title: "SEASON SO FAR")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                    ForEach(tiles) { tile in
                        tileView(tile)
                    }
                }
                Text("League rank in brackets, 1st is best. Shots, special teams and xGF% cover games with a shot breakdown.")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RinkGeo.padCard)
                    .padding(.vertical, 8)
            }
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(RinkPalette.hairline, lineWidth: 0.5)
            )
        }
    }

    private func tileView(_ tile: Tile) -> some View {
        // 1st reads as the 100th percentile, 32nd as the 0th, on the app's ramp.
        let percentile = Int((Double(32 - tile.rank) / 31 * 100).rounded())
        return VStack(spacing: 3) {
            Text(tile.value)
                .font(RinkType.statMed)
                .foregroundStyle(RinkPalette.ink)
                .monospacedDigit()
            Text(tile.label)
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("(\(TeamSeasonSummary.ordinal(tile.rank)))")
                .font(RinkType.smallBold)
                .foregroundStyle(RinkPalette.textColor(forPercentile: max(0, min(100, percentile))))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.label) \(tile.value), \(TeamSeasonSummary.ordinal(tile.rank)) in the league")
    }
}
