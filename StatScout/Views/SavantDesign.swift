import SwiftUI

enum GridironPalette {
    static let canvas       = Color(red: 0.94, green: 0.93, blue: 0.89)
    static let surface      = Color(red: 0.99, green: 0.98, blue: 0.94)
    static let surfaceAlt   = Color(red: 0.96, green: 0.95, blue: 0.90)
    static let surfaceSunk  = Color(red: 0.90, green: 0.89, blue: 0.84)
    static let hairline     = Color(red: 0.72, green: 0.71, blue: 0.66)
    static let divider      = Color(red: 0.82, green: 0.81, blue: 0.76)
    static let ink          = Color(red: 0.07, green: 0.09, blue: 0.08)
    static let inkSecondary = Color(red: 0.22, green: 0.25, blue: 0.23)
    static let inkTertiary  = Color(red: 0.39, green: 0.41, blue: 0.38)
    static let inkOnDark    = Color(red: 0.99, green: 0.98, blue: 0.94)
    static let midnight     = Color(red: 0.035, green: 0.08, blue: 0.07)
    static let turf         = Color(red: 0.08, green: 0.36, blue: 0.20)
    static let leather      = Color(red: 0.48, green: 0.23, blue: 0.10)
    static let gold         = Color(red: 0.84, green: 0.63, blue: 0.19)
    static let linkBlue     = Color(red: 0.05, green: 0.32, blue: 0.45)
    static let performanceHigh = Color(red: 0.02, green: 0.46, blue: 0.20)
    static let performanceMid  = Color(red: 0.40, green: 0.38, blue: 0.31)
    static let performanceLow  = Color(red: 0.70, green: 0.20, blue: 0.08)
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
    /// endpoints stay recognisably the same green and rust; only the middle is
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

    private static let hotRGB: (Double, Double, Double) = (0.02, 0.46, 0.20)
    private static let midRGB: (Double, Double, Double) = (0.40, 0.38, 0.31)
    private static let coldRGB: (Double, Double, Double) = (0.70, 0.20, 0.08)

    private static let hotTextRGB: (Double, Double, Double) = (0.06, 0.36, 0.19)
    private static let midTextRGB: (Double, Double, Double) = (0.24, 0.26, 0.24)
    private static let coldTextRGB: (Double, Double, Double) = (0.55, 0.20, 0.10)

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let r = a.0 + (b.0 - a.0) * t
        let g = a.1 + (b.1 - a.1) * t
        let bl = a.2 + (b.2 - a.2) * t
        return Color(red: r, green: g, blue: bl)
    }
}

enum GridironType {
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

enum GridironGeo {
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

/// NFL team primary colors, keyed by nflverse abbreviation.
enum NFLTeamColor {
    static let primary: [String: Color] = [
        "ARI": Color(red: 0.59, green: 0.14, blue: 0.25),
        "ATL": Color(red: 0.65, green: 0.10, blue: 0.19),
        "BAL": Color(red: 0.14, green: 0.09, blue: 0.45),
        "BUF": Color(red: 0.00, green: 0.20, blue: 0.55),
        "CAR": Color(red: 0.00, green: 0.52, blue: 0.79),
        "CHI": Color(red: 0.04, green: 0.09, blue: 0.16),
        "CIN": Color(red: 0.98, green: 0.31, blue: 0.08),
        "CLE": Color(red: 0.34, green: 0.18, blue: 0.05),
        "DAL": Color(red: 0.02, green: 0.12, blue: 0.26),
        "DEN": Color(red: 0.98, green: 0.31, blue: 0.08),
        "DET": Color(red: 0.00, green: 0.46, blue: 0.71),
        "GB":  Color(red: 0.13, green: 0.22, blue: 0.19),
        "HOU": Color(red: 0.01, green: 0.13, blue: 0.18),
        "IND": Color(red: 0.00, green: 0.17, blue: 0.37),
        "JAX": Color(red: 0.00, green: 0.40, blue: 0.47),
        "KC":  Color(red: 0.89, green: 0.09, blue: 0.22),
        "LA":  Color(red: 0.00, green: 0.21, blue: 0.58),
        "LAC": Color(red: 0.00, green: 0.50, blue: 0.78),
        "LV":  Color(red: 0.10, green: 0.10, blue: 0.11),
        "MIA": Color(red: 0.00, green: 0.56, blue: 0.59),
        "MIN": Color(red: 0.31, green: 0.15, blue: 0.51),
        "NE":  Color(red: 0.00, green: 0.13, blue: 0.27),
        "NO":  Color(red: 0.62, green: 0.53, blue: 0.36),
        "NYG": Color(red: 0.04, green: 0.13, blue: 0.40),
        "NYJ": Color(red: 0.07, green: 0.34, blue: 0.25),
        "PHI": Color(red: 0.00, green: 0.30, blue: 0.33),
        "PIT": Color(red: 0.98, green: 0.71, blue: 0.07),
        "SEA": Color(red: 0.00, green: 0.13, blue: 0.27),
        "SF":  Color(red: 0.67, green: 0.00, blue: 0.00),
        "TB":  Color(red: 0.84, green: 0.04, blue: 0.04),
        "TEN": Color(red: 0.05, green: 0.14, blue: 0.25),
        "WAS": Color(red: 0.35, green: 0.08, blue: 0.08)
    ]
    static func color(_ abbr: String) -> Color { primary[normalizedTeamAbbreviation(abbr)] ?? GridironPalette.inkTertiary }
}

/// NFL team abbreviations in nflverse form. Shared by the Teams grid and switcher.
let nflTeamAbbreviations: [String] = [
    "ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN",
    "DET", "GB", "HOU", "IND", "JAX", "KC", "LA", "LAC", "LV", "MIA",
    "MIN", "NE", "NO", "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB",
    "TEN", "WAS"
]

enum NFLConference: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "All"
    case afc = "AFC"
    case nfc = "NFC"

