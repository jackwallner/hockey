import SwiftUI

/// Thin wrapper over the shared `FavoritesStore` so the Teams tab and the
/// player profile can't drift apart on what "favorite" means. It used to own
/// its own copy of the same UserDefaults key.
@MainActor
struct TeamsViewModel {
    private let store = FavoritesStore.shared

    var favoriteTeam: String? { store.team }

    func isFavorite(_ team: String) -> Bool { store.isFavorite(team: team) }

    func setFavorite(_ team: String) { store.setFavorite(team: team) }

    func removeFavorite() { store.setFavorite(team: nil) }
}

struct TeamsView: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    @Binding var path: NavigationPath
    private let teamsViewModel = TeamsViewModel()
    @State private var favorites = FavoritesStore.shared
    @State private var searchText = ""
    @State private var showingTrial = false
    // Auto-enter the favorite team once per launch; popping back must not
    // re-push it, or the user can never reach the list.
    @State private var didAutoEnterFavorite = false
    @AppStorage("teams.view") private var mode: TeamsMode = .clubs

    enum TeamsMode: String, Hashable {
        case clubs
        case standings
        case power
    }

    /// Standings and power ratings are built from this season's games, so they
    /// only exist on the live season.
    private var showsLeagueTables: Bool {
        viewModel.selectedSeason == viewModel.freeSeason && viewModel.selectedPhase == .regular
    }

    private static let allTeams: [String] = nflTeamAbbreviations

    /// Eight divisions of four, in standings order. Grouping this way is what
    /// lets all thirty-two clubs fit one screen without scrolling, and it's how
    /// people already hold the league in their heads, so it reads faster than an
    /// alphabetical wall even before the space saving. Four across also sits
    /// more comfortably than baseball's five.
    static let divisions: [(name: String, teams: [String])] = [
        ("AFC East",    ["BUF", "MIA", "NE", "NYJ"]),
        ("AFC North",   ["BAL", "CIN", "CLE", "PIT"]),
        ("AFC South",   ["HOU", "IND", "JAX", "TEN"]),
        ("AFC West",    ["DEN", "KC", "LV", "LAC"]),
        ("NFC East",    ["DAL", "NYG", "PHI", "WAS"]),
        ("NFC North",   ["CHI", "DET", "GB", "MIN"]),
        ("NFC South",   ["ATL", "CAR", "NO", "TB"]),
        ("NFC West",    ["ARI", "LA", "SF", "SEA"]),
    ]

    private var filteredTeams: [String] {
        // The division grid always draws all 32 clubs, so search and the count
        // cover them too. Filtering to teams with published rows meant that in
        // Week 1, with four teams played, "Chiefs" found nothing and the header
        // read "4 teams" above a grid of 32.
        guard !viewModel.teamsWithData.isEmpty else { return [] }
        let teams = searchText.isEmpty ? Self.allTeams : Self.allTeams.filter {
            teamFullName($0).localizedCaseInsensitiveContains(searchText) ||
            $0.localizedCaseInsensitiveContains(searchText)
        }
        // Plain alphabetical by full team name - the old score-based ordering was
        // confusing and the score itself was a mislabeled percentile. The
        // favorite is lifted into its own pinned section above the grid.
        return teams.sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

    /// The favorite, shown only when not actively searching so search results
    /// stay a single uninterrupted list.
    private var pinnedFavorite: String? {
        guard searchText.isEmpty, let fav = teamsViewModel.favoriteTeam else { return nil }
        return fav
    }

    /// All-teams grid with the pinned favorite removed so it isn't listed twice.
    private var gridTeams: [String] {
        guard let fav = pinnedFavorite else { return filteredTeams }
        return filteredTeams.filter { $0 != fav }
    }

    private var isInitiallyLoading: Bool {
        viewModel.isLoading && viewModel.teamsWithData.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.selectedSeason == viewModel.freeSeason && viewModel.selectedPhase == .regular {
                    DataFreshnessView(viewModel: viewModel)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                if StatScoutSeason.isAllTime(viewModel.selectedSeason) {
                    allTimeUnavailableState
                } else if isInitiallyLoading {
                    teamsLoadingState
                } else {
                    if showsLeagueTables {
                        GridironSegmented(
                            segments: [
                                .init(value: TeamsMode.clubs, label: "Clubs"),
                                .init(value: TeamsMode.standings, label: "Standings"),
                                .init(value: TeamsMode.power, label: "Power"),
                            ],
                            selection: $mode
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    switch showsLeagueTables ? mode : .clubs {
                    case .clubs:
                        allTeamsSection
                    case .standings:
                        StandingsView(viewModel: viewModel, divisions: Self.divisions)
                    case .power:
                        PowerRankingsView(viewModel: viewModel)
                    }
                }
                // Scroll-under spacer so the last grid row isn't trapped behind
                // the floating tab bar - matches the Dashboard pattern.
                Color.clear.frame(height: 88)
            }
            .padding(.top, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GridironPalette.canvas.ignoresSafeArea())
        // Same header as Stats and Trends, from the one shared modifier, so the
        // season you are reading never moves when you change tabs.
        .modifier(
            SeasonPhaseNavBar(
                title: "Teams",
                // No All Time here: a career row carries the player's last team,
                // so a franchise's "all time" list would credit it with yards
                // earned elsewhere. See `seasonsExcludingAllTime`.
                seasons: viewModel.seasonsExcludingAllTime,
                selectedSeason: viewModel.selectedSeason,
                selectedPhase: viewModel.selectedPhase,
                isSeasonLocked: { viewModel.isSeasonLocked($0) },
                onSelectSeason: { season in
                    if viewModel.isSeasonLocked(season) {
                        showingTrial = true
                    } else {
                        viewModel.selectSeason(season)
                    }
                },
                onSelectPhase: { viewModel.selectedPhase = $0 }
            )
        )
        .refreshable {
            await viewModel.load()
        }
        .onAppear(perform: autoEnterFavoriteIfNeeded)
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .teamView)
        }
    }

    /// On first Teams visit, drop the user straight into their favorite team
    /// (the back button returns to the alphabetical list). Guarded so popping
    /// back or revisiting the tab doesn't trap them by re-pushing.
    private func autoEnterFavoriteIfNeeded() {
        guard !didAutoEnterFavorite,
              // A career selection has no franchise view to push into; the
              // explanatory state stays on screen instead.
              !StatScoutSeason.isAllTime(viewModel.selectedSeason),
              let favorite = teamsViewModel.favoriteTeam,
              path.isEmpty else { return }
        didAutoEnterFavorite = true
        path.append(TeamDestination(abbr: favorite))
    }

    /// The season is chosen once and shared across tabs, so picking All Time on
    /// Stats and then opening Teams lands here. Rather than silently reinterpret
    /// the selection (a franchise list built from career rows would credit each
    /// team with yards its players earned elsewhere) or silently change it back,
    /// this says what it can't do and offers the one tap that fixes it.
    private var allTimeUnavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(GridironPalette.inkTertiary)
            Text("Teams needs a single season")
                .font(GridironType.cardTitle)
                .foregroundStyle(GridironPalette.ink)
            Text("Career totals follow the player, not the club: a career line carries whichever team he finished with, so an all-time roster would credit a franchise with yards earned somewhere else. Pick a season to see its teams.")
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.selectedSeason = latestUnlockedSeason
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("Show " + SeasonLabel.text(latestUnlockedSeason))
                    .font(GridironType.smallBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(GridironPalette.turf)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }

    /// Newest season this user can actually open, so a free user isn't sent to a
    /// paywalled year by a button labelled as the fix.
    private var latestUnlockedSeason: Int {
        viewModel.seasonsExcludingAllTime.first { !viewModel.isSeasonLocked($0) }
            ?? viewModel.freeSeason
    }

    private var teamsLoadingState: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(GridironPalette.surfaceAlt)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GridironPalette.surfaceAlt)
                            .frame(width: 140, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GridironPalette.surfaceAlt)
                            .frame(width: 40, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
            }
        }
        .padding(.horizontal, 12)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .redacted(reason: .placeholder)
    }

    /// Logo grid replaces the old single-column list of rows. Each tile is a
    /// big colored disk with the abbreviation + full name, a corner star for
    /// favorites, and a long-press toggle so the row stays one-tap-to-navigate.
    private var allTeamsSection: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            if let fav = pinnedFavorite {
                HStack {
                    Text("FAVORITE TEAM")
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                FavoriteTeamCard(
                    abbr: fav,
                    destination: TeamDestination(abbr: fav),
                    onRemove: {
                        teamsViewModel.removeFavorite()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }

            HStack {
                Text("ALL TEAMS")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkSecondary)
                Spacer()
                if searchText.isEmpty {
                    Text("\(filteredTeams.count) teams")
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                } else {
                    Button("Clear") { searchText = "" }
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if filteredTeams.isEmpty {
                let noDataForSeason = searchText.isEmpty && viewModel.teamsWithData.isEmpty
                ContentUnavailableView {
                    Label(noDataForSeason ? "No teams available" : "No teams found", systemImage: "magnifyingglass")
                } description: {
                    Text(noDataForSeason
                         // Names the control, not a tab. There is no "Leaders"
                         // tab (it is "Stats"), and the fix has not lived on
                         // another screen since the season moved into the nav
                         // bar - it is the pill at the top of this one.
                         ? "No teams have player data for the \(SeasonLabel.text(viewModel.selectedSeason)) season. Pick another season from the pill at the top of the screen."
                         : "Try a different search term.")
                }
                .padding(.vertical, 48)
            } else if searchText.isEmpty {
                divisionGrid
            } else {
                // A search result has no meaningful division shape, so it falls
                // back to a flat run of whatever matched.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(gridTeams, id: \.self) { abbr in
                        teamDot(abbr)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    /// Eight labelled rows of four. Sized so the whole league sits on one
    /// screen.
    private var divisionGrid: some View {
        VStack(spacing: 10) {
            ForEach(Self.divisions, id: \.name) { division in
                VStack(spacing: 6) {
                    HStack {
                        Text(division.name.uppercased())
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.inkTertiary)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        ForEach(division.teams, id: \.self) { abbr in
                            teamDot(abbr)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// One club: the colour disk with its abbreviation, a favorite star when
    /// set, and a long-press to toggle it. No full team name, at four across
    /// there isn't room, and the helmet colours plus abbreviation are how people
    /// recognise a club anyway.
    private func teamDot(_ abbr: String) -> some View {
        NavigationLink(value: TeamDestination(abbr: abbr)) {
            // The disk already carries the abbreviation, so no caption beneath,
            // it printed the same letters twice and ate the vertical room the
            // eight division rows need.
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    TeamAbbrDisk(abbr: abbr)
                    if teamsViewModel.isFavorite(abbr) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.yellow)
                            .padding(2)
                            .background(GridironPalette.surface, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }
                if let status = weekStatus(abbr) {
                    Text(status.text)
                        .font(GridironType.micro)
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                if teamsViewModel.isFavorite(abbr) {
                    teamsViewModel.removeFavorite()
                } else {
                    teamsViewModel.setFavorite(abbr)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(teamsViewModel.isFavorite(abbr) ? "Remove Favorite" : "Set as Favorite",
                      systemImage: teamsViewModel.isFavorite(abbr) ? "star.slash" : "star.fill")
            }
        }
        .accessibilityLabel([teamFullName(abbr), weekStatus(abbr)?.spoken].compactMap { $0 }.joined(separator: ", "))
    }

    /// The club's record under each disk, or "Live" while it is playing. It
    /// used to be this week's kickoff day, which from Tuesday to Saturday put
    /// "Sun" under 28 of the 32 clubs and said nothing about any of them.
    private func weekStatus(_ abbr: String) -> (text: String, spoken: String, color: Color)? {
        guard viewModel.selectedSeason == viewModel.freeSeason,
              viewModel.selectedPhase == .regular else { return nil }
        if let game = viewModel.currentGame(forTeam: abbr),
           [.inProgress, .awaitingScore].contains(game.status()) {
            return ("Live", "playing \(game.matchupLabel(for: abbr))", GridironPalette.performanceLow)
        }
        if let record = viewModel.record(forTeam: abbr) {
            return (record, "record \(record)", GridironPalette.inkSecondary)
        }
        return legacyWeekStatus(abbr)
    }

    /// Before a club's first final: its first kickoff day, or its bye.
    private func legacyWeekStatus(_ abbr: String) -> (text: String, spoken: String, color: Color)? {
        guard let week = viewModel.currentGameWeek else { return nil }
        guard let game = viewModel.currentGame(forTeam: abbr) else {
            return week.phase == .regular ? ("Bye", "bye week", GridironPalette.inkTertiary) : nil
        }
        switch game.status() {
        case .final:
            let line = game.resultLine(for: abbr) ?? "Final"
            let color = game.result(for: abbr) == "L" ? GridironPalette.performanceLow : GridironPalette.performanceHigh
            return (line, "\(line) \(game.matchupLabel(for: abbr))", color)
        case .inProgress, .awaitingScore:
            return ("Live", "playing \(game.matchupLabel(for: abbr))", GridironPalette.performanceLow)
        case .upcoming:
            return (
                game.kickoff?.formatted(.dateTime.weekday(.abbreviated)) ?? "TBD",
                "\(game.matchupLabel(for: abbr)), \(game.dayLabel)",
                GridironPalette.inkSecondary
            )
        }
    }
}

/// Team colour disk with the abbreviation centered, the compact unit the
/// division grid is built from.
private struct TeamAbbrDisk: View {
    let abbr: String

    var body: some View {
        ZStack {
            Circle().fill(NFLTeamColor.color(abbr))
            Text(displayTeamAbbr(abbr))
                .font(GridironType.smallBold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
        .frame(height: 48)
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Favorite Team Card

/// Full-width "hero" row for the pinned favorite team. Reads as a featured item
/// distinct from the grid below - tap anywhere to open the team, tap the star to
/// unpin. This is what makes Favorite do something visible: your team is always
/// one tap away at the top of the list.
struct FavoriteTeamCard: View {
    let abbr: String
    let destination: TeamDestination
    var onRemove: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: destination) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(NFLTeamColor.color(abbr))
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                        Text(abbr)
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR TEAM")
                            .font(GridironType.micro)
                            .foregroundStyle(GridironPalette.turf)
                        Text(teamFullName(abbr))
                            .font(GridironType.bodyBold)
                            .foregroundStyle(GridironPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .padding(.trailing, 36)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(GridironPalette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                        .stroke(GridironPalette.turf, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            Button {
                onRemove?()
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .padding(8)
                    .background(Circle().fill(GridironPalette.surface))
                    .overlay(Circle().stroke(GridironPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove favorite")
            .padding(10)
        }
    }
}

// MARK: - Team Row

struct TeamRowContent: View {
    let abbr: String
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(NFLTeamColor.color(abbr))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(abbr)
                        .font(GridironType.smallBold)
                        .foregroundStyle(.white)
                )
                .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(teamFullName(abbr))
                    .font(GridironType.bodyBold)
                    .foregroundStyle(GridironPalette.ink)
                    .lineLimit(1)

                Text(abbr)
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GridironPalette.inkTertiary)
        }
        .padding(.leading, 12)
        .frame(height: 56)
        .contentShape(Rectangle())
        .background(isFavorite ? GridironPalette.surfaceAlt : GridironPalette.surface)
    }
}

// MARK: - Legacy Team Tile (for reference/previews)

struct TeamTile: View {
    let abbr: String
    var isFavorite: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(NFLTeamColor.color(abbr))
                    .frame(width: 44, height: 44)
                Text(abbr)
                    .font(GridironType.smallBold)
                    .foregroundStyle(.white)

                if isFavorite {
                    // Star badge
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                                .shadow(radius: 1)
                                .offset(x: 4, y: -4)
                        }
                        Spacer()
                    }
                    .frame(width: 44, height: 44)
                }
            }

            Text(teamFullName(abbr))
                .font(GridironType.smallBold)
                .foregroundStyle(isFavorite ? GridironPalette.turf : GridironPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(isFavorite ? GridironPalette.surfaceAlt : GridironPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(isFavorite ? GridironPalette.turf : GridironPalette.hairline, lineWidth: isFavorite ? 2 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TeamsView(viewModel: DashboardViewModel(), path: .constant(NavigationPath()))
            .environmentObject(StoreService.shared)
    }
}
#endif
