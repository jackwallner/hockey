package com.jackwallner.hockey.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.hockey.model.normalizedTeamAbbreviation

private fun rgb(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())

/** The iOS `RinkPalette`, value for value. The app is light-only, like iOS. */
object RinkPalette {
    val canvas = rgb(0.92, 0.94, 0.96)
    val surface = rgb(0.99, 0.99, 1.00)
    val surfaceAlt = rgb(0.95, 0.96, 0.98)
    val surfaceSunk = rgb(0.88, 0.90, 0.93)
    val hairline = rgb(0.68, 0.72, 0.77)
    val divider = rgb(0.80, 0.83, 0.87)
    val ink = rgb(0.05, 0.09, 0.16)
    val inkSecondary = rgb(0.22, 0.26, 0.33)
    val inkTertiary = rgb(0.40, 0.44, 0.50)
    val inkOnDark = rgb(0.97, 0.98, 1.00)
    val midnight = rgb(0.02, 0.07, 0.16)
    val turf = rgb(0.04, 0.25, 0.55)
    val leather = rgb(0.75, 0.14, 0.16)
    val gold = rgb(0.84, 0.63, 0.19)
    val linkBlue = rgb(0.04, 0.30, 0.58)
    val performanceHigh = rgb(0.78, 0.13, 0.14)
    val performanceMid = rgb(0.42, 0.44, 0.48)
    val performanceLow = rgb(0.12, 0.33, 0.72)

    /** iOS colours a team's result red for a win and blue for anything else. */
    fun resultColor(result: String?): Color = if (result == "W") performanceHigh else performanceLow
    val up = performanceHigh
    val down = performanceLow
    val flat = inkTertiary
    val sky = rgb(0.30, 0.55, 0.85)

    private val hot = Triple(0.78, 0.13, 0.14)
    private val mid = Triple(0.42, 0.44, 0.48)
    private val cold = Triple(0.12, 0.33, 0.72)
    private val hotText = Triple(0.62, 0.10, 0.12)
    private val midText = Triple(0.24, 0.27, 0.32)
    private val coldText = Triple(0.10, 0.27, 0.60)

    fun color(percentile: Int): Color {
        val t = (percentile / 100.0).coerceIn(0.0, 1.0)
        return if (t < 0.5) lerp(cold, mid, t * 2) else lerp(mid, hot, (t - 0.5) * 2)
    }

    /** Percentile colour for type on a light surface: the middle is pulled dark so every value clears contrast. */
    fun textColor(percentile: Int): Color {
        val t = (percentile / 100.0).coerceIn(0.0, 1.0)
        return if (t < 0.5) lerp(coldText, midText, t * 2) else lerp(midText, hotText, (t - 0.5) * 2)
    }

    private fun lerp(a: Triple<Double, Double, Double>, b: Triple<Double, Double, Double>, t: Double) =
        rgb(a.first + (b.first - a.first) * t, a.second + (b.second - a.second) * t, a.third + (b.third - a.third) * t)
}

/**
 * iOS semantic styles at their default Dynamic Type sizes, in the platform
 * face. Values use tabular digits so columns line up.
 */
object RinkType {
    private val face = FontFamily.Default
    private const val TABULAR = "tnum"

    val playerName = TextStyle(fontFamily = face, fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold)
    val pageTitle = TextStyle(fontFamily = face, fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.Bold)
    val sectionTitle = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold)
    val cardTitle = TextStyle(fontFamily = face, fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontFamily = face, fontSize = 15.sp, lineHeight = 20.sp)
    val bodyBold = TextStyle(fontFamily = face, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
    val small = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp)
    val smallBold = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold)
    val micro = TextStyle(fontFamily = face, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.SemiBold)
    /** Billed amount directly above a purchase button: one step above the CTA label, outweighed by nothing in a purchase surface. */
    val priceLead = TextStyle(fontFamily = face, fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold)

    val statHero = TextStyle(fontFamily = face, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR)
    val statLarge = TextStyle(fontFamily = face, fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR)
    val statMed = TextStyle(fontFamily = face, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TABULAR)
    val statSmall = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = TABULAR)
}

object RinkGeo {
    val radiusCard = 4.dp
    val radiusBadge = 2.dp
    val hairline = 0.5.dp
    val barTrack = 4.dp
    val barMarker = 12.dp
    val padInline = 12.dp
    val padCard = 16.dp
    val padPage = 16.dp
    val padSection = 24.dp
    val rowHeight = 44.dp
    val rowHeightHeader = 28.dp
    val controlRowGap = 10.dp
    /** Android's minimum touch target. */
    val touchTarget = 48.dp
}

/** NHL team primary colours, keyed by the NHL / MoneyPuck abbreviation. */
object TeamColor {
    private val primary = mapOf(
        "ANA" to rgb(0.96, 0.48, 0.22), "ARI" to rgb(0.55, 0.15, 0.20), "ATL" to rgb(0.04, 0.14, 0.32),
        "BOS" to rgb(0.95, 0.66, 0.08), "BUF" to rgb(0.00, 0.19, 0.53), "CGY" to rgb(0.82, 0.00, 0.11),
        "CAR" to rgb(0.81, 0.07, 0.15), "CHI" to rgb(0.81, 0.04, 0.17), "COL" to rgb(0.44, 0.15, 0.24),
        "CBJ" to rgb(0.00, 0.15, 0.33), "DAL" to rgb(0.00, 0.41, 0.28), "DET" to rgb(0.81, 0.07, 0.15),
        "EDM" to rgb(0.02, 0.12, 0.26), "FLA" to rgb(0.78, 0.06, 0.18), "LAK" to rgb(0.11, 0.11, 0.12),
        "MIN" to rgb(0.08, 0.28, 0.20), "MTL" to rgb(0.69, 0.12, 0.18), "NSH" to rgb(0.95, 0.66, 0.08),
        "NJD" to rgb(0.81, 0.07, 0.15), "NYI" to rgb(0.00, 0.33, 0.61), "NYR" to rgb(0.00, 0.22, 0.66),
        "OTT" to rgb(0.85, 0.10, 0.20), "PHI" to rgb(0.97, 0.29, 0.01), "PIT" to rgb(0.93, 0.68, 0.08),
        "SJS" to rgb(0.00, 0.43, 0.46), "SEA" to rgb(0.00, 0.09, 0.16), "STL" to rgb(0.00, 0.18, 0.53),
        "TBL" to rgb(0.00, 0.16, 0.41), "TOR" to rgb(0.00, 0.13, 0.36), "UTA" to rgb(0.42, 0.67, 0.89),
        "VAN" to rgb(0.00, 0.13, 0.36), "VGK" to rgb(0.71, 0.59, 0.35), "WSH" to rgb(0.78, 0.06, 0.18),
        "WPG" to rgb(0.02, 0.12, 0.26),
    )

    fun color(abbr: String): Color = primary[normalizedTeamAbbreviation(abbr)] ?: RinkPalette.inkTertiary
}

@Composable
fun StatScoutTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = RinkPalette.turf,
            onPrimary = Color.White,
            background = RinkPalette.canvas,
            surface = RinkPalette.surface,
            onSurface = RinkPalette.ink,
            onBackground = RinkPalette.ink,
            surfaceVariant = RinkPalette.surfaceAlt,
            outline = RinkPalette.hairline,
            secondary = RinkPalette.turf,
        ),
        content = content,
    )
}
