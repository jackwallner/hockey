package com.jackwallner.hockey.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.hockey.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import java.security.MessageDigest
import java.util.Date
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

/** A one-tap CTA's result. Only NEEDS_PLAN_PICKER may open the plan picker. */
sealed interface DirectPurchaseOutcome {
    data object Unlocked : DirectPurchaseOutcome
    data object Pending : DirectPurchaseOutcome
    data object Cancelled : DirectPurchaseOutcome
    data class Failed(val message: String) : DirectPurchaseOutcome
    data object NeedsPlanPicker : DirectPurchaseOutcome
}

class PurchaseException(message: String) : Exception(message)

internal fun purchaseOutcome(code: PurchasesErrorCode, userCancelled: Boolean): PurchaseOutcome? = when {
    userCancelled || code == PurchasesErrorCode.PurchaseCancelledError -> PurchaseOutcome.CANCELLED
    code == PurchasesErrorCode.PaymentPendingError -> PurchaseOutcome.PENDING
    else -> null
}

internal fun managedSubscriptionId(activeSubscriptions: Set<String>): String? =
    activeSubscriptions.map { it.substringBefore(":") }.sorted().firstOrNull()

private fun Period.toPlanPeriod(): PlanPeriod? {
    val unit = when (unit) {
        Period.Unit.DAY -> PeriodUnit.DAY
        Period.Unit.WEEK -> PeriodUnit.WEEK
        Period.Unit.MONTH -> PeriodUnit.MONTH
        Period.Unit.YEAR -> PeriodUnit.YEAR
        else -> return null
    }
    return PlanPeriod(value, unit)
}

/** Reusable access for Play reviewers, separate from purchases and developer overrides. */
class ReviewAccess(private val defaults: KeyValueStore, private val expectedDigest: String) {
    val isGranted: Boolean get() = expectedDigest.length == 64 && defaults.getString(KEY) == expectedDigest

