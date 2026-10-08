import Foundation

/// One NFL game from `public.games`, the published nflverse schedule.
///
/// Scores are null until nflverse posts a final. There is no live score feed:
/// a game past kickoff with no score is "in progress", not 0-0.
struct Game: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let season: Int
    let seasonPhase: SeasonPhase
    /// REG, WC, DIV, CON or SB.
    let gameType: String
    let week: Int
    let kickoff: Date?
    let gameDate: Date
    let awayTeam: String
    let homeTeam: String
    let awayScore: Int?
    let homeScore: Int?
    let overtime: Bool
    let stadium: String?

    enum CodingKeys: String, CodingKey {
        case id = "game_id"
        case season
        case seasonPhase = "season_type"
        case gameType = "game_type"
        case week
        case kickoff = "kickoff_at"
        case gameDate = "game_date"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case awayScore = "away_score"
        case homeScore = "home_score"
        case overtime
        case stadium
    }

    init(
        id: String,
        season: Int,
        seasonPhase: SeasonPhase = .regular,
        gameType: String = "REG",
        week: Int,
        kickoff: Date?,
        gameDate: Date? = nil,
        awayTeam: String,
        homeTeam: String,
        awayScore: Int? = nil,
        homeScore: Int? = nil,
        overtime: Bool = false,
        stadium: String? = nil
    ) {
        self.id = id
        self.season = season
        self.seasonPhase = seasonPhase
        self.gameType = gameType
        self.week = week
        self.kickoff = kickoff
        self.gameDate = gameDate ?? kickoff ?? .distantPast
        self.awayTeam = awayTeam
        self.homeTeam = homeTeam
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.overtime = overtime
        self.stadium = stadium
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        season = try c.decode(Int.self, forKey: .season)
        seasonPhase = try c.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        gameType = try c.decodeIfPresent(String.self, forKey: .gameType) ?? "REG"
        week = try c.decode(Int.self, forKey: .week)
        kickoff = try c.decodeIfPresent(String.self, forKey: .kickoff).flatMap(DataFreshness.parseDate)
        let rawDate = try c.decode(String.self, forKey: .gameDate)
        guard let parsed = DataFreshness.parseDate(rawDate) else {
            throw DecodingError.dataCorruptedError(forKey: .gameDate, in: c, debugDescription: "Invalid game_date: \(rawDate)")
        }
        gameDate = parsed
        awayTeam = try c.decode(String.self, forKey: .awayTeam)
        homeTeam = try c.decode(String.self, forKey: .homeTeam)
        awayScore = try c.decodeIfPresent(Int.self, forKey: .awayScore)
        homeScore = try c.decodeIfPresent(Int.self, forKey: .homeScore)
        overtime = try c.decodeIfPresent(Bool.self, forKey: .overtime) ?? false
        stadium = try c.decodeIfPresent(String.self, forKey: .stadium)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(season, forKey: .season)
        try c.encode(seasonPhase, forKey: .seasonPhase)
        try c.encode(gameType, forKey: .gameType)
        try c.encode(week, forKey: .week)
        let iso = ISO8601DateFormatter()
        try c.encodeIfPresent(kickoff.map { iso.string(from: $0) }, forKey: .kickoff)
        try c.encode(iso.string(from: gameDate), forKey: .gameDate)
        try c.encode(awayTeam, forKey: .awayTeam)
        try c.encode(homeTeam, forKey: .homeTeam)
        try c.encodeIfPresent(awayScore, forKey: .awayScore)
        try c.encodeIfPresent(homeScore, forKey: .homeScore)
        try c.encode(overtime, forKey: .overtime)
        try c.encodeIfPresent(stadium, forKey: .stadium)
    }

    var isFinal: Bool { awayScore != nil && homeScore != nil }

    func involves(_ team: String) -> Bool {
        let abbr = normalizedTeamAbbreviation(team)
        return normalizedTeamAbbreviation(awayTeam) == abbr || normalizedTeamAbbreviation(homeTeam) == abbr
    }

    func opponent(of team: String) -> String {
        normalizedTeamAbbreviation(awayTeam) == normalizedTeamAbbreviation(team) ? homeTeam : awayTeam
    }

    func isHome(_ team: String) -> Bool {
        normalizedTeamAbbreviation(homeTeam) == normalizedTeamAbbreviation(team)
    }

    func score(of team: String) -> Int? {
        isHome(team) ? homeScore : awayScore
    }

    /// "W", "L" or "T" for a final, from `team`'s side.
    func result(for team: String) -> String? {
        guard let mine = score(of: team), let theirs = score(of: opponent(of: team)) else { return nil }
        if mine == theirs { return "T" }
        return mine > theirs ? "W" : "L"
    }

    /// "W 36-31", team score first.
    func resultLine(for team: String) -> String? {
        guard let result = result(for: team),
              let mine = score(of: team),
              let theirs = score(of: opponent(of: team)) else { return nil }
        return "\(result) \(mine)-\(theirs)\(overtime ? " OT" : "")"
    }

    /// "vs HOU" at home, "at HOU" away.
    func matchupLabel(for team: String) -> String {
        "\(isHome(team) ? "vs" : "at") \(displayTeamAbbr(opponent(of: team)))"
    }

    var roundLabel: String {
        GameWeek.label(week: week, gameType: gameType)
    }

    func status(now: Date = .now) -> GameStatus {
        if isFinal { return .final }
        guard let kickoff else { return .upcoming }
        if now < kickoff { return .upcoming }
        // No live scores in the feed. Past a normal game length with no posted
        // final, say the score is on its way rather than "in progress" forever.
        return now.timeIntervalSince(kickoff) < 4.5 * 3_600 ? .inProgress : .awaitingScore
    }
}

