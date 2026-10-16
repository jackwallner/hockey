package com.jackwallner.hockey.data

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

interface AppClock {
    fun now(): Instant
    fun zone(): ZoneId
    fun today(): LocalDate = now().atZone(zone()).toLocalDate()
}

class SystemAppClock : AppClock {
    override fun now(): Instant = Instant.now()
    override fun zone(): ZoneId = ZoneId.systemDefault()
}

object StoreLinks {
    const val PACKAGE = "com.jackwallner.hockey"
    const val PLAY_LISTING_URL = "https://play.google.com/store/apps/details?id=$PACKAGE"
    const val PLAY_MARKET_URI = "market://details?id=$PACKAGE"
    const val FEEDBACK_EMAIL = "jackwallner+bb@gmail.com"
    const val SUPPORT_URL = "https://jackwallner.github.io/hockey/support.html"
    const val PRIVACY_URL = "https://jackwallner.github.io/hockey/android-privacy.html"
    const val TERMS_URL = "https://jackwallner.github.io/hockey/android-terms.html"

    fun manageSubscriptionURL(productId: String?): String =
        if (productId == null) "https://play.google.com/store/account/subscriptions"
        else "https://play.google.com/store/account/subscriptions?sku=$productId&package=$PACKAGE"

    /** Same address and subject as the iOS feedback draft. */
    fun feedbackMail(subject: String): Uri = Uri.parse("mailto:$FEEDBACK_EMAIL?subject=${Uri.encode(subject)}")
}

/**
 * Gates on the Play in-app review card, with the iOS keys and gates. Google
 * forbids a question before the card, so a positive moment that clears these
 * gates goes straight to `launchReviewFlow`; feedback is its own row.
 */
class ReviewPromptTracker(private val defaults: KeyValueStore, private val clock: AppClock) {
    /** Tests and screenshot runs never trigger the store card. */
    var isAutomationRun = false

    val appLaunchCount: Int get() = maxOf(defaults.getInt(LAUNCH_COUNT), 0)
    val positiveMomentCount: Int get() = maxOf(defaults.getInt(POSITIVE_MOMENTS), 0)
    val outcome: String? get() = defaults.getString(OUTCOME)
    private val hasPendingPositiveMoment: Boolean get() = defaults.getBoolean(PENDING)

    fun recordAppLaunch() {
        if (!defaults.contains(FIRST_OPEN)) defaults.putLong(FIRST_OPEN, clock.now().toEpochMilli())
        defaults.putInt(LAUNCH_COUNT, appLaunchCount + 1)
    }

    fun recordPositiveMoment() {
        defaults.putInt(POSITIVE_MOMENTS, positiveMomentCount + 1)
        defaults.putBoolean(PENDING, true)
    }

    fun consumePendingPositiveMoment() = defaults.putBoolean(PENDING, false)

    /** Only opening the review page ends the asks: someone who sent feedback can still rate. */
    private fun passivePromptAllowed(): Boolean {
        if (outcome == OPENED_WRITE_REVIEW) return false
        if (!defaults.contains(LAST_SHOWN)) return true
        return clock.now().toEpochMilli() - defaults.getLong(LAST_SHOWN) >= COOLDOWN_DAYS * DAY_MS
    }

    /** The only tenure gate is "not the first session": a second cold start. */
    fun canRequestReview(hasCompletedOnboarding: Boolean): Boolean {
        if (isAutomationRun || !hasCompletedOnboarding || !passivePromptAllowed()) return false
        return appLaunchCount >= MINIMUM_LAUNCH_COUNT
    }

    fun shouldRequestAfterPositiveMoment(hasCompletedOnboarding: Boolean): Boolean =
        hasPendingPositiveMoment && canRequestReview(hasCompletedOnboarding)

    /** Spent when requested, not when answered: Play may show nothing at all. */
    fun markShown() {
        defaults.putLong(LAST_SHOWN, clock.now().toEpochMilli())
        consumePendingPositiveMoment()
    }

    /** The Settings "Rate" row. Ends the passive asks for good. */
    fun markOpenedWriteReview() {
        defaults.putString(OUTCOME, OPENED_WRITE_REVIEW)
        markShown()
    }