    fun activate(code: String): Boolean {
        if (!expectedDigest.matches(Regex("[a-f0-9]{64}"))) return false
        val digest = MessageDigest.getInstance("SHA-256").digest(code.trim().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        if (!MessageDigest.isEqual(digest.toByteArray(), expectedDigest.toByteArray())) return false
        defaults.putString(KEY, expectedDigest)
        return true
    }

    private companion object {
        const val KEY = "subscription.playReviewAccess"
    }
}

/**
 * RevenueCat behind the `pro` entitlement, shown as StatScout+. Debug
 * builds use the Test Store key and release builds the Play key; neither ever
 * runs on the other. Every price and trial comes from the store.
 */
class SubscriptionService(
    private val context: Context,
    private val defaults: KeyValueStore,
    private val diagnostics: ConversionDiagnostics,
) {
    private val reviewAccess = ReviewAccess(defaults, BuildConfig.PLAY_REVIEW_CODE_SHA256)
    private var entitlementActive by mutableStateOf(false)
    private var reviewGranted by mutableStateOf(reviewAccess.isGranted)
    private var forcePro by mutableStateOf(false)

    /** The single gate the whole app reads. */
    val isPro: Boolean get() = entitlementActive || reviewGranted || forcePro

    var isConfigured by mutableStateOf(false)
        private set
    var isLoadingProducts by mutableStateOf(false)
        private set
    var purchaseInFlight by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set
    var plans by mutableStateOf<List<Plan>>(emptyList())
        private set
    var offeringId by mutableStateOf<String?>(null)
        private set
    /** Google trials are for people who never subscribed in this app. */
    var hasSubscriptionHistory by mutableStateOf(false)
        private set
    /** Until customer info answers, never promise a trial. */
    var introEligibilityResolved by mutableStateOf(false)
        private set
    var activeProductId by mutableStateOf<String?>(null)
        private set
    /** Held an entitlement that has since expired: the win-back variant. */
    var isLapsed by mutableStateOf(false)
        private set

    private var packages: List<Package> = emptyList()
    private var customerInfoLoaded = false
    private var isPreview = false
    private val impressionsThisSession = mutableSetOf<String>()

    // MARK: Debug and review access

    fun forceProForDebug(value: Boolean = true) {
        if (BuildConfig.DEBUG) forcePro = value
    }

    /** Debug screenshots and UI tests: a local plan stack with no store behind it. */
    fun loadPreviewPlans(plans: List<Plan>, history: Boolean = false) {
        if (!BuildConfig.DEBUG) return
        this.plans = plans
        packages = emptyList()
        hasSubscriptionHistory = history
        introEligibilityResolved = true
        isConfigured = true
        isPreview = true
        lastError = null
    }

    fun activateReviewAccess(code: String): Boolean {
        if (!reviewAccess.activate(code)) return false
        reviewGranted = true
        return true
    }

    // MARK: Derived offer copy

    fun plan(kind: PackageKind): Plan? = plans.firstOrNull { it.kind == kind }

    val yearlyPlan: Plan? get() = plan(PackageKind.YEARLY)
    val monthlyPlan: Plan? get() = plan(PackageKind.MONTHLY)
    val lifetimePlan: Plan? get() = plan(PackageKind.LIFETIME)

    /** Unknown eligibility never promises a trial on Play (a returning subscriber gets none). */
    fun isEligibleForIntroOffer(plan: Plan): Boolean = plan.introOfferLabel != null && introEligibilityResolved && !hasSubscriptionHistory

    val isYearlyTrialAvailable: Boolean get() = yearlyPlan?.let(::isEligibleForIntroOffer) ?: false

    val upgradeCTALabel: String get() = PriceCopy.upgradeCTALabel(isYearlyTrialAvailable)

    val defaultUpgradeTrigger: PaywallTrigger get() = if (isLapsed) PaywallTrigger.Winback else PaywallTrigger.Upgrade

    fun directCTALabel(trigger: PaywallTrigger): String {
        yearlyPlan?.let { yearly ->
            return PriceCopy.directCTALabel(yearly.priceLabel, yearly.introOfferLabel.takeIf { isEligibleForIntroOffer(yearly) }, trigger == PaywallTrigger.Winback)
        }
        lifetimePlan?.let { return "${if (trigger == PaywallTrigger.Winback) "Restart" else "Unlock"} StatScout+ for ${it.priceFormatted}" }
        return if (trigger == PaywallTrigger.Winback) "Restart StatScout+" else "Unlock StatScout+"
    }

    val paywallBlurCTA: String get() = directCTALabel(PaywallTrigger.Upgrade)

    val paywallBlurSubtext: String?
        get() {
            val yearly = yearlyPlan ?: return null
            if (!isEligibleForIntroOffer(yearly)) return null
            return "Then ${yearly.priceLabel}. Cancel anytime."
        }

    fun disclosureText(plan: Plan): String = PriceCopy.disclosureText(
        price = plan.priceLabel,
        isSubscription = plan.kind != PackageKind.LIFETIME,
        trial = plan.introOfferLabel.takeIf { isEligibleForIntroOffer(plan) },
    )

    val yearlyCTADisclosureText: String? get() = yearlyPlan?.let { disclosureText(it) }

    fun planPickerCTALabel(plan: Plan): String =
        PriceCopy.planPickerCTALabel(plan.kind == PackageKind.LIFETIME, isEligibleForIntroOffer(plan))

    /** Onboarding pitches monthly: the smaller number is the smaller first commitment. */
    val onboardingMonthlyCTALabel: String
        get() {
            val monthly = monthlyPlan ?: return "Upgrade to StatScout+"
            return PriceCopy.directCTALabel(monthly.priceLabel, monthly.introOfferLabel.takeIf { isEligibleForIntroOffer(monthly) }, false)
        }

    val onboardingMonthlyDisclosureText: String? get() = monthlyPlan?.let { disclosureText(it) }

    val monthlyAnchorPriceLabel: String? get() = monthlyPlan?.monthlyEquivalentAnchorLabel

    // MARK: Store

    suspend fun start() {
        if (!configureIfNeeded()) return
        refreshCustomerInfo()
        fetchProducts()
    }

    suspend fun refreshCustomerInfo() {
        if (!configureIfNeeded() || isPreview) return
        try {
            apply(Purchases.sharedInstance.awaitCustomerInfo())
            lastError = null
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
    }

    suspend fun fetchProducts() {
        if (!configureIfNeeded() || isPreview) return
        if (isLoadingProducts) {
            while (isLoadingProducts) delay(50)
            return
        }
        isLoadingProducts = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering: Offering? = offerings.all[ANDROID_OFFERING_ID] ?: offerings.current
            val loaded = offering?.availablePackages.orEmpty().sortedWith(compareBy<Package> { kind(it).ordinal }.thenBy { it.product.id })
            offeringId = offering?.identifier
            packages = loaded
            plans = loaded.map(::plan)
            lastError = if (loaded.isEmpty()) "Subscription options are temporarily unavailable. Please try again." else null
            if (!customerInfoLoaded) refreshCustomerInfo()
            introEligibilityResolved = customerInfoLoaded
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            packages = emptyList()
            plans = emptyList()
            lastError = "Couldn't load subscription options. Check your connection and try again."
        } finally {
            isLoadingProducts = false
        }
    }

    /** Feeds RevenueCat's paywall encounters; a custom paywall emits none of its own. */
    fun trackPaywallImpression(id: String, oncePerSession: Boolean = false) {
        if (forcePro) return
        if (oncePerSession && !impressionsThisSession.add(id)) return
        diagnostics.recordPitchView(id)
        if (!isConfigured || isPreview) return
        syncConversionAttributes()
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(CustomPaywallImpressionParams(id)) }
    }