enum GameStatus: Equatable, Sendable {
    case upcoming
    case inProgress
    case awaitingScore
    case final

    var sortOrder: Int {
        switch self {
        case .inProgress: return 0
        case .awaitingScore: return 1
        case .final: return 2
        case .upcoming: return 3
        }
    }
}

/// A selectable week of the schedule: regular-season weeks, then playoff rounds.
struct GameWeek: Hashable, Identifiable, Sendable {
    let week: Int
    let phase: SeasonPhase
    let label: String

    var id: String { "\(phase.rawValue)-\(week)" }

    /// Short chip text: "Wk 1", "WC", "SB".
    var shortLabel: String {
        phase == .regular ? "Wk \(week)" : label
    }

    static func label(week: Int, gameType: String) -> String {
        switch gameType.uppercased() {
        case "WC": return "Wild Card"
        case "DIV": return "Divisional"
        case "CON": return "Conference"
        case "SB": return "Super Bowl"
        default: return "Week \(week)"
        }
    }

    static func weeks(in games: [Game]) -> [GameWeek] {
        var seen: [String: GameWeek] = [:]
        for game in games {
            let week = GameWeek(
                week: game.week,
                phase: game.seasonPhase,
                label: game.seasonPhase == .regular ? "Week \(game.week)" : label(week: game.week, gameType: game.gameType)
            )
            seen[week.id] = week
        }
        return seen.values.sorted {
            ($0.phase == .regular ? 0 : 1, $0.week) < ($1.phase == .regular ? 0 : 1, $1.week)
        }
    }

    /// The week a fan means by "this week".
    ///
    /// A week stays current until a day before the next week's first kickoff:
    /// Monday night's result, and the whole weekend's finals, stay on screen
    /// through Wednesday, when the talk is still about them, and the next slate
    /// takes over on the eve of Thursday night. It used to hand over 36 hours
    /// after the last kickoff, which put a list of future kickoff times with no
    /// scores in it on the front door from Wednesday morning. Before the season
    /// it is the first week; after it, the last.
    static func current(in games: [Game], now: Date = .now) -> GameWeek? {
        let weeks = weeks(in: games)
        for (index, week) in weeks.enumerated() {
            guard index + 1 < weeks.count,
                  let nextFirst = firstKickoff(of: weeks[index + 1], in: games) else { return week }
            if now < nextFirst.addingTimeInterval(-24 * 3_600) { return week }
        }
        return weeks.last
    }

    private static func firstKickoff(of week: GameWeek, in games: [Game]) -> Date? {
        games.filter { $0.week == week.week && $0.seasonPhase == week.phase }
            .compactMap(\.kickoff)
            .min()
    }

    func games(from games: [Game]) -> [Game] {
        games.filter { $0.week == week && $0.seasonPhase == phase }
    }
}

extension Game {
    /// Orders a slate: in progress, then finals, then upcoming, each by kickoff.
    static func slateOrder(_ games: [Game], now: Date = .now) -> [Game] {
        games.sorted {
            let a = $0.status(now: now).sortOrder
            let b = $1.status(now: now).sortOrder
            if a != b { return a < b }
            return ($0.kickoff ?? $0.gameDate, $0.id) < ($1.kickoff ?? $1.gameDate, $1.id)
        }
    }

    /// "Sun 1:00 PM" in the phone's zone.
    var kickoffLabel: String {
        guard let kickoff else { return gameDate.formatted(DataCoverage.gameDayStyle) }
        return kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Sun, Sep 13".
    var dayLabel: String {
        guard let kickoff else { return gameDate.formatted(DataCoverage.gameDayStyle) }
        return kickoff.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
