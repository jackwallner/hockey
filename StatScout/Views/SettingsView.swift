import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    var dataCoverage: DataCoverage?
    var freshness: DataFreshness?
    var onRequestReview: (() -> Void)?
    @State private var paywallTrigger: PaywallTrigger?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                proStatusCard
                glossaryCard
                linkCard
                refreshCard
                aboutCard
                versionCard
                disclaimerCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            Color.clear.frame(height: 88)
        }
        .background(RinkPalette.canvas.ignoresSafeArea())
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
    }

    private var glossaryCard: some View {
        NavigationLink {
            StatGlossaryView()
        } label: {
            VStack(spacing: 0) {
                RinkSectionBar(title: "REFERENCE")
                row(
                    icon: "text.book.closed.fill",
                    title: "Stat Glossary",
                    subtitle: "Definitions and formulas for every stat in StatScout."
                )
            }
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(RinkPalette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "STATSCOUT")
            HStack(spacing: 12) {
                Image(systemName: "hockey.puck.fill")
                    .font(.title2)
                    .foregroundStyle(RinkPalette.turf)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hockey StatScout")
                        .font(RinkType.cardTitle)
                        .foregroundStyle(RinkPalette.ink)
                    Text("Every NHL skater and goalie ranked by expected goals, against their own position.")
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.inkSecondary)
                }
                Spacer()
            }
            .padding(RinkGeo.padCard)
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private var proStatusCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "STATSCOUT+")
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: store.isPro ? "crown.fill" : "crown")
                        .font(.title2)
                        .foregroundStyle(store.isPro ? Color.yellow : RinkPalette.inkTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isPro ? "StatScout+ Unlocked" : "Free Version")
                            .font(RinkType.bodyBold)
                            .foregroundStyle(RinkPalette.ink)
                        // Named to match `PaywallView.proFeatures`. This used to
                        // promise "historical seasons and year-over-year
                        // comparisons" and stop there, undercounting the
                        // subscription by three features (Trends, recent form,
                        // head-to-head) on the one screen a user reaches by
                        // going looking for the offer.
                        Text(store.isPro
                             ? "All StatScout+ features are active."
                             : "Unlock Trends, recent form, head-to-head and every season back to 2008-09.")
                            .font(RinkType.small)
                            .foregroundStyle(RinkPalette.inkSecondary)
                    }
                    Spacer()
                    if !store.isPro {
                        Button(store.isLapsed ? "Renew" : store.upgradeCTALabel) {
                            paywallTrigger = store.defaultUpgradeTrigger
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RinkPalette.turf)
                        .controlSize(.small)
                    }
                }
                .padding(RinkGeo.padCard)

                Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Restore Purchases")
                            .font(RinkType.smallBold)
                    }
                    .foregroundStyle(RinkPalette.linkBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RinkGeo.padCard)
                }
                .buttonStyle(.plain)

                if let error = store.lastError {
                    Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)
                    Text(error)
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.turf)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RinkGeo.padCard)
                }
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    /// Which games are in, phrased the way the boards phrase it.
    ///
    /// The row "Last Refreshed" needs standing next to it. The nightly job can
    /// rewrite every row on a night with no new final, so the write stamp says
    /// today while the newest game is yesterday's. Reporting only the write
    /// stamp made the app contradict the Trends header, which correctly says
    /// "Through Oct 7". The date of the last game is the unit the whole app
    /// counts in.
    private var gamesThroughText: String {
        guard let coverage = freshness?.coverage ?? dataCoverage else { return "-" }
        let stamp = coverage.asOf.formatted(DataCoverage.gameDayStyle)
        return coverage.phase == .playoffs ? "\(stamp) (playoffs)" : stamp
    }

    private var checkedText: String {
        (freshness?.checkedAt ?? lastUpdated)?.formatted(date: .long, time: .shortened) ?? "-"
    }

    private var sourcePublishedText: String? {
        freshness?.sourcePublishedAt?.formatted(date: .long, time: .shortened)
    }

    private var refreshCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "DATA")
            row(
                icon: "arrow.triangle.2.circlepath",
                title: "Data Updates",
                subtitle: "Checks for new NHL numbers after every night's games."
            )
            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)
            row(
                icon: "calendar.badge.clock",
                title: "Games Through",
                subtitle: gamesThroughText
            )
            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)
            row(
                icon: "clock.arrow.circlepath",
                title: "Last Checked",
                subtitle: checkedText
            )
            if let sourcePublishedText {
                Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)
                row(
                    icon: "cloud.sun.fill",
                    title: "Source Published",
                    subtitle: sourcePublishedText
                )
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private var linkCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "SUPPORT & PRIVACY")
            Button {
                if let onRequestReview {
                    onRequestReview()
                } else {
                    ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                }
            } label: {
                row(
                    icon: "star.fill",
                    title: "Rate or Send Feedback",
                    subtitle: "Help StatScout grow, or tell us what to improve."
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)

            // Always-works fallback: the native rating sheet is rate-limited and
            // may show nothing, so keep a direct write-review link for users who
            // explicitly want to leave a review.
            Link(destination: AppStoreReviewLinks.writeReviewURL) {
                row(
                    icon: "square.and.pencil",
                    title: "Rate on the App Store",
                    subtitle: "Opens the App Store to write a review."
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)

            if let supportURL = URL(string: "https://jackwallner.github.io/hockey/support.html") {
                Link(destination: supportURL) {
                    row(
                        icon: "envelope.fill",
                        title: "Contact Support",
                        subtitle: "jackwallner+bb@gmail.com"
                    )
                }
                .buttonStyle(.plain)
            }
            
            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline)
            
            if let privacyURL = URL(string: "https://jackwallner.github.io/hockey/privacy-policy.html") {
                Link(destination: privacyURL) {
                    row(
                        icon: "shield.lefthalf.filled",
                        title: "Privacy Policy",
                        subtitle: "No ads or tracking."
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private var versionCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "VERSION")
            HStack {
                Text("App Version")
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
                Spacer()
                Text(version)
                    .font(RinkType.statSmall)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
            .padding(RinkGeo.padCard)
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private var disclaimerCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "DISCLAIMER")
            Text("Not affiliated with, endorsed by, or sponsored by the National Hockey League, its teams, the NHLPA or MoneyPuck. Expected goals and shot data from MoneyPuck.com. Team names and abbreviations are used for identification only.")
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RinkGeo.padCard)
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(RinkPalette.turf)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
                Text(subtitle)
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
            Spacer()
        }
        .padding(RinkGeo.padCard)
    }
}

