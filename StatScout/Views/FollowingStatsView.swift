import SwiftUI

struct FollowingStatsView: View {
    let viewModel: DashboardViewModel
    @State private var favorites = FavoritesStore.shared
    @State private var showingPlayers = false

    private var players: [Player] {
        FanStatsSelection.players(
            ids: favorites.playerIds, from: viewModel.seasonPlayers,
            season: viewModel.selectedSeason, phase: viewModel.selectedPhase
        )
    }

    private var missingCount: Int { Set(favorites.playerIds).count - players.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let team = favorites.team, !StatScoutSeason.isAllTime(viewModel.selectedSeason) {
                    NavigationLink(value: TeamDestination(abbr: team)) {
                        HStack(spacing: 12) {
                            TeamColorDot(abbr: team, size: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("YOUR TEAM").font(RinkType.micro)
                                    .foregroundStyle(RinkPalette.inkSecondary)
                                Text(teamFullName(team)).font(RinkType.bodyBold)
                                    .foregroundStyle(RinkPalette.ink)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(RinkPalette.inkTertiary)
                        }
                        .padding(16)
                        .background(RinkPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text("Your players").font(RinkType.cardTitle)
                    Spacer()
                    Button(players.isEmpty ? "Follow players" : "Manage") { showingPlayers = true }
                        .font(RinkType.smallBold)
                        .frame(minHeight: 44)
                }

                if favorites.playerIds.isEmpty {
                    ContentUnavailableView {
                        Label("Keep your players close", systemImage: "star")
                    } description: {
                        Text("Follow your favorites for their season stats and a shortcut to every profile. Following is\u{00A0}free.")
                    } actions: {
                        Button("Choose players") { showingPlayers = true }
                            .buttonStyle(.borderedProminent)
                    }
                }

                ForEach(players) { player in
                    NavigationLink(value: player) { playerCard(player) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Unfollow \(player.name)", systemImage: "star.slash") {
                                favorites.toggleFavorite(playerId: player.playerId)
                            }
                        }
                }

                if missingCount > 0 {
                    Text("\(missingCount) followed \(missingCount == 1 ? "player has" : "players have") no published stats for this season and phase yet. They stay on your list.")
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Color.clear.frame(height: 88)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showingPlayers) {
            FollowPlayersSheet(viewModel: viewModel)
        }
    }

    private func playerCard(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.name).font(RinkType.bodyBold)
                        .foregroundStyle(RinkPalette.ink)
                    Text("\(displayTeamAbbr(player.team)) · \(player.displayPosition)")
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(RinkPalette.inkTertiary)
            }
            let stats = FanStatsSelection.summary(for: player)
            if !stats.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(stats) { stat in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stat.value).font(RinkType.statMed).monospacedDigit()
                                .foregroundStyle(RinkPalette.turf)
                            Text(stat.label).font(RinkType.small)
                                .foregroundStyle(RinkPalette.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Three-stat lines (goalies) keep the same four columns as
                    // skaters, so the numbers line up from card to card.
                    ForEach(0..<max(0, 4 - stats.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            } else {
                Text("Open profile for available metrics")
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
        }
        .padding(16)
        .background(RinkPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
