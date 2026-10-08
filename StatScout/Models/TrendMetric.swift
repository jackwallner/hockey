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
    /// True where a falling number is the improvement: a quarterback's INT% or
    /// sack rate, a back's fumble rate.
    let lowerIsBetter: Bool

    var id: String { key }

    func format(_ value: Double) -> String {
        if decimals == 0 {
            return Int(value.rounded()).formatted(.number.grouping(.automatic)) + unit
        }
        return String(format: "%.\(decimals)f", value) + unit
    }

    // MARK: - Advanced

    static let qbAdvanced: [TrendMetric] = [
        .init(key: "passing_epa", label: "EPA/Play", unit: "", decimals: 2, lowerIsBetter: false),
        .init(key: "cpoe", label: "CPOE", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "ypa", label: "Y/A", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "cmp_pct", label: "Cmp%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "passer_rating", label: "Rating", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "int_rate", label: "INT%", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "sack_rate", label: "Sack%", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "avg_time_to_throw", label: "Time to Throw", unit: " s", decimals: 2, lowerIsBetter: false),
    ]

    static let rbAdvanced: [TrendMetric] = [
        .init(key: "ypc", label: "Y/C", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "rush_yoe", label: "RYOE", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "rushing_epa", label: "Rush EPA", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "catch_pct", label: "Catch%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "fumble_rate", label: "Fumble%", unit: "%", decimals: 1, lowerIsBetter: true),
    ]

    /// Receivers and tight ends read the same board. Separating them would
    /// halve two already-small pools without changing what any metric means.
    static let receivingAdvanced: [TrendMetric] = [
        .init(key: "receiving_epa", label: "Rec EPA", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "catch_pct", label: "Catch%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "avg_separation", label: "Separation", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "avg_yac_above_expectation", label: "YAC+", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "racr", label: "RACR", unit: "", decimals: 2, lowerIsBetter: false),
    ]

    // MARK: - Standard

    /// The counting line, summed across the window rather than averaged from
    /// per-game rates. It answers a different question from the advanced
    /// metrics: what actually happened, not how well it was done.
    static let qbStandard: [TrendMetric] = [
        .init(key: "pass_yards", label: "Pass Yds", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "pass_tds", label: "Pass TD", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "completions", label: "Cmp", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "attempts", label: "Att", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "interceptions", label: "INT", unit: "", decimals: 0, lowerIsBetter: true),
        .init(key: "rush_yards", label: "Rush Yds", unit: "", decimals: 0, lowerIsBetter: false),
    ]

    static let rbStandard: [TrendMetric] = [
        .init(key: "rush_yards", label: "Rush Yds", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "rush_tds", label: "Rush TD", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "carries", label: "Car", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "rush_first_downs", label: "Rush 1D", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "receptions", label: "Rec", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "rec_yards", label: "Rec Yds", unit: "", decimals: 0, lowerIsBetter: false),
    ]

    static let receivingStandard: [TrendMetric] = [
        .init(key: "rec_yards", label: "Rec Yds", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "receptions", label: "Rec", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "rec_tds", label: "Rec TD", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "targets", label: "Tgt", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "yac", label: "YAC", unit: "", decimals: 0, lowerIsBetter: false),
    ]

    /// Defence has no advanced list: the weekly feed carries no snap counts or
    /// coverage charting, so every defensive metric the rollup can build is a
    /// count. Rather than invent a thin "advanced" tab out of the same numbers,
    /// the board drops the Advanced / Standard control entirely for this side.
    static let defStandard: [TrendMetric] = [
        .init(key: "tackles", label: "Tackles", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "sacks", label: "Sacks", unit: "", decimals: 1, lowerIsBetter: false),
        .init(key: "def_ints", label: "INT", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "passes_defended", label: "PD", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "tfl", label: "TFL", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "qb_hits", label: "QB Hits", unit: "", decimals: 0, lowerIsBetter: false),
        .init(key: "forced_fumbles", label: "FF", unit: "", decimals: 0, lowerIsBetter: false),
    ]

    static func advanced(for side: TrendSide) -> [TrendMetric] {
        switch side {
        case .qb:  return qbAdvanced
        case .rb:  return rbAdvanced
        case .wr, .te: return receivingAdvanced
        case .def: return []
        }
    }

    static func standard(for side: TrendSide) -> [TrendMetric] {
        switch side {
        case .qb:  return qbStandard
        case .rb:  return rbStandard
        case .wr, .te: return receivingStandard
        case .def: return defStandard
        }
    }

    static func list(for side: TrendSide, mode: TrendStatMode) -> [TrendMetric] {
        let picked = mode == .advanced ? advanced(for: side) : standard(for: side)
        // Defence has no advanced list; fall through rather than showing an
        // empty picker.
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

/// Which position group the Trends board is ranking.
///
/// Mixing groups is not an option: Y/A means nothing to a safety, and a
/// receiver's Catch% is not a quarterback's.
enum TrendSide: String, CaseIterable, Identifiable, Sendable {
    case qb
    case rb
    case wr
    case te
    case def

    var id: String { rawValue }

    var label: String {
        switch self {
        case .qb:  return "Quarterbacks"
        case .rb:  return "Running Backs"
        case .wr:  return "Receivers"
        case .te:  return "Tight Ends"
        case .def: return "Defense"
        }
    }

    /// Compact label for the five equal-width position tabs.
    var shortLabel: String {
        switch self {
        case .qb:  return "QB"
        case .rb:  return "RB"
        case .wr:  return "WR"
        case .te:  return "TE"
        case .def: return "DEF"
        }
    }

    /// Matches `player_recent_form.player_type`.
    var playerType: String { rawValue }

    /// Whether this side has a meaningful advanced/standard split at all.
    var hasAdvancedMetrics: Bool { !TrendMetric.advanced(for: self).isEmpty }
}
