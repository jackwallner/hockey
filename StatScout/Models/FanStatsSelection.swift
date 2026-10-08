import Foundation

/// Keeps a followed list in the fan's order and in the selected season/phase.
enum FanStatsSelection {
    static func players(ids: [Int], from players: [Player], season: Int, phase: SeasonPhase) -> [Player] {
        let eligible = players.filter { $0.season == season && $0.seasonPhase == phase }
        let byID = Dictionary(eligible.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
    }

    static func summary(for player: Player) -> [StandardStat] {
        let labels: [String]
        switch player.positionGroup {
        case .forward: labels = ["G", "A", "P", "SOG"]
        case .defense: labels = ["P", "+/-", "Blk", "TOI/GP"]
        case .goalie: labels = ["W", "GAA", "SV%"]
        }
        return labels.compactMap { label in
            player.standardStats?.first { $0.label == label }
        }
    }
}
