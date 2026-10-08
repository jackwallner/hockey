#if DEBUG
import Foundation

/// Deterministic, fictional NHL rows used only by the release screenshot
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
        UserDefaults.standard.set([12001, 12008, 12013], forKey: "favorites.playerIds")
        UserDefaults.standard.set("SEA", forKey: "favoriteTeam")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set("standard", forKey: "stats.board")
        UserDefaults.standard.removeObject(forKey: "statcast.dataFreshness")
        UserDefaults.standard.removeObject(forKey: "statcast.displayedDataRevision")
    }

    private static let season = StatScoutSeason.current
    private static let priorSeason = season - 1
    // Oct 21 is a coherent fictional capture date for the 2026-27 season, two
    // weeks after opening night. It keeps the current-season windows honest
    // and repeatable.
    private static let asOf = makeDate("2026-10-21T20:00:00Z")
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
        return DataCoverage(asOf: Self.asOf, week: 3, phase: .regular, gamesIncluded: 112)
    }

    func fetchDataFreshness(season: Int) async throws -> DataFreshness? {
        guard season == Self.season else { return nil }
        return DataFreshness(
            status: .ready,
            revision: "screenshot-fixture-v13",
            sourcePublishedAt: Self.asOf,
            publishedAt: Self.asOf,
            checkedAt: Self.asOf,
            coverage: DataCoverage(asOf: Self.asOf, week: 3, phase: .regular, gamesIncluded: 112),
            message: "Fixture data through Oct 21",
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
        /// ixG for a skater (after eight games), GSAx for a goalie.
        let headline: Double
    }

    static let seeds: [PlayerSeed] = [
        .init(id: 12001, name: "Callum Therrien", team: "SEA", position: "C", type: "f", percentile: 96, headline: 4.9),
        .init(id: 12002, name: "Rasmus Holloway", team: "EDM", position: "L", type: "f", percentile: 92, headline: 3.8),
        .init(id: 12003, name: "Jonas Whitlock", team: "TOR", position: "R", type: "f", percentile: 88, headline: 3.4),
        .init(id: 12004, name: "Tobias Marchetti", team: "COL", position: "C", type: "f", percentile: 85, headline: 3.1),
        .init(id: 12005, name: "Anders Pelletier", team: "BOS", position: "L", type: "f", percentile: 80, headline: 2.7),
        .init(id: 12006, name: "Dmitri Vasko", team: "DAL", position: "C", type: "f", percentile: 74, headline: 2.2),
        .init(id: 12007, name: "Owen Castellan", team: "SEA", position: "R", type: "f", percentile: 90, headline: 3.5),
        .init(id: 12008, name: "Mikael Sandvik", team: "SEA", position: "D", type: "d", percentile: 94, headline: 57.4),
        .init(id: 12009, name: "Lucas Brannigan", team: "NJD", position: "D", type: "d", percentile: 89, headline: 55.8),
        .init(id: 12010, name: "Pavel Drozdov", team: "CAR", position: "D", type: "d", percentile: 84, headline: 54.6),
        .init(id: 12011, name: "Hunter Leclair", team: "VGK", position: "D", type: "d", percentile: 79, headline: 53.1),
        .init(id: 12012, name: "Gustav Nyqvist", team: "MIN", position: "D", type: "d", percentile: 73, headline: 51.9),
        .init(id: 12013, name: "Henrik Dalgaard", team: "SEA", position: "G", type: "g", percentile: 93, headline: 3.4),
        .init(id: 12014, name: "Ilya Morozov", team: "FLA", position: "G", type: "g", percentile: 88, headline: 2.6),
        .init(id: 12015, name: "Samuel Whitaker", team: "WPG", position: "G", type: "g", percentile: 82, headline: 1.7),
        .init(id: 12016, name: "Teodor Lindahl", team: "NYR", position: "G", type: "g", percentile: 76, headline: 0.9),
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
                handedness: seed.position == "G" ? "L" : "R",
                updatedAt: asOf,
                season: season,
                seasonPhase: .regular,
                playerType: seed.type,
                source: "screenshot-fixture",
                metrics: metrics(for: seed, scale: scale, volume: prior ? 9.5 : 1, percentile: percentile),
                standardStats: standardStats(for: seed, scale: scale, volume: prior ? 9.5 : 1),
                games: gameTrends(for: seed, prior: prior)
            )
        }
    }

    /// One metric per registry label, values scaled by how good the player is
    /// (`scale` shrinks a rate for the prior season, `volume` grows a count).
    static func metrics(
        for seed: PlayerSeed,
        scale: Double,
        volume: Double,
        percentile: Int
    ) -> [Metric] {
        let rank = 0.72 + Double(percentile) / 100 * 0.28
        func rate(_ label: String, _ base: Double, _ offset: Int, _ category: MetricCategory) -> Metric {
            metric(label, base * rank * scale, max(50, percentile - offset), category)
        }
        func count(_ label: String, _ base: Double, _ offset: Int, _ category: MetricCategory) -> Metric {
            metric(label, base * rank * scale * volume, max(50, percentile - offset), category)
        }
        switch seed.type {
        case "f":
            return [
                rate("P/60", 3.6, 0, .scoring), count("Primary P", 8, 2, .scoring),
                count("G", 5, 3, .scoring), count("A", 6, 4, .scoring), count("P", 11, 1, .scoring),
                count("SOG", 28, 6, .scoring), rate("Sh%", 16, 8, .scoring),
                metric("ixG", seed.headline * scale * volume, percentile, .shotQuality),
                metric("GAx", 1.2 * scale * volume, max(50, percentile - 9), .shotQuality),
                rate("ixG/60", 1.3, 2, .shotQuality), rate("Shots/60", 12.4, 5, .shotQuality),
                count("HD Shots", 11, 5, .shotQuality),
                rate("xGF%", 56, 4, .playDriving), rate("CF%", 54, 6, .playDriving),
                rate("xGF/60", 3.1, 7, .playDriving), count("Hits", 12, 25, .playDriving),
            ]
        case "d":
            return [
                metric("xGF%", seed.headline * scale, percentile, .playDriving),
                metric("Rel xGF%", 4.6 * scale, max(50, percentile - 3), .playDriving),
                metric("xGA/60", 2.1 / scale, max(50, percentile - 5), .playDriving),
                count("Blocks", 14, 8, .playDriving), count("Hits", 11, 20, .playDriving),
                rate("P/60", 1.9, 6, .scoring), count("P", 6, 5, .scoring), count("A", 5, 6, .scoring),
                metric("ixG", 1.4 * scale * volume, max(50, percentile - 10), .shotQuality),
            ]
        default:
            return [
                metric("GSAx", seed.headline * scale * volume, percentile, .goaltending),
                metric("GSAx/60", 0.38 * scale, max(50, percentile - 2), .goaltending),
                metric("SV%", 0.925 * (0.97 + 0.03 * scale), max(50, percentile - 1), .goaltending),
                metric("GAA", 2.2 / scale, max(50, percentile - 3), .goaltending),
                metric("HD SV%", 0.858 * (0.97 + 0.03 * scale), max(50, percentile - 6), .goaltending),
                metric("xGA/60", 2.5, max(50, percentile - 10), .goaltending),
                metric("Rebound%", 6.8 / scale, max(50, percentile - 7), .goaltending),
                metric("Saves", 150 * volume, max(50, percentile - 12), .goaltending),
                metric("W", 4 * volume, max(50, percentile - 9), .goaltending),
            ]
        }
    }

    static func metric(
        _ label: String,
        _ value: Double,
        _ percentile: Int,
        _ category: MetricCategory
    ) -> Metric {
        Metric(
            id: "\(category.rawValue)-\(label)",
            label: label,
            value: formattedMetricValue(label: label, value: value),
            percentile: percentile,
            category: category,
            qualified: true
        )
    }

    static func formattedMetricValue(label: String, value: Double) -> String {
        switch label {
        case "Sh%", "xGF%", "CF%", "HDCF%", "GF%", "Rebound%":
            return String(format: "%.1f%%", value)
        case "GAx", "GSAx", "Rel xGF%", "Rel CF%":
            return String(format: "%+.1f", value)
        case "SV%", "HD SV%":
            return RecentMetricKey.savePercentage(value)
        case "P/60", "ixG/60", "xGF/60", "xGA/60", "GSAx/60", "GAA", "Game Score":
            return String(format: "%.2f", value)
        case "ixG", "Shots/60":
            return String(format: "%.1f", value)
        default:
            return Int(value.rounded()).formatted(.number.grouping(.automatic))
        }
    }

    static func standardStats(for seed: PlayerSeed, scale: Double, volume: Double) -> [StandardStat] {
        func stat(_ label: String, _ value: String) -> StandardStat {
            StandardStat(id: "std-\(label)", label: label, value: value)
        }
        let rank = 0.72 + (Double(seed.percentile) / 100.0 * 0.28)
        func total(_ base: Double) -> String {
            "\(Int((base * rank * scale * volume).rounded()))"
        }
        let games = volume > 1 ? 76 : 8
        if seed.type == "g" {
            let started = volume > 1 ? 58 : 6
            let shots = Int((29 * Double(started)).rounded())
            let saves = Int((Double(shots) * (0.905 + 0.03 * rank * scale)).rounded())
            let wins = Int((Double(started) * 0.45 * rank * scale).rounded())
            return [
                stat("GP", "\(started)"), stat("GS", "\(started)"),
                stat("W", "\(wins)"), stat("L", "\(max(0, started - wins - 2))"), stat("OT", "2"),
                stat("GAA", String(format: "%.2f", Double(shots - saves) / (Double(started) * 60) * 60)),
                stat("SV%", RecentMetricKey.savePercentage(Double(saves) / Double(shots))),
                stat("SO", "\(volume > 1 ? 4 : 1)"),
                stat("SA", "\(shots)"), stat("SV", "\(saves)"),
            ]
        }
        let goals = Int((5 * rank * scale * volume).rounded())
        let assists = Int((6 * rank * scale * volume).rounded())
        let shots = Int((27 * rank * scale * volume).rounded())
        var stats = [
            stat("GP", "\(games)"), stat("G", "\(goals)"), stat("A", "\(assists)"),
            stat("P", "\(goals + assists)"), stat("+/-", "+\(Int((4 * rank * scale * volume).rounded()))"),
            stat("PIM", total(4)), stat("PPG", total(1.5)), stat("PPP", total(3.5)),
            stat("SHG", "0"), stat("GWG", total(1)), stat("SOG", "\(shots)"),
            stat("Sh%", String(format: "%.1f%%", shots > 0 ? Double(goals) / Double(shots) * 100 : 0)),
            stat("TOI/GP", seed.type == "d" ? "23:48" : "18:52"),
            stat("Hits", total(12)), stat("Blk", total(seed.type == "d" ? 14 : 5)),
        ]
        if seed.position == "C" { stats.append(stat("FO%", "52.4%")) }
        return stats
    }

    static func gameTrends(for seed: PlayerSeed, prior: Bool) -> [GameTrend] {
        let opponents = ["VAN", "CGY", "LAK", "SJS", "ANA"]
        return (0..<5).map { index in
            GameTrend(
                id: "\(seed.id)-\(prior ? "prior" : "current")-\(index)",
                date: Calendar.current.date(byAdding: .day, value: -(index * 2), to: asOf) ?? asOf,
                opponent: opponents[index],
                summary: index == 0 ? "Strong finish" : "Solid night",
                percentileDelta: (prior ? 1 : 2) * (5 - index),
                keyMetric: seed.type == "g" ? "GSAx" : "ixG"
            )
        }
    }

    /// Eight games over the two weeks before the capture date.
    private static let gameDayOffsets = [12, 10, 9, 7, 5, 3, 2, 0]

    static func makeGameLogs(for player: Player) -> [PlayerGameLog] {
        let type = player.playerType ?? "f"
        let opponents = ["VAN", "CGY", "LAK", "SJS", "ANA", "VGK", "UTA", "STL"]
        return gameDayOffsets.enumerated().map { index, offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: asOf) ?? asOf
            let factor = 1.0 + (Double(index) * 0.04)
            return PlayerGameLog(
                fixturePlayerId: player.playerId,
                season: season,
                seasonPhase: .regular,
                gameDate: date,
                playerType: type,
                team: player.team,
                opponent: opponents[index],
                plays: plays(for: type),
                touches: touches(for: type),
                metrics: gameMetrics(for: type, factor: factor)
            )
        }
    }

    /// Ice time in whole minutes.
    static func plays(for type: String) -> Int {
        switch type {
        case "f": return 19
        case "d": return 24
        default: return 60
        }
    }

    /// Shot attempts for a skater, shots against for a goalie.
    static func touches(for type: String) -> Int {
        switch type {
        case "f": return 6
        case "d": return 4
        default: return 28
        }
    }

    static func gameMetrics(for type: String, factor: Double) -> [String: Double?] {
        switch type {
        case "g":
            return [
                "shots_against": 28 * factor, "saves": 26 * factor, "goals_against": 2,
                "xga": 2.4 * factor, "hd_shots_against": 8 * factor, "hd_goals_against": 1,
                "toi_seconds": 3_600, "decision_win": 1, "shutout": 0, "started": 1,
            ]
        default:
            let toi = type == "d" ? 1_440.0 : 1_140.0
            return [
                "goals": 0.6 * factor, "assists": 0.7 * factor, "primary_assists": 0.4 * factor,
                "points": 1.3 * factor, "shots_on_goal": 3.4 * factor, "shot_attempts": 6 * factor,
                "ixg": 0.62 * factor, "hd_shots": 1.4 * factor, "hits": 1.6 * factor,
                "blocks": 0.9 * factor, "takeaways": 0.8 * factor, "giveaways": 0.7,
                "pim": 0.5, "plus_minus": 0.4 * factor, "pp_goals": 0.2 * factor,
                "faceoffs_won": 7, "faceoffs_lost": 6, "toi_seconds": toi,
            ]
        }
    }

    static func makeRecentForm(for player: Player, windowWeeks: Int) -> RecentForm {
        let type = player.playerType ?? "f"
        let seed = Double(player.playerId % 7) / 10
        let games = type == "g" ? max(2, windowWeeks) : min(windowWeeks * 3, 8)
        let metrics: [String: Double]
        let delta: [String: Double]
        if type == "g" {
            metrics = ["sv_pct": 0.931 - seed / 20, "gaa": 2.1 + seed, "gsax": 3.2 - seed * 2,
                       "gsax_per_60": 0.41 - seed / 5, "hd_sv_pct": 0.861 - seed / 20,
                       "shots_against_per_60": 27.5, "saves": 140, "goals_against": 10,
                       "games": Double(games), "wins": Double(games) - 1]
            delta = ["sv_pct": 0.018 - seed / 25, "gaa": -0.4 + seed / 2, "gsax": 2.1 - seed,
                     "gsax_per_60": 0.22 - seed / 6, "hd_sv_pct": 0.02 - seed / 30,
                     "shots_against_per_60": 1.1]
        } else {
            metrics = ["points_per_60": 3.8 - seed, "goals_per_60": 1.6 - seed / 2, "ixg_per_60": 1.3 - seed / 4,
                       "gax": 1.4 - seed, "shooting_pct": 17 - seed * 6, "shots_per_60": 12.8,
                       "hd_shots_per_60": 4.1, "blocks_per_60": 1.0, "hits_per_60": 3.2,
                       "goals": 5, "assists": 6, "points": 11, "shots_on_goal": 28,
                       "ixg": 3.9 - seed, "games": Double(games)]
            delta = ["points_per_60": 1.4 - seed, "goals_per_60": 0.7 - seed / 3, "ixg_per_60": 0.3 - seed / 8,
                     "gax": 0.9 - seed / 2, "shooting_pct": 4.2 - seed * 3, "shots_per_60": 1.1,
                     "hd_shots_per_60": 0.6, "blocks_per_60": 0.1, "hits_per_60": 0.2]
        }
        let priorMetrics = metrics.merging(delta) { now, change in now - change }
        return RecentForm(
            fixturePlayerId: player.playerId,
            season: season,
            seasonPhase: .regular,
            playerType: type,
            windowWeeks: windowWeeks,
            asOf: asOf,
            startWeek: 1,
            endWeek: 3,
            team: player.team,
            games: games,
            plays: plays(for: type) * games,
            touches: touches(for: type) * games,
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
