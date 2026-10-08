import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(playerId)-\(season ?? 0)-\(seasonPhase.rawValue)" }
    let playerId: Int
    let name: String
    let team: String
    let position: String
    let handedness: String
    let updatedAt: Date
    let season: Int?
    let seasonPhase: SeasonPhase
    let playerType: String?
    let source: String?
    let metrics: [Metric]
    let standardStats: [StandardStat]?
    let games: [GameTrend]

    enum CodingKeys: String, CodingKey {
        case playerId = "id"
        case name
        case team
        case position
        case handedness
        case updatedAt = "updated_at"
        case season
        case seasonPhase = "season_type"
        case playerType = "player_type"
        case source
        case metrics
        case standardStats = "standard_stats"
        case games
    }

    init(
        playerId: Int,
        name: String,
        team: String,
        position: String,
        handedness: String,
        updatedAt: Date,
        season: Int? = nil,
        seasonPhase: SeasonPhase = .regular,
        playerType: String? = nil,
        source: String? = nil,
        metrics: [Metric],
        standardStats: [StandardStat]?,
        games: [GameTrend]
    ) {
        self.playerId = playerId
        self.name = name
        self.team = team
        self.position = position
        self.handedness = handedness
        self.updatedAt = updatedAt
        self.season = season
        self.seasonPhase = seasonPhase
        self.playerType = playerType
        self.source = source
        self.metrics = metrics
        self.standardStats = standardStats
        self.games = games
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(Int.self, forKey: .playerId)
        name = try container.decode(String.self, forKey: .name)
        team = try container.decode(String.self, forKey: .team)
        position = try container.decode(String.self, forKey: .position)
        handedness = try container.decode(String.self, forKey: .handedness)
        // No headshot field: the app never renders player photos (same as the
        // baseball build), and the league's headshot URLs aren't ours to
        // redistribute. It was also a live decoding hazard - it used to be
        // decoded as `URL`, which only round-trips from a plain string on
        // JSONDecoder. PropertyListDecoder expects URL's keyed
        // {relative, base} form, so it threw typeMismatch on the first row and
        // took the whole `[Player]` array down with it, leaving the bundled
        // current *and* historical datasets unreadable ("Data Error - No
        // players found"). The feed still sends `image_url`; unknown keys are
        // simply ignored.
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        season = try container.decodeIfPresent(Int.self, forKey: .season)
        seasonPhase = try container.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        playerType = try container.decodeIfPresent(String.self, forKey: .playerType)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        metrics = try container.decode([Metric].self, forKey: .metrics)
        standardStats = try container.decodeIfPresent([StandardStat].self, forKey: .standardStats)
        games = try container.decodeIfPresent([GameTrend].self, forKey: .games) ?? []
    }

    /// Explicit mirror of `init(from:)` so the on-disk plist cache is written
    /// in exactly the shape the decoder above reads back. Leaving this
    /// synthesized is what let the encode and decode sides drift apart in the
    /// first place.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playerId, forKey: .playerId)
        try container.encode(name, forKey: .name)
        try container.encode(team, forKey: .team)
        try container.encode(position, forKey: .position)
        try container.encode(handedness, forKey: .handedness)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(season, forKey: .season)
        try container.encode(seasonPhase, forKey: .seasonPhase)
        try container.encodeIfPresent(playerType, forKey: .playerType)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encode(metrics, forKey: .metrics)
        try container.encodeIfPresent(standardStats, forKey: .standardStats)
        try container.encode(games, forKey: .games)
    }

    /// Metrics that carry a real rank. See `Metric.isUnranked`.
    var rankedMetrics: [Metric] { metrics.filter { !$0.isUnranked } }

    var overallPercentile: Int {
        let metrics = rankedMetrics
        guard !metrics.isEmpty else { return 0 }
        // Players who span more than one category (e.g. a rushing QB with both
        // Passing and Rushing metrics) shouldn't have their headline number
        // diluted by averaging across unrelated skills - take the best category.
        let categories = Set(metrics.map(\.category))
        if categories.count > 1 {
            let categoryAverages = Dictionary(grouping: metrics) { $0.category }
                .values
                .map { group in
                    Double(group.map(\.percentile).reduce(0, +)) / Double(group.count)
                }
            return Int(round(categoryAverages.max() ?? 0))
        }
        let total = metrics.map(\.percentile).reduce(0, +)
        return Int(round(Double(total) / Double(metrics.count)))
    }

    var headlineMetric: Metric? {
        rankedMetrics.sorted { $0.percentile > $1.percentile }.first
    }

    var latestGame: GameTrend? {
        games.sorted { $0.date > $1.date }.first
    }

    var latestPercentileDelta: Int {
        latestGame?.percentileDelta ?? 0
    }

    var weeklyDelta: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return games.filter { $0.date >= cutoff }
            .map(\.percentileDelta)
            .reduce(0, +)
    }

    var shareSummary: String {
        let headline = headlineMetric.map { metric in
            let valueText = metric.value.isEmpty ? "\(metric.percentile.ordinal) percentile" : "\(metric.value), \(metric.percentile.ordinal) percentile"
            return "\(metric.label) \(valueText)"
        } ?? "\(overallPercentile.ordinal) overall percentile"
        return "\(name) · \(team) \(displayPosition)\nOverall: \(overallPercentile.ordinal) percentile\nTop stat: \(headline)\nGridiron StatScout"
    }

    func percentile(for category: MetricCategory) -> Int? {
        let categoryMetrics = rankedMetrics.filter { $0.category == category }
        guard !categoryMetrics.isEmpty else { return nil }
        let total = categoryMetrics.map(\.percentile).reduce(0, +)
        return Int(round(Double(total) / Double(categoryMetrics.count)))
    }
}

