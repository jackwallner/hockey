import SwiftUI

enum RinkPalette {
    // Ice sheet: cool near-white surfaces on a pale blue-grey canvas, deep
    // navy ink. The percentile ramp is the one hockey readers already know
    // from NHL EDGE and Baseball Savant: red is hot, blue is cold.
    static let canvas       = Color(red: 0.92, green: 0.94, blue: 0.96)
    static let surface      = Color(red: 0.99, green: 0.99, blue: 1.00)
    static let surfaceAlt   = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let surfaceSunk  = Color(red: 0.88, green: 0.90, blue: 0.93)
    static let hairline     = Color(red: 0.68, green: 0.72, blue: 0.77)
    static let divider      = Color(red: 0.80, green: 0.83, blue: 0.87)
    static let ink          = Color(red: 0.05, green: 0.09, blue: 0.16)
    static let inkSecondary = Color(red: 0.22, green: 0.26, blue: 0.33)
    static let inkTertiary  = Color(red: 0.40, green: 0.44, blue: 0.50)
    static let inkOnDark    = Color(red: 0.97, green: 0.98, blue: 1.00)
    static let midnight     = Color(red: 0.02, green: 0.07, blue: 0.16)
    static let turf         = Color(red: 0.04, green: 0.25, blue: 0.55)
    static let leather      = Color(red: 0.75, green: 0.14, blue: 0.16)
    static let gold         = Color(red: 0.84, green: 0.63, blue: 0.19)
    static let linkBlue     = Color(red: 0.04, green: 0.30, blue: 0.58)
    static let performanceHigh = Color(red: 0.78, green: 0.13, blue: 0.14)
    static let performanceMid  = Color(red: 0.42, green: 0.44, blue: 0.48)
    static let performanceLow  = Color(red: 0.12, green: 0.33, blue: 0.72)
    static let up           = performanceHigh
    static let down         = performanceLow
    static let flat         = inkTertiary

    static func color(forPercentile p: Int) -> Color {
        let t = max(0.0, min(1.0, Double(p) / 100.0))
        if t < 0.5 {
            return lerp(coldRGB, midRGB, t * 2.0)
        } else {
            return lerp(midRGB, hotRGB, (t - 0.5) * 2.0)
        }
    }

    /// Percentile colour for *text* on a light surface.
    ///
    /// The fill ramp passes through a pale sand at the 50th percentile, which
    /// is right for a bar sitting on the cream card and unreadable as type: an
    /// average player's number came out the same value as the background. The
    /// endpoints stay recognisably the same red and blue; only the middle is
    /// pulled down to a dark neutral, so every value on the board clears
    /// contrast while the hot/cold reading survives.
    static func textColor(forPercentile p: Int) -> Color {
        let t = max(0.0, min(1.0, Double(p) / 100.0))
        if t < 0.5 {
            return lerp(coldTextRGB, midTextRGB, t * 2.0)
        } else {
            return lerp(midTextRGB, hotTextRGB, (t - 0.5) * 2.0)
        }
    }

    private static let hotRGB: (Double, Double, Double) = (0.78, 0.13, 0.14)
    private static let midRGB: (Double, Double, Double) = (0.42, 0.44, 0.48)
    private static let coldRGB: (Double, Double, Double) = (0.12, 0.33, 0.72)

    private static let hotTextRGB: (Double, Double, Double) = (0.62, 0.10, 0.12)
    private static let midTextRGB: (Double, Double, Double) = (0.24, 0.27, 0.32)
    private static let coldTextRGB: (Double, Double, Double) = (0.10, 0.27, 0.60)

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let r = a.0 + (b.0 - a.0) * t
        let g = a.1 + (b.1 - a.1) * t
        let bl = a.2 + (b.2 - a.2) * t
        return Color(red: r, green: g, blue: bl)
    }
}

