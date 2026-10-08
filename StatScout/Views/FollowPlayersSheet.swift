import SwiftUI

/// Pick the players you follow, in bulk.
///
/// Following was previously only reachable from the star on a player's own
/// page, which is fine for the one guy you just looked up and useless for
/// building a list of ten. This is the manager: search the league, tap to
/// follow, done. Free, following is what makes the app feel like yours, and
/// what's paid is the payoff.
///
/// Opened from the Compare tab, which owns the followed list. It used to hang
/// off the Trends board, which left Trends doing two jobs and put the personal
/// list on a tab that's otherwise entirely league-wide.
struct FollowPlayersSheet: View {
    @Bindable var viewModel: DashboardViewModel
    /// Which position group the Trends board is showing, so the sheet opens
    /// on the list the user was already looking at.
    var side: TrendSide = .qb

    @Environment(\.dismiss) private var dismiss
    @State private var favorites = FavoritesStore.shared
    @State private var searchText = ""
    @State private var listSide: TrendSide

    init(viewModel: DashboardViewModel, side: TrendSide = .qb) {
        self.viewModel = viewModel
        self.side = side
        _listSide = State(initialValue: side)
    }

    private var allPlayers: [Player] {
        viewModel.players(forSeason: viewModel.selectedSeason)
    }

    private var followed: [Player] {
        // Ordered by when they were followed, matching the Trends board.
        favorites.playerIds.compactMap { id in
            allPlayers.first { $0.playerId == id }
        }
    }

    private var candidates: [Player] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let wanted: String = listSide.playerType
        let sameSide: [Player] = allPlayers.filter { player in
            (player.playerType ?? "") == wanted
        }
        let matching: [Player] = query.isEmpty ? sameSide : sameSide.filter { player in
            player.name.lowercased().contains(query) || player.team.lowercased().contains(query)
        }
        return matching.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    searchField

                    // Always present, even at zero. If this card appeared only
                    // once you'd followed someone, the browse list below would
                    // jump down by its height on the first star you tapped,
                    // right under the finger about to tap the second one.
                    card {
                        GridironSectionBar(title: "FOLLOWING (\(followed.count))")
                        if followed.isEmpty {
                            Text("Nobody yet. Tap a star to follow.")
                                .font(GridironType.small)
                                .foregroundStyle(GridironPalette.inkSecondary)
                                .frame(height: GridironGeo.rowHeight)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(followed.enumerated()), id: \.element.playerId) { index, player in
                                row(player: player, index: index)
                            }
                        }
                    }

                    card {
                        // Same five-group menu the Trends board uses. A
                        // segmented row can't hold five legibly, and the two
                        // screens ask the identical question, so they use the
                        // identical control.
                        HStack {
                            Menu {
                                ForEach(TrendSide.allCases) { option in
                                    Button {
                                        listSide = option
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        if option == listSide {
                                            Label(option.label, systemImage: "checkmark")
                                        } else {
                                            Text(option.label)
                                        }
                                    }
                                }
                            } label: {
                                GridironInlinePill(systemImage: "person.fill", title: listSide.label)
                            }
                            .menuOrder(.fixed)
                            .accessibilityLabel("Position group")
                            .accessibilityValue(listSide.label)
                            Spacer(minLength: 0)
                        }
                        .padding(12)

                        if candidates.isEmpty {
                            Text("No players match “\(searchText)”.")
                                .font(GridironType.small)
                                .foregroundStyle(GridironPalette.inkSecondary)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(candidates.enumerated()), id: \.element.playerId) { index, player in
                                row(player: player, index: index)
                            }
                        }
                    }

                    Color.clear.frame(height: 24)
                }
            }
            .background(GridironPalette.canvas)
            .navigationTitle("Follow Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(GridironType.smallBold)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GridironPalette.inkTertiary)
            TextField("Search players", text: $searchText)
                .font(GridironType.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(GridironPalette.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(GridironPalette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(GridironPalette.hairline, lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func row(player: Player, index: Int) -> some View {
        let following = favorites.isFavorite(playerId: player.playerId)
        return Button {
            favorites.toggleFavorite(playerId: player.playerId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 10) {
                PlayerHeadshot(team: player.team, initials: player.initials, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(GridironType.bodyBold)
                        .foregroundStyle(GridironPalette.ink)
                        .lineLimit(1)
                    Text("\(player.team) · \(player.position)")
                        .font(GridironType.micro)
                        .tracking(0.3)
                        .foregroundStyle(GridironPalette.inkTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: following ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(following ? Color.yellow : GridironPalette.inkTertiary)
            }
            .padding(.horizontal, GridironGeo.padInline)
            .frame(height: GridironGeo.rowHeight)
            .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(following ? "Unfollow \(player.name)" : "Follow \(player.name)")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(GridironPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                    .stroke(GridironPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
    }
}
