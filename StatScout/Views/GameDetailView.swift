import Charts
import SwiftUI

/// One game: the score first, then the shot-quality story the NHL box score
/// leaves out: expected goals by side, the xG race, the chances that decided
/// it, and every skater's and goalie's line.
struct GameDetailView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    let gameId: String

    @State private var paywallTrigger: PaywallTrigger?
    @State private var detail: GameDetail?
    @State private var isDetailLoading = false
    @State private var detailFailed = false
    @State private var linesTeam: String = ""

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
        .background(RinkPalette.canvas.ignoresSafeArea())
        .navigationTitle(game.map { "\(displayTeamAbbr($0.awayTeam)) at \(displayTeamAbbr($0.homeTeam))" } ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadGames(force: true)
            await loadDetail()
        }
        .task { await viewModel.loadGames() }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .task(id: "\(gameId)-\(game.map(viewModel.hasStats) ?? false)-\(viewModel.freshnessRevision ?? "none")") {
            await loadDetail()
        }
    }

    /// Tracked apart from the page, so a request still in flight or one that
    /// failed never reads as "not published yet".
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
        if linesTeam.isEmpty { linesTeam = game.awayTeam }
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
                            scoreText(game.awayScore, winner: game.result(for: game.awayTeam) == "W")
                            Text("-")
                                .font(RinkType.statLarge)
                                .foregroundStyle(RinkPalette.inkTertiary)
                            scoreText(game.homeScore, winner: game.result(for: game.homeTeam) == "W")
                        }
                    } else {
                        Text(status == .upcoming ? game.kickoffLabel : "In progress")
                            .font(RinkType.cardTitle)
                            .foregroundStyle(status == .upcoming ? RinkPalette.ink : RinkPalette.performanceLow)
                    }
                    Text(statusLine(game, status: status))
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                }
                .frame(minWidth: 110)
                teamColumn(game.homeTeam, game: game, label: "Home")
            }

            Text([game.roundLabel, game.dayLabel, game.stadium].compactMap { $0 }.joined(separator: " · "))
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func teamColumn(_ team: String, game: Game, label: String) -> some View {
        NavigationLink(value: TeamDestination(abbr: normalizedTeamAbbreviation(team))) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(TeamColor.color(team))
                    Text(displayTeamAbbr(team))
                        .font(RinkType.smallBold)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 48, height: 48)
                Text(teamFullName(team))
                    .font(RinkType.smallBold)
                    .foregroundStyle(RinkPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(([label] + [game.seasonPhase == .regular ? viewModel.record(forTeam: team, through: game) : nil].compactMap { $0 }).joined(separator: " · "))
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the team")
    }

    private func scoreText(_ score: Int?, winner: Bool) -> some View {
        Text(score.map(String.init) ?? "-")
            .font(RinkType.statHero)
            .foregroundStyle(winner ? RinkPalette.ink : RinkPalette.inkTertiary)
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

    /// Advanced first, the way analytics box scores read: how much danger each
    /// side created, how the game swung, the chances that decided it, who drove
    /// it.
    @ViewBuilder
    private func detail(for game: Game) -> some View {
        switch game.status() {
        case .upcoming:
            upcomingCard(game)
        case .inProgress:
            notice(
                icon: "hockey.puck",
                title: "Game in progress",
                text: "The score and the shot breakdown post when the game goes final."
            )
        case .final, .awaitingScore:
            finalDetail(game)
        }
    }

    @ViewBuilder
    private func finalDetail(_ game: Game) -> some View {
        if let detail {
            teamCard(detail, game: game)
            if detail.xgRace.count > 2 {
                xgRaceCard(detail, game: game)
            }
            if !detail.bigPlays.isEmpty {
                bigPlaysCard(detail, game: game)
            }
            playerLines(detail, game: game)
            footnote("Percentiles rank each number against every team game (or every player game with enough volume) this season, and update as new games arrive. xG is the chance each shot becomes a goal, from MoneyPuck's model. GAx is goals minus xG; GSAx is xG faced minus goals allowed.")
            StatGlossaryLink()
                .padding(.horizontal, 12)
                .padding(.top, 12)
        } else if isDetailLoading {
            ProgressView("Loading shot breakdown")
                .font(RinkType.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if detailFailed {
            notice(
                icon: "wifi.exclamationmark",
                title: "Couldn't load the shot breakdown",
                text: "Expected goals and the xG race didn't load. Check your connection and try again.",
                action: ("Try again", { Task { await loadDetail() } })
            )
        } else {
            notice(
                icon: "chart.xyaxis.line",
                title: "Shot breakdown on the way",
                text: "Expected goals, the xG race and every player's line post once shots are published, usually within a few hours of the final."
            )
        }
    }

    private func teamLabel(_ team: String) -> some View {
        HStack(spacing: 4) {
            TeamColorDot(abbr: team, size: 8)
            Text(displayTeamAbbr(team))
                .font(RinkType.smallBold)
                .foregroundStyle(RinkPalette.ink)
        }
    }

    // MARK: - Team expected goals

    enum RateStyle {
        case decimal
        case signedDecimal
        case share
        case count

        func format(_ value: Double) -> String {
            switch self {
            case .decimal: return value.formatted(.number.precision(.fractionLength(2)))
            case .signedDecimal: return value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            case .share:
                // The feed ships shares either as a fraction or as a percentage.
                let percent = value <= 1.5 ? value * 100 : value
                return percent.formatted(.number.precision(.fractionLength(1))) + "%"
            case .count: return Int(value.rounded()).formatted()
            }
        }
    }

    private struct TeamMetric {
        let label: String
        let key: String
        let style: RateStyle
        /// Shown instead of the value when present, e.g. "1/4" on the power play.
        var fraction: (String, String)? = nil
    }

    private static let teamMetrics: [TeamMetric] = [
        .init(label: "xG", key: "xg", style: .decimal),
        .init(label: "xG 5v5", key: "xg_5v5", style: .decimal),
        .init(label: "xGF% 5v5", key: "xgf_pct_5v5", style: .share),
        .init(label: "CF% 5v5", key: "cf_pct_5v5", style: .share),
        .init(label: "High-danger chances", key: "hd_chances", style: .count),
        .init(label: "Shots on goal", key: "sog", style: .count),
        .init(label: "Shot attempts", key: "shot_attempts", style: .count),
        .init(label: "Goals above expected", key: "gax", style: .signedDecimal),
        .init(label: "Power play", key: "pp_goals", style: .count, fraction: ("pp_goals", "pp_opportunities")),
        .init(label: "Faceoff %", key: "faceoff_pct", style: .share),
        .init(label: "Hits", key: "hits", style: .count),
        .init(label: "Blocks", key: "blocks", style: .count),
        .init(label: "Penalty minutes", key: "pim", style: .count),
    ]

    private func teamCard(_ detail: GameDetail, game: Game) -> some View {
        let away = detail.stats(for: game.awayTeam)
        let home = detail.stats(for: game.homeTeam)
        return card(title: "Expected goals") {
            HStack {
                teamLabel(game.awayTeam)
                Spacer()
                Text("Bars: percentile vs all team games")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                Spacer()
                teamLabel(game.homeTeam)
            }
            .padding(.horizontal, RinkGeo.padCard)
            .frame(height: 30)
            .background(RinkPalette.surfaceAlt)

            ForEach(Array(Self.teamMetrics.enumerated()), id: \.element.key) { index, metric in
                if away[metric.key] != nil || home[metric.key] != nil {
                    teamRow(metric, away: away, home: home, index: index, game: game)
                }
            }
        }
    }

    private func teamRow(_ metric: TeamMetric, away: [String: RatedValue], home: [String: RatedValue], index: Int, game: Game) -> some View {
        func text(_ side: [String: RatedValue]) -> String {
            if let fraction = metric.fraction,
               let made = side[fraction.0], let tries = side[fraction.1] {
                return "\(Int(made.value))/\(Int(tries.value))"
            }
            return side[metric.key].map { metric.style.format($0.value) } ?? "-"
        }
        return HStack(spacing: 8) {
            ratedCell(text(away), percentile: away[metric.key]?.percentile, alignment: .leading)
            Text(metric.label)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            ratedCell(text(home), percentile: home[metric.key]?.percentile, alignment: .trailing)
        }
        .padding(.horizontal, RinkGeo.padCard)
        .frame(height: 40)
        .background(index.isMultiple(of: 2) ? RinkPalette.surface : RinkPalette.surfaceAlt)
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
                .font(RinkType.statMed)
                .foregroundStyle(percentile.map { RinkPalette.textColor(forPercentile: $0) } ?? RinkPalette.ink)
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

    // MARK: - xG race

    /// A goal on the race: the running xG of the side that scored, at the
    /// moment it did.
    private struct GoalMarker: Identifiable {
        let id: String
        let elapsed: Double
        let xg: Double
        let team: String
    }

    private func goalMarkers(_ points: [GameDetail.XGRacePoint], game: Game) -> [GoalMarker] {
        var markers: [GoalMarker] = []
        for (previous, point) in zip(points, points.dropFirst()) {
            if point.awayGoals > previous.awayGoals {
                markers.append(GoalMarker(id: "a\(point.elapsed)", elapsed: point.elapsed, xg: point.awayXG, team: game.awayTeam))
            }
            if point.homeGoals > previous.homeGoals {
                markers.append(GoalMarker(id: "h\(point.elapsed)", elapsed: point.elapsed, xg: point.homeXG, team: game.homeTeam))
            }
        }
        return markers
    }

    /// The two clubs' colors for the race lines. Several matchups pair near
    /// identical navies (Seattle and Toronto, say), which turns the chart into
    /// one line; when the colors are that close the home line takes a
    /// contrasting accent so the two stay apart.
    private func raceColors(_ game: Game) -> (away: Color, home: Color) {
        let away = TeamColor.color(game.awayTeam)
        let home = TeamColor.color(game.homeTeam)
        func rgb(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
        let (ar, ag, ab) = rgb(away)
        let (hr, hg, hb) = rgb(home)
        let distance = ((ar - hr) * (ar - hr) + (ag - hg) * (ag - hg) + (ab - hb) * (ab - hb)).squareRoot()
        return distance < 0.45 ? (away, Color(red: 0.86, green: 0.56, blue: 0.10)) : (away, home)
    }

    private func xgRaceCard(_ detail: GameDetail, game: Game) -> some View {
        let points = detail.xgRace
        let end = max(3600, points.last?.elapsed ?? 3600)
        let top = max(1, (points.map { max($0.awayXG, $0.homeXG) }.max() ?? 1) * 1.15)
        let goals = goalMarkers(points, game: game)
        let awayName = displayTeamAbbr(game.awayTeam)
        let homeName = displayTeamAbbr(game.homeTeam)
        return card(title: "xG race") {
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value("xG", point.awayXG),
                            series: .value("Team", awayName)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value("Team", awayName))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value("xG", point.homeXG),
                            series: .value("Team", homeName)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value("Team", homeName))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    ForEach(goals) { goal in
                        PointMark(
                            x: .value("Time", goal.elapsed),
                            y: .value("xG", goal.xg)
                        )
                        .symbolSize(70)
                        .foregroundStyle(by: .value("Team", displayTeamAbbr(goal.team)))
                    }
                }
                .chartForegroundStyleScale([
                    awayName: raceColors(game).away,
                    homeName: raceColors(game).home,
                ])
                .chartLegend(position: .top, alignment: .leading)
                .chartYScale(domain: 0...top)
                .chartXScale(domain: 0...end)
                .chartXAxis {
                    AxisMarks(values: [0, 1200, 2400] + (end > 3600 ? [3600] : [])) { value in
                        AxisGridLine().foregroundStyle(RinkPalette.divider)
                        AxisValueLabel(anchor: .topLeading) {
                            let seconds = value.as(Double.self) ?? 0
                            Text(seconds >= 3600 ? "OT" : "P\(Int(seconds / 1200) + 1)")
                                .font(RinkType.micro)
                                .foregroundStyle(RinkPalette.inkTertiary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(RinkPalette.divider)
                        AxisValueLabel {
                            Text((value.as(Double.self) ?? 0).formatted(.number.precision(.fractionLength(1))))
                                .font(RinkType.micro)
                                .foregroundStyle(RinkPalette.inkTertiary)
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Expected goals race: \(teamFullName(game.awayTeam)) \((points.last?.awayXG ?? 0).formatted(.number.precision(.fractionLength(2)))), \(teamFullName(game.homeTeam)) \((points.last?.homeXG ?? 0).formatted(.number.precision(.fractionLength(2))))")

                Text("Cumulative expected goals by period. Dots mark goals.")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(RinkGeo.padCard)
        }
    }

    // MARK: - Chances

    /// "P2 12:34", "OT 3:05".
    private func periodLabel(_ play: GameDetail.BigPlay) -> String {
        let period: String
        switch play.period {
        case ...3: period = "P\(play.period)"
        case 4: period = "OT"
        default: period = "SO"
        }
        let clock = play.clock.hasPrefix("0") ? String(play.clock.dropFirst()) : play.clock
        return "\(period) \(clock)"
    }

    private func bigPlaysCard(_ detail: GameDetail, game: Game) -> some View {
        card(title: "Chances that decided it") {
            ForEach(Array(detail.bigPlays.enumerated()), id: \.element.id) { index, play in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(periodLabel(play))
                            .lineLimit(1)
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                        HStack(spacing: 4) {
                            TeamColorDot(abbr: play.team, size: 6)
                            Text(displayTeamAbbr(play.team))
                                .font(RinkType.micro)
                                .foregroundStyle(RinkPalette.inkSecondary)
                        }
                    }
                    .frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if let shooter = play.shooter {
                            Text(shooter)
                                .font(play.isGoal ? RinkType.bodyBold : RinkType.small)
                                .foregroundStyle(RinkPalette.ink)
                                .lineLimit(1)
                        }
                        Text(play.description)
                            .font(play.isGoal ? RinkType.smallBold : RinkType.small)
                            .foregroundStyle(play.isGoal ? RinkPalette.ink : RinkPalette.inkSecondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let xg = play.xg {
                        Text(xg.formatted(.number.precision(.fractionLength(2))) + " xG")
                            .font(RinkType.statSmall)
                            .fontWeight(play.isGoal ? .bold : .regular)
                            .foregroundStyle(play.isGoal ? RinkPalette.performanceHigh : RinkPalette.inkSecondary)
                            .lineLimit(1)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                .padding(.horizontal, RinkGeo.padInline)
                .padding(.vertical, 10)
                .background(index.isMultiple(of: 2) ? RinkPalette.surface : RinkPalette.surfaceAlt)
                .accessibilityElement(children: .combine)
            }
            footnoteRow("Every goal plus the five most dangerous shots that did not score.")
        }
    }

    // MARK: - Player lines

    @ViewBuilder
    private func playerLines(_ detail: GameDetail, game: Game) -> some View {
        if store.isPro {
            let team = linesTeam.isEmpty ? game.awayTeam : linesTeam
            teamPicker(game, team: team)
            let skaters = Array(detail.players(.skater, team: team).prefix(20))
            if !skaters.isEmpty {
                card(title: "Skaters") {
                    lineHeader([("TOI", 40), ("G", 22), ("A", 22), ("P", 22), ("SOG", 30), ("ixG", 40), ("GAx", 40)])
                    ForEach(Array(skaters.enumerated()), id: \.element.id) { index, line in
                        skaterRow(line, index: index)
                    }
                }
            }
            let goalies = detail.players(.goalie, team: team)
            if !goalies.isEmpty {
                card(title: "Goalies") {
                    lineHeader([("SV/SA", 48), ("GA", 24), ("xGA", 40), ("GSAx", 42), ("SV%", 42)])
                    ForEach(Array(goalies.enumerated()), id: \.element.id) { index, line in
                        goalieRow(line, index: index)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(RinkPalette.inkTertiary)
                Text("Every player's line")
                    .font(RinkType.cardTitle)
                    .foregroundStyle(RinkPalette.ink)
                Text("Individual expected goals, goals above expected, and each goalie's GSAx and save percentage for every player, ranked against the season.")
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PlusDirectCTA(trigger: .advancedBoxScore, style: .capsule)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(RinkPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    private func teamPicker(_ game: Game, team: String) -> some View {
        RinkSegmented(
            segments: [
                .init(value: game.awayTeam, label: teamFullName(game.awayTeam)),
                .init(value: game.homeTeam, label: teamFullName(game.homeTeam)),
            ],
            selection: Binding(get: { team }, set: { linesTeam = $0 })
        )
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    private func lineHeader(_ columns: [(String, CGFloat)]) -> some View {
        HStack(spacing: 0) {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column.0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: column.1, alignment: .trailing)
            }
        }
        .font(RinkType.micro)
        .foregroundStyle(RinkPalette.inkTertiary)
        .padding(.horizontal, RinkGeo.padInline)
        .frame(height: 26)
        .background(RinkPalette.surfaceAlt)
    }

    private func skaterRow(_ line: GameDetail.PlayerLine, index: Int) -> some View {
        lineRow(line, index: index, cells: [
            (line.toiLabel ?? "-", nil, 40),
            (count(line.goals), nil, 22),
            (count(line.assists), nil, 22),
            (count(line.points), nil, 22),
            (count(line.sog), nil, 30),
            rated(line.ixg, .decimal, width: 40),
            rated(line.gax, .signedDecimal, width: 40),
        ])
    }

    private func goalieRow(_ line: GameDetail.PlayerLine, index: Int) -> some View {
        let saves = line.saves.map(String.init) ?? "-"
        let faced = line.shotsAgainst.map(String.init) ?? "-"
        return lineRow(line, index: index, cells: [
            ("\(saves)/\(faced)", nil, 48),
            (count(line.goalsAgainst), nil, 24),
            rated(line.xga, .decimal, width: 40),
            rated(line.gsax, .signedDecimal, width: 42),
            ratedSavePercentage(line.svPct, width: 42),
        ])
    }

    private func count(_ value: Int?) -> String { value.map(String.init) ?? "-" }

    private func rated(_ value: RatedValue?, _ style: RateStyle, width: CGFloat) -> (String, Int?, CGFloat) {
        guard let value else { return ("-", nil, width) }
        return (style.format(value.value), value.percentile, width)
    }

    private func ratedSavePercentage(_ value: RatedValue?, width: CGFloat) -> (String, Int?, CGFloat) {
        guard let value else { return ("-", nil, width) }
        return (RecentMetricKey.savePercentage(value.value), value.percentile, width)
    }

    private func lineRow(_ line: GameDetail.PlayerLine, index: Int, cells: [(String, Int?, CGFloat)]) -> some View {
        let player = game.flatMap { viewModel.player(id: line.playerId, season: $0.season, phase: $0.seasonPhase) }
        let row = HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(player?.name ?? line.name ?? "Player")
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let position = line.position {
                    Text(position)
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell.0)
                    .font(RinkType.statSmall)
                    .fontWeight(cell.1 == nil ? .regular : .semibold)
                    .foregroundStyle(cell.1.map { RinkPalette.textColor(forPercentile: $0) } ?? RinkPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: cell.2, alignment: .trailing)
            }
        }
        .padding(.horizontal, RinkGeo.padInline)
        .frame(minHeight: 40)
        .background(index.isMultiple(of: 2) ? RinkPalette.surface : RinkPalette.surfaceAlt)
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

    private func upcomingCard(_ game: Game) -> some View {
        notice(
            icon: "calendar",
            title: "Not started yet",
            text: "The score and shot breakdown post here when the game goes final. Scout both rosters from the team pages above."
        )
    }

    // MARK: - Pieces

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: title)
            content()
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
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
                .foregroundStyle(RinkPalette.inkTertiary)
            Text(title)
                .font(RinkType.cardTitle)
                .foregroundStyle(RinkPalette.ink)
            Text(text)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.label, action: action.perform)
                    .font(RinkType.smallBold)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    private func footnoteRow(_ text: String) -> some View {
        Text(text)
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, RinkGeo.padCard)
            .padding(.vertical, 10)
    }
}