    /** Sending feedback never stops the rating asks, and never overwrites a write-review stop. */
    fun markFeedbackSent() {
        if (outcome == OPENED_WRITE_REVIEW) return
        defaults.putString(OUTCOME, SUBMITTED_FEEDBACK)
    }

    companion object {
        /** Ask early: most installs are gone within a week. */
        const val MINIMUM_LAUNCH_COUNT = 2
        /** Days between our calls. Play applies its own quota on top. */
        const val COOLDOWN_DAYS = 30L

        const val OPENED_WRITE_REVIEW = "openedWriteReview"
        /** Written by the old feedback funnel; it no longer stops anything. */
        const val SUBMITTED_FEEDBACK = "submittedFeedback"

        private const val LAUNCH_COUNT = "reviewPrompt.appLaunchCount"
        private const val FIRST_OPEN = "reviewPrompt.firstAppOpenDate"
        private const val LAST_SHOWN = "reviewPrompt.lastShownDate"
        private const val OUTCOME = "reviewPrompt.outcome"
        private const val POSITIVE_MOMENTS = "reviewPrompt.positiveMomentCount"
        private const val PENDING = "reviewPrompt.pendingPositiveMoment"
    }
}

/**
 * On-device record of how someone met StatScout+ before buying, mirrored onto
 * the RevenueCat customer as the fleet-wide attributes. Counts, dates and
 * surface names only.
 */
class ConversionDiagnostics(private val defaults: KeyValueStore, private val clock: AppClock) {
    fun recordAppOpen() {
        if (!defaults.contains(INSTALLED_AT)) defaults.putLong(INSTALLED_AT, millis())
        defaults.putInt(APP_OPENS, defaults.getInt(APP_OPENS) + 1)
    }

    fun recordPitchView(impressionId: String) {
        val surface = impressionId.removePrefix(PREFIX)
        defaults.putInt(TOTAL_VIEWS, defaults.getInt(TOTAL_VIEWS) + 1)
        defaults.putInt(views(surface), defaults.getInt(views(surface)) + 1)
        defaults.putString(LAST_SURFACE, surface)
        if (!defaults.contains(FIRST_SEEN)) {
            defaults.putLong(FIRST_SEEN, millis())
            defaults.putInt(OPENS_BEFORE_FIRST_PITCH, defaults.getInt(APP_OPENS))
            if (defaults.contains(INSTALLED_AT)) defaults.putInt(DAYS_TO_FIRST_PITCH, daysSince(defaults.getLong(INSTALLED_AT)))
        }
    }

    /** Only the first conversion is recorded. */
    fun recordConversion(plan: String, startedTrial: Boolean, offeringId: String?) {
        if (defaults.contains(CONVERTED_ON)) return
        defaults.putString(CONVERTED_ON, defaults.getString(LAST_SURFACE) ?: "unknown")
        defaults.putInt(VIEWS_AT_CONVERT, defaults.getInt(TOTAL_VIEWS))
        defaults.putString(CONVERTED_PLAN, plan)
        defaults.putBoolean(CONVERTED_WITH_TRIAL, startedTrial)
        defaults.putLong(CONVERTED_AT, millis())
        offeringId?.let { defaults.putString(CONVERTED_OFFERING, it) }
        if (defaults.contains(FIRST_SEEN)) defaults.putInt(DAYS_TO_CONVERT, daysSince(defaults.getLong(FIRST_SEEN)))
    }

