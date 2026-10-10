import SwiftUI

/// Division standings from posted finals, East then West.
struct StandingsView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        let table = viewModel.standings
        VStack(spacing: 12) {
            ForEach([LeagueConference.east, .west]) { conference in
                conferenceTitle(conference)
                ForEach(LeagueDivision.allCases.filter { $0.conference == conference }) { division in
                    divisionCard(division, table: table)
                }
            }
            Text("Ordered by points, then points percentage and goal differential, not the NHL's full tiebreakers. PTS are standings points: two for a win, one for an overtime or shootout loss.")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    private func conferenceTitle(_ conference: LeagueConference) -> some View {
        Text(conference.rawValue.uppercased() + "ERN CONFERENCE")
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private func divisionCard(_ division: LeagueDivision, table: [String: StandingsRow]) -> some View {
        let rows = StandingsRow.ordered(division.teams.compactMap { table[$0] })
        return VStack(spacing: 0) {
            header(division.rawValue)
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

    private func header(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W-L-OTL").frame(width: 56, alignment: .trailing)
            Text("PTS").frame(width: 34, alignment: .trailing)
            Text("P%").frame(width: 36, alignment: .trailing)
            Text("GF").frame(width: 28, alignment: .trailing)
            Text("GA").frame(width: 28, alignment: .trailing)
            Text("DIFF").frame(width: 40, alignment: .trailing)
            Text("STRK").frame(width: 36, alignment: .trailing)
        }
        .font(RinkType.micro)
        .foregroundStyle(RinkPalette.inkTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(height: RinkGeo.rowHeightHeader)
        .padding(.horizontal, RinkGeo.padInline)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
    }

    private func line(_ row: StandingsRow) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                TeamColorDot(abbr: row.team, size: 10)
                Text(displayTeamAbbr(row.team))
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cell(row.record, width: 56, color: RinkPalette.ink)
            cell(row.games == 0 ? "-" : "\(row.points)", width: 34, color: RinkPalette.ink, bold: true)
            cell(row.games == 0 ? "-" : pointsPercentage(row), width: 36, color: RinkPalette.inkSecondary)
            cell(row.games == 0 ? "-" : "\(row.goalsFor)", width: 28, color: RinkPalette.inkSecondary)
            cell(row.games == 0 ? "-" : "\(row.goalsAgainst)", width: 28, color: RinkPalette.inkSecondary)
            cell(row.games == 0 ? "-" : differential(row), width: 40, color: differentialColor(row))
            cell(row.streak ?? "-", width: 36, color: RinkPalette.inkSecondary)
        }
        .monospacedDigit()
        .frame(height: 44)
        .padding(.horizontal, RinkGeo.padInline)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(teamFullName(row.team)), \(row.record), \(row.points) points, goal differential \(row.differential)"
        )
    }

    private func cell(_ text: String, width: CGFloat, color: Color, bold: Bool = false) -> some View {
        Text(text)
            .font(bold ? RinkType.statMed : RinkType.statSmall)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .trailing)
    }

    /// ".625", the way points percentage is written in hockey.
    private func pointsPercentage(_ row: StandingsRow) -> String {
        RecentMetricKey.savePercentage(row.winPercentage)
    }

    private func differential(_ row: StandingsRow) -> String {
        row.differential > 0 ? "+\(row.differential)" : "\(row.differential)"
    }

    private func differentialColor(_ row: StandingsRow) -> Color {
        if row.differential > 0 { return RinkPalette.performanceHigh }
        return row.differential < 0 ? RinkPalette.performanceLow : RinkPalette.inkSecondary
    }
}

/// The league ranked by power rating: what a club does minus what it allows,
/// in goals per game, adjusted for who it played.
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
        let through = ratings.first.map { rating -> String in
            guard rating.throughWeek > 0 else { return "Early season: last season's ratings, regressed. " }
            guard let asOf = viewModel.dataCoverage?.asOf else { return "" }
            return "Through \(asOf.formatted(DataCoverage.gameDayStyle)). "
        } ?? ""
        return through + "Goals per game better or worse than an average team on neutral ice: expected goals and actual goals for, minus against, adjusted for schedule. Early in the season last year counts as extra games of evidence. Read two ratings like a puck line, with about 0.2 goals for home ice."
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