enum SeasonPhase: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case regular = "REG"
    case playoffs = "POST"

    var id: String { rawValue }

    /// One name, everywhere.
    ///
    /// There used to be a short `label` ("Regular") for controls and a
    /// `fullLabel` ("Regular Season") for prose, and the short one was wrong in
    /// every place it appeared: on its own, "Regular" is an adjective with no
    /// noun, and the nav pill read "2025 · Regular" as though it were describing
    /// the year. The saving was about forty points of width on one capsule,
    /// which the bar has.
    var label: String {
        switch self {
        case .regular: return "Regular Season"
        case .playoffs: return "Playoffs"
        }
    }
}

struct Metric: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    let percentile: Int
    let category: MetricCategory
    /// Whether the player clears the (prorated) qualification bar for this
    /// metric. Only the live season ships it, because only the live season ships
    /// players under the bar; nil means the row exists because it qualified.
    var qualified: Bool? = nil
    /// Set false by screens that build a metric from a counting stat outside
    /// the registry (the profile's standard line), so a zero there is unranked
    /// by the same rule as below.
    var rankable: Bool? = nil

    /// A traditional counting stat at zero: 0 INT, 0 sacks, 0 rushing TD.
    ///
    /// The feed ranks these with the midpoint of the tie, so at Week 3 the 674
    /// defenders without an interception were all painted 47th percentile. A
    /// player who has done none of a thing is not a 47th-percentile player at
    /// it, and when most of the league is tied at zero there is no honest rank
    /// at all. The value still shows; the bar, the number and the player's
    /// overall average leave it out.
    var isUnranked: Bool {
        if rankable == false { return true }
        guard let definition = FootballMetricRegistry.definition(for: label, category: category),
              definition.kind == .traditional,
              FootballMetricRegistry.aggregation(for: label, category: category) == .sum,
              let number = metricNumericValue(value)
        else { return false }
        return number == 0
    }

    /// Below the prorated playing-time bar for this metric.
    var isSmallSample: Bool { qualified == false }
}

struct StandardStat: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
}

/// Shared meaning for the compact values in `standard_stats`.
///
/// The feed stores completions/attempts and receptions/targets as display-ready
/// pairs. Treating the leading component as the numeric value made `8/11` rank
/// as eight instead of a 72.7% catch rate in both profile and comparison UI.
enum StandardStatSemantics {
    enum Winner: Equatable {
        case left
        case right
    }

    static func numericValue(label: String, value: String) -> Double? {
        switch label.uppercased() {
        case "CMP/ATT", "REC/TGT":
            let parts = value.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let numerator = metricNumericValue(String(parts[0])),
                  let denominator = metricNumericValue(String(parts[1])),
                  denominator > 0 else { return nil }
            return numerator / denominator * 100
        default:
            return metricNumericValue(value)
        }
    }

