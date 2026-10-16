package com.jackwallner.hockey.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType

object RinkControl {
    /** One height for every inline control (a 48dp touch target is added around it). */
    val height = 32.dp
}

/** The StatScout+ crown's yellow, as on iOS. */
val CrownYellow = Color(1f, 0.8f, 0f)

data class Segment<T>(val value: T, val label: String, val isLocked: Boolean = false, val icon: String? = null)

/**
 * Two to four inline options, one height and shape everywhere. A locked
 * segment draws a crown and routes the tap to [onLockedTap] instead of selecting.
 */
@Composable
fun <T> RinkSegmented(
    segments: List<Segment<T>>,
    selection: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    onLockedTap: ((T) -> Unit)? = null,
    selectedFill: (T) -> Color = { RinkPalette.turf },
) {
    val haptic = rememberHaptic()
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        segments.forEach { segment ->
            val isSelected = segment.value == selection && !segment.isLocked
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    .clickable {
                        if (segment.isLocked) onLockedTap?.invoke(segment.value) else onSelect(segment.value)
                        haptic()
                    }
                    .semantics {
                        contentDescription = if (segment.isLocked) "${segment.label}, requires StatScout+" else segment.label
                        selected = isSelected
                        role = Role.Tab
                    }
                    .testTag("segment_${segment.label}"),
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(RinkControl.height)
                        .clip(CircleShape)
                        .background(if (isSelected) selectedFill(segment.value) else RinkPalette.surface)
                        .border(0.5.dp, if (isSelected) Color.Transparent else RinkPalette.hairline, CircleShape)
                        .padding(horizontal = 6.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val tint = if (isSelected) Color.White else RinkPalette.inkSecondary
                    segment.icon?.let { SfIcon(it, 13.dp, tint) ; Spacer(Modifier.width(4.dp)) }
                    FitText(segment.label, RinkType.smallBold, tint, Modifier.weight(1f, fill = false), minScale = 0.6f)
                    if (segment.isLocked) {
                        Spacer(Modifier.width(4.dp))
                        SfIcon("crown.fill", 11.dp, CrownYellow)
                    }
                }
            }
        }
    }
}

sealed interface ChipTrailing {
    data object None : ChipTrailing
    data object Chevron : ChipTrailing
    data class SortArrow(val descending: Boolean) : ChipTrailing
}

/** The single standalone-control shape: an outlined capsule that fills turf while active. */
@Composable
fun RinkChip(
    modifier: Modifier = Modifier,
    title: String? = null,
    icon: String? = null,
    trailing: ChipTrailing = ChipTrailing.None,
    isActive: Boolean = false,
    isLocked: Boolean = false,
) {
    val glyph = if (isActive) Color.White else RinkPalette.inkSecondary
    Row(
        modifier
            .height(RinkControl.height)
            .then(if (title == null) Modifier.width(RinkControl.height) else Modifier)
            .clip(CircleShape)
            .background(if (isActive) RinkPalette.turf else RinkPalette.surface)
            .border(0.5.dp, if (isActive) Color.Transparent else RinkPalette.hairline, CircleShape)
            .padding(horizontal = if (title == null) 0.dp else 12.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let { SfIcon(it, 14.dp, glyph) }
        title?.let { Text(it, style = RinkType.smallBold, color = if (isActive) Color.White else RinkPalette.ink, maxLines = 1, softWrap = false) }
        if (isLocked) SfIcon("crown.fill", 11.dp, CrownYellow)
        when (trailing) {
            ChipTrailing.None -> Unit
            ChipTrailing.Chevron -> SfIcon("chevron.down", 14.dp, glyph)
            is ChipTrailing.SortArrow -> SfIcon(
                if (trailing.descending) "arrow.down" else "arrow.up",
                13.dp,
                if (isActive) Color.White else RinkPalette.turf,
            )
        }
    }
}

/** A chip with a 48dp touch target around its 32dp capsule. */
@Composable
fun ChipButton(onClick: () -> Unit, modifier: Modifier = Modifier, description: String? = null, content: @Composable () -> Unit) {
    Box(
        modifier
            .heightIn(min = 44.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .then(if (description != null) Modifier.semantics { contentDescription = description } else Modifier),
        contentAlignment = Alignment.Center,
    ) { content() }
}

data class MenuItem(
    val title: String,
    val checked: Boolean = false,
    val locked: Boolean = false,
    val icon: String? = null,
    val onClick: () -> Unit,
)

data class MenuSection(val title: String?, val items: List<MenuItem>)

/**
 * A plain pop-up menu, the counterpart of SwiftUI's `Menu`: optional section
 * headers, a check on the current choice, a crown on a locked one. Always the
 * light popup, even when opened from the midnight bar.
 */
@Composable
fun RinkMenu(
    sections: List<MenuSection>,
    modifier: Modifier = Modifier,
    trigger: @Composable (open: () -> Unit) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val haptic = rememberHaptic()
    Box(modifier) {
        trigger { expanded = true }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = RinkPalette.surface,
            modifier = Modifier.heightIn(max = 520.dp).widthIn(min = 200.dp),
        ) {
            sections.forEachIndexed { index, section ->
                if (index > 0) HorizontalDivider(color = RinkPalette.divider, thickness = 0.5.dp)
                section.title?.let {
                    Text(
                        it,
                        style = RinkType.micro,
                        color = RinkPalette.inkTertiary,
                        modifier = Modifier.padding(start = 16.dp, top = 10.dp, bottom = 4.dp, end = 16.dp),
                    )
                }
                section.items.forEach { item ->
                    DropdownMenuItem(
                        text = { Text(item.title, style = RinkType.body, color = RinkPalette.ink) },
                        onClick = {
                            expanded = false
                            haptic()
                            item.onClick()
                        },
                        trailingIcon = when {
                            item.locked -> ({ SfIcon("crown.fill", 16.dp, CrownYellow) })
                            item.checked -> ({ SfIcon("checkmark", 18.dp, RinkPalette.turf) })
                            item.icon != null -> ({ SfIcon(item.icon, 18.dp, RinkPalette.inkSecondary) })
                            else -> null
                        },
                        colors = MenuDefaults.itemColors(textColor = RinkPalette.ink),
                        modifier = Modifier.testTag("menu_${item.title}"),
                    )
                }
            }
        }
    }
}

/** Season type first, then the seasons: two rows above a long list keep the playoffs reachable. */
@Composable
fun SeasonPhasePicker(
    seasons: List<Int>,
    selectedSeason: Int,
    selectedPhase: SeasonPhase,
    isSeasonLocked: (Int) -> Boolean,
    onSelectSeason: (Int) -> Unit,
    onSelectPhase: (SeasonPhase) -> Unit,
    modifier: Modifier = Modifier,
    trigger: @Composable (open: () -> Unit) -> Unit,
) {
    RinkMenu(
        sections = listOf(
            MenuSection("Season type", SeasonPhase.entries.map { phase ->
                MenuItem(phase.label, checked = phase == selectedPhase) { onSelectPhase(phase) }
            }),
            MenuSection("Season", seasons.map { season ->
                MenuItem(SeasonLabel.display(season), checked = season == selectedSeason && !isSeasonLocked(season), locked = isSeasonLocked(season)) {
                    onSelectSeason(season)
                }
            }),
        ),
        modifier = modifier,
        trigger = trigger,
    )
}

@Composable
fun SeasonMenu(
    seasons: List<Int>,
    selected: Int,
    isLocked: (Int) -> Boolean,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    trigger: @Composable (open: () -> Unit) -> Unit,
) {
    RinkMenu(
        sections = listOf(MenuSection(null, seasons.map { season ->
            MenuItem(SeasonLabel.display(season), checked = season == selected && !isLocked(season), locked = isLocked(season)) { onSelect(season) }
        })),
        modifier = modifier,
        trigger = trigger,
    )
}

@Composable
fun SeasonPhaseMenu(
    selected: SeasonPhase,
    onSelect: (SeasonPhase) -> Unit,
    modifier: Modifier = Modifier,
    trigger: @Composable (open: () -> Unit) -> Unit,
) {
    RinkMenu(
        sections = listOf(MenuSection(null, SeasonPhase.entries.map { MenuItem(it.label, checked = it == selected) { onSelect(it) } })),
        modifier = modifier,
        trigger = trigger,
    )
}

/** The tappable label for a chooser on the midnight bar. */
@Composable
fun RinkNavPill(title: String, onClick: () -> Unit, icon: String? = null, description: String? = null) {
    Box(
        Modifier.heightIn(min = 44.dp).clip(CircleShape).clickable(onClick = onClick)
            .semantics { contentDescription = description ?: title }.testTag("navPill"),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.clip(CircleShape).background(RinkPalette.turf).padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            icon?.let { SfIcon(it, 13.dp, Color.White) }
            Text(title, style = RinkType.micro, color = Color.White, maxLines = 1)
            SfIcon("chevron.down", 12.dp, Color.White)
        }
    }
}

