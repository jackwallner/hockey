package com.jackwallner.hockey

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.hockey.data.ConversionDiagnostics
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.FavoritesStore
import com.jackwallner.hockey.data.OfflineStatcastApi
import com.jackwallner.hockey.data.PaywallGate
import com.jackwallner.hockey.data.PlayerCaching
import com.jackwallner.hockey.data.ReviewPromptTracker
import com.jackwallner.hockey.data.SharedPreferencesStore
import com.jackwallner.hockey.data.StatcastApi
import com.jackwallner.hockey.data.StatcastProviding
import com.jackwallner.hockey.data.SubscriptionService
import com.jackwallner.hockey.data.SystemAppClock
import com.jackwallner.hockey.data.TwoTierPlayerCache
import kotlinx.coroutines.MainScope

/** Every long-lived object the screens share, built once per process. */
class AppGraph(context: Context) {
    val appContext: Context = context.applicationContext
    val scope = MainScope()
    val clock = SystemAppClock()
    val defaults = SharedPreferencesStore(appContext)
    val review = ReviewPromptTracker(defaults, clock)
    val diagnostics = ConversionDiagnostics(defaults, clock)
    val subscriptions = SubscriptionService(appContext, defaults, diagnostics)
    val favorites = FavoritesStore(defaults)
    val paywallGate = PaywallGate()

    /** Null when the build has no feed configuration: the app says so instead of showing an empty league. */
    val api: StatcastProviding? = if (BuildConfig.SUPABASE_URL.startsWith("https://") && BuildConfig.SUPABASE_ANON_KEY.isNotBlank()) {
        StatcastApi(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY) { if (BuildConfig.BUILD_TYPE != "release") android.util.Log.d("StatScoutLoad", it) }
    } else null

    /** Tab name to open, set by debug launch options and consumed by the root screen. */
    var pendingTab by mutableStateOf<String?>(null)

    /** Debug screenshot runs swap in a fixture feed before anything reads [dashboard]. */
    var feedOverride: Pair<StatcastProviding, PlayerCaching?>? = null

    val dashboard by lazy {
        DashboardViewModel(
            provider = feedOverride?.first ?: api ?: OfflineStatcastApi,
            cache = if (feedOverride != null) feedOverride?.second else TwoTierPlayerCache(appContext.cacheDir) {
                runCatching { appContext.assets.open(HISTORY_ASSET) }.getOrNull()
            },
        defaults = defaults,
        scope = scope,
            log = { if (BuildConfig.BUILD_TYPE != "release") android.util.Log.d("StatScoutLoad", it) },
        )
    }
}

/** Gzip JSON of every past season. Not `.gz`: the packager would inflate and rename it. */
private const val HISTORY_ASSET = "players-historical.bin"
