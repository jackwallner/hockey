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
        // Players who span more than one category (e.g. a forward with Scoring,
        // Shot Quality and Play Driving metrics) shouldn't have their headline number
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
        return "\(name) · \(team) \(displayPosition)\nOverall: \(overallPercentile.ordinal) percentile\nTop stat: \(headline)\nRink StatScout"
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

    init(id: String, label: String, value: String, percentile: Int, category: MetricCategory, qualified: Bool? = nil, rankable: Bool? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.percentile = percentile
        self.category = category
        self.qualified = qualified
        self.rankable = rankable
    }

    enum CodingKeys: String, CodingKey {
        case id, label, value, percentile, category, qualified, rankable
    }

    /// The historical bundle leaves the id out (it is the single largest cost
    /// in a 20,000-row plist and is fully determined by category and label
    /// within one player); the live feed still carries it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        value = try c.decode(String.self, forKey: .value)
        percentile = try c.decode(Int.self, forKey: .percentile)
        category = try c.decode(MetricCategory.self, forKey: .category)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Self.derivedID(category: category, label: label)
        qualified = try c.decodeIfPresent(Bool.self, forKey: .qualified)
        rankable = try c.decodeIfPresent(Bool.self, forKey: .rankable)
    }

    static func derivedID(category: MetricCategory, label: String) -> String {
        "\(category.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(label)"
    }

    /// A traditional counting stat at zero: 0 G, 0 SHG, 0 SO.
    ///
    /// The feed ranks these with the midpoint of the tie, so a week in, the 300
    /// skaters without a goal were all painted 47th percentile. A
    /// player who has done none of a thing is not a 47th-percentile player at
    /// it, and when most of the league is tied at zero there is no honest rank
    /// at all. The value still shows; the bar, the number and the player's
    /// overall average leave it out.
    var isUnranked: Bool {
        if rankable == false { return true }
        guard let definition = HockeyMetricRegistry.definition(for: label, category: category),
              definition.kind == .traditional,
              HockeyMetricRegistry.aggregation(for: label, category: category) == .sum,
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
/// Most values are plain numbers. `TOI/GP` is a clock ("19:42") and ranks by
/// its minutes; for a few stats the smaller number is the better one.
enum StandardStatSemantics {
    enum Winner: Equatable {
        case left
        case right
    }

    static func numericValue(label: String, value: String) -> Double? {
        switch label.uppercased() {
        case "TOI/GP":
            return MetricWeight.clockMinutes(value)
        default:
            return metricNumericValue(value)
        }
    }

    /// Stats where fewer is better: goals against average, penalty minutes,
    /// and a goalie's losses and overtime losses.
    static func higherIsBetter(label: String) -> Bool {
        !["GAA", "PIM", "L", "OT"].contains(label.uppercased())
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
    // Strip thousands separators - the feed ships "1,312".
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
    case scoring = "Scoring"
    case shotQuality = "Shot Quality"
    case playDriving = "Play Driving"
    case goaltending = "Goaltending"

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

    /// Short form for segmented controls and chips.
    var shortLabel: String {
        switch self {
        case .scoring: return "Scoring"
        case .shotQuality: return "Shots"
        case .playDriving: return "Driving"
        case .goaltending: return "Goalies"
        }
    }

    /// Registry-driven display order. Advanced metrics lead within each category,
    /// followed by traditional production metrics.
    var metricPriorityOrder: [String] {
        HockeyMetricRegistry.definitions
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

/// NHL seasons span two calendar years. The feed keys a season by its start
/// year (2026 is 2026-27); every label the user sees goes through here.
enum SeasonLabel {
    static let allTime = 0

    static func display(_ season: Int) -> String {
        guard season != allTime else { return "All Time" }
        let end = (season + 1) % 100
        return String(format: "%d-%02d", season, end)
    }

    /// "2026-27 regular season" style captions.
    static func display(_ season: Int, phase: SeasonPhase) -> String {
        guard season != allTime else { return "All Time" }
        return "\(display(season)) \(phase == .regular ? "regular season" : "playoffs")"
    }
}

extension Player {
    /// Known NHL cohorts the snapshot feed assigns: forwards, defensemen, goalies.
    private static let knownTypes: Set<String> = ["f", "d", "g"]

    func matchesPlayerType(for category: MetricCategory?) -> Bool {
        guard let category else { return true }
        // Only filter on a recognized cohort. An unknown / missing player_type
        // falls through to "include" so we never drop a player who lost their
        // role label upstream but still carries real metrics.
        guard let type = playerType?.lowercased(), Self.knownTypes.contains(type) else { return true }
        switch category {
        case .scoring, .shotQuality, .playDriving:
            return type == "f" || type == "d"
        case .goaltending:
            return type == "g"
        }
    }

    /// The category a player leads with - drives Recent Form and single-category
    /// framing. Derived from the cohort, falling back to the most common metric
    /// category when the role label is missing.
    var primaryCategory: MetricCategory {
        switch playerType?.lowercased() {
        case "f": return .scoring
        case "d": return .playDriving
        case "g": return .goaltending
        default:
            let counts = Dictionary(grouping: metrics, by: \.category).mapValues(\.count)
            return counts.max { $0.value < $1.value }?.key ?? .scoring
        }
    }

    /// Position to surface in the UI. When the snapshot has no position (TBD /
    /// empty) but the player has metrics, fall back to the cohort label so we
    /// never show "TBD" next to real stats.
    var displayPosition: String {
        let trimmed = position.trimmingCharacters(in: .whitespaces).uppercased()
        if !trimmed.isEmpty && trimmed != "TBD" && trimmed != "\u{2014}" && trimmed != "-" {
            return trimmed == "L" ? "LW" : trimmed == "R" ? "RW" : trimmed
        }
        return positionGroup.rawValue
    }

    var initials: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return "" }
        guard parts.count > 1 else { return String(first.prefix(1)) }

        let last = parts.last!
        let suffix = last.trimmingCharacters(in: .punctuationCharacters).uppercased()
        let hasSuffix = ["JR", "SR", "II", "III", "IV", "V"].contains(suffix)

        if hasSuffix && parts.count > 2 {
            let lastName = parts[parts.count - 2]
            return String(first.prefix(1)) + String(lastName.prefix(1))
        }

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
    case forward = "F"
    case defense = "D"
    case goalie = "G"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forward: return "Forwards"
        case .defense: return "Defensemen"
        case .goalie: return "Goalies"
        }
    }

    var singular: String {
        switch self {
        case .forward: return "Forward"
        case .defense: return "Defenseman"
        case .goalie: return "Goalie"
        }
    }

    var cohortDescription: String {
        "Among \(displayName.lowercased())"
    }

    var isSkater: Bool { self != .goalie }

    var primaryCategory: MetricCategory {
        switch self {
        case .forward: return .scoring
        case .defense: return .playDriving
        case .goalie: return .goaltending
        }
    }

    /// The categories this cohort appears in, in board order.
    var categories: [MetricCategory] {
        switch self {
        case .forward: return [.scoring, .shotQuality, .playDriving]
        case .defense: return [.playDriving, .shotQuality, .scoring]
        case .goalie: return [.goaltending]
        }
    }

    var preferredAdvancedMetrics: [String] {
        switch self {
        case .forward: return ["ixG", "GAx", "P/60", "xGF%"]
        case .defense: return ["xGF%", "Rel xGF%", "xGA/60", "ixG"]
        case .goalie: return ["GSAx", "HD SV%", "GSAx/60"]
        }
    }

    var preferredTraditionalMetrics: [String] {
        switch self {
        case .forward: return ["P", "G", "A"]
        case .defense: return ["P", "Blocks", "A"]
        case .goalie: return ["SV%", "GAA", "W"]
        }
    }
}

enum MetricKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case advanced = "Advanced"
    case traditional = "Traditional"

    var id: String { rawValue }
}

