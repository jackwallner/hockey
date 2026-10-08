import SwiftUI
import UIKit

/// Manual presentation from About bypasses passive eligibility gates.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    enum Presentation {
        case enjoymentPrompt
        case feedbackOnly
    }

    @Published var pendingPresentation: Presentation?

    private init() {}

    func requestEnjoymentPrompt() {
        pendingPresentation = .enjoymentPrompt
    }

    func requestFeedback() {
        pendingPresentation = .feedbackOnly
    }

    func clear() {
        pendingPresentation = nil
    }
}

enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case feedbackSubmitted
    case openedWriteReview
    /// User chose "Yes" but dismissed the pitch without opening the store, host may call `requestReview()` once in `onDismiss`.
    case enjoyedMaybeLater
}

struct ReviewPromptSheet: View {
    enum Step {
        case enjoyment
        case reviewPitch
        case feedback
    }

    let initialStep: Step
    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    init(initialStep: Step = .enjoyment, onFinish: @escaping (ReviewPromptDismissOutcome) -> Void) {
        self.initialStep = initialStep
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .enjoyment:
                    enjoymentContent
                case .reviewPitch:
                    reviewPitchContent
                case .feedback:
                    feedbackContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(GridironNavBarPublic())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        handleNotNow()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents(step == .feedback ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .background(GridironPalette.canvas.ignoresSafeArea())
    }

    private var navigationTitle: String {
        switch step {
        case .enjoyment: "Enjoying StatScout?"
        case .reviewPitch: "Support an indie app"
        case .feedback: "Help us improve"
        }
    }

    private var enjoymentContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(GridironPalette.turf)
                    .frame(width: 64, height: 64)
                Image(systemName: "football.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            Text("If StatScout is helping you scout the league, a quick rating on the App Store makes a real difference.")
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button {
                    step = .reviewPitch
                } label: {
                    primaryButtonLabel("Yes, I'm enjoying it")
                }
                .buttonStyle(.plain)

                Button {
                    step = .feedback
                } label: {
                    secondaryButtonLabel("Not really")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var reviewPitchContent: some View {
        VStack(spacing: 18) {
            Text("StatScout is built by one indie developer. No ads, no accounts, and your scouting data stays on your phone.")
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("An honest App Store review takes seconds and helps more fans find a clean NFL advanced-stats scout.")
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button {
                    ReviewPromptTracker.markOpenedWriteReview()
                    UIApplication.shared.open(AppStoreReviewLinks.writeReviewURL)
                    finish(.openedWriteReview)
                } label: {
                    primaryButtonLabel("Rate on the App Store")
                }
                .buttonStyle(.plain)

                Button {
                    ReviewPromptTracker.markShown()
                    finish(.enjoyedMaybeLater)
                } label: {
                    secondaryButtonLabel("Maybe later")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What would make StatScout work better for you?")
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $feedbackText)
                .font(GridironType.body)
                .frame(minHeight: 140)
                .padding(10)
                .background(GridironPalette.surface, in: RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                        .stroke(GridironPalette.hairline, lineWidth: 0.5)
                )
                .focused($feedbackFocused)

            Text("Opens your mail app with a draft to the developer. No analytics, just your words.")
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkTertiary)

            Button {
                sendFeedback()
            } label: {
                primaryButtonLabel("Send feedback")
            }
            .buttonStyle(.plain)
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear { feedbackFocused = true }
    }

    private func primaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(GridironType.bodyBold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(GridironPalette.turf, in: Capsule())
    }

    private func secondaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(GridironType.smallBold)
            .foregroundStyle(GridironPalette.linkBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private func handleNotNow() {
        ReviewPromptTracker.markShown()
        finish(.notNow)
    }

    private func sendFeedback() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.feedbackMailURL(body: trimmed) else { return }
        ReviewPromptTracker.markFeedbackSubmitted()
        UIApplication.shared.open(url)
        finish(.feedbackSubmitted)
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
        dismiss()
    }

    static func feedbackMailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "jackwallner+bb@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "StatScout feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
