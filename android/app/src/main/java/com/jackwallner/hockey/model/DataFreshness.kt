package com.jackwallner.hockey.model

import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The small, stable vocabulary the app shows while a release moves through the pipeline. */
enum class DataFreshnessStatus(val accessibilityName: String) {
    READY("Ready"),
    CHECKING("Checking"),
    PENDING("Waiting for source data"),
    PARTIAL("Partial data"),
    STALE("Stale data"),
    OFFLINE("Offline"),
    FAILED("Refresh failed");

    val raw: String get() = name.lowercase()

    companion object {
        fun from(raw: String): DataFreshnessStatus = when (raw.lowercase()) {
            "ready", "published", "complete", "completed", "healthy", "unchanged" -> READY
            "checking", "probing", "building", "retrying" -> CHECKING
            "pending", "waiting", "waiting_for_source", "source_pending" -> PENDING
            "partial", "degraded" -> PARTIAL
            "stale", "regressed" -> STALE
            "offline", "unavailable" -> OFFLINE
            "failed", "error" -> FAILED
            else -> READY
        }
    }
}

/** The hockey a dataset covers, separate from when its row was written. */
data class DataCoverage(
    val asOf: Instant,
    val week: Int?,
    val phase: SeasonPhase,
    val gamesIncluded: Int? = null,
    val expectedGames: Int? = null,
)

/** `data_refresh_status`, accepting the older names during rollout. */
data class DataFreshness(
    val status: DataFreshnessStatus = DataFreshnessStatus.READY,
    val revision: String? = null,
    val sourcePublishedAt: Instant? = null,
    val publishedAt: Instant? = null,
    val checkedAt: Instant? = null,
    val coverage: DataCoverage? = null,
    val message: String? = null,
    val isCached: Boolean = false,
    /** MoneyPuck shot file (`shots_status`) and NHL summary (`summary_status`) publisher state. */
    val shotsStatus: String? = null,
    val summaryStatus: String? = null,
) {
    /** True while the MoneyPuck shot file or the NHL summary trails the published games. */
    val isAdvancedPending: Boolean
        get() = listOf(shotsStatus, summaryStatus).any { status ->
            val s = status?.lowercase() ?: return@any false
            s != "ready" && s != "not_applicable" && s != "unavailable"
        }

    fun toJson(): JsonObject = buildJsonObject {
        put("status", status.raw)
        revision?.let { put("revision", it) }
        sourcePublishedAt?.let { put("source_published_at", ISO.format(it)) }
        publishedAt?.let { put("published_at", ISO.format(it)) }
        checkedAt?.let { put("checked_at", ISO.format(it)) }
        coverage?.let { c ->
            put("as_of", ISO.format(c.asOf))
            c.week?.let { put("week", it) }
            put("season_type", c.phase.raw)
            c.gamesIncluded?.let { put("games_included", it) }
            c.expectedGames?.let { put("expected_games", it) }
        }
        message?.let { put("message", it) }
        put("is_cached", isCached)
        shotsStatus?.let { put("shots_status", it) }
        summaryStatus?.let { put("summary_status", it) }
    }

    companion object {
        private val ISO = DateTimeFormatter.ISO_INSTANT

        fun fromJson(o: JsonObject): DataFreshness {
            val nested = o.obj("coverage")
            val rawAsOf = o.string("as_of") ?: o.string("max_game_date") ?: nested?.string("as_of")
            val rawWeek = o.int("week") ?: o.int("end_week") ?: o.int("max_week") ?: nested?.int("week") ?: nested?.int("end_week")
            val rawPhase = o.string("season_type") ?: nested?.string("season_type")
            val gamesIncluded = o.int("games_included") ?: o.int("games_through") ?: o.int("observed_games")
                ?: nested?.int("games_included") ?: nested?.int("games_through")
            val expectedGames = o.int("expected_games") ?: nested?.int("expected_games")
            val coverage = rawAsOf?.let(::parseDate)?.let { asOf ->
                DataCoverage(asOf, rawWeek, rawPhase?.let { SeasonPhase.from(it) } ?: SeasonPhase.REGULAR, gamesIncluded, expectedGames)
            }
            return DataFreshness(
                status = DataFreshnessStatus.from(o.string("status") ?: "ready"),
                revision = o.string("revision") ?: o.string("refresh_id") ?: o.string("source_fingerprint"),
                sourcePublishedAt = o.string("source_published_at")?.let(::parseDate),
                publishedAt = o.string("published_at")?.let(::parseDate),
                checkedAt = o.string("checked_at")?.let(::parseDate) ?: o.string("last_checked_at")?.let(::parseDate),
                coverage = coverage,
                message = o.string("message") ?: o.string("error_message"),
                isCached = o.bool("is_cached") ?: false,
                shotsStatus = o.string("shots_status"),
                summaryStatus = o.string("summary_status"),
            )
        }
    }
}
