import Foundation

/// A basic box score rebuilt from one game's `player_game_logs` rows.
///
/// Every number is a raw count from the NHL boxscore, joined with MoneyPuck's
/// shot-level expected goals. Nothing here is a roster average or a
/// percentile. Skater keys are `goals`, `assists`, `points`, `shots_on_goal`,
/// `ixg`, `toi_seconds` and friends; goalie keys are `shots_against`,
/// `saves`, `goals_against`, `xga`, `toi_seconds`.
struct GameBoxScore: Sendable {
    struct PlayerLine: Identifiable, Hashable, Sendable {
        let playerId: Int
        let team: String
        let playerType: String
        let metrics: [String: Double]

        var id: String { "\(playerId)-\(playerType)" }
        var isGoalie: Bool { playerType.lowercased() == "g" }

        func value(_ key: String) -> Double { metrics[key] ?? 0 }
        func int(_ key: String) -> Int { Int(value(key).rounded()) }

        /// "19:42", from `toi_seconds`.
        var toiLabel: String? {
            let seconds = int("toi_seconds")
            guard seconds > 0 else { return nil }
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    let lines: [PlayerLine]

    init(logs: [PlayerGameLog]) {
        lines = logs.map { log in
            PlayerLine(
                playerId: log.playerId,
                team: normalizedTeamAbbreviation(log.team ?? ""),
                playerType: log.playerType,
                metrics: log.metrics.compactMapValues { $0 }
            )
        }
    }

    var isEmpty: Bool { lines.isEmpty }

    func lines(for team: String) -> [PlayerLine] {
        let abbr = normalizedTeamAbbreviation(team)
        return lines.filter { $0.team == abbr }
    }

    /// "1 G, 1 A, 4 SOG, 0.62 ixG, 19:42 TOI" for a skater, leaving out what
    /// he did not do.
    static func skaterSummary(_ line: PlayerLine) -> String {
        var parts: [String] = []
        if line.int("goals") > 0 { parts.append("\(line.int("goals")) G") }
        if line.int("assists") > 0 { parts.append("\(line.int("assists")) A") }
        if parts.isEmpty { parts.append("0 P") }
        parts.append("\(line.int("shots_on_goal")) SOG")
        if line.metrics["ixg"] != nil {
            parts.append(String(format: "%.2f ixG", line.value("ixg")))
        }
        if let toi = line.toiLabel { parts.append("\(toi) TOI") }
        return parts.joined(separator: ", ")
    }

    /// "28 saves on 30 shots, 2 GA" for a goalie.
    static func goalieSummary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("saves")) saves on \(line.int("shots_against")) shots"]
        parts.append("\(line.int("goals_against")) GA")
        if line.metrics["xga"] != nil {
            parts.append(String(format: "%.2f xGA", line.value("xga")))
        }
        return parts.joined(separator: ", ")
    }

    /// A player's one-line game summary.
    static func summary(_ line: PlayerLine) -> String {
        line.isGoalie ? goalieSummary(line) : skaterSummary(line)
    }
}
