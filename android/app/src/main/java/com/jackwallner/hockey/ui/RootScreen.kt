package com.jackwallner.hockey.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.zIndex
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.hockey.AppGraph
import com.jackwallner.hockey.DebugLaunchOptions
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkNavPill
import com.jackwallner.hockey.ui.components.RinkTopBar
import com.jackwallner.hockey.ui.components.SeasonPhasePicker
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatScoutSheet
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.NavStack
import com.jackwallner.hockey.ui.nav.Navigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.screens.ConfigMissingScreen
import com.jackwallner.hockey.ui.screens.Destination
import com.jackwallner.hockey.ui.screens.OnboardingScreen
import com.jackwallner.hockey.ui.screens.PaywallScreen
import com.jackwallner.hockey.ui.screens.SEEN_KEY
import com.jackwallner.hockey.ui.screens.TabRoot
import com.jackwallner.hockey.ui.screens.TrialPitchSheet
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class AppTab(val title: String, val icon: String) {
    STATS("Stats", "chart.bar.fill"),
    GAMES("Games", "sportscourt.fill"),
    TRENDS("Trends", "flame.fill"),
    TEAMS("Teams", "shield.lefthalf.filled"),
    COMPARE("Compare", "arrow.left.arrow.right"),
}

@Composable
fun RootScreen(graph: AppGraph) {
    if (graph.api == null) {
        ConfigMissingScreen()
        return
    }
    val vm = graph.dashboard
    val store = graph.subscriptions
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var hasCompletedOnboarding by remember { mutableStateOf(graph.defaults.getBoolean(SEEN_KEY)) }
    var selection by rememberSaveable { mutableIntStateOf(DebugLaunchOptions.launchTab ?: 0) }
    val navigators = remember { AppTab.entries.associateWith { Navigator() } }
    LaunchedEffect(graph.pendingTab) {
        val name = graph.pendingTab ?: return@LaunchedEffect
        AppTab.entries.firstOrNull { it.title.equals(name, ignoreCase = true) }?.let { selection = it.ordinal }
        graph.pendingTab = null
    }
    var paywall by remember { mutableStateOf<PaywallTrigger?>(null) }
    var pitch by remember { mutableStateOf<PaywallTrigger?>(null) }
    var reviewShownThisSession by remember { mutableStateOf(false) }

    val actions = remember {
        object : AppActions {
            override fun openPaywall(trigger: PaywallTrigger) {
                pitch = null
                paywall = trigger
            }

            override fun openTrialPitch(trigger: PaywallTrigger) {
                pitch = trigger
            }

            /**
             * Google forbids a question before the Play card: the gates decide, then the card shows
             * itself after about three seconds. If anything is on screen then (onboarding, the
             * paywall, a pitch or any other sheet) the moment stays pending and the next one asks.
             */
            override fun positiveMoment() {
                graph.review.recordPositiveMoment()
                val completed = graph.defaults.getBoolean(SEEN_KEY)
                if (reviewShownThisSession || !graph.review.shouldRequestAfterPositiveMoment(completed)) return
                scope.launch {
                    delay(3_000)
                    val activity = context.findActivity() ?: return@launch
                    // Every sheet and alert is its own window, so the activity only has focus when none is up.
                    val screenClear = hasCompletedOnboarding && paywall == null && pitch == null && activity.hasWindowFocus()
                    if (!screenClear || reviewShownThisSession) return@launch
                    if (!graph.review.shouldRequestAfterPositiveMoment(graph.defaults.getBoolean(SEEN_KEY))) return@launch
                    reviewShownThisSession = true
                    graph.review.markShown()
                    val manager = ReviewManagerFactory.create(activity)
                    manager.requestReviewFlow().addOnCompleteListener { request ->
                        if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
                    }
                }
            }
        }
    }

    LaunchedEffect(Unit) { vm.loadIfNeeded() }
    LaunchedEffect(store.isPro) {
        vm.applyProState(store.isPro)
        if (store.isPro) vm.loadHistoricalIfNeeded()
    }
    // While the app is in front, ask the status endpoint every two minutes so boards update in place.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            vm.refreshOnForeground()
            while (true) {
                delay(120_000)
                vm.refreshOnForeground()
            }
        }
    }

    CompositionLocalProvider(LocalAppActions provides actions) {
        Box(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
            // Every tab stays composed so its stack and scroll survive switching; the active one sits on top.
            AppTab.entries.forEachIndexed { index, tab ->
                val active = selection == index
                Box(
                    Modifier.fillMaxSize().zIndex(if (active) 1f else 0f).background(RinkPalette.canvas)
                        .then(if (active) Modifier else Modifier.alpha(0f).clearAndSetSemantics { }.swallowTouches()),
                ) {
                    NavStack(navigators.getValue(tab), enabled = active && hasCompletedOnboarding) { route ->
                        if (route == Route.Root) TabRoot(tab, active) else Destination(route)
                    }
                }
            }
            FloatingTabBar(selection, Modifier.align(Alignment.BottomCenter).zIndex(2f)) { index ->
                if (selection == index) navigators.getValue(AppTab.entries[index]).popToRoot() else selection = index
            }
            if (!hasCompletedOnboarding) Box(Modifier.zIndex(3f)) {
                OnboardingScreen(
                    onFinish = {
                        graph.defaults.putBoolean(SEEN_KEY, true)
                        hasCompletedOnboarding = true
                    },
                    startPage = DebugLaunchOptions.onboardingPage ?: 0,
                )
            }
        }
        StatScoutSheet(visible = pitch != null, onDismiss = { pitch = null }, fullHeight = false) {
            pitch?.let { TrialPitchSheet(it) { pitch = null } }
        }
        StatScoutSheet(visible = paywall != null, onDismiss = { paywall = null }) {
            paywall?.let { PaywallScreen(it) { paywall = null } }
        }
    }
}

