import SwiftUI

/// Route to one game's detail page. Registered with the player-profile route so
/// every tab that can show a player can also open the game he played in.
struct GameRoute: Hashable {
    let gameId: String
}

/// The week's slate: who played whom, the finals, what is on next.
///
/// This is the football-first front door. Scores, schedule and box scores are
/// free for everyone; the analysis layers stay where they were.
struct GamesView: View {
    @Bindable var viewModel: DashboardViewModel
    let isActive: Bool
    @State private var favorites = FavoritesStore.shared
    @State private var selectedWeekID: String?

    private var weeks: [GameWeek] { GameWeek.weeks(in: viewModel.games) }

    private var selectedWeek: GameWeek? {
        weeks.first { $0.id == selectedWeekID } ?? viewModel.currentGameWeek
    }

    private var slate: [Game] {
        guard let selectedWeek else { return [] }
        return Game.slateOrder(selectedWeek.games(from: viewModel.games))
    }

    /// Clubs on this week's schedule, for the bye line.
    private var byeTeams: [String] {
        guard selectedWeek?.phase == .regular, !slate.isEmpty else { return [] }
        let playing = Set(slate.flatMap { [normalizedTeamAbbreviation($0.awayTeam), normalizedTeamAbbreviation($0.homeTeam)] })
        return leagueTeamAbbreviations.filter { !playing.contains($0) }
    }

    /// "Week 3 · Sep 24 - 28", so the slate and the Stats caption ("Through
    /// Week 3") are plainly two different things.
    private var weekDateRange: String? {
        guard let selectedWeek else { return nil }
        let days = slate.compactMap(\.kickoff)
        guard let first = days.min(), let last = days.max() else { return nil }
        let style = Date.FormatStyle().month(.abbreviated).day()
        let calendar = Calendar.current
        let range = calendar.isDate(first, inSameDayAs: last)
            ? first.formatted(style)
            : calendar.isDate(first, equalTo: last, toGranularity: .month)
                ? "\(first.formatted(style)) - \(last.formatted(.dateTime.day()))"
                : "\(first.formatted(style)) - \(last.formatted(style))"
        return "\(selectedWeek.label) · \(range)"
    }

