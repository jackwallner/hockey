#if DEBUG
import Foundation

/// Invented schedule, results and shot breakdowns for the screenshot harness.
///
/// Eight rounds of a 32-team circle schedule, played over the two weeks to last night, so
/// every club has eight finals and the standings, the team game card and the
/// game page all read from real-shaped rows. Scores, shots and names are made
/// up from a hash of the game id, so a run never changes between launches.
extension ScreenshotFixtureAPI {
    // MARK: - Hashing

    /// FNV-1a over the text, so every invented number is stable across runs.
    static func fnv(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        hash ^= hash >> 29
        hash = hash &* 0xbf58_476d_1ce4_e5b9
        hash ^= hash >> 32
        return hash
    }

    /// A stable value in 0..<1 for a text and a salt.
    static func unit(_ text: String, _ salt: Int) -> Double {
        Double(fnv("\(text)-\(salt)") % 10_000) / 10_000
    }

    // MARK: - Schedule

    /// Fourteen days before the last slot, which is last night (see `asOf`).
    private static let openingNight = Calendar.current.date(byAdding: .day, value: -14, to: asOf.addingTimeInterval(3 * 3_600)) ?? asOf

    static let games: [Game] = makeGames()

    static var gameIds: Set<String> { Set(games.map(\.id)) }

    private static func makeGames() -> [Game] {
        var order = leagueTeamAbbreviations.sorted()
        var result: [Game] = []
        var number = 1
        for round in 0..<8 {
            for index in 0..<16 {
                let a = order[index]
                let b = order[31 - index]
                let flip = (round + index).isMultiple(of: 2)
                let away = flip ? a : b
                let home = flip ? b : a
                let slot = round * 2 + (index < 8 ? 0 : 1)
                let day = min(slot, 14)
                let kickoff = Calendar.current.date(byAdding: .day, value: day, to: openingNight)!
                    .addingTimeInterval(TimeInterval((index % 8 / 2) * 1_800))
                let id = String(format: "20260200%02d", number)
                number += 1
                let seed = fnv(id)
                var awayGoals = 1 + Int(seed % 5)
                var homeGoals = 1 + Int((seed / 7) % 5)
                var overtime = false
                if awayGoals == homeGoals {
                    if seed % 2 == 0 { homeGoals += 1 } else { awayGoals += 1 }
                    overtime = true
                } else if abs(awayGoals - homeGoals) == 1, (seed / 13) % 4 == 0 {
                    overtime = true
                }
                result.append(Game(
                    id: id, season: season, week: 1 + day / 7, kickoff: kickoff,
                    awayTeam: away, homeTeam: home,
                    awayScore: awayGoals, homeScore: homeGoals, overtime: overtime
                ))
            }
            // Circle method: the first club stays put, the rest rotate one place.
            let last = order.removeLast()
            order.insert(last, at: 1)
        }
        return result
    }

    // MARK: - Rosters for the game page

    private static let firstNames = ["Aksel", "Bram", "Calder", "Dario", "Emil", "Felix", "Gavin", "Hugo", "Ivar", "Joran", "Kasper", "Leif", "Magnus", "Nils", "Oskar", "Pierce"]
    private static let lastNames = ["Ashgrove", "Brandvold", "Corwin", "Dunmore", "Eskildsen", "Falkner", "Garrick", "Halvorsen", "Ingram", "Jessup", "Kellner", "Lundgren", "Maddox", "Norwood", "Overby", "Penhall", "Quist", "Rademaker", "Sundquist", "Tolliver"]

    struct GameRosterPlayer {
        let id: Int
        let name: String
        let position: String
    }

    /// Six skaters and a goalie per club. A club's fixture players come first,
    /// so the game page agrees with the leaderboards.
    static func gameRoster(for team: String) -> (skaters: [GameRosterPlayer], goalie: GameRosterPlayer) {
        let teamIndex = leagueTeamAbbreviations.firstIndex(of: team) ?? 0
        let seeded = seeds.filter { $0.team == team }
        var skaters = seeded.filter { $0.type != "g" }.map {
            GameRosterPlayer(id: $0.id, name: shortName($0.name), position: $0.position)
        }
        let positions = ["C", "L", "R", "D", "D", "L"]
        var slot = 0
        while skaters.count < 6 {
            let first = firstNames[(teamIndex + slot * 3) % firstNames.count]
            let last = lastNames[(teamIndex * 2 + slot * 5) % lastNames.count]
            skaters.append(GameRosterPlayer(
                id: 30_000 + teamIndex * 20 + slot,
                name: "\(first.prefix(1)). \(last)",
                position: positions[skaters.count % positions.count]
            ))
            slot += 1
        }
        let goalie = seeded.first { $0.type == "g" }.map {
            GameRosterPlayer(id: $0.id, name: shortName($0.name), position: "G")
        } ?? GameRosterPlayer(
            id: 30_000 + teamIndex * 20 + 19,
            name: "\(firstNames[(teamIndex + 7) % firstNames.count].prefix(1)). \(lastNames[(teamIndex * 3 + 4) % lastNames.count])",
            position: "G"
        )
        return (Array(skaters.prefix(6)), goalie)
    }

