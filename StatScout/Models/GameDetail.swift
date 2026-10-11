import Foundation

/// A number with its percentile among this season's team games or qualifying
/// player games. Counts are stored plain and decode with no percentile.
struct RatedValue: Decodable, Hashable, Sendable {
    let value: Double
    let percentile: Int?

    init(value: Double, percentile: Int? = nil) {
        self.value = value
        self.percentile = percentile
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case percentile = "pct"
    }

    init(from decoder: Decoder) throws {
        if let number = try? decoder.singleValueContainer().decode(Double.self) {
            value = number
            percentile = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(Double.self, forKey: .value)
        percentile = try c.decodeIfPresent(Int.self, forKey: .percentile)
    }
}

/// Each side's expected goals for one final, the number the Games list shows
/// under a score.
struct GameXG: Hashable, Sendable {
    let away: Double
    let home: Double

    /// "xG 2.9-1.7", away first like the rows above it.
    var label: String {
        "xG " + String(format: "%.1f-%.1f", away, home)
    }
}

/// Shot-level breakdown for one game, from `public.game_details`: expected
/// goals by side, every skater's and goalie's line, the cumulative xG race,
/// and the chances that decided it.
struct GameDetail: Decodable, Sendable {
    struct PlayerLine: Decodable, Identifiable, Hashable, Sendable {
        enum Role: String, Decodable, Sendable {
            case skater, goalie
        }

        let role: Role
        let playerId: Int
        let name: String?
        let team: String
        let position: String?
        /// Seconds on ice.
        let toi: Int?
        let goals: Int?
        let assists: Int?
        let points: Int?
        let sog: Int?
        let shotAttempts: Int?
        let hdShots: Int?
        let ixg: RatedValue?
        let gax: RatedValue?
        let ixgPer60: RatedValue?
        let shotsAgainst: Int?
        let saves: Int?
        let goalsAgainst: Int?
        let xga: RatedValue?
        let gsax: RatedValue?
        let svPct: RatedValue?

        var id: String { "\(role.rawValue)-\(playerId)" }

        /// "18:42".
        var toiLabel: String? {
            guard let toi else { return nil }
            return String(format: "%d:%02d", toi / 60, toi % 60)
        }

        enum CodingKeys: String, CodingKey {
            case role
            case playerId = "player_id"
            case name, team, position, toi, goals, assists, points, sog
            case shotAttempts = "shot_attempts"
            case hdShots = "hd_shots"
            case ixg, gax
            case ixgPer60 = "ixg_per_60"
            case shotsAgainst = "shots_against"
            case saves
            case goalsAgainst = "goals_against"
            case xga, gsax
            case svPct = "sv_pct"
        }
    }

    struct BigPlay: Decodable, Identifiable, Hashable, Sendable {
        let period: Int
        let clock: String
        let team: String
        let description: String
        let xg: Double?
        /// GOAL, SAVE, MISS or BLOCK.
        let result: String
        let playerId: Int?
        let shooter: String?
        /// Goals only: assisting players' full names, primary first.
        let assists: [String]?
        /// Goals only: "PP", "SH" or "EN"; nil at even strength.
        let strength: String?
        /// Goals only: the score after it, `[away, home]`.
        let score: [Int]?
        /// Goals only: the scorer's season goal count, the "(5)" of a summary.
        let goalNumber: Int?

        var id: String { "\(period)-\(clock)-\(team)-\(result)-\(playerId ?? 0)" }
        var isGoal: Bool { result.uppercased() == "GOAL" }

        /// "Saved", "Missed", "Blocked" for a chance that did not score.
        var resultLabel: String? {
            switch result.uppercased() {
            case "SAVE": return "Saved"
            case "MISS": return "Missed"
            case "BLOCK": return "Blocked"
            default: return nil
            }
        }

