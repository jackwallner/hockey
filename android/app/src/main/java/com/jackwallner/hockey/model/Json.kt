package com.jackwallner.hockey.model

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeParseException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/** The league's calendar: date-only columns are Eastern midnight. */
val EASTERN: ZoneId = ZoneId.of("America/New_York")

/** Thrown for a row the decoder cannot use; callers drop the row, not the page. */
class RowDecodeException(message: String) : Exception(message)

internal fun JsonObject.prim(key: String): JsonPrimitive? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }

internal fun JsonObject.string(key: String): String? = prim(key)?.takeIf { it.isString }?.contentOrNull

internal fun JsonObject.int(key: String): Int? = prim(key)?.let { p ->
    p.longOrNull?.toInt() ?: p.doubleOrNull?.takeIf { it == Math.floor(it) && !p.isString }?.toInt()
}

internal fun JsonObject.double(key: String): Double? = prim(key)?.takeIf { !it.isString }?.doubleOrNull

internal fun JsonObject.bool(key: String): Boolean? = prim(key)?.takeIf { !it.isString }?.booleanOrNull

internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

internal fun JsonObject.array(key: String): JsonArray? = this[key] as? JsonArray

internal fun JsonObject.requireString(key: String): String = string(key) ?: throw RowDecodeException("missing $key")

internal fun JsonObject.requireInt(key: String): Int = int(key) ?: throw RowDecodeException("missing $key")

/** A JSONB object of nullable numbers; nulls and non-numbers are dropped. */
internal fun JsonObject.numberMap(key: String): Map<String, Double> {
    val raw = obj(key) ?: return emptyMap()
    val out = LinkedHashMap<String, Double>(raw.size)
    for ((k, v) in raw) {
        val p = v as? JsonPrimitive ?: continue
        if (p is JsonNull || p.isString) continue
        p.doubleOrNull?.let { out[k] = it }
    }
    return out
}

/** Decodes each element, keeping the ones that parse (Swift's `Lenient<T>`). */
internal fun <T> JsonElement.lenientList(decode: (JsonObject) -> T): List<T> =
    (this as? JsonArray).orEmpty().mapNotNull { element ->
        (element as? JsonObject)?.let { runCatching { decode(it) }.getOrNull() }
    }

/**
 * ISO-8601 with any fractional precision, or a bare `yyyy-MM-dd` read as
 * Eastern midnight. PostgREST emits variable-length fractions, so this never
 * relies on a fixed three-digit form.
 */
fun parseDate(raw: String): Instant? {
    val trimmed = raw.trim()
    try {
        return OffsetDateTime.parse(trimmed).toInstant()
    } catch (_: DateTimeParseException) {
    }
    try {
        return Instant.parse(trimmed)
    } catch (_: DateTimeParseException) {
    }
    // "2026-09-13 17:25:00+00" style (Postgres text form).
    try {
        val normalized = trimmed.replace(' ', 'T').let { if (Regex("[+-]\\d\\d$").containsMatchIn(it)) "$it:00" else it }
        return OffsetDateTime.parse(normalized).toInstant()
    } catch (_: DateTimeParseException) {
    }
    return parseDay(trimmed)
}

/** "YYYY-MM-DD" (or the date prefix of a longer string) as Eastern midnight. */
fun parseDay(raw: String, zone: ZoneId = EASTERN): Instant? = try {
    LocalDate.parse(raw.trim().take(10)).atStartOfDay(zone).toInstant()
} catch (_: DateTimeParseException) {
    null
}
