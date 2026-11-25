import StoreKit
import SwiftUI
import UIKit

extension View {
    /// Calls Apple's rating prompt a few seconds after a good moment, with no
    /// question in front of it (App Review 5.6.1). Bump `moment` when a good
    /// moment happens (see `ReviewMoment`).
    ///
    /// The view still being on screen and `isClear` are checked again when the
    /// wait is over, so the prompt never lands on a sheet opened in the
    /// meantime. A skipped ask costs nothing: the next good moment asks.
    func requestsReview(after moment: Int, isClear: @escaping () -> Bool = { ReviewRequestScreen.isClear }) -> some View {
        modifier(ReviewRequestModifier(moment: moment, isClear: isClear))
    }
}

enum ReviewRequestScreen {
    /// No sheet, alert, full-screen cover, paywall or trial pitch is presented
    /// over any window. Those belong to the screens that raise them, so ask
    /// UIKit rather than tracking flags.
    @MainActor static var isClear: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .allSatisfy { $0.rootViewController?.presentedViewController == nil }
    }
}

private struct ReviewRequestModifier: ViewModifier {
    let moment: Int
    let isClear: () -> Bool

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService
    @Environment(\.requestReview) private var requestReview
    /// False while onboarding or an update showcase covers the tabs.
    @Environment(\.isEnabled) private var isEnabled
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
            .onChange(of: moment) { _, _ in schedule() }
    }

    private var mayAsk: Bool {
        hasCompletedOnboarding
            && isEnabled
            && store.isOn(.ratingPrompt)
            && ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: hasCompletedOnboarding)
    }

    private func schedule() {
        guard mayAsk else { return }
        Task { @MainActor in
            // Let the result land first.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard onScreen, isClear(), mayAsk else { return }
            ReviewPromptTracker.markShown()
            requestReview()
        }
    }
}
