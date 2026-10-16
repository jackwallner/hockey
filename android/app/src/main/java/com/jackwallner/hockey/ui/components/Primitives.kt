package com.jackwallner.hockey.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.PlayerProfile
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.displayTeamFullName
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.ordinal
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import com.jackwallner.hockey.ui.theme.TeamColor
import com.jackwallner.hockey.ui.theme.sf
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.pow

private val TEXT_SHADOW = Shadow(Color.Black.copy(alpha = 0.35f), Offset(0f, 1f), 2f)

/** A single-line label that shrinks (down to [minScale]) before it truncates, like iOS `minimumScaleFactor`. */
@Composable
fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.8f,
    textAlign: TextAlign? = null,
) {
    BoxWithConstraints(modifier) {
        val measurer = androidx.compose.ui.text.rememberTextMeasurer()
        val maxPx = constraints.maxWidth
        val fitted = remember(text, style, maxPx) {
            if (maxPx == Int.MAX_VALUE) return@remember style
            var scale = 1f
            while (scale > minScale) {
                val width = measurer.measure(text, style.copy(fontSize = style.fontSize * scale), maxLines = 1).size.width
                if (width <= maxPx) break
                scale -= 0.05f
            }
            style.copy(fontSize = style.fontSize * scale.coerceAtLeast(minScale))
        }
        Text(text, style = fitted, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = textAlign, softWrap = false)
    }
}

@Composable
fun SfIcon(name: String, size: Dp, tint: Color, modifier: Modifier = Modifier, contentDescription: String? = null) {
    Icon(sf(name), contentDescription = contentDescription, tint = tint, modifier = modifier.size(size))
}

@Composable
fun SfIcon(icon: ImageVector, size: Dp, tint: Color, modifier: Modifier = Modifier) {
    Icon(icon, contentDescription = null, tint = tint, modifier = modifier.size(size))
}

/** Initials in the team colour: the app never renders player photos. */
@Composable
fun PlayerHeadshot(team: String, initials: String, size: Dp, modifier: Modifier = Modifier, ring: Color? = null) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(TeamColor.color(team))
            .border(if (ring != null) 2.dp else 0.5.dp, ring ?: Color.White.copy(alpha = 0.25f), CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text(initials, color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.34f).sp)
    }
}

@Composable
fun OverallPercentileBadge(percentile: Int, size: Dp = 64.dp) {
    val tier = when {
        percentile >= 90 -> "Elite"
        percentile >= 75 -> "Excellent"
        percentile >= 50 -> "Above Average"
        percentile >= 25 -> "Below Average"
        else -> "Poor"
    }
    Column(
        Modifier
            .size(size)
            .clip(RoundedCornerShape(RinkGeo.radiusBadge))
            .background(RinkPalette.color(percentile))
            .clearAndSetSemantics { contentDescription = "Overall ${percentile.ordinal} percentile, $tier" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("$percentile", style = RinkType.statHero.copy(shadow = TEXT_SHADOW), color = Color.White)
        Text(percentile.ordinal, style = RinkType.micro.copy(shadow = TEXT_SHADOW), color = Color.White.copy(alpha = 0.9f))
    }
}

@Composable
fun TeamColorDot(abbr: String, size: Dp = 8.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(TeamColor.color(abbr)))
}

