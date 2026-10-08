#if DEBUG
import Foundation

/// Deterministic, fictional NFL rows used only by the release screenshot
/// harness. The capture suite still drives the shipped views and navigation,
/// while this provider keeps a screenshot run independent of network timing,
/// source publication lag, and the shared simulator's cache.
struct ScreenshotFixtureAPI: StatcastProviding {
    static let launchArgument = "-ScreenshotData"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Seeds only the local simulator's fan context for a capture. The hook is
    /// called from `StatScoutApp` before `ContentView` is created, which makes
    /// the Following board deterministic without teaching a product view about
    /// test data.
    static func prepareUserDefaults() {
        UserDefaults.standard.set([12001, 12007, 12011], forKey: "favorites.playerIds")
        UserDefaults.standard.set("KC", forKey: "favoriteTeam")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set("standard", forKey: "stats.board")
        UserDefaults.standard.removeObject(forKey: "statcast.dataFreshness")
        UserDefaults.standard.removeObject(forKey: "statcast.displayedDataRevision")
    }

    private static let season = StatScoutSeason.current
    private static let priorSeason = season - 1
    // Week 2 is a coherent fictional capture date for the 2026 season. It
    // keeps the current-season windows honest and repeatable.
    private static let asOf = makeDate("2026-09-16T20:00:00Z")
    private static let playersBySeason: [Int: [Player]] = [
        season: makePlayers(season: season, prior: false),
        priorSeason: makePlayers(season: priorSeason, prior: true),
    ]

    func fetchPlayers() async throws -> [Player] {
        Self.playersBySeason.values.flatMap { $0 }
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        Self.playersBySeason[Self.priorSeason] ?? []
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        Self.playersBySeason[Self.season] ?? []
    }

    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        guard seasonPhase == .regular,
              season == Self.season,
              let player = Self.playersBySeason[season]?.first(where: { $0.playerId == playerId })
        else { return [] }
        return Self.makeGameLogs(for: player)
    }

    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog] {
        guard seasonPhase == .regular,
              let players = Self.playersBySeason[season]
        else { return [] }
        return players
            .filter { $0.team == team }
            .flatMap { Self.makeGameLogs(for: $0) }
            .filter { $0.gameDate >= sinceDate }
    }

    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        guard seasonPhase == .regular,
              season == Self.season
        else { return [] }
        return (Self.playersBySeason[Self.season] ?? []).map {
            Self.makeRecentForm(for: $0, windowWeeks: windowWeeks)
        }
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        guard season == Self.season else { return nil }
        return DataCoverage(asOf: Self.asOf, week: 2, phase: .regular, gamesIncluded: 32)
    }

    func fetchDataFreshness(season: Int) async throws -> DataFreshness? {
        guard season == Self.season else { return nil }
        return DataFreshness(
            status: .ready,
            revision: "screenshot-fixture-v12",
            sourcePublishedAt: Self.asOf,
            publishedAt: Self.asOf,
            checkedAt: Self.asOf,
            coverage: DataCoverage(asOf: Self.asOf, week: 2, phase: .regular, gamesIncluded: 32),
            message: "Fixture data through Week 2",
            isCached: false
        )
    }
}

extension ScreenshotFixtureAPI {
    struct PlayerSeed {
        let id: Int
        let name: String
        let team: String
        let position: String
        let type: String
        let percentile: Int
        let headline: Double
    }

