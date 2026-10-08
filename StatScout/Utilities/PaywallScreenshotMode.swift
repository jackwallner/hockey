#if DEBUG
import Foundation

/// Launch with `-PaywallSnapshot trial|monthly|yearly|lifetime|onboarding` to render
/// paywall surfaces for portfolio screenshot capture (see `capture-portfolio-paywall-screenshots.sh`).
///
/// `onboarding` opens straight on the last onboarding page, the one carrying the
/// purchase CTA. It is a purchase point like any other, and the only way to see
/// it on a simulator is to seed it: RevenueCat is deliberately never configured
/// there, so without the mock products this harness loads it renders with no
/// price at all. That gap is exactly how the missing disclosure reached App
/// Review unnoticed.
enum PaywallScreenshotMode: String {
    case trial
    case monthly
    case yearly
    case lifetime
    case onboarding

    static var current: PaywallScreenshotMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PaywallSnapshot"),
              index + 1 < arguments.count else { return nil }
        return PaywallScreenshotMode(rawValue: arguments[index + 1])
    }

    static var isActive: Bool { current != nil }
}
#endif