/** One percentile row: label, coloured track with the rank bubble, value. */
@Composable
fun MetricBar(metric: Metric, modifier: Modifier = Modifier, showValue: Boolean = true) {
    val description = if (metric.isUnranked) "${metric.label}: ${metric.value}, not ranked" else {
        val valueText = if (metric.value.isEmpty()) "${metric.percentile.ordinal} percentile" else "${metric.value}, ${metric.percentile.ordinal} percentile"
        "${metric.label}: $valueText${if (metric.isSmallSample) ", small sample" else ""}"
    }
    Row(
        modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.width(78.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            FitText(metric.label.statDisplayLabel, RinkType.bodyBold, RinkPalette.ink, minScale = 0.75f)
            if (metric.isSmallSample && !metric.isUnranked) {
                Text("Small sample", fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = RinkPalette.inkTertiary, maxLines = 1)
            }
        }
        Box(Modifier.weight(1f).height(28.dp), contentAlignment = Alignment.CenterStart) {
            if (metric.isUnranked) {
                Box(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(4.dp)).background(RinkPalette.surfaceSunk))
                Text(
                    "Not ranked",
                    style = RinkType.micro,
                    color = RinkPalette.inkTertiary,
                    modifier = Modifier.padding(start = 8.dp).clip(CircleShape).background(RinkPalette.surfaceSunk).padding(horizontal = 6.dp),
                )
            } else {
                PercentileTrack(metric.percentile.coerceIn(0, 100), dimmed = metric.isSmallSample)
            }
        }
        Box(Modifier.width(72.dp), contentAlignment = Alignment.CenterEnd) {
            if (showValue && metric.value.isNotEmpty()) {
                FitText(
                    metric.value,
                    RinkType.statMed,
                    if (metric.isSmallSample || metric.isUnranked) RinkPalette.inkSecondary else RinkPalette.ink,
                    minScale = 0.7f,
                    textAlign = TextAlign.End,
                )
            }
        }
    }
}

@Composable
private fun PercentileTrack(percentile: Int, dimmed: Boolean) {
    val color = RinkPalette.color(percentile)
    val alpha = if (dimmed) 0.45f else 1f
    BoxWithConstraints(Modifier.fillMaxWidth().height(28.dp)) {
        val circle = 28.dp
        val trackWidth = maxWidth - circle
        val offset = circle / 2 + trackWidth * (percentile / 100f)
        Box(
            Modifier.align(Alignment.CenterStart).fillMaxWidth().height(10.dp).clip(RoundedCornerShape(4.dp))
                .background(RinkPalette.surfaceSunk.copy(alpha = alpha)),
        )
        Box(Modifier.align(Alignment.CenterStart).width(offset).height(10.dp).clip(RoundedCornerShape(4.dp)).background(color.copy(alpha = alpha)))
        Box(
            Modifier.offset(x = offset - circle / 2).size(circle).clip(CircleShape).background(color.copy(alpha = alpha)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "$percentile",
                style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum", shadow = TEXT_SHADOW),
                color = Color.White,
            )
        }
    }
}

/** Season and recent bars stacked; a missing window says so rather than vanishing. */
@Composable
fun DualMetricBar(season: Metric, recent: Metric?, recentCaption: String = "Recent") {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Season", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(52.dp))
            MetricBar(season)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                recentCaption,
                style = RinkType.micro,
                color = if (recent == null) RinkPalette.inkTertiary else RinkPalette.turf,
                modifier = Modifier.width(52.dp),
            )
            if (recent != null) MetricBar(recent)
            else Text("Season figure only", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
fun SearchField(
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    focusOnAppear: Boolean = false,
    prompt: String = "Search players or teams",
) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(focusOnAppear) { if (focusOnAppear) runCatching { focus.requestFocus() } }
    Row(
        modifier
            .fillMaxWidth()
            .height(40.dp)
            .clip(RoundedCornerShape(RinkGeo.radiusCard))
            .background(RinkPalette.surface)
            .border(1.dp, RinkPalette.hairline, RoundedCornerShape(RinkGeo.radiusCard))
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        SfIcon("magnifyingglass", 18.dp, RinkPalette.inkSecondary)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) Text(prompt, style = RinkType.body, color = RinkPalette.inkSecondary)
            BasicTextField(
                value = text,
                onValueChange = onTextChange,
                singleLine = true,
                textStyle = RinkType.body.copy(color = RinkPalette.ink),
                cursorBrush = SolidColor(RinkPalette.turf),
                modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("searchField"),
            )
        }
        if (text.isNotEmpty()) {
            SfIcon("xmark.circle.fill", 18.dp, RinkPalette.inkTertiary, Modifier.clickable { onTextChange("") }, "Clear search")
        }
    }
}

@Composable
fun SectionHeader(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = RinkType.sectionTitle, color = RinkPalette.ink)
        Text(subtitle, style = RinkType.small, color = RinkPalette.inkSecondary)
    }
}