    static let seeds: [PlayerSeed] = [
        .init(id: 12001, name: "Caleb Mercer", team: "KC", position: "QB", type: "qb", percentile: 96, headline: 0.31),
        .init(id: 12002, name: "Mason Reed", team: "SEA", position: "QB", type: "qb", percentile: 91, headline: 0.24),
        .init(id: 12003, name: "Jordan Vale", team: "SF", position: "QB", type: "qb", percentile: 87, headline: 0.19),
        .init(id: 12004, name: "Tyler Knox", team: "BUF", position: "QB", type: "qb", percentile: 83, headline: 0.13),
        .init(id: 12005, name: "Darius Cole", team: "DET", position: "QB", type: "qb", percentile: 78, headline: 0.09),
        .init(id: 12006, name: "Eli Brooks", team: "PHI", position: "QB", type: "qb", percentile: 73, headline: 0.05),
        .init(id: 12007, name: "Marcus Hale", team: "KC", position: "RB", type: "rb", percentile: 94, headline: 0.22),
        .init(id: 12008, name: "Devon Price", team: "BAL", position: "RB", type: "rb", percentile: 89, headline: 0.17),
        .init(id: 12009, name: "Andre Lewis", team: "DET", position: "RB", type: "rb", percentile: 84, headline: 0.12),
        .init(id: 12010, name: "Nico Grant", team: "DAL", position: "RB", type: "rb", percentile: 77, headline: 0.06),
        .init(id: 12011, name: "Jalen Cross", team: "CIN", position: "WR", type: "wr", percentile: 95, headline: 0.29),
        .init(id: 12012, name: "Cam Porter", team: "MIA", position: "WR", type: "wr", percentile: 86, headline: 0.16),
        .init(id: 12013, name: "Theo Banks", team: "KC", position: "TE", type: "te", percentile: 90, headline: 0.21),
        .init(id: 12014, name: "Roman Ellis", team: "GB", position: "TE", type: "te", percentile: 81, headline: 0.11),
        .init(id: 12015, name: "Isaiah Boone", team: "PIT", position: "LB", type: "def", percentile: 93, headline: 0.0),
        .init(id: 12016, name: "Malik Ford", team: "DAL", position: "EDGE", type: "def", percentile: 88, headline: 0.0),
        .init(id: 12017, name: "Trent York", team: "SF", position: "CB", type: "def", percentile: 84, headline: 0.0),
        .init(id: 12018, name: "Kade Rivers", team: "BUF", position: "S", type: "def", percentile: 79, headline: 0.0),
    ]

    static func makePlayers(season: Int, prior: Bool) -> [Player] {
        seeds.map { seed in
            let scale = prior ? 0.84 : 1.0
            let percentile = prior ? max(55, seed.percentile - 4) : seed.percentile
            return Player(
                playerId: seed.id,
                name: seed.name,
                team: seed.team,
                position: seed.position,
                handedness: seed.type == "def" ? "" : "R",
                updatedAt: asOf,
                season: season,
                seasonPhase: .regular,
                playerType: seed.type,
                source: "screenshot-fixture",
                metrics: metrics(for: seed, scale: scale, percentile: percentile),
                standardStats: standardStats(for: seed, scale: scale),
                games: gameTrends(for: seed, prior: prior)
            )
        }
    }

    static func metrics(
        for seed: PlayerSeed,
        scale: Double,
        percentile: Int
    ) -> [Metric] {
        switch seed.type {
        case "qb":
            return [
                metric("epa-play", "EPA/Play", seed.headline * scale, percentile, .passing),
                metric("cpoe", "CPOE", 6.4 * scale, max(50, percentile - 3), .passing),
                metric("int-rate", "INT%", 1.3 / scale, max(50, percentile - 7), .passing),
                metric("sack-rate", "Sack%", 4.8 / scale, max(50, percentile - 4), .passing),
                metric("time-to-throw", "Time to Throw", 2.63 / scale, max(50, percentile - 5), .passing),
                metric("aggressiveness", "Aggressiveness", 18.2 * scale, max(50, percentile - 8), .passing),
                metric("air-yards", "Intended Air Yds", 8.7 * scale, max(50, percentile - 2), .passing),
                metric("rush-epa", "EPA/Rush", 0.12 * scale, max(50, percentile - 8), .rushing),
                metric("rush-yoe", "RYOE", 34 * scale, max(50, percentile - 12), .rushing),
            ]
        case "rb":
            return [
                metric("epa-rush", "EPA/Rush", seed.headline * scale, percentile, .rushing),
                metric("ryoe", "RYOE", 49 * scale, max(50, percentile - 3), .rushing),
                metric("explosive", "Explosive%", 14.2 * scale, max(50, percentile - 7), .rushing),
                metric("rush-epa", "Rush EPA", 11.4 * scale, max(50, percentile - 4), .rushing),
                metric("fumble-rate", "Fumble%", 1.1 / scale, max(50, percentile - 6), .rushing),
                metric("epa-target", "EPA/Tgt", 0.16 * scale, max(50, percentile - 7), .receiving),
            ]
        case "wr", "te":
            return [
                metric("epa-target", "EPA/Tgt", seed.headline * scale, percentile, .receiving),
                metric("wopr", "WOPR", 0.51 * scale, max(50, percentile - 3), .receiving),
                metric("target-share", "Target Share", 24.8 * scale, max(50, percentile - 5), .receiving),
                metric("racr", "RACR", 1.34 * scale, max(50, percentile - 2), .receiving),
                metric("separation", "Separation", 3.1 * scale, max(50, percentile - 8), .receiving),
                metric("yac-plus", "YAC+", 2.4 * scale, max(50, percentile - 5), .receiving),
                metric("rec-epa", "Rec EPA", 17.7 * scale, max(50, percentile - 3), .receiving),
            ]
        default:
            return [
                metric("pressures", "Pressures", 29 * scale, percentile, .defense),
                metric("hurries", "Hurries", 21 * scale, max(50, percentile - 4), .defense),
                metric("qb-kd", "QB KD", 8 * scale, max(50, percentile - 6), .defense),
                metric("cmp-allowed", "Cmp% Allowed", 48.2 / scale, max(50, percentile - 6), .defense),
                metric("yards-target", "Yds/Tgt Allowed", 6.1 / scale, max(50, percentile - 4), .defense),
                metric("rating-allowed", "Rating Allowed", 71.4 / scale, max(50, percentile - 5), .defense),
                metric("missed-tackle", "Missed Tkl%", 7.8 / scale, max(50, percentile - 4), .defense),
            ]
        }
    }

