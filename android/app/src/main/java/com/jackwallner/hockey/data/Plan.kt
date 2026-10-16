package com.jackwallner.hockey.data

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency

/** Paywall display order: yearly first, then monthly, then lifetime. */
enum class PackageKind {
    YEARLY, MONTHLY, LIFETIME, OTHER;

    companion object {
        fun fromIdentifiers(vararg ids: String): PackageKind {
            val lower = ids.map { it.lowercase() }
            return when {
                lower.any { it.substringBefore(":") == StatScoutProduct.LIFETIME || "lifetime" in it } -> LIFETIME
                lower.any { StatScoutProduct.YEARLY in it || "annual" in it || "yearly" in it } -> YEARLY
                lower.any { StatScoutProduct.MONTHLY in it || "monthly" in it } -> MONTHLY
                else -> OTHER
            }
        }
    }
}

object StatScoutProduct {
    const val LIFETIME = "com.jackwallner.hockey.pro"
    const val YEARLY = "com.jackwallner.hockey.pro.yearly"
    const val MONTHLY = "com.jackwallner.hockey.pro.monthly"
}

enum class PeriodUnit { DAY, WEEK, MONTH, YEAR }

data class PlanPeriod(val value: Int, val unit: PeriodUnit)

/**
 * A purchasable plan detached from the RevenueCat SDK, so every price string
 * the paywall shows is a pure function of what the store returned. Ports the
 * `Package` extensions in the iOS `StoreService.swift`.
 */
data class Plan(
    val packageId: String,
    val productId: String,
    val kind: PackageKind,
    val priceMicros: Long,
    val priceFormatted: String,
    val currencyCode: String,
    val period: PlanPeriod?,
    val trial: PlanPeriod?,
    val title: String = "",
) {
    val price: BigDecimal get() = BigDecimal.valueOf(priceMicros, 6)

    val displayName: String
        get() = when (kind) {
            PackageKind.LIFETIME -> "Lifetime"
            PackageKind.YEARLY -> "Yearly"
            PackageKind.MONTHLY -> "Monthly"
            PackageKind.OTHER -> title
        }

    /** "$7.99 / year", or the bare price for a one-time product. */
    val priceLabel: String
        get() {
            val p = period ?: return priceFormatted
            val unit = unitName(p.unit, p.value)
            return if (p.value == 1) "$priceFormatted / $unit" else "$priceFormatted / ${p.value} $unit"
        }

    private val monthsInPeriod: BigDecimal?
        get() {
            val p = period ?: return null
            val v = BigDecimal(p.value)
            return when (p.unit) {
                PeriodUnit.DAY -> v.divide(BigDecimal(30), MathContext.DECIMAL64)
                PeriodUnit.WEEK -> v.multiply(BigDecimal(7)).divide(BigDecimal(30), MathContext.DECIMAL64)
                PeriodUnit.MONTH -> v
                PeriodUnit.YEAR -> v.multiply(BigDecimal(12))
            }
        }

    /** Per-month price for a recurring plan longer than a month: "$0.67". */
    val monthlyEquivalentLabel: String?
        get() {
            val months = monthsInPeriod ?: return null
            if (months <= BigDecimal.ONE) return null
            return currency(price.divide(months, MathContext.DECIMAL64))
        }

    /** "$1.49/mo" for monthly, the per-month equivalent otherwise. */
    val monthlyEquivalentAnchorLabel: String?
        get() = when (kind) {
            PackageKind.MONTHLY -> "$priceFormatted/mo"
            else -> monthlyEquivalentLabel?.let { "$it/mo" }
        }

    /** "7-day free trial" when the plan carries a free phase. */
    val introOfferLabel: String?
        get() {
            val t = trial ?: return null
            if (t.unit == PeriodUnit.WEEK) return "${t.value * 7}-day free trial"
            val unit = unitName(t.unit, t.value)
            return "${t.value}-${if (t.value == 1) unit else unit.dropLast(1)} free trial"
        }

    private fun currency(amount: BigDecimal): String {
        val format = NumberFormat.getCurrencyInstance().apply {
            runCatching { currency = Currency.getInstance(currencyCode) }
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }
        return format.format(amount.setScale(2, RoundingMode.HALF_EVEN))
    }

    private fun unitName(unit: PeriodUnit, value: Int): String = when (unit) {
        PeriodUnit.DAY -> if (value == 1) "day" else "days"
        PeriodUnit.WEEK -> if (value == 1) "week" else "weeks"
        PeriodUnit.MONTH -> if (value == 1) "month" else "months"
        PeriodUnit.YEAR -> if (value == 1) "year" else "years"
    }
}

/** Integer savings the yearly plan offers against twelve monthly payments. */
fun yearlySavingsPercent(yearly: Plan, monthly: Plan?): Int? {
    if (yearly.kind != PackageKind.YEARLY || monthly == null) return null
    val twelve = monthly.price.multiply(BigDecimal(12))
    if (twelve <= BigDecimal.ZERO || yearly.price >= twelve) return null
    val saving = twelve.subtract(yearly.price).divide(twelve, MathContext.DECIMAL64).multiply(BigDecimal(100))
    val percent = saving.setScale(0, RoundingMode.HALF_UP).toInt()
    return percent.takeIf { it > 0 }
}

/** The copy every purchase surface uses, as pure functions of the offer. */
object PriceCopy {
    const val RENEW = "Auto-renews unless cancelled before the end of the current period. Manage or cancel in Google Play › Payments & subscriptions."

    /** Navigation affordances that open the offer: "Try Free" or "Upgrade". */
    fun upgradeCTALabel(trialAvailable: Boolean): String = if (trialAvailable) "Try Free" else "Upgrade"

    /**
     * The approved Baseball Savvy StatScout ladder: the button names the trial when one applies,
     * and the billed amount sits on its own `priceLead` line directly above it, one type step
     * louder. A win-back never leads with the trial: a lapsed subscriber has already used it.
     */
    fun directCTALabel(price: String, trial: String?, isWinback: Boolean): String {
        if (!isWinback && trial != null) return "Start $trial"
        return "${if (isWinback) "Restart" else "Try"} StatScout+ for $price"
    }

    /** The plan picker's button names the action, never a price. */
    fun planPickerCTALabel(isLifetime: Boolean, trialEligible: Boolean): String {
        if (isLifetime) return "Unlock Lifetime"
        return if (trialEligible) "Start Free Trial" else "Subscribe"
    }

    fun disclosureText(price: String, isSubscription: Boolean, trial: String?): String {
        if (!isSubscription) return "$price. One-time purchase. Lifetime access, no subscription."
        trial ?: return "$price. $RENEW"
        return "${trial.capitalizeWords()}, then $price. $RENEW"
    }
}

/** Swift's `String.capitalized`: every word, including after a hyphen. */
fun String.capitalizeWords(): String =
    split(" ").joinToString(" ") { word -> word.split("-").joinToString("-") { it.lowercase().replaceFirstChar(Char::uppercaseChar) } }
