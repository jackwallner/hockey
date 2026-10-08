import Foundation

/// A basic box score rebuilt from one game's `player_game_logs` rows.
///
/// Every number is a sum of per-player counts nflverse publishes for the game.
/// Nothing here is a roster average or a percentile. Team totals only use
/// columns that do not double count: receiving yards are the same yards as
/// passing yards, so they are never added in.
struct GameBoxScore: Sendable {
    struct PlayerLine: Identifiable, Hashable, Sendable {
        let playerId: Int
        let team: String
        let playerType: String
        let metrics: [String: Double]

        var id: String { "\(playerId)-\(playerType)" }

        func value(_ key: String) -> Double { metrics[key] ?? 0 }
        func int(_ key: String) -> Int { Int(value(key).rounded()) }

        var tackles: Double { value("def_tackles_solo") + value("def_tackle_assists") }
    }

    struct TeamTotals: Equatable, Sendable {
        var passingYards = 0.0
        var sackYardsLost = 0.0
        var rushingYards = 0.0
        var firstDowns = 0.0
        var interceptionsThrown = 0.0
        var fumblesLost = 0.0
        var sacksTaken = 0.0
        var passAttempts = 0.0
        var carries = 0.0
        var offenseEPA = 0.0
        var hasEPA = false
        var passingEPA = 0.0
        var rushingEPA = 0.0
        var hasPassingEPA = false
        var hasRushingEPA = false
        var airYards = 0.0
        var yardsAfterCatch = 0.0

        /// Net passing (sacks subtracted) plus rushing, the box-score convention.
        var totalYards: Double { passingYards - sackYardsLost + rushingYards }
        var netPassingYards: Double { passingYards - sackYardsLost }
        var turnovers: Double { interceptionsThrown + fumblesLost }
        var dropbacks: Double { passAttempts + sacksTaken }
        var plays: Double { dropbacks + carries }
        var epaPerPlay: Double? { hasEPA && plays > 0 ? offenseEPA / plays : nil }
        var epaPerDropback: Double? { hasPassingEPA && dropbacks > 0 ? passingEPA / dropbacks : nil }
        var epaPerCarry: Double? { hasRushingEPA && carries > 0 ? rushingEPA / carries : nil }
        var yardsPerPlay: Double? { plays > 0 ? totalYards / plays : nil }
        var netYardsPerDropback: Double? { dropbacks > 0 ? netPassingYards / dropbacks : nil }
        var yardsPerCarry: Double? { carries > 0 ? rushingYards / carries : nil }
        var airYardsPerAttempt: Double? { passAttempts > 0 ? airYards / passAttempts : nil }
        /// Share of completed passing yards gained after the catch.
        var yacShare: Double? { passingYards > 0 ? yardsAfterCatch / passingYards * 100 : nil }
        var sackRate: Double? { dropbacks > 0 ? sacksTaken / dropbacks * 100 : nil }
        var firstDownRate: Double? { plays > 0 ? firstDowns / plays * 100 : nil }
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

    func totals(for team: String) -> TeamTotals {
        var totals = TeamTotals()
        for line in lines(for: team) {
            totals.passingYards += line.value("passing_yards")
            totals.sackYardsLost += line.value("sack_yards_lost")
            totals.rushingYards += line.value("rushing_yards")
            totals.firstDowns += line.value("passing_first_downs") + line.value("rushing_first_downs")
            totals.interceptionsThrown += line.value("interceptions")
            totals.fumblesLost += line.value("rushing_fumbles_lost")
            totals.sacksTaken += line.value("sacks_suffered")
            totals.passAttempts += line.value("attempts")
            totals.carries += line.value("carries")
            totals.airYards += line.value("passing_air_yards")
            totals.yardsAfterCatch += line.value("receiving_yac")
            if let epa = line.metrics["passing_epa"] {
                totals.passingEPA += epa
                totals.offenseEPA += epa
                totals.hasPassingEPA = true
                totals.hasEPA = true
            }
            if let epa = line.metrics["rushing_epa"] {
                totals.rushingEPA += epa
                totals.offenseEPA += epa
                totals.hasRushingEPA = true
                totals.hasEPA = true
            }
        }
        return totals
    }

    func passers(for team: String) -> [PlayerLine] {
        lines(for: team).filter { $0.value("attempts") > 0 }
            .sorted { $0.value("attempts") > $1.value("attempts") }
    }

    func rushers(for team: String) -> [PlayerLine] {
        lines(for: team).filter { $0.value("carries") > 0 }
            .sorted { ($0.value("rushing_yards"), $0.value("carries")) > ($1.value("rushing_yards"), $1.value("carries")) }
    }

