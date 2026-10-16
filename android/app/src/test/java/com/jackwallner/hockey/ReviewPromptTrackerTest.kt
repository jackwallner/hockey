package com.jackwallner.hockey

import com.jackwallner.hockey.data.InMemoryStore
import com.jackwallner.hockey.data.ReviewPromptTracker
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Gates on the Play review card, matching the iOS ReviewPromptTrackerTests. */
class ReviewPromptTrackerTest {
    private val store = InMemoryStore()
    private val clock = FakeClock()
    private val tracker = ReviewPromptTracker(store, clock)

    private fun launches(count: Int) = repeat(count) { tracker.recordAppLaunch() }

    private fun advanceDays(days: Long) {
        clock.instant = clock.instant.plus(Duration.ofDays(days))
    }

    @Test
    fun asksFromTheSecondLaunch() {
        launches(2)
        assertTrue(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    @Test
    fun neverAsksInTheFirstSession() {
        launches(1)
        assertFalse(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    @Test
    fun requiresFinishedOnboarding() {
        launches(9)
        assertFalse(tracker.canRequestReview(hasCompletedOnboarding = false))
    }

    @Test
    fun automationRunsNeverAsk() {
        launches(9)
        tracker.isAutomationRun = true
        assertFalse(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    @Test
    fun waitsOutTheCooldown() {
        launches(9)
        tracker.markShown()
        advanceDays(29)
        assertFalse(tracker.canRequestReview(hasCompletedOnboarding = true))
        advanceDays(2)
        assertTrue(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    @Test
    fun openingTheReviewPageEndsTheAsks() {
        launches(9)
        tracker.markOpenedWriteReview()
        advanceDays(400)
        assertFalse(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    @Test
    fun sendingFeedbackStillLeavesARatingAsk() {
        launches(9)
        tracker.markFeedbackSent()
        assertTrue(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    @Test
    fun feedbackAfterWriteReviewKeepsTheStop() {
        launches(9)
        tracker.markOpenedWriteReview()
        tracker.markFeedbackSent()
        assertEquals(ReviewPromptTracker.OPENED_WRITE_REVIEW, tracker.outcome)
        assertFalse(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    /** Installs that answered the old feedback sheet can still be asked to rate. */
    @Test
    fun oldFeedbackOutcomeNoLongerBlocks() {
        launches(9)
        store.putString("reviewPrompt.outcome", ReviewPromptTracker.SUBMITTED_FEEDBACK)
        assertTrue(tracker.canRequestReview(hasCompletedOnboarding = true))
    }

    /** An ask skipped because a sheet was up must leave the moment pending for the next one. */
    @Test
    fun blockedAskKeepsTheMomentPending() {
        launches(9)
        assertFalse(tracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding = true))
        tracker.recordPositiveMoment()
        assertTrue(tracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding = true))
        assertTrue(tracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding = true))
        tracker.markShown()
        assertFalse(tracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding = true))
    }
}
