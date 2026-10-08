import SwiftUI

/// Every "pick one of many" control in the app is a plain SwiftUI `Menu`.
///
/// This used to be a hand-built popover (`VerticalOptionPopover`) so a column
/// of four-character years wouldn't sit in UIKit's wide menu minimum. That
/// bought a narrower list and cost everything else: the panel clipped its last
/// row, it opened without the system's menu animation, and half the app's
/// choosers (sort, mode, roster filters) were `Menu`s anyway, so the two shapes
/// sat a tap apart and looked like different apps. Width was the wrong thing to
/// optimise for. Native scrolls properly, sizes itself, dismisses correctly and
/// is the control users already know.
///
/// `GridironSegmented` still covers two-to-four inline options; past that, this.
/// The generic is named `Trigger`, not `Label`, so the rows below can still say
/// `Label(_:systemImage:)` and mean SwiftUI's.
struct SeasonMenu<Trigger: View>: View {
    let seasons: [Int]
    let selected: Int
    let isLocked: (Int) -> Bool
    let onSelect: (Int) -> Void
    @ViewBuilder let label: () -> Trigger

    var body: some View {
        Menu {
            ForEach(seasons, id: \.self) { season in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(season)
                } label: {
                    // A locked year keeps its crown and still routes the tap,
                    // so it can pitch that specific season rather than being
                    // hidden or inert.
                    if isLocked(season) {
                        Label(SeasonLabel.text(season), systemImage: "crown.fill")
                    } else if season == selected {
                        Label(SeasonLabel.text(season), systemImage: "checkmark")
                    } else {
                        Text(SeasonLabel.text(season))
                    }
                }
            }
        } label: {
            label()
        }
        // Newest season first is the order the array already carries; without
        // this UIKit reverses it for menus that open upward.
        .menuOrder(.fixed)
        .gridironMenuAppearance()
        .accessibilityLabel("Season")
        .accessibilityValue(SeasonLabel.text(selected))
    }
}

struct SeasonPhaseMenu<Trigger: View>: View {
    let selected: SeasonPhase
    let onSelect: (SeasonPhase) -> Void
    @ViewBuilder let label: () -> Trigger

    var body: some View {
        Menu {
            ForEach(SeasonPhase.allCases) { phase in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(phase)
                } label: {
                    if phase == selected {
                        Label(phase.label, systemImage: "checkmark")
                    } else {
                        Text(phase.label)
                    }
                }
            }
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .gridironMenuAppearance()
        .accessibilityLabel("Season type")
        .accessibilityValue(selected.label)
    }
}

/// Season and season type in a single menu, behind whatever trigger the caller
/// draws.
///
/// Season type comes *first*, and that ordering is the whole reason one menu
/// can hold both. The season list is twenty-seven rows (All Time plus 2000
/// through the current year), which is far taller than a menu can show, so with
/// seasons on top the two phase rows sat below the fold: the control existed,
/// scrolled to the very bottom of a long list, and to anyone opening the menu
/// the playoffs simply weren't switchable. Two rows above a scrolling list cost
/// the season picker nothing and make the phase the first thing you see.
///
/// Shared by the tab nav bars and the team page. The team page used to carry a
/// season-only `SeasonMenu`, which is how a screen whose every number is filtered
/// by `selectedPhase` ended up with no way to reach the playoffs - and because
/// the Teams tab pushes straight into your favorite club on first visit, that
/// was the *only* Teams screen most sessions ever saw.
struct SeasonPhasePicker<Trigger: View>: View {
    let seasons: [Int]
    let selectedSeason: Int
    let selectedPhase: SeasonPhase
    let isSeasonLocked: (Int) -> Bool
    let onSelectSeason: (Int) -> Void
    let onSelectPhase: (SeasonPhase) -> Void
    @ViewBuilder let label: () -> Trigger