    static func higherIsBetter(label: String) -> Bool {
        label.uppercased() != "INT"
    }

    /// Midpoint rank against every peer carrying the same stat. A single
    /// available value is the middle of its one-player cohort, never an absent
    /// percentile. The caller supplies one season and position group.
    static func percentile(label: String, value: String, peerValues: [String]) -> Int {
        guard let currentValue = numericValue(label: label, value: value) else {
            return 50
        }
        var values = peerValues.compactMap {
            numericValue(label: label, value: $0)
        }
        if values.isEmpty { values = [currentValue] }

        let below = values.reduce(0) { $0 + ($1 < currentValue ? 1 : 0) }
        let equal = values.reduce(0) { $0 + ($1 == currentValue ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        let oriented = higherIsBetter(label: label) ? raw : 100 - raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    static func winner(label: String, left: String?, right: String?) -> Winner? {
        guard let left,
              let right,
              let leftValue = numericValue(label: label, value: left),
              let rightValue = numericValue(label: label, value: right),
              leftValue != rightValue else { return nil }
        let leftWins = higherIsBetter(label: label)
            ? leftValue > rightValue
            : leftValue < rightValue
        return leftWins ? .left : .right
    }
}

/// Pulls the leading number out of a formatted feed value: `"6.2%"` -> 6.2,
/// `"3,322"` -> 3322, `"+2.3"` -> 2.3.
///
/// Lives here, free of any actor, because it is pure string arithmetic that both
/// the view model (main actor) and the model layer need. It used to exist only as
/// `DashboardViewModel.rawNumeric`, which inherited the view model's
/// `@MainActor` isolation and so couldn't be called from a plain model type at
/// all. That method now forwards here, so there is still one implementation.
func metricNumericValue(_ value: String) -> Double? {
    var s = value.trimmingCharacters(in: .whitespaces)
    // Strip thousands separators - NFL yardage ships as "3,322".
    s = s.replacingOccurrences(of: ",", with: "")
    if s.hasPrefix(".") { s = "0" + s }
    if s.hasPrefix("-.") { s = "-0" + s.dropFirst() }
    let scanner = Scanner(string: s)
    scanner.charactersToBeSkipped = nil
    return scanner.scanDouble()
}

/// The display shape of a metric value, read back off the feed's own strings.
///
/// The pipeline formats every metric server-side (`"6.2%"`, `"+2.3"`, `"3,322"`,
/// `"0.05"`) and the app only ever passes those through. An aggregate has no
/// such string to pass through, so it has to be rendered here - and rather than
/// keep a second copy of the backend's format table in Swift, where the two
/// would quietly drift the first time a metric changed precision, the format is
/// inferred from the very values being aggregated. A column of `"6.2%"` renders
/// its total as `"6.2%"` by construction.
struct MetricValueFormat: Hashable, Sendable {
    var decimals = 0
    var isPercent = false
    var isSigned = false
    var hasGrouping = false

    static func inferred(from samples: [String]) -> MetricValueFormat {
        var format = MetricValueFormat()
        for sample in samples {
            let trimmed = sample.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("%") { format.isPercent = true }
            if trimmed.hasPrefix("+") { format.isSigned = true }
            if trimmed.contains(",") { format.hasGrouping = true }
            // Max rather than first: a column holding both "0.1" and "0.12"
            // should render its aggregate at the finer precision, not truncate.
            let digits = trimmed
                .drop { $0 != "." }
                .dropFirst()
                .prefix { $0.isNumber }
                .count
            format.decimals = max(format.decimals, digits)
        }
        return format
    }

    func string(_ value: Double) -> String {
        var text: String
        if decimals == 0, hasGrouping {
            text = Int(value.rounded()).formatted(.number.grouping(.automatic))
        } else if decimals == 0 {
            text = String(Int(value.rounded()))
        } else {
            text = String(format: "%.\(decimals)f", value)
        }
        if isSigned, value > 0 { text = "+" + text }
        if isPercent { text += "%" }
        return text
    }
}

enum MetricDirection: String, Codable, Hashable, Sendable {
    case up
    case flat
    case down
}

enum MetricCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case passing = "Passing"
    case rushing = "Rushing"
    case receiving = "Receiving"
    case defense = "Defense"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let category = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
        }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown metric category: \(value)"
            )
        }
        self = category
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Registry-driven display order. Advanced metrics lead within each category,
    /// followed by traditional production metrics.
    var metricPriorityOrder: [String] {
        FootballMetricRegistry.definitions
            .filter { $0.category == self }
            .sorted { $0.priority < $1.priority }
            .map(\.label)
    }

    /// Returns a comparator for sorting metric labels within this category.
    func sortMetrics(_ a: String, _ b: String) -> Bool {
        let order = metricPriorityOrder
        let ia = order.firstIndex(of: a) ?? order.count
        let ib = order.firstIndex(of: b) ?? order.count
        return ia < ib
    }
}

