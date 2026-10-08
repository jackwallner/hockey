import Foundation

/// Who a player is, what he costs, how much he plays and whether he is hurt,
/// from `public.player_profiles` (see `backend/ingest_enrichment.py`).
///
/// Every field is optional: a source that was late on the last run leaves its
/// columns null, and the screens that read them simply leave that line out.
struct PlayerProfile: Decodable, Hashable, Sendable {
    let playerId: Int
    let season: Int
    var jersey: Int?
    var birthDate: Date?
    var heightInches: Int?
    var weightPounds: Int?
    var college: String?
    var yearsExperience: Int?
    var draftYear: Int?
    var draftRound: Int?
    var draftPick: Int?
    var draftTeam: String?
    /// Average per year, in millions of dollars.
    var contractAPY: Double?
    /// APY as a share of the salary cap in the year it was signed, which is
    /// what makes a 2022 deal and a 2026 deal comparable.
    var contractCapShare: Double?
    var contractYears: Int?
    var contractYearSigned: Int?
    var offenseSnaps: Int?
    var defenseSnaps: Int?
    var offenseSnapShare: Double?
    var defenseSnapShare: Double?
    var injuryWeek: Int?
    var injuryStatus: String?
    var injury: String?
    var practiceStatus: String?

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case jersey
        case birthDate = "birth_date"
        case heightInches = "height_in"
        case weightPounds = "weight_lb"
        case college
        case yearsExperience = "years_exp"
        case draftYear = "draft_year"
        case draftRound = "draft_round"
        case draftPick = "draft_pick"
        case draftTeam = "draft_team"
        case contractAPY = "contract_apy"
        case contractCapShare = "contract_cap_pct"
        case contractYears = "contract_years"
        case contractYearSigned = "contract_year_signed"
        case offenseSnaps = "off_snaps"
        case defenseSnaps = "def_snaps"
        case offenseSnapShare = "off_snap_pct"
        case defenseSnapShare = "def_snap_pct"
        case injuryWeek = "injury_week"
        case injuryStatus = "injury_status"
        case injury
        case practiceStatus = "practice_status"
    }

    init(playerId: Int, season: Int) {
        self.playerId = playerId
        self.season = season
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        jersey = try c.decodeIfPresent(Int.self, forKey: .jersey)
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate).flatMap(Self.day)
        heightInches = try c.decodeIfPresent(Int.self, forKey: .heightInches)
        weightPounds = try c.decodeIfPresent(Int.self, forKey: .weightPounds)
        college = try c.decodeIfPresent(String.self, forKey: .college)
        yearsExperience = try c.decodeIfPresent(Int.self, forKey: .yearsExperience)
        draftYear = try c.decodeIfPresent(Int.self, forKey: .draftYear)
        draftRound = try c.decodeIfPresent(Int.self, forKey: .draftRound)
        draftPick = try c.decodeIfPresent(Int.self, forKey: .draftPick)
        draftTeam = try c.decodeIfPresent(String.self, forKey: .draftTeam)
        contractAPY = try c.decodeIfPresent(Double.self, forKey: .contractAPY)
        contractCapShare = try c.decodeIfPresent(Double.self, forKey: .contractCapShare)
        contractYears = try c.decodeIfPresent(Int.self, forKey: .contractYears)
        contractYearSigned = try c.decodeIfPresent(Int.self, forKey: .contractYearSigned)
        offenseSnaps = try c.decodeIfPresent(Int.self, forKey: .offenseSnaps)
        defenseSnaps = try c.decodeIfPresent(Int.self, forKey: .defenseSnaps)
        offenseSnapShare = try c.decodeIfPresent(Double.self, forKey: .offenseSnapShare)
        defenseSnapShare = try c.decodeIfPresent(Double.self, forKey: .defenseSnapShare)
        injuryWeek = try c.decodeIfPresent(Int.self, forKey: .injuryWeek)
        injuryStatus = try c.decodeIfPresent(String.self, forKey: .injuryStatus)
        injury = try c.decodeIfPresent(String.self, forKey: .injury)
        practiceStatus = try c.decodeIfPresent(String.self, forKey: .practiceStatus)
    }

    private static func day(_ raw: String) -> Date? {
        let bits = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: DateComponents(year: bits[0], month: bits[1], day: bits[2]))
    }

    func age(on date: Date = .now) -> Int? {
        guard let birthDate else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: date).year
    }

    /// "6-1, 196".
    var sizeLabel: String? {
        guard let heightInches, heightInches > 0 else { return nil }
        let height = "\(heightInches / 12)-\(heightInches % 12)"
        guard let weightPounds, weightPounds > 0 else { return height }
        return "\(height), \(weightPounds)"
    }

    /// "2023 R1 #20", or "Undrafted" for a player who came in without a pick.
    var draftLabel: String? {
        if let draftYear, let draftRound, let draftPick {
            return "\(draftYear) R\(draftRound) #\(draftPick)"
        }
        return yearsExperience != nil ? "Undrafted" : nil
    }

    /// "$42.2M/yr".
    var contractLabel: String? {
        guard let contractAPY, contractAPY > 0 else { return nil }
        return contractAPY >= 10
            ? String(format: "$%.1fM/yr", contractAPY)
            : String(format: "$%.2fM/yr", contractAPY)
    }

    /// Snap share for the side of the ball the player is ranked on.
    func snapShare(defense: Bool) -> Double? {
        defense ? defenseSnapShare : offenseSnapShare
    }

    func snaps(defense: Bool) -> Int? {
        defense ? defenseSnaps : offenseSnaps
    }
}