    func receivers(for team: String) -> [PlayerLine] {
        lines(for: team).filter { $0.value("targets") > 0 || $0.value("receptions") > 0 }
            .sorted { ($0.value("receiving_yards"), $0.value("receptions")) > ($1.value("receiving_yards"), $1.value("receptions")) }
    }

    func defenders(for team: String) -> [PlayerLine] {
        lines(for: team)
            .filter { $0.tackles > 0 || $0.value("def_sacks") > 0 || $0.value("def_interceptions") > 0 }
            .sorted {
                ($0.value("def_sacks") + $0.value("def_interceptions"), $0.tackles)
                    > ($1.value("def_sacks") + $1.value("def_interceptions"), $1.tackles)
            }
    }

    /// A player's EPA across everything he did: passing, rushing and receiving.
    /// Per player this is not double counting; a completion's value is credited
    /// to both passer and receiver by design, so these are never summed to a team.
    static func totalEPA(_ line: PlayerLine) -> Double? {
        let parts = ["passing_epa", "rushing_epa", "receiving_epa"].compactMap { line.metrics[$0] }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    /// The most valuable players of the game by total EPA, both teams.
    func epaLeaders(limit: Int = 5) -> [PlayerLine] {
        lines.compactMap { line in Self.totalEPA(line).map { (line, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Game leaders across both teams: passing, rushing and receiving yards,
    /// plus the defender with the most sacks and interceptions, then tackles.
    struct Leader: Identifiable, Hashable, Sendable {
        let title: String
        let line: PlayerLine
        let summary: String
        var id: String { title }
    }

    var leaders: [Leader] {
        var result: [Leader] = []
        if let top = lines.filter({ $0.value("attempts") > 0 }).max(by: { $0.value("passing_yards") < $1.value("passing_yards") }) {
            result.append(Leader(title: "Passing", line: top, summary: Self.passingSummary(top)))
        }
        if let top = lines.filter({ $0.value("carries") > 0 }).max(by: { $0.value("rushing_yards") < $1.value("rushing_yards") }) {
            result.append(Leader(title: "Rushing", line: top, summary: Self.rushingSummary(top)))
        }
        if let top = lines.filter({ $0.value("receptions") > 0 }).max(by: { $0.value("receiving_yards") < $1.value("receiving_yards") }) {
            result.append(Leader(title: "Receiving", line: top, summary: Self.receivingSummary(top)))
        }
        if let top = lines.filter({ $0.tackles > 0 || $0.value("def_sacks") > 0 }).max(by: {
            ($0.value("def_sacks") + $0.value("def_interceptions"), $0.tackles)
                < ($1.value("def_sacks") + $1.value("def_interceptions"), $1.tackles)
        }) {
            result.append(Leader(title: "Defense", line: top, summary: Self.defenseSummary(top)))
        }
        return result
    }

    static func passingSummary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("completions"))/\(line.int("attempts"))", "\(line.int("passing_yards")) yds"]
        if line.int("passing_tds") > 0 { parts.append("\(line.int("passing_tds")) TD") }
        if line.int("interceptions") > 0 { parts.append("\(line.int("interceptions")) INT") }
        return parts.joined(separator: ", ")
    }

    static func rushingSummary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("carries")) car", "\(line.int("rushing_yards")) yds"]
        if line.int("rushing_tds") > 0 { parts.append("\(line.int("rushing_tds")) TD") }
        return parts.joined(separator: ", ")
    }

    static func receivingSummary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("receptions")) rec", "\(line.int("receiving_yards")) yds"]
        if line.int("receiving_tds") > 0 { parts.append("\(line.int("receiving_tds")) TD") }
        return parts.joined(separator: ", ")
    }

    static func defenseSummary(_ line: PlayerLine) -> String {
        var parts = ["\(Int(line.tackles.rounded())) tkl"]
        let sacks = line.value("def_sacks")
        if sacks > 0 { parts.append("\(sacks.formatted(.number.precision(.fractionLength(0...1)))) sck") }
        if line.int("def_interceptions") > 0 { parts.append("\(line.int("def_interceptions")) INT") }
        return parts.joined(separator: ", ")
    }

    /// A player's one-line game summary, whichever parts of the game they had.
    static func summary(_ line: PlayerLine) -> String {
        var parts: [String] = []
        if line.value("attempts") > 0 { parts.append(passingSummary(line)) }
        if line.value("carries") > 0 { parts.append(rushingSummary(line)) }
        if line.value("targets") > 0 || line.value("receptions") > 0 { parts.append(receivingSummary(line)) }
        if parts.isEmpty, line.tackles > 0 || line.value("def_sacks") > 0 { parts.append(defenseSummary(line)) }
        return parts.joined(separator: " · ")
    }
}
