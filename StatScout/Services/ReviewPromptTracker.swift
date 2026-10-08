import Foundation

extension Notification.Name {
    /// Posted after a satisfaction moment, host may present the enjoyment funnel after a short delay.
    static let statscoutPositiveMomentForReview = Notification.Name("com.jackwallner.football.positiveMomentForReview")
}

/// How the user last resolved the in-app review / feedback prompt.
enum ReviewPromptOutcome: String, Sendable {
    case openedWriteReview
    case submittedFeedback
}

/// Persists launch counts, positive moments, and review-prompt eligibility.
@MainActor
enum ReviewPromptTracker {
    private static let defaults = UserDefaults.standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"
    private static let softDeferKey = "reviewPrompt.softDefer"
    private static let distinctDaysKey = "reviewPrompt.distinctUseDays"
    private static let lastUseDayKey = "reviewPrompt.lastUseDay"

    // Enjoyment pre-filter keeps unhappy users off the public Store; thresholds
    // match the Vitals portfolio standard for passive prompts.
    static let minimumLaunchCount = 5
    static let minimumDaysSinceFirstOpen = 7
    static let minimumPositiveMoments = 3
    static let cooldownDays = 120
    /// Shorter cooldown after "Maybe later". Apple's `requestReview()` is
    /// rate-limited and silently shows nothing much of the time, so the common
    /// case was a user who never saw a prompt being locked out for four months.
    static let softDeferCooldownDays = 30
    /// Separate calendar days of use before a returning-user prompt is allowed.
    /// Three taps in one sitting isn't a habit; three days is.
    static let minimumDistinctUseDays = 3

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var outcome: ReviewPromptOutcome? {
        get {
            guard let raw = defaults.string(forKey: outcomeKey) else { return nil }
            return ReviewPromptOutcome(rawValue: raw)
        }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: outcomeKey)
            } else {
                defaults.removeObject(forKey: outcomeKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    /// Skip passive prompts during UI tests / Fastlane snapshot runs.
    static var isAutomationRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
            || ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
    }

    /// Distinct calendar days the app has been opened.
    static var distinctUseDays: Int {
        max(defaults.integer(forKey: distinctDaysKey), 0)
    }

    /// Bump the distinct-day counter once per calendar day. This is the
    /// retention signal the funnel leans on now: the old trigger fired on the
    /// third player profile opened, which a single sitting satisfies and which
    /// says nothing about whether someone values the app.
    private static func recordUseDay(now: Date) {
        // Local calendar on purpose: "a different day" should mean the user's
        // day, not UTC's. Built from components rather than a cached formatter,
        // which isn't Sendable under Swift 6 strict concurrency.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let key = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        guard defaults.string(forKey: lastUseDayKey) != key else { return }
        defaults.set(key, forKey: lastUseDayKey)
        defaults.set(distinctUseDays + 1, forKey: distinctDaysKey)
    }

    static func recordAppLaunch(now: Date = .now) {
        recordUseDay(now: now)
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    static func recordPositiveMoment() {
        positiveMomentCount += 1
        hasPendingPositiveMoment = true
        NotificationCenter.default.post(name: .statscoutPositiveMomentForReview, object: nil)
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome == nil else { return false }
        guard let last = lastShownDate else { return true }
        let days = isSoftDeferred ? softDeferCooldownDays : cooldownDays
        return now.timeIntervalSince(last) >= TimeInterval(days) * 86_400
    }

    /// True after "Maybe later" until the next hard `markShown` or outcome.
    /// Callers must NOT call `markShown()` on sheet dismiss while this is set,
    /// that clears the flag and reinstates the full cooldown, which is exactly
    /// the leak this exists to close.
    static var isSoftDeferred: Bool {
        defaults.bool(forKey: softDeferKey)
    }

    /// The user said they like the app, then deferred the store review. We fire
    /// `requestReview()`, which Apple often no-ops, so keep the door open with
    /// the short cooldown instead of jailing them for the full term.
    static func markSoftDeferred(now: Date = .now) {
        lastShownDate = now
        defaults.set(true, forKey: softDeferKey)
        consumePendingPositiveMoment()
    }

    static func canPresentEnjoymentPrompt(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard !isAutomationRun else { return false }
        guard hasCompletedOnboarding else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard positiveMomentCount >= minimumPositiveMoments else { return false }
        // Came back on separate days, the strongest signal available that
        // someone actually values the app rather than having poked it once.
        guard distinctUseDays >= minimumDistinctUseDays else { return false }
        guard let first = firstAppOpenDate else { return false }
        let minInterval = TimeInterval(minimumDaysSinceFirstOpen) * 86_400
        guard now.timeIntervalSince(first) >= minInterval else { return false }
        return true
    }

    static func shouldShowAfterPositiveMoment(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canPresentEnjoymentPrompt(hasCompletedOnboarding: hasCompletedOnboarding, now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        defaults.set(false, forKey: softDeferKey)
        consumePendingPositiveMoment()
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    static func markFeedbackSubmitted() {
        outcome = .submittedFeedback
        markShown()
    }
}
