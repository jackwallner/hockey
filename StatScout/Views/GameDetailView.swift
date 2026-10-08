import Charts
import SwiftUI

/// One game: the score first, then the box score, then the few advanced numbers
/// the per-player feed can total honestly.
struct GameDetailView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    let gameId: String

    @State private var paywallTrigger: PaywallTrigger?
    @State private var detail: GameDetail?
    @State private var isDetailLoading = false
    @State private var detailFailed = false

    @State private var logs: [PlayerGameLog] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var boxTeam: String = ""

    private var game: Game? { viewModel.game(id: gameId) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let game {
                    header(game)
                    detail(for: game)
                } else if viewModel.isGamesLoading {
                    ProgressView().padding(.vertical, 64)
                } else {
                    ContentUnavailableView("Game not found", systemImage: "calendar.badge.exclamationmark")
                        .padding(.vertical, 48)
                }
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationTitle(game.map { "\(displayTeamAbbr($0.awayTeam)) at \(displayTeamAbbr($0.homeTeam))" } ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadGames(force: true)
            await loadLogs(force: true)
            await loadDetail()
        }
        .task { await viewModel.loadGames() }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .task(id: "\(gameId)-\(game.map(viewModel.hasStats) ?? false)-\(viewModel.freshnessRevision ?? "none")") {
            async let details: Void = loadDetail()
            async let lines: Void = loadLogs(force: false)
            _ = await (details, lines)
        }
    }

    private var boxScore: GameBoxScore { GameBoxScore(logs: logs) }

    /// Tracked apart from the box score, so a request still in flight or one
    /// that failed never reads as "not published yet".
    private func loadDetail() async {
        guard let game, game.status() != .upcoming else { return }
        isDetailLoading = detail == nil
        defer { isDetailLoading = false }
        do {
            if let loaded = try await viewModel.fetchGameDetail(gameId: gameId) {
                detail = loaded
            }
            detailFailed = false
        } catch {
            if !isTaskCancellation(error), detail == nil {
                detailFailed = true
            }
        }
    }

    private func loadLogs(force: Bool) async {
        guard let game, game.status() == .final || viewModel.hasStats(game) else { return }
        if !force, !logs.isEmpty, viewModel.hasStats(game) { return }
        isLoading = logs.isEmpty
        do {
            logs = try await viewModel.fetchGameLogs(gameId: gameId)
            loadError = nil
        } catch {
            if !isTaskCancellation(error), logs.isEmpty {
                loadError = "Couldn't load the box score. Pull to try again."
            }
        }
        if boxTeam.isEmpty { boxTeam = game.awayTeam }
        isLoading = false
    }

    // MARK: - Header

    private func header(_ game: Game) -> some View {
        let status = game.status()
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                teamColumn(game.awayTeam, game: game, label: "Away")
                VStack(spacing: 4) {
                    if game.isFinal {
                        HStack(spacing: 10) {
                            scoreText(game.awayScore, winner: game.result(for: game.awayTeam) != "L")
                            Text("-")
                                .font(GridironType.statLarge)
                                .foregroundStyle(GridironPalette.inkTertiary)
                            scoreText(game.homeScore, winner: game.result(for: game.homeTeam) != "L")
                        }
                    } else {
                        Text(status == .upcoming ? game.kickoffLabel : "In progress")
                            .font(GridironType.cardTitle)
                            .foregroundStyle(status == .upcoming ? GridironPalette.ink : GridironPalette.performanceLow)
                    }
                    Text(statusLine(game, status: status))
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                }
                .frame(minWidth: 110)
                teamColumn(game.homeTeam, game: game, label: "Home")
            }

            Text([game.roundLabel, game.dayLabel, game.stadium].compactMap { $0 }.joined(separator: " · "))
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func teamColumn(_ team: String, game: Game, label: String) -> some View {
        NavigationLink(value: TeamDestination(abbr: normalizedTeamAbbreviation(team))) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(NFLTeamColor.color(team))
                    Text(displayTeamAbbr(team))
                        .font(GridironType.smallBold)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 48, height: 48)
                Text(teamFullName(team))
                    .font(GridironType.smallBold)
                    .foregroundStyle(GridironPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(([label] + [game.seasonPhase == .regular ? viewModel.record(forTeam: team, through: game) : nil].compactMap { $0 }).joined(separator: " · "))
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the team")
    }

    private func scoreText(_ score: Int?, winner: Bool) -> some View {
        Text(score.map(String.init) ?? "-")
            .font(GridironType.statHero)
            .foregroundStyle(winner ? GridironPalette.ink : GridironPalette.inkTertiary)
            .monospacedDigit()
    }

    private func statusLine(_ game: Game, status: GameStatus) -> String {
        switch status {
        case .final: return game.overtime ? "Final/OT" : "Final"
        case .inProgress, .awaitingScore: return "Score posts at the final"
        case .upcoming: return game.kickoff.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
        }
    }

    // MARK: - Body

    /// Advanced first, the way analytics box scores read: how the game swung,
    /// how efficiently each offense played, the plays that decided it, who
    /// drove it. The traditional box score follows for the counts.
    @ViewBuilder
    private func detail(for game: Game) -> some View {
        if detail != nil || !logs.isEmpty {
            if let detail {
                if detail.winProbability.count > 2 {
                    winProbabilityCard(detail, game: game)
                }
                efficiencyCard(detail, game: game)
                if !detail.bigPlays.isEmpty {
                    bigPlaysCard(detail, game: game)
                }
                playerEfficiencyCards(detail)
            } else if isDetailLoading {
                ProgressView("Loading advanced breakdown")
                    .font(GridironType.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if detailFailed {
                notice(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load the advanced breakdown",
                    text: "Win probability, EPA and success rate didn't load. Check your connection and try again.",
                    action: ("Try again", { Task { await loadDetail() } })
                )
            } else {
                notice(
                    icon: "chart.xyaxis.line",
                    title: "Advanced breakdown on the way",
                    text: "Win probability, EPA and success rate post once play-by-play is published, usually within a few hours of the final."
                )
            }

            if !logs.isEmpty {
                sectionHeading("Box score")
                leadersCard
                teamStatsCard(game)
                boxScoreCard(game)
            }

            footnote("Percentiles rank each number against every team game (or every player game with enough volume) this season, and update as new games arrive. EPA is expected points added; success rate is the share of plays with positive EPA.")
            StatGlossaryLink()
                .padding(.horizontal, 12)
                .padding(.top, 12)
        } else if isLoading {
            ProgressView("Loading box score")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let loadError {
            footnote(loadError)
        } else {
            switch game.status() {
            case .final:
                notice(
                    icon: "clock",
                    title: "Stats arriving",
                    text: "The final score is in. Player stats usually post within a few hours of the final whistle."
                )
            case .inProgress, .awaitingScore:
                notice(
                    icon: "football",
                    title: "Game in progress",
                    text: "The score and box score post when the game goes final."
                )
            case .upcoming:
                upcomingCard(game)
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(GridironType.sectionTitle)
            .foregroundStyle(GridironPalette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 24)
    }

    private var leadersCard: some View {
        card(title: "Game leaders") {
            ForEach(Array(boxScore.leaders.enumerated()), id: \.element.id) { index, leader in
                playerRow(line: leader.line, index: index) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            TeamColorDot(abbr: leader.line.team, size: 6)
                            Text("\(leader.title.uppercased()) · \(displayTeamAbbr(leader.line.team))")
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                        nameText(leader.line)
                        Text(leader.summary)
                            .font(GridironType.small)
                            .foregroundStyle(GridironPalette.inkSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func teamStatsCard(_ game: Game) -> some View {
        let away = boxScore.totals(for: game.awayTeam)
        let home = boxScore.totals(for: game.homeTeam)
        return card(title: "Team stats") {
            HStack {
                Text(displayTeamAbbr(game.awayTeam)).frame(width: 64, alignment: .leading)
                Spacer()
                Text(displayTeamAbbr(game.homeTeam)).frame(width: 64, alignment: .trailing)
            }
            .font(GridironType.smallBold)
            .foregroundStyle(GridironPalette.inkSecondary)
            .padding(.horizontal, GridironGeo.padCard)
            .frame(height: 30)
            .background(GridironPalette.surfaceAlt)

            comparisonRow("Total yards", away.totalYards, home.totalYards, higherIsBetter: true)
            comparisonRow("Passing yards", away.passingYards - away.sackYardsLost, home.passingYards - home.sackYardsLost, higherIsBetter: true)
            comparisonRow("Rushing yards", away.rushingYards, home.rushingYards, higherIsBetter: true)
            comparisonRow("First downs", away.firstDowns, home.firstDowns, higherIsBetter: true)
            comparisonRow("Sacks taken", away.sacksTaken, home.sacksTaken, higherIsBetter: false)
            footnoteRow("Totals add up each team's player lines.")
        }
    }

    private func comparisonRow(_ label: String, _ away: Double, _ home: Double, higherIsBetter: Bool, decimals: Int = 0) -> some View {
        comparisonRow(label, away, home, higherIsBetter: higherIsBetter) { value in
            decimals == 0
                ? Int(value.rounded()).formatted()
                : value.formatted(.number.precision(.fractionLength(decimals)).sign(strategy: .always(includingZero: false)))
        }
    }

    private func comparisonRow(_ label: String, _ away: Double, _ home: Double, higherIsBetter: Bool, format: @escaping (Double) -> String) -> some View {
        let awayBetter = higherIsBetter ? away > home : away < home
        let homeBetter = higherIsBetter ? home > away : home < away
        return HStack {
            Text(format(away))
                .font(GridironType.statMed)
                .fontWeight(awayBetter ? .bold : .regular)
                .foregroundStyle(awayBetter ? GridironPalette.ink : GridironPalette.inkSecondary)
                .frame(width: 64, alignment: .leading)
            Spacer()
            Text(label)
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
            Spacer()
            Text(format(home))
                .font(GridironType.statMed)
                .fontWeight(homeBetter ? .bold : .regular)
                .foregroundStyle(homeBetter ? GridironPalette.ink : GridironPalette.inkSecondary)
                .frame(width: 64, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, GridironGeo.padCard)
        .frame(height: 36)
        .overlay(Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline), alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(teamFullName(game?.awayTeam ?? "")) \(format(away)), \(teamFullName(game?.homeTeam ?? "")) \(format(home))")
    }

    // MARK: - Advanced

    private func winProbabilityCard(_ detail: GameDetail, game: Game) -> some View {
        let points = detail.winProbability
        let end = max(3600, points.last?.elapsed ?? 3600)
        let homeColor = NFLTeamColor.color(game.homeTeam)
        return card(title: "Win probability") {
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    RuleMark(y: .value("Even", 50))
                        .foregroundStyle(GridironPalette.divider)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value("Home win probability", point.homeWinProbability * 100)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(homeColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: 0...end)
                .chartXAxis {
                    AxisMarks(values: [0, 900, 1800, 2700] + (end > 3600 ? [3600] : [])) { value in
                        AxisGridLine().foregroundStyle(GridironPalette.divider)
                        AxisValueLabel(anchor: .topLeading) {
                            let seconds = value.as(Double.self) ?? 0
                            Text(seconds >= 3600 ? "OT" : "Q\(Int(seconds / 900) + 1)")
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisValueLabel {
                            let wp = value.as(Double.self) ?? 50
                            Text(wp == 100 ? displayTeamAbbr(game.homeTeam) : wp == 0 ? displayTeamAbbr(game.awayTeam) : "50%")
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Win probability chart for \(teamFullName(game.homeTeam))")

                Text("\(teamFullName(game.homeTeam)) chance to win, play by play. Up is \(displayTeamAbbr(game.homeTeam)), down is \(displayTeamAbbr(game.awayTeam)).")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(GridironGeo.padCard)
        }
    }

    enum RateStyle {
        case epa
        case percent
        case decimal
        case signedDecimal
        case count

        func format(_ value: Double) -> String {
            switch self {
            case .epa: return value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
            case .percent: return (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
            case .decimal: return value.formatted(.number.precision(.fractionLength(1)))
            case .signedDecimal: return value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            case .count: return Int(value.rounded()).formatted()
            }
        }
    }

    private struct EfficiencyMetric {
        let label: String
        let key: String
        let style: RateStyle
        /// Shown instead of the rate when present, e.g. "3/9" on third down.
        var fraction: (String, String)? = nil
    }

    private static let efficiencyMetrics: [EfficiencyMetric] = [
        .init(label: "EPA per play", key: "epa_per_play", style: .epa),
        .init(label: "Success rate", key: "success_rate", style: .percent),
        .init(label: "Dropback EPA", key: "pass_epa_per_dropback", style: .epa),
        .init(label: "Dropback success", key: "pass_success_rate", style: .percent),
        .init(label: "Rush EPA", key: "rush_epa_per_carry", style: .epa),
        .init(label: "Rush success", key: "rush_success_rate", style: .percent),
        .init(label: "Explosive plays", key: "explosive_play_rate", style: .percent),
        .init(label: "Early-down pass rate", key: "early_down_pass_rate", style: .percent),
        .init(label: "Pass rate over expected", key: "pass_rate_over_expected", style: .percent),
        .init(label: "Yards per play", key: "yards_per_play", style: .decimal),
        .init(label: "Third down", key: "third_down_rate", style: .percent, fraction: ("third_down_conversions", "third_down_attempts")),
        .init(label: "Red zone TDs", key: "red_zone_td_rate", style: .percent, fraction: ("red_zone_tds", "red_zone_trips")),
        .init(label: "CPOE", key: "cpoe", style: .signedDecimal),
        .init(label: "Avg depth of target", key: "adot", style: .decimal),
        .init(label: "Sack rate", key: "sack_rate", style: .percent),
        .init(label: "Turnovers", key: "turnovers", style: .count),
    ]

    private func efficiencyCard(_ detail: GameDetail, game: Game) -> some View {
        let away = detail.stats(for: game.awayTeam)
        let home = detail.stats(for: game.homeTeam)
        return card(title: "Team efficiency") {
            HStack {
                teamLabel(game.awayTeam)
                Spacer()
                Text("Bars: percentile vs all team games")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                Spacer()
                teamLabel(game.homeTeam)
            }
            .padding(.horizontal, GridironGeo.padCard)
            .frame(height: 30)
            .background(GridironPalette.surfaceAlt)

            ForEach(Array(Self.efficiencyMetrics.enumerated()), id: \.element.key) { index, metric in
                if away[metric.key] != nil || home[metric.key] != nil {
                    efficiencyRow(metric, away: away, home: home, index: index, game: game)
                }
            }
        }
    }

    private func teamLabel(_ team: String) -> some View {
        HStack(spacing: 4) {
            TeamColorDot(abbr: team, size: 8)
            Text(displayTeamAbbr(team))
                .font(GridironType.smallBold)
                .foregroundStyle(GridironPalette.ink)
        }
    }

    private func efficiencyRow(_ metric: EfficiencyMetric, away: [String: RatedValue], home: [String: RatedValue], index: Int, game: Game) -> some View {
        func text(_ side: [String: RatedValue]) -> String {
            if let fraction = metric.fraction,
               let made = side[fraction.0], let tries = side[fraction.1], tries.value > 0 {
                return "\(Int(made.value))/\(Int(tries.value))"
            }
            return side[metric.key].map { metric.style.format($0.value) } ?? "-"
        }
        return HStack(spacing: 8) {
            ratedCell(text(away), percentile: away[metric.key]?.percentile, alignment: .leading)
            Text(metric.label)
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            ratedCell(text(home), percentile: home[metric.key]?.percentile, alignment: .trailing)
        }
        .padding(.horizontal, GridironGeo.padCard)
        .frame(height: 40)
        .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.label): \(teamFullName(game.awayTeam)) \(text(away))\(away[metric.key]?.percentile.map { ", \($0.ordinalString) percentile" } ?? ""), "
                + "\(teamFullName(game.homeTeam)) \(text(home))\(home[metric.key]?.percentile.map { ", \($0.ordinalString) percentile" } ?? "")"
        )
    }

    /// A value over a thin percentile bar, the value tinted by its rank.
    private func ratedCell(_ text: String, percentile: Int?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(text)
                .font(GridironType.statMed)
                .foregroundStyle(percentile.map { GridironPalette.textColor(forPercentile: $0) } ?? GridironPalette.ink)
            if let percentile {
                PercentileBarMini(percentile: percentile, height: 4)
                    .frame(width: 44)
                    .scaleEffect(x: alignment == .trailing ? -1 : 1)
            } else {
                Color.clear.frame(width: 44, height: 4)
            }
        }
        .frame(width: 64, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func bigPlaysCard(_ detail: GameDetail, game: Game) -> some View {
        card(title: "Plays that swung it") {
            ForEach(Array(detail.bigPlays.enumerated()), id: \.element.id) { index, play in
                let home = normalizedTeamAbbreviation(play.team) == normalizedTeamAbbreviation(game.homeTeam)
                let swing = home ? play.homeWPA : -play.homeWPA
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Q\(play.qtr) \(play.clock.hasPrefix("0") ? String(play.clock.dropFirst()) : play.clock)")
                            .lineLimit(1)
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.inkTertiary)
                        HStack(spacing: 4) {
                            TeamColorDot(abbr: play.team, size: 6)
                            Text(displayTeamAbbr(play.team))
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.inkSecondary)
                        }
                    }
                    .frame(width: 58, alignment: .leading)
                    Text(Self.cleanDescription(play.description))
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.ink)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text((swing * 100).formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + "%")
                        .font(GridironType.statMed)
                        .foregroundStyle(swing >= 0 ? GridironPalette.performanceHigh : GridironPalette.performanceLow)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, GridironGeo.padInline)
                .padding(.vertical, 10)
                .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
                .accessibilityElement(children: .combine)
            }
            footnoteRow("Change in the offense's win probability on the play.")
        }
    }

    /// Play-by-play text starts with the clock and formation tags the row
    /// already shows: "(1:41) (Shotgun) 17-J.Allen pass deep middle...".
    static func cleanDescription(_ text: String) -> String {
        var result = text
        while result.hasPrefix("(") , let close = result.firstIndex(of: ")") {
            result = String(result[result.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return result.replacingOccurrences(of: #"\b\d{1,2}-(?=[A-Z])"#, with: "", options: .regularExpression)
    }

    @ViewBuilder
    private func playerEfficiencyCards(_ detail: GameDetail) -> some View {
        if store.isPro {
            let passers = detail.players(.passer)
            if !passers.isEmpty {
                card(title: "Passing efficiency") {
                    efficiencyHeader(["DB", "EPA", "EPA/DB", "SUCC", "CPOE"])
                    ForEach(Array(passers.enumerated()), id: \.element.id) { index, line in
                        efficiencyPlayerRow(line, index: index, cells: [
                            (line.dropbacks.map(String.init) ?? "-", nil),
                            (line.epa.map { RateStyle.epa.format($0) } ?? "-", nil),
                            rated(line.epaPerDropback, .epa),
                            rated(line.successRate, .percent),
                            rated(line.cpoe, .signedDecimal),
                        ])
                    }
                }
            }
            let rushers = detail.players(.rusher)
            if !rushers.isEmpty {
                card(title: "Rushing efficiency") {
                    efficiencyHeader(["CAR", "EPA", "EPA/C", "SUCC"])
                    ForEach(Array(rushers.enumerated()), id: \.element.id) { index, line in
                        efficiencyPlayerRow(line, index: index, cells: [
                            (line.carries.map(String.init) ?? "-", nil),
                            (line.epa.map { RateStyle.epa.format($0) } ?? "-", nil),
                            rated(line.epaPerCarry, .epa),
                            rated(line.successRate, .percent),
                        ])
                    }
                }
            }
            let receivers = detail.players(.receiver)
            if !receivers.isEmpty {
                card(title: "Receiving efficiency") {
                    efficiencyHeader(["TGT", "EPA", "EPA/T", "SUCC", "ADOT"])
                    ForEach(Array(receivers.enumerated()), id: \.element.id) { index, line in
                        efficiencyPlayerRow(line, index: index, cells: [
                            (line.targets.map(String.init) ?? "-", nil),
                            (line.epa.map { RateStyle.epa.format($0) } ?? "-", nil),
                            rated(line.epaPerTarget, .epa),
                            rated(line.successRate, .percent),
                            rated(line.adot, .decimal),
                        ])
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GridironPalette.inkTertiary)
                Text("Every player's efficiency")
                    .font(GridironType.cardTitle)
                    .foregroundStyle(GridironPalette.ink)
                Text("EPA per dropback, success rate, CPOE and depth of target for every passer, rusher and receiver, ranked against the season.")
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PlusDirectCTA(trigger: .advancedBoxScore, style: .capsule)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(GridironPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                    .stroke(GridironPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    private func rated(_ value: RatedValue?, _ style: RateStyle) -> (String, Int?) {
        guard let value else { return ("-", nil) }
        return (style.format(value.value), value.percentile)
    }

    private func efficiencyHeader(_ columns: [String]) -> some View {
        tableHeader(columns, width: 44)
    }

    private func efficiencyPlayerRow(_ line: GameDetail.PlayerLine, index: Int, cells: [(String, Int?)]) -> some View {
        let player = game.flatMap { viewModel.player(id: line.playerId, season: $0.season, phase: $0.seasonPhase) }
        let row = HStack(spacing: 0) {
            HStack(spacing: 6) {
                TeamColorDot(abbr: line.team, size: 7)
                Text(player?.name ?? line.name ?? "Player")
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell.0)
                    .font(GridironType.statSmall)
                    .fontWeight(cell.1 == nil ? .regular : .semibold)
                    .foregroundStyle(cell.1.map { GridironPalette.textColor(forPercentile: $0) } ?? GridironPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, GridironGeo.padInline)
        .frame(minHeight: 40)
        .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
        .contentShape(Rectangle())
        return Group {
            if let player {
                NavigationLink(value: player) { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private func teamPicker(_ game: Game, team: String) -> some View {
        GridironSegmented(
            segments: [
                .init(value: game.awayTeam, label: teamFullName(game.awayTeam)),
                .init(value: game.homeTeam, label: teamFullName(game.homeTeam)),
            ],
            selection: Binding(get: { team }, set: { boxTeam = $0 })
        )
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    private func boxScoreCard(_ game: Game) -> some View {
        let team = boxTeam.isEmpty ? game.awayTeam : boxTeam
        return VStack(spacing: 0) {
            teamPicker(game, team: team)

            card(title: "Passing") {
                tableHeader(["C/ATT", "YDS", "TD", "INT"])
                ForEach(Array(boxScore.passers(for: team).enumerated()), id: \.element.id) { index, line in
                    tableRow(line, index: index, values: [
                        "\(line.int("completions"))/\(line.int("attempts"))",
                        "\(line.int("passing_yards"))", "\(line.int("passing_tds"))", "\(line.int("interceptions"))",
                    ])
                }
            }
            card(title: "Rushing") {
                tableHeader(["CAR", "YDS", "AVG", "TD"])
                ForEach(Array(boxScore.rushers(for: team).enumerated()), id: \.element.id) { index, line in
                    let carries = line.value("carries")
                    tableRow(line, index: index, values: [
                        "\(line.int("carries"))", "\(line.int("rushing_yards"))",
                        carries > 0 ? (line.value("rushing_yards") / carries).formatted(.number.precision(.fractionLength(1))) : "-",
                        "\(line.int("rushing_tds"))",
                    ])
                }
            }
            card(title: "Receiving") {
                tableHeader(["REC", "TGT", "YDS", "TD"])
                ForEach(Array(boxScore.receivers(for: team).enumerated()), id: \.element.id) { index, line in
                    tableRow(line, index: index, values: [
                        "\(line.int("receptions"))", "\(line.int("targets"))",
                        "\(line.int("receiving_yards"))", "\(line.int("receiving_tds"))",
                    ])
                }
            }
            card(title: "Defense") {
                tableHeader(["TKL", "SCK", "INT", "PD"])
                ForEach(Array(boxScore.defenders(for: team).prefix(12).enumerated()), id: \.element.id) { index, line in
                    tableRow(line, index: index, values: [
                        "\(Int(line.tackles.rounded()))",
                        line.value("def_sacks").formatted(.number.precision(.fractionLength(0...1))),
                        "\(line.int("def_interceptions"))", "\(line.int("def_pass_defended"))",
                    ])
                }
            }
        }
    }

    private func upcomingCard(_ game: Game) -> some View {
        notice(
            icon: "calendar",
            title: "Not started yet",
            text: "The score and box score post here when the game goes final. Scout both rosters from the team pages above."
        )
    }

    // MARK: - Pieces

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: title)
            content()
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func tableHeader(_ columns: [String], width: CGFloat = 46) -> some View {
        HStack(spacing: 0) {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: width, alignment: .trailing)
            }
        }
        .font(GridironType.micro)
        .foregroundStyle(GridironPalette.inkTertiary)
        .padding(.horizontal, GridironGeo.padInline)
        .frame(height: 26)
        .background(GridironPalette.surfaceAlt)
    }

    private func tableRow(_ line: GameBoxScore.PlayerLine, index: Int, width: CGFloat = 46, values: [String]) -> some View {
        playerRow(line: line, index: index) {
            HStack(spacing: 0) {
                nameText(line)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(GridironType.statSmall)
                        .foregroundStyle(GridironPalette.ink)
                        .frame(width: width, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    /// A tappable row when the player is in the live dataset, a plain one if not.
    @ViewBuilder
    private func playerRow<Content: View>(line: GameBoxScore.PlayerLine, index: Int, @ViewBuilder content: () -> Content) -> some View {
        let row = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GridironGeo.padInline)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
            .contentShape(Rectangle())
        if let player = player(for: line) {
            NavigationLink(value: player) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func nameText(_ line: GameBoxScore.PlayerLine) -> some View {
        Text(player(for: line)?.name ?? "Player \(line.playerId)")
            .font(GridironType.bodyBold)
            .foregroundStyle(GridironPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func player(for line: GameBoxScore.PlayerLine) -> Player? {
        guard let game else { return nil }
        return viewModel.player(id: line.playerId, season: game.season, phase: game.seasonPhase)
    }

    private func notice(
        icon: String,
        title: String,
        text: String,
        action: (label: String, perform: () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(GridironPalette.inkTertiary)
            Text(title)
                .font(GridironType.cardTitle)
                .foregroundStyle(GridironPalette.ink)
            Text(text)
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.label, action: action.perform)
                    .font(GridironType.smallBold)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(GridironType.micro)
            .foregroundStyle(GridironPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    private func footnoteRow(_ text: String) -> some View {
        Text(text)
            .font(GridironType.micro)
            .foregroundStyle(GridironPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GridironGeo.padCard)
            .padding(.vertical, 10)
    }
}
