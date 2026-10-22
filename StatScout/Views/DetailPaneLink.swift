import SwiftUI

/// What the trailing pane of the unfolded iPhone Duo shows: the player, team
/// or game the user last opened from the leading pane.
enum PaneDetail: Hashable {
    case player(Player)
    case team(TeamDestination)
    case game(GameRoute)

    /// Identity of the page on screen. A refresh that reloads the same player
    /// with new numbers keeps it, so the pane isn't rebuilt under the reader.
    var pageID: String {
        switch self {
        case .player(let player): return "player-\(player.id)"
        case .team(let team): return "team-\(normalizedTeamAbbreviation(team.abbr))"
        case .game(let game): return "game-\(game.gameId)"
        }
    }

    /// Same page, whatever season or phase the link carried.
    func matches(_ other: PaneDetail?) -> Bool {
        switch (self, other) {
        case let (.player(a), .player(b)?): return a.playerId == b.playerId
        case let (.team(a), .team(b)?): return normalizedTeamAbbreviation(a.abbr) == normalizedTeamAbbreviation(b.abbr)
        case let (.game(a), .game(b)?): return a.gameId == b.gameId
        default: return false
        }
    }
}

extension EnvironmentValues {
    /// Set only in the leading pane while the Duo is split. `nil` everywhere
    /// else, so links push exactly as they do on a phone.
    @Entry var openInDetailPane: (@MainActor (PaneDetail) -> Void)? = nil
    /// The trailing pane's page, so the row that opened it can show it.
    @Entry var detailPaneSelection: PaneDetail? = nil
    /// True inside the trailing pane, where the status bar shares the toolbar
    /// row and a page's hero already names what it shows.
    @Entry var isInDetailPane = false
}

/// A player, team or game link. On a phone it is a `NavigationLink`; in the
/// leading pane of the unfolded Duo it opens the page beside the list instead
/// of pushing over it. Board rows pass `marksSelection` so the open row
/// carries a turf edge.
struct DetailPaneLink<Label: View>: View {
    private let detail: PaneDetail
    private let marksSelection: Bool
    private let label: Label
    @Environment(\.openInDetailPane) private var openInDetailPane
    @Environment(\.detailPaneSelection) private var selection

    init(value: Player, marksSelection: Bool = false, @ViewBuilder label: () -> Label) {
        self.init(detail: .player(value), marksSelection: marksSelection, label: label)
    }

    init(value: TeamDestination, marksSelection: Bool = false, @ViewBuilder label: () -> Label) {
        self.init(detail: .team(value), marksSelection: marksSelection, label: label)
    }

    init(value: GameRoute, marksSelection: Bool = false, @ViewBuilder label: () -> Label) {
        self.init(detail: .game(value), marksSelection: marksSelection, label: label)
    }

    private init(detail: PaneDetail, marksSelection: Bool, @ViewBuilder label: () -> Label) {
        self.detail = detail
        self.marksSelection = marksSelection
        self.label = label()
    }

    private var isOpen: Bool { detail.matches(selection) }

    var body: some View {
        if let openInDetailPane {
            Button {
                openInDetailPane(detail)
            } label: {
                label.overlay(alignment: .leading) {
                    if marksSelection, isOpen {
                        Rectangle()
                            .fill(RinkPalette.turf)
                            .frame(width: 3)
                    }
                }
            }
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        } else {
            switch detail {
            case .player(let player): NavigationLink(value: player) { label }
            case .team(let team): NavigationLink(value: team) { label }
            case .game(let game): NavigationLink(value: game) { label }
            }
        }
    }
}

/// Keeps the leading pane's toolbar horizontal while the Duo is split. Left to
/// itself, iOS 27.1 gives that phone-width pane a vertical bar against the
/// fold, which pushed the back button and gear to the crease and narrowed every
/// board by the bar's width. Elsewhere (the phone, the folded Duo, the detail
/// pane at the display edge) the system keeps choosing.
struct FoldSideToolbar: ViewModifier {
    @Environment(\.openInDetailPane) private var openInDetailPane

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(openInDetailPane == nil ? .automatic : .disabled)
        } else {
            content
        }
    }
}