struct TeamRoute: Hashable {
    let abbr: String
    let players: [Player]
}

extension Player {
    /// Known NFL position groups the snapshot feed assigns.
    private static let knownTypes: Set<String> = ["qb", "rb", "wr", "te", "def"]

    func matchesPlayerType(for category: MetricCategory?) -> Bool {
        guard let category else { return true }
        // Only filter on a recognized position group. An unknown / missing
        // player_type falls through to "include" so we never drop a player who
        // lost their role label upstream but still carries real metrics.
        guard let type = playerType?.lowercased(), Self.knownTypes.contains(type) else { return true }
        switch category {
        case .passing:
            return type == "qb"
        case .rushing:
            return ["qb", "rb", "wr", "te"].contains(type)
        case .receiving:
            return ["rb", "wr", "te"].contains(type)
        case .defense:
            return type == "def"
        }
    }

    /// The category a player leads with - drives Recent Form and single-category
    /// framing. Derived from the position group, falling back to the most common
    /// metric category when the role label is missing.
    var primaryCategory: MetricCategory {
        switch playerType?.lowercased() {
        case "qb": return .passing
        case "rb": return .rushing
        case "wr", "te": return .receiving
        case "def": return .defense
        default:
            let counts = Dictionary(grouping: metrics, by: \.category).mapValues(\.count)
            return counts.max { $0.value < $1.value }?.key ?? .passing
        }
    }

    /// Position to surface in the UI. When the snapshot has no position (TBD /
    /// empty) but the player has metrics, fall back to the player-type label so
    /// we never show "TBD" next to real stats.
    var displayPosition: String {
        let trimmed = position.trimmingCharacters(in: .whitespaces).uppercased()
        if !trimmed.isEmpty && trimmed != "TBD" && trimmed != "\u{2014}" && trimmed != "-" {
            return position
        }
        return playerType?.uppercased() ?? position
    }

    var initials: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return "" }
        guard parts.count > 1 else { return String(first.prefix(1)) }

        let last = parts.last!
        let suffix = last.trimmingCharacters(in: .punctuationCharacters).uppercased()
        let hasSuffix = ["JR", "SR", "II", "III", "IV", "V"].contains(suffix)

        if hasSuffix && parts.count > 2 {
            // Use part before suffix as last name (e.g., "Bobby Witt Jr." → "BW")
            let lastName = parts[parts.count - 2]
            return String(first.prefix(1)) + String(lastName.prefix(1))
        }

        // Standard case: first initial + last initial
        return String(first.prefix(1)) + String(last.prefix(1))
    }
}

struct GameTrend: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let date: Date
    let opponent: String
    let summary: String
    let percentileDelta: Int
    let keyMetric: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case opponent
        case summary
        case percentileDelta = "percentile_delta"
        case keyMetric = "key_metric"
    }
}


enum PlayerPositionGroup: String, CaseIterable, Identifiable, Hashable, Sendable {
    case qb = "QB"
    case rb = "RB"
    case wr = "WR"
    case te = "TE"
    case defense = "DEF"

    var id: String { rawValue }

    var cohortDescription: String {
        switch self {
        case .defense: return "Among defensive players"
        default: return "Among \(rawValue)s"
        }
    }

    var primaryCategory: MetricCategory {
        switch self {
        case .qb: return .passing
        case .rb: return .rushing
        case .wr, .te: return .receiving
        case .defense: return .defense
        }
    }

    var preferredAdvancedMetrics: [String] {
        switch self {
        case .qb: return ["EPA/Play", "CPOE", "Rating"]
        case .rb: return ["EPA/Rush", "RYOE", "Explosive%", "Rush EPA"]
        case .wr, .te: return ["EPA/Tgt", "WOPR", "YAC+", "Rec EPA"]
        // Pressures leads because it is the one advanced defensive number that
        // exists for every defender rather than only for those targeted enough
        // to be ranked in coverage.
        case .defense: return ["Pressures", "Rating Allowed", "Cmp% Allowed", "Missed Tkl%"]
        }
    }