enum MetricFamily: String, CaseIterable, Identifiable, Hashable, Sendable {
    case production = "Production"
    case expectedGoals = "Expected Goals"
    case shooting = "Shooting"
    case possession = "Possession"
    case defense = "Defense"
    case usage = "Usage"
    case goaltending = "Goaltending"
    case workload = "Workload"

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

enum HockeyMetricRegistry {
    private static let skaters: Set<PlayerPositionGroup> = [.forward, .defense]

    static let definitions: [MetricDefinition] = [
        // Scoring. Rates lead; the counting stats every box score carries follow.
        definition("P/60", .scoring, .advanced, .production, skaters, 10, "Points per 60 minutes of ice time, all situations. Production with the ice time taken out."),
        definition("Primary P", .scoring, .advanced, .production, skaters, 20, "Goals plus primary assists. Secondary assists are left out because they track linemates more than the player."),
        definition("Game Score", .scoring, .advanced, .production, skaters, 30, "MoneyPuck game score per game played: one number that weighs goals, assists, shots, blocks, penalties, faceoffs and on-ice shot share."),
        definition("G", .scoring, .traditional, .production, skaters, 110, "Goals, all situations."),
        definition("A", .scoring, .traditional, .production, skaters, 120, "Assists, primary and secondary."),
        definition("P", .scoring, .traditional, .production, skaters, 130, "Points: goals plus assists."),
        definition("PP P", .scoring, .traditional, .production, skaters, 140, "Power-play points, scored at 5 on 4."),
        definition("SOG", .scoring, .traditional, .shooting, skaters, 150, "Shots on goal."),
        definition("Sh%", .scoring, .traditional, .shooting, skaters, 160, "Goals divided by shots on goal."),

        // Shot Quality. MoneyPuck's expected goals model, the number analytics
        // readers reach for first.
        definition("ixG", .shotQuality, .advanced, .expectedGoals, skaters, 10, "Individual expected goals: the sum of each shot's probability of scoring given its location, type, rebound and rush context. From MoneyPuck."),
        definition("GAx", .shotQuality, .advanced, .expectedGoals, skaters, 20, "Goals above expected: actual goals minus individual expected goals. Positive means finishing above what the shots deserved."),
        definition("ixG/60", .shotQuality, .advanced, .expectedGoals, skaters, 30, "Individual expected goals per 60 minutes, all situations."),
        definition("xG/Shot", .shotQuality, .advanced, .shooting, skaters, 40, "Expected goals per unblocked shot attempt: how dangerous the average shot is."),
        definition("Shots/60", .shotQuality, .advanced, .shooting, skaters, 50, "Shot attempts per 60 minutes, blocked and missed included."),
        definition("Shot Att", .shotQuality, .traditional, .shooting, skaters, 110, "Shot attempts: on goal, missed and blocked."),
        definition("HD Shots", .shotQuality, .traditional, .shooting, skaters, 120, "High-danger shots, the attempts MoneyPuck rates at 20% or more to score."),
        definition("Rebounds", .shotQuality, .traditional, .shooting, skaters, 130, "Rebounds created by the player's shots."),

        // Play Driving. 5 on 5 on-ice share metrics, the Natural Stat Trick
        // vocabulary, plus the counting stats a defenseman is judged on.
        definition("xGF%", .playDriving, .advanced, .possession, skaters, 10, "Share of 5-on-5 expected goals that went the player's way while on the ice. 50% is even."),
        definition("Rel xGF%", .playDriving, .advanced, .possession, skaters, 20, "On-ice xGF% minus the team's xGF% with the player on the bench. Separates the player from the team."),
        definition("CF%", .playDriving, .advanced, .possession, skaters, 30, "Corsi for percentage: share of all 5-on-5 shot attempts while on the ice."),
        definition("Rel CF%", .playDriving, .advanced, .possession, skaters, 40, "On-ice CF% minus the team's CF% with the player on the bench."),
        definition("HDCF%", .playDriving, .advanced, .possession, skaters, 50, "Share of 5-on-5 high-danger shot attempts while on the ice."),
        definition("GF%", .playDriving, .advanced, .possession, skaters, 60, "Share of 5-on-5 goals while on the ice. Swings on goaltending and shooting luck; compare with xGF%."),
        definition("xGF/60", .playDriving, .advanced, .possession, skaters, 70, "5-on-5 expected goals for per 60 minutes while on the ice."),
        definition("xGA/60", .playDriving, .advanced, .defense, skaters, 80, "5-on-5 expected goals against per 60 minutes while on the ice. Lower is better.", higherIsBetter: false),
        definition("Blocks", .playDriving, .traditional, .defense, skaters, 110, "Shots blocked."),
        definition("Hits", .playDriving, .traditional, .defense, skaters, 120, "Hits credited by the home scorer."),
        definition("Takeaways", .playDriving, .traditional, .defense, skaters, 130, "Takeaways credited by the home scorer."),
        definition("Giveaways", .playDriving, .traditional, .defense, skaters, 140, "Giveaways credited by the home scorer. Lower is better.", higherIsBetter: false),

        // Goaltending. Goals saved above expected is the headline; save
        // percentage and GAA are the numbers on the broadcast.
        definition("GSAx", .goaltending, .advanced, .goaltending, [.goalie], 10, "Goals saved above expected: expected goals faced minus goals allowed. From MoneyPuck."),
        definition("GSAx/60", .goaltending, .advanced, .goaltending, [.goalie], 20, "Goals saved above expected per 60 minutes."),
        definition("HD SV%", .goaltending, .advanced, .goaltending, [.goalie], 30, "Save percentage on high-danger shots."),
        definition("xGA/60", .goaltending, .advanced, .workload, [.goalie], 40, "Expected goals faced per 60 minutes: how much danger the goalie saw."),
        definition("Rebound%", .goaltending, .advanced, .goaltending, [.goalie], 50, "Share of shots on goal that produced a rebound. Lower is better.", higherIsBetter: false),
        definition("SV%", .goaltending, .traditional, .goaltending, [.goalie], 110, "Saves divided by shots on goal."),
        definition("GAA", .goaltending, .traditional, .goaltending, [.goalie], 120, "Goals against per 60 minutes. Lower is better.", higherIsBetter: false),
        definition("W", .goaltending, .traditional, .production, [.goalie], 130, "Wins."),
        definition("SO", .goaltending, .traditional, .production, [.goalie], 140, "Shutouts."),
        definition("Saves", .goaltending, .traditional, .workload, [.goalie], 150, "Saves."),
        definition("GA", .goaltending, .traditional, .goaltending, [.goalie], 160, "Goals against. Lower is better.", higherIsBetter: false)
    ]

