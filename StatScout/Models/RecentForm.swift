import Foundation

/// One player's league-anchored weekly window, as stored in
/// `public.player_recent_form`.
///
/// Mirrors the rolling-leaderboard shape the baseball app uses: the current
/// window, the equal-length window immediately before it, and the change
/// between them. The delta is the interesting column, a 3.1 P/60 means more
/// when you can see it was 1.4 over the two weeks before that.
///
/// Windows are shared league date ranges anchored on the latest game played,
/// so an injured player who has not appeared recently does not surface on a
/// current Trends board.
struct RecentForm: Codable, Hashable, Sendable, Identifiable {
    let playerId: Int
    let season: Int
    let seasonPhase: SeasonPhase
    let playerType: String
    let windowWeeks: Int
    /// Date of the last game in the window. Lets the UI say "through Feb 8"
    /// rather than implying the window runs to today.
    let asOf: Date?
    /// League week numbers of the first and last game in the window. Kept for
    /// the row shape; the label shown to users is the date range.
    let startWeek: Int?
    let endWeek: Int?
    let team: String?
    let games: Int
    /// Ice time in the window, whole minutes (the column keeps its NFL name).
    let plays: Int
    /// Shot attempts (skaters) or shots against (goalies) in the window.
    let touches: Int
    let metrics: [String: Double]
    let priorMetrics: [String: Double]
    let delta: [String: Double]

    var id: String {
        "\(playerId)-\(seasonPhase.rawValue)-\(playerType)-\(windowWeeks)"
    }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case seasonPhase = "season_type"
        case playerType = "player_type"
        case windowWeeks = "window_weeks"
        case legacyWindowGames = "window_games"
        case asOf = "as_of"
        case startWeek = "start_week"
        case endWeek = "end_week"
        case team
        case games
        case plays
        case touches
        case metrics
        case priorMetrics = "prior_metrics"
        case delta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        seasonPhase = try c.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        playerType = try c.decode(String.self, forKey: .playerType)
        windowWeeks = try c.decodeIfPresent(Int.self, forKey: .windowWeeks)
            ?? c.decode(Int.self, forKey: .legacyWindowGames)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        touches = try c.decodeIfPresent(Int.self, forKey: .touches) ?? 0
        startWeek = try c.decodeIfPresent(Int.self, forKey: .startWeek)
        endWeek = try c.decodeIfPresent(Int.self, forKey: .endWeek)

        // as_of is a Postgres `date`, so it arrives as "YYYY-MM-DD" and won't
        // parse with the ISO8601 strategy the rest of the payload uses.
        if let raw = try c.decodeIfPresent(String.self, forKey: .asOf) {
            var parts = DateComponents()
            let bits = raw.split(separator: "-").compactMap { Int($0) }
            if bits.count == 3 {
                parts.year = bits[0]; parts.month = bits[1]; parts.day = bits[2]
                asOf = Calendar.current.date(from: parts)
            } else {
                asOf = nil
            }
        } else {
            asOf = nil
        }

        // Null metric values mean "no data in this window" (see the rollup's
        // omit-rather-than-zero rule), so they're dropped rather than coerced.
        func numbers(_ key: CodingKeys) -> [String: Double] {
            guard let raw = try? c.decodeIfPresent([String: Double?].self, forKey: key) else { return [:] }
            return raw.compactMapValues { $0 }
        }
        metrics = numbers(.metrics)
        priorMetrics = numbers(.priorMetrics)
        delta = numbers(.delta)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(season, forKey: .season)
        try c.encode(seasonPhase, forKey: .seasonPhase)
        try c.encode(playerType, forKey: .playerType)
        try c.encode(windowWeeks, forKey: .windowWeeks)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encode(games, forKey: .games)
        try c.encode(plays, forKey: .plays)
        try c.encode(touches, forKey: .touches)
        try c.encodeIfPresent(startWeek, forKey: .startWeek)
        try c.encodeIfPresent(endWeek, forKey: .endWeek)
        try c.encode(metrics, forKey: .metrics)
        try c.encode(priorMetrics, forKey: .priorMetrics)
        try c.encode(delta, forKey: .delta)
    }

    /// Dates covered, e.g. "Sep 24 - Oct 7". Nil when the rollup carries no
    /// anchor date.
    var weekRangeLabel: String? {
        guard let asOf else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -(windowWeeks * 7 - 1), to: asOf) ?? asOf
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "\(start.formatted(style)) - \(asOf.formatted(style))"
    }

    /// Small samples make wild deltas. A skater needs an hour of ice time in
    /// the window (three or four games) before a rate is worth ranking; a
    /// goalie needs two starts' worth.
    var isSmallSample: Bool { isSmallSample(minimumGames: 2) }

    /// The same volume floor with a different game minimum. The early-season
    /// board ranks a single week, so it asks for one game rather than two.
    func isSmallSample(minimumGames: Int) -> Bool {
        if games < minimumGames { return true }
        switch playerType {
        case "g":  return plays < 100
        default:   return plays < 60
        }
    }
}

