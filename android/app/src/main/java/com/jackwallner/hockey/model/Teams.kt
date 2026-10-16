package com.jackwallner.hockey.model

/** The 32 current NHL clubs. Shared by the Teams grid and switcher. */
val leagueTeamAbbreviations: List<String> = listOf(
    "ANA", "BOS", "BUF", "CGY", "CAR", "CHI", "COL", "CBJ", "DAL", "DET",
    "EDM", "FLA", "LAK", "MIN", "MTL", "NSH", "NJD", "NYI", "NYR", "OTT",
    "PHI", "PIT", "SJS", "SEA", "STL", "TBL", "TOR", "UTA", "VAN", "VGK",
    "WSH", "WPG",
)

enum class LeagueConference(val label: String) {
    ALL("All"), EAST("East"), WEST("West");

    fun contains(team: String): Boolean {
        val abbr = normalizedTeamAbbreviation(team)
        return when (this) {
            ALL -> true
            EAST -> abbr in EAST_TEAMS
            WEST -> abbr in WEST_TEAMS
        }
    }

    private companion object {
        val EAST_TEAMS = setOf(
            "BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR",
            "CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH",
        )
        val WEST_TEAMS = setOf(
            "CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG",
            "ANA", "CGY", "EDM", "LAK", "SJS", "SEA", "VAN", "VGK",
        )
    }
}

/** Division for the Teams grid headers. */
enum class LeagueDivision(val label: String, val teams: List<String>) {
    ATLANTIC("Atlantic", listOf("BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR")),
    METROPOLITAN("Metropolitan", listOf("CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH")),
    CENTRAL("Central", listOf("CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG")),
    PACIFIC("Pacific", listOf("ANA", "CGY", "EDM", "LAK", "SJS", "SEA", "VAN", "VGK"));

    val conference: LeagueConference
        get() = if (this == ATLANTIC || this == METROPOLITAN) LeagueConference.EAST else LeagueConference.WEST

    companion object {
        fun of(team: String): LeagueDivision? {
            val abbr = normalizedTeamAbbreviation(team)
            return entries.firstOrNull { abbr in it.teams }
        }
    }
}

private val TEAM_ALIASES = mapOf(
    // Alternate codes seen in NHL feeds and box scores.
    "L.A" to "LAK", "LA" to "LAK", "N.J" to "NJD", "NJ" to "NJD", "S.J" to "SJS", "SJ" to "SJS",
    "T.B" to "TBL", "TB" to "TBL", "PHX" to "ARI", "WAS" to "WSH", "VEG" to "VGK", "LV" to "VGK",
    "MON" to "MTL", "CLB" to "CBJ", "NAS" to "NSH", "WPJ" to "WPG", "CAL" to "CGY",
    // Full names to abbreviation.
    "ANAHEIM DUCKS" to "ANA", "ARIZONA COYOTES" to "ARI", "ATLANTA THRASHERS" to "ATL",
    "BOSTON BRUINS" to "BOS", "BUFFALO SABRES" to "BUF", "CALGARY FLAMES" to "CGY",
    "CAROLINA HURRICANES" to "CAR", "CHICAGO BLACKHAWKS" to "CHI", "COLORADO AVALANCHE" to "COL",
    "COLUMBUS BLUE JACKETS" to "CBJ", "DALLAS STARS" to "DAL", "DETROIT RED WINGS" to "DET",
    "EDMONTON OILERS" to "EDM", "FLORIDA PANTHERS" to "FLA", "LOS ANGELES KINGS" to "LAK",
    "MINNESOTA WILD" to "MIN", "MONTREAL CANADIENS" to "MTL", "NASHVILLE PREDATORS" to "NSH",
    "NEW JERSEY DEVILS" to "NJD", "NEW YORK ISLANDERS" to "NYI", "NEW YORK RANGERS" to "NYR",
    "OTTAWA SENATORS" to "OTT", "PHILADELPHIA FLYERS" to "PHI", "PITTSBURGH PENGUINS" to "PIT",
    "SAN JOSE SHARKS" to "SJS", "SEATTLE KRAKEN" to "SEA", "ST. LOUIS BLUES" to "STL",
    "ST LOUIS BLUES" to "STL", "TAMPA BAY LIGHTNING" to "TBL", "TORONTO MAPLE LEAFS" to "TOR",
    "UTAH MAMMOTH" to "UTA", "UTAH HOCKEY CLUB" to "UTA", "VANCOUVER CANUCKS" to "VAN",
    "VEGAS GOLDEN KNIGHTS" to "VGK", "WASHINGTON CAPITALS" to "WSH", "WINNIPEG JETS" to "WPG",
)

private val TEAM_NAMES = mapOf(
    "ANA" to "Anaheim Ducks", "ARI" to "Arizona Coyotes", "ATL" to "Atlanta Thrashers",
    "BOS" to "Boston Bruins", "BUF" to "Buffalo Sabres", "CGY" to "Calgary Flames",
    "CAR" to "Carolina Hurricanes", "CHI" to "Chicago Blackhawks", "COL" to "Colorado Avalanche",
    "CBJ" to "Columbus Blue Jackets", "DAL" to "Dallas Stars", "DET" to "Detroit Red Wings",
    "EDM" to "Edmonton Oilers", "FLA" to "Florida Panthers", "LAK" to "Los Angeles Kings",
    "MIN" to "Minnesota Wild", "MTL" to "Montreal Canadiens", "NSH" to "Nashville Predators",
    "NJD" to "New Jersey Devils", "NYI" to "New York Islanders", "NYR" to "New York Rangers",
    "OTT" to "Ottawa Senators", "PHI" to "Philadelphia Flyers", "PIT" to "Pittsburgh Penguins",
    "SJS" to "San Jose Sharks", "SEA" to "Seattle Kraken", "STL" to "St. Louis Blues",
    "TBL" to "Tampa Bay Lightning", "TOR" to "Toronto Maple Leafs", "UTA" to "Utah Mammoth",
    "VAN" to "Vancouver Canucks", "VGK" to "Vegas Golden Knights", "WSH" to "Washington Capitals",
    "WPG" to "Winnipeg Jets",
)

fun normalizedTeamAbbreviation(team: String): String {
    val key = team.trim().uppercase()
    return TEAM_ALIASES[key] ?: key
}

fun teamFullName(abbr: String): String = TEAM_NAMES[normalizedTeamAbbreviation(abbr)] ?: abbr

private val TWO_WORD_CITIES = listOf("Los Angeles", "New Jersey", "New York", "San Jose", "St. Louis", "Tampa Bay")

/** Short club name for tight columns: "Oilers", "Maple Leafs". */
fun teamNickname(abbr: String): String {
    val full = teamFullName(abbr)
    for (city in TWO_WORD_CITIES) if (full.startsWith("$city ")) return full.drop(city.length + 1)
    val parts = full.split(" ", limit = 2)
    return parts.lastOrNull() ?: full
}

private fun isUnsignedTeam(abbr: String): Boolean {
    val trimmed = abbr.trim().uppercase()
    return trimmed.isEmpty() || trimmed == "TBD" || trimmed == "—" || trimmed == "-"
}

fun displayTeamAbbr(abbr: String): String = if (isUnsignedTeam(abbr)) "FA" else abbr

fun displayTeamFullName(abbr: String): String = if (isUnsignedTeam(abbr)) "Free Agent" else teamFullName(abbr)
