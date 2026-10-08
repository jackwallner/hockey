import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let provider: StatcastProviding
    private let cache: PlayerCaching?

    var players: [Player] = []
    var playerHistories: [Int: [Player]] = [:]
    var searchText = ""
    var selectedConference: LeagueConference = .all
    var selectedPosition: PlayerPositionGroup = .forward {
        didSet {
            guard oldValue != selectedPosition else { return }
            userSortMetric = nil
            applyDefaultSortDirection()
        }
    }
    // Compatibility bridge for callers that still speak in wire-format categories.
    var selectedCategory: MetricCategory? {
        get { selectedPosition.primaryCategory }
        set {
            switch newValue {
            case .scoring, .shotQuality: selectedPosition = .forward
            case .playDriving: selectedPosition = .defense
            case .goaltending: selectedPosition = .goalie
            case nil: break
            }
        }
    }

    private var userSortMetric: String?
    var sortDescending = true
    var selectedSeason: Int = StatScoutSeason.free
    var selectedPhase: SeasonPhase = .regular

    var sortLabel: String { currentSortMetric ?? "Top Metric" }

    var currentSortMetric: String? {
        if let userSortMetric, availableSortMetrics.contains(userSortMetric) {
            return userSortMetric
        }
        return determineSortMetricLabel()
    }

    var availableSortMetrics: [String] {
        var seen = Set<String>()
        return HockeyMetricRegistry.sorted(eligibleMetrics)
            .filter { seen.insert($0.label).inserted }
            .map(\.label)
    }

    var availableAdvancedSortMetrics: [String] {
        availableSortMetrics.filter { label in
            eligibleMetrics.contains { metric in
                metric.label == label
                    && HockeyMetricRegistry.definition(
                        for: metric.label,
                        category: metric.category
                    )?.kind == .advanced
            }
        }
    }

    func setUserSortMetric(_ label: String?) {
        userSortMetric = label
        applyDefaultSortDirection()
    }

    /// Call when the user explicitly flips direction (header tap / menu item)
    /// so the auto-default doesn't stomp their preference until they change
    /// the active metric or category.
    func toggleSortDirection() {
        sortDescending.toggle()
    }

    /// Reset direction to "best first" for the active metric. Triggered by
    /// category changes and by picking a new sort metric - but only when the
    /// user hasn't manually pinned a direction in this session.
    private func applyDefaultSortDirection() {
        guard let label = currentSortMetric,
              let metric = eligibleMetrics.first(where: { $0.label == label }) else {
            sortDescending = true
            return
        }
        sortDescending = HockeyMetricRegistry.definition(for: label, category: metric.category)?.higherIsBetter ?? true
    }
    // Mirrors StoreService.isPro. Set by the view layer so season gating and
    // selectedSeason clamping stay consistent without the VM depending on the store.
    var isPro: Bool = false

    /// The season a free user gets: the live season, whatever has loaded.
    /// See `StatScoutSeason.free`.
    var freeSeason: Int { StatScoutSeason.free }

    func isSeasonLocked(_ season: Int) -> Bool {
        !isPro && season != freeSeason
    }

    /// The season Recent form opens on: the live one.
    var recentFormSeason: Int { freeSeason }

    /// The seasons Recent form is offered for: the live one and the one before it.
    ///
    /// Recent is a rolling last-N-games window read off `player_recent_form`,
    /// and that rollup is not kept for all time: a "last 3 games" board for 2017
    /// is a historical curiosity nobody opened, and the game logs behind it were
    /// the single biggest thing in the database, so everything older was purged.
    /// Last season survives the cut deliberately. A season does not stop being
    /// worth a form board the moment the next one kicks off, and pinning this to
    /// the live season alone left a hole every September: Trends would go blank
    /// for the year you were actually still reading about.
    ///
    /// Newest first, so a menu built from this needs no further sorting. Floored
    /// at `earliestRecentForm`, the oldest season the rollup table still holds -
    /// without that, "the one before" resolves to a year that was purged and the
    /// menu offers a board that can only come back empty.
    var recentFormSeasons: [Int] {
        [recentFormSeason, recentFormSeason - 1]
            .filter { $0 >= StatScoutSeason.earliestRecentForm }
    }

    /// Whether Recent/Both controls should appear for this season at all.
    /// False hides the control rather than locking it: it is not a Pro upsell,
    /// the data does not exist.
    func supportsRecentForm(_ season: Int) -> Bool { recentFormSeasons.contains(season) }

    /// Switch season, and fetch what that season needs.
    ///
    /// Season history is loaded lazily - the launch path only fetches the live
    /// season, because decoding thirty-three thousand historical rows is the
    /// slowest thing the app does and most sessions never leave the current
    /// year. Nothing was triggering that load from the nav bar, though, so
    /// picking any past season (and All since 2000 most visibly, since it is the
    /// first row of the menu) dropped you on an empty board with no spinner and
    /// no explanation. Whether it recovered came down to whether you had
    /// happened to open the Compare tab earlier in the session, which is the
    /// only place that asked for history.
    ///
    /// Setting the season first and loading second is deliberate: the header
    /// updates on the tap, so the screen acknowledges you immediately and the
    /// board fills in behind it.
    func selectSeason(_ season: Int) {
        selectedSeason = season
        guard !hasLoadedHistorical, season != freeSeason else { return }
        seasonLoadTask = Task { await loadHistoricalIfNeeded() }
    }

    /// Held only so tests can await the load the tap kicked off. Nothing in the
    /// app reads it: the board is driven by `isHistoricalLoading` and the
    /// resulting data, not by the task.
    private(set) var seasonLoadTask: Task<Void, Never>?

    /// Push Pro state in from the view and re-clamp the selected season so a free
    /// user can never land on (and silently render) a locked past season.
    func applyProState(_ pro: Bool) {
        isPro = pro
        clampSelectedSeason()
    }

    private func clampSelectedSeason() {
        guard isSeasonLocked(selectedSeason) else { return }
        let target = availableSeasons.first(where: { !isSeasonLocked($0) }) ?? freeSeason
        if selectedSeason != target { selectedSeason = target }
    }

    // Start true so the very first frame shows a spinner, not a "No data for 2026" empty state
    // before saved players or the network feed resolves.
    var isLoading = true
    var isHistoricalLoading = false
    var hasLoadedHistorical = false
    var loadingMessage = "Starting up…"
    var loadingProgress = 0.05
    var errorMessage: String?
    var lastFetchFailed = false
    /// The last failure was the network, not the data.
    ///
    /// Drives the offline framing on the empty board: "Data Error" beside a
    /// warning triangle is a claim about the stats, and on a first run with no
    /// signal the stats are fine and the phone is not.
    var lastFailureWasConnectivity = false
    private var hasStartedLoading = false
    private var loadTask: Task<Void, Never>?
    private var freshnessCheckTask: Task<FreshnessCheckResult, Never>?
    private var lastForegroundCheckAt: Date?
    private var lastStatusCheckAt: Date?

    /// The latest status returned by the publisher. This is persisted as a
    /// small metadata cache so offline users can still see an honest boundary.
    var dataFreshness: DataFreshness?
    /// Revision actually represented by the player and recent-form data on
    /// screen. It can lag the server revision while a new version is pending.
    private(set) var displayedDataRevision: String?
    private(set) var localLastCheckedAt: Date?

    /// The revision cards should use in their task identity. It changes only
    /// after a validated current dataset has been accepted, so a server probe
    /// cannot make a profile or team card discard good data prematurely.
    var freshnessRevision: String? { displayedDataRevision }

    var freshnessForDisplay: DataFreshness? {
        guard let remote = dataFreshness else { return nil }
        let dataFreshness = remote.replacing(coverage: .some(dataCoverage))
        if lastFetchFailed {
            return dataFreshness.replacing(
                status: .failed,
                message: .some(errorMessage ?? "Showing saved data while the latest refresh is retried."),
                isCached: .some(true)
            )
        }
        guard dataFreshness.status == .ready,
              let serverRevision = dataFreshness.revision,
              let displayedDataRevision,
              serverRevision != displayedDataRevision else {
            return dataFreshness
        }
        return dataFreshness.replacing(
            status: .stale,
            message: .some("New game data is ready, but this screen is still showing the last complete revision."),
            isCached: .some(true)
        )
    }

    var freshnessStatus: DataFreshnessStatus {
        if lastFetchFailed { return .failed }
        return freshnessForDisplay?.status ?? (players.isEmpty && isLoading ? .checking : .ready)
    }

    var lastCheckedAt: Date? { localLastCheckedAt ?? dataFreshness?.checkedAt }

    var isRefreshing: Bool {
        loadTask != nil || freshnessCheckTask != nil
    }

    enum FreshnessCheckResult: Equatable, Sendable {
        case unavailable
        case unchanged
        case updated
        case pending
        case partial
        case stale
        case failed
        case throttled
    }

    var isReady: Bool { !players.isEmpty }

    private var _teamScores: [String: Double] = [:]
    private var _teamsWithData: [String] = []
    private var _teamCacheSeason: Int?
    private var _teamCachePhase: SeasonPhase?

    var teamScores: [String: Double] {
        if _teamCacheSeason != selectedSeason || _teamCachePhase != selectedPhase {
            recomputeTeamCache()
        }
        return _teamScores
    }

    var teamsWithData: [String] {
        if _teamCacheSeason != selectedSeason || _teamCachePhase != selectedPhase {
            recomputeTeamCache()
        }
        return _teamsWithData
    }

    var teamCounts: [String: Int] {
        Dictionary(grouping: seasonPlayers) { normalizedTeamAbbreviation($0.team) }
            .mapValues(\.count)
    }

    var lastUpdated: Date? {
        players.map(\.updatedAt).max()
    }

    /// The last game the data actually covers, as opposed to when the rows were
    /// written. See `DataCoverage`.
    var dataCoverage: DataCoverage?

    var freshnessText: String? {
        guard let lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    /// Fetch per-game logs for a single player. Powers the Recent Form card.
    /// The VM is a passthrough so the card stays UI-only and we do not
    /// have to thread the provider through every PlayerProfileView caller.
    ///
    /// The phase is a parameter rather than read off `selectedPhase` because a
    /// player page carries its own: opening a 2025 playoff profile from a
    /// regular-season board has to fetch that player's playoff games, not the
    /// tab's.
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        try await provider.fetchGameLogs(
            playerId: playerId,
            season: season,
            seasonPhase: seasonPhase
        )
    }

    /// Team-scoped game logs since `sinceDate`. The TeamRankingsCard caps at 30
    /// days so we don't pull the whole season for an aggregate we only ever
    /// slice into 7/15/30 day windows.
    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog] {
        try await provider.fetchTeamGameLogs(
            team: team,
            season: season,
            seasonPhase: seasonPhase,
            sinceDate: sinceDate
        )
    }

    init(provider: StatcastProviding, cache: PlayerCaching? = nil) {
        self.provider = provider
        self.cache = cache
        if cache != nil, let cachedFreshness = DataFreshnessCache.load() {
            self.dataFreshness = cachedFreshness.replacing(isCached: .some(true))
            self.dataCoverage = cachedFreshness.coverage
            self.displayedDataRevision = DataFreshnessCache.loadDisplayedRevision()
            self.localLastCheckedAt = cachedFreshness.checkedAt
        }
    }

    #if DEBUG
    convenience init() {
        self.init(provider: PreviewStatcastAPI())
    }
    #endif

    // Keep the full supported range visible even before historical data loads.
    // Free users can discover older seasons in the menu and see that they are
    // part of StatScout+, rather than seeing a misleading single-year picker.
    var availableSeasons: [Int] {
        // Runs through the live season, which is always offered (and is the
        // default) from the day the calendar names it.
        var seasons = Set(StatScoutSeason.earliest...max(freeSeason, StatScoutSeason.earliest))
        seasons.formUnion(playerHistories.values.flatMap { $0 }.compactMap(\.season))
        // The career rollup sits under season 0, so a plain descending sort would
        // bury "All Time" underneath 2000. It belongs at the top of the menu, as
        // the widest possible frame rather than the narrowest.
        let years = seasons.subtracting([StatScoutSeason.allTime]).sorted(by: >)
        return [StatScoutSeason.allTime] + years
    }

    /// Seasons offered where a career rollup makes no sense.
    ///
    /// Two screens are excluded, for different reasons.
    ///
    /// **Trends** ranks the last 3/5/8 *weeks* against the span before them,
    /// which is a question about one season in progress. There is no such thing
    /// as the last five weeks of all time, and the rolling-window table has no
    /// rows under the sentinel, so offering it there would only ever produce an
    /// empty board.
    ///
    /// **Teams** is the subtler one. A career row carries whichever team the
    /// player *last* played for, because that is what a career aggregate can
    /// know - the rollup has no per-franchise split. So "Kansas City, All Time"
    /// would list players who happened to finish there, crediting them with
    /// production earned elsewhere, and would file Joe Montana under the Chiefs
    /// rather than the 49ers. That is not franchise all-time leaders; it just
    /// looks enough like it to be believed. Until the pipeline stores a
    /// per-team career split, not offering it is the honest answer.
    var seasonsExcludingAllTime: [Int] {
        availableSeasons.filter { !StatScoutSeason.isAllTime($0) }
    }

    // Players filtered by selected season - pull from histories to get all years.
    // Returns empty when the selected season has no data so callers render an empty state
    // instead of falling back to a stale "latest snapshot" set.
    var seasonPlayers: [Player] {
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter {
            $0.season == selectedSeason && $0.seasonPhase == selectedPhase
        }
        var seenIds = Set<Int>()
        return allSeasonPlayers.filter { seenIds.insert($0.playerId).inserted }
    }

    // MARK: - Games

    /// The live season's schedule and posted finals, from `public.games`.
    private(set) var games: [Game] = []
    /// Games whose player stats are published, so a final can say whether its
    /// box score is in yet.
    private(set) var gameIdsWithStats: Set<String> = []
    private(set) var isGamesLoading = false
    private(set) var gamesError: String?
    private(set) var gamesLoadedAt: Date?
    private var gamesTask: Task<Void, Never>?

    var currentGameDay: GameDay? { GameDay.current(in: games) }

    // MARK: - Enrichment

    /// Bio, contract, snaps and injury for the live season, keyed by player.
    /// Optional context: empty until `player_profiles` answers, and every
    /// screen that reads it leaves the line out rather than waiting.
    private(set) var profiles: [Int: PlayerProfile] = [:] {
        didSet { contractValueCache = nil }
    }
    /// Power ratings for the live season, keyed by normalized team.
    private(set) var teamRatings: [String: TeamRating] = [:]
    /// Projected margins for unplayed games, keyed by game id.
    private(set) var projections: [String: GameProjection] = [:]

    func profile(for player: Player) -> PlayerProfile? {
        guard let profile = profiles[player.playerId], profile.season == player.season else { return nil }
        return profile
    }

    func teamRating(_ team: String) -> TeamRating? {
        teamRatings[normalizedTeamAbbreviation(team)]
    }

    func projection(for game: Game) -> GameProjection? {
        game.isFinal ? nil : projections[game.id]
    }

    private func loadProfiles() async {
        guard let loaded = try? await provider.fetchPlayerProfiles(season: freeSeason),
              !loaded.isEmpty else { return }
        profiles = Dictionary(loaded.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Division and league standings from posted finals, every club present.
    var standings: [String: StandingsRow] {
        StandingsRow.build(from: games, teams: leagueTeamAbbreviations)
    }

    /// The first regular-season week a club has not finished yet, which is the
    /// week its injury report is about.
    func upcomingWeek(forTeam team: String) -> Int? {
        games.filter { $0.seasonPhase == .regular && !$0.isFinal && $0.involves(team) }
            .map(\.week)
            .min()
    }

    /// The player's game status for his club's next game, or nil when he is
    /// not on the report or the report is about a game already played.
    func injuryReport(for player: Player) -> InjuryReport? {
        guard player.season == freeSeason, player.seasonPhase == .regular else { return nil }
        return InjuryReport.current(
            from: profile(for: player),
            upcomingWeek: upcomingWeek(forTeam: player.team)
        )
    }

    // MARK: - Contract value

    @ObservationIgnored private var contractValueCache: (key: String, values: [Int: ContractValue])?

    /// Production against pay for the selected season's offensive players.
    /// Only the live season has contracts: a deal signed in 2026 says nothing
    /// about what a player cost in 2019.
    var contractValues: [Int: ContractValue] {
        guard selectedSeason == freeSeason, selectedPhase == .regular, !profiles.isEmpty else { return [:] }
        let key = "\(selectedSeason)-\(displayedDataRevision ?? "none")-\(seasonPlayers.count)"
        if let cache = contractValueCache, cache.key == key { return cache.values }
        let values = ContractValue.compute(
            players: seasonPlayers,
            profiles: profiles,
            isQualified: { [unowned self] player in
                self.isPlayerQualified(player, in: player.positionGroup.primaryCategory)
            }
        )
        contractValueCache = (key, values)
        return values
    }

    func contractValue(for player: Player) -> ContractValue? {
        guard player.season == freeSeason, player.seasonPhase == .regular else { return nil }
        if player.season == selectedSeason, selectedPhase == .regular {
            return contractValues[player.playerId]
        }
        return nil
    }

    /// Players on the Value board: the selected position, qualified, with a
    /// contract, best value first (or worst, with the direction flipped).
    func contractValueBoard(descending: Bool) -> [(player: Player, value: ContractValue)] {
        let values = contractValues
        return seasonPlayers
            .filter { $0.positionGroup == selectedPosition && matchesSelectedConference($0) }
            .compactMap { player in values[player.playerId].map { (player, $0) } }
            .sorted {
                if $0.value.score != $1.value.score {
                    return descending ? $0.value.score > $1.value.score : $0.value.score < $1.value.score
                }
                return $0.player.name < $1.player.name
            }
    }

    /// Loads the schedule, at most once a minute unless forced. Failures keep
    /// whatever schedule is already on screen.
    func loadGames(force: Bool = false) async {
        if let gamesTask {
            await gamesTask.value
            return
        }
        if !force, let gamesLoadedAt, Date().timeIntervalSince(gamesLoadedAt) < 60 {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGamesLoad()
        }
        gamesTask = task
        await task.value
    }

    private func performGamesLoad() async {
        defer { gamesTask = nil }
        isGamesLoading = games.isEmpty
        let season = freeSeason
        do {
            async let schedule = provider.fetchGames(season: season)
            async let withStats = provider.fetchGameIdsWithStats(season: season)
            let (loadedGames, loadedIds) = try await (schedule, withStats)
            if !loadedGames.isEmpty || games.isEmpty {
                games = loadedGames
            }
            gameIdsWithStats = loadedIds
            gamesError = nil
            gamesLoadedAt = Date()
            // Ratings and projections ride along with the schedule they
            // describe. Optional: a failure keeps whatever was there.
            async let ratings = try? provider.fetchTeamRatings(season: season)
            async let projected = try? provider.fetchGameProjections(season: season)
            if let loadedRatings = await ratings, !loadedRatings.isEmpty {
                teamRatings = Dictionary(
                    loadedRatings.map { (normalizedTeamAbbreviation($0.team), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            if let loadedProjections = await projected {
                projections = Dictionary(
                    loadedProjections.map { ($0.gameId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        } catch {
            if !isTaskCancellation(error) {
                gamesError = "Couldn't load games. Check your connection and try again."
            }
        }
        isGamesLoading = false
    }

    func game(id: String) -> Game? {
        games.first { $0.id == id }
    }

    /// A team's game on the day the Games tab calls current, else its next
    /// game, else its last one.
    func currentGame(forTeam team: String) -> Game? {
        if let day = currentGameDay, let game = day.games(from: games).first(where: { $0.involves(team) }) {
            return game
        }
        let mine = games.filter { $0.involves(team) }.sorted { ($0.kickoff ?? $0.gameDate) < ($1.kickoff ?? $1.gameDate) }
        return mine.first { !$0.isFinal } ?? mine.last
    }

    /// Regular-season record from posted finals, "2-1" or "2-1-1". When
    /// `through` is given, only games kicked off up to and including it count.
    func record(forTeam team: String, through game: Game? = nil) -> String? {
        let cutoff = game?.kickoff ?? .distantFuture
        let finals = games.filter {
            $0.seasonPhase == .regular && $0.isFinal && $0.involves(team)
                && ($0.kickoff ?? $0.gameDate) <= cutoff
        }
        guard !finals.isEmpty else { return nil }
        let results = finals.compactMap { $0.result(for: team) }
        let wins = results.filter { $0 == "W" }.count
        let losses = results.filter { $0 == "L" }.count
        let ties = results.filter { $0 == "T" }.count
        return ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    /// Every game on a club's schedule this season, in kickoff order.
    func schedule(forTeam team: String) -> [Game] {
        games.filter { $0.involves(team) }
            .sorted { ($0.kickoff ?? $0.gameDate) < ($1.kickoff ?? $1.gameDate) }
    }

    func hasStats(_ game: Game) -> Bool {
        gameIdsWithStats.contains(game.id)
    }

    func fetchGameDetail(gameId: String) async throws -> GameDetail? {
        try await provider.fetchGameDetail(gameId: gameId)
    }

    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] {
        try await provider.fetchGameLogs(gameId: gameId)
    }

    /// The live-season player row for a game-log line, for names and links.
    func player(id: Int, season: Int, phase: SeasonPhase) -> Player? {
        (playerHistories[id] ?? []).first { $0.season == season && $0.seasonPhase == phase }
            ?? (playerHistories[id] ?? []).first { $0.season == season }
    }

    // MARK: - Recent form

    /// Rolling windows keyed by length, cached per season so flipping between
    /// 2 / 4 / 8 does not refetch what's already in hand.
    var recentFormByWindow: [Int: [Int: RecentForm]] = [:]
    var recentFormLoadingWindows: Set<Int> = []
    var recentFormError: String?
    private var recentFormContext: String?
    private var recentFormTasks: [Int: Task<Void, Never>] = [:]

    /// The window the Trends board and the trend arrows read from.
    ///
    /// Two weeks, so movement exists by the third week of October. A longer
    /// default left the paid board with nothing to rank through the opening
    /// month of every season, which is when the installs happen.
    var recentWindow: TrendWindow = .two

    /// True while a board is showing recent form rather than season totals.
    /// Pro-gated at the call site, free users get a blurred teaser.
    var showingRecent = false

    func recentForm(
        for playerId: Int,
        window: TrendWindow? = nil,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) -> RecentForm? {
        let targetSeason = season ?? selectedSeason
        let targetPhase = phase ?? selectedPhase
        return recentFormByWindow[(window ?? recentWindow).rawValue]?[playerId]
            .flatMap {
                $0.season == targetSeason && $0.seasonPhase == targetPhase ? $0 : nil
            }
    }

    func recentForm(
        for playerId: Int,
        window: RecentWindow,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) -> RecentForm? {
        let targetSeason = season ?? selectedSeason
        let targetPhase = phase ?? selectedPhase
        return recentFormByWindow[window.rawValue]?[playerId]
            .flatMap {
                $0.season == targetSeason && $0.seasonPhase == targetPhase ? $0 : nil
            }
    }

    var isRecentFormLoading: Bool {
        recentFormLoadingWindows.contains(recentWindow.rawValue)
    }

    /// The last game date covered by the loaded window, for honest labelling.
    func recentFormAsOf(
        window: TrendWindow,
        season: Int,
        phase: SeasonPhase
    ) -> Date? {
        recentFormRowsByWindow[window.rawValue]?
            .filter { $0.season == season && $0.seasonPhase == phase }
            .compactMap(\.asOf)
            .max()
    }

    /// The latest week any loaded row reaches, so a board can say "through
    /// Week 18" without every row carrying its own caption.
    func recentFormThroughWeek(
        window: TrendWindow,
        season: Int,
        phase: SeasonPhase
    ) -> Int? {
        recentFormRowsByWindow[window.rawValue]?
            .filter { $0.season == season && $0.seasonPhase == phase }
            .compactMap(\.endWeek)
            .max()
    }

    /// Every row for a window, keyed by side of the ball. The Trends board
    /// ranks within one position group, so it needs the rows a per-player
    /// dictionary throws away: a two-way player has one row per player_type.
    func recentFormRows(
        window: TrendWindow,
        playerType: String,
        season: Int,
        phase: SeasonPhase
    ) -> [RecentForm] {
        (recentFormRowsByWindow[window.rawValue] ?? [])
            .filter {
                $0.playerType == playerType
                    && $0.season == season
                    && $0.seasonPhase == phase
            }
    }

    private var recentFormRowsByWindow: [Int: [RecentForm]] = [:]

    /// Clears every league recent-form window after a new active data revision
    /// is adopted. In-flight requests are cancelled so an older response cannot
    /// repopulate a newer snapshot.
    func invalidateRecentFormCache() {
        for task in recentFormTasks.values { task.cancel() }
        recentFormTasks.removeAll()
        recentFormLoadingWindows.removeAll()
        recentFormByWindow.removeAll()
        recentFormRowsByWindow.removeAll()
        recentFormContext = nil
        recentFormError = nil
    }

    func reloadRecentForm(
        window: TrendWindow? = nil,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) async {
        let target = window ?? recentWindow
        recentFormTasks[target.rawValue]?.cancel()
        recentFormTasks.removeValue(forKey: target.rawValue)
        recentFormByWindow.removeValue(forKey: target.rawValue)
        recentFormRowsByWindow.removeValue(forKey: target.rawValue)
        recentFormError = nil
        await loadRecentFormIfNeeded(window: target, season: season, phase: phase)
    }

    func loadRecentFormIfNeeded(
        window: TrendWindow? = nil,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) async {
        let target = window ?? recentWindow
        let targetSeason = season ?? selectedSeason
        let targetPhase = phase ?? selectedPhase
        // Season changed under us, the cache describes a different year.
        let context = "\(targetSeason)-\(targetPhase.rawValue)"
        if recentFormContext != context {
            for task in recentFormTasks.values { task.cancel() }
            recentFormTasks.removeAll()
            recentFormLoadingWindows.removeAll()
            recentFormByWindow.removeAll()
            recentFormRowsByWindow.removeAll()
            recentFormContext = context
        }
        guard recentFormByWindow[target.rawValue] == nil else { return }

        if let inFlight = recentFormTasks[target.rawValue] {
            await inFlight.value
            return
        }

        recentFormLoadingWindows.insert(target.rawValue)
        recentFormError = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.recentFormLoadingWindows.remove(target.rawValue)
                self.recentFormTasks.removeValue(forKey: target.rawValue)
            }
            do {
                let rows = try await self.provider.fetchRecentForm(
                    season: targetSeason,
                    seasonPhase: targetPhase,
                    windowWeeks: target.rawValue
                )
                guard self.recentFormContext == context,
                      rows.allSatisfy({
                          $0.season == targetSeason && $0.seasonPhase == targetPhase
                      }) else { return }
                var byPlayer: [Int: RecentForm] = [:]
                for row in rows {
                    if let existing = byPlayer[row.playerId],
                       existing.plays >= row.plays { continue }
                    byPlayer[row.playerId] = row
                }
                self.recentFormByWindow[target.rawValue] = byPlayer
                self.recentFormRowsByWindow[target.rawValue] = rows
            } catch {
                if !isTaskCancellation(error) {
                    self.recentFormError = "Couldn't load recent form."
                }
            }
        }
        recentFormTasks[target.rawValue] = task
        await task.value
    }

    func loadRecentFormIfNeeded(
        window: RecentWindow,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) async {
        guard let trendWindow = TrendWindow(rawValue: window.rawValue) else { return }
        await loadRecentFormIfNeeded(
            window: trendWindow,
            season: season,
            phase: phase
        )
    }

    /// Unique players for an arbitrary season, not just the selected one.
    /// Drill-down leaderboards opened from a player profile need the season
    /// that profile is showing, which can differ from `selectedSeason`.
    func players(forSeason season: Int, phase: SeasonPhase? = nil) -> [Player] {
        let targetPhase = phase ?? selectedPhase
        let all = playerHistories.values.flatMap { $0 }.filter {
            $0.season == season && $0.seasonPhase == targetPhase
        }
        var seen = Set<Int>()
        return all.filter { seen.insert($0.playerId).inserted }
    }

    /// Clubs whose name or abbreviation matches the current search.
    ///
    /// Searching used to only ever narrow the list of players. Someone typing
    /// "chiefs" is usually after Kansas City, so the club itself is now a
    /// result: one tap to the team page, with the roster still filtered
    /// underneath if that's what they wanted.
    var searchedTeams: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return teamsWithData
            .filter {
                selectedConference.contains(team: $0)
                    && (
                        teamFullName($0).localizedCaseInsensitiveContains(query)
                            || $0.localizedCaseInsensitiveContains(query)
                    )
            }
            .sorted { teamFullName($0) < teamFullName($1) }
    }

    private var eligibleMetrics: [Metric] {
        seasonPlayers
            .filter { $0.positionGroup == selectedPosition }
            .flatMap(\.metrics)
            .filter { HockeyMetricRegistry.isSupported($0, by: selectedPosition) }
    }

    var filteredPlayers: [Player] {
        // Resolved once: it walks every metric in the season.
        let gateLabel = qualifierLevel == .qualified ? currentSortMetricLabelForGate : nil
        return seasonPlayers.filter { player in
            let matchesSearch = searchText.isEmpty
                || player.name.localizedCaseInsensitiveContains(searchText)
                || player.team.localizedCaseInsensitiveContains(searchText)
                || teamFullName(player.team).localizedCaseInsensitiveContains(searchText)
            let matchesPosition = player.positionGroup == selectedPosition
            let matchesConference = matchesSelectedConference(player)
            let matchingMetrics = player.metrics.filter {
                HockeyMetricRegistry.isSupported($0, by: selectedPosition)
            }
            let qualifies = isQualifiedForBoard(player, metrics: matchingMetrics, sortLabel: gateLabel)
            return matchesSearch
                && matchesPosition
                && matchesConference
                && !matchingMetrics.isEmpty
                && qualifies
        }
    }

    func matchesSelectedConference(_ player: Player) -> Bool {
        selectedConference.contains(team: player.team)
    }

    enum QualifierLevel: String, CaseIterable, Identifiable {
        case all = "All Players"
        case qualified = "Qualified"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .all: return "Small samples dimmed"
            case .qualified: return "Playing-time minimum"
            }
        }
    }

    /// All players by default, with small samples dimmed and sorted below
    /// qualified players. Users can choose Qualified in the View menu to hide
    /// the small samples.
    var qualifierLevel: QualifierLevel = DashboardViewModel.storedQualifierLevel {
        didSet { UserDefaults.standard.set(qualifierLevel.rawValue, forKey: Self.qualifierKey) }
    }

    private static let qualifierKey = "stats.qualifier"

    private static var storedQualifierLevel: QualifierLevel {
        UserDefaults.standard.string(forKey: qualifierKey).flatMap(QualifierLevel.init(rawValue:)) ?? .all
    }

    func isQualified(_ player: Player, for category: MetricCategory?) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            return isPlayerQualified(player, in: category)
        }
    }

    /// Whether a player clears the bar, whatever the filter says. Defenders
    /// with snap counts qualify on snap share; everyone else on the feed's own
    /// prorated flag.
    func isPlayerQualified(_ player: Player, in category: MetricCategory?) -> Bool {
        if let snapQualified = defensiveSnapQualification(player) { return snapQualified }
        return Self.hasQualifyingMetric(player, in: category)
    }

    /// Per metric: a receiver over the target bar for Catch% is not thereby
    /// qualified for a Separation board he has no Next Gen sample on.
    func isQualified(_ player: Player, metric: Metric) -> Bool {
        if let snapQualified = defensiveSnapQualification(player) { return snapQualified }
        return metric.qualified != false
    }

    /// A defender has to play a quarter of his club's defensive snaps.
    ///
    /// The feed's defensive bar is games played, which admits every
    /// special-teamer who stepped on the field. Nil when there is no snap line
    /// (a past season, or before the first snap-count publish), which falls
    /// back to the feed's flag.
    static let defensiveSnapShareMinimum = 0.25

    private func defensiveSnapQualification(_ player: Player) -> Bool? {
        guard player.isDefensivePlayer,
              let share = profile(for: player)?.defenseSnapShare else { return nil }
        return share >= Self.defensiveSnapShareMinimum
    }

    /// The board's gate: qualified for the metric it is ranked by, or for any
    /// of its metrics when it has no sort yet.
    private func isQualifiedForBoard(_ player: Player, metrics: [Metric], sortLabel: String?) -> Bool {
        guard qualifierLevel == .qualified else { return true }
        if let label = sortLabel,
           let metric = metrics.first(where: { $0.label == label }) {
            return isQualified(player, metric: metric)
        }
        return metrics.contains { isQualified(player, metric: $0) }
    }

    /// The sort label without re-entering `filteredPlayers` (which
    /// `currentSortMetric` reads through `eligibleMetrics`).
    private var currentSortMetricLabelForGate: String? {
        userSortMetric ?? determineSortMetricLabel()
    }

    /// The live season flags each metric; past seasons only ever shipped
    /// qualifying rows, so there a metric's presence is the signal.
    static func hasQualifyingMetric(_ player: Player, in category: MetricCategory?) -> Bool {
        player.metrics.contains {
            (category == nil || $0.category == category) && $0.qualified != false
        }
    }

    var leaderboard: [Player] {
        guard let label = currentSortMetric,
              let referenceMetric = eligibleMetrics.first(where: { $0.label == label }) else {
            return filteredPlayers.sorted { $0.name < $1.name }
        }
        let sorted = filteredPlayers.sorted(
            by: Self.metricComparator(
                label: label,
                category: referenceMetric.category,
                descending: sortDescending
            )
        )
        // Small samples go below the rest, in the same order, so the top of a
        // board is never a one-target receiver. Only reachable under "All
        // players"; the default filter already leaves them out.
        let isSmall: (Player) -> Bool = { [unowned self] player in
            guard let metric = player.metrics.first(where: {
                $0.label == label && $0.category == referenceMetric.category
            }) else { return false }
            return !self.isQualified(player, metric: metric)
        }
        return sorted.filter { !isSmall($0) } + sorted.filter(isSmall)
    }

    /// Board subtitle volume: "16 att", "23 tgt", "142 snaps".
    func volumeCaption(for player: Player, category: MetricCategory?) -> String? {
        let category = category ?? player.primaryCategory
        if category == .defense,
           let snaps = profile(for: player)?.defenseSnaps, snaps > 0 {
            return "\(snaps) snaps"
        }
        return player.volumeCaption(for: category)
    }

    /// Rank by the backend's direction-correct percentile, then use the raw
    /// number only to break a tied percentile bucket. Percentile-only metrics
    /// remain rankable instead of being swept below every printable value.
    static func metricComparator(
        label: String,
        category: MetricCategory,
        descending: Bool
    ) -> (Player, Player) -> Bool {
        let percentileDescending = descending != lowerIsBetter(
            label: label,
            category: category
        )
        return { first, second in
            let firstMetric = first.metrics.first {
                $0.label == label && $0.category == category
            }
            let secondMetric = second.metrics.first {
                $0.label == label && $0.category == category
            }

            switch (firstMetric, secondMetric) {
            case (nil, nil):
                return first.name < second.name
            case (nil, _):
                return false
            case (_, nil):
                return true
            default:
                break
            }

            guard let firstMetric, let secondMetric else { return false }
            if firstMetric.percentile != secondMetric.percentile {
                return percentileDescending
                    ? firstMetric.percentile > secondMetric.percentile
                    : firstMetric.percentile < secondMetric.percentile
            }
            if let firstValue = rawNumeric(firstMetric.value),
               let secondValue = rawNumeric(secondMetric.value),
               firstValue != secondValue {
                return descending
                    ? firstValue > secondValue
                    : firstValue < secondValue
            }
            return first.name < second.name
        }
    }

    /// Parse a leading numeric value from a metric's display string.
    /// Handles ".345", "8.2%", "98.5 mph", "28.5 ft/s", "25.3°", "-1.2".
    /// Forwards to the actor-free `metricNumericValue` in the model layer, which
    /// is the single implementation. Kept as a static here because a large number
    /// of call sites already spell it this way.
    static func rawNumeric(_ value: String) -> Double? {
        metricNumericValue(value)
    }

    static func lowerIsBetter(label: String, category: MetricCategory) -> Bool {
        guard let definition = HockeyMetricRegistry.definition(for: label, category: category) else { return false }
        return !definition.higherIsBetter
    }

    /// Default sort direction for a metric - descending (highest first) unless
    /// the metric reads better when lower. Used to keep "best player first" as
    /// the initial ordering even after switching to raw-value sorting.
    static func defaultSortDescending(label: String?, category: MetricCategory?) -> Bool {
        guard let label, let category else { return true }
        return !lowerIsBetter(label: label, category: category)
    }

    private func determineSortMetricLabel() -> String? {
        let preferred = selectedPosition.preferredAdvancedMetrics + selectedPosition.preferredTraditionalMetrics
        for label in preferred where eligibleMetrics.contains(where: { $0.label == label }) {
            return label
        }
        return availableSortMetrics.first
    }

    // Expose the current sort metric for row display. When no category is
    // active the leaderboard sorts by raw xwOBA; surface that label (with
    // nil category) so LeaderboardTableRow matches by label alone and shows
    // each player's xwOBA value instead of a percentile fallback.
    var currentSortMetricForDisplay: (label: String?, category: MetricCategory?) {
        guard let label = currentSortMetric,
              let metric = eligibleMetrics.first(where: { $0.label == label }) else {
            return (nil, nil)
        }
        return (label, metric.category)
    }

    func players(forTeam team: String) -> [Player] {
        // Sort the roster by overall percentile so the standout players surface
        // first regardless of position group.
        let normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { $0.overallPercentile > $1.overallPercentile }
    }

    func teamScore(_ abbr: String) -> Double {
        _teamScores[normalizedTeamAbbreviation(abbr)] ?? 0
    }

    /// Players who meet the active qualifier for at least one category they appear in.
    /// Used to filter the StatScout leaders and Box Score so unqualified samples don't pollute results.
    var qualifiedSeasonPlayers: [Player] {
        seasonPlayers.filter { player in
            let categories = Set(player.metrics.map(\.category))
            if categories.isEmpty { return isQualified(player, for: nil) }
            return categories.contains { isQualified(player, for: $0) }
        }
    }

    var allMetrics: [(label: String, category: MetricCategory, best: (player: Player, percentile: Int, actualValue: String)?, worst: (player: Player, percentile: Int, actualValue: String)?)] {
        var metricMap: [String: (category: MetricCategory, values: [(player: Player, percentile: Int, actualValue: String)])] = [:]
        for player in seasonPlayers where matchesSelectedConference(player) {
            for metric in player.metrics {
                guard isQualified(player, for: metric.category) else { continue }
                let compositeKey = "\(metric.label)|\(metric.category.rawValue)"
                if metricMap[compositeKey] == nil {
                    metricMap[compositeKey] = (category: metric.category, values: [])
                }
                metricMap[compositeKey]?.values.append((player: player, percentile: metric.percentile, actualValue: metric.value))
            }
        }
        return metricMap.compactMap { (key, data) -> MetricLeaderEntry? in
            let label = key.split(separator: "|").first.map(String.init) ?? key
            // Rank Best/Worst by Rink percentile, NOT by parsing the value
            // string. Roughly half of xISO / xOBP / Hard-Hit% (and 100% of
            // Arm Strength / Squared-Up%) ship a valid percentile but a blank
            // value; rawNumeric("") collapsed them all to 0, every player tied,
            // and the sort returned the same player (e.g. Ohtani) for both
            // ends with empty cells. Percentile is Rink's normalized
            // goodness - already direction-correct (it inverts for pitchers),
            // so highest = best, lowest = worst with no per-metric polarity
            // table needed.
            let byPercentile = data.values.sorted { $0.percentile < $1.percentile }
            guard let best = byPercentile.last else { return nil }
            let worst = byPercentile.first
            // Single qualifier (or every qualifier tied): the same player can't
            // be both Best and Worst - drop the duplicate so the row reads
            // "Best: X / Only qualifier" instead of "X is also the worst".
            let dedupedWorst = (worst?.player.id == best.player.id) ? nil : worst
            return (
                label: label,
                category: data.category,
                best: best,
                worst: dedupedWorst
            )
        }.sorted { $0.label < $1.label }
    }

    func loadIfNeeded() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        await load()
    }

    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    /// Checks the lightweight publisher status when the app returns to the
    /// foreground. A changed ready revision triggers the normal full load;
    /// unchanged or pending status leaves the current screen in place.
    func refreshOnForeground(now: Date = .now) async {
        let interval: TimeInterval = dataFreshness?.status == .pending ? 120 : 300
        if let lastForegroundCheckAt,
           now.timeIntervalSince(lastForegroundCheckAt) < interval {
            return
        }
        lastForegroundCheckAt = now
        if await checkForUpdates(force: false) == .updated {
            await load()
        } else {
            await loadGames()
        }
    }

    @discardableResult
    func checkForUpdates(force: Bool = false) async -> FreshnessCheckResult {
        if let freshnessCheckTask {
            return await freshnessCheckTask.value
        }
        if !force,
           let lastStatusCheckAt,
           Date().timeIntervalSince(lastStatusCheckAt) < (dataFreshness?.status == .pending ? 120 : 300) {
            return .throttled
        }

        let task = Task { @MainActor [weak self] in
            await self?.performFreshnessCheck() ?? .unavailable
        }
        freshnessCheckTask = task
        return await task.value
    }

    private func performFreshnessCheck() async -> FreshnessCheckResult {
        defer { freshnessCheckTask = nil }
        let now = Date()
        lastStatusCheckAt = now
        localLastCheckedAt = now

        do {
            guard let remote = try await provider.fetchDataFreshness(season: freeSeason) else {
                // The endpoint is optional while the backend rolls out. The
                // player load remains the source of truth in that case.
                return .unavailable
            }

            dataFreshness = remote.replacing(
                checkedAt: .some(remote.checkedAt ?? now),
                isCached: .some(false)
            )
            persistFreshness()

            switch remote.status {
            case .ready:
                if let revision = remote.revision,
                   revision != displayedDataRevision {
                    return .updated
                }
                return .unchanged
            case .pending: return .pending
            case .partial:
                if let revision = remote.revision, revision != displayedDataRevision { return .updated }
                return .partial
            case .stale: return .stale
            case .checking: return .unchanged
            case .offline, .failed: return .failed
            }
        } catch is CancellationError {
            return .failed
        } catch {
            if let existing = dataFreshness {
                dataFreshness = existing.replacing(
                    status: .offline,
                    checkedAt: .some(now),
                    message: .some("We couldn't check for new game data."),
                    isCached: .some(true)
                )
                persistFreshness()
            }
            return .failed
        }
    }

    private func performLoad() async {
        defer { loadTask = nil }
        hasStartedLoading = true
        isLoading = players.isEmpty
        loadingMessage = players.isEmpty ? "Loading saved players…" : "Refreshing player data…"
        loadingProgress = players.isEmpty ? 0.12 : 0.2

        let cached: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return (try? cache.loadCurrentPlayers()) ?? []
            }
            return (try? cache?.loadPlayers()) ?? []
        }.value

        if players.isEmpty, !cached.isEmpty {
            ingestPlayers(cached)
        }

        loadingMessage = "Checking for updates…"
        loadingProgress = 0.45
        isLoading = players.isEmpty
        errorMessage = nil
        lastFetchFailed = false
        lastFailureWasConnectivity = false

        let freshnessResult = await checkForUpdates(force: true)
        let revisionAtStart = dataFreshness?.revision

        var acceptedCurrent: [Player] = []
        var loadedCurrentData = false
        var playersToIngest: [Player] = []

        do {
            let current = try await provider.fetchCurrentPlayers()
            let fallbackPlayers = cached.isEmpty ? playerHistories.values.flatMap { $0 } : cached
            let hasCompleteFallback = PlayerSnapshotValidator.isCompleteCurrent(fallbackPlayers)
            let passesCompleteness = PlayerSnapshotValidator.isCompleteCurrent(current)
            acceptedCurrent = passesCompleteness || !hasCompleteFallback
                ? current
                : []
            // Before the status endpoint exists, a source regression can still
            // satisfy the live-season minimum with fewer teams. Retain the
            // complete cached set when a whole team disappears or a large part
            // of the known player set vanishes.
            if !acceptedCurrent.isEmpty,
               (freshnessResult == .unavailable || freshnessResult == .failed),
               hasUnsafeSnapshotRegression(current, against: fallbackPlayers) {
                acceptedCurrent = []
            }
            let allPlayers = acceptedCurrent.isEmpty ? fallbackPlayers : mergePlayers(replacing: acceptedCurrent)

            if allPlayers.isEmpty {
                // No current data (offseason / cold cache / offline). Fall back to
                // bundled historical so the app is usable instead of trapped on an
                // empty state; season gating still applies via isSeasonLocked.
                let historicalFallback: [Player] = await Task.detached { [cache] in
                    if let cache = cache as? TwoTierPlayerCache {
                        return cache.loadHistoricalPlayers()
                    }
                    return (try? cache?.loadPlayers()) ?? []
                }.value
                if !historicalFallback.isEmpty {
                    ingestPlayers(historicalFallback)
                } else {
                    errorMessage = "No players found."
                    lastFetchFailed = true
                }
            } else {
                loadingMessage = "Preparing leaderboard…"
                loadingProgress = 0.85
                playersToIngest = allPlayers
                if !acceptedCurrent.isEmpty {
                    loadedCurrentData = true
                } else if !current.isEmpty {
                    errorMessage = "Showing complete saved data while the live feed finishes updating."
                    lastFetchFailed = true
                }
            }

        } catch is DecodingError {
            errorMessage = "Data format changed - app may need an update."
            lastFetchFailed = true
        } catch _ as URLError {
            errorMessage = players.isEmpty ? "Can't reach data feed. Check your connection." : "Showing saved data. Pull to refresh when your connection improves."
            lastFetchFailed = true
            lastFailureWasConnectivity = true
        } catch {
            errorMessage = players.isEmpty ? "Something went wrong loading player data." : "Showing saved data. Pull to refresh to try again."
            lastFetchFailed = true
        }
        isLoading = false
        loadingProgress = 1

        // Off the critical path on purpose: a single row that only the About
        // sheet reads, fetched once the leaderboard is already on screen. A
        // failure here leaves the coverage line blank rather than failing the
        // load.
        let candidateCoverage = try? await provider.fetchDataCoverage(season: freeSeason)

        // The source can publish a new revision while snapshots are being
        // fetched. Bracket the candidate with a second status read so a new
        // status row cannot be paired with older player rows. Keep the prior
        // display and wait for the next check when the bracket moves.
        let endingResult = await checkForUpdates(force: true)
        let revisionAtEnd = dataFreshness?.revision
        // Only a revision that actually moved counts. A first status read that
        // failed (nil) and a second that succeeded is not drift; treating it as
        // drift discarded a good load and, on a cold start, left a blank app.
        let revisionDrifted = revisionAtStart != nil
            && revisionAtEnd != nil
            && revisionAtEnd != revisionAtStart
        if revisionDrifted {
            playersToIngest = []
            acceptedCurrent = []
            loadedCurrentData = false
            if let current = dataFreshness {
                dataFreshness = current.replacing(
                    status: .checking,
                    message: .some("A newer game revision arrived while this update was loading."),
                    isCached: .some(true)
                )
            }
        } else if !playersToIngest.isEmpty {
            ingestPlayers(playersToIngest)
        }
        if loadedCurrentData {
            dataCoverage = dataFreshness?.coverage ?? candidateCoverage
            try? cache?.savePlayers(acceptedCurrent)
            adoptLoadedRevision(
                players: acceptedCurrent,
                useServerRevision: canUseServerRevision(freshnessResult, endingResult)
            )
        } else if lastFetchFailed, let current = dataFreshness {
            dataFreshness = current.replacing(
                status: .failed,
                message: .some(errorMessage ?? "Showing saved data while the latest refresh is retried."),
                isCached: .some(true)
            )
        }
        persistFreshness()
        await loadProfiles()
        await loadGames(force: true)
    }

    /// Marks a successfully accepted snapshot as the revision shown by every
    /// dependent surface. Recent form is cleared only after this point, so a
    /// failed or partial response cannot erase useful in-memory results.
    private func adoptLoadedRevision(
        players loadedPlayers: [Player],
        useServerRevision: Bool
    ) {
        let candidate: String?
        if useServerRevision,
           (dataFreshness?.status == .ready || dataFreshness?.status == .partial),
           let revision = dataFreshness?.revision {
            candidate = revision
        } else {
            candidate = fallbackRevision(players: loadedPlayers, coverage: dataCoverage)
        }
        guard let candidate else { return }
        let changed = displayedDataRevision != candidate
        displayedDataRevision = candidate
        if changed {
            invalidateRecentFormCache()
        }

        if let current = dataFreshness {
            dataFreshness = current.replacing(
                status: current.status == .checking ? .ready : nil,
                revision: useServerRevision ? nil : .some(candidate),
                coverage: .some(dataCoverage),
                isCached: .some(false)
            )
        } else {
            dataFreshness = DataFreshness(
                status: .ready,
                revision: candidate,
                checkedAt: localLastCheckedAt ?? Date(),
                coverage: dataCoverage
            )
        }
    }

    private func canUseServerRevision(
        _ initial: FreshnessCheckResult,
        _ ending: FreshnessCheckResult
    ) -> Bool {
        let allowed: Set<FreshnessCheckResult> = [.updated, .unchanged, .partial]
        return allowed.contains(initial) && allowed.contains(ending)
    }

    private func fallbackRevision(players: [Player], coverage: DataCoverage?) -> String? {
        guard let latest = players.map(\.updatedAt).max() else { return nil }
        let timestamp = Int(latest.timeIntervalSince1970)
        let week = coverage?.week ?? 0
        let asOf = coverage.map { Int($0.asOf.timeIntervalSince1970) } ?? 0
        return "players-\(timestamp)-week-\(week)-asof-\(asOf)"
    }

    private func hasUnsafeSnapshotRegression(
        _ candidate: [Player],
        against fallback: [Player]
    ) -> Bool {
        let currentSeason = StatScoutSeason.current
        let fallbackCurrent = fallback.filter {
            $0.season == currentSeason && $0.seasonPhase == .regular
        }
        let candidateCurrent = candidate.filter {
            $0.season == currentSeason && $0.seasonPhase == .regular
        }
        guard !fallbackCurrent.isEmpty, !candidateCurrent.isEmpty else { return false }

        let fallbackTeams = Set(fallbackCurrent.map { normalizedTeamAbbreviation($0.team) })
        let candidateTeams = Set(candidateCurrent.map { normalizedTeamAbbreviation($0.team) })
        guard fallbackTeams.isSubset(of: candidateTeams) else { return true }

        let fallbackIDs = Set(fallbackCurrent.map(\.playerId))
        let candidateIDs = Set(candidateCurrent.map(\.playerId))
        let missing = fallbackIDs.subtracting(candidateIDs).count
        return Double(missing) / Double(fallbackIDs.count) > 0.20
    }

    private func persistFreshness() {
        guard cache != nil, let dataFreshness else { return }
        DataFreshnessCache.save(
            dataFreshness.replacing(coverage: .some(dataCoverage)),
            displayedRevision: displayedDataRevision
        )
    }

    func loadHistoricalIfNeeded() async {
        guard !hasLoadedHistorical, !isHistoricalLoading else { return }
        isHistoricalLoading = true
        loadingMessage = "Loading past seasons…"
        loadingProgress = 0.12

        var historical: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return cache.loadHistoricalPlayers()
            }
            return ((try? cache?.loadPlayers()) ?? []).filter { ($0.season ?? 0) < StatScoutSeason.current }
        }.value

        // The screenshot fixture and lightweight providers may intentionally
        // disable the disk cache. Fetch their historical tier directly rather
        // than leaving a Pro season menu with no data.
        if historical.isEmpty {
            historical = (try? await provider.fetchHistoricalPlayers()) ?? []
        }

        loadingMessage = "Preparing season history…"
        loadingProgress = 0.78

        if !historical.isEmpty {
            ingestPlayers(mergePlayers(replacing: historical))
            hasLoadedHistorical = true
        }

        isHistoricalLoading = false
        loadingProgress = 1
    }

    private func ingestPlayers(_ players: [Player]) {
        let grouped = Dictionary(grouping: players, by: \.playerId)
        var latestPlayers: [Player] = []
        var histories: [Int: [Player]] = [:]

        for (playerId, history) in grouped {
            let sortedHistory = history.sorted {
                guard let s1 = $0.season, let s2 = $1.season else {
                    if $0.season == nil && $1.season == nil { return false }
                    return $0.season != nil
                }
                if s1 == s2, $0.seasonPhase != $1.seasonPhase {
                    return $0.seasonPhase == .regular
                }
                return s1 > s2
            }
            histories[playerId] = sortedHistory
            if let latest = sortedHistory.first {
                latestPlayers.append(latest)
            }
        }

        self.playerHistories = histories
        self.players = latestPlayers
        // No auto-jump to an older season when the live one is thin or empty:
        // the live season is the default for everyone, Pro included.

        recomputeTeamCache()
    }

    private func recomputeTeamCache() {
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter {
            $0.season == selectedSeason && $0.seasonPhase == selectedPhase
        }
        var seenIds = Set<Int>()
        let uniquePlayers = allSeasonPlayers.filter { seenIds.insert($0.playerId).inserted }

        var teams = Set<String>()
        var teamScoresAccum: [String: (sum: Int, count: Int)] = [:]

        for player in uniquePlayers {
            let abbr = normalizedTeamAbbreviation(player.team)
            teams.insert(abbr)
            let score = player.overallPercentile
            if score > 0 {
                var entry = teamScoresAccum[abbr] ?? (0, 0)
                entry.sum += score
                entry.count += 1
                teamScoresAccum[abbr] = entry
            }
        }

        _teamsWithData = teams.sorted()
        _teamScores = teamScoresAccum.mapValues { Double($0.sum) / Double($0.count) }
        _teamCacheSeason = selectedSeason
        _teamCachePhase = selectedPhase
    }

    private func mergePlayers(replacing replacements: [Player]) -> [Player] {
        var merged: [String: Player] = [:]
        for player in playerHistories.values.flatMap({ $0 }) {
            merged[player.id] = player
        }
        for player in replacements {
            merged[player.id] = player
        }
        return Array(merged.values)
    }
}