    var preferredTraditionalMetrics: [String] {
        switch self {
        case .qb: return ["Pass Yds", "Pass TD", "Cmp%"]
        case .rb: return ["Rush Yds", "Rush TD", "Car"]
        case .wr, .te: return ["Rec Yds", "Rec TD", "Rec"]
        case .defense: return ["Tackles", "Sacks", "Def INT"]
        }
    }
}

enum MetricKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case advanced = "Advanced"
    case traditional = "Traditional"

    var id: String { rawValue }
}

enum MetricFamily: String, CaseIterable, Identifiable, Hashable, Sendable {
    case efficiency = "Efficiency"
    case accuracy = "Accuracy"
    case pressure = "Pressure"
    case aggressiveness = "Aggressiveness"
    case rushing = "Rushing"
    case expectedProduction = "Expected"
    case explosiveness = "Explosiveness"
    case usage = "Usage"
    case receiving = "Receiving"
    case separation = "Separation"
    case yac = "YAC"
    case production = "Production"
    case passRush = "Pass Rush"
    case turnovers = "Turnovers"
    case coverage = "Coverage"
    case tackling = "Tackling"

    var id: String { rawValue }
}

struct MetricDefinition: Hashable, Sendable {
    let label: String
    let category: MetricCategory
    let kind: MetricKind
    let family: MetricFamily
    let positions: Set<PlayerPositionGroup>
    let higherIsBetter: Bool
    let priority: Int
    let description: String
}

