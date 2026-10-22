import CoreGraphics
import SwiftUI

/// Pane frames for the unfolded iPhone Duo: the tabs on the leading side of the
/// fold, the player, team or game they open on the trailing side, so no card
/// straddles the crease. `nil` keeps the single-column layout (every ordinary
/// iPhone, the folded Duo, and the unfolded Duo held in portrait, where each
/// half would be too narrow).
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the compact leaderboard, the five-tab
    /// bar and the player profile.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// What the split measures: the container's width and, on iOS 27.1, the fold.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat
    var fold: ClosedRange<CGFloat>?
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

/// Keeps a full-screen overlay (onboarding) inside the leading pane when the
/// Duo is unfolded, so its centred column never sits on the fold.
struct UnfoldedPrimaryPane: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var geometry = PaneGeometry(width: 0, fold: nil)

    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(width: geometry.width, isRegularWidth: horizontalSizeClass == .regular, fold: geometry.fold)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.horizontalSizeClass, split == nil ? horizontalSizeClass : .compact)
            .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: PaneGeometry.self) { proxy in
                PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
            } action: { geometry = $0 }
    }
}