/**
 * Recent-vs-prior change: the arrow points the way the number moved; green
 * always means better. Below half the last shown digit it is flat.
 */
@Composable
fun TrendArrow(delta: Double, decimals: Int = 1, lowerIsBetter: Boolean = false, modifier: Modifier = Modifier) {
    val isFlat = abs(delta) < 5 * 10.0.pow(-(decimals + 1).toDouble())
    val tint = when {
        isFlat -> RinkPalette.inkTertiary
        (if (lowerIsBetter) delta < 0 else delta > 0) -> RinkPalette.performanceHigh
        else -> RinkPalette.performanceLow
    }
    val text = if (isFlat) "0" else String.format(java.util.Locale.US, "%.${decimals}f", abs(delta))
    Row(
        modifier.clearAndSetSemantics { contentDescription = if (isFlat) "No recent change" else "${if (delta > 0) "Up" else "Down"} $text recently" },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!isFlat) SfIcon(if (delta > 0) "arrow.up" else "arrow.down", 10.dp, tint)
        Text(text, style = RinkType.micro.copy(fontFeatureSettings = "tnum"), color = tint)
    }
}

@Composable
fun PercentileBarMini(percentile: Int, modifier: Modifier = Modifier, height: Dp = 7.dp, tint: Color? = null) {
    BoxWithConstraints(modifier.height(height)) {
        Box(Modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(height / 2)).background(RinkPalette.surfaceSunk))
        Box(
            Modifier.width(maxWidth * (percentile.coerceIn(0, 100) / 100f)).height(height).clip(RoundedCornerShape(height / 2))
                .background(tint ?: RinkPalette.color(percentile)),
        )
    }
}

@Composable
fun InlineLoadError(message: String, retry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padInline, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(message, style = RinkType.small, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center)
        TextAction("Try Again", RinkType.smallBold, RinkPalette.turf, retry)
    }
}

/** A plain text button with an Android-sized touch target. */
@Composable
fun TextAction(title: String, style: TextStyle, color: Color, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Box(
        modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 8.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = style, color = color.copy(alpha = if (enabled) 1f else 0.5f), textAlign = TextAlign.Center)
    }
}

/** The leaderboard header: RANK / PLAYER / TEAM, then the metric chooser and direction toggle. */
@Composable
fun LeaderboardTableHeader(
    sortDescending: Boolean,
    sortLabel: String = "OVERALL",
    metrics: List<String> = emptyList(),
    onSelectMetric: (String) -> Unit = {},
    onToggleDirection: () -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().height(RinkGeo.rowHeightHeader).background(RinkPalette.surfaceAlt)
            .bottomHairline(RinkPalette.divider).padding(horizontal = RinkGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("RANK", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(42.dp))
        Text("PLAYER", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f))
        Text("TEAM", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(44.dp))
        Row(Modifier.width(104.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            val label = @Composable { open: () -> Unit ->
                Row(
                    Modifier.widthIn(max = 82.dp).clickable(onClick = open).padding(vertical = 4.dp).semantics { contentDescription = "Metric, $sortLabel" },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    FitText(sortLabel, RinkType.micro, RinkPalette.turf, Modifier.widthIn(max = 70.dp), minScale = 0.7f)
                    if (metrics.isNotEmpty()) SfIcon("chevron.down", 10.dp, RinkPalette.turf)
                }
            }
            // With no metric list the label is part of the sort toggle, as on the iOS board.
            if (metrics.isEmpty()) label(onToggleDirection)
            else RinkMenu(sections = listOf(MenuSection(null, metrics.map { MenuItem(it, checked = it == sortLabel) { onSelectMetric(it) } }))) { open ->
                label(open)
            }
            Box(
                Modifier.size(width = 22.dp, height = 28.dp).clickable(onClick = onToggleDirection)
                    .semantics { contentDescription = if (sortDescending) "Highest first" else "Lowest first" },
                contentAlignment = Alignment.Center,
            ) { SfIcon(if (sortDescending) "arrow.down" else "arrow.up", 11.dp, RinkPalette.turf) }
        }
    }
}