    var body: some View {
        Menu {
            Section("Season type") {
                ForEach(SeasonPhase.allCases) { phase in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelectPhase(phase)
                    } label: {
                        if phase == selectedPhase {
                            Label(phase.label, systemImage: "checkmark")
                        } else {
                            Text(phase.label)
                        }
                    }
                }
            }
            Section("Season") {
                ForEach(seasons, id: \.self) { season in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelectSeason(season)
                    } label: {
                        // A locked year keeps its crown and still routes the tap,
                        // so it can pitch that specific season.
                        if isSeasonLocked(season) {
                            Label(SeasonLabel.text(season), systemImage: "crown.fill")
                        } else if season == selectedSeason {
                            Label(SeasonLabel.text(season), systemImage: "checkmark")
                        } else {
                            Text(SeasonLabel.text(season))
                        }
                    }
                }
            }
        } label: {
            label()
        }
        // Newest season first is the order the array already carries; without
        // this UIKit reverses it for menus that open upward.
        .menuOrder(.fixed)
        .gridironMenuAppearance()
        .accessibilityLabel("Season and season type")
        .accessibilityValue(SeasonLabel.text(selectedSeason) + ", " + selectedPhase.label)
    }
}

/// Season + phase context in the navigation bar itself, alongside the tab's
/// title.
///
/// This used to be `SeasonPhaseFilterBar`, a content row sitting directly under
/// the nav bar - but only on Stats and Trends. Teams put the same two menus in
/// the bar, so the app had one control in two places: the year you were looking
/// at moved down a row when you switched tabs, and Stats/Trends each gave up
/// ~40pt of board to repeat something the bar had room for. The bar is also
/// where the season *belongs*: it's the context every number on the screen is
/// read against, not a filter you set and forget.
///
/// Both pills live in a single `ToolbarItem` rather than a `ToolbarItemGroup`
/// so the gap between them is ours to set and identical on all three tabs -
/// a group lets UIKit pick its own spacing, which is what made the pair sit
/// unevenly next to the centered title.
struct SeasonPhaseNavBar: ViewModifier {
    let title: String
    let seasons: [Int]
    let selectedSeason: Int
    let selectedPhase: SeasonPhase
    let isSeasonLocked: (Int) -> Bool
    let onSelectSeason: (Int) -> Void
    let onSelectPhase: (SeasonPhase) -> Void

    func body(content: Content) -> some View {
        content
            // No centered title.
            //
            // Four things wanted that bar at once: two season pills, the title,
            // the settings gear and the upgrade CTA. iOS resolves that by
            // dropping the title's neighbours into a "..." overflow - which on
            // Teams had already buried the upgrade button, the one control on
            // screen we most need to stay visible, and squeezed the title out
            // anyway. Something had to go, and the title was the cheapest: the
            // tab bar at the bottom of the screen already says "Stats" in green
            // with a filled icon, so the centered copy of it was the only item
            // in the bar carrying no information. Removing it leaves the pills
            // and the two trailing controls spread across the full width.
            //
            // `navigationBarTitleDisplayMode(.inline)` still matters: it keeps
            // the bar at one compact height instead of the large-title layout.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // The screen's name is NOT painted on here.
            //
            // `.accessibilityLabel` on a container hands that label to the
            // elements inside it, and this container is the whole screen: the
            // search chip, the stat picker and the View menu all announced
            // themselves as "Stats" instead of saying what they do. VoiceOver
            // still gets the screen's name from the tab bar, which says it in
            // words and marks the selected one.
            .toolbar {
                // The green pills are their own capsules; suppress the iOS 26
                // Liquid Glass container or each reads as a pill inside a pill.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { pills }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { pills }
                }
            }
    }

    /// One pill, not two.
    ///
    /// Season and phase used to be separate capsules. Together they ran to about
    /// 185pt, and with the gear and the upgrade CTA on the other side iOS ran out
    /// of bar and pushed the CTA into a "..." overflow - burying the one control
    /// we least want hidden. Dropping the centered title wasn't enough on its
    /// own, because width was the binding constraint rather than the title.
    ///
    /// Merging them costs nothing in reach (it was always one tap to open a menu,
    /// and still is) and reads better besides: "2025 · Regular" is a single fact
    /// about what you're looking at, not two settings that happen to be adjacent.
    ///
    /// See `SeasonPhasePicker` for why season type sits above the season list.
    private var pills: some View {
        SeasonPhasePicker(
            seasons: seasons,
            selectedSeason: selectedSeason,
            selectedPhase: selectedPhase,
            isSeasonLocked: isSeasonLocked,
            onSelectSeason: onSelectSeason,
            onSelectPhase: onSelectPhase
        ) {
            // No calendar glyph.
            //
            // Spelling the phase out in full ("Regular Season", not "Regular")
            // costs about fifty points, and the bar has a hard budget: overrun
            // it and iOS sweeps the trailing items into a "..." overflow, which
            // on the first build of this change swallowed the upgrade CTA - the
            // one control that must never be hidden. The glyph is what pays for
            // it, and it is the right thing to cut: a four-digit year beside the
            // word "Season" is already unmistakably a date, so the icon was
            // decoration sitting in front of the label it decorated.
            GridironNavPill(
                title: SeasonLabel.text(selectedSeason) + " · " + selectedPhase.label
            )
        }
    }
}

