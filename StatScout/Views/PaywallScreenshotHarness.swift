#if DEBUG
import SwiftUI

struct PaywallScreenshotHarness: View {
    let mode: PaywallScreenshotMode
    @StateObject private var store = StoreService.shared

    @State private var onboardingComplete = false

    var body: some View {
        Group {
            switch mode {
            case .trial:
                trialBackdrop {
                    TrialPitchSheet(trigger: .upgrade)
                }
            case .onboarding:
                OnboardingCards(
                    viewModel: DashboardViewModel(),
                    hasCompletedOnboarding: $onboardingComplete
                )
            case .monthly, .yearly, .lifetime:
                PaywallView(trigger: .upgrade)
            }
        }
        .environmentObject(store)
        .task {
            // Render the real paywall with mock products (no RC configure / no
            // StoreKit) so it works headless on the simulator for screenshots.
            if store.products.isEmpty { store.loadScreenshotProducts() }
        }
    }

    private func trialBackdrop<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            GridironPalette.canvas.ignoresSafeArea()
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack {
                Spacer()
                content()
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }
}
#endif