enum FootballMetricRegistry {
    static let definitions: [MetricDefinition] = [
        definition("EPA/Play", .passing, .advanced, .efficiency, [.qb], 10, "Passing expected points added divided by attempts plus sacks. EPA measures the change in expected points from before to after a play."),
        definition("CPOE", .passing, .advanced, .accuracy, [.qb], 20, "Completion percentage minus the completion rate expected from throw difficulty, in percentage points."),
        definition("INT%", .passing, .advanced, .accuracy, [.qb], 30, "Passing interceptions divided by attempts.", higherIsBetter: false),
        definition("Sack%", .passing, .advanced, .pressure, [.qb], 40, "Sacks taken divided by attempts plus sacks.", higherIsBetter: false),
        definition("Time to Throw", .passing, .advanced, .pressure, [.qb], 50, "Average seconds from the snap until the passer releases the ball."),
        definition("Aggressiveness", .passing, .advanced, .aggressiveness, [.qb], 60, "Percentage of attempts thrown into tight coverage, with a defender within one yard of the receiver."),
        definition("Intended Air Yds", .passing, .advanced, .aggressiveness, [.qb], 70, "Average vertical distance the ball travels from the line of scrimmage to the intended target."),
        definition("Pass Yds", .passing, .traditional, .production, [.qb], 110, "Total passing yards."),
        definition("Pass TD", .passing, .traditional, .production, [.qb], 120, "Total passing touchdowns."),
        definition("Cmp%", .passing, .traditional, .accuracy, [.qb], 130, "Completions divided by passing attempts."),
        definition("Y/A", .passing, .traditional, .efficiency, [.qb], 140, "Passing yards per attempt."),
        definition("Rating", .passing, .traditional, .efficiency, [.qb], 150, "NFL passer rating calculated from completion rate, yards per attempt, touchdown rate, and interception rate. Maximum 158.3."),

        definition("EPA/Rush", .rushing, .advanced, .efficiency, [.qb, .rb, .wr, .te], 10, "Expected points added per rushing attempt."),
        definition("RYOE", .rushing, .advanced, .expectedProduction, [.qb, .rb], 20, "Total rushing yards gained above or below the yards expected by the Next Gen Stats model."),
        definition("Explosive%", .rushing, .advanced, .explosiveness, [.qb, .rb, .wr, .te], 30, "Percentage of carries gaining at least 10 yards."),
        definition("Rush EPA", .rushing, .advanced, .production, [.qb, .rb, .wr, .te], 40, "Total expected points added on rushing plays."),
        definition("Fumble%", .rushing, .advanced, .efficiency, [.qb, .rb, .wr, .te], 50, "Rushing fumbles divided by carries.", higherIsBetter: false),
        definition("Rush Yds", .rushing, .traditional, .production, [.qb, .rb, .wr, .te], 110, "Total rushing yards."),
        definition("Rush TD", .rushing, .traditional, .production, [.qb, .rb, .wr, .te], 120, "Total rushing touchdowns."),
        definition("Y/C", .rushing, .traditional, .efficiency, [.qb, .rb, .wr, .te], 130, "Rushing yards per carry."),
        definition("Rush 1D", .rushing, .traditional, .production, [.qb, .rb, .wr, .te], 140, "Rushing first downs."),

        definition("EPA/Tgt", .receiving, .advanced, .efficiency, [.rb, .wr, .te], 10, "Expected points added per target."),
        definition("WOPR", .receiving, .advanced, .usage, [.rb, .wr, .te], 20, "Weighted opportunity rating: 1.5 × target share plus 0.7 × air-yards share."),
        definition("Target Share", .receiving, .advanced, .usage, [.rb, .wr, .te], 30, "Player targets as a share of the team's pass attempts."),
        definition("RACR", .receiving, .advanced, .efficiency, [.rb, .wr, .te], 40, "Receiving yards divided by receiving air yards."),
        definition("Separation", .receiving, .advanced, .separation, [.rb, .wr, .te], 50, "Average yards between the targeted receiver and the nearest defender at pass arrival."),
        definition("YAC+", .receiving, .advanced, .yac, [.rb, .wr, .te], 60, "Average yards after catch gained above or below the Next Gen Stats expectation."),
        definition("Rec EPA", .receiving, .advanced, .production, [.rb, .wr, .te], 70, "Total expected points added on receiving plays."),
        definition("Rec", .receiving, .traditional, .production, [.rb, .wr, .te], 110, "Total receptions."),
        definition("Rec Yds", .receiving, .traditional, .production, [.rb, .wr, .te], 120, "Total receiving yards."),
        definition("Rec TD", .receiving, .traditional, .production, [.rb, .wr, .te], 130, "Total receiving touchdowns."),
        definition("YAC", .receiving, .traditional, .yac, [.rb, .wr, .te], 140, "Yards after catch."),
        definition("Catch%", .receiving, .traditional, .efficiency, [.rb, .wr, .te], 150, "Receptions divided by targets."),

        // Advanced defence, from Pro-Football-Reference's advanced defensive
        // table (2018 onward - the first season it was published). Defenders
        // were previously the one position group with nothing but counting
        // stats, which made the whole advanced half of the app silent on half
        // the field. Coverage metrics describe what a defender *allowed* when
        // targeted, so on all four of them a lower number is the better one.
        definition("Pressures", .defense, .advanced, .passRush, [.defense], 10, "Quarterback pressures: sacks, hits and hurries credited to this defender. Pro-Football-Reference, 2018 onward."),
        definition("Hurries", .defense, .advanced, .passRush, [.defense], 20, "Times the defender forced the quarterback to move off his spot or throw early without hitting him. 2018 onward."),
        definition("QB KD", .defense, .advanced, .passRush, [.defense], 30, "Quarterback knockdowns: times the defender put the passer on the ground, sack or not. 2018 onward."),
        definition("Cmp% Allowed", .defense, .advanced, .coverage, [.defense], 40, "Completion percentage on passes thrown at this defender. Needs at least 20 targets to be ranked. 2018 onward.", higherIsBetter: false),
        definition("Yds/Tgt Allowed", .defense, .advanced, .coverage, [.defense], 50, "Yards allowed per pass thrown at this defender. Needs at least 20 targets to be ranked. 2018 onward.", higherIsBetter: false),
        definition("Rating Allowed", .defense, .advanced, .coverage, [.defense], 60, "Passer rating on throws into this defender's coverage. Needs at least 20 targets to be ranked. 2018 onward.", higherIsBetter: false),
        definition("Missed Tkl%", .defense, .advanced, .tackling, [.defense], 70, "Share of this defender's tackle attempts that he missed. Needs at least 20 combined tackles to be ranked. 2018 onward.", higherIsBetter: false),

        definition("Tackles", .defense, .traditional, .production, [.defense], 110, "Total tackles."),
        definition("TFL", .defense, .traditional, .production, [.defense], 120, "Tackles for loss."),
        definition("PD", .defense, .traditional, .production, [.defense], 130, "Passes defended."),
        definition("Sacks", .defense, .traditional, .passRush, [.defense], 140, "Total sacks."),
        definition("QB Hits", .defense, .traditional, .passRush, [.defense], 150, "Quarterback hits."),
        definition("INT", .defense, .traditional, .turnovers, [.defense], 160, "Defensive interceptions."),
        definition("FF", .defense, .traditional, .turnovers, [.defense], 170, "Forced fumbles.")
    ]