    /** Empty until the first pitch. Keys stay under RevenueCat's 40-character limit. */
    val subscriberAttributes: Map<String, String>
        get() {
            val total = defaults.getInt(TOTAL_VIEWS)
            if (total <= 0) return emptyMap()
            val attributes = mutableMapOf("pitch_views_total" to total.toString())
            for (key in defaults.keys()) {
                if (!key.startsWith(VIEWS_PREFIX) || key == TOTAL_VIEWS) continue
                val count = defaults.getInt(key)
                if (count > 0) attributes["pitch_views_${key.removePrefix(VIEWS_PREFIX)}".take(40)] = count.toString()
            }
            defaults.getString(LAST_SURFACE)?.let { attributes["pitch_last"] = it }
            if (defaults.contains(FIRST_SEEN)) {
                val first = defaults.getLong(FIRST_SEEN)
                attributes["pitch_first_seen"] = Instant.ofEpochMilli(first).toString()
                attributes["days_since_first_pitch"] = daysSince(first).toString()
            }
            if (defaults.contains(DAYS_TO_FIRST_PITCH)) attributes["days_since_install"] = defaults.getInt(DAYS_TO_FIRST_PITCH).toString()
            if (defaults.contains(OPENS_BEFORE_FIRST_PITCH)) attributes["opens_before_first_pitch"] = defaults.getInt(OPENS_BEFORE_FIRST_PITCH).toString()
            defaults.getString(CONVERTED_ON)?.let { convertedOn ->
                attributes["converted_surface"] = convertedOn
                attributes["converted_at"] = Instant.ofEpochMilli(defaults.getLong(CONVERTED_AT)).toString()
                attributes["pitch_views_at_convert"] = defaults.getInt(VIEWS_AT_CONVERT).toString()
                attributes["days_to_convert"] = defaults.getInt(DAYS_TO_CONVERT).toString()
                attributes["converted_plan"] = defaults.getString(CONVERTED_PLAN) ?: "unknown"
                attributes["converted_with_trial"] = if (defaults.getBoolean(CONVERTED_WITH_TRIAL)) "true" else "false"
                defaults.getString(CONVERTED_OFFERING)?.let { attributes["converted_offering"] = it }
            }
            return attributes
        }

    private fun millis() = clock.now().toEpochMilli()
    private fun daysSince(millis: Long): Int = maxOf(0, ((millis() - millis) / DAY_MS).toInt())
    private fun views(surface: String) = "$VIEWS_PREFIX$surface"

    private companion object {
        const val PREFIX = "statscout_paywall_"
        const val VIEWS_PREFIX = "conv.pitchViews."
        const val TOTAL_VIEWS = "conv.pitchViews.total"
        const val FIRST_SEEN = "conv.pitchFirstSeen"
        const val LAST_SURFACE = "conv.pitchLastSurface"
        const val INSTALLED_AT = "conv.installedAt"
        const val APP_OPENS = "conv.appOpens"
        const val OPENS_BEFORE_FIRST_PITCH = "conv.opensBeforeFirstPitch"
        const val DAYS_TO_FIRST_PITCH = "conv.daysToFirstPitch"
        const val CONVERTED_ON = "conv.convertedOn"
        const val CONVERTED_AT = "conv.convertedAt"
        const val VIEWS_AT_CONVERT = "conv.viewsAtConvert"
        const val DAYS_TO_CONVERT = "conv.daysToConvert"
        const val CONVERTED_PLAN = "conv.convertedPlan"
        const val CONVERTED_WITH_TRIAL = "conv.convertedWithTrial"
        const val CONVERTED_OFFERING = "conv.convertedOffering"
    }
}

/**
 * Favorited players and team. Free on purpose: following is what makes the app
 * yours; the paid part is the payoff (recent-form deltas on the players you follow).
 */
class FavoritesStore(private val defaults: KeyValueStore) {
    var playerIds by mutableStateOf(load())
        private set
    var team by mutableStateOf(defaults.getString(TEAM_KEY))
        private set

    private fun load(): List<Int> =
        defaults.getString(PLAYERS_KEY)?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: emptyList()

    fun isFavorite(playerId: Int): Boolean = playerId in playerIds

    fun toggleFavorite(playerId: Int) {
        playerIds = if (playerId in playerIds) playerIds - playerId else playerIds + playerId
        defaults.putString(PLAYERS_KEY, playerIds.joinToString(","))
    }

    fun isFavoriteTeam(abbr: String): Boolean = team == abbr

    fun setFavoriteTeam(abbr: String?) {
        team = abbr
        if (abbr != null) defaults.putString(TEAM_KEY, abbr) else defaults.remove(TEAM_KEY)
    }

    /** Anything followed: a review-funnel signal that someone is invested. */
    val hasAnyFavorite: Boolean get() = playerIds.isNotEmpty() || team != null

    private companion object {
        const val PLAYERS_KEY = "favorites.playerIds"
        const val TEAM_KEY = "favoriteTeam"
    }
}
