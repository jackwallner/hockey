import Foundation

/// Who a player is and how much he plays, from `public.player_profiles` (see
/// `backend/ingest_enrichment.py`).
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
    /// "Richmond Hill, ON, CAN".
    var birthplace: String?
    var yearsExperience: Int?
    /// The league's Calder eligibility; nil before the feed carried it.
    var isRookie: Bool?
    var draftYear: Int?
    var draftRound: Int?
    var draftPick: Int?
    var draftTeam: String?
    /// Season ice time in seconds, all situations.
    var toiSeconds: Int?
    /// Ice time per game in seconds.
    var toiPerGame: Int?
    var powerPlayToiSeconds: Int?
    var penaltyKillToiSeconds: Int?
    /// Share of the club's skater minutes this player was on the ice for.
    var toiShare: Double?

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case jersey
        case birthDate = "birth_date"
        case heightInches = "height_in"
        case weightPounds = "weight_lb"
        case birthplace
        case yearsExperience = "years_exp"
        case isRookie = "is_rookie"
        case draftYear = "draft_year"
        case draftRound = "draft_round"
        case draftPick = "draft_pick"
        case draftTeam = "draft_team"
        case toiSeconds = "toi_seconds"
        case toiPerGame = "toi_per_gp"
        case powerPlayToiSeconds = "pp_toi_seconds"
        case penaltyKillToiSeconds = "pk_toi_seconds"
        case toiShare = "toi_share"
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
        birthplace = try c.decodeIfPresent(String.self, forKey: .birthplace)
        yearsExperience = try c.decodeIfPresent(Int.self, forKey: .yearsExperience)
        isRookie = try c.decodeIfPresent(Bool.self, forKey: .isRookie)
        draftYear = try c.decodeIfPresent(Int.self, forKey: .draftYear)
        draftRound = try c.decodeIfPresent(Int.self, forKey: .draftRound)
        draftPick = try c.decodeIfPresent(Int.self, forKey: .draftPick)
        draftTeam = try c.decodeIfPresent(String.self, forKey: .draftTeam)
        // Seconds arrive as numerics ("toi_per_gp": 1437.2); decoding them as
        // Int threw and dropped every profile with a fractional average.
        toiSeconds = Self.seconds(c, .toiSeconds)
        toiPerGame = Self.seconds(c, .toiPerGame)
        powerPlayToiSeconds = Self.seconds(c, .powerPlayToiSeconds)
        penaltyKillToiSeconds = Self.seconds(c, .penaltyKillToiSeconds)
        toiShare = try c.decodeIfPresent(Double.self, forKey: .toiShare)
    }

    private static func seconds(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        guard let value = try? c.decodeIfPresent(Double.self, forKey: key), value.isFinite else { return nil }
        return Int(value.rounded())
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

    /// `6'1", 196 lb`.
    var sizeLabel: String? {
        guard let heightInches, heightInches > 0 else { return nil }
        let height = "\(heightInches / 12)'\(heightInches % 12)\""
        guard let weightPounds, weightPounds > 0 else { return height }
        return "\(height), \(weightPounds) lb"
    }

    /// "2015 Rd 1, #1 overall", or "Undrafted" for a player who came in
    /// without a pick. The feed's pick is the overall number.
    var draftLabel: String? {
        if let draftYear, let draftRound, let draftPick {
            return "\(draftYear) Rd \(draftRound), #\(draftPick) overall"
        }
        return yearsExperience != nil ? "Undrafted" : nil
    }

    /// "21:14 TOI/GP".
    var toiPerGameLabel: String? {
        guard let toiPerGame, toiPerGame > 0 else { return nil }
        return String(format: "%d:%02d", toiPerGame / 60, toiPerGame % 60)
    }

    /// "3:12 PP · 1:48 PK" per game, for the deployment line.
    func specialTeamsLabel(games: Int) -> String? {
        guard games > 0 else { return nil }
        func clock(_ seconds: Int?) -> String? {
            guard let seconds, seconds > 0 else { return nil }
            let per = seconds / games
            return String(format: "%d:%02d", per / 60, per % 60)
        }
        let parts = [clock(powerPlayToiSeconds).map { "\($0) PP" }, clock(penaltyKillToiSeconds).map { "\($0) PK" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One club's power rating from `public.team_ratings`: goals per game better
/// or worse than an average team on neutral ice. Expected goals and actual
/// goals, schedule-adjusted; see `backend/team_ratings.py`. The `ties`
/// column holds overtime and shootout losses, `points_for` goals for.
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

    /// "+0.58", "-0.12": ratings live within about half a goal of zero, so
    /// one decimal would flatten most of the league to "+0.1".
    static func signed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == 0 { return "0.00" }
        return String(format: "%+.2f", rounded)
    }
}

/// A projected margin for an unplayed game, from the two power ratings plus
/// home ice.
struct GameProjection: Decodable, Hashable, Sendable {
    let gameId: String
    let homeMargin: Double
    let homeWinProbability: Double

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case homeMargin = "home_margin"
        case homeWinProbability = "home_win_prob"
    }

    /// "EDM 62%", the favourite's chance to win, or "Toss-up" when it rounds
    /// to 50%. Hockey reads a matchup as a win chance, not a point spread:
    /// margins here are fractions of a goal, and most games sit near even, so
    /// 52% still says who is favoured.
    func label(home: String, away: String) -> String {
        let favouriteChance = max(homeWinProbability, 1 - homeWinProbability)
        guard favouriteChance >= 0.505 else { return "Toss-up" }
        let favourite = homeWinProbability >= 0.5 ? home : away
        return "\(displayTeamAbbr(favourite)) \(Int((favouriteChance * 100).rounded()))%"
    }

    func winProbability(for team: String, home: String) -> Double {
        normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(home)
            ? homeWinProbability
            : 1 - homeWinProbability
    }
}

/// A club's line in the standings, from posted finals. `ties` holds overtime
/// and shootout losses (a point each), `pointsFor` and `pointsAgainst` are
/// goals; the names stay so the team cards and tests read the same fields.
struct StandingsRow: Hashable, Sendable, Identifiable {
    let team: String
    var wins = 0
    var losses = 0
    var ties = 0
    var pointsFor = 0
    var pointsAgainst = 0
    /// "W2", "L1", "OT1" (overtime or shootout losses, as the league writes
    /// it); nil before a game.
    var streak: String?

    var id: String { team }
    var games: Int { wins + losses + ties }
    var otLosses: Int { ties }
    var goalsFor: Int { pointsFor }
    var goalsAgainst: Int { pointsAgainst }
    var differential: Int { pointsFor - pointsAgainst }
    /// Standings points: two for a win, one for an overtime or shootout loss.
    var points: Int { wins * 2 + ties }
    /// Points percentage, the NHL's own tiebreaker before regulation wins.
    var winPercentage: Double {
        games == 0 ? 0 : Double(points) / Double(games * 2)
    }

    /// "12-5-2", always three numbers, the way hockey records are written.
    var record: String {
        "\(wins)-\(losses)-\(ties)"
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
                results[team, default: []].append(result == "OTL" ? "OT" : result)
            }
        }
        for (team, list) in results {
            guard let last = list.last else { continue }
            let run = list.reversed().prefix { $0 == last }.count
            rows[team]?.streak = "\(last)\(run)"
        }
        return rows
    }

    /// Points, then points percentage, then goal differential, then name: not
    /// the NHL's full tiebreaker ladder, and the Standings screen says so.
    static func ordered(_ rows: [StandingsRow]) -> [StandingsRow] {
        rows.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.winPercentage != $1.winPercentage { return $0.winPercentage > $1.winPercentage }
            if $0.differential != $1.differential { return $0.differential > $1.differential }
            return $0.team < $1.team
        }
    }

    /// A club's place inside its division, by the same ordering the Standings
    /// screen draws. Nil before the club has played, or for a club outside the
    /// four divisions.
    static func divisionPlace(of team: String, in table: [String: StandingsRow]) -> (place: Int, division: LeagueDivision)? {
        let abbr = normalizedTeamAbbreviation(team)
        guard let division = LeagueDivision.division(of: abbr),
              let row = table[abbr], row.games > 0 else { return nil }
        let rows = ordered(division.teams.compactMap { table[$0] })
        guard let index = rows.firstIndex(where: { $0.team == abbr }) else { return nil }
        return (index + 1, division)
    }

    /// "1ST", "2ND", "3RD", "4TH", "11TH", "22ND".
    static func ordinal(_ number: Int) -> String {
        let teens = (11...13).contains(number % 100)
        let suffix: String
        switch (teens, number % 10) {
        case (false, 1): suffix = "ST"
        case (false, 2): suffix = "ND"
        case (false, 3): suffix = "RD"
        default: suffix = "TH"
        }
        return "\(number)\(suffix)"
    }
}