    static func definition(for label: String, category: MetricCategory) -> MetricDefinition? {
        definitions.first { $0.label == label && $0.category == category }
    }

    /// How a metric combines when several players are pooled into one number,
    /// the roster aggregate the team comparison draws.
    ///
    /// A rate cannot be averaged across players without weighting it by the
    /// volume it was computed over: twenty minutes at 4.0 P/60 and a thousand
    /// at 1.5 do not average to 2.75. Per-60 rates weight by ice time, per-shot
    /// rates by shots, goalie rates by shots against. Shares (xGF%, CF%) weight
    /// by ice time too, which is exact when every player's on-ice sample is in
    /// proportion to his minutes and a close approximation otherwise.
    static func aggregation(for label: String, category: MetricCategory) -> MetricAggregation {
        switch (category, label) {
        case (.scoring, "Sh%"):
            return .weighted(.shotsOnGoal)
        case (.scoring, "P/60"), (.scoring, "Game Score"):
            return .weighted(.iceTime)
        case (.scoring, _):
            return .sum

        case (.shotQuality, "xG/Shot"):
            return .weighted(.shotAttempts)
        case (.shotQuality, "ixG/60"), (.shotQuality, "Shots/60"):
            return .weighted(.iceTime)
        case (.shotQuality, _):
            return .sum

        case (.playDriving, "Blocks"), (.playDriving, "Hits"),
             (.playDriving, "Takeaways"), (.playDriving, "Giveaways"):
            return .sum
        case (.playDriving, _):
            return .weighted(.iceTime)

        case (.goaltending, "W"), (.goaltending, "SO"), (.goaltending, "Saves"),
             (.goaltending, "GA"), (.goaltending, "GSAx"):
            return .sum
        case (.goaltending, "GAA"), (.goaltending, "GSAx/60"), (.goaltending, "xGA/60"):
            return .weighted(.iceTime)
        case (.goaltending, _):
            return .weighted(.shotsAgainst)
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
    /// Total ice time in minutes: TOI/GP times GP.
    case iceTime
    case shotsOnGoal
    case shotAttempts
    case shotsAgainst
    case games

    /// Pulls the weight out of a player's standard-stat line. Returns nil when
    /// the player has no volume for it, which correctly drops them from the
    /// weighted mean instead of contributing a zero.
    func value(for player: Player) -> Double? {
        switch self {
        case .iceTime: return Self.totalIceTime(in: player)
        case .shotsOnGoal: return Self.plain("SOG", in: player)
        case .shotAttempts: return Self.plain("SOG", in: player)
        case .shotsAgainst: return Self.plain("SA", in: player)
        case .games: return Self.plain("GP", in: player)
        }
    }

    private static func plain(_ label: String, in player: Player) -> Double? {
        guard let raw = player.standardStats?.first(where: { $0.label == label })?.value,
              let value = metricNumericValue(raw),
              value > 0
        else { return nil }
        return value
    }

    /// "19:42" per game times games played. A goalie line carries no TOI/GP, so
    /// goalies weight by games instead.
    private static func totalIceTime(in player: Player) -> Double? {
        guard let games = plain("GP", in: player) else { return nil }
        guard let raw = player.standardStats?.first(where: { $0.label == "TOI/GP" })?.value,
              let perGame = clockMinutes(raw), perGame > 0
        else { return games }
        return perGame * games
    }

    /// "19:42" -> 19.7 minutes.
    static func clockMinutes(_ raw: String) -> Double? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else {
            return metricNumericValue(raw)
        }
        return minutes + seconds / 60
    }
}

extension Player {
    var isGoalie: Bool {
        playerType?.lowercased() == "g" || positionGroup == .goalie
    }

