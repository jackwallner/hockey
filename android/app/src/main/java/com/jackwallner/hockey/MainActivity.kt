package com.jackwallner.hockey

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.lifecycleScope
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.RootScreen
import com.jackwallner.hockey.ui.theme.StatScoutTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as StatScoutApplication).graph

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val graph = graph
        if (savedInstanceState == null) {
            graph.review.recordAppLaunch()
            graph.diagnostics.recordAppOpen()
            DebugLaunchOptions.apply(graph, intent)
        }
        // Light icons over the midnight bar at the top; dark icons over the cream canvas below.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        lifecycleScope.launch { graph.subscriptions.start() }
        setContent {
            CompositionLocalProvider(LocalGraph provides graph) {
                StatScoutTheme {
                    // Test tags double as resource ids so UI Automator and capture scripts can find controls.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) { RootScreen(graph) }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Renewals, restores and late grants flip the app promptly, like iOS's foreground refresh.
        lifecycleScope.launch { graph.subscriptions.refreshCustomerInfo() }
    }

    override fun onStop() {
        super.onStop()
        graph.subscriptions.syncConversionAttributes()
    }
}
