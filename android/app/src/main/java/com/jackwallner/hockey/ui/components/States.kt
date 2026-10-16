package com.jackwallner.hockey.ui.components

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import kotlinx.coroutines.launch

/** SwiftUI's `ContentUnavailableView`: an icon, a title, a line of explanation and an optional action. */
@Composable
fun EmptyState(
    title: String,
    icon: String,
    description: String? = null,
    modifier: Modifier = Modifier,
    actionTitle: String? = null,
    action: (() -> Unit)? = null,
) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        SfIcon(icon, 40.dp, RinkPalette.inkTertiary)
        Text(title, style = RinkType.cardTitle.copy(fontSize = RinkType.cardTitle.fontSize * 1.15f), color = RinkPalette.ink, textAlign = TextAlign.Center)
        description?.let { Text(it, style = RinkType.body, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center) }
        if (actionTitle != null && action != null) {
            Box(
                Modifier.heightIn(min = 44.dp).clip(CircleShape).background(RinkPalette.inkTertiary).clickable(onClick = action)
                    .padding(horizontal = 18.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) { Text(actionTitle, style = RinkType.bodyBold, color = Color.White) }
        }
    }
}

/** Pull to refresh around a scrolling board; the spinner tracks the real load. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefreshableBox(onRefresh: suspend () -> Unit, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
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
        modifier = modifier,
        content = content,
    )
}

/**
 * The blur behind a StatScout+ gate. Before Android 12 there is no render
 * blur, so the teaser is faded nearly out instead of shown legibly.
 */
fun Modifier.gateBlur(): Modifier =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) this.blur(8.dp) else this.alpha(0.12f)

/** The first-run loading card over an empty board. */
@Composable
fun LoadingCard(message: String, progress: Double, modifier: Modifier = Modifier) {
    val value = progress.coerceIn(0.0, 1.0).toFloat()
    Column(
        modifier
            .widthIn(max = 300.dp)
            .padding(horizontal = 24.dp)
            .shadow(16.dp, RoundedCornerShape(4.dp), ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f))
            .rinkCard()
            .padding(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        LinearProgressIndicator(progress = { value }, color = RinkPalette.turf, trackColor = RinkPalette.surfaceSunk, modifier = Modifier.fillMaxWidth())
        Text(message, style = RinkType.bodyBold, color = RinkPalette.ink, textAlign = TextAlign.Center)
        Text("${(value * 100).toInt()}%", style = RinkType.micro, color = RinkPalette.inkTertiary)
    }
}

/** The thin progress pill shown above a board while it refreshes in place. */
@Composable
fun LoadingStatusBar(message: String, progress: Double, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 12.dp).clip(CircleShape).background(RinkPalette.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LinearProgressIndicator(
            progress = { progress.coerceIn(0.0, 1.0).toFloat() },
            color = RinkPalette.turf,
            trackColor = RinkPalette.surfaceSunk,
            modifier = Modifier.weight(1f),
        )
        Text(message, style = RinkType.micro, color = RinkPalette.inkSecondary, maxLines = 1)
    }
}

/** An "i" note under a board: coverage limits and what the bars mean. */
@Composable
fun InfoNote(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        SfIcon("info.circle", 12.dp, RinkPalette.inkTertiary, Modifier.padding(top = 1.dp))
        Text(text, style = RinkType.micro, color = RinkPalette.inkTertiary)
    }
}

@Composable
fun CenteredBox(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) =
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center, content = content)