    private var favoriteGame: Game? {
        guard let team = favorites.team else { return nil }
        return slate.first { $0.involves(team) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.games.isEmpty {
                    emptyState
                } else {
                    weekSelector
                        .padding(.top, 10)
                    if let range = weekDateRange {
                        Text(range)
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    content
                }
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RinkPalette.canvas.ignoresSafeArea())
        .refreshable { await viewModel.loadGames(force: true) }
        .task(id: isActive) {
            guard isActive else { return }
            await pollWhileActive()
        }
    }

    /// Re-reads the schedule while this tab is on screen: every two minutes
    /// while a game is under way or a final is still waiting on its stats, every
    /// ten otherwise. The backend itself only updates every fifteen minutes on a
    /// game day, so anything faster would be noise.
    private func pollWhileActive() async {
        while !Task.isCancelled {
            await viewModel.loadGames()
            let now = Date()
            let busy = viewModel.games.contains { game in
                switch game.status(now: now) {
                case .inProgress, .awaitingScore: return true
                case .final:
                    guard let kickoff = game.kickoff else { return false }
                    return !viewModel.hasStats(game) && now.timeIntervalSince(kickoff) < 12 * 3_600
                case .upcoming: return false
                }
            }
            try? await Task.sleep(for: .seconds(busy ? 120 : 600))
        }
    }

    // MARK: - Week selector

    private var weekSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(weeks) { week in
                        let isSelected = week.id == selectedWeek?.id
                        Button {
                            selectedWeekID = week.id
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(week.shortLabel)
                                .font(RinkType.smallBold)
                                .foregroundStyle(isSelected ? .white : RinkPalette.inkSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: RinkControl.height)
                                .background(isSelected ? RinkPalette.turf : RinkPalette.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : RinkPalette.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .id(week.id)
                        .accessibilityLabel(week.label)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                    }
                }
                .padding(.horizontal, 12)
            }
            .onAppear {
                if let id = selectedWeek?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: selectedWeek?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: - Slate

    @ViewBuilder
    private var content: some View {
        if let favoriteGame {
            section(title: "Your team", games: [favoriteGame])
        }
        let now = Date()
        let remaining = slate.filter { $0.id != favoriteGame?.id }
        let live = remaining.filter { [.inProgress, .awaitingScore].contains($0.status(now: now)) }
        let finals = remaining.filter { $0.status(now: now) == .final }
        let upcoming = remaining.filter { $0.status(now: now) == .upcoming }
        if !live.isEmpty { section(title: "In progress", games: live) }
        if !finals.isEmpty { section(title: "Final", games: finals) }
        if !upcoming.isEmpty { section(title: "Upcoming", games: upcoming) }

        if upcoming.contains(where: { viewModel.projection(for: $0) != nil }) {
            Text("Projected margins come from StatScout Power Ratings: each club's efficiency and scoring against an average team, adjusted for schedule, plus two points for home field. Details on the Teams tab.")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }

        if !byeTeams.isEmpty {
            Text("Bye: " + byeTeams.map(displayTeamAbbr).joined(separator: ", "))
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }

        Text(favorites.team == nil
             ? "Scores post when each game goes final, stats usually within a few hours. Follow a team from its page to pin its game here."
             : "Scores post when each game goes final. Player stats usually follow within a few hours.")
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func section(title: String, games: [Game]) -> some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: title)
            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                NavigationLink(value: GameRoute(gameId: game.id)) {
                    GameRow(
                        game: game,
                        hasStats: viewModel.hasStats(game),
                        highlight: favorites.team,
                        awayRecord: viewModel.record(forTeam: game.awayTeam, through: game),
                        homeRecord: viewModel.record(forTeam: game.homeTeam, through: game),
                        projection: viewModel.projection(for: game)
                    )
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
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isGamesLoading {
            ProgressView("Loading games")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            ContentUnavailableView {
                Label(
                    viewModel.gamesError == nil ? "No games scheduled" : "Couldn't load games",
                    systemImage: viewModel.gamesError == nil ? "calendar" : "wifi.slash"
                )
            } description: {
                Text(viewModel.gamesError ?? "The \(String(viewModel.freeSeason)) schedule isn't published yet.")
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.loadGames(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(RinkPalette.turf)
            }
            .padding(.vertical, 48)
        }
    }
}

// MARK: - Row

/// Two stacked team lines with scores, and the status on the right.
struct GameRow: View {
    let game: Game
    let hasStats: Bool
    var highlight: String? = nil
    /// Each club's record through this game: after it for a final, going into
    /// it for one still to be played.
    var awayRecord: String? = nil
    var homeRecord: String? = nil
    /// The power ratings' projected margin, upcoming games only.
    var projection: GameProjection? = nil

    var body: some View {
        let status = game.status()
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                teamLine(game.awayTeam, score: game.awayScore, status: status, record: awayRecord)
                teamLine(game.homeTeam, score: game.homeScore, status: status, record: homeRecord)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 3) {
                Text(statusTitle(status))
                    .font(RinkType.smallBold)
                    .foregroundStyle(status == .inProgress ? RinkPalette.performanceLow : RinkPalette.ink)
                if let detail = statusDetail(status) {
                    Text(detail)
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                }
            }
            .frame(width: 104, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RinkPalette.inkTertiary)
        }
        .padding(.horizontal, RinkGeo.padInline)
        .padding(.vertical, 10)
        .overlay(
            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(status))
        .accessibilityHint("Opens the game")
    }

    private func teamLine(_ team: String, score: Int?, status: GameStatus, record: String?) -> some View {
        let isWinner = game.result(for: team) == "W"
        let dim = status == .final && !isWinner && game.result(for: team) != "T"
        return HStack(spacing: 8) {
            TeamColorDot(abbr: team, size: 10)
            Text(displayTeamAbbr(team))
                .font(RinkType.bodyBold)
                .foregroundStyle(dim ? RinkPalette.inkTertiary : RinkPalette.ink)
                .frame(width: 40, alignment: .leading)
            Text(teamFullName(team))
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let record {
                Text(record)
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
            if let highlight, normalizedTeamAbbreviation(highlight) == normalizedTeamAbbreviation(team) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.yellow)
            }
            Spacer(minLength: 4)
            if let score {
                Text("\(score)")
                    .font(RinkType.statMed)
                    .foregroundStyle(dim ? RinkPalette.inkTertiary : RinkPalette.ink)
                    .monospacedDigit()
            }
        }
    }

    private func statusTitle(_ status: GameStatus) -> String {
        switch status {
        case .final: return game.overtime ? "Final/OT" : "Final"
        case .inProgress: return "In progress"
        case .awaitingScore: return "Final soon"
        case .upcoming: return game.kickoffLabel
        }
    }

    private func statusDetail(_ status: GameStatus) -> String? {
        switch status {
        case .final: return hasStats ? game.dayLabel : "Stats arriving"
        case .inProgress, .awaitingScore: return "Score at final"
        case .upcoming:
            if let projection {
                return projection.label(home: game.homeTeam, away: game.awayTeam)
            }
            return game.kickoff.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        }
    }

    private func accessibilityText(_ status: GameStatus) -> String {
        let away = teamFullName(game.awayTeam)
        let home = teamFullName(game.homeTeam)
        switch status {
        case .final:
            let score = "\(away) \(game.awayScore ?? 0), \(home) \(game.homeScore ?? 0)"
            return "\(score), \(statusTitle(status))" + (hasStats ? "" : ", stats arriving")
        case .inProgress, .awaitingScore:
            return "\(away) at \(home), in progress"
        case .upcoming:
            let projected = projection.map { ", projected \($0.label(home: game.homeTeam, away: game.awayTeam))" } ?? ""
            return "\(away) at \(home), \(game.dayLabel) at \(game.kickoff?.formatted(date: .omitted, time: .shortened) ?? "time TBD")\(projected)"
        }
    }
}