enum RinkType {
    // SF Pro is the single language face throughout the app. Semantic styles
    // keep the hierarchy coherent and participate in Dynamic Type.
    //
    // Stock width, deliberately. Build 16 shipped these condensed to buy back
    // the horizontal budget the ported-from-baseball column widths (42pt rank,
    // 44pt team, 48pt value) were measured against in RobotoCondensed, but the
    // condensed face read worse than the mild squeeze it fixed. If a column
    // needs more room, widen that column rather than narrowing every glyph.
    static let playerName   = Font.system(.title2, design: .default, weight: .bold)
    static let pageTitle    = Font.system(.title3, design: .default, weight: .bold)
    static let sectionTitle = Font.system(.caption, design: .default, weight: .bold)
    static let cardTitle    = Font.system(.headline, design: .default, weight: .semibold)
    static let body         = Font.system(.subheadline, design: .default)
    static let bodyBold     = Font.system(.subheadline, design: .default, weight: .semibold)
    static let small        = Font.system(.caption, design: .default)
    static let smallBold    = Font.system(.caption, design: .default, weight: .semibold)
    static let micro        = Font.system(.caption2, design: .default, weight: .semibold)

    // Values and ranks are SF Pro too, with tabular digits so columns still
    // line up. They used to be SF Mono, which put a second typeface on every
    // row: a name in SF Pro beside a number in Mono, and the few titles that
    // borrowed a stat style ("Full Player Scouting") read as code.
    static let statHero  = Font.system(.title, design: .default, weight: .bold).monospacedDigit()
    static let statLarge = Font.system(.title3, design: .default, weight: .bold).monospacedDigit()
    static let statMed   = Font.system(.subheadline, design: .default, weight: .semibold).monospacedDigit()
    static let statSmall = Font.system(.caption, design: .default, weight: .medium).monospacedDigit()
}

enum RinkGeo {
    static let radiusCard: CGFloat = 4
    static let radiusBadge: CGFloat = 2
    static let hairline: CGFloat = 0.5
    static let barTrack: CGFloat = 4
    static let barMarker: CGFloat = 12
    static let padInline: CGFloat = 12
    static let padCard: CGFloat = 16
    static let padPage: CGFloat = 16
    static let padSection: CGFloat = 24
    static let rowHeight: CGFloat = 44
    static let rowHeightHeader: CGFloat = 28
    /// Breathing room between the underlined position tabs and the first row of
    /// inline controls under them. The tabs carry their own underline plus a
    /// hairline, so a control butted straight up against them reads as part of
    /// the tab strip rather than as the board's own filter.
    static let controlRowGap: CGFloat = 10
}

/// NHL team primary colors, keyed by the NHL / MoneyPuck abbreviation.
enum TeamColor {
    static let primary: [String: Color] = [
        "ANA": Color(red: 0.96, green: 0.48, blue: 0.22),
        "ARI": Color(red: 0.55, green: 0.15, blue: 0.20),
        "ATL": Color(red: 0.04, green: 0.14, blue: 0.32),
        "BOS": Color(red: 0.95, green: 0.66, blue: 0.08),
        "BUF": Color(red: 0.00, green: 0.19, blue: 0.53),
        "CGY": Color(red: 0.82, green: 0.00, blue: 0.11),
        "CAR": Color(red: 0.81, green: 0.07, blue: 0.15),
        "CHI": Color(red: 0.81, green: 0.04, blue: 0.17),
        "COL": Color(red: 0.44, green: 0.15, blue: 0.24),
        "CBJ": Color(red: 0.00, green: 0.15, blue: 0.33),
        "DAL": Color(red: 0.00, green: 0.41, blue: 0.28),
        "DET": Color(red: 0.81, green: 0.07, blue: 0.15),
        "EDM": Color(red: 0.02, green: 0.12, blue: 0.26),
        "FLA": Color(red: 0.78, green: 0.06, blue: 0.18),
        "LAK": Color(red: 0.11, green: 0.11, blue: 0.12),
        "MIN": Color(red: 0.08, green: 0.28, blue: 0.20),
        "MTL": Color(red: 0.69, green: 0.12, blue: 0.18),
        "NSH": Color(red: 0.95, green: 0.66, blue: 0.08),
        "NJD": Color(red: 0.81, green: 0.07, blue: 0.15),
        "NYI": Color(red: 0.00, green: 0.33, blue: 0.61),
        "NYR": Color(red: 0.00, green: 0.22, blue: 0.66),
        "OTT": Color(red: 0.85, green: 0.10, blue: 0.20),
        "PHI": Color(red: 0.97, green: 0.29, blue: 0.01),
        "PIT": Color(red: 0.93, green: 0.68, blue: 0.08),
        "SJS": Color(red: 0.00, green: 0.43, blue: 0.46),
        "SEA": Color(red: 0.00, green: 0.09, blue: 0.16),
        "STL": Color(red: 0.00, green: 0.18, blue: 0.53),
        "TBL": Color(red: 0.00, green: 0.16, blue: 0.41),
        "TOR": Color(red: 0.00, green: 0.13, blue: 0.36),
        "UTA": Color(red: 0.42, green: 0.67, blue: 0.89),
        "VAN": Color(red: 0.00, green: 0.13, blue: 0.36),
        "VGK": Color(red: 0.71, green: 0.59, blue: 0.35),
        "WSH": Color(red: 0.78, green: 0.06, blue: 0.18),
        "WPG": Color(red: 0.02, green: 0.12, blue: 0.26)
    ]
    static func color(_ abbr: String) -> Color { primary[normalizedTeamAbbreviation(abbr)] ?? RinkPalette.inkTertiary }
}

