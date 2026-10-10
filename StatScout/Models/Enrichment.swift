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
        draftYear = try c.decodeIfPresent(Int.self, forKey: .draftYear)
        draftRound = try c.decodeIfPresent(Int.self, forKey: .draftRound)
        draftPick = try c.decodeIfPresent(Int.self, forKey: .draftPick)
        draftTeam = try c.decodeIfPresent(String.self, forKey: .draftTeam)
        toiSeconds = try c.decodeIfPresent(Int.self, forKey: .toiSeconds)
        toiPerGame = try c.decodeIfPresent(Int.self, forKey: .toiPerGame)
        powerPlayToiSeconds = try c.decodeIfPresent(Int.self, forKey: .powerPlayToiSeconds)
        penaltyKillToiSeconds = try c.decodeIfPresent(Int.self, forKey: .penaltyKillToiSeconds)
        toiShare = try c.decodeIfPresent(Double.self, forKey: .toiShare)
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

    /// "2015 R1 #1", or "Undrafted" for a player who came in without a pick.
    var draftLabel: String? {
        if let draftYear, let draftRound, let draftPick {
            return "\(draftYear) R\(draftRound) #\(draftPick)"
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

    static func signed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0.0" }
        return String(format: "%+.1f", rounded)
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

    /// "EDM by 0.6", "Toss-up" under a quarter of a goal.
    func label(home: String, away: String) -> String {
        let margin = abs(homeMargin)
        guard margin >= 0.25 else { return "Toss-up" }
        let favourite = homeMargin > 0 ? home : away
        return "\(displayTeamAbbr(favourite)) by \(String(format: "%.1f", margin))"
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
    /// "W2", "L1"; nil before a game.
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
                results[team, default: []].append(result == "OTL" ? "L" : result)
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
