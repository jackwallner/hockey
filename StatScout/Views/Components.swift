import SwiftUI

// MARK: - Atomic Components

struct PlayerHeadshot: View {
    let team: String
    let initials: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(TeamColor.color(team))
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .default))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Shimmer Effect Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.5), .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 2)
                    .offset(x: -proxy.size.width + phase * proxy.size.width * 2)
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
                }
            )
            .mask(content)
            .onAppear { phase = 1 }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct OverallPercentileBadge: View {
    let percentile: Int
    var size: CGFloat = 64

    private var tierDescription: String {
        switch percentile {
        case 90...100: return "Elite"
        case 75..<90: return "Excellent"
        case 50..<75: return "Above Average"
        case 25..<50: return "Below Average"
        default: return "Poor"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(percentile)")
                .font(RinkType.statHero)
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
            Text(percentile.ordinal)
                .font(RinkType.micro)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 0.5)
        }
        .frame(width: size, height: size)
        .background(RinkPalette.color(forPercentile: percentile))
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusBadge))
        .accessibilityLabel("Overall \(percentile.ordinalString) percentile, \(tierDescription)")
    }
}

struct TeamColorDot: View {
    let abbr: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(TeamColor.color(abbr)).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

func displayTeamAbbr(_ abbr: String) -> String {
    let trimmed = abbr.trimmingCharacters(in: .whitespaces).uppercased()
    if trimmed.isEmpty || trimmed == "TBD" || trimmed == "\u{2014}" || trimmed == "-" {
        return "FA"
    }
    return abbr
}

// MARK: - Module 2: Percentile Bar Row (MetricBar) - hockey analytics Style

struct MetricBar: View {
    let metric: Metric
    var showValue: Bool = true

    private var accessibilityLabel: String {
        if metric.isUnranked {
            return "\(metric.label): \(metric.value), not ranked"
        }
        let valueText = metric.value.isEmpty ? "\(metric.percentile.ordinalString) percentile" : "\(metric.value), \(metric.percentile.ordinalString) percentile"
        let sample = metric.isSmallSample ? ", small sample" : ""
        return "\(metric.label): \(valueText)\(sample)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Label column - left aligned
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.label)
                    .font(RinkType.bodyBold)
                    .foregroundStyle(RinkPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if metric.isSmallSample, !metric.isUnranked {
                    Text("Small sample")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: 78, alignment: .leading)

            if metric.isUnranked {
                // A zero count has no honest rank (see `Metric.isUnranked`):
                // an empty track, no bubble, no colour.
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(RinkPalette.surfaceSunk)
                        .frame(height: 10)
                    Text("Not ranked")
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(RinkPalette.surfaceSunk))
                        .padding(.leading, 8)
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity)
            } else {
                percentileTrack
                    .opacity(metric.isSmallSample ? 0.45 : 1)
            }