/// The 32 current NHL clubs. Shared by the Teams grid and switcher.
let leagueTeamAbbreviations: [String] = [
    "ANA", "BOS", "BUF", "CGY", "CAR", "CHI", "COL", "CBJ", "DAL", "DET",
    "EDM", "FLA", "LAK", "MIN", "MTL", "NSH", "NJD", "NYI", "NYR", "OTT",
    "PHI", "PIT", "SJS", "SEA", "STL", "TBL", "TOR", "UTA", "VAN", "VGK",
    "WSH", "WPG"
]

enum LeagueConference: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "All"
    case east = "East"
    case west = "West"

    var id: String { rawValue }

    func contains(team: String) -> Bool {
        let abbr = normalizedTeamAbbreviation(team)
        switch self {
        case .all:
            return true
        case .east:
            return Self.eastTeams.contains(abbr)
        case .west:
            return Self.westTeams.contains(abbr)
        }
    }

    private static let eastTeams: Set<String> = [
        "BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR",
        "CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH",
    ]

    private static let westTeams: Set<String> = [
        "CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG",
        "ANA", "CGY", "EDM", "LAK", "SJS", "SEA", "VAN", "VGK",
    ]
}

/// Division for the Teams grid headers.
enum LeagueDivision: String, CaseIterable, Identifiable, Sendable {
    case atlantic = "Atlantic"
    case metropolitan = "Metropolitan"
    case central = "Central"
    case pacific = "Pacific"

    var id: String { rawValue }

    var conference: LeagueConference {
        switch self {
        case .atlantic, .metropolitan: return .east
        case .central, .pacific: return .west
        }
    }

    var teams: [String] {
        switch self {
        case .atlantic: return ["BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR"]
        case .metropolitan: return ["CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH"]
        case .central: return ["CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG"]
        case .pacific: return ["ANA", "CGY", "EDM", "LAK", "SJS", "SEA", "VAN", "VGK"]
        }
    }

    static func division(of team: String) -> LeagueDivision? {
        let abbr = normalizedTeamAbbreviation(team)
        return allCases.first { $0.teams.contains(abbr) }
    }
}

