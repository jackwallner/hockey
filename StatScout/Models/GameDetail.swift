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

/// Play-by-play breakdown for one game, from `public.game_details`.
struct GameDetail: Decodable, Sendable {
    struct PlayerLine: Decodable, Identifiable, Hashable, Sendable {
        enum Role: String, Decodable, Sendable {
            case passer, rusher, receiver
        }

        let role: Role
        let playerId: Int
        let name: String?
        let team: String
        let dropbacks: Int?
        let carries: Int?
        let targets: Int?
        let epa: Double?
        let epaPerDropback: RatedValue?
        let epaPerCarry: RatedValue?
        let epaPerTarget: RatedValue?
        let successRate: RatedValue?
        let cpoe: RatedValue?
        let adot: RatedValue?

        var id: String { "\(role.rawValue)-\(playerId)" }

        enum CodingKeys: String, CodingKey {
            case role
            case playerId = "player_id"
            case name, team, dropbacks, carries, targets, epa
            case epaPerDropback = "epa_per_dropback"
            case epaPerCarry = "epa_per_carry"
            case epaPerTarget = "epa_per_target"
            case successRate = "success_rate"
            case cpoe, adot
        }
    }

    struct BigPlay: Decodable, Identifiable, Hashable, Sendable {
        let qtr: Int
        let clock: String
        let team: String
        let description: String
        let epa: Double?
        let homeWPA: Double

        var id: String { "\(qtr)-\(clock)-\(description.prefix(24))" }

        enum CodingKeys: String, CodingKey {
            case qtr, clock, team, description, epa
            case homeWPA = "home_wpa"
        }
    }

    struct WinProbabilityPoint: Hashable, Sendable, Identifiable {
        let elapsed: Double
        let homeWinProbability: Double
        var id: Double { elapsed }
    }

    let gameId: String
    let awayTeam: String
    let homeTeam: String
    let away: [String: RatedValue]
    let home: [String: RatedValue]
    let players: [PlayerLine]
    let winProbability: [WinProbabilityPoint]
    let bigPlays: [BigPlay]

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case teamStats = "team_stats"
        case players
        case winProbability = "win_probability"
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
        let raw = (try? c.decodeIfPresent([[Double]].self, forKey: .winProbability)) ?? []
        winProbability = raw.compactMap { pair in
            pair.count == 2 ? WinProbabilityPoint(elapsed: pair[0], homeWinProbability: pair[1]) : nil
        }
        bigPlays = (try? c.decodeIfPresent([Lossy<BigPlay>].self, forKey: .bigPlays))?.compactMap(\.value) ?? []
    }

    func stats(for team: String) -> [String: RatedValue] {
        normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(homeTeam) ? home : away
    }

    func players(_ role: PlayerLine.Role) -> [PlayerLine] {
        players.filter { $0.role == role }.sorted { ($0.epa ?? -.infinity) > ($1.epa ?? -.infinity) }
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