    static func metric(
        _ id: String,
        _ label: String,
        _ value: Double,
        _ percentile: Int,
        _ category: MetricCategory
    ) -> Metric {
        Metric(
            id: id,
            label: label,
            value: formattedMetricValue(label: label, value: value),
            percentile: percentile,
            category: category,
            qualified: true
        )
    }

    static func formattedMetricValue(label: String, value: Double) -> String {
        switch label {
        case "CPOE", "Aggressiveness", "Target Share", "Explosive%", "Cmp% Allowed", "Missed Tkl%":
            return String(format: "%.1f%%", value)
        case "INT%", "Sack%", "Fumble%":
            return String(format: "%.1f%%", value)
        case "EPA/Play", "EPA/Rush": return String(format: "%.2f", value)
        case "Time to Throw": return String(format: "%.2f s", value)
        case "WOPR", "RACR": return String(format: "%.2f", value)
        case "EPA/Tgt": return String(format: "%.2f", value)
        case "Yds/Tgt Allowed": return String(format: "%.1f", value)
        case "Rating Allowed": return String(format: "%.1f", value)
        case "YAC+", "Separation": return String(format: "%.1f", value)
        default: return String(format: "%.1f", value)
        }
    }

    static func standardStats(for seed: PlayerSeed, scale: Double) -> [StandardStat] {
        func stat(_ label: String, _ value: String) -> StandardStat {
            StandardStat(id: label.lowercased().replacingOccurrences(of: " ", with: "-"), label: label, value: value)
        }
        let games = max(1, Int((5 * scale).rounded()))
        let rankFactor = 0.72 + (Double(seed.percentile) / 100.0 * 0.28)
        switch seed.type {
        case "qb":
            let yards = Int((1_650 * rankFactor * scale).rounded())
            let attempts = Int((178 * rankFactor * scale).rounded())
            let completions = Int((122 * rankFactor * scale).rounded())
            return [
                stat("G", "\(games)"), stat("Cmp/Att", "\(completions)/\(attempts)"),
                stat("Pass Yds", "\(yards)"), stat("Pass TD", "\(Int((16 * rankFactor * scale).rounded()))"),
                stat("INT", "\(max(1, Int((2 * scale).rounded())))"),
                stat("Car", "\(Int((18 * rankFactor * scale).rounded()))"), stat("Rush Yds", "\(Int((108 * rankFactor * scale).rounded()))"),
                stat("Rush TD", "\(max(1, Int((2 * rankFactor * scale).rounded())))"),
            ]
        case "rb":
            return [
                stat("G", "\(games)"), stat("Car", "\(Int((82 * rankFactor * scale).rounded()))"),
                stat("Rush Yds", "\(Int((496 * rankFactor * scale).rounded()))"), stat("Rush TD", "\(Int((6 * rankFactor * scale).rounded()))"),
                stat("Rec/Tgt", "\(Int((19 * rankFactor * scale).rounded()))/\(Int((25 * rankFactor * scale).rounded()))"),
                stat("Rec Yds", "\(Int((164 * rankFactor * scale).rounded()))"), stat("Rec TD", "\(max(1, Int((2 * rankFactor * scale).rounded())))"),
            ]
        case "wr", "te":
            let rec = seed.type == "wr" ? 31 : 23
            let tgt = seed.type == "wr" ? 46 : 34
            return [
                stat("G", "\(games)"), stat("Rec/Tgt", "\(Int((Double(rec) * rankFactor * scale).rounded()))/\(Int((Double(tgt) * rankFactor * scale).rounded()))"),
                stat("Rec Yds", "\(Int((412 * rankFactor * scale).rounded()))"), stat("Rec TD", "\(Int((4 * rankFactor * scale).rounded()))"),
                stat("YAC", "\(Int((146 * rankFactor * scale).rounded()))"), stat("Car", "\(Int((3 * rankFactor * scale).rounded()))"),
                stat("Rush Yds", "\(Int((19 * rankFactor * scale).rounded()))"), stat("Rush TD", "0"),
            ]
        default:
            return [
                stat("G", "\(games)"), stat("Tackles", "\(Int((42 * rankFactor * scale).rounded()))"),
                stat("Sacks", String(format: "%.1f", 3.5 * rankFactor * scale)), stat("Def INT", "\(max(1, Int((2 * rankFactor * scale).rounded())))"),
                stat("PD", "\(Int((6 * rankFactor * scale).rounded()))"), stat("TFL", "\(Int((5 * rankFactor * scale).rounded()))"),
                stat("QB Hits", "\(Int((9 * rankFactor * scale).rounded()))"), stat("FF", "\(max(1, Int((1 * rankFactor * scale).rounded())))"),
            ]
        }
    }