func normalizedTeamAbbreviation(_ team: String) -> String {
    let key = team.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let aliases: [String: String] = [
        // Alternate codes seen in NHL feeds and box scores.
        "L.A": "LAK", "LA": "LAK", "N.J": "NJD", "NJ": "NJD", "S.J": "SJS", "SJ": "SJS",
        "T.B": "TBL", "TB": "TBL", "PHX": "ARI", "WAS": "WSH", "VEG": "VGK", "LV": "VGK",
        "MON": "MTL", "CLB": "CBJ", "NAS": "NSH", "WPJ": "WPG", "CAL": "CGY",
        // Full names to abbreviation.
        "ANAHEIM DUCKS": "ANA", "ARIZONA COYOTES": "ARI", "ATLANTA THRASHERS": "ATL",
        "BOSTON BRUINS": "BOS", "BUFFALO SABRES": "BUF", "CALGARY FLAMES": "CGY",
        "CAROLINA HURRICANES": "CAR", "CHICAGO BLACKHAWKS": "CHI", "COLORADO AVALANCHE": "COL",
        "COLUMBUS BLUE JACKETS": "CBJ", "DALLAS STARS": "DAL", "DETROIT RED WINGS": "DET",
        "EDMONTON OILERS": "EDM", "FLORIDA PANTHERS": "FLA", "LOS ANGELES KINGS": "LAK",
        "MINNESOTA WILD": "MIN", "MONTREAL CANADIENS": "MTL", "NASHVILLE PREDATORS": "NSH",
        "NEW JERSEY DEVILS": "NJD", "NEW YORK ISLANDERS": "NYI", "NEW YORK RANGERS": "NYR",
        "OTTAWA SENATORS": "OTT", "PHILADELPHIA FLYERS": "PHI", "PITTSBURGH PENGUINS": "PIT",
        "SAN JOSE SHARKS": "SJS", "SEATTLE KRAKEN": "SEA", "ST. LOUIS BLUES": "STL",
        "ST LOUIS BLUES": "STL", "TAMPA BAY LIGHTNING": "TBL", "TORONTO MAPLE LEAFS": "TOR",
        "UTAH MAMMOTH": "UTA", "UTAH HOCKEY CLUB": "UTA", "VANCOUVER CANUCKS": "VAN",
        "VEGAS GOLDEN KNIGHTS": "VGK", "WASHINGTON CAPITALS": "WSH", "WINNIPEG JETS": "WPG"
    ]
    return aliases[key] ?? key
}

func teamFullName(_ abbr: String) -> String {
    let map: [String: String] = [
        "ANA": "Anaheim Ducks", "ARI": "Arizona Coyotes", "ATL": "Atlanta Thrashers",
        "BOS": "Boston Bruins", "BUF": "Buffalo Sabres", "CGY": "Calgary Flames",
        "CAR": "Carolina Hurricanes", "CHI": "Chicago Blackhawks", "COL": "Colorado Avalanche",
        "CBJ": "Columbus Blue Jackets", "DAL": "Dallas Stars", "DET": "Detroit Red Wings",
        "EDM": "Edmonton Oilers", "FLA": "Florida Panthers", "LAK": "Los Angeles Kings",
        "MIN": "Minnesota Wild", "MTL": "Montreal Canadiens", "NSH": "Nashville Predators",
        "NJD": "New Jersey Devils", "NYI": "New York Islanders", "NYR": "New York Rangers",
        "OTT": "Ottawa Senators", "PHI": "Philadelphia Flyers", "PIT": "Pittsburgh Penguins",
        "SJS": "San Jose Sharks", "SEA": "Seattle Kraken", "STL": "St. Louis Blues",
        "TBL": "Tampa Bay Lightning", "TOR": "Toronto Maple Leafs", "UTA": "Utah Mammoth",
        "VAN": "Vancouver Canucks", "VGK": "Vegas Golden Knights", "WSH": "Washington Capitals",
        "WPG": "Winnipeg Jets"
    ]
    let normalized = normalizedTeamAbbreviation(abbr)
    return map[normalized] ?? abbr
}

/// Short club name for tight columns: "Oilers", "Maple Leafs".
func teamNickname(_ abbr: String) -> String {
    let full = teamFullName(abbr)
    let twoWordCities: Set<String> = ["Los Angeles", "New Jersey", "New York", "San Jose", "St. Louis", "Tampa Bay"]
    for city in twoWordCities where full.hasPrefix(city + " ") {
        return String(full.dropFirst(city.count + 1))
    }
    return full.split(separator: " ", maxSplits: 1).last.map(String.init) ?? full
}

struct StatScoutTheme {
    static let background = LinearGradient(colors: [RinkPalette.canvas, RinkPalette.canvas], startPoint: .top, endPoint: .bottom)
    static let card       = RinkPalette.surface
    static let stroke     = RinkPalette.hairline
    static let accent     = RinkPalette.turf
    static let hot        = RinkPalette.performanceHigh
    static let performanceLow = RinkPalette.performanceLow
    static let turf       = RinkPalette.turf
    static let leather    = RinkPalette.leather
    static let sky        = Color(red: 0.30, green: 0.55, blue: 0.85)

    static func percentileColor(_ percentile: Int) -> Color {
        RinkPalette.color(forPercentile: percentile)
    }
}