    static func definition(for label: String, category: MetricCategory) -> MetricDefinition? {
        definitions.first { $0.label == label && $0.category == category }
    }

    /// How a metric combines when several players are pooled into one number -
    /// the roster aggregate the team comparison draws.
    ///
    /// Kept as its own table rather than a field on `MetricDefinition` because
    /// it answers a different question from the rest of the registry (how to
    /// *display* one player's metric vs how to *combine* many), and because the
    /// weights below are the honest part: a rate cannot be averaged across
    /// players without weighting it by the volume it was computed over. Ten
    /// carries at 8.0 EPA/Rush and two hundred at 0.05 do not average to 4.0.
    ///
    /// Volume-weighting a per-play rate by its own denominator reproduces the
    /// true team rate exactly for the ratio metrics (EPA/Play, Sack%, INT%,
    /// Explosive%, Fumble%, Catch%, Cmp%, Y/A, Y/C, EPA/Rush, EPA/Tgt), because
    /// summing numerator and denominator separately is what the weighted mean
    /// works out to. For the Next Gen averages (Time to Throw, Separation,
    /// YAC+, CPOE, ADOT) it is a very close approximation rather than an
    /// identity, since we hold the per-player mean rather than the raw plays.
    static func aggregation(for label: String, category: MetricCategory) -> MetricAggregation {
        switch (category, label) {
        // Passing: every rate is per attempt. Passer rating is a composite of
        // four per-attempt rates, so it weights the same way.
        case (.passing, "Pass Yds"), (.passing, "Pass TD"):
            return .sum
        case (.passing, _):
            return .weighted(.attempts)

        // Rushing: RYOE and Rush EPA are yardage/points totals, not rates.
        case (.rushing, "Rush Yds"), (.rushing, "Rush TD"), (.rushing, "Rush 1D"),
             (.rushing, "Rush EPA"), (.rushing, "RYOE"):
            return .sum
        case (.rushing, _):
            return .weighted(.carries)

        // Receiving: Target Share and WOPR are shares of a team's own passing
        // volume, so a roster's shares genuinely do add up - summing them is
        // right, and it is also the interesting number (how much of the offence
        // these players account for).
        case (.receiving, "Rec"), (.receiving, "Rec Yds"), (.receiving, "Rec TD"),
             (.receiving, "YAC"), (.receiving, "Rec EPA"),
             (.receiving, "Target Share"), (.receiving, "WOPR"):
            return .sum
        case (.receiving, _):
            return .weighted(.targets)

        // Defense: the PFR coverage and pass-rush rates are per target or per
        // tackle attempt; the rest are counting stats.
        case (.defense, "Cmp% Allowed"), (.defense, "Yds/Tgt Allowed"),
             (.defense, "Rating Allowed"), (.defense, "ADOT"):
            return .weighted(.targetsAllowed)
        case (.defense, "Missed Tkl%"):
            return .weighted(.games)
        case (.defense, _):
            return .sum
        }
    }

    static func kind(for metric: Metric) -> MetricKind {
        definition(for: metric.label, category: metric.category)?.kind ?? .advanced
    }

    static func isSupported(_ metric: Metric, by position: PlayerPositionGroup) -> Bool {
        definition(for: metric.label, category: metric.category)?.positions.contains(position) ?? true
    }

    static func sorted(_ metrics: [Metric]) -> [Metric] {
        metrics.sorted { lhs, rhs in
            let left = definition(for: lhs.label, category: lhs.category)?.priority ?? Int.max
            let right = definition(for: rhs.label, category: rhs.category)?.priority ?? Int.max
            if left == right { return lhs.label < rhs.label }
            return left < right
        }
    }