/// An entry on the weekly injury report, when it still describes a game that
/// has not been played.
struct InjuryReport: Hashable, Sendable {
    let status: String
    let injury: String?

    /// "Out", "Doubtful" and "Questionable" are what the badge shows; a
    /// practice-only line ("Limited") is not a game status and is left off.
    static func current(from profile: PlayerProfile?, upcomingWeek: Int?) -> InjuryReport? {
        guard let profile,
              let status = profile.injuryStatus?.trimmingCharacters(in: .whitespaces),
              !status.isEmpty,
              let week = profile.injuryWeek,
              let upcomingWeek,
              week >= upcomingWeek
        else { return nil }
        return InjuryReport(status: status, injury: profile.injury)
    }

    var isOut: Bool { status.lowercased() == "out" }

    /// "Q", "D", "Out".
    var shortStatus: String {
        switch status.lowercased() {
        case "questionable": return "Q"
        case "doubtful": return "D"
        default: return status
        }
    }
}

/// One club's power rating from `public.team_ratings`: points per game better
/// or worse than an average team on a neutral field. After Hawk Blogger's HB
/// Power Rankings; see `backend/team_ratings.py`.
struct TeamRating: Decodable, Hashable, Sendable, Identifiable {
    let season: Int
    let team: String
    let rank: Int
    let games: Int
    let throughWeek: Int
    let rating: Double
    let offense: Double
    let defense: Double
    let schedule: Double
    let wins: Int
    let losses: Int
    let ties: Int
    let pointsFor: Int
    let pointsAgainst: Int

    var id: String { team }

    enum CodingKeys: String, CodingKey {
        case season, team, rank, games, rating, offense, defense, schedule, wins, losses, ties
        case throughWeek = "through_week"
        case pointsFor = "points_for"
        case pointsAgainst = "points_against"
    }

    static func signed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0.0" }
        return String(format: "%+.1f", rounded)
    }
}

/// A projected margin for an unplayed game, from the two power ratings plus
/// home field.
struct GameProjection: Decodable, Hashable, Sendable {
    let gameId: String
    let homeMargin: Double
    let homeWinProbability: Double

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case homeMargin = "home_margin"
        case homeWinProbability = "home_win_prob"
    }

    /// "SEA by 4.5", "Toss-up" under a point.
    func label(home: String, away: String) -> String {
        let margin = abs(homeMargin)
        guard margin >= 1 else { return "Toss-up" }
        let favourite = homeMargin > 0 ? home : away
        return "\(displayTeamAbbr(favourite)) by \(String(format: "%.1f", (margin * 2).rounded() / 2))"
    }

    func winProbability(for team: String, home: String) -> Double {
        normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(home)
            ? homeWinProbability
            : 1 - homeWinProbability
    }
}

/// A club's line in the standings, from posted finals.
struct StandingsRow: Hashable, Sendable, Identifiable {
    let team: String
    var wins = 0
    var losses = 0
    var ties = 0
    var pointsFor = 0
    var pointsAgainst = 0
    /// "W2", "L1"; nil before a game.
    var streak: String?

    var id: String { team }
    var games: Int { wins + losses + ties }
    var differential: Int { pointsFor - pointsAgainst }
    var winPercentage: Double {
        games == 0 ? 0 : (Double(wins) + Double(ties) / 2) / Double(games)
    }

