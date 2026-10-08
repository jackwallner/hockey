#if DEBUG
import Foundation

struct SampleData {
    // Players for the 2025 season, plus one 2024 row to exercise year switching.
    static let players: [Player] = [
        Player(
            playerId: 33873,
            name: "Patrick Mahomes",
            team: "KC",
            position: "QB",
            handedness: "",
            updatedAt: Date(),
            season: 2025,
            playerType: "qb",
            metrics: [
                Metric(id: "mahomes-passyds", label: "Pass Yds", value: "3,928", percentile: 88, category: .passing),
                Metric(id: "mahomes-passtd", label: "Pass TD", value: "26", percentile: 85, category: .passing),
                Metric(id: "mahomes-cmp", label: "Cmp%", value: "67.5%", percentile: 82, category: .passing),
                Metric(id: "mahomes-ya", label: "Y/A", value: "7.0", percentile: 70, category: .passing),
                Metric(id: "mahomes-rating", label: "Rating", value: "98.5", percentile: 84, category: .passing),
                Metric(id: "mahomes-epa", label: "EPA/Play", value: "0.14", percentile: 88, category: .passing),
                Metric(id: "mahomes-cpoe", label: "CPOE", value: "3.5", percentile: 86, category: .passing),
                Metric(id: "mahomes-int", label: "INT%", value: "1.5%", percentile: 75, category: .passing),
                Metric(id: "mahomes-sack", label: "Sack%", value: "5.2%", percentile: 60, category: .passing)
            ],
            standardStats: [
                StandardStat(id: "std-G", label: "G", value: "16"),
                StandardStat(id: "std-CmpAtt", label: "Cmp/Att", value: "351/520"),
                StandardStat(id: "std-PassYds", label: "Pass Yds", value: "3,928"),
                StandardStat(id: "std-PassTD", label: "Pass TD", value: "26"),
                StandardStat(id: "std-INT", label: "INT", value: "8"),
                StandardStat(id: "std-Car", label: "Car", value: "58"),
                StandardStat(id: "std-RushYds", label: "Rush Yds", value: "307"),
                StandardStat(id: "std-RushTD", label: "Rush TD", value: "2")
            ],
            games: []
        ),
        Player(
            playerId: 34857,
            name: "Josh Allen",
            team: "BUF",
            position: "QB",
            handedness: "",
            updatedAt: Date(),
            season: 2025,
            playerType: "qb",
            metrics: [
                Metric(id: "allen-passyds", label: "Pass Yds", value: "3,731", percentile: 80, category: .passing),
                Metric(id: "allen-passtd", label: "Pass TD", value: "28", percentile: 90, category: .passing),
                Metric(id: "allen-rating", label: "Rating", value: "101.4", percentile: 88, category: .passing),
                Metric(id: "allen-epa", label: "EPA/Play", value: "0.16", percentile: 91, category: .passing),
                Metric(id: "allen-rushyds", label: "Rush Yds", value: "531", percentile: 96, category: .rushing),
                Metric(id: "allen-rushtd", label: "Rush TD", value: "12", percentile: 99, category: .rushing),
                Metric(id: "allen-yc", label: "Y/C", value: "5.6", percentile: 92, category: .rushing),
                Metric(id: "allen-eparush", label: "EPA/Rush", value: "0.19", percentile: 95, category: .rushing),
                Metric(id: "allen-rushepa", label: "Rush EPA", value: "18.2", percentile: 95, category: .rushing)
            ],
            standardStats: [
                StandardStat(id: "std-G", label: "G", value: "17"),
                StandardStat(id: "std-CmpAtt", label: "Cmp/Att", value: "307/483"),
                StandardStat(id: "std-PassYds", label: "Pass Yds", value: "3,731"),
                StandardStat(id: "std-PassTD", label: "Pass TD", value: "28"),
                StandardStat(id: "std-INT", label: "INT", value: "6"),
                StandardStat(id: "std-Car", label: "Car", value: "94"),
                StandardStat(id: "std-RushYds", label: "Rush Yds", value: "531"),
                StandardStat(id: "std-RushTD", label: "Rush TD", value: "12")
            ],
            games: []
        ),
        Player(
            playerId: 34844,
            name: "Saquon Barkley",
            team: "PHI",
            position: "RB",
            handedness: "",
            updatedAt: Date(),
            season: 2025,
            playerType: "rb",
            metrics: [
                Metric(id: "saquon-rushyds", label: "Rush Yds", value: "2,005", percentile: 99, category: .rushing),
                Metric(id: "saquon-rushtd", label: "Rush TD", value: "13", percentile: 97, category: .rushing),
                Metric(id: "saquon-yc", label: "Y/C", value: "5.8", percentile: 95, category: .rushing),
                Metric(id: "saquon-eparush", label: "EPA/Rush", value: "0.06", percentile: 91, category: .rushing),
                Metric(id: "saquon-rushepa", label: "Rush EPA", value: "22.1", percentile: 98, category: .rushing),
                Metric(id: "saquon-explosive", label: "Explosive%", value: "12.5%", percentile: 94, category: .rushing),
                Metric(id: "saquon-ryoe", label: "RYOE", value: "310", percentile: 97, category: .rushing),
                Metric(id: "saquon-rec", label: "Rec", value: "33", percentile: 60, category: .receiving),
                Metric(id: "saquon-recyds", label: "Rec Yds", value: "278", percentile: 55, category: .receiving),
                Metric(id: "saquon-yac", label: "YAC", value: "8.1", percentile: 78, category: .receiving)
            ],
            standardStats: [
                StandardStat(id: "std-G", label: "G", value: "16"),
                StandardStat(id: "std-Car", label: "Car", value: "345"),
                StandardStat(id: "std-RushYds", label: "Rush Yds", value: "2,005"),
                StandardStat(id: "std-RushTD", label: "Rush TD", value: "13"),
                StandardStat(id: "std-RecTgt", label: "Rec/Tgt", value: "33/43"),
                StandardStat(id: "std-RecYds", label: "Rec Yds", value: "278"),
                StandardStat(id: "std-RecTD", label: "Rec TD", value: "2")
            ],
            games: []
        ),
        Player(
            playerId: 36900,
            name: "Ja'Marr Chase",
            team: "CIN",
            position: "WR",
            handedness: "",
            updatedAt: Date(),
            season: 2025,
            playerType: "wr",
            metrics: [
                Metric(id: "chase-rec", label: "Rec", value: "127", percentile: 99, category: .receiving),
                Metric(id: "chase-recyds", label: "Rec Yds", value: "1,708", percentile: 99, category: .receiving),
                Metric(id: "chase-rectd", label: "Rec TD", value: "17", percentile: 99, category: .receiving),
                Metric(id: "chase-yac", label: "YAC", value: "5.9", percentile: 82, category: .receiving),
                Metric(id: "chase-target", label: "Target Share", value: "29.5%", percentile: 97, category: .receiving),
                Metric(id: "chase-epatgt", label: "EPA/Tgt", value: "0.54", percentile: 98, category: .receiving),
                Metric(id: "chase-wopr", label: "WOPR", value: "0.72", percentile: 96, category: .receiving),
                Metric(id: "chase-racr", label: "RACR", value: "1.05", percentile: 80, category: .receiving),
                Metric(id: "chase-catch", label: "Catch%", value: "68.3%", percentile: 72, category: .receiving),
                Metric(id: "chase-sep", label: "Separation", value: "2.9", percentile: 62, category: .receiving)
            ],
            standardStats: [
                StandardStat(id: "std-G", label: "G", value: "17"),
                StandardStat(id: "std-RecTgt", label: "Rec/Tgt", value: "127/186"),
                StandardStat(id: "std-RecYds", label: "Rec Yds", value: "1,708"),
                StandardStat(id: "std-RecTD", label: "Rec TD", value: "17")
            ],
            games: []
        ),
        Player(
            playerId: 36612,
            name: "Micah Parsons",
            team: "DAL",
            position: "LB",
            handedness: "",
            updatedAt: Date(),
            season: 2025,
            playerType: "def",
            metrics: [
                Metric(id: "parsons-tackles", label: "Tackles", value: "43", percentile: 55, category: .defense),
                Metric(id: "parsons-sacks", label: "Sacks", value: "12.0", percentile: 95, category: .defense),
                Metric(id: "parsons-int", label: "INT", value: "0", percentile: 20, category: .defense),
                Metric(id: "parsons-pd", label: "PD", value: "3", percentile: 60, category: .defense),
                Metric(id: "parsons-ff", label: "FF", value: "3", percentile: 90, category: .defense),
                Metric(id: "parsons-tfl", label: "TFL", value: "15", percentile: 92, category: .defense),
                Metric(id: "parsons-qbhits", label: "QB Hits", value: "24", percentile: 96, category: .defense)
            ],
            standardStats: [
                StandardStat(id: "std-G", label: "G", value: "13"),
                StandardStat(id: "std-Tackles", label: "Tackles", value: "43"),
                StandardStat(id: "std-Sacks", label: "Sacks", value: "12.0"),
                StandardStat(id: "std-DefINT", label: "Def INT", value: "0")
            ],
            games: []
        ),
        // 2024 row for the same player id (Mahomes) so year switching has data.
        Player(
            playerId: 33873,
            name: "Patrick Mahomes",
            team: "KC",
            position: "QB",
            handedness: "",
            updatedAt: Date(),
            season: 2024,
            playerType: "qb",
            metrics: [
                Metric(id: "mahomes24-passyds", label: "Pass Yds", value: "3,928", percentile: 84, category: .passing),
                Metric(id: "mahomes24-passtd", label: "Pass TD", value: "26", percentile: 78, category: .passing),
                Metric(id: "mahomes24-rating", label: "Rating", value: "93.5", percentile: 74, category: .passing),
                Metric(id: "mahomes24-epa", label: "EPA/Play", value: "0.11", percentile: 79, category: .passing)
            ],
            standardStats: [
                StandardStat(id: "std-G", label: "G", value: "16"),
                StandardStat(id: "std-CmpAtt", label: "Cmp/Att", value: "392/581"),
                StandardStat(id: "std-PassYds", label: "Pass Yds", value: "3,928"),
                StandardStat(id: "std-PassTD", label: "Pass TD", value: "26"),
                StandardStat(id: "std-INT", label: "INT", value: "11")
            ],
            games: []
        )
    ]
}
#endif
