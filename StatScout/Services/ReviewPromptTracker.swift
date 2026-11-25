import Foundation

/// The good moments that may ask for a rating. Nothing else asks on its own:
/// not launch, not a tab or screen appearing, not a count of opens.
enum ReviewMoment: Equatable, Sendable {
    /// The player just followed someone. Good once the watchlist holds three:
    /// they have built something they came back to use.
    case followedPlayer(followingCount: Int)
    /// A StatScout+ member is looking at a head-to-head comparison they built.
    case comparedPlayers(isPro: Bool)

    static let watchlistMilestone = 3

    var isGood: Bool {
        switch self {
        case .followedPlayer(let count): return count >= Self.watchlistMilestone
        case .comparedPlayers(let isPro): return isPro
        }
    }
}

/// What the user did about a review. Only opening the review page ends the
/// passive asks: someone who sent feedback can still rate.
enum ReviewPromptOutcome: String, Sendable {
    case openedWriteReview
    /// Written by the old feedback funnel. Kept so those installs decode it;
    /// it no longer stops anything.
    case submittedFeedback
}

/// Persists launch counts and review-prompt eligibility. No question goes in
/// front of Apple's prompt (App Review 5.6.1).
@MainActor
enum ReviewPromptTracker {
    private static let defaults = UserDefaults.standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"

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

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome != .openedWriteReview else { return false }
        guard let last = lastShownDate else { return true }
        let cooldown = TimeInterval(cooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    /// Whether a good moment right now may call `requestReview()`.
    static func canRequestReview(hasCompletedOnboarding: Bool, now: Date = .now) -> Bool {
        guard !isAutomationRun else { return false }
        guard hasCompletedOnboarding else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        return appLaunchCount >= minimumLaunchCount
    }

    /// Recorded when the call is made: Apple may show nothing, and there is
    /// no answer to wait for.
    static func markShown(now: Date = .now) {
        lastShownDate = now
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