    private static func shortName(_ full: String) -> String {
        let parts = full.split(separator: " ")
        guard let first = parts.first, let last = parts.last, parts.count > 1 else { return full }
        return "\(first.prefix(1)). \(last)"
    }

    // MARK: - Game detail

    private struct Shot {
        let elapsed: Double
        let xg: Double
        let team: String
        let isGoal: Bool
        let shooter: GameRosterPlayer
    }

    static func makeGameDetail(for game: Game) -> GameDetail? {
        let seed = game.id
        let awayRoster = gameRoster(for: game.awayTeam)
        let homeRoster = gameRoster(for: game.homeTeam)
        let awayGoals = game.awayScore ?? 0
        let homeGoals = game.homeScore ?? 0
        let end: Double = game.overtime ? 3_900 : 3_600

        func pct(_ key: String, _ salt: Int) -> Int {
            20 + Int(unit(seed + key, salt) * 75)
        }
        func totalXG(goals: Int, salt: Int) -> Double {
            max(0.9, Double(goals) * 0.55 + 0.9 + unit(seed, salt) * 1.4)
        }
        let awayXG = totalXG(goals: awayGoals, salt: 1)
        let homeXG = totalXG(goals: homeGoals, salt: 2)
        let awaySOG = 24 + Int(unit(seed, 3) * 12)
        let homeSOG = 24 + Int(unit(seed, 4) * 12)

        // Shots: every goal, plus enough misses and saves to reach the shot count.
        func shots(for team: String, roster: (skaters: [GameRosterPlayer], goalie: GameRosterPlayer), goals: Int, sog: Int, xg: Double, salt: Int) -> [Shot] {
            let count = max(goals + 4, sog)
            var raw: [(time: Double, weight: Double, shooter: GameRosterPlayer)] = []
            for index in 0..<count {
                let time = 30 + unit(seed + team, salt * 100 + index) * 3_500
                let weight = 0.04 + pow(unit(seed + team, salt * 100 + 50 + index), 2.2) * 0.55
                let shooter = roster.skaters[Int(unit(seed + team, salt * 100 + 80 + index) * Double(roster.skaters.count))]
                raw.append((time, weight, shooter))
            }
            raw.sort { $0.time < $1.time }
            // The goals are the shots that landed nearest a spread of moments.
            var goalIndexes = Set<Int>()
            for goal in 0..<goals {
                var candidate = (goal * count / max(goals, 1)) + Int(unit(seed + team, salt * 100 + 90 + goal) * Double(max(count / max(goals, 1), 1)))
                candidate = min(candidate, count - 1)
                while goalIndexes.contains(candidate) { candidate = (candidate + 1) % count }
                goalIndexes.insert(candidate)
            }
            let scale = xg / raw.map(\.weight).reduce(0, +)
            return raw.enumerated().map { index, shot in
                Shot(elapsed: shot.time, xg: shot.weight * scale, team: team, isGoal: goalIndexes.contains(index), shooter: shot.shooter)
            }
        }
        var awayShots = shots(for: game.awayTeam, roster: awayRoster, goals: awayGoals, sog: awaySOG, xg: awayXG, salt: 1)
        var homeShots = shots(for: game.homeTeam, roster: homeRoster, goals: homeGoals, sog: homeSOG, xg: homeXG, salt: 2)

        // An overtime game: the winner's last goal is the overtime goal.
        if game.overtime {
            func moveLastGoalToOvertime(_ shots: inout [Shot]) {
                guard let index = shots.lastIndex(where: \.isGoal) else { return }
                let shot = shots[index]
                shots[index] = Shot(elapsed: 3_620 + unit(seed, 9) * 220, xg: shot.xg, team: shot.team, isGoal: true, shooter: shot.shooter)
            }
            if awayGoals > homeGoals { moveLastGoalToOvertime(&awayShots) } else { moveLastGoalToOvertime(&homeShots) }
        }

        let events = (awayShots + homeShots).sorted { $0.elapsed < $1.elapsed }
        var race: [[Double]] = [[0, 0, 0, 0, 0]]
        var runningAway = 0.0, runningHome = 0.0, goalsAway = 0, goalsHome = 0
        for shot in events {
            if shot.team == game.awayTeam {
                runningAway += shot.xg
                if shot.isGoal { goalsAway += 1 }
            } else {
                runningHome += shot.xg
                if shot.isGoal { goalsHome += 1 }
            }
            race.append([shot.elapsed.rounded(), runningAway, runningHome, Double(goalsAway), Double(goalsHome)])
        }
        race.append([end, runningAway, runningHome, Double(goalsAway), Double(goalsHome)])

        // Team table.
        func teamStats(xg: Double, sog: Int, goals: Int, salt: Int, xgShare: Double) -> [String: Any] {
            func rated(_ value: Double, _ key: String) -> [String: Any] { ["value": value, "pct": pct(key, salt)] }
            return [
                "xg": rated(xg, "xg"),
                "xg_5v5": rated(xg * 0.82, "xg5"),
                "xgf_pct_5v5": rated(xgShare, "xgf"),
                "cf_pct_5v5": rated(0.42 + unit(seed, salt + 20) * 0.16, "cf"),
                "hd_chances": rated(Double(6 + Int(unit(seed, salt + 30) * 9)), "hd"),
                "sog": Double(sog),
                "shot_attempts": rated(Double(sog + 14 + Int(unit(seed, salt + 40) * 14)), "att"),
                "goals": Double(goals),
                "gax": rated(Double(goals) - xg, "gax"),
                "pp_goals": Double(Int(unit(seed, salt + 50) * 2.4)),
                "pp_opportunities": Double(2 + Int(unit(seed, salt + 60) * 3)),
                "faceoff_pct": rated(0.44 + unit(seed, salt + 70) * 0.12, "fo"),
                "hits": Double(14 + Int(unit(seed, salt + 80) * 20)),
                "blocks": Double(8 + Int(unit(seed, salt + 90) * 14)),
                "pim": Double(Int(unit(seed, salt + 95) * 4) * 2),
            ]
        }
        let share = awayXG / (awayXG + homeXG)
        let teamBlock: [String: Any] = [
            "away": teamStats(xg: awayXG, sog: awaySOG, goals: awayGoals, salt: 1, xgShare: share),
            "home": teamStats(xg: homeXG, sog: homeSOG, goals: homeGoals, salt: 2, xgShare: 1 - share),
        ]

        // Player lines: team goals go to the skaters who took the goal shots.
        func skaterLines(team: String, roster: (skaters: [GameRosterPlayer], goalie: GameRosterPlayer), shots: [Shot], goals: Int, sog: Int) -> [[String: Any]] {
            roster.skaters.enumerated().map { index, skater in
                let mine = shots.filter { $0.shooter.id == skater.id }
                let ixg = mine.map(\.xg).reduce(0, +)
                let scored = mine.filter(\.isGoal).count
                let assists = Int(unit(seed + skater.name, 7) * 2.2) * (goals > 0 ? 1 : 0)
                let toi = (skater.position == "D" ? 1_380 : 1_130) + Int(unit(seed + skater.name, 8) * 240)
                let shotsOnGoal = max(scored, Int((Double(mine.count) * 0.7).rounded()))
                return [
                    "role": "skater", "player_id": skater.id, "name": skater.name, "team": team,
                    "position": skater.position, "toi": toi,
                    "goals": scored, "assists": assists, "points": scored + assists,
                    "sog": shotsOnGoal, "shot_attempts": mine.count + Int(unit(seed + skater.name, 9) * 3),
                    "hd_shots": Int(unit(seed + skater.name, 10) * 3),
                    "ixg": ["value": ixg, "pct": 20 + Int(unit(seed + skater.name, 11) * 75)],
                    "gax": ["value": Double(scored) - ixg, "pct": 20 + Int(unit(seed + skater.name, 12) * 75)],
                    "ixg_per_60": ["value": ixg / (Double(toi) / 3_600), "pct": 20 + Int(unit(seed + skater.name, 13) * 75)],
                ]
            }
        }
        func goalieLine(team: String, goalie: GameRosterPlayer, against: Int, faced: Int, xga: Double) -> [String: Any] {
            let saves = max(0, faced - against)
            return [
                "role": "goalie", "player_id": goalie.id, "name": goalie.name, "team": team, "position": "G",
                "toi": Int(end), "shots_against": faced, "saves": saves, "goals_against": against,
                "xga": ["value": xga, "pct": 20 + Int(unit(seed + team, 21) * 75)],
                "gsax": ["value": xga - Double(against), "pct": 20 + Int(unit(seed + team, 22) * 75)],
                "sv_pct": ["value": faced > 0 ? Double(saves) / Double(faced) : 1.0, "pct": 20 + Int(unit(seed + team, 23) * 75)],
            ]
        }
        let players = skaterLines(team: game.awayTeam, roster: awayRoster, shots: awayShots, goals: awayGoals, sog: awaySOG)
            + skaterLines(team: game.homeTeam, roster: homeRoster, shots: homeShots, goals: homeGoals, sog: homeSOG)
            + [
                goalieLine(team: game.awayTeam, goalie: awayRoster.goalie, against: homeGoals, faced: homeSOG, xga: homeXG),
                goalieLine(team: game.homeTeam, goalie: homeRoster.goalie, against: awayGoals, faced: awaySOG, xga: awayXG),
            ]

        // The chances that decided it: every goal plus the five biggest misses.
        let descriptions = ["Wrist shot, slot", "Snap shot, slot, rebound", "One-timer, high slot", "Backhand, in tight", "Slap shot, off the rush", "Tip-in, crease"]
        func play(_ shot: Shot, index: Int) -> [String: Any] {
            let period = min(4, Int(shot.elapsed / 1_200) + 1)
            let inPeriod = Int(shot.elapsed) - (period - 1) * 1_200
            let results = ["SAVE", "SAVE", "MISS", "BLOCK"]
            return [
                "period": period,
                "clock": String(format: "%d:%02d", inPeriod / 60, inPeriod % 60),
                "team": shot.team,
                "description": descriptions[Int(fnv(seed + "\(index)") % UInt64(descriptions.count))],
                "xg": shot.xg,
                "result": shot.isGoal ? "GOAL" : results[Int(fnv(seed + "r\(index)") % 4)],
                "player_id": shot.shooter.id,
                "shooter": shot.shooter.name,
            ]
        }
        let goalShots = events.filter(\.isGoal)
        let topMisses = events.filter { !$0.isGoal }.sorted { $0.xg > $1.xg }.prefix(5)
        let bigPlays = (goalShots + topMisses).sorted { $0.elapsed < $1.elapsed }.enumerated().map { play($1, index: $0) }

        let payload: [String: Any] = [
            "game_id": game.id,
            "away_team": game.awayTeam,
            "home_team": game.homeTeam,
            "team_stats": teamBlock,
            "players": players,
            "win_probability": race,
            "big_plays": bigPlays,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder.statScout.decode(GameDetail.self, from: data)
    }

    // MARK: - Bios

    static func makeProfiles() -> [PlayerProfile] {
        let towns = ["Fairhaven, WA, USA", "Kestrel Bay, ON, CAN", "Norrby, SWE", "Valmont, MN, USA", "Harbourgate, BC, CAN", "Lindholm, FIN", "Stonebridge, MI, USA", "Ravenna Falls, QC, CAN"]
        return seeds.enumerated().map { index, seed in
            var profile = PlayerProfile(playerId: seed.id, season: season)
            profile.jersey = 8 + (index * 7) % 80
            profile.birthDate = makeDate("\(1993 + index % 8)-0\(1 + index % 9)-1\(index % 9)T12:00:00Z")
            profile.heightInches = seed.type == "g" ? 76 : (seed.type == "d" ? 75 : 72 + index % 3)
            profile.weightPounds = 185 + (index * 4) % 30
            profile.birthplace = towns[index % towns.count]
            profile.yearsExperience = 2 + index % 9
            profile.draftYear = 2013 + index % 8
            profile.draftRound = 1 + index % 3
            profile.draftPick = 3 + (index * 11) % 60
            profile.draftTeam = seed.team
            let perGame = seed.type == "d" ? 1_428 : (seed.type == "g" ? 3_600 : 1_132)
            profile.toiPerGame = perGame
            profile.toiSeconds = perGame * 8
            profile.powerPlayToiSeconds = seed.type == "g" ? nil : 190 * 8
            profile.penaltyKillToiSeconds = seed.type == "g" ? nil : 70 * 8
            profile.toiShare = seed.type == "g" ? nil : 0.11 + Double(index % 5) / 100
            return profile
        }
    }
}
#endif
