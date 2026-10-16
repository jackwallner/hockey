package com.jackwallner.hockey

import com.jackwallner.hockey.data.ConversionDiagnostics
import com.jackwallner.hockey.data.InMemoryStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The fleet paywall record, checked in this app's own build: the counts, the
 * conversion freeze, RevenueCat's silent 40-character key limit, and the rule
 * that nothing here may carry free text or health data.
 */
class PaywallFunnelTest {
    // A fresh store per test: these counters outlive a launch and would otherwise carry between tests.
    private val diagnostics = ConversionDiagnostics(InMemoryStore(), FakeClock())
    private val attributes get() = diagnostics.subscriberAttributes

    @Test
    fun countsPitchesPerSurfaceAndInTotal() {
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        diagnostics.recordPitchView("statscout_paywall_recent_form")

        assertEquals("3", attributes["pitch_views_total"])
        assertEquals("2", attributes["pitch_views_upgrade"])
        assertEquals("recent_form", attributes["pitch_last"])
    }

    /** Someone never shown a paywall has nothing to say about paywalls; zeros would read as a funnel failure. */
    @Test
    fun noAttributesBeforeAnyPitchIsSeen() {
        diagnostics.recordAppOpen()
        assertTrue(attributes.isEmpty())
    }

    @Test
    fun recordsHowEarlyTheFirstPitchArrived() {
        diagnostics.recordAppOpen()
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("statscout_paywall_upgrade")

        assertEquals("2", attributes["opens_before_first_pitch"])
        assertEquals("0", attributes["days_since_install"])
    }

    @Test
    fun theEarlinessPairIsFrozenOnTheFirstPitchOnly() {
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("statscout_paywall_recent_form")

        assertEquals("1", attributes["opens_before_first_pitch"])
    }

    /** No recorded app open means no install stamp. Absent is the honest answer; zero would claim a first-day ask. */
    @Test
    fun anInstallThatPredatesThisCodeReportsNoAge() {
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        assertNull(attributes["days_since_install"])
        assertNotNull(attributes["pitch_views_total"])
    }

    @Test
    fun conversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        diagnostics.recordPitchView("statscout_paywall_recent_form")
        diagnostics.recordConversion("yearly", true, "default")
        // A pitch after the sale must not rewrite how they converted.
        diagnostics.recordPitchView("statscout_paywall_upgrade")

        assertEquals("recent_form", attributes["converted_surface"])
        assertEquals("2", attributes["pitch_views_at_convert"])
        assertEquals("yearly", attributes["converted_plan"])
        assertEquals("true", attributes["converted_with_trial"])
        assertEquals("default", attributes["converted_offering"])
    }

    @Test
    fun onlyTheFirstConversionIsRecorded() {
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        diagnostics.recordConversion("monthly", true, null)
        // A renewal or plan change is not a new answer to what sold them.
        diagnostics.recordConversion("yearly", false, null)

        assertEquals("monthly", attributes["converted_plan"])
        assertEquals("true", attributes["converted_with_trial"])
    }

    @Test
    fun attributeKeysStayInsideRevenueCatsLimit() {
        // RevenueCat drops a key over 40 characters, silently.
        diagnostics.recordPitchView("statscout_paywall_" + "a".repeat(80))
        for (key in attributes.keys) assertTrue("attribute key too long: $key", key.length <= 40)
    }

    @Test
    fun noAttributeCarriesFreeTextOrHealthData() {
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("statscout_paywall_upgrade")
        diagnostics.recordConversion("monthly", false, null)

        for ((key, value) in attributes) {
            assertFalse("$key looks like free text: $value", value.contains(" "))
            assertTrue("$key is too long to be a label", value.length <= 64)
        }
    }
}