    var id: String { rawValue }

    func contains(team: String) -> Bool {
        let abbr = normalizedTeamAbbreviation(team)
        switch self {
        case .all:
            return true
        case .afc:
            return Self.afcTeams.contains(abbr)
        case .nfc:
            return Self.nfcTeams.contains(abbr)
        }
    }

    private static let afcTeams: Set<String> = [
        "BAL", "BUF", "CIN", "CLE", "DEN", "HOU", "IND", "JAX",
        "KC", "LAC", "LV", "MIA", "NE", "NYJ", "PIT", "TEN",
    ]

    private static let nfcTeams: Set<String> = [
        "ARI", "ATL", "CAR", "CHI", "DAL", "DET", "GB", "LA",
        "MIN", "NO", "NYG", "PHI", "SEA", "SF", "TB", "WAS",
    ]
}

func normalizedTeamAbbreviation(_ team: String) -> String {
    let key = team.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let aliases: [String: String] = [
        // Legacy / alternate abbreviations that map to the current nflverse code.
        "OAK": "LV", "LVR": "LV", "SD": "LAC", "SDG": "LAC", "STL": "LA",
        "LAR": "LA", "WSH": "WAS", "WFT": "WAS", "JAC": "JAX", "GNB": "GB",
        "KAN": "KC", "NWE": "NE", "NOR": "NO", "SFO": "SF", "TAM": "TB",
        "ARZ": "ARI", "CLV": "CLE", "HST": "HOU", "BLT": "BAL",
        // Full names → abbreviation.
        "ARIZONA CARDINALS": "ARI", "ATLANTA FALCONS": "ATL", "BALTIMORE RAVENS": "BAL",
        "BUFFALO BILLS": "BUF", "CAROLINA PANTHERS": "CAR", "CHICAGO BEARS": "CHI",
        "CINCINNATI BENGALS": "CIN", "CLEVELAND BROWNS": "CLE", "DALLAS COWBOYS": "DAL",
        "DENVER BRONCOS": "DEN", "DETROIT LIONS": "DET", "GREEN BAY PACKERS": "GB",
        "HOUSTON TEXANS": "HOU", "INDIANAPOLIS COLTS": "IND", "JACKSONVILLE JAGUARS": "JAX",
        "KANSAS CITY CHIEFS": "KC", "LOS ANGELES RAMS": "LA", "LOS ANGELES CHARGERS": "LAC",
        "LAS VEGAS RAIDERS": "LV", "MIAMI DOLPHINS": "MIA", "MINNESOTA VIKINGS": "MIN",
        "NEW ENGLAND PATRIOTS": "NE", "NEW ORLEANS SAINTS": "NO", "NEW YORK GIANTS": "NYG",
        "NEW YORK JETS": "NYJ", "PHILADELPHIA EAGLES": "PHI", "PITTSBURGH STEELERS": "PIT",
        "SEATTLE SEAHAWKS": "SEA", "SAN FRANCISCO 49ERS": "SF", "TAMPA BAY BUCCANEERS": "TB",
        "TENNESSEE TITANS": "TEN", "WASHINGTON COMMANDERS": "WAS"
    ]
    return aliases[key] ?? key
}

func teamFullName(_ abbr: String) -> String {
    let map: [String: String] = [
        "ARI": "Arizona Cardinals", "ATL": "Atlanta Falcons", "BAL": "Baltimore Ravens",
        "BUF": "Buffalo Bills", "CAR": "Carolina Panthers", "CHI": "Chicago Bears",
        "CIN": "Cincinnati Bengals", "CLE": "Cleveland Browns", "DAL": "Dallas Cowboys",
        "DEN": "Denver Broncos", "DET": "Detroit Lions", "GB": "Green Bay Packers",
        "HOU": "Houston Texans", "IND": "Indianapolis Colts", "JAX": "Jacksonville Jaguars",
        "KC": "Kansas City Chiefs", "LA": "Los Angeles Rams", "LAC": "Los Angeles Chargers",
        "LV": "Las Vegas Raiders", "MIA": "Miami Dolphins", "MIN": "Minnesota Vikings",
        "NE": "New England Patriots", "NO": "New Orleans Saints", "NYG": "New York Giants",
        "NYJ": "New York Jets", "PHI": "Philadelphia Eagles", "PIT": "Pittsburgh Steelers",
        "SEA": "Seattle Seahawks", "SF": "San Francisco 49ers", "TB": "Tampa Bay Buccaneers",
        "TEN": "Tennessee Titans", "WAS": "Washington Commanders"
    ]
    let normalized = normalizedTeamAbbreviation(abbr)
    return map[normalized] ?? abbr
}

struct StatScoutTheme {
    static let background = LinearGradient(colors: [GridironPalette.canvas, GridironPalette.canvas], startPoint: .top, endPoint: .bottom)
    static let card       = GridironPalette.surface
    static let stroke     = GridironPalette.hairline
    static let accent     = GridironPalette.turf
    static let hot        = GridironPalette.performanceHigh
    static let performanceLow = GridironPalette.performanceLow
    static let turf       = GridironPalette.turf
    static let leather    = GridironPalette.leather
    static let sky        = Color(red: 0.30, green: 0.55, blue: 0.85)

    static func percentileColor(_ percentile: Int) -> Color {
        GridironPalette.color(forPercentile: percentile)
    }
}