/**
 * One banded leaderboard row. A player without the sorted metric gets a muted
 * dash, never a bar drawn from a different number.
 */
@Composable
fun LeaderboardTableRow(
    rank: Int,
    player: Player,
    /** Row position for the zebra band: Android ranks ties as 1, 2, 2, 4, so the rank repeats. */
    stripe: Int? = null,
    metricLabel: String? = null,
    metricCategory: MetricCategory? = null,
    trendDelta: Double? = null,
    trendDecimals: Int = 3,
    valueOverride: String? = null,
    volume: String? = null,
    isSmallSample: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val metric = metricLabel?.let { label ->
        if (metricCategory != null) player.metrics.firstOrNull { it.label == label && it.category == metricCategory }
        else player.metrics.firstOrNull { it.label == label }
    }
    val percentile = metric?.percentile ?: 0
    val valueText = valueOverride ?: metric?.let { if (it.value.isNotEmpty()) it.value else it.percentile.ordinal } ?: "-"
    val valueColor = when {
        isSmallSample || metric?.isUnranked == true -> RinkPalette.inkTertiary
        valueOverride == null -> RinkPalette.textColor(percentile)
        else -> RinkPalette.ink
    }
    val subtitle = listOfNotNull(player.displayPosition, volume, if (isSmallSample) "small sample" else null).joinToString(" · ")
    Row(
        Modifier.fillMaxWidth().height(52.dp)
            .background(if ((stripe ?: (rank - 1)) % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = RinkGeo.padInline)
            .testTag("leaderboardRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("$rank", style = RinkType.statSmall, color = RinkPalette.inkSecondary, modifier = Modifier.width(42.dp))
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            PlayerHeadshot(player.team, player.initials, 36.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                FitText(player.name, RinkType.bodyBold, RinkPalette.ink, minScale = 0.85f)
                FitText(subtitle, RinkType.micro, RinkPalette.inkTertiary, minScale = 0.85f)
            }
        }
        Row(Modifier.width(44.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColorDot(player.team, 6.dp)
            Text(displayTeamAbbr(player.team), style = RinkType.small, color = RinkPalette.inkSecondary, maxLines = 1)
        }
        Row(
            Modifier.width(if (trendDelta == null) 92.dp else 56.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (metric != null || valueOverride != null) {
                if (valueOverride == null) {
                    if (metric?.isUnranked == true) Spacer(Modifier.width(36.dp))
                    else PercentileBarMini(percentile, Modifier.width(36.dp).alphaIf(isSmallSample, 0.35f))
                }
                FitText(valueText, RinkType.statSmall, valueColor, Modifier.width(48.dp), minScale = 0.7f, textAlign = TextAlign.End)
            } else {
                Text("-", style = RinkType.statSmall, color = RinkPalette.inkTertiary, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth())
            }
        }
        if (trendDelta != null) {
            Box(Modifier.width(46.dp), contentAlignment = Alignment.CenterEnd) { TrendArrow(trendDelta, trendDecimals) }
        }
    }
}

fun Modifier.alphaIf(condition: Boolean, alpha: Float): Modifier =
    if (condition) this.then(Modifier.graphicsAlpha(alpha)) else this

private fun Modifier.graphicsAlpha(alpha: Float): Modifier = this.alpha(alpha)

/** A hairline along the bottom edge, drawn rather than laid out. */
fun Modifier.bottomHairline(color: Color = RinkPalette.divider, width: Dp = RinkGeo.hairline): Modifier = drawBehind {
    val stroke = width.toPx()
    drawRect(color, topLeft = Offset(0f, size.height - stroke), size = androidx.compose.ui.geometry.Size(size.width, stroke))
}

fun Modifier.topHairline(color: Color = RinkPalette.divider, width: Dp = RinkGeo.hairline): Modifier = drawBehind {
    drawRect(color, size = androidx.compose.ui.geometry.Size(size.width, width.toPx()))
}

/** The card surface every module sits on. */
fun Modifier.rinkCard(stroke: Color = RinkPalette.hairline): Modifier = this
    .clip(RoundedCornerShape(RinkGeo.radiusCard))
    .background(RinkPalette.surface)
    .border(RinkGeo.hairline, stroke, RoundedCornerShape(RinkGeo.radiusCard))

@Composable
fun RinkSectionBar(title: String, trailing: (@Composable RowScope.() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().height(RinkGeo.rowHeightHeader).background(RinkPalette.surfaceSunk),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title.uppercase(), style = RinkType.sectionTitle, color = RinkPalette.ink, modifier = Modifier.padding(start = RinkGeo.padCard))
        Spacer(Modifier.weight(1f))
        if (trailing != null) Row(Modifier.padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically, content = trailing)
    }
}

@Composable
fun RinkSubSectionBar(title: String, trailing: String? = null, trailingColor: Color = RinkPalette.inkSecondary) {
    Row(
        Modifier.fillMaxWidth().height(26.dp).background(RinkPalette.surfaceAlt).bottomHairline().padding(horizontal = RinkGeo.padCard),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title.uppercase(), style = RinkType.micro, color = RinkPalette.inkSecondary)
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, style = RinkType.statSmall, color = trailingColor)
    }
}

