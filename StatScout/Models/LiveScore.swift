import Foundation

/// The running score of a game under way, read straight from the NHL's public
/// scoreboard. The StatScout backend publishes a score only at the final, so
/// this is what lets a game in progress show its score and clock.
struct LiveScore: Hashable, Sendable {
    let gameId: String
    let awayScore: Int
    let homeScore: Int
    let awayShots: Int?
    let homeShots: Int?
    /// NHL `gameState`: FUT, PRE, LIVE, CRIT, FINAL or OFF.
    let state: String
    let period: Int
    let periodType: String
    /// "12:34" left in the period.
    let timeRemaining: String?
    let inIntermission: Bool

    var isFinal: Bool { ["FINAL", "OFF"].contains(state) }
    var isUnderway: Bool { ["LIVE", "CRIT"].contains(state) }

    /// "1st", "2nd", "3rd", "OT", "2OT".
    var periodLabel: String {
        switch (periodType, period) {
        case ("SO", _): return "SO"
        case (_, 1): return "1st"
        case (_, 2): return "2nd"
        case (_, 3): return "3rd"
        case (_, 4): return "OT"
        default: return "\(period - 3)OT"
        }
    }

    /// "2nd 12:34", "2nd INT", "Shootout", "End 3rd", "Final/OT".
    var clockLabel: String {
        if isFinal {
            switch periodType {
            case "OT": return period > 4 ? "Final/\(period - 3)OT" : "Final/OT"
            case "SO": return "Final/SO"
            default: return "Final"
            }
        }
        if periodType == "SO" { return "Shootout" }
        if inIntermission { return "\(periodLabel) INT" }
        guard let timeRemaining, timeRemaining != "00:00" else { return "End \(periodLabel)" }
        let clock = timeRemaining.hasPrefix("0") ? String(timeRemaining.dropFirst()) : timeRemaining
        return "\(periodLabel) \(clock)"
    }

    func score(isHome: Bool) -> Int { isHome ? homeScore : awayScore }

    /// Games from one `score/<date>` payload that have started.
    static func parse(_ data: Data) -> [LiveScore] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.games.compactMap { game in
            guard let away = game.awayTeam.score, let home = game.homeTeam.score,
                  !["FUT", "PRE"].contains(game.gameState) else { return nil }
            return LiveScore(
                gameId: String(game.id),
                awayScore: away,
                homeScore: home,
                awayShots: game.awayTeam.sog,
                homeShots: game.homeTeam.sog,
                state: game.gameState,
                period: game.periodDescriptor?.number ?? game.period ?? 1,
                periodType: game.periodDescriptor?.periodType ?? "REG",
                timeRemaining: game.clock?.timeRemaining,
                inIntermission: game.clock?.inIntermission ?? false
            )
        }
    }

    private struct Payload: Decodable {
        let games: [PayloadGame]
    }

    private struct PayloadGame: Decodable {
        struct Side: Decodable {
            let score: Int?
            let sog: Int?
        }
        struct Period: Decodable {
            let number: Int?
            let periodType: String?
        }
        struct Clock: Decodable {
            let timeRemaining: String?
            let inIntermission: Bool?
        }
        let id: Int
        let gameState: String
        let period: Int?
        let periodDescriptor: Period?
        let clock: Clock?
        let awayTeam: Side
        let homeTeam: Side
    }
}

/// Reads the NHL scoreboard for the given NHL game dates ("2026-10-11").
struct LiveScoreClient: Sendable {
    var session: URLSession = .shared

    func fetch(dates: Set<String>) async -> [String: LiveScore] {
        await withTaskGroup(of: [LiveScore].self) { group in
            for date in dates {
                group.addTask {
                    guard let url = URL(string: "https://api-web.nhle.com/v1/score/\(date)") else { return [] }
                    var request = URLRequest(url: url, timeoutInterval: 10)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    guard let (data, response) = try? await session.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return LiveScore.parse(data)
                }
            }
            var scores: [String: LiveScore] = [:]
            for await batch in group {
                for score in batch { scores[score.gameId] = score }
            }
            return scores
        }
    }

    /// The NHL files a game under its local date; `Game.gameDate` holds it at
    /// Eastern midnight (see `DataFreshness.parseDate`).
    static func dateKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
