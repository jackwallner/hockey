package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.launch

/** Small pieces the games and teams screens share; kept private to this feature. */
internal object GamesTeamsUi {
    private val monthDayFormat = DateTimeFormatter.ofPattern("MMM d", Locale.US)
    private val weekdayFormat = DateTimeFormatter.ofPattern("EEE", Locale.US)

    /** "Sep 24" in the phone's zone. */
    fun monthDay(instant: Instant): String = monthDayFormat.format(instant.atZone(ZoneId.systemDefault()))

    /** "Sun" in the phone's zone. */
    fun weekday(instant: Instant): String = weekdayFormat.format(instant.atZone(ZoneId.systemDefault()))

    /** "1:00 PM", the phone's own time style. */
    fun shortTime(instant: Instant): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(instant.atZone(ZoneId.systemDefault()))

    /** Wins read green, losses red. */
    fun resultColor(result: String?): Color = RinkPalette.resultColor(result)

    /** The counterpart of SwiftUI's `ContentUnavailableView`. */
    @Composable
    fun Unavailable(
        icon: String,
        title: String,
        description: String? = null,
        modifier: Modifier = Modifier,
        actions: (@Composable () -> Unit)? = null,
    ) {
        Column(
            modifier.fillMaxWidth().padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SfIcon(icon, 40.dp, RinkPalette.inkTertiary)
            Text(title, style = RinkType.pageTitle, color = RinkPalette.ink, textAlign = TextAlign.Center)
            description?.let { Text(it, style = RinkType.body, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center) }
            actions?.invoke()
        }
    }

    /** A spinner with its caption, the counterpart of `ProgressView("...")`. */
    @Composable
    fun Spinner(text: String? = null, modifier: Modifier = Modifier) {
        Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(24.dp), color = RinkPalette.inkTertiary, strokeWidth = 2.dp)
            text?.let { Text(it, style = RinkType.small, color = RinkPalette.inkSecondary) }
        }
    }

    /** A small inline spinner beside a caption, for loading rows inside a card. */
    @Composable
    fun InlineSpinner(text: String, modifier: Modifier = Modifier) {
        Row(
            modifier.fillMaxWidth().padding(vertical = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(Modifier.size(16.dp), color = RinkPalette.inkTertiary, strokeWidth = 2.dp)
            Text(text, style = RinkType.small, color = RinkPalette.inkSecondary)
        }
    }

    /** SwiftUI's `.refreshable`: pull down, run [onRefresh], show the spinner until it returns. */
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun RefreshBox(onRefresh: suspend () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
        var refreshing by remember { mutableStateOf(false) }
        val scope = rememberCoroutineScope()
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                refreshing = true
                scope.launch {
                    try {
                        onRefresh()
                    } finally {
                        refreshing = false
                    }
                }
            },
            modifier = modifier.fillMaxSize(),
        ) { Box(Modifier.fillMaxSize()) { content() } }
    }

    /**
     * Two picker groups on one row, each given width in proportion to how many
     * segments it holds (the first of each pair), so every capsule in the row
     * comes out the same width. The counterpart of `RinkPickerRow`.
     */
    @Composable
    fun PickerRow(groups: List<Pair<Int, @Composable () -> Unit>>, modifier: Modifier = Modifier) {
        Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            groups.forEach { (count, content) -> Box(Modifier.weight(count.coerceAtLeast(1).toFloat())) { content() } }
        }
    }
}
