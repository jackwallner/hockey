import SwiftUI

struct TeamScheduleRoute: Hashable {
    let team: String
}

/// A team's game this week, on its team page: the result, the next kickoff, or
/// the bye. It sits above the roster cards so the first thing a team page says
/// is what happened on the field. Under it: follow the club, open its schedule.
struct TeamWeekGameCard: View {
    @Bindable var viewModel: DashboardViewModel
    let team: String
    @State private var favorites = FavoritesStore.shared

    var body: some View {
        if let week = viewModel.currentGameWeek {
            VStack(spacing: 8) {
                if let game = viewModel.currentGame(forTeam: team) {
                    NavigationLink(value: GameRoute(gameId: game.id)) {
                        content(week: week, game: game)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the game")
                } else if week.phase == .regular {
                    shell(week: week) {
                        Text("Bye week")
                            .font(GridironType.bodyBold)
                            .foregroundStyle(GridironPalette.ink)
                        Spacer(minLength: 0)
                    }
                }
                actions
            }
        }
    }

    private var actions: some View {
        let following = favorites.isFavorite(team: normalizedTeamAbbreviation(team))
        return HStack(spacing: 8) {
            Button {
                favorites.setFavorite(team: following ? nil : normalizedTeamAbbreviation(team))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                GridironChip(
                    title: following ? "Your team" : "Follow team",
                    systemImage: following ? "star.fill" : "star",
                    isActive: following
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(following ? "Stops pinning this team's games" : "Pins this team's games at the top of Games")

            NavigationLink(value: TeamScheduleRoute(team: normalizedTeamAbbreviation(team))) {
                GridironChip(title: "Schedule", systemImage: "calendar")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func content(week: GameWeek, game: Game) -> some View {
        shell(week: week) {
            TeamColorDot(abbr: game.opponent(of: team), size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.matchupLabel(for: team)) · \(teamFullName(game.opponent(of: team)))")
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detail(game))
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
            Spacer(minLength: 8)
            if let line = game.resultLine(for: team) {
                Text(line)
                    .font(GridironType.statMed)
                    .foregroundStyle(game.result(for: team) == "L" ? GridironPalette.performanceLow : GridironPalette.performanceHigh)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GridironPalette.inkTertiary)
        }
    }

    private func detail(_ game: Game) -> String {
        switch game.status() {
        case .final:
            return viewModel.hasStats(game) ? "Final · box score" : "Final · stats arriving"
        case .inProgress, .awaitingScore:
            return "In progress"
        case .upcoming:
            return "\(game.dayLabel), \(game.kickoff?.formatted(date: .omitted, time: .shortened) ?? "time TBD")"
        }
    }

    private func shell<Content: View>(week: GameWeek, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(([week.label] + [viewModel.record(forTeam: team)].compactMap { $0 }).joined(separator: " · ").uppercased())
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
            HStack(spacing: 10) {
                content()
            }
        }
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

/// One club's season: every week, the opponent, the result or the kickoff.
struct TeamScheduleView: View {
    @Bindable var viewModel: DashboardViewModel
    let team: String

    var body: some View {
        let games = viewModel.schedule(forTeam: team)
        ScrollView {
            LazyVStack(spacing: 0) {
                VStack(spacing: 0) {
                    GridironSectionBar(
                        title: "\(String(viewModel.freeSeason)) schedule",
                        trailing: viewModel.record(forTeam: team).map {
                            AnyView(Text($0).font(GridironType.statSmall).foregroundStyle(GridironPalette.inkSecondary))
                        }
                    )
                    ForEach(Array(entries(games).enumerated()), id: \.element.id) { index, entry in
                        let background = index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt
                        switch entry {
                        case .game(let game):
                            NavigationLink(value: GameRoute(gameId: game.id)) {
                                row(game).background(background)
                            }
                            .buttonStyle(.plain)
                        case .bye(let week):
                            byeRow(week).background(background)
                        }
                    }
                    if games.isEmpty {
                        Text(viewModel.isGamesLoading ? "Loading schedule" : "Schedule not published yet")
                            .font(GridironType.small)
                            .foregroundStyle(GridironPalette.inkTertiary)
                            .padding(.vertical, 32)
                    }
                }
                .background(GridironPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                        .stroke(GridironPalette.hairline, lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
                Color.clear.frame(height: 88)
            }
        }
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationTitle(teamFullName(team))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadGames() }
    }

    enum Entry: Identifiable {
        case game(Game)
        case bye(Int)

        var id: String {
            switch self {
            case .game(let game): return game.id
            case .bye(let week): return "bye-\(week)"
            }
        }
    }

    /// The schedule with the bye week slotted in where the club has no game.
    private func entries(_ games: [Game]) -> [Entry] {
        let regularWeeks = Set(viewModel.games.filter { $0.seasonPhase == .regular }.map(\.week))
        let played = Set(games.filter { $0.seasonPhase == .regular }.map(\.week))
        var result: [Entry] = []
        for week in regularWeeks.sorted() {
            if let game = games.first(where: { $0.seasonPhase == .regular && $0.week == week }) {
                result.append(.game(game))
            } else if !played.contains(week) {
                result.append(.bye(week))
            }
        }
        result += games.filter { $0.seasonPhase != .regular }.map(Entry.game)
        return result
    }

    private func byeRow(_ week: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(week)")
                .font(GridironType.statSmall)
                .foregroundStyle(GridironPalette.inkTertiary)
                .frame(width: 30, alignment: .leading)
            Text("Bye week")
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.inkTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GridironGeo.padInline)
        .frame(minHeight: 44)
        .overlay(Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline), alignment: .bottom)
    }

    private func row(_ game: Game) -> some View {
        HStack(spacing: 10) {
            Text(game.seasonPhase == .regular ? "\(game.week)" : game.gameType)
                .font(GridironType.statSmall)
                .foregroundStyle(GridironPalette.inkTertiary)
                .frame(width: 30, alignment: .leading)
            TeamColorDot(abbr: game.opponent(of: team), size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.matchupLabel(for: team)) · \(teamFullName(game.opponent(of: team)))")
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(game.dayLabel)
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
            Spacer(minLength: 8)
            if let line = game.resultLine(for: team) {
                Text(line)
                    .font(GridironType.statMed)
                    .foregroundStyle(game.result(for: team) == "L" ? GridironPalette.performanceLow : GridironPalette.performanceHigh)
            } else {
                Text(game.status() == .upcoming ? (game.kickoff?.formatted(date: .omitted, time: .shortened) ?? "TBD") : "In progress")
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GridironPalette.inkTertiary)
        }
        .padding(.horizontal, GridironGeo.padInline)
        .frame(minHeight: 52)
        .overlay(Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
    }
}

/// A player's most recent game on his profile: opponent, result, his line, and
/// a way into the box score. Free, and real: the one-game answer to "how did he
/// look?" that the recent-form cards can't give until there are several games.
struct PlayerLastGameCard: View {
    @Bindable var viewModel: DashboardViewModel
    let player: Player
    let season: Int
    let phase: SeasonPhase

    @State private var log: PlayerGameLog?
    @State private var loadedKey: String?

    private var key: String {
        "\(player.playerId)-\(season)-\(phase.rawValue)-\(viewModel.freshnessRevision ?? "none")"
    }

    private var game: Game? {
        log?.gameId.flatMap { viewModel.game(id: $0) }
    }

    var body: some View {
        // A VStack, not a Group: modifiers on an empty Group land on no view,
        // so the task that fetches the log would never run.
        VStack(spacing: 0) {
            if let log {
                card(log)
                    .padding(.top, 10)
            }
        }
        .task(id: key) { await load() }
    }

    private func load() async {
        guard loadedKey != key else { return }
        do {
            let logs = try await viewModel.fetchGameLogs(playerId: player.playerId, season: season, seasonPhase: phase)
            log = logs.max { $0.gameDate < $1.gameDate }
            loadedKey = key
        } catch {
            if !isTaskCancellation(error) { loadedKey = nil }
        }
    }

    @ViewBuilder
    private func card(_ log: PlayerGameLog) -> some View {
        let line = GameBoxScore(logs: [log]).lines[0]
        let team = log.team ?? player.team
        let summary = GameBoxScore.summary(line)
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title(log).uppercased())
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkSecondary)
                Spacer(minLength: 0)
                if game != nil {
                    Text("Box score")
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.turf)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GridironPalette.turf)
                }
            }
            HStack(spacing: 8) {
                Text(matchup(log, team: team))
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
                    .lineLimit(1)
                if let result = game?.resultLine(for: team) {
                    Text(result)
                        .font(GridironType.statSmall)
                        .foregroundStyle(game?.result(for: team) == "L" ? GridironPalette.performanceLow : GridironPalette.performanceHigh)
                }
                Spacer(minLength: 0)
            }
            if !summary.isEmpty {
                Text(summary)
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .contentShape(Rectangle())

        if let game {
            NavigationLink(value: GameRoute(gameId: game.id)) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the game")
        } else {
            content
        }
    }

    private func title(_ log: PlayerGameLog) -> String {
        if let game { return "Last game · \(game.roundLabel)" }
        return "Last game · \(log.gameDate.formatted(DataCoverage.gameDayStyle))"
    }

    private func matchup(_ log: PlayerGameLog, team: String) -> String {
        if let game { return "\(game.matchupLabel(for: team)) · \(game.dayLabel)" }
        return "vs \(displayTeamAbbr(log.opponent ?? ""))"
    }
}

/// Every game this season, newest first: week, opponent, result, and the
/// player's line. The week-by-week view a 17-game sport is read in, free, and
/// the natural companion to the Pro rolling windows.
struct PlayerGameLogCard: View {
    @Bindable var viewModel: DashboardViewModel
    let player: Player
    let season: Int
    let phase: SeasonPhase

    @State private var entries: [Entry] = []
    @State private var loadedKey: String?
    @State private var failed = false

    struct Entry: Identifiable, Hashable {
        let id: String
        let gameId: String?
        let gameDate: Date
        let team: String
        let opponent: String?
        let summary: String
    }

    private var key: String {
        "\(player.playerId)-\(season)-\(phase.rawValue)-\(viewModel.freshnessRevision ?? "none")"
    }

    var body: some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: "GAME LOG")
            if entries.isEmpty {
                Text(failed ? "Couldn't load games. Pull to refresh." : (loadedKey == nil ? "Loading games…" : "No games yet this season."))
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                        .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
                }
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .task(id: key) { await load() }
    }