/// Season metric label to the rolling rollup's column for it, plus the one
/// formatter for a window value.
///
/// The leaderboard, the team roster and the team cards all need to ask "what is
/// this player's Y/A over the last five games"; each had grown its own private
/// copy of the mapping, which is how a metric ends up trending on one screen
/// and blank on the next.
///
/// Returns nil for the season metrics the rollup has no column for. Those come
/// from Next Gen Stats aggregates with no per-game denominator (Aggressiveness,
/// Intended Air Yds, Target Share, WOPR) or from play-by-play the weekly feed
/// doesn't carry (Explosive%). A metric with no rollup key simply gets no
/// recent bar, which is the same rule baseball uses for the metrics Savant
/// publishes no season percentile for.
enum RecentMetricKey {
    static func key(for label: String) -> String? {
        switch label {
        // Scoring.
        case "G": return "goals"
        case "A": return "assists"
        case "P": return "points"
        case "P/60": return "points_per_60"
        case "Primary P": return "primary_points"
        case "SOG": return "shots_on_goal"
        case "Sh%": return "shooting_pct"
        // Shot Quality.
        case "ixG": return "ixg"
        case "GAx": return "gax"
        case "ixG/60": return "ixg_per_60"
        case "Shots/60": return "shots_per_60"
        case "Shot Att": return "shot_attempts"
        case "HD Shots": return "hd_shots"
        // Play Driving (counting stats only; on-ice shares have no per-game feed).
        case "Blocks": return "blocks"
        case "Hits": return "hits"
        case "Takeaways": return "takeaways"
        case "Giveaways": return "giveaways"
        // Goaltending.
        case "GSAx": return "gsax"
        case "GSAx/60": return "gsax_per_60"
        case "SV%": return "sv_pct"
        case "GAA": return "gaa"
        case "HD SV%": return "hd_sv_pct"
        case "xGA/60": return "xga_per_60"
        case "Saves": return "saves"
        case "GA": return "goals_against"
        case "W": return "wins"
        case "SO": return "shutouts"
        default: return nil
        }
    }

    /// True where a falling number is the improvement.
    static func lowerIsBetter(_ label: String) -> Bool {
        ["GAA", "GA", "Giveaways", "Rebound%"].contains(label)
    }

    /// How many decimals the metric's delta moves in. Counting stats are
    /// whole, expected-goal totals are tenths, per-60 rates hundredths and
    /// save percentages thousandths.
    static func decimals(for label: String) -> Int {
        switch label {
        case "SV%", "HD SV%", "xG/Shot": return 3
        case "P/60", "ixG/60", "GSAx/60", "xGA/60", "xGF/60", "GAA", "Game Score": return 2
        case "ixG", "GAx", "GSAx", "Rel xGF%", "Rel CF%", "Shots/60": return 1
        default:
            return label.hasSuffix("%") ? 1 : 0
        }
    }

    /// Matches the player page's conventions: a save percentage reads ".915",
    /// a share reads "54.2%", a rate carries its decimals and a count none.
    static func format(_ value: Double, label: String) -> String {
        if label.hasSuffix("SV%") {
            return savePercentage(value)
        }
        let places = decimals(for: label)
        if label.hasSuffix("%") { return String(format: "%.1f%%", value) }
        if places == 0 {
            let whole = Int(value.rounded())
            return whole.formatted(.number.grouping(.automatic))
        }
        return String(format: "%.\(places)f", value)
    }

    /// 0.915 or 91.5 -> ".915". The rollup stores save percentage as a fraction.
    static func savePercentage(_ value: Double) -> String {
        let fraction = value > 1.5 ? value / 100 : value
        let text = String(format: "%.3f", fraction)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }
}

/// Per-player and per-team windows. The same league-anchored week ranges the
/// Trends board uses, so a card and the board never disagree about "recent".
enum RecentWindow: Int, CaseIterable, Identifiable, Sendable {
    case two = 2
    case four = 4
    case eight = 8

    var id: Int { rawValue }
    var label: String { "Last \(rawValue) weeks" }
    var segmentLabel: String { "\(rawValue) wks" }
    var shortLabel: String { "\(rawValue)W" }
}

/// League-anchored windows used only by Trends.
enum TrendWindow: Int, CaseIterable, Identifiable, Sendable {
    case two = 2
    case four = 4
    case eight = 8

    var id: Int { rawValue }
    var label: String { "Last \(rawValue) weeks" }
    var segmentLabel: String { "\(rawValue) weeks" }
}
