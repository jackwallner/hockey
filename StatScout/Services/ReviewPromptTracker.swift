import Foundation

extension Notification.Name {
    /// Posted after a satisfaction moment. The root view may request the system
    /// rating prompt after a short delay, with no question in front of it.
    static let statscoutPositiveMomentForReview = Notification.Name("com.jackwallner.hockey.positiveMomentForReview")
}

/// What the user did about a review. Only opening the review page ends the
/// passive asks: someone who sent feedback can still rate.
enum ReviewPromptOutcome: String, Sendable {
    case openedWriteReview
    /// Written by the old feedback funnel. Kept so those installs decode it;
    /// it no longer stops anything.
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

    /// Ask early. Most installs are gone within a week, and a rating from
    /// someone on their second visit beats no rating at all. The only tenure
    /// gate is "not the first session": a second cold start.
    static let minimumLaunchCount = 2
    /// Days between our calls. Apple shows the prompt at most three times a
    /// year per device and decides each time, so this paces the asks rather
    /// than the user's answers.
    static let cooldownDays = 30

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
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
            || ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
        #else
        return false
        #endif
    }

    static func recordAppLaunch(now: Date = .now) {
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
        guard outcome != .openedWriteReview else { return false }
        guard let last = lastShownDate else { return true }
        let cooldown = TimeInterval(cooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    static func canRequestReview(hasCompletedOnboarding: Bool, now: Date = .now) -> Bool {
        guard !isAutomationRun else { return false }
        guard hasCompletedOnboarding else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        return appLaunchCount >= minimumLaunchCount
    }

    static func shouldRequestAfterPositiveMoment(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(hasCompletedOnboarding: hasCompletedOnboarding, now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        consumePendingPositiveMoment()
    }

    /// The Settings "Rate" row. Ends the passive asks for good.
    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    /// Sending feedback never stops the rating asks, and never overwrites a
    /// write-review stop.
    static func markFeedbackSent() {
        guard outcome != .openedWriteReview else { return }
        outcome = .submittedFeedback
    }
}
