import SwiftUI

enum GridironControl {
    /// One height for every inline control in the app, segmented groups,
    /// chips, and the popover pills. Previously 26, 28, 30, 32, 34 and 44 were
    /// all in use for controls at the same level, which is what made a row of
    /// filters read as a pile of unrelated buttons.
    static let height: CGFloat = 32
}

/// The single inline-options control for the whole app.
///
/// Same-level choices were being drawn four different ways, large filled
/// rounded-rects, tall capsules, short capsules, and underlined text tabs, so
/// two pickers that mean the same kind of thing looked unrelated. The app now
/// keeps exactly three tiers, and this is the third:
///
/// 1. **Page-level switch** (Percentiles / Roster, Percentiles / Standard Stats
///    / Year Compare): the large filled rounded-rect row. "Which screen is
///    this."
/// 2. **Metric category** (Passing / Rushing / Receiving / Defense):
///    `GridironTabs`, underlined text.
/// 3. **Inline options** (Season / Recent / Both, the Last 3 / 5 / 8 game
///    windows, Heating / Cooling): this control. One height, one shape,
///    everywhere. Past four options it hands over to a plain `Menu`, which is
///    what the season and Trends metric pickers use.
/// 4. **Standalone controls** (the sort chip, search, Filters, the pickers that
///    open a popover): `GridironChip`, same height and type as a segment.
///
/// The wording is shared too: a rolling window is always "Last 5 games",
/// never "5G" on one screen and "Last 5" on the next.
///
/// Segments can be individually locked, which draws a crown and routes the tap
/// to `onLockedTap` instead of selecting, that's how a free user can see that
/// Recent exists at all rather than the option being hidden entirely.
struct GridironSegmented<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let label: String
        var isLocked: Bool = false
        /// Optional leading glyph. Kept to SF Symbols so it tints with the
        /// palette and can't fall back to a missing-glyph box.
        var systemImage: String? = nil

        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value
    /// Called instead of selecting when a locked segment is tapped.
    var onLockedTap: ((Value) -> Void)? = nil
    /// Fill for the selected segment. Defaults to the turf green every other
    /// active control uses; Trends overrides it to encode hot vs cold.
    var selectedFill: (Value) -> Color = { _ in GridironPalette.turf }

    private let height: CGFloat = GridironControl.height

    var body: some View {
        HStack(spacing: 6) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection && !segment.isLocked
                Button {
                    if segment.isLocked {
                        onLockedTap?(segment.value)
                    } else {
                        selection = segment.value
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        if let icon = segment.systemImage {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(segment.label)
                            .font(GridironType.smallBold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if segment.isLocked {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                    }
                    .foregroundStyle(isSelected ? .white : GridironPalette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(isSelected ? selectedFill(segment.value) : GridironPalette.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(isSelected ? Color.clear : GridironPalette.hairline, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.isLocked ? "\(segment.label), requires StatScout+" : segment.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
    }
}

/// The single standalone-control shape: an outlined capsule that fills with
/// turf green while it's doing something.
///
/// Everything that isn't a segmented group is this, the sort chip, the search
/// toggle, the Filters menu, the season and metric pickers. They were each
/// hand-drawn before, and drifted: 30pt tall here and 32 there, `micro` type on
/// one and `smallBold` on the next, so a single row of filters read as three
/// unrelated buttons.
///
/// It renders a label only; the caller wraps it in whatever it needs to be
/// (`Button`, `Menu`, a popover anchor).
struct GridironChip: View {
    enum Trailing {
        case none
        /// A chooser, opens a menu or a popover.
        case chevron
        /// A sort control, tapping flips the arrow.
        case sortArrow(descending: Bool)
    }

    var title: String? = nil
    var systemImage: String? = nil
    var trailing: Trailing = .none
    /// Filled state: the control is currently changing what's on screen.
    var isActive: Bool = false
    /// Draws the StatScout+ crown. The caller still owns what a tap does.
    var isLocked: Bool = false
    /// Let the label shrink rather than force the row wider than its container.
    ///
    /// `fixedSize()` is right for a chip in a scrolling filter row, where being
    /// squeezed down to a bare icon is the failure mode. It is wrong inside a
    /// half-width column. Compare puts a season pill and a "Regular Season" pill
    /// side by side in each of two columns, and four unshrinkable pills demand
    /// more width than a phone has - so, because `fixedSize` propagates upward,
    /// the *whole page* grew past the viewport and every row on it clipped at
    /// both edges instead of the pills simply getting smaller.
    var compressible: Bool = false

    private var glyphColor: Color {
        isActive ? .white : GridironPalette.inkSecondary
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
            if let title {
                Text(title)
                    .font(GridironType.smallBold)
                    .foregroundStyle(isActive ? .white : GridironPalette.ink)
                    .lineLimit(1)
                    // Shrink before truncating: "Regular Sea…" reads as broken,
                    // a slightly smaller "Regular Season" does not.
                    .minimumScaleFactor(compressible ? 0.75 : 1)
            }
            if isLocked {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.yellow)
            }
            switch trailing {
            case .none:
                EmptyView()
            case .chevron:
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(glyphColor)
            case .sortArrow(let descending):
                Image(systemName: descending ? "arrow.down" : "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? .white : GridironPalette.turf)
            }
        }
        .fixedSize(horizontal: !compressible, vertical: true)
        .padding(.horizontal, title == nil ? 0 : 12)
        // An icon-only chip stays a circle rather than collapsing to a sliver.
        .frame(width: title == nil ? GridironControl.height : nil,
               height: GridironControl.height)
        .background(isActive ? GridironPalette.turf : GridironPalette.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(isActive ? Color.clear : GridironPalette.hairline, lineWidth: 0.5)
        )
    }
}

/// Which of a row's width a control is entitled to. Set by `segmentCount`.
private struct SegmentCountKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

extension View {
    /// Tells `GridironPickerRow` how many segments this control holds.
    func segmentCount(_ count: Int) -> some View {
        layoutValue(key: SegmentCountKey.self, value: count)
    }
}

/// Two picker groups on one row, each given width in proportion to how many
/// segments it holds, so every capsule in the row comes out the same width.
///
/// A plain `HStack` splits the row evenly between the *groups*, which is what
/// made "Season / Recent / Both" sit cramped beside "Hitting / Pitching":
/// three labels squeezed into the width two were given, and worse once the
/// free-tier crowns appeared on two of them.
struct GridironPickerRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = subviews
            .map { $0.sizeThatFits(.unspecified).height }
            .max() ?? GridironControl.height
        return CGSize(width: width, height: max(height, GridironControl.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let counts = subviews.map { max(1, $0[SegmentCountKey.self]) }
        let total = CGFloat(counts.reduce(0, +))
        let available = bounds.width - spacing * CGFloat(subviews.count - 1)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = available * CGFloat(counts[index]) / total
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}
