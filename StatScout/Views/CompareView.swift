import SwiftUI

/// Year-over-year history destination. Carries just the player id; the
/// destination rebuilds the season history from the view model so the route
/// stays cheap and Hashable.
struct YearCompareRoute: Hashable {
    let playerId: Int
    let playerName: String
    let phase: SeasonPhase
}

struct TeamComparisonRoute: Hashable {
    let teamA: String
    let teamB: String
    let seasonA: Int
    let phaseA: SeasonPhase
    let seasonB: Int
    let phaseB: SeasonPhase
}

/// Dedicated "Compare" tab, and the home of the players you follow.
///
/// The comparison flows also live inside the player profile (Year Compare tab +
/// the compare toolbar button); this tab doesn't replace those, it puts both
/// head-to-head and year-over-year one tap away, and blurs them behind a trial
/// pitch for non-Pro users.
///
/// Following used to have nowhere to live at all. It sat briefly on the Trends
/// board, which made Trends do two jobs, a league leaderboard and a personal
/// list, and left the tab you'd look for your own players in with no mention of
/// them. The list lives here now, above the comparison cards it feeds, and
/// stays free: following is what makes the app feel like yours, and what's paid
/// is the payoff.
struct CompareView: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    /// Whether the Compare tab is the one on screen.
    ///
    /// All four tabs are mounted at once (see `RootTabView.tabView`, which keeps
    /// each tab's navigation stack and scroll position alive by toggling opacity
    /// rather than swapping views). That means this view's `onAppear` fires at
    /// launch even when the user is looking at Stats - and it kicked off the
    /// historical decode, so every Pro user paid 33k rows of it on every cold
    /// launch, competing with the board they were actually waiting for, for a tab
    /// they might never open. `HotColdView` already takes this flag for the same
    /// reason; Compare never got it.
    var isActive: Bool = true

    private enum PickerTarget: Identifiable {
        case playerA, playerB, yearPlayer, teamA, teamB
        var id: Int { hashValue }
    }

    @State private var playerA: Player?
    @State private var playerB: Player?
    @State private var picker: PickerTarget?
    @State private var comparisonRoute: ComparisonRoute?
    @State private var yearRoute: YearCompareRoute?
    @State private var showingTrial = false
    @State private var showingFollowSheet = false
    @State private var favorites = FavoritesStore.shared
    @State private var seasonA: Int?
    @State private var seasonB: Int?
    @State private var phaseA: SeasonPhase
    @State private var phaseB: SeasonPhase
    @State private var yearPhase: SeasonPhase
    @State private var teamA: String?
    @State private var teamB: String?
    @State private var teamSeasonA: Int?
    @State private var teamSeasonB: Int?
    @State private var teamPhaseA: SeasonPhase
    @State private var teamPhaseB: SeasonPhase
    @State private var teamComparisonRoute: TeamComparisonRoute?

    init(viewModel: DashboardViewModel, isActive: Bool = true) {
        self.viewModel = viewModel
        self.isActive = isActive
        _seasonA = State(initialValue: viewModel.selectedSeason)
        _seasonB = State(initialValue: viewModel.selectedSeason)
        _phaseA = State(initialValue: viewModel.selectedPhase)
        _phaseB = State(initialValue: viewModel.selectedPhase)
        _yearPhase = State(initialValue: viewModel.selectedPhase)
        _teamSeasonA = State(initialValue: viewModel.selectedSeason)
        _teamSeasonB = State(initialValue: viewModel.selectedSeason)
        _teamPhaseA = State(initialValue: viewModel.selectedPhase)
        _teamPhaseB = State(initialValue: viewModel.selectedPhase)
    }

    private var activeSeasonA: Int { seasonA ?? viewModel.selectedSeason }
    private var activeSeasonB: Int { seasonB ?? viewModel.selectedSeason }
    private var activeTeamSeasonA: Int { teamSeasonA ?? viewModel.selectedSeason }
    private var activeTeamSeasonB: Int { teamSeasonB ?? viewModel.selectedSeason }

    /// The same club twice is a legitimate comparison - a franchise against its
    /// own past is the whole point of holding a season picker under each slot.
    /// Only the exactly-identical pair is refused, because that one compares a
    /// roster with itself and every row would tie.
    private var isSameTeamContext: Bool {
        guard let teamA, let teamB else { return false }
        return normalizedTeamAbbreviation(teamA) == normalizedTeamAbbreviation(teamB)
            && activeTeamSeasonA == activeTeamSeasonB
            && teamPhaseA == teamPhaseB
    }

    private var canCompareTeams: Bool {
        teamA != nil && teamB != nil && !isSameTeamContext
    }

    /// Says why the button is off, rather than leaving a grey button with no
    /// explanation - the fix (change one side's season) isn't guessable.
    private var teamWarning: String? {
        guard isSameTeamContext, let teamA else { return nil }
        return "Both sides are \(teamFullName(teamA)) in \(SeasonLabel.text(activeTeamSeasonA)) \(teamPhaseA.label.lowercased()). Change one side's season or season type to compare."
    }

    private func players(forSeason season: Int, phase: SeasonPhase) -> [Player] {
        viewModel.players(forSeason: season, phase: phase).sorted { $0.name < $1.name }
    }

    private func resolved(
        _ player: Player?,
        season: Int,
        phase: SeasonPhase
    ) -> Player? {
        guard let player else { return nil }
        if player.season == season, player.seasonPhase == phase {
            return player
        }
        return viewModel.playerHistories[player.playerId]?.first {
            $0.season == season && $0.seasonPhase == phase
        }
    }

    private var resolvedA: Player? {
        resolved(playerA, season: activeSeasonA, phase: phaseA)
    }

    private var resolvedB: Player? {
        resolved(playerB, season: activeSeasonB, phase: phaseB)
    }
    private var canCompareResolvedPlayers: Bool {
        guard let a = resolvedA, let b = resolvedB else { return false }
        return a.canCompareHeadToHead(with: b)
    }

    private var slotWarning: String? {
        if viewModel.isHistoricalLoading, resolvedA == nil || resolvedB == nil {
            return "Loading past seasons…"
        }
        if let playerA, resolvedA == nil {
            return "No \(SeasonLabel.text(activeSeasonA)) \(phaseA.label.lowercased()) data for \(playerA.name)."
        }
        if let playerB, resolvedB == nil {
            return "No \(SeasonLabel.text(activeSeasonB)) \(phaseB.label.lowercased()) data for \(playerB.name)."
        }
        if let a = resolvedA, let b = resolvedB, !a.canCompareHeadToHead(with: b) {
            return "Choose two offensive players or two defensive players."
        }
        return nil
    }

    /// The followed players that exist in the selected season, in the order
    /// they were followed.
    private var followedPlayers: [Player] {
        let roster = viewModel.players(
            forSeason: activeSeasonA,
            phase: phaseA
        )
        return favorites.playerIds.compactMap { id in
            roster.first { $0.playerId == id }
        }
    }

    private func teamsWithData(
        season: Int,
        phase: SeasonPhase
    ) -> [String] {
        Set(
            viewModel.players(forSeason: season, phase: phase)
                .map { normalizedTeamAbbreviation($0.team) }
        )
        .sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                yourPlayersCard

                // Only the comparison cards blur. Following is free, so putting
                // the whole page behind the gate would have hidden the one
                // thing a free user can actually do here.
                ZStack(alignment: .bottom) {
                    VStack(spacing: 12) {
                        playerVsPlayerCard
                        teamVsTeamCard
                        yearOverYearCard
                    }
                    .blur(radius: store.isPro ? 0 : 5)
                    .disabled(!store.isPro)
                    .allowsHitTesting(store.isPro)

                    if !store.isPro {
                        // The same gate every other locked module uses, rather
                        // than this screen's own floating panel.
                        BlurGateUnlock(
                            headline: "Stack any two players, or any player against his own past seasons",
                            trigger: .playerComparison
                        )
                        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
            // Scroll-under spacer so content can pass behind the floating tab
            // bar, matches the Dashboard / Teams pattern.
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await viewModel.load() }
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFollowSheet) {
            FollowPlayersSheet(viewModel: viewModel)
        }
        // Keyed on `isActive` rather than a bare `onAppear`, so the preload waits
        // until the tab is actually opened. It still runs ahead of the user
        // picking a player, which is the point of preloading at all.
        .task(id: "\(isActive)-\(store.isPro)") {
            guard isActive, store.isPro,
                  !viewModel.hasLoadedHistorical,
                  !viewModel.isHistoricalLoading else { return }
            await viewModel.loadHistoricalIfNeeded()
        }
        .task(
            id: "\(activeSeasonA)-\(phaseA.rawValue)-\(activeSeasonB)-\(phaseB.rawValue)-\(activeTeamSeasonA)-\(teamPhaseA.rawValue)-\(activeTeamSeasonB)-\(teamPhaseB.rawValue)"
        ) {
            guard store.isPro,
                  activeSeasonA != viewModel.selectedSeason
                    || activeSeasonB != viewModel.selectedSeason
                    || activeTeamSeasonA != viewModel.selectedSeason
                    || activeTeamSeasonB != viewModel.selectedSeason
            else { return }
            await viewModel.loadHistoricalIfNeeded()
        }
        .sheet(item: $picker) { target in
            let context: (season: Int, phase: SeasonPhase) = {
                switch target {
                case .playerA: return (activeSeasonA, phaseA)
                case .playerB: return (activeSeasonB, phaseB)
                case .yearPlayer: return (activeSeasonA, yearPhase)
                case .teamA: return (activeTeamSeasonA, teamPhaseA)
                case .teamB: return (activeTeamSeasonB, teamPhaseB)
                }
            }()
            switch target {
            case .teamA, .teamB:
                // Every club with data, including the one already in the other
                // slot. Seahawks 2016 against Seahawks 2025 is one of the most
                // natural questions this card can answer, and filtering the
                // duplicate out made it unaskable: the slots both open on the
                // selected season, so the team you wanted was missing from the
                // list at the exact moment you went looking for it. The
                // degenerate case (same club, same season, same phase) is
                // handled at the Compare button instead, where it can say why.
                CompareTeamPicker(
                    teams: teamsWithData(
                        season: context.season,
                        phase: context.phase
                    )
                ) { selected in
                    if target == .teamA {
                        teamA = selected
                    } else {
                        teamB = selected
                    }
                }
            default:
                ComparePlayerPicker(
                    players: players(
                        forSeason: context.season,
                        phase: context.phase
                    ).filter { candidate in
                        switch target {
                        case .playerA:
                            return (
                                candidate.playerId != playerB?.playerId
                                    || context.season != activeSeasonB
                                    || context.phase != phaseB
                            )
                                && (resolvedB?.canCompareHeadToHead(with: candidate) ?? true)
                        case .playerB:
                            return (
                                candidate.playerId != playerA?.playerId
                                    || context.season != activeSeasonA
                                    || context.phase != phaseA
                            )
                                && (resolvedA?.canCompareHeadToHead(with: candidate) ?? true)
                        case .yearPlayer: return true
                        case .teamA, .teamB: return false
                        }
                    },
                    season: context.season,
                    isLoading: viewModel.isHistoricalLoading
                ) { selected in
                    switch target {
                    case .playerA: playerA = selected
                    case .playerB: playerB = selected
                    case .yearPlayer:
                        comparisonRoute = nil
                        yearRoute = YearCompareRoute(
                            playerId: selected.playerId,
                            playerName: selected.name,
                            phase: yearPhase
                        )
                    case .teamA, .teamB: break
                    }
                }
            }
        }
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .playerComparison)
        }
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(
                playerA: route.playerA,
                playerB: route.playerB,
                catalog: ComparisonCatalog(
                    viewModel: viewModel,
                    defaultPhase: route.playerA.seasonPhase
                )
            )
                .modifier(GridironNavBarPublic())
        }
        .navigationDestination(item: $yearRoute) { route in
            YearCompareDestination(
                route: route,
                viewModel: viewModel,
                onChangePlayer: { picker = .yearPlayer }
            )
                .modifier(GridironNavBarPublic())
        }
        .navigationDestination(item: $teamComparisonRoute) { route in
            TeamComparisonView(
                route: route,
                playersA: viewModel.players(
                    forSeason: route.seasonA,
                    phase: route.phaseA
                ),
                playersB: viewModel.players(
                    forSeason: route.seasonB,
                    phase: route.phaseB
                )
            )
            .modifier(GridironNavBarPublic())
        }
    }

    private var intro: some View {
        VStack(spacing: 6) {
            Text("Compare")
                .font(GridironType.pageTitle)
                .foregroundStyle(GridironPalette.ink)
            Text("Stack two players head-to-head, or track one player across seasons.")
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// The followed list. Free, and the first thing on the tab: it's the only
    /// personal state the app holds, and it feeds the slots below it.
    private var yourPlayersCard: some View {
        VStack(spacing: 0) {
            GridironSectionBar(
                title: "YOUR PLAYERS",
                trailing: AnyView(
                    Button {
                        showingFollowSheet = true
                    } label: {
                        Label(favorites.playerIds.isEmpty ? "Add" : "Edit", systemImage: "star")
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.turf)
                    }
                    .buttonStyle(.plain)
                )
            )

            if followedPlayers.isEmpty {
                VStack(spacing: 8) {
                    Text("Follow players to keep them one tap from a comparison, and to spot them on the Trends board.")
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showingFollowSheet = true
                    } label: {
                        Text("Follow players")
                            .font(GridironType.smallBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: GridironControl.height)
                            .background(GridironPalette.turf)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(followedPlayers.enumerated()), id: \.element.playerId) { index, player in
                    followedRow(player: player, index: index)
                }
                Text(store.isPro
                     ? "Tap a player to load them into a slot below."
                     : "Tap a player to see their stats. Head-to-head needs StatScout+.")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, GridironGeo.padCard)
                    .padding(.vertical, 10)
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    /// A followed player, and what tapping him does.
    ///
    /// For Pro that's "load into a comparison slot". For everyone else it's
    /// "open his page": his own stats are free, so a free tap that threw up the
    /// comparison pitch would give the user nothing, on a list they built
    /// themselves. Head-to-head is what's paid; a player's own numbers never
    /// were. The pitch is still one row further down, on the blurred cards that
    /// actually need it.
    @ViewBuilder
    private func followedRow(player: Player, index: Int) -> some View {
        let inSlot = playerA?.playerId == player.playerId || playerB?.playerId == player.playerId

        HStack(spacing: 0) {
            if store.isPro {
                Button {
                    loadIntoSlot(player)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    followedRowLabel(player: player, inSlot: inSlot)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Loads \(player.name) into a comparison slot")

                // A Pro tap is spent on the slot, which left the list you
                // curated yourself with no way through to any of the pages it
                // names. The chevron is its own target and does the obvious
                // thing.
                NavigationLink(value: player) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .frame(width: 40, height: GridironGeo.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(player.name)'s page")
            } else {
                NavigationLink(value: player) {
                    followedRowLabel(player: player, inSlot: inSlot)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(player.name)'s stats")
            }
        }
        .padding(.trailing, store.isPro ? 4 : 0)
        .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
            alignment: .bottom
        )
        .contextMenu {
            NavigationLink(value: player) {
                Label("Open player page", systemImage: "person.text.rectangle")
            }
            Button(role: .destructive) {
                favorites.toggleFavorite(playerId: player.playerId)
            } label: {
                Label("Unfollow", systemImage: "star.slash")
            }
        }
    }

    private func followedRowLabel(player: Player, inSlot: Bool) -> some View {
        HStack(spacing: 10) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
                    .lineLimit(1)
                Text("\(displayTeamAbbr(player.team)) · \(player.displayPosition)")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
            Spacer(minLength: 0)
            if inSlot {
                Text("IN SLOT")
                    .font(GridironType.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GridironPalette.turf)
                    .clipShape(Capsule())
            } else {
                // The glyph states the outcome: a slot to fill for Pro (the
                // chevron beside it opens the page), a page to open for
                // everyone else.
                Image(systemName: store.isPro ? "plus.circle" : "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
        }
        .padding(.leading, GridironGeo.padInline)
        .padding(.trailing, store.isPro ? 6 : GridironGeo.padInline)
        .frame(height: GridironGeo.rowHeight)
        .contentShape(Rectangle())
    }

    /// Fills the first empty slot, then replaces the older of the two, so
    /// tapping down a list keeps swapping the challenger against a held player
    /// rather than clearing both.
    private func loadIntoSlot(_ player: Player) {
        if playerA == nil || playerA?.playerId == player.playerId {
            playerA = player
        } else if playerB == nil || playerB?.playerId == player.playerId {
            if let playerA, !playerA.canCompareHeadToHead(with: player) {
                self.playerA = player
                playerB = nil
                return
            }
            playerB = player
        } else {
            if let playerA, !playerA.canCompareHeadToHead(with: player) {
                self.playerA = nil
            }
            playerB = player
        }
    }

    private var playerVsPlayerCard: some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: "PLAYER VS PLAYER")

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    slotColumn(
                        player: playerA,
                        placeholder: "Player A",
                        season: activeSeasonA,
                        phase: phaseA,
                        onPickPlayer: { picker = .playerA },
                        onPickSeason: { seasonA = $0 },
                        onPickPhase: { phaseA = $0 }
                    )
                    Text("vs")
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .padding(.top, 40)
                    slotColumn(
                        player: playerB,
                        placeholder: "Player B",
                        season: activeSeasonB,
                        phase: phaseB,
                        onPickPlayer: { picker = .playerB },
                        onPickSeason: { seasonB = $0 },
                        onPickPhase: { phaseB = $0 }
                    )
                }

                if let slotWarning {
                    Text(slotWarning)
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    if let a = resolvedA, let b = resolvedB,
                       a.canCompareHeadToHead(with: b) {
                        comparisonRoute = ComparisonRoute(playerA: a, playerB: b)
                    }
                } label: {
                    Text("Compare")
                        .font(GridironType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(canCompareResolvedPlayers
                                    ? GridironPalette.turf
                                    : GridironPalette.inkTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canCompareResolvedPlayers)
            }
            .padding(16)
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private var yearOverYearCard: some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: "YEAR OVER YEAR")

            VStack(spacing: 12) {
                Text("Pick a player and season type to compare their aggregated stats across years.")
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SeasonPhaseMenu(
                        selected: yearPhase,
                        onSelect: { yearPhase = $0 }
                    ) {
                        GridironInlinePill(
                            systemImage: "football.fill",
                            title: yearPhase.label
                        )
                    }

                    Button {
                        picker = .yearPlayer
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Choose a player")
                                .font(GridironType.bodyBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(GridironPalette.turf)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private var teamVsTeamCard: some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: "TEAM VS TEAM")

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    teamSlotColumn(
                        team: teamA,
                        placeholder: "Team A",
                        season: activeTeamSeasonA,
                        phase: teamPhaseA,
                        onPickTeam: { picker = .teamA },
                        onPickSeason: { teamSeasonA = $0 },
                        onPickPhase: { teamPhaseA = $0 }
                    )
                    Text("vs")
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .padding(.top, 40)
                    teamSlotColumn(
                        team: teamB,
                        placeholder: "Team B",
                        season: activeTeamSeasonB,
                        phase: teamPhaseB,
                        onPickTeam: { picker = .teamB },
                        onPickSeason: { teamSeasonB = $0 },
                        onPickPhase: { teamPhaseB = $0 }
                    )
                }

                if let teamWarning {
                    Text(teamWarning)
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    guard let teamA, let teamB, canCompareTeams else { return }
                    teamComparisonRoute = TeamComparisonRoute(
                        teamA: teamA,
                        teamB: teamB,
                        seasonA: activeTeamSeasonA,
                        phaseA: teamPhaseA,
                        seasonB: activeTeamSeasonB,
                        phaseB: teamPhaseB
                    )
                } label: {
                    Text("Compare Teams")
                        .font(GridironType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            canCompareTeams
                                ? GridironPalette.turf
                                : GridironPalette.inkTertiary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canCompareTeams)

            }
            .padding(16)
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private func teamSlotColumn(
        team: String?,
        placeholder: String,
        season: Int,
        phase: SeasonPhase,
        onPickTeam: @escaping () -> Void,
        onPickSeason: @escaping (Int) -> Void,
        onPickPhase: @escaping (SeasonPhase) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            teamSlot(
                team: team,
                placeholder: placeholder,
                action: onPickTeam
            )

            SeasonPhasePicker(
                // Team-scoped, so no All Time: a career line carries the
                // player's last club and would miscredit the franchise.
                seasons: viewModel.seasonsExcludingAllTime,
                selectedSeason: season,
                selectedPhase: phase,
                isSeasonLocked: viewModel.isSeasonLocked,
                onSelectSeason: { picked in
                    if viewModel.isSeasonLocked(picked) {
                        showingTrial = true
                    } else {
                        onPickSeason(picked)
                    }
                },
                onSelectPhase: onPickPhase
            ) {
                GridironInlinePill(
                    systemImage: nil,
                    title: "\(SeasonLabel.text(season)) · \(phase.label)",
                    compressible: true
                )
                .frame(maxWidth: .infinity)
            }
            // Named by its slot. `SeasonPhasePicker` labels itself "Season and
            // season type", and three of them on one screen - the nav bar's and
            // one per team - left VoiceOver saying the same phrase three times
            // with no way to tell which control was which.
            .accessibilityLabel("Season and season type for \(team ?? placeholder)")
        }
        .frame(maxWidth: .infinity)
    }

    private func teamSlot(
        team: String?,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(team.map(NFLTeamColor.color) ?? GridironPalette.surfaceAlt)
                        .frame(width: 48, height: 48)
                    Text(team.map(displayTeamAbbr) ?? "+")
                        .font(GridironType.smallBold)
                        .foregroundStyle(team == nil ? GridironPalette.inkTertiary : .white)
                }
                Text(team.map(teamFullName) ?? placeholder)
                    .font(GridironType.smallBold)
                    .foregroundStyle(team == nil ? GridironPalette.inkTertiary : GridironPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(GridironPalette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private func slotColumn(
        player: Player?,
        placeholder: String,
        season: Int,
        phase: SeasonPhase,
        onPickPlayer: @escaping () -> Void,
        onPickSeason: @escaping (Int) -> Void,
        onPickPhase: @escaping (SeasonPhase) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            playerSlot(player: player, placeholder: placeholder, action: onPickPlayer)

            SeasonPhasePicker(
                seasons: viewModel.availableSeasons,
                selectedSeason: season,
                selectedPhase: phase,
                isSeasonLocked: { viewModel.isSeasonLocked($0) },
                onSelectSeason: { picked in
                    if viewModel.isSeasonLocked(picked) {
                        showingTrial = true
                    } else {
                        onPickSeason(picked)
                    }
                },
                onSelectPhase: onPickPhase
            ) {
                GridironInlinePill(
                    systemImage: nil,
                    title: "\(SeasonLabel.text(season)) · \(phase.label)",
                    compressible: true
                )
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Season and season type for \(player?.name ?? placeholder)")
        }
        .frame(maxWidth: .infinity)
    }

    private func playerSlot(player: Player?, placeholder: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let player {
                    PlayerHeadshot(team: player.team, initials: player.initials, size: 44)
                    Text(player.name)
                        .font(GridironType.smallBold)
                        .foregroundStyle(GridironPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    ZStack {
                        Circle()
                            .fill(GridironPalette.surfaceAlt)
                            .frame(width: 44, height: 44)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(GridironPalette.inkTertiary)
                    }
                    Text(placeholder)
                        .font(GridironType.small)
                        .foregroundStyle(GridironPalette.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(GridironPalette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var lockedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.yellow)
            Text("Find the Edge")
                .font(GridironType.cardTitle)
                .foregroundStyle(GridironPalette.ink)
            Text("Compare is a StatScout+ feature.")
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                perkRow("person.2.fill", "Head-to-head comparisons across every metric")
                perkRow("chart.line.uptrend.xyaxis", "Year-over-year trends for any player")
                perkRow("calendar.badge.clock", "Every past season unlocked")
                perkRow("arrow.down.circle.fill", "Available offline, even at the stadium")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Button {
                showingTrial = true
            } label: {
                HStack(spacing: 6) {
                    Text(store.paywallBlurCTA)
                        .font(GridironType.bodyBold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(GridironPalette.turf)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            if let subtext = store.paywallBlurSubtext {
                Text(subtext)
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .fill(GridironPalette.surface)
                .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 28)
    }

    private func perkRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GridironPalette.turf)
                .frame(width: 16)
            Text(text)
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Resolves a `YearCompareRoute` into the player's season history and renders
/// the existing year-over-year comparison. Empty-history players surface a
/// graceful message instead of a blank screen.
private struct YearCompareDestination: View {
    let route: YearCompareRoute
    let viewModel: DashboardViewModel
    var onChangePlayer: (() -> Void)? = nil

    private var history: [Player] {
        (viewModel.playerHistories[route.playerId] ?? []).filter {
            $0.seasonPhase == route.phase
        }
    }

    private var latest: Player? {
        history.max { ($0.season ?? 0) < ($1.season ?? 0) }
    }

    @ViewBuilder
    private var playerBar: some View {
        HStack(spacing: 10) {
            if let latest {
                NavigationLink(value: latest) {
                    HStack(spacing: 10) {
                        PlayerHeadshot(team: latest.team, initials: latest.initials, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.playerName)
                                .font(GridironType.bodyBold)
                                .foregroundStyle(GridironPalette.ink)
                                .lineLimit(1)
                            Text("\(displayTeamAbbr(latest.team)) · \(latest.displayPosition)")
                                .font(GridironType.micro)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(route.playerName)'s page")
            } else {
                Text(route.playerName)
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
            }

            Spacer(minLength: 0)

            if let onChangePlayer {
                Button(action: onChangePlayer) {
                    GridironInlinePill(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Change"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare a different player's seasons")
            }
        }
        .padding(.horizontal, GridironGeo.padInline)
        .padding(.vertical, 10)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                playerBar
                if history.count < 2 {
                    ContentUnavailableView {
                        Label("Not enough history", systemImage: "calendar.badge.clock")
                    } description: {
                        Text(viewModel.isHistoricalLoading
                             ? "Loading past seasons for \(route.playerName)…"
                             : "\(route.playerName) doesn't have multiple seasons of data to compare.")
                    }
                    .padding(.vertical, 64)
                } else {
                    YearComparisonView(history: history)
                }
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationTitle(route.playerName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lightweight, self-contained player picker (the profile screen's picker is
/// private to that file).
struct ComparePlayerPicker: View {
    let players: [Player]
    var season: Int? = nil
    var isLoading: Bool = false
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Player] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.team.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { player in
                Button {
                    dismiss()
                    onSelect(player)
                } label: {
                    HStack(spacing: 12) {
                        PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(GridironType.bodyBold)
                                .foregroundStyle(GridironPalette.ink)
                            Text("\(player.team) · \(player.displayPosition)")
                                .font(GridironType.small)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(
                            isLoading ? "Loading players…" : "No players",
                            systemImage: "person.slash"
                        )
                    } description: {
                        if isLoading {
                            Text("Pulling the \(season.map(String.init) ?? "") roster.")
                        } else if !searchText.isEmpty {
                            Text("Nobody matches “\(searchText)”.")
                        } else if let season {
                            Text("No player data for the " + SeasonLabel.text(season) + " season.")
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
            .navigationTitle(season.map { "Select Player · " + String($0) } ?? "Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CompareTeamPicker: View {
    let teams: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredTeams: [String] {
        let sorted = teams.sorted { teamFullName($0) < teamFullName($1) }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.localizedCaseInsensitiveContains(searchText)
                || teamFullName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredTeams, id: \.self) { team in
                Button {
                    dismiss()
                    onSelect(team)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(NFLTeamColor.color(team))
                                .frame(width: 36, height: 36)
                            Text(displayTeamAbbr(team))
                                .font(GridironType.micro)
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(teamFullName(team))
                                .font(GridironType.bodyBold)
                                .foregroundStyle(GridironPalette.ink)
                            Text(displayTeamAbbr(team))
                                .font(GridironType.small)
                                .foregroundStyle(GridironPalette.inkTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search teams"
            )
            .navigationTitle("Select Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct TeamComparisonView: View {
    let route: TeamComparisonRoute
    let playersA: [Player]
    let playersB: [Player]

    private struct StatRow: Identifiable {
        let id: String
        let label: String
        let aText: String
        let bText: String
        /// Comparison values, sign-flipped for lower-is-better metrics so the
        /// trophy always goes to the greater number. Nil means "show the value,
        /// don't declare a winner".
        let aValue: Double?
        let bValue: Double?
    }

    /// Roster aggregates that are context rather than a verdict. Both are shares
    /// of a team's own passing volume, so summing them across a roster measures
    /// how much of the offence we track, not how good it is.
    private static let descriptiveOnlyLabels: Set<String> = ["Target Share", "WOPR"]

    private var rosterA: [Player] {
        playersA.filter {
            normalizedTeamAbbreviation($0.team)
                == normalizedTeamAbbreviation(route.teamA)
        }
    }

    private var rosterB: [Player] {
        playersB.filter {
            normalizedTeamAbbreviation($0.team)
                == normalizedTeamAbbreviation(route.teamB)
        }
    }

    /// Advanced rows come from `metrics`, standard rows from `standard_stats`,
    /// so they are built separately and interleaved category by category. The
    /// team card used to show only the standard half, which left the one screen
    /// in the app that exists to answer "which of these two teams is better"
    /// unable to reference a single advanced number - the exact thing the rest
    /// of the app is built on.
    private var statGroups: [(title: String, rows: [StatRow])] {
        MetricCategory.allCases.flatMap { category -> [(title: String, rows: [StatRow])] in
            [
                (category.rawValue.uppercased() + " · ADVANCED", advancedRows(for: category)),
                (category.rawValue.uppercased() + " · STANDARD", standardRows(for: category)),
            ]
        }
        .map { group in
            (title: group.title, rows: group.rows.filter { $0.aText != "-" || $0.bText != "-" })
        }
        .filter { !$0.rows.isEmpty }
    }

    /// Every advanced metric that either roster has for this category, in the
    /// registry's own display order so the card reads like the player page.
    private func advancedRows(for category: MetricCategory) -> [StatRow] {
        let labels = FootballMetricRegistry.definitions
            .filter { $0.category == category && $0.kind == .advanced }
            .sorted { $0.priority < $1.priority }
            .map(\.label)

        return labels.compactMap { label in
            let a = aggregate(label: label, category: category, roster: rosterA)
            let b = aggregate(label: label, category: category, roster: rosterB)
            guard a != nil || b != nil else { return nil }
            let format = MetricValueFormat.inferred(
                from: (rosterA + rosterB).compactMap { player in
                    player.metrics.first { $0.label == label && $0.category == category }?.value
                }
            )
            // Lower-is-better metrics (Sack%, INT%, Fumble%) must not hand the
            // trophy to the bigger number. Flipping the sign of both sides is
            // enough: the comparison is only ever "is mine greater than theirs".
            let higherIsBetter = FootballMetricRegistry
                .definition(for: label, category: category)?.higherIsBetter ?? true
            let sign: Double = higherIsBetter ? 1 : -1
            // Some aggregates describe a roster without ranking it. A team's
            // summed Target Share is mostly a count of how many of its receivers
            // cleared the qualification bar, so awarding a trophy for the bigger
            // number would be scoring roster shape as if it were quality. Nil
            // values keep the row (it is genuinely interesting context) and
            // suppress the marker.
            let comparable = !Self.descriptiveOnlyLabels.contains(label)
            return StatRow(
                id: category.rawValue + "-adv-" + label,
                label: label,
                aText: a.map(format.string) ?? "-",
                bText: b.map(format.string) ?? "-",
                aValue: comparable ? a.map { $0 * sign } : nil,
                bValue: comparable ? b.map { $0 * sign } : nil
            )
        }
    }

    /// Pools one metric across a roster using the registry's aggregation rule.
    private func aggregate(
        label: String,
        category: MetricCategory,
        roster: [Player]
    ) -> Double? {
        let values = roster.compactMap { player -> (value: Double, weight: Double)? in
            guard let metric = player.metrics.first(where: {
                $0.label == label && $0.category == category
            }), let value = DashboardViewModel.rawNumeric(metric.value) else { return nil }

            switch FootballMetricRegistry.aggregation(for: label, category: category) {
            case .sum:
                return (value, 1)
            case .weighted(let weight):
                // No volume means no rate to trust: drop the player rather than
                // let an unweighted value slide in as if it were weight 1.
                guard let w = weight.value(for: player) else { return nil }
                return (value, w)
            }
        }
        guard !values.isEmpty else { return nil }

        switch FootballMetricRegistry.aggregation(for: label, category: category) {
        case .sum:
            return values.reduce(0) { $0 + $1.value }
        case .weighted:
            let totalWeight = values.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { return nil }
            return values.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
        }
    }

    private func standardRows(for category: MetricCategory) -> [StatRow] {
        switch category {
        case .passing:
            return [
                pairedRow(label: "Cmp/Att", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Pass Yds", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Pass TD", rosterA: rosterA, rosterB: rosterB),
                totalRow(
                    label: "INT",
                    rosterA: rosterA,
                    rosterB: rosterB,
                    higherIsBetter: false
                ),
            ]
        case .rushing:
            return [
                totalRow(label: "Car", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Rush Yds", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Rush TD", rosterA: rosterA, rosterB: rosterB),
            ]
        case .receiving:
            return [
                pairedRow(label: "Rec/Tgt", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Rec Yds", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Rec TD", rosterA: rosterA, rosterB: rosterB),
            ]
        case .defense:
            return [
                totalRow(label: "Tackles", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Sacks", rosterA: rosterA, rosterB: rosterB),
                totalRow(label: "Def INT", rosterA: rosterA, rosterB: rosterB),
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    teamHeader(
                        route.teamA,
                        rosterCount: rosterA.count,
                        season: route.seasonA,
                        phase: route.phaseA
                    )
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GridironPalette.inkTertiary)
                    teamHeader(
                        route.teamB,
                        rosterCount: rosterB.count,
                        season: route.seasonB,
                        phase: route.phaseB
                    )
                }

                if statGroups.isEmpty {
                    ContentUnavailableView {
                        Label("No aggregate stats", systemImage: "sum")
                    } description: {
                        Text("Neither selected roster has standard stats for this context.")
                    }
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .background(GridironPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                } else {
                    ForEach(statGroups, id: \.title) { group in
                        VStack(spacing: 0) {
                            GridironSectionBar(title: group.title)
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                statRow(row, index: index)
                            }
                        }
                        .background(GridironPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                        .overlay(
                            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                                .stroke(GridironPalette.hairline, lineWidth: 0.5)
                        )
                    }
                }

                Text("Totals sum the selected roster's player season lines. Traded players bring their full-season line, so these are roster aggregates rather than official team totals.")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            Color.clear.frame(height: 88)
        }
        .background(GridironPalette.canvas.ignoresSafeArea())
        .navigationTitle("Team Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func teamHeader(
        _ team: String,
        rosterCount: Int,
        season: Int,
        phase: SeasonPhase
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(NFLTeamColor.color(team))
                    .frame(width: 58, height: 58)
                Text(displayTeamAbbr(team))
                    .font(GridironType.smallBold)
                    .foregroundStyle(.white)
            }
            Text(teamFullName(team))
                .font(GridironType.bodyBold)
                .foregroundStyle(GridironPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(
                String(rosterCount)
                    + " tracked · "
                    + SeasonLabel.text(season)
                    + " "
                    + phase.label
            )
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private func statRow(_ row: StatRow, index: Int) -> some View {
        HStack(spacing: 8) {
            statValue(
                row.aText,
                value: row.aValue,
                other: row.bValue
            )
            Text(row.label)
                .font(GridironType.smallBold)
                .foregroundStyle(GridironPalette.ink)
                .frame(width: 88)
            statValue(
                row.bText,
                value: row.bValue,
                other: row.aValue
            )
        }
        .frame(height: 56)
        .padding(.horizontal, GridironGeo.padInline)
        .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
        .overlay(
            Rectangle()
                .fill(GridironPalette.divider)
                .frame(height: GridironGeo.hairline),
            alignment: .bottom
        )
    }

    private func statValue(
        _ text: String,
        value: Double?,
        other: Double?
    ) -> some View {
        HStack(spacing: 4) {
            if let value, let other, value > other {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.yellow)
            }
            Text(text)
                .font(GridironType.statMed)
                .foregroundStyle(text == "-" ? GridironPalette.inkTertiary : GridironPalette.turf)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// `higherIsBetter: false` flips which side gets the trophy. Interceptions
    /// thrown was the row that needed it: as a plain total it handed the marker
    /// to whichever offence turned the ball over *more*, which is backwards, and
    /// on the one screen whose whole job is saying which team is better.
    private func totalRow(
        label: String,
        rosterA: [Player],
        rosterB: [Player],
        higherIsBetter: Bool = true
    ) -> StatRow {
        let a = total(label: label, roster: rosterA)
        let b = total(label: label, roster: rosterB)
        let sign: Double = higherIsBetter ? 1 : -1
        return StatRow(
            id: label,
            label: label,
            aText: format(a, label: label),
            bText: format(b, label: label),
            aValue: a.map { $0 * sign },
            bValue: b.map { $0 * sign }
        )
    }

    private func pairedRow(
        label: String,
        rosterA: [Player],
        rosterB: [Player]
    ) -> StatRow {
        StatRow(
            id: label,
            label: label,
            aText: pairedTotal(label: label, roster: rosterA),
            bText: pairedTotal(label: label, roster: rosterB),
            aValue: nil,
            bValue: nil
        )
    }

    private func total(label: String, roster: [Player]) -> Double? {
        let values = roster.compactMap { player in
            player.standardStats?
                .first { $0.label == label }
                .flatMap { DashboardViewModel.rawNumeric($0.value) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func pairedTotal(label: String, roster: [Player]) -> String {
        let pairs = roster.compactMap { player -> (Double, Double)? in
            guard let raw = player.standardStats?.first(where: {
                $0.label == label
            })?.value else { return nil }
            let components = raw.split(separator: "/", maxSplits: 1)
            guard components.count == 2,
                  let first = DashboardViewModel.rawNumeric(String(components[0])),
                  let second = DashboardViewModel.rawNumeric(String(components[1]))
            else { return nil }
            return (first, second)
        }
        guard !pairs.isEmpty else { return "-" }
        let first = pairs.reduce(0) { $0 + $1.0 }
        let second = pairs.reduce(0) { $0 + $1.1 }
        return format(first, label: label) + "/" + format(second, label: label)
    }

    private func format(_ value: Double?, label: String) -> String {
        guard let value else { return "-" }
        if label == "Sacks", value.rounded() != value {
            return String(format: "%.1f", value)
        }
        return Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}

/// Public mirror of RootTabView's private GridironNavBar so destinations pushed
/// from this file keep the same midnight bar treatment.
struct GridironNavBarPublic: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(GridironPalette.midnight, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CompareView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