            // Value column - far right, fixed width (sized for "30.0 ft/s" / "0.421" range)
            if showValue && !metric.value.isEmpty {
                Text(metric.value)
                    .font(RinkType.statMed)
                    .foregroundStyle(metric.isSmallSample || metric.isUnranked ? RinkPalette.inkSecondary : RinkPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 72, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: 72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var percentileTrack: some View {
            let percentileValue = max(0, min(100, metric.percentile))
            return GeometryReader { proxy in
                let circleSize: CGFloat = 28
                let trackWidth = proxy.size.width - circleSize
                let offset = (circleSize / 2) + (trackWidth * CGFloat(percentileValue) / 100.0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(RinkPalette.surfaceSunk)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(RinkPalette.color(forPercentile: percentileValue))
                        .frame(width: offset, height: 10)

                    ZStack {
                        Circle()
                            .fill(RinkPalette.color(forPercentile: percentileValue))
                            .frame(width: circleSize, height: circleSize)

                        Text("\(percentileValue)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0.5)
                    }
                    .position(x: offset, y: 14)
                }
            }
            .frame(height: 28)
    }
}

/// Season + recent percentile bars stacked in one row - same Rink layout,
/// with a compact recent track under the season bar when both are available.
struct DualMetricBar: View {
    let season: Metric
    var recent: Metric?
    var recentCaption: String = "Recent"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Season")
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .frame(width: 52, alignment: .leading)
                MetricBar(metric: season, showValue: true)
            }

            HStack(spacing: 6) {
                Text(recentCaption)
                    .font(RinkType.micro)
                    .foregroundStyle(recent == nil ? RinkPalette.inkTertiary : RinkPalette.turf)
                    .frame(width: 52, alignment: .leading)
                if let recent {
                    MetricBar(metric: recent, showValue: true)
                } else {
                    // The row used to just vanish, which made "Both" look
                    // identical to "Season" and read as a broken toggle rather
                    // than as a metric with no window figure. Say which it is.
                    // Nothing here is derivable for the on-ice shares (xGF%,
                    // CF%, Rel xGF%): the per-game feed carries no shift-level
                    // denominator for them, and averaging their per-game
                    // averages would be a different number wearing this
                    // one's label.
                    Text("Not available per game")
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Search (restyled for light mode)

struct SearchField: View {
    @Binding var text: String
    var focusOnAppear: Bool = false
    /// What this field searches. Defaults to the leaderboard's answer because
    /// that is where most of them live; the glossary searches stats.
    var prompt: String = "Search players or teams"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RinkPalette.inkSecondary)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(RinkType.body)
                        .foregroundStyle(RinkPalette.inkSecondary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(RinkPalette.ink)
                    .focused($isFocused)
            }
        }
        .onAppear {
            if focusOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Category Tabs (Module 5 variant for dashboard)

struct CategoryFilter: View {
    @Binding var selectedCategory: MetricCategory?
    var showAllOption: Bool = false

    var body: some View {
        let categoryTabs = MetricCategory.allCases.map { $0.rawValue }
        let tabs = showAllOption ? ["All"] + categoryTabs : categoryTabs
        let selectedTab = selectedCategory?.rawValue ?? (showAllOption ? "All" : MetricCategory.scoring.rawValue)

        RinkTabs(
            tabs: tabs,
            selected: Binding(
                get: { selectedTab },
                set: { newValue in
                    if showAllOption && newValue == "All" {
                        selectedCategory = nil
                    } else {
                        selectedCategory = MetricCategory.allCases.first { $0.rawValue == newValue }
                    }
                }
            )
        )
    }
}

// MARK: - Qualifier Picker

struct QualifierPicker: View {
    @Binding var selection: DashboardViewModel.QualifierLevel

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                    Button {
                        selection = level
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(level.rawValue)
                            .font(RinkType.micro)
                            .foregroundStyle(selection == level ? .white : RinkPalette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(selection == level ? RinkPalette.turf : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RinkPalette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(RinkPalette.hairline, lineWidth: 0.5))

            // Threshold caption - keeps "All" and "Min Sample" from reading as
            // synonyms by spelling out what the active level actually filters.
            Text(selection.description)
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
        }
    }
}

/// Compact menu variant of `QualifierPicker`. The segmented picker takes a
/// whole row (plus a caption); this collapses into a chip that fits beside the
/// category tabs. Use when vertical space matters more than at-a-glance state.
struct QualifierMenu: View {
    @Binding var selection: DashboardViewModel.QualifierLevel

    var body: some View {
        Menu {
            ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                Button {
                    selection = level
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if level == selection {
                        Label("\(level.rawValue) · \(level.description)", systemImage: "checkmark")
                    } else {
                        Text("\(level.rawValue) · \(level.description)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(selection.rawValue)
                    .font(RinkType.micro)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(RinkPalette.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RinkPalette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(RinkPalette.hairline, lineWidth: 0.5))
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Qualifier")
        .accessibilityValue("\(selection.rawValue), \(selection.description)")
    }
}

// MARK: - Section Header (legacy, minimal use)

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(RinkType.sectionTitle)
                .foregroundStyle(RinkPalette.ink)
            Text(subtitle)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
        }
    }
}

// MARK: - Trend Glyph

struct TrendGlyph: View {
    let direction: MetricDirection

    var body: some View {
        Image(systemName: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(color)
    }

    private var icon: String {
        switch direction {
        case .up: "arrow.up.right"
        case .flat: "minus"
        case .down: "arrow.down.right"
        }
    }

    private var color: Color {
        switch direction {
        case .up: RinkPalette.up
        case .flat: RinkPalette.inkTertiary
        case .down: RinkPalette.down
        }
    }
}

// MARK: - Trend Arrow

/// Recent-vs-prior change for one metric, drawn as an arrow and a magnitude.
///
/// Lives on the Trends tab and the team form cards, and nowhere else. It used
/// to ride along as an extra column on the Stats leaderboard, where it only
/// rendered for the players the rolling window happened to cover: rows with a
/// trend lost their percentile bar and rows without it kept one, so the board's
/// most-read column changed shape halfway down the list. Trends are a screen,
/// not a garnish on the season leaderboard.
struct TrendArrow: View {
    let delta: Double
    /// Counting stats move in whole numbers, percentages and expected goals in
    /// tenths, per-60 rates in hundredths.
    var decimals: Int = 1
    /// For metrics where down is the good direction, GAA, goals against. The
    /// arrow still points the way the number actually moved; only the colour
    /// flips, so green always means "better".
    var lowerIsBetter: Bool = false

    /// Below half of the last displayed digit a delta is noise, and an arrow
    /// would imply a signal: 0.5 for whole numbers, 0.05 for a percent reported
    /// to a tenth, 0.005 for a save percentage.
    private var isFlat: Bool { abs(delta) < 5 * pow(10, -Double(decimals + 1)) }

    private var tint: Color {
        if isFlat { return RinkPalette.inkTertiary }
        let improved = lowerIsBetter ? delta < 0 : delta > 0
        return improved ? RinkPalette.performanceHigh : RinkPalette.performanceLow
    }

    private var text: String {
        if isFlat { return "0" }
        return String(format: "%.\(decimals)f", abs(delta))
    }

    var body: some View {
        HStack(spacing: 2) {
            if !isFlat {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(RinkType.micro)
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .accessibilityLabel(
            isFlat ? "No recent change" : "\(delta > 0 ? "Up" : "Down") \(text) recently"
        )
    }
}

// MARK: - Percentile Bar Mini (for leaderboards)

struct PercentileBarMini: View {
    let percentile: Int
    var height: CGFloat = 7
    /// Overrides the percentile ramp, for a rank where high is not "good" (pay).
    var tint: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height/2)
                    .fill(RinkPalette.surfaceSunk)
                    .frame(height: height)

                RoundedRectangle(cornerRadius: height/2)
                    .fill(tint ?? RinkPalette.color(forPercentile: percentile))
                    .frame(width: proxy.size.width * CGFloat(percentile) / 100.0, height: height)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Leaderboard Table

struct LeaderboardTableHeader: View {
    let sortDescending: Bool
    var sortLabel: String = "OVERALL"
    var metrics: [String] = []
    var onSelectMetric: (String) -> Void = { _ in }
    var onToggleDirection: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Text("RANK")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .frame(width: 42, alignment: .leading)

            Text("PLAYER")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("TEAM")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .frame(width: 44, alignment: .leading)

            HStack(spacing: 2) {
                Menu {
                    ForEach(metrics, id: \.self) { metric in
                        Button {
                            onSelectMetric(metric)
                        } label: {
                            if metric == sortLabel {
                                Label(metric, systemImage: "checkmark")
                            } else {
                                Text(metric)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(sortLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.turf)
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Metric")
                .accessibilityValue(sortLabel)

                Button(action: onToggleDirection) {
                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(RinkPalette.turf)
                        .frame(width: 18, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sortDescending ? "Highest first" : "Lowest first")
                .accessibilityHint("Double tap to reverse ranking order")
            }
            .frame(width: 104, alignment: .trailing)
        }
        .frame(height: RinkGeo.rowHeightHeader)
        .padding(.horizontal, RinkGeo.padInline)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
    }
}

struct InlineLoadError: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await retry() }
            }
            .font(RinkType.smallBold)
            .foregroundStyle(RinkPalette.turf)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, RinkGeo.padInline)
        .padding(.vertical, 24)
    }
}

struct LeaderboardTableRow: View {
    let rank: Int
    let player: Player
    var metricLabel: String? = nil
    var metricCategory: MetricCategory? = nil
    var trendDelta: Double? = nil
    var trendDecimals: Int = 3
    /// The rolling-window value, shown in place of the season number when the
    /// list is ranking by recent form. Uncoloured: the season percentile is the
    /// wrong ruler for five games' worth of numbers, and there is no window
    /// curve to colour it against.
    var valueOverride: String? = nil
    /// The volume behind the ranked number, "412 min" or "612 SA", printed
    /// after the position. A rate with no denominator beside it gave a
    /// fourth liner the same authority as a top-pair defenseman.
    var volume: String? = nil
    /// Under the playing-time bar for the ranked metric: value and bar dimmed.
    var isSmallSample: Bool = false

    private var displayMetric: Metric? {
        guard let label = metricLabel else { return nil }
        // When no category is active (the all-categories leaderboard) fall back
        // to matching on label alone so we still surface the player's headline
        // entry regardless of which category it lives under.
        if let category = metricCategory {
            return player.metrics.first { $0.label == label && $0.category == category }
        }
        return player.metrics.first { $0.label == label }
    }

    private var displayPercentile: Int {
        displayMetric?.percentile ?? 0
    }

    // Raw stat value only - never the percentile. The colored bar to the left
    // already conveys percentile visually; numeric percentile in this column
    // duplicates that signal and reads as "the stat value" at a glance.
    private var displayValueText: String {
        if let valueOverride { return valueOverride }
        guard let metric = displayMetric else { return "-" }
        if !metric.value.isEmpty { return metric.value }
        return metric.percentile.ordinal
    }

    private var displayValueColor: Color {
        if isSmallSample || displayMetric?.isUnranked == true { return RinkPalette.inkTertiary }
        return valueOverride == nil
            ? RinkPalette.textColor(forPercentile: displayPercentile)
            : RinkPalette.ink
    }

    private var subtitle: String {
        [player.displayPosition, volume, isSmallSample ? "small sample" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(RinkType.statSmall)
                .foregroundStyle(RinkPalette.inkSecondary)
                .frame(width: 42, alignment: .leading)
                .monospacedDigit()

            HStack(spacing: 10) {
                PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(RinkType.bodyBold)
                        .foregroundStyle(RinkPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                TeamColorDot(abbr: player.team, size: 6)
                Text(displayTeamAbbr(player.team))
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
            .frame(width: 44, alignment: .leading)

            HStack(spacing: 8) {
                // A player without the sorted metric gets no bar - drawing one
                // from their overall percentile would mislabel a different number
                // as this column's stat. Show a muted "-" instead.
                if displayMetric != nil || valueOverride != nil {
                    // A window value drops the bar: the season percentile bar
                    // beside five games' worth of numbers reads as that
                    // number's rank, which it is not.
                    if valueOverride == nil {
                        if displayMetric?.isUnranked == true {
                            Color.clear.frame(width: 40, height: 7)
                        } else {
                            PercentileBarMini(percentile: displayPercentile)
                                .frame(width: 40)
                                .opacity(isSmallSample ? 0.35 : 1)
                        }
                    }
                    Text(displayValueText)
                        .font(RinkType.statSmall)
                        .foregroundStyle(displayValueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 48, alignment: .trailing)
                        .monospacedDigit()
                } else {
                    Text("-")
                        .font(RinkType.statSmall)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .frame(width: trendDelta == nil ? 92 : 56, alignment: .trailing)

            if let trendDelta {
                TrendArrow(delta: trendDelta, decimals: trendDecimals)
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .frame(height: RinkGeo.rowHeight)
        .padding(.horizontal, RinkGeo.padInline)
        // Banded rows, the same white / near-white alternation the Trends board
        // and the standard-stats board already use. Fifty rows of one flat
        // surface is where the eye loses its place tracking a name across to a
        // number; the band is what carries it. Keyed on `rank` (1-based) so the
        // first row is the plain surface and the card's top edge stays clean.
        .background(rank % 2 == 1 ? RinkPalette.surface : RinkPalette.surfaceAlt)
        .contentShape(Rectangle())
    }
}

// MARK: - Blur Gate Unlock

/// Compact unlock affordance for Pro-gated, blurred teasers. Anchors to the
/// bottom over a gradient that fades the blurred preview into the card surface,
/// so the teaser stays visible as the hook instead of being buried under an
/// opaque panel. Used by RecentFormCard, TeamRankingsCard, and YearComparePreview.
///
/// The CTA transacts. It used to open `TrialPitchSheet`, which showed the same
/// offer a second time under a second button, so a user who had already said
/// yes to "Start 7-day free trial" had to say it again before Apple's confirm
/// sheet ever appeared. The button says what it does and then does it; the plan
/// picker stays reachable behind a quiet "See all plans" link for anyone who
/// actually wants to weigh monthly against lifetime.
struct BlurGateUnlock: View {
    let headline: String
    /// Entry point this gate represents, drives the impression id and the
    /// copy on the plan picker, if the user asks for it.
    let trigger: PaywallTrigger

    var body: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(RinkType.smallBold)
                .foregroundStyle(RinkPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PlusDirectCTA(trigger: trigger, style: .capsule)
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, RinkPalette.surface.opacity(0.95), RinkPalette.surface],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Stat Glossary Link

/// Quiet "what do these mean?" footer, for the bottom of any screen that puts
/// abbreviated stats in front of the reader.
///
/// The glossary already held a definition for every metric in the app and there
/// was exactly one way in: Settings, behind the gear, two taps from anywhere.
/// So the one moment a reader wants it - looking at a GSAx bar and wondering
/// what GSAx is - was the moment it was furthest away, and nothing on the screen
/// suggested it existed at all.
///
/// A footer rather than a badge on every row: the question is "what is all this",
/// asked once, not "what is this one" asked forty times, and forty ⓘ glyphs down
/// a percentile card would compete with the bars they annotate. Scrolling to the
/// end of the page is already what someone does when they have run out of things
/// to read.
///
/// Sits inside whatever `NavigationStack` hosts it, so the back button returns to
/// the page you were reading rather than dumping you in Settings.
struct StatGlossaryLink: View {
    var body: some View {
        NavigationLink {
            StatGlossaryView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RinkPalette.turf)
                Text("What do these stats mean?")
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.turf)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RinkPalette.inkTertiary)
            }
            .padding(RinkGeo.padCard)
            .frame(maxWidth: .infinity)
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(RinkPalette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stat glossary")
        .accessibilityHint("Definitions for every stat in StatScout")
    }
}

// MARK: - One-tap StatScout+ CTA

/// The app's only in-place conversion control, and the reason there is no
/// pitch-then-pitch path left.
///
/// Every surface that names an offer, the blurred gates, the player-page
/// upsell card, the trial sheet's footer, used to hand off to another screen
/// that showed the same offer under another button. This one transacts: tap it
/// and the next thing on screen is Apple's confirm sheet. The plan picker is
/// still there for anyone who wants to weigh monthly against lifetime, but it's
/// a quiet text link rather than a toll gate, and it's also where a failed
/// product load lands because that's the only screen that can retry.
struct PlusDirectCTA: View {
    enum Style {
        /// Compact pill, for the bottom of a blurred teaser.
        case capsule
        /// Full-width bar, for a card or sheet footer.
        case bar
    }

    @EnvironmentObject private var store: StoreService

    let trigger: PaywallTrigger
    var style: Style = .bar
    /// Hidden where the surrounding screen already offers plan choice.
    var showsAllPlansLink: Bool = true
    /// The billed amount leads on every purchase surface. A trial may still be
    /// shown, but only as the subordinate second line.
    var emphasis: PriceEmphasis = .billedAmountFirst

    @State private var isPurchasing = false
    @State private var statusMessage: String?
    @State private var showingPlans = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: buy) {
                label
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityLabel(
                [
                    store.directCTALabel(for: trigger, emphasis: emphasis),
                    store.directCTATrialSubline(for: trigger, emphasis: emphasis),
                ]
                .compactMap { $0 }
                .joined(separator: ". ")
            )

            // Full auto-renew terms sit beside the purchase point, because this
            // button *is* the purchase point now (Apple 3.1.2).
            if let disclosure = store.yearlyCTADisclosureText(emphasis: emphasis) ?? store.paywallBlurSubtext {
                Text(disclosure)
                    .font(RinkType.micro)
                    .tracking(0.3)
                    .foregroundStyle(RinkPalette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(RinkType.micro)
                    .foregroundStyle(RinkPalette.turf)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsAllPlansLink {
                Button("See all plans") { showingPlans = true }
                    .font(RinkType.micro)
                    .tracking(0.3)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            store.trackPaywallImpression(id: trigger.paywallImpressionId, oncePerSession: true)
            if store.currentOffering == nil { await store.fetchProducts() }
        }
        .sheet(isPresented: $showingPlans) {
            PaywallView(trigger: trigger)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .capsule:
            HStack(spacing: 6) {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11))
                    Text(store.directCTALabel(for: trigger, emphasis: emphasis))
                        .font(RinkType.bodyBold)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(RinkPalette.turf)
            .clipShape(Capsule())
        case .bar:
            // Two lines only where the emphasis asks for it: the billed amount
            // in the button's own type, the trial under it in micro at 85%
            // white. Same button, same height budget; the trial is still sold,
            // just not louder than the price (Apple 3.1.2(c)).
            let subline = store.directCTATrialSubline(for: trigger, emphasis: emphasis)
            ZStack {
                VStack(spacing: 1) {
                    Text(store.directCTALabel(for: trigger, emphasis: emphasis))
                        .font(RinkType.bodyBold)
                    if let subline {
                        Text(subline)
                            .font(RinkType.micro)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .opacity(isPurchasing ? 0 : 1)
                if isPurchasing {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.vertical, subline == nil ? 0 : 6)
            .background(RinkPalette.turf)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func buy() {
        statusMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            switch await store.purchaseYearlyDirect() {
            case .unlocked:
                break
            case .pending:
                // Ask-to-Buy / deferred payment: not unlocked, not an error.
                statusMessage = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
            case .cancelled:
                statusMessage = "Purchase cancelled. Tap again to continue."
            case .failed(let message):
                statusMessage = message
            case .needsPlanPicker:
                // Nothing loaded to buy, the picker's retry/empty state is the
                // only surface that can say so and recover.
                showingPlans = true
            }
        }
    }
}

// MARK: - Int Ordinal Extension

extension Int {
    var ordinal: String {
        let suffix: String
        switch self % 100 {
        case 11...13: suffix = "th"
        default:
            switch self % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(self)\(suffix)"
    }
}

// MARK: - Extensions for Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Int {
    /// "1st", "22nd", "93rd", "11th": VoiceOver reads percentile ranks aloud.
    var ordinalString: String {
        let tens = self % 100
        if (11...13).contains(tens) { return "\(self)th" }
        switch self % 10 {
        case 1: return "\(self)st"
        case 2: return "\(self)nd"
        case 3: return "\(self)rd"
        default: return "\(self)th"
        }
    }
}