    private static func definition(
        _ label: String,
        _ category: MetricCategory,
        _ kind: MetricKind,
        _ family: MetricFamily,
        _ positions: Set<PlayerPositionGroup>,
        _ priority: Int,
        _ description: String,
        higherIsBetter: Bool = true
    ) -> MetricDefinition {
        MetricDefinition(
            label: label,
            category: category,
            kind: kind,
            family: family,
            positions: positions,
            higherIsBetter: higherIsBetter,
            priority: priority,
            description: description
        )
    }
}

/// How several players' values for one metric collapse into a single number.
enum MetricAggregation: Hashable, Sendable {
    /// Counting stats and totals: add them up.
    case sum
    /// Rates: mean weighted by the volume each player's rate was measured over.
    case weighted(MetricWeight)
}

/// The denominator a rate was computed against, so it can be weighted by it.
/// Each case resolves to a number already present in the player's standard
/// stats, so no extra feed columns are needed.
enum MetricWeight: Hashable, Sendable {
    case attempts
    case carries
    case targets
    case targetsAllowed
    case games

    /// Pulls the weight out of a player's standard-stat line. Returns nil when
    /// the player has no volume for it, which correctly drops them from the
    /// weighted mean instead of contributing a zero.
    func value(for player: Player) -> Double? {
        switch self {
        case .attempts: return Self.secondComponent(of: "Cmp/Att", in: player)
        case .targets: return Self.secondComponent(of: "Rec/Tgt", in: player)
        case .targetsAllowed: return Self.plain("Tgt Allowed", in: player)
        case .carries: return Self.plain("Car", in: player)
        case .games: return Self.plain("G", in: player)
        }
    }

    private static func plain(_ label: String, in player: Player) -> Double? {
        guard let raw = player.standardStats?.first(where: { $0.label == label })?.value,
              let value = metricNumericValue(raw),
              value > 0
        else { return nil }
        return value
    }

    /// "18/29" -> 29. The feed packs completions and attempts (and receptions
    /// and targets) into one display string, and the denominator is the half we
    /// want to weight by.
    private static func secondComponent(of label: String, in player: Player) -> Double? {
        guard let raw = player.standardStats?.first(where: { $0.label == label })?.value else { return nil }
        let parts = raw.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let value = metricNumericValue(String(parts[1])),
              value > 0
        else { return nil }
        return value
    }
}

extension Player {
    var isDefensivePlayer: Bool {
        playerType?.lowercased() == "def" || positionGroup == .defense
    }

    func canCompareHeadToHead(with other: Player) -> Bool {
        isDefensivePlayer == other.isDefensivePlayer
    }

    var positionGroup: PlayerPositionGroup {
        switch playerType?.lowercased() {
        case "qb": return .qb
        case "rb": return .rb
        case "wr": return .wr
        case "te": return .te
        case "def": return .defense
        default:
            let position = displayPosition.uppercased()
            if position == "QB" { return .qb }
            if position == "RB" || position == "FB" { return .rb }
            if position == "WR" { return .wr }
            if position == "TE" { return .te }
            return primaryCategory == .defense ? .defense : .wr
        }
    }

    /// The volume a category's rates were measured over, for a board subtitle:
    /// "16 att", "23 tgt", "31 car". Nil when the line has none.
    func volumeCaption(for category: MetricCategory) -> String? {
        switch category {
        case .passing:
            return MetricWeight.attempts.value(for: self).map { "\(Int($0)) att" }
        case .rushing:
            return MetricWeight.carries.value(for: self).map { "\(Int($0)) car" }
        case .receiving:
            return MetricWeight.targets.value(for: self).map { "\(Int($0)) tgt" }
        case .defense:
            return MetricWeight.games.value(for: self).map { "\(Int($0)) G" }
        }
    }

    func metrics(kind: MetricKind) -> [Metric] {
        FootballMetricRegistry.sorted(metrics.filter { FootballMetricRegistry.kind(for: $0) == kind })
    }

    func preferredHeadlineMetric(kind: MetricKind) -> Metric? {
        let candidates = metrics(kind: kind)
        let preferred = kind == .advanced
            ? positionGroup.preferredAdvancedMetrics
            : positionGroup.preferredTraditionalMetrics
        for label in preferred {
            if let metric = candidates.first(where: { $0.label == label }) { return metric }
        }
        return candidates.first
    }
}
