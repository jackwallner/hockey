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
    /// nflverse game id, e.g. "2026_01_BUF_HOU". The join key to `Game`.
    /// Optional because rows ingested before the column existed carry none.
    var gameId: String? = nil
    let gameDate: Date
    let playerType: String
    let team: String?
    let opponent: String?
    /// Offensive involvement: pass attempts + carries + targets.
    let plays: Int
    /// Ball touches: completions + carries + receptions.
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

/// Aggregated stats over the last N games. NFL cadence is weekly, so the window
/// is measured in games (last 1 / 3 / 5), not days.
struct RecentFormWindow {
    let label: String
    /// Number of games requested for the window.
    let span: Int
    /// Actual number of games in the window.
    let games: Int
    let plays: Int
    let touches: Int
    /// Per-metric totals across the window. NFL box-score stats are counting
    /// stats (yards, TDs, receptions), so the window value is their sum.
    let metrics: [String: Double]

    /// Derived from `RecentWindow` so the per-player card, the team card and the
    /// league Trends board all offer the same three choices under the same
    /// wording. They used to be declared here as 1 / 3 / 5 and in RecentWindow
    /// as 3 / 5 / 8, so the same word meant two different spans a tab apart.
    static let windows: [(label: String, span: Int)] = RecentWindow.allCases.map {
        (label: $0.label, span: $0.rawValue)
    }

    /// What to call a window of `games` when `span` games were asked for.
    ///
    /// The pickers offer 3 / 5 / 8, but a player one week into a season has
    /// one. Captioning that column "5 games" claims a span the numbers under it
    /// do not cover, so the caption follows the games in hand and only says
    /// five when there are five.
    static func caption(games: Int, span: Int) -> String {
        let count = min(games, span)
        guard count < span else { return "\(span) games" }
        return count == 1 ? "1 game" : "\(count) games"
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

        // Combined tackles has no column of its own in the weekly feed - the
        // game log stores solo and assists separately, the way nflverse
        // publishes them. Every consumer wants the total (that is what
        // "Tackles" means on the season line and on every board), so derive it
        // once here rather than leaving each caller to look up a `tackles` key
        // that has never existed and silently render nothing. That was the
        // shipped behaviour: a defender's Recent card had no Tackles bar at all.
        let solo = combined["def_tackles_solo"]
        let assists = combined["def_tackle_assists"]
        if solo != nil || assists != nil {
            combined["tackles"] = (solo ?? 0) + (assists ?? 0)
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