    static func gameTrends(for seed: PlayerSeed, prior: Bool) -> [GameTrend] {
        (0..<5).map { index in
            GameTrend(
                id: "\(seed.id)-\(prior ? "prior" : "current")-\(index)",
                date: Calendar.current.date(byAdding: .day, value: -(index * 7), to: asOf) ?? asOf,
                opponent: ["LV", "LAC", "DEN", "CIN", "BUF"][index],
                summary: index == 0 ? "Strong finish" : "Complete game",
                percentileDelta: (prior ? 1 : 2) * (5 - index),
                keyMetric: seed.type == "def" ? "Pressures" : "EPA/Play"
            )
        }
    }

    static func makeGameLogs(for player: Player) -> [PlayerGameLog] {
        (0..<5).map { index in
            let date = Calendar.current.date(byAdding: .day, value: -((4 - index) * 7), to: asOf) ?? asOf
            let factor = 1.0 + (Double(index) * 0.04)
            return PlayerGameLog(
                fixturePlayerId: player.playerId,
                season: season,
                seasonPhase: .regular,
                gameDate: date,
                playerType: player.playerType ?? "qb",
                team: player.team,
                opponent: ["LV", "LAC", "DEN", "CIN", "BUF"][index],
                plays: plays(for: player.playerType ?? "qb"),
                touches: touches(for: player.playerType ?? "qb"),
                metrics: gameMetrics(for: player.playerType ?? "qb", factor: factor)
            )
        }
    }

    static func plays(for type: String) -> Int {
        switch type {
        case "qb": return 34
        case "rb": return 21
        case "wr": return 13
        case "te": return 11
        default: return 0
        }
    }

    static func touches(for type: String) -> Int {
        switch type {
        case "qb": return 31
        case "rb": return 17
        case "wr": return 8
        case "te": return 7
        default: return 0
        }
    }

    static func gameMetrics(for type: String, factor: Double) -> [String: Double?] {
        switch type {
        case "qb":
            return [
                "passing_epa": 0.24 * factor, "cpoe": 4.8 * factor, "ypa": 8.3 * factor,
                "cmp_pct": 69.0 * factor, "passer_rating": 108.0 * factor, "int_rate": 1.0 / factor,
                "sack_rate": 4.0 / factor, "avg_time_to_throw": 2.55 / factor,
                "pass_yards": 278 * factor, "pass_tds": 2 * factor, "completions": 24 * factor,
                "attempts": 34 * factor, "interceptions": 0, "rush_yards": 18 * factor,
                "rush_tds": 0, "carries": 4 * factor,
            ]
        case "rb":
            return [
                "rushing_epa": 0.18 * factor, "rush_yoe": 9.0 * factor,
                "ypc": 5.8 * factor, "rush_yards": 96 * factor, "rush_tds": 1 * factor,
                "carries": 17 * factor, "rush_first_downs": 5 * factor,
                "receptions": 4 * factor, "rec_yards": 33 * factor, "rec_tds": 0,
                "catch_pct": 80.0 * factor, "fumble_rate": 0.5 / factor,
            ]
        case "wr", "te":
            return [
                "receiving_epa": 0.35 * factor, "catch_pct": 72.0 * factor,
                "avg_separation": 3.2 * factor, "avg_yac_above_expectation": 2.4 * factor,
                "racr": 1.42 * factor, "rec_yards": (type == "wr" ? 92 : 67) * factor,
                "receptions": (type == "wr" ? 7 : 5) * factor, "rec_tds": 1 * factor,
                "targets": (type == "wr" ? 10 : 7) * factor, "yac": 37 * factor,
            ]
        default:
            return [
                "tackles": 8 * factor, "sacks": 0.5 * factor, "def_ints": 0,
                "passes_defended": 1 * factor, "tfl": 1 * factor, "qb_hits": 2 * factor,
                "forced_fumbles": 0,
            ]
        }
    }

