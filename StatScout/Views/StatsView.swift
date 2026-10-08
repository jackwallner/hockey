import SwiftUI

/// Single home for every league-wide statistic. The position tabs and control
/// row stay fixed while the chosen statistic selects Advanced or Standard.
struct StatsView: View {
    let viewModel: DashboardViewModel
    @EnvironmentObject private var store: StoreService

    @AppStorage("stats.board") private var board: StatsBoard = .standard
    /// Set when DEF, which has no advanced line until PFR publishes, pushed the
    /// board to Standard, so leaving DEF puts Advanced back.
    @State private var fellBackFromAdvanced = false
    @State private var showingFollowing = false
    @State private var standardStat = "Pass Yds"
    @State private var standardSortDescending = true
    @State private var paywallTrigger: PaywallTrigger?

    private var position: PlayerPositionGroup { viewModel.selectedPosition }

    private var bindings: StatsBoardBindings {
        StatsBoardBindings(
            board: $board,
            standardStat: $standardStat,
            standardSortDescending: $standardSortDescending
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedSeason == viewModel.freeSeason && viewModel.selectedPhase == .regular {
                DataFreshnessView(viewModel: viewModel)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            RinkSegmented(
                segments: [
                    .init(value: false, label: "League leaders"),
                    .init(value: true, label: "Following", systemImage: "star.fill"),
                ],
                selection: $showingFollowing
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if showingFollowing {
                FollowingStatsView(viewModel: viewModel)
            } else {
                leagueBoard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RinkPalette.canvas)
        .modifier(
            SeasonPhaseNavBar(
                title: "Stats",
                seasons: viewModel.availableSeasons,
                selectedSeason: viewModel.selectedSeason,
                selectedPhase: viewModel.selectedPhase,
                isSeasonLocked: viewModel.isSeasonLocked,
                onSelectSeason: selectSeason,
                onSelectPhase: { viewModel.selectedPhase = $0 }
            )
        )
        .onChange(of: viewModel.selectedPosition) { old, next in
            let kept = StandardStatCatalog.stat(keeping: standardStat, from: old, to: next)
            if kept != standardStat {
                standardStat = kept
                standardSortDescending = StandardStatCatalog.defaultDescending(
                    for: kept,
                    position: next
                )
            }
            if viewModel.availableAdvancedSortMetrics.isEmpty, board == .advanced {
                board = .standard
                fellBackFromAdvanced = true
            } else if fellBackFromAdvanced, !viewModel.availableAdvancedSortMetrics.isEmpty {
                if board == .standard { board = .advanced }
                fellBackFromAdvanced = false
            }
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    @ViewBuilder
    private var leagueBoard: some View {
        switch board {
        case .advanced:
            DashboardView(viewModel: viewModel, boardBindings: bindings)
        case .standard:
            StandardStatsLeadersView(
                players: standardBoardPlayers,
                selectedStat: $standardStat,
                selectedPosition: selectedPositionBinding,
                sortDescending: $standardSortDescending,
                boardBindings: bindings,
                viewModel: viewModel
            )
        case .bestWorst:
            BestWorstBoard(viewModel: viewModel, bindings: bindings)
        case .contractValue:
            ContractValueBoard(viewModel: viewModel, bindings: bindings)
        }
    }

    private var standardBoardPlayers: [Player] {
        viewModel.qualifiedSeasonPlayers.filter {
            $0.positionGroup == viewModel.selectedPosition
                && viewModel.matchesSelectedConference($0)
        }
    }

    private var selectedPositionBinding: Binding<PlayerPositionGroup> {
        Binding(
            get: { viewModel.selectedPosition },
            set: { viewModel.selectedPosition = $0 }
        )
    }

    private func selectSeason(_ season: Int) {
        if viewModel.isSeasonLocked(season) {
            paywallTrigger = .lockedSeason(season)
        } else {
            viewModel.selectSeason(season)
        }
    }
}

private struct BestWorstBoard: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    let bindings: StatsBoardBindings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatsViewMenu(
                    viewModel: viewModel,
                    board: bindings.$board
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if store.isPro {
                MetricLeadersView(metrics: viewModel.allMetrics)
            } else {
                ZStack(alignment: .bottom) {
                    MetricLeadersView(metrics: viewModel.allMetrics)
                        .blur(radius: 8)
                        .allowsHitTesting(false)
                    BlurGateUnlock(
                        headline: "See who leads and who trails on every metric in the league",
                        trigger: .bestWorst
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 100)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StatsView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