/// A club's season at a glance from its posted finals and game breakdowns:
/// the numbers a standings page leaves out, each with its league rank.
struct TeamSeasonSummary: Hashable, Sendable {
    struct Stat: Hashable, Sendable {
        let value: Double
        /// 1 is best in the league.
        var rank: Int = 0
    }

    let team: String
    let games: Int
    var goalsFor: Stat
    var goalsAgainst: Stat
    var shotsFor: Stat?
    var shotsAgainst: Stat?
    var powerPlay: Stat?
    var penaltyKill: Stat?
    var expectedGoalsShare: Stat?

    /// Every club's summary, ranked. `xg` covers the games with a built
    /// breakdown, the source of shots, special teams and xG.
    static func build(games: [Game], xg: [String: GameXG], teams: [String]) -> [String: TeamSeasonSummary] {
        struct Totals {
            var games = 0, goalsFor = 0, goalsAgainst = 0
            var detailed = 0, shotsFor = 0, shotsAgainst = 0
            var ppGoals = 0, ppChances = 0, pkAgainst = 0, pkChances = 0
            var xgFor = 0.0, xgAgainst = 0.0
        }
        var totals: [String: Totals] = [:]
        for game in games where game.seasonPhase == .regular && game.isFinal {
            for side in [game.awayTeam, game.homeTeam] {
                let team = normalizedTeamAbbreviation(side)
                let home = game.isHome(side)
                var t = totals[team] ?? Totals()
                t.games += 1
                t.goalsFor += game.score(of: side) ?? 0
                t.goalsAgainst += game.score(of: game.opponent(of: side)) ?? 0
                if let x = xg[game.id] {
                    t.detailed += 1
                    t.xgFor += home ? x.home : x.away
                    t.xgAgainst += home ? x.away : x.home
                    t.shotsFor += (home ? x.homeShots : x.awayShots) ?? 0
                    t.shotsAgainst += (home ? x.awayShots : x.homeShots) ?? 0
                    t.ppGoals += (home ? x.homePowerPlayGoals : x.awayPowerPlayGoals) ?? 0
                    t.ppChances += (home ? x.homePowerPlays : x.awayPowerPlays) ?? 0
                    t.pkAgainst += (home ? x.awayPowerPlayGoals : x.homePowerPlayGoals) ?? 0
                    t.pkChances += (home ? x.awayPowerPlays : x.homePowerPlays) ?? 0
                }
                totals[team] = t
            }
        }
        var out: [String: TeamSeasonSummary] = [:]
        for team in teams {
            guard let t = totals[team], t.games > 0 else { continue }
            let detailed = Double(max(t.detailed, 1))
            out[team] = TeamSeasonSummary(
                team: team,
                games: t.games,
                goalsFor: Stat(value: Double(t.goalsFor) / Double(t.games)),
                goalsAgainst: Stat(value: Double(t.goalsAgainst) / Double(t.games)),
                shotsFor: t.detailed > 0 ? Stat(value: Double(t.shotsFor) / detailed) : nil,
                shotsAgainst: t.detailed > 0 ? Stat(value: Double(t.shotsAgainst) / detailed) : nil,
                powerPlay: t.ppChances > 0 ? Stat(value: Double(t.ppGoals) / Double(t.ppChances)) : nil,
                penaltyKill: t.pkChances > 0 ? Stat(value: 1 - Double(t.pkAgainst) / Double(t.pkChances)) : nil,
                expectedGoalsShare: t.xgFor + t.xgAgainst > 0 ? Stat(value: t.xgFor / (t.xgFor + t.xgAgainst)) : nil
            )
        }
        rank(&out, \.goalsFor, higherIsBetter: true)
        rank(&out, \.goalsAgainst, higherIsBetter: false)
        rankOptional(&out, \.shotsFor, higherIsBetter: true)
        rankOptional(&out, \.shotsAgainst, higherIsBetter: false)
        rankOptional(&out, \.powerPlay, higherIsBetter: true)
        rankOptional(&out, \.penaltyKill, higherIsBetter: true)
        rankOptional(&out, \.expectedGoalsShare, higherIsBetter: true)
        return out
    }

    /// Competition ranking: ties share the better rank ("T-3rd" style).
    private static func rank(_ table: inout [String: TeamSeasonSummary], _ path: WritableKeyPath<TeamSeasonSummary, Stat>, higherIsBetter: Bool) {
        let values = table.mapValues { $0[keyPath: path].value }
        for (team, value) in values {
            let better = values.values.filter { higherIsBetter ? $0 > value + 1e-9 : $0 < value - 1e-9 }.count
            table[team]?[keyPath: path].rank = better + 1
        }
    }

    private static func rankOptional(_ table: inout [String: TeamSeasonSummary], _ path: WritableKeyPath<TeamSeasonSummary, Stat?>, higherIsBetter: Bool) {
        let values = table.compactMapValues { $0[keyPath: path]?.value }
        for (team, value) in values {
            let better = values.values.filter { higherIsBetter ? $0 > value + 1e-9 : $0 < value - 1e-9 }.count
            table[team]?[keyPath: path]?.rank = better + 1
        }
    }

    /// "1st", "2nd", "32nd".
    static func ordinal(_ rank: Int) -> String {
        StandingsRow.ordinal(rank).lowercased()
    }
}