    private func load() async {
        guard loadedKey != key else { return }
        do {
            let logs = try await viewModel.fetchGameLogs(playerId: player.playerId, season: season, seasonPhase: phase)
            entries = Self.entries(from: logs, fallbackTeam: player.team)
            loadedKey = key
            failed = false
        } catch {
            if !isTaskCancellation(error) { failed = true }
        }
    }

    /// One entry per game; a player with two roles in a game (a rushing QB is
    /// one row, a two-way player two) reads as one line.
    static func entries(from logs: [PlayerGameLog], fallbackTeam: String) -> [Entry] {
        let grouped = Dictionary(grouping: logs) { $0.gameId ?? ISO8601DateFormatter().string(from: $0.gameDate) }
        return grouped.map { id, rows in
            let first = rows[0]
            let summary = GameBoxScore(logs: rows).lines
                .map(GameBoxScore.summary)
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return Entry(
                id: id,
                gameId: first.gameId,
                gameDate: first.gameDate,
                team: first.team ?? fallbackTeam,
                opponent: first.opponent,
                summary: summary
            )
        }
        .sorted { $0.gameDate > $1.gameDate }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let game = entry.gameId.flatMap { viewModel.game(id: $0) }
        let content = HStack(alignment: .top, spacing: 10) {
            Text(game.map { $0.seasonPhase == .regular ? "\($0.week)" : $0.gameType } ?? "-")
                .font(GridironType.statSmall)
                .foregroundStyle(GridironPalette.inkTertiary)
                .frame(width: 28, alignment: .leading)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(game?.matchupLabel(for: entry.team) ?? "vs \(displayTeamAbbr(entry.opponent ?? ""))")
                        .font(GridironType.bodyBold)
                        .foregroundStyle(GridironPalette.ink)
                    if let line = game?.resultLine(for: entry.team) {
                        Text(line)
                            .font(GridironType.statSmall)
                            .foregroundStyle(game?.result(for: entry.team) == "L" ? GridironPalette.performanceLow : GridironPalette.performanceHigh)
                    }
                    Spacer(minLength: 0)
                    Text(entry.gameDate.formatted(DataCoverage.gameDayStyle))
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                }
                Text(entry.summary.isEmpty ? "No box score line" : entry.summary)
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())

        if let game {
            NavigationLink(value: GameRoute(gameId: game.id)) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the game")
        } else {
            content
        }
    }
}
