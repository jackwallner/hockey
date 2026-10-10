import SwiftUI

/// The app's one contextual offer: a compact, native half-sheet that names what
/// the user just reached for, makes three promises, and buys the yearly plan in
/// place.
///
/// It used to be a scrolling page: an 84pt hero circle, a headline, a subtitle,
/// and five benefit rows of two-line prose. On a phone that meant the pitch and
/// the button were never on screen together, so the sheet opened showing a
/// benefit list with its argument cut off mid-sentence and its CTA below the
/// fold. Everything here is now sized to land inside one detent on the smallest
/// supported phone: an inline glyph instead of a hero badge, three one-line
/// benefits instead of five paragraphs, and the CTA always visible.
struct TrialPitchSheet: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger

    private struct Benefit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    /// Three, never more, and each one line.
    ///
    /// Context-aware: `.playerScouting` (the player-page first-tap pitch) leads
    /// with current-season value, triggers that opened a history feature get the
    /// time-shaped pitch. The fourth and fifth bullets the list used to carry
    /// were the ones nobody scrolled to.
    private var benefits: [Benefit] {
        switch trigger {
        case .advancedBoxScore:
            return [
                Benefit(icon: "hockey.puck.fill",
                        title: "Every player's line",
                        detail: "ixG and GAx for every skater, GSAx for every goalie, every game."),
                Benefit(icon: "flame.fill",
                        title: "The Trends board",
                        detail: "The whole league ranked by who's moving, right now."),
                Benefit(icon: "chart.bar.fill",
                        title: "Recent form everywhere",
                        detail: "Last 2 / 4 / 8 weeks on any player, team or board.")
            ]
        case .playerScouting, .recentForm, .upgrade, .onboarding, .activation, .bestWorst:
            return [
                Benefit(icon: "flame.fill",
                        title: "The Trends board",
                        detail: "The whole league ranked by who's moving, right now."),
                Benefit(icon: "chart.bar.fill",
                        title: "Recent form everywhere",
                        detail: "Last 2 / 4 / 8 weeks on any player, team or board."),
                Benefit(icon: "person.2.fill",
                        title: "Head-to-head matchups",
                        detail: "Stack any two players across every percentile.")
            ]
        case .lockedSeason(let year):
            return [
                Benefit(icon: "calendar.badge.clock",
                        title: year == SeasonLabel.allTime ? "All-time career stats" : "The \(SeasonLabel.display(year)) season",
                        detail: "Every percentile ranking, plus every year back to 2008-09."),
                Benefit(icon: "arrow.left.arrow.right.circle.fill",
                        title: "Year-over-year trends",
                        detail: "Put \(SeasonLabel.display(year)) beside any other season and see what moved."),
                Benefit(icon: "flame.fill",
                        title: "The Trends board",
                        detail: "The whole league ranked by who's moving, right now.")
            ]
        case .pastSeason, .pastSeasonsLoad, .yearCompare:
            return [
                Benefit(icon: "calendar.badge.clock",
                        title: "Every past season",
                        detail: "Back to 2008-09, with full percentile history."),
                Benefit(icon: "arrow.left.arrow.right.circle.fill",
                        title: "Year-over-year trends",
                        detail: "Compare any two seasons side by side."),
                Benefit(icon: "flame.fill",
                        title: "The Trends board",
                        detail: "The whole league ranked by who's moving, right now.")
            ]
        case .playerComparison, .teamView, .winback:
            return [
                Benefit(icon: "person.2.fill",
                        title: "Head-to-head matchups",
                        detail: "Stack any two players across every percentile."),
                Benefit(icon: "shield.lefthalf.filled",
                        title: "Full team scouting",
                        detail: "Every club's roster, ranked by any metric."),
                Benefit(icon: "flame.fill",
                        title: "The Trends board",
                        detail: "The whole league ranked by who's moving, right now.")
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The ScrollView is a safety net for Dynamic Type and the smallest
            // devices, not the layout: at default sizes nothing here scrolls.
            ScrollView {
                VStack(spacing: 14) {
                    hero
                    benefitList
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(RinkPalette.canvas.ignoresSafeArea())
        // A fixed height rather than a fraction, because what has to fit is a
        // fixed amount of content: hero, three benefits, CTA and the auto-renew
        // disclosure. A fraction that looked right on a 6.3" phone clipped the
        // third benefit on a 4.7" one. This is about half the screen on a
        // current phone, which is the size this pitch has always been, and
        // two-thirds on the smallest, where it needs to be. Drags up to full
        // height for large accessibility text.
        .presentationDetents([.height(460), .large])
        .presentationDragIndicator(.visible)
        // Tick the session cap on the *pitch* sheet too, not just the full
        // PaywallView. Otherwise PaywallGate.shouldPresent(.playerScouting)
        // stays true forever for sheets that never reach PaywallView, and the
        // half-sheet would auto-present on every player open.
        .onAppear { PaywallGate.shared.markPresented(trigger) }
        // Impression and product-load both belong to the CTA now, which reports
        // the trigger-specific id. Reporting a second, generic
        // "statscout_trial_sheet" id from here double-counted every pitch.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    /// Glyph, headline and one line of argument, on three tight lines. The 84pt
    /// badge this replaced cost more vertical space than two whole benefits.
    private var hero: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: trigger.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(RinkPalette.turf)
                Text(trigger.title)
                    .font(RinkType.pageTitle)
                    .foregroundStyle(RinkPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Text(trigger.subtitle)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefitList: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                HStack(spacing: 12) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RinkPalette.turf)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(benefit.title)
                            .font(RinkType.bodyBold)
                            .foregroundStyle(RinkPalette.ink)
                        Text(benefit.detail)
                            .font(RinkType.small)
                            .foregroundStyle(RinkPalette.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)

                if index < benefits.count - 1 {
                    Rectangle()
                        .fill(RinkPalette.divider)
                        .frame(height: RinkGeo.hairline)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // Same control as every other pitch in the app: it buys the yearly
            // plan in place (trial when eligible, paid otherwise) and carries
            // its own auto-renew disclosure and "See all plans" escape hatch.
            // The billed amount is the primary line on every purchase surface.
            // The trial remains visible only as subordinate copy.
            PlusDirectCTA(trigger: trigger, emphasis: .billedAmountFirst)

            // Legal links and the way out share a row, because three stacked
            // secondary lines under a button is three lines of nothing.
            HStack(spacing: 14) {
                Link("Terms", destination: StatScoutLegal.termsURL)
                Link("Privacy", destination: StatScoutLegal.privacyURL)
                Button("Maybe later") { dismiss() }
            }
            .font(RinkType.micro)
            .tracking(0.3)
            .foregroundStyle(RinkPalette.inkSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            RinkPalette.surface
                .overlay(
                    Rectangle()
                        .fill(RinkPalette.divider)
                        .frame(height: RinkGeo.hairline),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

}

#if DEBUG
#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            TrialPitchSheet(trigger: .upgrade)
                .environmentObject(StoreService.shared)
        }
}
#endif