    /** Attributes, not extra impressions: impressions would inflate the encounter rate. */
    fun syncConversionAttributes() {
        if (!isConfigured || isPreview) return
        val attributes = diagnostics.subscriberAttributes.toMutableMap()
        if (attributes.isEmpty()) return
        offeringId?.let { attributes["offering_id"] = it }
        runCatching { Purchases.sharedInstance.setAttributes(attributes) }
    }

    /** A cancel is an outcome, not an error. Throws only with a user-facing message. */
    suspend fun purchase(activity: Activity, plan: Plan?): PurchaseOutcome {
        if (isPreview && plan != null) {
            forcePro = true
            return PurchaseOutcome.PURCHASED
        }
        val pkg = plan?.let { p -> packages.firstOrNull { it.identifier == p.packageId } }
        if (!configureIfNeeded() || pkg == null) throw PurchaseException(UNAVAILABLE)
        purchaseInFlight = true
        val startedTrial = isEligibleForIntroOffer(plan)
        // A returning subscriber buys the base plan; Play would refuse the trial offer anyway.
        val option = if (startedTrial) pkg.product.defaultOption else pkg.product.subscriptionOptions?.basePlan
        val params = if (option != null) {
            PurchaseParams.Builder(activity, option).presentedOfferingContext(pkg.presentedOfferingContext).build()
        } else PurchaseParams.Builder(activity, pkg).build()
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(params)
            apply(result.customerInfo)
            if (!entitlementActive) return PurchaseOutcome.PENDING
            diagnostics.recordConversion(pkg.product.id, startedTrial, pkg.presentedOfferingContext.offeringIdentifier)
            syncConversionAttributes()
            PurchaseOutcome.PURCHASED
        } catch (error: PurchasesTransactionException) {
            purchaseOutcome(error.code, error.userCancelled) ?: run {
                lastError = "Couldn't complete the purchase. Please try again."
                throw PurchaseException(lastError!!)
            }
        } finally {
            purchaseInFlight = false
        }
    }

    /**
     * The single conversion path behind every pitch: a CTA that names an offer
     * is that offer, never a second pitch.
     */
    suspend fun purchaseYearlyDirect(activity: Activity): DirectPurchaseOutcome {
        if (yearlyPlan == null && offeringId == null) fetchProducts()
        val yearly = yearlyPlan ?: return DirectPurchaseOutcome.NeedsPlanPicker
        return try {
            when (purchase(activity, yearly)) {
                PurchaseOutcome.PURCHASED -> DirectPurchaseOutcome.Unlocked
                PurchaseOutcome.PENDING -> DirectPurchaseOutcome.Pending
                PurchaseOutcome.CANCELLED -> DirectPurchaseOutcome.Cancelled
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            DirectPurchaseOutcome.Failed(lastError ?: "Couldn't complete the purchase. Please try again.")
        }
    }

    /** Leaves [lastError] set when nothing was restored, like iOS. */
    suspend fun restorePurchases() {
        lastError = null
        if (isPreview) return
        if (!configureIfNeeded()) {
            lastError = UNAVAILABLE
            return
        }
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            if (!isPro) lastError = "No active StatScout+ purchase was found for this Google Play account."
        } catch (error: CancellationException) {
            throw error
        } catch (error: PurchasesException) {
            lastError = if (error.code == PurchasesErrorCode.PaymentPendingError) {
                "Google Play is still processing your payment. StatScout+ unlocks as soon as it completes."
            } else "Couldn't restore purchases. Try again."
        } catch (_: Throwable) {
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    private fun apply(info: CustomerInfo) {
        customerInfoLoaded = true
        hasSubscriptionHistory = info.allExpirationDatesByProduct.isNotEmpty()
        introEligibilityResolved = plans.isNotEmpty() || packages.isNotEmpty()
        entitlementActive = hasProEntitlement(info)
        activeProductId = managedSubscriptionId(info.activeSubscriptions)
        val now = Date()
        isLapsed = !entitlementActive && info.entitlements.all.values.any { !it.isActive && (it.expirationDate?.before(now) ?: false) }
    }

    /** The entitlement, with product ownership as a backstop for a mis-mapped dashboard. */
    private fun hasProEntitlement(info: CustomerInfo): Boolean {
        val active = info.entitlements.active
        if (active[ENTITLEMENT]?.isActive == true || active[FALLBACK_ENTITLEMENT]?.isActive == true) return true
        if (info.nonSubscriptionTransactions.any { it.productIdentifier == StatScoutProduct.LIFETIME }) return true
        val recurring = setOf(StatScoutProduct.YEARLY, StatScoutProduct.MONTHLY)
        return info.activeSubscriptions.any { it.substringBefore(":") in recurring }
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        val builder = PurchasesConfiguration.Builder(context, key)
        // Test Store runs share one tester instead of a fresh anonymous customer
        // per install, so test installs don't inflate the live project's
        // customer charts. Never with the Play key: real buyers would share one identity.
        if (key.startsWith("test_")) builder.appUserID(QA_APP_USER_ID)
        Purchases.configure(builder.build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private fun kind(pkg: Package): PackageKind = when (pkg.packageType) {
        PackageType.LIFETIME -> PackageKind.LIFETIME
        PackageType.ANNUAL -> PackageKind.YEARLY
        PackageType.MONTHLY -> PackageKind.MONTHLY
        else -> PackageKind.fromIdentifiers(pkg.identifier, pkg.product.id)
    }

    private fun plan(pkg: Package): Plan {
        val price = pkg.product.price
        val free = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase ?: pkg.product.defaultOption?.freePhase
        return Plan(
            packageId = pkg.identifier,
            productId = pkg.product.id,
            kind = kind(pkg),
            priceMicros = price.amountMicros,
            priceFormatted = price.formatted,
            currencyCode = price.currencyCode,
            period = pkg.product.period?.toPlanPeriod(),
            trial = free?.billingPeriod?.toPlanPeriod(),
            title = pkg.product.title,
        )
    }

    companion object {
        const val ENTITLEMENT = "pro"
        const val FALLBACK_ENTITLEMENT = "pro"
        private const val ANDROID_OFFERING_ID = "android"
        private const val QA_APP_USER_ID = "qa-android"
        private const val UNAVAILABLE = "Google Play isn't reachable right now. Check your connection and try again."
    }
}
