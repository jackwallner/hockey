import SwiftUI

/// Division standings from posted finals, with each club's power rating beside
/// its record.
struct StandingsView: View {
    @Bindable var viewModel: DashboardViewModel
    let divisions: [(name: String, teams: [String])]

    var body: some View {
        let table = viewModel.standings
        VStack(spacing: 12) {
            ForEach(divisions, id: \.name) { division in
                let rows = StandingsRow.ordered(division.teams.compactMap { table[$0] })
                VStack(spacing: 0) {
                    header(division.name)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: TeamDestination(abbr: row.team)) {
                            line(row)
                                .background(index.isMultiple(of: 2) ? RinkPalette.surface : RinkPalette.surfaceAlt)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RinkPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                        .stroke(RinkPalette.hairline, lineWidth: 0.5)
                )
            }
            Text("Ordered by win percentage, then point differential, not the NFL's full tiebreakers. PWR is the StatScout Power Rating: points better or worse than an average team on a neutral field.")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W-L").frame(width: 44, alignment: .trailing)
            Text("DIFF").frame(width: 44, alignment: .trailing)
            Text("STRK").frame(width: 40, alignment: .trailing)
            Text("PWR").frame(width: 48, alignment: .trailing)
        }
        .font(RinkType.micro)
        .foregroundStyle(RinkPalette.inkTertiary)
        .frame(height: RinkGeo.rowHeightHeader)
        .padding(.horizontal, RinkGeo.padInline)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
    }

    private func line(_ row: StandingsRow) -> some View {
        let rating = viewModel.teamRating(row.team)
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                TeamColorDot(abbr: row.team, size: 10)
                Text(displayTeamAbbr(row.team))
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
                    .frame(width: 40, alignment: .leading)
                Text(teamNickname(row.team))
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.record)
                .font(RinkType.statSmall)
                .foregroundStyle(RinkPalette.ink)
                .frame(width: 44, alignment: .trailing)
            Text(row.games == 0 ? "-" : (row.differential > 0 ? "+\(row.differential)" : "\(row.differential)"))
                .font(RinkType.statSmall)
                .foregroundStyle(row.differential > 0 ? RinkPalette.performanceHigh : (row.differential < 0 ? RinkPalette.performanceLow : RinkPalette.inkSecondary))
                .frame(width: 44, alignment: .trailing)
            Text(row.streak ?? "-")
                .font(RinkType.statSmall)
                .foregroundStyle(RinkPalette.inkSecondary)
                .frame(width: 40, alignment: .trailing)
            Text(rating.map { TeamRating.signed($0.rating) } ?? "-")
                .font(RinkType.statSmall)
                .foregroundStyle(RinkPalette.ink)
                .frame(width: 48, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(height: 44)
        .padding(.horizontal, RinkGeo.padInline)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(teamFullName(row.team)), \(row.record), point differential \(row.differential)"
                + (rating.map { ", power rating \(TeamRating.signed($0.rating))" } ?? "")
        )
    }
}

/// The league ranked by power rating, after Hawk Blogger's HB Power Rankings:
/// what a club does minus what it allows, adjusted for who it played.
struct PowerRankingsView: View {
    @Bindable var viewModel: DashboardViewModel

    private var ratings: [TeamRating] {
        viewModel.teamRatings.values.sorted { $0.rank < $1.rank }
    }

    var body: some View {
        VStack(spacing: 12) {
            if ratings.isEmpty {
                ContentUnavailableView {
                    Label("Power ratings loading", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Ratings arrive with the next update. Pull to refresh.")
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .background(RinkPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            } else {
                VStack(spacing: 0) {
                    header
                    ForEach(Array(ratings.enumerated()), id: \.element.id) { index, rating in
                        NavigationLink(value: TeamDestination(abbr: rating.team)) {
                            line(rating)
                                .background(index.isMultiple(of: 2) ? RinkPalette.surface : RinkPalette.surfaceAlt)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RinkPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                        .stroke(RinkPalette.hairline, lineWidth: 0.5)
                )
            }
            Text(footnote)
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    private var footnote: String {
        let through = ratings.first.map { $0.throughWeek > 0 ? "Through Week \($0.throughWeek). " : "Preseason: last season's ratings, regressed. " } ?? ""
        return through + "Points per game better or worse than an average team on a neutral field: EPA per dropback and per run plus points, for minus against, adjusted for schedule. Early in the season last year counts as five games of evidence. Read two ratings like a spread, with about two points for home field. Modeled on Hawk Blogger's HB Power Rankings."
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 28, alignment: .leading)
            Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
            Text("OFF").frame(width: 44, alignment: .trailing)
            Text("DEF").frame(width: 44, alignment: .trailing)
            Text("RATING").frame(width: 60, alignment: .trailing)
        }
        .font(RinkType.micro)
        .foregroundStyle(RinkPalette.inkTertiary)
        .frame(height: RinkGeo.rowHeightHeader)
        .padding(.horizontal, RinkGeo.padInline)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
    }

    private func line(_ rating: TeamRating) -> some View {
        let record = viewModel.standings[normalizedTeamAbbreviation(rating.team)]?.record
        return HStack(spacing: 0) {
            Text("\(rating.rank)")
                .font(RinkType.statSmall)
                .foregroundStyle(RinkPalette.inkSecondary)
                .frame(width: 28, alignment: .leading)
            HStack(spacing: 8) {
                TeamColorDot(abbr: rating.team, size: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(teamFullName(rating.team))
                        .font(RinkType.bodyBold)
                        .foregroundStyle(RinkPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let record {
                        Text(record)
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(TeamRating.signed(rating.offense))
                .font(RinkType.statSmall)
                .foregroundStyle(tint(rating.offense))
                .frame(width: 44, alignment: .trailing)
            Text(TeamRating.signed(rating.defense))
                .font(RinkType.statSmall)
                .foregroundStyle(tint(rating.defense))
                .frame(width: 44, alignment: .trailing)
            Text(TeamRating.signed(rating.rating))
                .font(RinkType.statMed)
                .foregroundStyle(tint(rating.rating))
                .frame(width: 60, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(height: RinkGeo.rowHeight)
        .padding(.horizontal, RinkGeo.padInline)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(rating.rank). \(teamFullName(rating.team)), rating \(TeamRating.signed(rating.rating)), offense \(TeamRating.signed(rating.offense)), defense \(TeamRating.signed(rating.defense))"
        )
    }

    private func tint(_ value: Double) -> Color {
        if value >= 1 { return RinkPalette.performanceHigh }
        if value <= -1 { return RinkPalette.performanceLow }
        return RinkPalette.inkSecondary
    }
}

/// "Seahawks" from "Seattle Seahawks".
func teamNickname(_ abbr: String) -> String {
    teamFullName(abbr).split(separator: " ").last.map(String.init) ?? abbr
}