/** Underlined text tabs: the metric-category tier. */
@Composable
fun RinkTabs(tabs: List<String>, selected: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    val haptic = rememberHaptic()
    Row(modifier.fillMaxWidth().background(RinkPalette.surface).bottomHairline(RinkPalette.hairline)) {
        tabs.forEach { tab ->
            val isSelected = selected == tab
            Column(
                Modifier.weight(1f).clickable {
                    onSelect(tab)
                    haptic()
                }.semantics { contentDescription = tab }.testTag("tab_$tab"),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) {
                    FitText(tab.uppercase(), RinkType.smallBold, if (isSelected) RinkPalette.ink else RinkPalette.inkTertiary, minScale = 0.75f)
                }
                Box(Modifier.fillMaxWidth().height(3.dp).background(if (isSelected) RinkPalette.turf else Color.Transparent))
            }
        }
    }
}

/** Player header on the midnight band: name, club, bio, origin and draft lines. */
@Composable
fun PlayerIdentityStrip(player: Player, showOverallBadge: Boolean = false, profile: PlayerProfile? = null) {
    val hand = player.handedness.trim { it.isWhitespace() || !it.isLetterOrDigit() }
    val handLabel = hand.takeIf { it.isNotEmpty() }?.let { "${if (player.positionGroup == PlayerPositionGroup.GOALIE) "Catches" else "Shoots"} $it" }
    val bioLine = if (profile == null) positionAndHandedness(player) else listOfNotNull(
        profile.jersey?.let { "#$it" },
        player.displayPosition,
        handLabel,
        profile.age(LocalDate.now())?.let { "$it yrs" },
    ).joinToString(" · ")
    val originLine = profile?.let { p -> listOfNotNull(p.sizeLabel, p.birthplace).takeIf { it.isNotEmpty() }?.joinToString(" · ") }
    val careerLine = profile?.let { p ->
        listOfNotNull(
            p.draftLabel?.let { if (it == "Undrafted") it else "Draft: $it" },
            if (p.isRookie == true) "Rookie" else null,
        ).takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }
    Row(
        Modifier.fillMaxWidth().background(RinkPalette.midnight).padding(RinkGeo.padPage),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        PlayerHeadshot(player.team, player.initials, 72.dp, ring = Color.White)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(player.name, RinkType.playerName, RinkPalette.inkOnDark, minScale = 0.7f)
            FitText(displayTeamFullName(player.team), RinkType.bodyBold, Color.White.copy(alpha = 0.85f), minScale = 0.8f)
            FitText(bioLine, RinkType.small, Color.White.copy(alpha = 0.65f), minScale = 0.8f)
            listOfNotNull(originLine, careerLine).forEach { FitText(it, RinkType.small, Color.White.copy(alpha = 0.65f), minScale = 0.8f) }
        }
        if (showOverallBadge) OverallPercentileBadge(player.overallPercentile)
    }
}

