import Foundation

/// One NHL game from `public.games`, synced from the league schedule.
///
/// Scores are null until the game is final. In-progress scores are not
/// published: a game past its start time with no score is "in progress", not 0-0.
struct Game: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let season: Int
    let seasonPhase: SeasonPhase
    /// REG, or the playoff round: R1, R2, CF or SCF.
    let gameType: String
    /// League week, counted from the week of opening night. Used for anchoring
    /// and coverage captions only; the app groups games by date.
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

    /// "W", "L" or "OTL" for a final, from `team`'s side. An overtime or
    /// shootout loss earns a point, so the standings vocabulary keeps it apart.
    func result(for team: String) -> String? {
        guard let mine = score(of: team), let theirs = score(of: opponent(of: team)) else { return nil }
        if mine > theirs { return "W" }
        return overtime ? "OTL" : "L"
    }

    /// "W 4-3 OT", team score first.
    func resultLine(for team: String) -> String? {
        guard let result = result(for: team),
              let mine = score(of: team),
              let theirs = score(of: opponent(of: team)) else { return nil }
        let shown = result == "OTL" ? "L" : result
        return "\(shown) \(mine)-\(theirs)\(overtime ? " OT" : "")"
    }

    /// "vs HOU" at home, "at HOU" away.
    func matchupLabel(for team: String) -> String {
        "\(isHome(team) ? "vs" : "at") \(displayTeamAbbr(opponent(of: team)))"
    }

    var roundLabel: String {
        GameDay.roundLabel(gameType: gameType)
    }

    func status(now: Date = .now) -> GameStatus {
        if isFinal { return .final }
        guard let kickoff else { return .upcoming }
        if now < kickoff { return .upcoming }
        // No live scores in the feed. Past a normal game length with no posted
        // final, say the score is on its way rather than "in progress" forever.
        return now.timeIntervalSince(kickoff) < 3.25 * 3_600 ? .inProgress : .awaitingScore
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

/// A selectable day of the schedule. Hockey plays most nights, so the unit a
/// fan thinks in is the date, not the week.
struct GameDay: Hashable, Identifiable, Sendable {
    /// Start of the day in the phone's calendar.
    let date: Date
    let phase: SeasonPhase

    var id: String { "\(phase.rawValue)-\(Self.key(date))" }

    /// "Today", "Yesterday", "Tomorrow", else "Tue, Oct 7".
    func label(now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var label: String { label(now: .now) }

    /// Short chip text: "Oct 7".
    var shortLabel: String { date.formatted(.dateTime.month(.abbreviated).day()) }

    static func roundLabel(gameType: String) -> String {
        switch gameType.uppercased() {
        case "R1": return "Round 1"
        case "R2": return "Round 2"
        case "CF": return "Conference Final"
        case "SCF": return "Stanley Cup Final"
        default: return "Regular Season"
        }
    }

    static func key(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    /// The local calendar day a game belongs to, from its start time when
    /// known. A 7:00 PM Pacific start is the same night everywhere in North
    /// America, which is what the schedule date already says.
    static func day(of game: Game) -> Date {
        Calendar.current.startOfDay(for: game.kickoff ?? game.gameDate)
    }

    static func days(in games: [Game]) -> [GameDay] {
        var seen: [String: GameDay] = [:]
        for game in games {
            let day = GameDay(date: day(of: game), phase: game.seasonPhase)
            seen[day.id] = day
        }
        return seen.values.sorted { $0.date < $1.date }
    }

    /// The day a fan means by "tonight".
    ///
    /// Today's slate while there is one. Until mid-afternoon the previous
    /// night's finals are what people are talking about, so before 2 PM local
    /// yesterday's games stay on the front door if nothing has started yet
    /// today. With no games today, the most recent day with games; before
    /// the season, the first.
    static func current(in games: [Game], now: Date = .now) -> GameDay? {
        let days = days(in: games)
        guard !days.isEmpty else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let hour = calendar.component(.hour, from: now)
        if let todays = days.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            let started = todays.games(from: games).contains { ($0.kickoff ?? $0.gameDate) <= now }
            if started || hour >= 14 { return todays }
            if let yesterday = days.last(where: { $0.date < today }) { return yesterday }
            return todays
        }
        return days.last { $0.date < today } ?? days.first
    }

    func games(from games: [Game]) -> [Game] {
        games.filter { Self.day(of: $0) == date && $0.seasonPhase == phase }
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

    /// "Tue 7:00 PM" in the phone's zone.
    var kickoffLabel: String {
        guard let kickoff else { return gameDate.formatted(DataCoverage.gameDayStyle) }
        return kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Tue, Oct 7".
    var dayLabel: String {
        guard let kickoff else { return gameDate.formatted(DataCoverage.gameDayStyle) }
        return kickoff.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
