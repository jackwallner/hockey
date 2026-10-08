import Foundation

/// One player's contribution in one game (one row per player_type). Powers the
/// Recent Form card.
struct PlayerGameLog: Codable, Hashable, Sendable {
    let playerId: Int
    let season: Int
    /// Regular season or playoffs.
    ///
    /// The row has always carried this (`player_game_logs.season_type`); nothing
    /// read it, and nothing filtered on it either, so every "last N games" window
    /// in the app was built from whichever games happened most recently
    /// regardless of phase. For a club that reached the playoffs that meant the
    /// *Regular Season* board's last five games were mostly playoff games - the
    /// postseason is what sits at the top of a date-descending list - and the
    /// Playoffs board padded its short run out with December.
    let seasonPhase: SeasonPhase
    /// NHL game id, e.g. "2026020012". The join key to `Game`.
    /// Optional because rows ingested before the column existed carry none.
    var gameId: String? = nil
    let gameDate: Date
    let playerType: String
    let team: String?
    let opponent: String?
    /// Ice time in whole minutes (the column keeps its football name).
    let plays: Int
    /// Shot attempts for a skater, shots against for a goalie.
    let touches: Int
    let metrics: [String: Double?]

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case seasonPhase = "season_type"
        case gameId = "game_id"
        case gameDate = "game_date"
        case playerType = "player_type"
        case team
        case opponent
        case plays
        case touches
        case metrics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        // Defaulted rather than required: the fixtures in the test suite predate
        // the column, and a row with no phase is a regular-season row.
        seasonPhase = try c.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        playerType = try c.decode(String.self, forKey: .playerType)
        gameId = try c.decodeIfPresent(String.self, forKey: .gameId)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        opponent = try c.decodeIfPresent(String.self, forKey: .opponent)
        plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        touches = try c.decodeIfPresent(Int.self, forKey: .touches) ?? 0

        // game_date arrives as "YYYY-MM-DD" from Supabase (date column, not timestamptz).
        let raw = try c.decode(String.self, forKey: .gameDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        guard let parsed = formatter.date(from: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .gameDate, in: c, debugDescription: "Invalid game_date: \(raw)")
        }
        gameDate = parsed

        // metrics is a JSONB object with nullable numeric values.
        if let dict = try? c.decode([String: Double?].self, forKey: .metrics) {
            metrics = dict
        } else {
            metrics = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(season, forKey: .season)
        try c.encode(seasonPhase, forKey: .seasonPhase)
        try c.encode(playerType, forKey: .playerType)
        try c.encodeIfPresent(gameId, forKey: .gameId)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encodeIfPresent(opponent, forKey: .opponent)
        try c.encode(plays, forKey: .plays)
        try c.encode(touches, forKey: .touches)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        try c.encode(formatter.string(from: gameDate), forKey: .gameDate)
        try c.encode(metrics, forKey: .metrics)
    }
}

/// Aggregated stats over a trailing span of weeks (2 / 4 / 8), summed from the
/// player's game logs.
struct RecentFormWindow {
    let label: String
    /// Number of weeks requested for the window.
    let span: Int
    /// Actual number of games in the window.
    let games: Int
    let plays: Int
    let touches: Int
    /// Per-metric totals across the window. Box-score stats are counting
    /// stats (goals, shots, saves), so the window value is their sum.
    let metrics: [String: Double]

    /// Derived from `RecentWindow` so the per-player card, the team card and the
    /// league Trends board all offer the same choices under the same wording.
    static let windows: [(label: String, span: Int)] = RecentWindow.allCases.map {
        (label: $0.label, span: $0.rawValue)
    }

    /// What to call a window of `games` played in a `span`-week window.
    static func caption(games: Int, span: Int) -> String {
        games == 1 ? "1 game" : "\(games) games"
    }

    /// Build a window by summing each metric across the supplied game logs.
    static func build(label: String, span: Int, logs: [PlayerGameLog]) -> RecentFormWindow {
        let plays = logs.reduce(0) { $0 + $1.plays }
        let touches = logs.reduce(0) { $0 + $1.touches }

        var combined: [String: Double] = [:]
        let allKeys = Set(logs.flatMap { $0.metrics.keys })
        for key in allKeys {
            var total = 0.0
            var any = false
            for log in logs {
                if let value = log.metrics[key] ?? nil {
                    total += value
                    any = true
                }
            }
            if any { combined[key] = total }
        }

        return RecentFormWindow(
            label: label,
            span: span,
            games: logs.count,
            plays: plays,
            touches: touches,
            metrics: combined
        )
    }
}

extension RecentFormWindow {
    /// Logs from the trailing `weeks` before the newest one in the set, newest
    /// first. The league board anchors on the league's latest game; a card
    /// that holds one player's or one club's logs anchors on the latest game
    /// in them.
    static func logs(_ logs: [PlayerGameLog], weeks: Int) -> [PlayerGameLog] {
        guard let anchor = logs.map(\.gameDate).max() else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -(weeks * 7), to: anchor) ?? anchor
        return logs.filter { $0.gameDate > start }.sorted { $0.gameDate > $1.gameDate }
    }

    /// Ice time in the window, in hours.
    private var hours: Double? {
        let seconds = metrics["toi_seconds"] ?? 0
        return seconds > 0 ? seconds / 3_600 : nil
    }

    /// The window's value for a season metric, rebuilt from summed counts.
    /// Rates only: a four-week total would be read against a full-season
    /// ruler, so counting stats are not offered. Nil when the window has no
    /// denominator for it.
    func value(forSeasonLabel label: String) -> Double? {
        func total(_ key: String) -> Double? { metrics[key] }
        func per60(_ key: String) -> Double? {
            guard let hours, let sum = total(key) else { return nil }
            return sum / hours
        }
        switch label {
        case "P/60": return per60("points")
        case "ixG/60": return per60("ixg")
        case "Shots/60": return per60("shot_attempts")
        case "Sh%":
            guard let goals = total("goals"), let shots = total("shots_on_goal"), shots > 0 else { return nil }
            return goals / shots * 100
        case "SV%":
            guard let saves = total("saves"), let faced = total("shots_against"), faced > 0 else { return nil }
            return saves / faced
        case "GAA": return per60("goals_against")
        case "GSAx/60":
            guard let hours, let xga = total("xga"), let against = total("goals_against") else { return nil }
            return (xga - against) / hours
        case "HD SV%":
            guard let faced = total("hd_shots_against"), faced > 0,
                  let against = total("hd_goals_against") else { return nil }
            return 1 - against / faced
        default: return nil
        }
    }

    /// Season labels the Recent card draws bars for, in display order.
    static func recentLabels(goalie: Bool) -> [String] {
        goalie
            ? ["SV%", "GSAx/60", "GAA", "HD SV%"]
            : ["P/60", "ixG/60", "Shots/60", "Sh%"]
    }
}