private struct GlossaryEntry: Identifiable {
    let id: String
    let label: String
    let category: String
    let description: String
}

struct StatGlossaryView: View {
    @State private var searchText = ""

    private let supplemental: [GlossaryEntry] = [
        .init(id: "general-gp", label: "GP", category: "General", description: "Games played."),
        .init(id: "general-toi", label: "TOI/GP", category: "General", description: "Average ice time per game played, in minutes and seconds."),
        .init(id: "general-plus-minus", label: "+/-", category: "General", description: "Goals for minus goals against while the player was on the ice, at even strength or shorthanded. Power-play goals do not count."),
        .init(id: "general-ppp", label: "PPP", category: "General", description: "Power-play points: goals and assists scored with the team a man up. PPG is the goals alone."),
        .init(id: "general-power", label: "Power Rating", category: "General", description: "Goals per game better or worse than an average team on neutral ice, from expected goals and actual goals for, minus against, adjusted for schedule. Early in the season last year's rating counts as extra games of evidence. Two ratings read like a puck line, with about 0.2 goals for home ice."),
        .init(id: "general-small-sample", label: "Small sample", category: "General", description: "Below the playing-time minimum for that stat, prorated by how much of the season the typical team has played. Skaters need 200 minutes over a full season, goalies 600."),
        .init(id: "general-not-ranked", label: "Not ranked", category: "General", description: "A counting stat at zero. When most of the league has none of something, a tie at zero has no honest percentile, so the value shows and the bar does not."),
        .init(id: "percentile", label: "Percentile", category: "General", description: "A 1–100 rank among players in the same season, season type, and stat category. Higher is always better after lower-is-better stats are inverted."),
    ]