    static func makeRecentForm(for player: Player, windowWeeks: Int) -> RecentForm {
        let current = player.playerId == 12001 ? 0.34 : player.playerId == 12002 ? 0.19 : 0.07
        let prior = current - (player.playerId == 12001 ? 0.18 : player.playerId == 12002 ? 0.04 : 0.01)
        let type = player.playerType ?? "qb"
        var metrics = gameMetrics(for: type, factor: 1.0).compactMapValues { $0 }
        var priorMetrics = metrics
        var delta = metrics.mapValues { _ in 0.0 }
        if type == "qb" {
            metrics["passing_epa"] = current
            priorMetrics["passing_epa"] = prior
            delta["passing_epa"] = current - prior
            metrics["ypa"] = 8.5 + current
            priorMetrics["ypa"] = 7.4 + prior
            delta["ypa"] = current - prior + 0.9
        }
        return RecentForm(
            fixturePlayerId: player.playerId,
            season: season,
            seasonPhase: .regular,
            playerType: type,
            windowWeeks: windowWeeks,
            asOf: asOf,
            startWeek: max(1, 3 - windowWeeks),
            endWeek: 2,
            team: player.team,
            games: min(windowWeeks, 2),
            plays: max(plays(for: type) * min(windowWeeks, 2), 1),
            touches: touches(for: type) * min(windowWeeks, 2),
            metrics: metrics,
            priorMetrics: priorMetrics,
            delta: delta
        )
    }

    static func makeDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value) ?? Date(timeIntervalSince1970: 1_0)
    }
}

private extension PlayerGameLog {
    init(
        fixturePlayerId: Int,
        season: Int,
        seasonPhase: SeasonPhase,
        gameDate: Date,
        playerType: String,
        team: String?,
        opponent: String?,
        plays: Int,
        touches: Int,
        metrics: [String: Double?]
    ) {
        self.playerId = fixturePlayerId
        self.season = season
        self.seasonPhase = seasonPhase
        self.gameDate = gameDate
        self.playerType = playerType
        self.team = team
        self.opponent = opponent
        self.plays = plays
        self.touches = touches
        self.metrics = metrics
    }
}

private extension RecentForm {
    init(
        fixturePlayerId: Int,
        season: Int,
        seasonPhase: SeasonPhase,
        playerType: String,
        windowWeeks: Int,
        asOf: Date?,
        startWeek: Int?,
        endWeek: Int?,
        team: String?,
        games: Int,
        plays: Int,
        touches: Int,
        metrics: [String: Double],
        priorMetrics: [String: Double],
        delta: [String: Double]
    ) {
        self.playerId = fixturePlayerId
        self.season = season
        self.seasonPhase = seasonPhase
        self.playerType = playerType
        self.windowWeeks = windowWeeks
        self.asOf = asOf
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.team = team
        self.games = games
        self.plays = plays
        self.touches = touches
        self.metrics = metrics
        self.priorMetrics = priorMetrics
        self.delta = delta
    }
}

/// In-memory cache used by the screenshot app hook. The production model loads
/// historical rows lazily from its bundled plist; this cache lets the same
/// lazy path exercise the fixture's prior season without touching disk.
struct ScreenshotFixtureCache: PlayerCaching {
    func loadPlayers() throws -> [Player] {
        ScreenshotFixtureAPI.fixturePlayers
    }

    func savePlayers(_ players: [Player]) throws {}
}

extension ScreenshotFixtureAPI {
    fileprivate static var fixturePlayers: [Player] {
        playersBySeason.values.flatMap { $0 }
    }
}
#endif