        /// "Draisaitl, Nugent-Hopkins", "Unassisted", or nil before the feed
        /// carried assists.
        var assistLine: String? {
            guard isGoal, let assists else { return nil }
            guard !assists.isEmpty else { return "Unassisted" }
            return assists.map(Self.lastName).joined(separator: ", ")
        }

        /// "Connor McDavid" -> "McDavid", "James van Riemsdyk" -> "van Riemsdyk".
        static func lastName(_ name: String) -> String {
            let parts = name.split(separator: " ", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : name
        }

        enum CodingKeys: String, CodingKey {
            case period, clock, team, description, xg, result, shooter, assists, strength, score
            case playerId = "player_id"
            case goalNumber = "goal_number"
        }
    }

    /// One point on the cumulative expected-goals race.
    struct XGRacePoint: Hashable, Sendable, Identifiable {
        /// Game seconds elapsed.
        let elapsed: Double
        let awayXG: Double
        let homeXG: Double
        let awayGoals: Int
        let homeGoals: Int
        var id: Double { elapsed }
    }

    let gameId: String
    let awayTeam: String
    let homeTeam: String
    let away: [String: RatedValue]
    let home: [String: RatedValue]
    let players: [PlayerLine]
    let xgRace: [XGRacePoint]
    let bigPlays: [BigPlay]

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case teamStats = "team_stats"
        case players
        case xgRace = "win_probability"
        case bigPlays = "big_plays"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameId = try c.decode(String.self, forKey: .gameId)
        awayTeam = try c.decode(String.self, forKey: .awayTeam)
        homeTeam = try c.decode(String.self, forKey: .homeTeam)
        let sides = try c.decodeIfPresent(LossyDictionarySides.self, forKey: .teamStats)
        away = sides?.away ?? [:]
        home = sides?.home ?? [:]
        players = (try? c.decodeIfPresent([Lossy<PlayerLine>].self, forKey: .players))?.compactMap(\.value) ?? []
        let raw = (try? c.decodeIfPresent([[Double]].self, forKey: .xgRace)) ?? []
        xgRace = raw.compactMap { row in
            guard row.count >= 5 else { return nil }
            return XGRacePoint(
                elapsed: row[0], awayXG: row[1], homeXG: row[2],
                awayGoals: Int(row[3].rounded()), homeGoals: Int(row[4].rounded())
            )
        }
        bigPlays = (try? c.decodeIfPresent([Lossy<BigPlay>].self, forKey: .bigPlays))?.compactMap(\.value) ?? []
    }

    func stats(for team: String) -> [String: RatedValue] {
        normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(homeTeam) ? home : away
    }

    /// Skaters by individual expected goals, goalies by goals saved above expected.
    func players(_ role: PlayerLine.Role) -> [PlayerLine] {
        switch role {
        case .skater:
            return players.filter { $0.role == .skater }
                .sorted { ($0.ixg?.value ?? -.infinity) > ($1.ixg?.value ?? -.infinity) }
        case .goalie:
            return players.filter { $0.role == .goalie }
                .sorted { ($0.gsax?.value ?? -.infinity) > ($1.gsax?.value ?? -.infinity) }
        }
    }

    func players(_ role: PlayerLine.Role, team: String) -> [PlayerLine] {
        players(role).filter { normalizedTeamAbbreviation($0.team) == normalizedTeamAbbreviation(team) }
    }
}

/// Team stats mix rated metrics with plain counts and the occasional null.
/// Decode each side key by key so one odd value can't drop the whole side.
private struct LossyDictionarySides: Decodable {
    let away: [String: RatedValue]
    let home: [String: RatedValue]

    private enum CodingKeys: String, CodingKey { case away, home }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        away = Self.side(c, .away)
        home = Self.side(c, .home)
    }

    private static func side(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: RatedValue] {
        guard let raw = try? c.decode([String: Lossy<RatedValue>].self, forKey: key) else { return [:] }
        return raw.compactMapValues(\.value)
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