    /// Kept for call sites that framed the gate as offense vs defense; in
    /// hockey the line that cannot be crossed is skater vs goalie.
    var isDefensivePlayer: Bool { isGoalie }

    func canCompareHeadToHead(with other: Player) -> Bool {
        isGoalie == other.isGoalie
    }

    var positionGroup: PlayerPositionGroup {
        switch playerType?.lowercased() {
        case "f": return .forward
        case "d": return .defense
        case "g": return .goalie
        default:
            let position = self.position.trimmingCharacters(in: .whitespaces).uppercased()
            if position == "G" { return .goalie }
            if position == "D" { return .defense }
            if ["C", "L", "R", "W", "LW", "RW", "F"].contains(position) { return .forward }
            return primaryCategory == .goaltending ? .goalie : .forward
        }
    }

    /// The volume a category's rates were measured over, for a board subtitle:
    /// "41 SOG", "312 min", "12 GP". Nil when the line has none.
    func volumeCaption(for category: MetricCategory) -> String? {
        switch category {
        case .scoring, .playDriving:
            return MetricWeight.iceTime.value(for: self).map { "\(Int($0.rounded())) min" }
        case .shotQuality:
            return MetricWeight.shotsOnGoal.value(for: self).map { "\(Int($0)) SOG" }
        case .goaltending:
            return MetricWeight.shotsAgainst.value(for: self).map { "\(Int($0)) SA" }
        }
    }

    func metrics(kind: MetricKind) -> [Metric] {
        HockeyMetricRegistry.sorted(metrics.filter { HockeyMetricRegistry.kind(for: $0) == kind })
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