    private var entries: [GlossaryEntry] {
        let registry = HockeyMetricRegistry.definitions.map {
            GlossaryEntry(
                id: "\($0.category.rawValue)-\($0.label)",
                label: $0.label,
                category: $0.category.rawValue,
                description: $0.description
            )
        }
        let all = (supplemental + registry).sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
                || $0.category.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var categories: [String] {
        let order = ["General"] + MetricCategory.allCases.map(\.rawValue)
        return order.filter { category in entries.contains { $0.category == category } }
    }

    /// A `ScrollView` of cards, not a `List` with `.searchable`.
    ///
    /// Two things were wrong with the system version. The app draws its own
    /// floating tab bar over every screen, including pushed ones - and on iOS 26
    /// `.searchable` puts the search field at the *bottom* of the screen, so the
    /// field materialised underneath the tab bar with its lower half clipped off.
    /// Nothing about the search was reachable. And the grouped `List` was the one
    /// screen in the app rendering system chrome instead of the card idiom
    /// everything else uses, so it read as a different app.
    ///
    /// The in-content `SearchField` is the same control the Teams tab and the
    /// team roster already use, it sits where the reader's eye starts, and it
    /// cannot collide with the tab bar.
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SearchField(text: $searchText, prompt: "Search stats")

                Text("Expected goals and shot data come from MoneyPuck. Schedules, box scores and bios come from the NHL. Percentiles are calculated separately for each season and season type. The current season ranks everyone who has played; past seasons rank qualifying players.")
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No stats found", systemImage: "magnifyingglass")
                    } description: {
                        Text("Nothing matches \"\(searchText)\". Try a stat's abbreviation, like ixG or GSAx.")
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(categories, id: \.self) { category in
                        categoryCard(category)
                    }
                }

                sourcesCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            // Scroll-under spacer for the floating tab bar, same as every other
            // scrolling screen.
            Color.clear.frame(height: 88)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RinkPalette.canvas.ignoresSafeArea())
        .navigationTitle("Stat Glossary")
        .navigationBarTitleDisplayMode(.inline)
        // Same midnight bar as the screen it was opened from; the default bar
        // left the status bar's white clock on a pale background.
        .modifier(RinkNavBarPublic())
    }

    private func categoryCard(_ category: String) -> some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: category.uppercased())

            let rows = entries.filter { $0.category == category }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.label)
                        .font(RinkType.bodyBold)
                        .foregroundStyle(RinkPalette.ink)
                    Text(entry.description)
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RinkGeo.padCard)
                .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private var sourcesCard: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "SOURCES")
            sourceRow(
                "MoneyPuck: expected goals and shot data",
                url: URL(string: "https://moneypuck.com/about.htm")!
            )
            sourceRow(
                "NHL: schedules, box scores and stats",
                url: URL(string: "https://www.nhl.com/stats/")!,
                isLast: true
            )
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
    }

    private func sourceRow(_ title: String, url: URL, isLast: Bool = false) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Text(title)
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.turf)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RinkPalette.inkTertiary)
            }
            .padding(RinkGeo.padCard)
            .background(RinkPalette.surface)
            .overlay(
                Rectangle()
                    .fill(isLast ? Color.clear : RinkPalette.divider)
                    .frame(height: RinkGeo.hairline),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AboutView(
            lastUpdated: Date(),
            dataCoverage: DataCoverage(asOf: .now, week: 3, phase: .regular)
        )
            .environmentObject(StoreService.shared)
    }
}
