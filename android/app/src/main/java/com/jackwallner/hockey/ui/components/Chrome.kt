package com.jackwallner.hockey.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack

/** The midnight navigation bar every screen wears, with the status bar drawn into it. */
@Composable
fun RinkTopBar(
    title: String? = null,
    onBack: (() -> Unit)? = null,
    leading: (@Composable RowScope.() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Column(Modifier.fillMaxWidth().background(RinkPalette.midnight)) {
        Spacer(Modifier.windowInsetsPadding(WindowInsets.statusBars))
        Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp)) {
            Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically) {
                if (onBack != null) {
                    Box(
                        Modifier.size(48.dp).clip(CircleShape).clickable(onClick = onBack).semantics { contentDescription = "Back" }.testTag("back"),
                        contentAlignment = Alignment.Center,
                    ) { SfIcon(Icons.AutoMirrored.Filled.ArrowBack, 24.dp, Color.White) }
                } else Spacer(Modifier.size(8.dp))
                leading?.invoke(this)
            }
            if (title != null) {
                Text(
                    title,
                    style = RinkType.cardTitle,
                    color = Color.White,
                    maxLines = 1,
                    textAlign = TextAlign.Center,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    modifier = Modifier.align(Alignment.Center).padding(horizontal = if (onBack != null || leading != null) 56.dp else 16.dp)
                        .widthIn(max = 280.dp),
                )
            }
            if (trailing != null) {
                Row(
                    Modifier.align(Alignment.CenterEnd).padding(end = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    content = trailing,
                )
            }
        }
    }
}

/** A pushed screen: bar with back, then content on the canvas. */
@Composable
fun PushedScreen(
    title: String?,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val navigator = LocalNavigator.current
    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(title = title, onBack = { navigator.pop() }, trailing = trailing)
        content()
    }
}

/** Bottom padding so scrolling content clears the floating tab bar and gesture area. */
@Composable
fun bottomBarPadding(extra: Dp = 96.dp): PaddingValues =
    PaddingValues(bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + extra)

/** Content limited to a readable width and centred on wide screens. */
@Composable
fun Readable(modifier: Modifier = Modifier, maxWidth: Dp = 900.dp, content: @Composable ColumnScope.() -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = maxWidth).fillMaxWidth(), content = content)
    }
}

/**
 * A page sheet: slides up over everything. Back or the scrim dismisses it.
 * [fraction] below 1 makes a half sheet anchored to the bottom.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun StatScoutSheet(visible: Boolean, onDismiss: () -> Unit, fullHeight: Boolean = true, content: @Composable () -> Unit) {
    val state = remember { MutableTransitionState(false) }
    state.targetState = visible
    if (!state.currentState && !state.targetState && state.isIdle) return
    val dismiss = rememberUpdatedState(onDismiss)
    Dialog(
        onDismissRequest = { dismiss.value() },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        val view = LocalView.current
        LaunchedEffect(view) {
            (view.parent as? DialogWindowProvider)?.window?.let { window ->
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                window.setWindowAnimations(0)
            }
        }
        Box(Modifier.fillMaxSize()) {
            AnimatedVisibility(state, enter = fadeIn(tween(250)), exit = fadeOut(tween(250))) {
                Box(
                    Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)).clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { dismiss.value() },
                )
            }
            AnimatedVisibility(
                state,
                enter = slideInVertically(tween(320)) { it },
                exit = slideOutVertically(tween(280)) { it },
                modifier = Modifier.fillMaxSize(),
            ) {
                BackHandler { dismiss.value() }
                val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 10.dp
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    Box(
                        Modifier
                            .then(if (fullHeight) Modifier.fillMaxSize().padding(top = top) else Modifier.fillMaxWidth().padding(top = top))
                            .widthIn(max = 700.dp)
                            .clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
                            .background(RinkPalette.canvas)
                            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                            .semantics { testTagsAsResourceId = true }
                            .imePadding(),
                    ) { content() }
                }
            }
        }
    }
}

/** Dark status-bar icons while a light, full-screen surface (onboarding) is up; restores on exit. */
@Composable
fun DarkStatusIcons() {
    val view = LocalView.current
    androidx.compose.runtime.DisposableEffect(view) {
        val window = (view.context as? android.app.Activity)?.window
        val controller = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        val previous = controller?.isAppearanceLightStatusBars
        controller?.isAppearanceLightStatusBars = true
        onDispose { if (previous != null) controller.isAppearanceLightStatusBars = previous }
    }
}