private fun positionAndHandedness(player: Player): String {
    val pos = player.displayPosition.trim()
    val hand = player.handedness.trim { it.isWhitespace() || !it.isLetterOrDigit() }
    return when {
        pos.isEmpty() && hand.isEmpty() -> ""
        hand.isEmpty() -> pos
        pos.isEmpty() -> hand
        else -> "$pos · $hand"
    }
}

@Composable
fun TeamIdentityStrip(team: String, season: Int? = null) {
    val abbr = normalizedTeamAbbreviation(team)
    Row(
        Modifier.fillMaxWidth().background(RinkPalette.midnight).padding(RinkGeo.padPage),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(56.dp).clip(CircleShape).background(TeamColor.color(abbr)), contentAlignment = Alignment.Center) {
            Text(abbr, style = RinkType.pageTitle, color = Color.White)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(teamFullName(abbr), RinkType.playerName, RinkPalette.inkOnDark, minScale = 0.7f)
            Text("${season ?: LocalDate.now().year} Season", style = RinkType.small, color = Color.White.copy(alpha = 0.65f))
        }
    }
}

@Composable
fun rememberHaptic(): () -> Unit {
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    return remember(haptic) { { haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.SegmentTick) } }
}

/**
 * One slice of a card drawn as separate lazy items: the outline's sides on every
 * slice, its top edge and corners on the first, its bottom on the last.
 */
fun Modifier.cardSlice(first: Boolean, last: Boolean, stroke: Color = RinkPalette.hairline): Modifier {
    val radius = RinkGeo.radiusCard
    val shape = RoundedCornerShape(
        topStart = if (first) radius else 0.dp,
        topEnd = if (first) radius else 0.dp,
        bottomStart = if (last) radius else 0.dp,
        bottomEnd = if (last) radius else 0.dp,
    )
    return this.clip(shape).background(RinkPalette.surface).drawWithContent {
        drawContent()
        val w = RinkGeo.hairline.toPx()
        val r = radius.toPx()
        drawRect(stroke, topLeft = Offset(0f, if (first) r else 0f), size = androidx.compose.ui.geometry.Size(w, size.height - (if (first) r else 0f) - (if (last) r else 0f)))
        drawRect(stroke, topLeft = Offset(size.width - w, if (first) r else 0f), size = androidx.compose.ui.geometry.Size(w, size.height - (if (first) r else 0f) - (if (last) r else 0f)))
        if (first) {
            drawRect(stroke, topLeft = Offset(r, 0f), size = androidx.compose.ui.geometry.Size(size.width - 2 * r, w))
            drawArc(stroke, 180f, 90f, false, topLeft = Offset(w / 2, w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
            drawArc(stroke, 270f, 90f, false, topLeft = Offset(size.width - 2 * r - w / 2, w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
        }
        if (last) {
            drawRect(stroke, topLeft = Offset(r, size.height - w), size = androidx.compose.ui.geometry.Size(size.width - 2 * r, w))
            drawArc(stroke, 90f, 90f, false, topLeft = Offset(w / 2, size.height - 2 * r - w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
            drawArc(stroke, 0f, 90f, false, topLeft = Offset(size.width - 2 * r - w / 2, size.height - 2 * r - w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
        }
    }
}

/** Compact display spellings for the box-score acronyms that read loud on a bar. */
val String.statDisplayLabel: String
    get() = when (this) {
        "SH%" -> "Sh%"
        "HITS" -> "Hits"
        "BLK" -> "Blk"
        else -> this
    }

/** Forwards / Defensemen / Goalies, the one cohort switch every board shares. */
@Composable
fun PositionTabs(selection: PlayerPositionGroup, onSelect: (PlayerPositionGroup) -> Unit, modifier: Modifier = Modifier) {
    RinkTabs(
        PlayerPositionGroup.entries.map { it.displayName },
        selection.displayName,
        { name -> PlayerPositionGroup.entries.firstOrNull { it.displayName == name }?.let(onSelect) },
        modifier.semantics { contentDescription = "Position" },
    )
}
