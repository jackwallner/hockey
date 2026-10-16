package com.jackwallner.hockey

import com.jackwallner.hockey.data.PriceCopy
import com.jackwallner.hockey.data.StoreLinks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the purchase copy. Every surface follows the approved Baseball Savvy
 * StatScout ladder, as on iOS: the button names the trial when one applies,
 * and the billed amount sits on its own `priceLead` line directly above the
 * button, one type step louder than the button label.
 *
 * Deliberate platform difference: the renewal sentence names Google Play and has
 * no "24 hours" clause (Play has no such rule), so these tests pin the Play copy.
 */
class PriceDisclosureTest {
    private val renew = "Auto-renews unless cancelled before the end of the current period. " +
        "Manage or cancel in Google Play › Payments & subscriptions."

    @Test
    fun renewalCopyIsThePlaySentence() {
        assertEquals(renew, PriceCopy.RENEW)
    }

    @Test
    fun trialEligibleButtonNamesTheTrial() {
        assertEquals("Start 7-day free trial", PriceCopy.directCTALabel("$7.99 / year", "7-day free trial", false))
        assertEquals("Start 7-day free trial", PriceCopy.directCTALabel("$1.49 / month", "7-day free trial", false))
    }

    @Test
    fun noTrialLeftNamesThePrice() {
        assertEquals("Try StatScout+ for $7.99 / year", PriceCopy.directCTALabel("$7.99 / year", null, false))
    }

    /** A lapsed subscriber has already used the trial, so a win-back never offers it again. */
    @Test
    fun winbackNeverOffersTheTrial() {
        for (trial in listOf(null, "7-day free trial")) {
            val label = PriceCopy.directCTALabel("$7.99 / year", trial, true)
            assertEquals("Restart StatScout+ for $7.99 / year", label)
            assertFalse(label, label.lowercase().contains("trial"))
        }
    }

    @Test
    fun planPickerCTANamesTheActionNotTheOffer() {
        assertEquals("Start Free Trial", PriceCopy.planPickerCTALabel(isLifetime = false, trialEligible = true))
        assertEquals("Subscribe", PriceCopy.planPickerCTALabel(isLifetime = false, trialEligible = false))
        assertEquals("Unlock Lifetime", PriceCopy.planPickerCTALabel(isLifetime = true, trialEligible = false))
    }

    /** A non-consumable has no introductory offer, so eligibility never leaks a trial onto the lifetime button. */
    @Test
    fun lifetimePlanNeverOffersATrial() {
        assertEquals("Unlock Lifetime", PriceCopy.planPickerCTALabel(isLifetime = true, trialEligible = true))
    }

    /** The billed amount belongs to the `priceLead` line above this button. */
    @Test
    fun planPickerCTANeverCarriesAPrice() {
        for (isLifetime in listOf(true, false)) {
            for (trialEligible in listOf(true, false)) {
                val label = PriceCopy.planPickerCTALabel(isLifetime, trialEligible)
                assertFalse("\"$label\" states an amount the price line already shows", label.any { it.isDigit() } || label.contains("$"))
            }
        }
    }

    @Test
    fun trialDisclosureNamesTheTrialThenThePrice() {
        assertEquals("7-Day Free Trial, then $7.99 / year. $renew", PriceCopy.disclosureText("$7.99 / year", true, "7-day free trial"))
    }

    @Test
    fun subscriptionWithoutATrialLeadsWithThePrice() {
        assertEquals("$1.49 / month. $renew", PriceCopy.disclosureText("$1.49 / month", true, null))
    }

    /** A non-consumable must not claim to auto-renew. */
    @Test
    fun lifetimeIsNeverDescribedAsASubscription() {
        val text = PriceCopy.disclosureText("$15.99", false, null)
        assertEquals("$15.99. One-time purchase. Lifetime access, no subscription.", text)
        assertFalse(text, text.contains("Auto-renews"))
    }

    @Test
    fun everyDisclosureStatesThePriceAndTheTerms() {
        data class Case(val price: String, val isSubscription: Boolean, val trial: String?)
        val cases = listOf(
            Case("$7.99 / year", true, "7-day free trial"),
            Case("$7.99 / year", true, null),
            Case("$1.49 / month", true, "3-day free trial"),
            Case("$15.99", false, null),
        )
        for (c in cases) {
            val text = PriceCopy.disclosureText(c.price, c.isSubscription, c.trial)
            assertTrue("\"$text\" omits the price", text.contains(c.price))
            if (c.isSubscription) assertTrue("\"$text\" omits the renewal and cancel terms", text.contains(renew))
            c.trial?.let { assertTrue("\"$text\" omits the trial", text.lowercase().contains(it.lowercase())) }
        }
    }

    /** Android points at its own hosted pages, not Apple's EULA. */
    @Test
    fun legalLinksResolve() {
        assertEquals("https://jackwallner.github.io/hockey/android-terms.html", StoreLinks.TERMS_URL)
        assertEquals("https://jackwallner.github.io/hockey/android-privacy.html", StoreLinks.PRIVACY_URL)
    }
}
