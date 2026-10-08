#if DEBUG
import Foundation

struct SampleData {
    // Invented players for the 2026-27 season, plus one 2025-26 row to
    // exercise year switching. No real names.
    static let players: [Player] = [
        Player(
            playerId: 12001,
            name: "Callum Therrien",
            team: "SEA",
            position: "C",
            handedness: "L",
            updatedAt: Date(),
            season: 2026,
            playerType: "f",
            metrics: [
                Metric(id: "therrien-p60", label: "P/60", value: "3.62", percentile: 96, category: .scoring),
                Metric(id: "therrien-g", label: "G", value: "6", percentile: 93, category: .scoring),
                Metric(id: "therrien-a", label: "A", value: "7", percentile: 95, category: .scoring),
                Metric(id: "therrien-p", label: "P", value: "13", percentile: 96, category: .scoring),
                Metric(id: "therrien-sog", label: "SOG", value: "31", percentile: 88, category: .scoring),
                Metric(id: "therrien-shp", label: "Sh%", value: "19.4%", percentile: 90, category: .scoring),
                Metric(id: "therrien-ixg", label: "ixG", value: "4.9", percentile: 97, category: .shotQuality),
                Metric(id: "therrien-gax", label: "GAx", value: "+1.1", percentile: 82, category: .shotQuality),
                Metric(id: "therrien-ixg60", label: "ixG/60", value: "1.31", percentile: 95, category: .shotQuality),
                Metric(id: "therrien-xgf", label: "xGF%", value: "56.8%", percentile: 91, category: .playDriving),
                Metric(id: "therrien-cf", label: "CF%", value: "54.1%", percentile: 84, category: .playDriving),
                Metric(id: "therrien-hits", label: "Hits", value: "9", percentile: 48, category: .playDriving)
            ],
            standardStats: [
                StandardStat(id: "std-GP", label: "GP", value: "8"),
                StandardStat(id: "std-G", label: "G", value: "6"),
                StandardStat(id: "std-A", label: "A", value: "7"),
                StandardStat(id: "std-P", label: "P", value: "13"),
                StandardStat(id: "std-+/-", label: "+/-", value: "+5"),
                StandardStat(id: "std-PIM", label: "PIM", value: "4"),
                StandardStat(id: "std-PPG", label: "PPG", value: "2"),
                StandardStat(id: "std-PPP", label: "PPP", value: "5"),
                StandardStat(id: "std-SOG", label: "SOG", value: "31"),
                StandardStat(id: "std-Sh%", label: "Sh%", value: "19.4%"),
                StandardStat(id: "std-TOI/GP", label: "TOI/GP", value: "20:14"),
                StandardStat(id: "std-FO%", label: "FO%", value: "54.3%")
            ],
            games: []
        ),
        Player(
            playerId: 12002,
            name: "Rasmus Holloway",
            team: "EDM",
            position: "L",
            handedness: "L",
            updatedAt: Date(),
            season: 2026,
            playerType: "f",
            metrics: [
                Metric(id: "holloway-p60", label: "P/60", value: "3.05", percentile: 90, category: .scoring),
                Metric(id: "holloway-g", label: "G", value: "5", percentile: 89, category: .scoring),
                Metric(id: "holloway-p", label: "P", value: "9", percentile: 86, category: .scoring),
                Metric(id: "holloway-ixg", label: "ixG", value: "3.7", percentile: 91, category: .shotQuality),
                Metric(id: "holloway-gax", label: "GAx", value: "+1.3", percentile: 87, category: .shotQuality),
                Metric(id: "holloway-xgf", label: "xGF%", value: "53.2%", percentile: 74, category: .playDriving)
            ],
            standardStats: [
                StandardStat(id: "std-GP", label: "GP", value: "8"),
                StandardStat(id: "std-G", label: "G", value: "5"),
                StandardStat(id: "std-A", label: "A", value: "4"),
                StandardStat(id: "std-P", label: "P", value: "9"),
                StandardStat(id: "std-SOG", label: "SOG", value: "27"),
                StandardStat(id: "std-TOI/GP", label: "TOI/GP", value: "18:41")
            ],
            games: []
        ),
        Player(
            playerId: 12008,
            name: "Mikael Sandvik",
            team: "SEA",
            position: "D",
            handedness: "R",
            updatedAt: Date(),
            season: 2026,
            playerType: "d",
            metrics: [
                Metric(id: "sandvik-xgf", label: "xGF%", value: "57.4%", percentile: 94, category: .playDriving),
                Metric(id: "sandvik-rel", label: "Rel xGF%", value: "+5.2", percentile: 92, category: .playDriving),
                Metric(id: "sandvik-xga", label: "xGA/60", value: "2.01", percentile: 88, category: .playDriving),
                Metric(id: "sandvik-blk", label: "Blocks", value: "14", percentile: 80, category: .playDriving),
                Metric(id: "sandvik-p", label: "P", value: "7", percentile: 90, category: .scoring),
                Metric(id: "sandvik-ixg", label: "ixG", value: "1.2", percentile: 84, category: .shotQuality)
            ],
            standardStats: [
                StandardStat(id: "std-GP", label: "GP", value: "8"),
                StandardStat(id: "std-G", label: "G", value: "2"),
                StandardStat(id: "std-A", label: "A", value: "5"),
                StandardStat(id: "std-P", label: "P", value: "7"),
                StandardStat(id: "std-+/-", label: "+/-", value: "+6"),
                StandardStat(id: "std-Blk", label: "Blk", value: "14"),
                StandardStat(id: "std-TOI/GP", label: "TOI/GP", value: "24:32")
            ],
            games: []
        ),
        Player(
            playerId: 12013,
            name: "Henrik Dalgaard",
            team: "SEA",
            position: "G",
            handedness: "L",
            updatedAt: Date(),
            season: 2026,
            playerType: "g",
            metrics: [
                Metric(id: "dalgaard-gsax", label: "GSAx", value: "+3.4", percentile: 93, category: .goaltending),
                Metric(id: "dalgaard-gsax60", label: "GSAx/60", value: "0.42", percentile: 92, category: .goaltending),
                Metric(id: "dalgaard-sv", label: "SV%", value: ".931", percentile: 94, category: .goaltending),
                Metric(id: "dalgaard-gaa", label: "GAA", value: "2.02", percentile: 90, category: .goaltending),
                Metric(id: "dalgaard-hdsv", label: "HD SV%", value: ".861", percentile: 85, category: .goaltending),
                Metric(id: "dalgaard-w", label: "W", value: "5", percentile: 82, category: .goaltending)
            ],
            standardStats: [
                StandardStat(id: "std-GP", label: "GP", value: "6"),
                StandardStat(id: "std-GS", label: "GS", value: "6"),
                StandardStat(id: "std-W", label: "W", value: "5"),
                StandardStat(id: "std-L", label: "L", value: "1"),
                StandardStat(id: "std-OT", label: "OT", value: "0"),
                StandardStat(id: "std-GAA", label: "GAA", value: "2.02"),
                StandardStat(id: "std-SV%", label: "SV%", value: ".931"),
                StandardStat(id: "std-SO", label: "SO", value: "1"),
                StandardStat(id: "std-SA", label: "SA", value: "174"),
                StandardStat(id: "std-SV", label: "SV", value: "162")
            ],
            games: []
        ),
        // 2025-26 row for the same player id so year switching has data.
        Player(
            playerId: 12001,
            name: "Callum Therrien",
            team: "SEA",
            position: "C",
            handedness: "L",
            updatedAt: Date(),
            season: 2025,
            playerType: "f",
            metrics: [
                Metric(id: "therrien25-p60", label: "P/60", value: "2.84", percentile: 86, category: .scoring),
                Metric(id: "therrien25-p", label: "P", value: "71", percentile: 88, category: .scoring),
                Metric(id: "therrien25-ixg", label: "ixG", value: "26.4", percentile: 90, category: .shotQuality),
                Metric(id: "therrien25-xgf", label: "xGF%", value: "53.9%", percentile: 79, category: .playDriving)
            ],
            standardStats: [
                StandardStat(id: "std-GP", label: "GP", value: "79"),
                StandardStat(id: "std-G", label: "G", value: "29"),
                StandardStat(id: "std-A", label: "A", value: "42"),
                StandardStat(id: "std-P", label: "P", value: "71"),
                StandardStat(id: "std-SOG", label: "SOG", value: "231")
            ],
            games: []
        )
    ]
}
#endif
