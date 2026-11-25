import Foundation

/// Everything RevenueCat can change without a release, read from the current
/// offering's metadata (a running Experiment's variant included). Every
/// variant ships in the binary; a missing, non-string or unknown value is the
/// control, which is what shipped before the reader existed. Keys a switch
/// reads must be set the same on every offering, or an Experiment arm would
/// flip them as a side effect. Wording tests go through the offering metadata
/// key `trial_cta`.
///
/// DEBUG builds can pin any key for captures: `-hockey.rc.<key> <value>`.

/// The trial button's wording. The control is exactly the copy that shipped:
/// `Start <trial>` on the one-tap buttons (onboarding, blur gates, trial
/// sheet) and `Start Free Trial` on the plan picker. An account that already
/// used its trial never sees any of these (3.1.2): the callers fall back to
/// the price or `Subscribe` wording before this type is asked.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: today's copy, "Start 7-day free trial".
    case control = "seven_day"
    case my
    case your

    enum Surface: Sendable {
        /// Onboarding, the blurred gates and the trial sheet: sentence case.
        case direct
        /// The plan picker (`PaywallView`): title case.
        case planPicker
    }

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .control)
    }

    /// `trial` is the real intro offer, such as "7-day free trial". Only the
    /// control names it.
    func title(_ surface: Surface, trial: String = "7-day free trial") -> String {
        switch (self, surface) {
        case (.control, .direct): return "Start \(trial)"
        case (.control, .planPicker): return "Start Free Trial"
        case (.my, .direct): return "Start my free trial"
        case (.my, .planPicker): return "Start My Free Trial"
        case (.your, .direct): return "Start your free trial"
        case (.your, .planPicker): return "Start Your Free Trial"
        }
    }
}

/// Remote off switches, for what is worth pausing without a release. On
/// unless the metadata says "off".
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt after a good moment.
    case ratingPrompt = "rating_prompt"
}

enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string,
    /// or not one of the shipped variants.
    static func value<T: RawRepresentable>(_ key: String, in metadata: [String: Any]?, default fallback: T) -> T
    where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-hockey.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

extension StoreService {
    var trialCTAArm: TrialCTA { TrialCTA.from(metadata: remoteMetadata) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool { RemoteConfig.isOn(remoteSwitch, in: remoteMetadata) }
}