/** The in-content chooser: a chip with a chevron. */
@Composable
fun RinkInlinePill(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: String? = null, isLocked: Boolean = false) {
    ChipButton(onClick, modifier, description = title) {
        RinkChip(title = title, icon = icon, trailing = ChipTrailing.Chevron, isLocked = isLocked)
    }
}

data class StatOption(val id: String, val label: String, val isSelected: Boolean = false)

/** The one control used everywhere to choose which statistic a board ranks. */
@Composable
fun StatPickerMenu(
    activeLabel: String,
    modifier: Modifier = Modifier,
    advanced: List<StatOption> = emptyList(),
    standard: List<StatOption> = emptyList(),
    onSelectAdvanced: (StatOption) -> Unit = {},
    onSelectStandard: (StatOption) -> Unit = {},
) {
    val sections = buildList {
        if (advanced.isNotEmpty()) add(MenuSection("Advanced", advanced.map { MenuItem(it.label, checked = it.isSelected) { onSelectAdvanced(it) } }))
        if (standard.isNotEmpty()) add(MenuSection("Standard", standard.map { MenuItem(it.label, checked = it.isSelected) { onSelectStandard(it) } }))
    }
    RinkMenu(sections, modifier.testTag("statPicker")) { open ->
        RinkInlinePill(activeLabel, open, icon = "chart.bar.fill")
    }
}

@Composable
fun SortDirectionButton(descending: Boolean, statLabel: String, onClick: () -> Unit) {
    val haptic = rememberHaptic()
    ChipButton(
        onClick = {
            onClick()
            haptic()
        },
        description = "Sort direction, $statLabel, ${if (descending) "highest first" else "lowest first"}",
    ) { RinkChip(trailing = ChipTrailing.SortArrow(descending)) }
}

@Composable
fun QualifierMenu(selection: DashboardViewModel.QualifierLevel, onSelect: (DashboardViewModel.QualifierLevel) -> Unit) {
    RinkMenu(listOf(MenuSection(null, DashboardViewModel.QualifierLevel.entries.map { level ->
        MenuItem("${level.label} · ${level.description}", checked = level == selection) { onSelect(level) }
    }))) { open ->
        ChipButton(open, description = "Qualifier, ${selection.label}") {
            RinkChip(title = selection.label, icon = "line.3.horizontal.decrease.circle", trailing = ChipTrailing.Chevron)
        }
    }
}

@Composable
fun Gap(size: androidx.compose.ui.unit.Dp) = Spacer(Modifier.size(size))