extension View {
    /// Pins a `Menu` to the light popup the rest of the app draws.
    ///
    /// The midnight nav bar is set up with `.toolbarColorScheme(.dark)`, which is
    /// right for the bar's own title and glyphs, but a menu presented from a
    /// toolbar item inherits that environment, so the season picker opened as a
    /// black panel while the identical Filters / sort / metric menus a row
    /// below it opened white. Same control, two looks, a tap apart. The pill
    /// labels set their own colours explicitly, so forcing light here changes
    /// nothing but the popup.
    func gridironMenuAppearance() -> some View {
        environment(\.colorScheme, .light)
    }
}

/// The tappable label for a nav-bar chooser on the midnight bar.
///
/// Every nav-bar chooser (season on Stats / Teams / a team page) drew its own
/// copy of this, and they drifted, one was a `Menu`, the others popovers, and
/// the team page's had no `fixedSize()` so it clipped to a bare icon. One view
/// now, so a change lands everywhere.
struct GridironNavPill: View {
    /// Optional: a bar that is tight on width can drop the glyph and keep the
    /// label, which is the part that carries meaning.
    var systemImage: String? = nil
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                // Micro rather than smallBold. The bar holds this pill, the
                // settings gear and the upgrade CTA, and it is a fixed budget:
                // spelling out "Regular Season" pushed the total past it and iOS
                // swept the CTA into a "..." overflow. One step down the type
                // scale buys the words back without touching the CTA, and this
                // is nav-bar chrome rather than content, so it can afford to sit
                // a size below the board it labels.
                .font(GridironType.micro)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.white)
        // Without this the toolbar squeezes the label and the title itself is
        // the first thing to get clipped, leaving a bare icon.
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(GridironPalette.turf)
        .clipShape(Capsule())
    }
}

/// In-content variant: same control, but sitting on a card rather than the midnight
/// bar, so it's a quiet outlined capsule instead of a green one. It's a
/// `GridironChip` with a chevron, so it can't drift from the sort / search /
/// Filters chips it shares a row with.
struct GridironInlinePill: View {
    let systemImage: String?
    let title: String
    var isLocked: Bool = false
    /// See `GridironChip.compressible`: set it where two of these share a
    /// half-width column, as they do in each Compare slot.
    var compressible: Bool = false

    var body: some View {
        GridironChip(
            title: title,
            systemImage: systemImage,
            trailing: .chevron,
            isLocked: isLocked,
            compressible: compressible
        )
    }
}
