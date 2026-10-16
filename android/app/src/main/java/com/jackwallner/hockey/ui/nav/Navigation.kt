package com.jackwallner.hockey.ui.nav

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.SeasonPhase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob

/** Every pushed destination in the app; the iOS `navigationDestination` routes. */
sealed interface Route {
    data object Root : Route
    data class PlayerProfile(val player: Player) : Route
    data class Game(val gameId: String) : Route
    data class TeamSchedule(val team: String) : Route
    data class Team(val abbr: String) : Route
    /** A drill-down carries its season and phase: a 2022 playoff profile opens the 2022 playoff board. */
    /** [position] picks the cohort to rank: percentiles compare within forwards, defensemen or goalies. */
    data class Metric(val label: String, val category: MetricCategory, val season: Int? = null, val phase: SeasonPhase? = null, val position: PlayerPositionGroup? = null) : Route
    data class StandardStat(val stat: String, val position: PlayerPositionGroup, val season: Int? = null, val phase: SeasonPhase? = null) : Route
    data class Comparison(val playerA: Player, val playerB: Player) : Route
    data class YearCompare(val player: Player) : Route
    data class TeamComparison(val teamA: String, val teamB: String, val seasonA: Int, val phaseA: SeasonPhase, val seasonB: Int, val phaseB: SeasonPhase) : Route
    data class YearCompareRoute(val playerId: Int, val playerName: String, val phase: SeasonPhase) : Route
    data object Standings : Route
    data object PowerRankings : Route
    data object Settings : Route
    data object Glossary : Route
    data object FollowingStats : Route
    data class Custom(val key: String, val content: @Composable () -> Unit) : Route
}

internal data class Entry(val id: Int, val route: Route)

/** One navigation stack, the Compose counterpart of a `NavigationStack`. */
@Stable
class Navigator {
    private var nextId = 1
    private val entries = mutableStateListOf(Entry(0, Route.Root))
    var lastWasPop by mutableStateOf(false)
        private set
    /** Bumps on every pop, so a screen can react to coming back into view. */
    var popCount by mutableIntStateOf(0)
        private set

    val depth: Int get() = entries.size
    val top: Route get() = entries.last().route
    internal val topEntry: Entry get() = entries.last()

    fun push(route: Route) {
        lastWasPop = false
        entries.add(Entry(nextId++, route))
    }

    fun pop(): Boolean {
        if (entries.size <= 1) return false
        lastWasPop = true
        release(entries.removeAt(entries.lastIndex).id)
        popCount++
        return true
    }

    fun popToRoot() {
        if (entries.size <= 1) return
        lastWasPop = true
        while (entries.size > 1) release(entries.removeAt(entries.lastIndex).id)
        popCount++
    }

    /** Objects that outlive a screen leaving composition while it sits under another. */
    internal val retained = mutableMapOf<Int, MutableMap<String, Any?>>()

    private fun release(id: Int) {
        retained.remove(id)?.values?.forEach { (it as? AutoCloseable)?.close() }
    }
}

private val LocalEntryId = staticCompositionLocalOf { -1 }

/** Like `remember`, but survives being covered by a pushed screen; released on pop. */
@Suppress("UNCHECKED_CAST")
@Composable
fun <T> rememberRetained(key: String, init: () -> T): T {
    val navigator = LocalNavigator.current
    val id = LocalEntryId.current
    return remember(id, key) {
        val bucket = navigator.retained.getOrPut(id) { mutableMapOf() }
        if (bucket.containsKey(key)) bucket[key] as T else init().also { bucket[key] = it }
    }
}

val LocalNavigator = staticCompositionLocalOf<Navigator> { error("No navigator") }

/** Renders the top of a stack with a push/pop slide and keeps every screen below it alive. */
@Composable
fun NavStack(navigator: Navigator, enabled: Boolean = true, content: @Composable (Route) -> Unit) {
    val holder = rememberSaveableStateHolder()
    BackHandler(enabled = enabled && navigator.depth > 1) { navigator.pop() }
    AnimatedContent(
        targetState = navigator.topEntry,
        transitionSpec = {
            val duration = 300
            if (navigator.lastWasPop) {
                (slideInHorizontally(tween(duration)) { -it / 3 } + fadeIn(tween(duration))) togetherWith
                    slideOutHorizontally(tween(duration)) { it }
            } else {
                slideInHorizontally(tween(duration)) { it } togetherWith
                    (slideOutHorizontally(tween(duration)) { -it / 3 } + fadeOut(tween(duration)))
            }
        },
        modifier = Modifier.fillMaxSize(),
        label = "nav",
    ) { entry ->
        holder.SaveableStateProvider(entry.id) {
            CompositionLocalProvider(LocalNavigator provides navigator, LocalEntryId provides entry.id) {
                Box(Modifier.fillMaxSize()) { content(entry.route) }
            }
        }
    }
}

/** A screen's retained state with a coroutine scope that ends when the screen is popped. */
abstract class ScreenModel : AutoCloseable {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun close() {
        scope.coroutineContext[Job]?.cancel()
    }
}