    var record: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    /// Regular-season finals only, oldest first so the streak reads off the end.
    static func build(from games: [Game], teams: [String]) -> [String: StandingsRow] {
        var rows = Dictionary(uniqueKeysWithValues: teams.map { ($0, StandingsRow(team: $0)) })
        let finals = games
            .filter { $0.seasonPhase == .regular && $0.isFinal }
            .sorted { ($0.kickoff ?? $0.gameDate) < ($1.kickoff ?? $1.gameDate) }
        var results: [String: [String]] = [:]
        for game in finals {
            for side in [game.homeTeam, game.awayTeam] {
                let team = normalizedTeamAbbreviation(side)
                guard var row = rows[team],
                      let result = game.result(for: side),
                      let mine = game.score(of: side),
                      let theirs = game.score(of: game.opponent(of: side)) else { continue }
                switch result {
                case "W": row.wins += 1
                case "L": row.losses += 1
                default: row.ties += 1
                }
                row.pointsFor += mine
                row.pointsAgainst += theirs
                rows[team] = row
                results[team, default: []].append(result)
            }
        }
        for (team, list) in results {
            guard let last = list.last else { continue }
            let run = list.reversed().prefix { $0 == last }.count
            rows[team]?.streak = "\(last)\(run)"
        }
        return rows
    }

    /// Win percentage, then point differential, then name: not the NFL's full
    /// tiebreaker ladder, and the Standings screen says so.
    static func ordered(_ rows: [StandingsRow]) -> [StandingsRow] {
        rows.sorted {
            if $0.winPercentage != $1.winPercentage { return $0.winPercentage > $1.winPercentage }
            if $0.differential != $1.differential { return $0.differential > $1.differential }
            return $0.team < $1.team
        }
    }
}

/// What a player produces set against what he is paid, in the app's percentile
/// idiom. Inspired by Hawk Blogger's Value Over Expected, with the contract
/// rather than the draft slot as the expectation: the version that moves every
/// week of the season.
///
/// Both halves are percentile ranks inside one pool: this season's qualified
/// players at the position who have an active deal. Pay ranks cap share at
/// signing; production ranks the average of the player's ranked, qualified
/// percentiles in his position's category. Value is production minus pay.
struct ContractValue: Hashable, Sendable {
    let payPercentile: Int
    let productionPercentile: Int
    let poolSize: Int

    var score: Int { productionPercentile - payPercentile }

    enum Verdict: String, Sendable {
        case bargain = "Bargain"
        case outplaying = "Outplaying his deal"
        case fair = "Paid about right"
        case under = "Below his deal"
        case overpaid = "Overpaid so far"
    }

    var verdict: Verdict {
        switch score {
        case 25...: return .bargain
        case 10..<25: return .outplaying
        case -9..<10: return .fair
        case -24 ..< -9: return .under
        default: return .overpaid
        }
    }

    var scoreLabel: String { score > 0 ? "+\(score)" : "\(score)" }

    /// Offense only for now: until Pro-Football-Reference's advanced defensive
    /// table publishes, a defender's production percentile is counting stats.
    static let positions: Set<PlayerPositionGroup> = [.qb, .rb, .wr, .te]

    /// Values for every eligible player in `players` (one season and phase).
    static func compute(
        players: [Player],
        profiles: [Int: PlayerProfile],
        isQualified: (Player) -> Bool
    ) -> [Int: ContractValue] {
        var out: [Int: ContractValue] = [:]
        let groups = Dictionary(grouping: players.filter { positions.contains($0.positionGroup) }, by: \.positionGroup)
        for (_, group) in groups {
            let pool: [(id: Int, pay: Double, production: Double)] = group.compactMap { player in
                guard isQualified(player),
                      let share = profiles[player.playerId]?.contractCapShare, share > 0,
                      let production = production(for: player) else { return nil }
                return (player.playerId, share, production)
            }
            guard pool.count >= 5 else { continue }
            let pays = pool.map(\.pay)
            let productions = pool.map(\.production)
            for entry in pool {
                out[entry.id] = ContractValue(
                    payPercentile: midpointPercentile(entry.pay, in: pays),
                    productionPercentile: midpointPercentile(entry.production, in: productions),
                    poolSize: pool.count
                )
            }
        }
        return out
    }

    /// Mean of the player's ranked, qualified percentiles in his primary
    /// category, or nil when there are none to average.
    static func production(for player: Player) -> Double? {
        let category = player.positionGroup.primaryCategory
        let ranked = player.metrics.filter {
            $0.category == category && $0.qualified != false && !$0.isUnranked
        }
        guard !ranked.isEmpty else { return nil }
        return Double(ranked.map(\.percentile).reduce(0, +)) / Double(ranked.count)
    }

    static func midpointPercentile(_ value: Double, in values: [Double]) -> Int {
        guard !values.isEmpty else { return 50 }
        let below = values.filter { $0 < value }.count
        let equal = values.filter { $0 == value }.count
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        return max(1, min(99, Int(raw.rounded())))
    }
}
