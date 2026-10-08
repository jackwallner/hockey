import Foundation

/// A metric the Trends board can rank by.
///
/// Keyed to the game-log / rollup column rather than the season metric label,
/// because Trends reads `player_recent_form` directly and never touches the
/// season snapshot.
struct TrendMetric: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    /// Suffix appended to a value, e.g. "%" or " s". Empty for plain numbers.
    let unit: String
    /// Also drives the delta formatting on the row.
    let decimals: Int
    /// True where a falling number is the improvement: a goalie's GAA or
    /// goals against.
    let lowerIsBetter: Bool

    var id: String { key }

    func format(_ value: Double) -> String {
        if label.hasSuffix("SV%") { return RecentMetricKey.savePercentage(value) }
        if decimals == 0 {
            return Int(value.rounded()).formatted(.number.grouping(.automatic)) + unit
        }
        return String(format: "%.\(decimals)f", value) + unit
    }

    // MARK: - Advanced

    /// Forwards and defensemen read the same board. The rollup has no per-game
    /// on-ice shares (xGF%, CF% need a shift-level feed), so the advanced list
    /// is individual expected goals and the rates built on it.
    static let skaterAdvanced: [TrendMetric] = [
        .init(key: "points_per_60", label: "P/60", unit: "", decimals: 2, lowerIsBetter: false),
        .init(key: "ixg_per_60", label: "ixG/60", unit: "", decimals: 2, lowerIsBetter: false),
        .init(key: "gax", label: "GAx", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "shots_per_60", label: "Shots/60", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "hd_shots_per_60", label: "HD Shots/60", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "shooting_pct", label: "Sh%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "goals_per_60", label: "G/60", unit: "", decimals: 2, lowerIsBetter: false),
    ]

    static let goalieAdvanced: [TrendMetric] = [
        .init(key: "gsax", label: "GSAx", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "gsax_per_60", label: "GSAx/60", unit: "", decimals: 2, lowerIsBetter: false),
        .init(key: "hd_sv_pct", label: "HD SV%", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "shots_against_per_60", label: "SA/60", unit: "", decimals: 1, lowerIsBetter: false),
    ]

    // MARK: - Standard

    /// The counting line, summed across the window rather than averaged from
    /// per-game rates. It answers a different question from the advanced
    /// metrics: what actually happened, not how well it was done.
    static let skaterStandard: [TrendMetric] = [
        .init(key: "points", label: "P", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "goals", label: "G", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "assists", label: "A", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "shots_on_goal", label: "SOG", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "ixg", label: "ixG", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "hd_shots", label: "HD Shots", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "blocks", label: "Blocks", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "hits", label: "Hits", unit: "", decimals: 0, lowerIsBetter: false),
    ]

    static let goalieStandard: [TrendMetric] = [
        .init(key: "sv_pct", label: "SV%", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "gaa", label: "GAA", unit: "", decimals: 2, lowerIsBetter: true),
        .init(key: "saves", label: "Saves", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "goals_against", label: "GA", unit: "", decimals: 0, lowerIsBetter: true),
        .init(key: "wins", label: "W", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "shutouts", label: "SO", unit: "", decimals: 0, lowerIsBetter: false),
    ]

    static func advanced(for side: TrendSide) -> [TrendMetric] {
        switch side {
        case .forward, .defense: return skaterAdvanced
        case .goalie: return goalieAdvanced
        }
    }

    static func standard(for side: TrendSide) -> [TrendMetric] {
        switch side {
        case .forward, .defense: return skaterStandard
        case .goalie: return goalieStandard
        }
    }

    static func list(for side: TrendSide, mode: TrendStatMode) -> [TrendMetric] {
        let picked = mode == .advanced ? advanced(for: side) : standard(for: side)
        return picked.isEmpty ? standard(for: side) : picked
    }
}

/// Which vocabulary the Trends board is ranking in: the advanced line or the
/// traditional one. The same split the Stats tab, the player page and the team
/// page all use, so a user who has picked "Standard" once knows what it means
/// everywhere.
enum TrendStatMode: String, CaseIterable, Identifiable, Sendable {
    case advanced
    case standard

    var id: String { rawValue }
    var label: String { self == .advanced ? "Advanced" : "Standard" }
}

/// Which cohort the Trends board is ranking.
///
/// Mixing cohorts is not an option: a defenseman's point pace is not a
/// winger's, and a goalie shares no metric with either.
enum TrendSide: String, CaseIterable, Identifiable, Sendable {
    case forward = "f"
    case defense = "d"
    case goalie = "g"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forward: return "Forwards"
        case .defense: return "Defensemen"
        case .goalie: return "Goalies"
        }
    }

    /// Compact label for the equal-width cohort tabs.
    var shortLabel: String {
        switch self {
        case .forward: return "F"
        case .defense: return "D"
        case .goalie: return "G"
        }
    }

    /// Matches `player_recent_form.player_type`.
    var playerType: String { rawValue }

    var positionGroup: PlayerPositionGroup {
        switch self {
        case .forward: return .forward
        case .defense: return .defense
        case .goalie: return .goalie
        }
    }

    /// Whether this side has a meaningful advanced/standard split at all.
    var hasAdvancedMetrics: Bool { !TrendMetric.advanced(for: self).isEmpty }
}