/** Hand-rolled floating tab bar: each tab keeps its stack and scroll when you switch away. */
@Composable
private fun FloatingTabBar(selection: Int, modifier: Modifier = Modifier, onSelect: (Int) -> Unit) {
    val haptic = rememberHaptic()
    Row(
        modifier
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(bottom = 12.dp)
            .shadow(12.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.1f), spotColor = Color.Black.copy(alpha = 0.1f))
            .clip(CircleShape)
            .background(RinkPalette.surface.copy(alpha = 0.97f))
            .border(0.5.dp, RinkPalette.hairline, CircleShape)
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .widthIn(max = 420.dp),
    ) {
        AppTab.entries.forEachIndexed { index, tab ->
            val isSelected = selection == index
            val tint by animateColorAsState(if (isSelected) RinkPalette.turf else RinkPalette.inkSecondary, label = "tabTint")
            Column(
                Modifier.width(66.dp).height(54.dp).clip(CircleShape)
                    .background(if (isSelected) RinkPalette.turf.copy(alpha = 0.12f) else Color.Transparent)
                    .clickable {
                        onSelect(index)
                        haptic()
                    }
                    .semantics { contentDescription = tab.title; selected = isSelected }
                    .testTag("tab_${tab.title}"),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
            ) {
                SfIcon(tab.icon, 22.dp, tint)
                FitText(tab.title, RinkType.smallBold, tint, minScale = 0.8f)
            }
        }
    }
}

/** The midnight bar for a home tab: a leading chooser or title, then settings and the upgrade pill. */
@Composable
fun HomeTopBar(title: String? = null, leading: (@Composable RowScope.() -> Unit)? = null) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val haptic = rememberHaptic()
    RinkTopBar(
        title = title,
        leading = leading,
        trailing = {
            Box(
                Modifier.size(44.dp).clip(CircleShape).clickable {
                    haptic()
                    navigator.push(Route.Settings)
                }.semantics { contentDescription = "Settings" }.testTag("settingsButton"),
                contentAlignment = Alignment.Center,
            ) { SfIcon("gearshape", 22.dp, Color.White.copy(alpha = 0.85f)) }
            if (!store.isPro) {
                val label = store.upgradeCTALabel
                Box(
                    Modifier.height(44.dp).clip(CircleShape).clickable { actions.openPaywall(store.defaultUpgradeTrigger) }
                        .semantics { contentDescription = "$label, unlock all features" }.testTag("upgradeButton"),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        Modifier.clip(CircleShape).background(Color(1f, 0.8f, 0f)).padding(horizontal = 9.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SfIcon("crown.fill", 12.dp, RinkPalette.midnight)
                        Text(label, style = RinkType.micro.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = RinkPalette.midnight, maxLines = 1)
                    }
                }
            }
        },
    )
}

/** The season and phase pill on Stats, Trends and Teams: season type first, then the years. */
@Composable
fun SeasonPhaseNavPill(seasons: List<Int>, onLockedSeason: (Int) -> Unit) {
    val vm = LocalGraph.current.dashboard
    SeasonPhasePicker(
        seasons = seasons,
        selectedSeason = vm.selectedSeason,
        selectedPhase = vm.selectedPhase,
        isSeasonLocked = vm::isSeasonLocked,
        onSelectSeason = { season -> if (vm.isSeasonLocked(season)) onLockedSeason(season) else vm.selectSeason(season) },
        onSelectPhase = { vm.selectedPhase = it },
    ) { open ->
        RinkNavPill(
            SeasonLabel.display(vm.selectedSeason) + " · " + vm.selectedPhase.label,
            open,
            description = "Season and season type, ${SeasonLabel.display(vm.selectedSeason)}, ${vm.selectedPhase.label}",
        )
    }
}

/** A hidden tab must never take a tap meant for the visible one. */
private fun Modifier.swallowTouches(): Modifier = pointerInput(Unit) {
    awaitPointerEventScope {
        while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
    }
}

/** The nav-bar season pill for a screen that keeps its own season and phase (Trends, a team page). */
@Composable
fun SeasonPhaseNavPillFor(
    seasons: List<Int>,
    selectedSeason: Int,
    selectedPhase: com.jackwallner.hockey.model.SeasonPhase,
    onSelectSeason: (Int) -> Unit,
    onSelectPhase: (com.jackwallner.hockey.model.SeasonPhase) -> Unit,
) {
    val vm = LocalGraph.current.dashboard
    SeasonPhasePicker(
        seasons = seasons,
        selectedSeason = selectedSeason,
        selectedPhase = selectedPhase,
        isSeasonLocked = vm::isSeasonLocked,
        onSelectSeason = onSelectSeason,
        onSelectPhase = onSelectPhase,
    ) { open ->
        RinkNavPill(
            SeasonLabel.display(selectedSeason) + " · " + selectedPhase.label,
            open,
            description = "Season and season type, ${SeasonLabel.display(selectedSeason)}, ${selectedPhase.label}",
        )
    }
}
