import SwiftUI

/// The traditional line for a whole club, percentile-mapped against the other
/// 31.
///
/// The percentile card next to it answers "how good is this group"; this
/// answers "what actually happened". The app already does this on a player
/// page, so a team not having it was the gap.
///
/// The ruler here is the league's thirty-two clubs, not its several hundred
/// players: a team's .915 save percentage means nothing against individual
/// goalies' spread, and everything against the other clubs'.
struct TeamStandardCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    /// See `TeamRankingsCard.seasonPhase`.
    var seasonPhase: SeasonPhase = .regular
    let players: [Player]
    /// Every player in the season, used to build the thirty-two team lines.
    let leaguePlayers: [Player]
    /// (team, season, phase, since).
    let fetchTeamGameLogs: ((String, Int, SeasonPhase, Date) async throws -> [PlayerGameLog])?
    /// False on a historical season: the per-game logs a rolling window is built
    /// from are only kept for the live season, so the control is hidden rather
    /// than offered and left to come back empty.
    var supportsRecent: Bool = true
    let onUpgradeTap: () -> Void

    @State private var side: PlayerPositionGroup = .forward
    @State private var showingRecent = false
    @State private var windowWeeks: Int = 4
    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?

    // MARK: - Stat vocabulary

    /// Rate stats, rebuilt from summed counts. Averaging a roster's shooting
    /// percentages would weight a fourth liner's 1-for-3 like a sniper's
    /// season; summing goals and shots is exact.
    private static let skaterRates = ["SH%"]
    private static let goalieRates = ["SV%"]

    private static let skaterCounts = [
        "P", "G", "A", "+/-", "PIM", "PPG", "PPP", "SHG", "GWG", "SOG", "HITS", "BLK", "GP",
    ]
    private static let goalieCounts = ["W", "L", "OT", "SO", "SV", "SA", "GP"]

    /// Lower is better: penalty minutes, and a goalie's losses.
    private static let lowerIsBetterLabels: Set<String> = ["PIM", "L", "OT"]

    private var rateLabels: [String] {
        side == .goalie ? Self.goalieRates : Self.skaterRates
    }

    private var countingLabels: [String] {
        side == .goalie ? Self.goalieCounts : Self.skaterCounts
    }

    private var order: [String] { rateLabels + countingLabels }

    private var window: RecentWindow {
        RecentWindow(rawValue: windowWeeks) ?? .four
    }

    /// What the card actually renders. The toggle survives a season change (it
    /// is view state, the season is a parameter), so a user who turned Recent on
    /// for the live season and then walked back to 2018 would otherwise sit in
    /// front of a permanently empty window.
    private var isRecent: Bool { showingRecent && supportsRecent }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            RinkSectionBar(title: "TEAM STANDARD STATS")

            RinkPickerRow {
                RinkSegmented(
                    segments: PlayerPositionGroup.allCases.map { .init(value: $0, label: $0.pickerLabel) },
                    selection: $side
                )
                .segmentCount(PlayerPositionGroup.allCases.count)
                if supportsRecent {
                    RinkSegmented(
                        segments: [
                            .init(value: false, label: "Season"),
                            .init(value: true, label: "Recent", isLocked: !store.isPro),
                        ],
                        selection: $showingRecent,
                        onLockedTap: { _ in onUpgradeTap() }
                    )
                    .segmentCount(2)
                }
            }
            .padding(.horizontal, RinkGeo.padInline)
            .padding(.vertical, 8)
            .background(RinkPalette.surfaceAlt)

            if isRecent {
                RinkSegmented(
                    segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
                    selection: Binding(
                        get: { window },
                        set: { windowWeeks = $0.rawValue }
                    )
                )
                .padding(.horizontal, RinkGeo.padInline)
                .padding(.bottom, 8)
                .background(RinkPalette.surfaceAlt)
            }

            if isRecent {
                recentContent
            } else {
                seasonContent
            }
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(seasonPhase.rawValue)-\(isRecent)-\(store.isPro)") {
            if isRecent, store.isPro { await load() }
        }
    }

    // MARK: - Season

    @ViewBuilder
    private var seasonContent: some View {
        let line = teamLine(for: players)
        if line.isEmpty {
            emptyState("No standard stats for this roster")
        } else {
            let league = leagueLines()
            barGroup(title: "RATE", labels: rateLabels, line: line, league: league, startIndex: 0)
            barGroup(title: "VOLUME", labels: countingLabels, line: line, league: league, startIndex: rateLabels.count)
            Text("Totals add up the current roster's season lines, so a player traded at the deadline brings his whole year with him.")
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkTertiary)
                .padding(.horizontal, RinkGeo.padCard)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func barGroup(
        title: String,
        labels: [String],
        line: [String: Double],
        league: [[String: Double]],
        startIndex: Int
    ) -> some View {
        let present = labels.filter { line[$0] != nil }
        return Group {
            if !present.isEmpty {
                RinkSubSectionBar(title: title)
                ForEach(Array(present.enumerated()), id: \.element) { offset, label in
                    let value = line[label] ?? 0
                    MetricBar(
                        metric: Metric(
                            id: "team-std-\(label)",
                            label: label,
                            value: format(label, value),
                            percentile: percentile(label: label, value: value, league: league),
                            category: side.primaryCategory
                        )
                    )
                    .padding(.horizontal, RinkGeo.padCard)
                    .padding(.vertical, 12)
                    .background((startIndex + offset) % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentContent: some View {
        if !store.isPro {
            ZStack(alignment: .bottom) {
                teaser
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See every club's last 2 / 4 / 8 weeks",
                    trigger: .teamView
                )
            }
        } else if loading {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.75)
                Text("Loading recent games…")
                    .font(RinkType.small)
                    .foregroundStyle(RinkPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let loadError {
            InlineLoadError(message: loadError) { await load() }
        } else {
            let totals = windowTotals()
            if totals.isEmpty {
                emptyState("No \(side.displayName.lowercased()) games in the last \(windowWeeks) weeks")
            } else {
                let rates = windowRates(totals)
                let seasonLine = teamLine(for: players)

                // Season to window, not a percentile bar. Two weeks of team
                // shooting percentage sits outside the whole spread of
                // thirty-two *season* figures more often than not, so a bar
                // drawn on that ruler pins to 1 or 100 and says nothing. The move against the
                // club's own season number is the real information, and it's the
                // same framing the Trends board uses.
                if !rates.isEmpty {
                    RinkSubSectionBar(title: "RATE · \(windowTitle)")
                    ForEach(Array(rates.keys.sorted(by: sortByOrder).enumerated()), id: \.element) { index, label in
                        let now = rates[label] ?? 0
                        let then = seasonLine[label]
                        HStack(spacing: 10) {
                            Text(label)
                                .font(RinkType.bodyBold)
                                .foregroundStyle(RinkPalette.ink)
                                .frame(width: 68, alignment: .leading)
                            if let then, !windowIsWholeSeason {
                                Text("\(format(label, then)) → \(format(label, now))")
                                    .font(RinkType.small)
                                    .monospacedDigit()
                                    .foregroundStyle(RinkPalette.inkSecondary)
                            } else {
                                Text(format(label, now))
                                    .font(RinkType.small)
                                    .monospacedDigit()
                                    .foregroundStyle(RinkPalette.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            if let then, !windowIsWholeSeason {
                                TrendArrow(
                                    delta: now - then,
                                    decimals: label == "SV%" ? 3 : 1,
                                    lowerIsBetter: Self.lowerIsBetterLabels.contains(label)
                                )
                            }
                        }
                        .padding(.horizontal, RinkGeo.padCard)
                        .frame(height: RinkGeo.rowHeight)
                        .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                            alignment: .bottom
                        )
                    }
                    Text(
                        windowIsWholeSeason
                            ? "Every game this club has played so far."
                            : "Compared with the same club's season line."
                    )
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .padding(.horizontal, RinkGeo.padCard)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Counting stats get no bar. Two weeks of goals against
                // thirty-two season totals would sit at the first percentile for
                // every club in the league, which says nothing.
                RinkSubSectionBar(title: "TOTALS · \(windowTitle)")
                let counts = countingWindowKeys.filter { totals[$0.label] != nil }
                ForEach(Array(counts.enumerated()), id: \.element.label) { index, entry in
                    HStack {
                        Text(entry.label)
                            .font(RinkType.bodyBold)
                            .foregroundStyle(RinkPalette.ink)
                        Spacer()
                        Text(String(format: "%.0f", totals[entry.label] ?? 0))
                            .font(RinkType.statSmall)
                            .monospacedDigit()
                            .foregroundStyle(RinkPalette.ink)
                    }
                    .padding(.horizontal, RinkGeo.padCard)
                    .frame(height: RinkGeo.rowHeight)
                    .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    /// Invented numbers in the real layout, so a free user can see what the
    /// window actually reports rather than a padlock. It tracks the window
    /// picker, because a preview that ignores the control above it looks broken.
    private var teaser: some View {
        let rows = teaserRows
        return VStack(spacing: 0) {
            RinkSubSectionBar(title: "RATE · LAST \(windowWeeks) WEEKS")
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(RinkType.bodyBold)
                        .foregroundStyle(RinkPalette.ink)
                        .frame(width: 68, alignment: .leading)
                    Text("\(format(row.0, row.1)) → \(format(row.0, row.2))")
                        .font(RinkType.small)
                        .monospacedDigit()
                        .foregroundStyle(RinkPalette.inkSecondary)
                    Spacer(minLength: 0)
                    TrendArrow(delta: row.2 - row.1, decimals: 1)
                }
                .padding(.horizontal, RinkGeo.padCard)
                .frame(height: RinkGeo.rowHeight)
                .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
            }
            RinkSubSectionBar(title: "TOTALS · LAST \(windowWeeks) WEEKS")
            ForEach(Array(teaserTotals.enumerated()), id: \.element.0) { index, row in
                HStack {
                    Text(row.0)
                        .font(RinkType.bodyBold)
                        .foregroundStyle(RinkPalette.ink)
                    Spacer()
                    Text("\(row.1)")
                        .font(RinkType.statSmall)
                        .monospacedDigit()
                        .foregroundStyle(RinkPalette.ink)
                }
                .padding(.horizontal, RinkGeo.padCard)
                .frame(height: RinkGeo.rowHeight)
                .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
            }
        }
    }

    /// Season line to an invented window, per side and per window length. Built
    /// from *this* club's real season rates so the preview is the team the user
    /// is looking at, and so moving the position or 2/4/8 pickers visibly
    /// redraws it. Only the window column is fictional, and it stays behind the
    /// blur.
    private var teaserRows: [(String, Double, Double)] {
        let seasonLine = teamLine(for: players)
        let labels = rateLabels.filter { seasonLine[$0] != nil }
        let fallback: [(String, Double)] = side == .goalie
            ? [("SV%", 0.907)]
            : [("SH%", 9.8)]
        let base: [(String, Double)] = labels.isEmpty
            ? fallback
            : labels.prefix(4).map { ($0, seasonLine[$0] ?? 0) }

        return base.map { label, season in
            let seed = Self.stableSeed("\(label)-\(side.rawValue)-\(windowWeeks)-\(team)")
            // Plus or minus 12% of the season figure, the size of a real
            // few-week swing.
            let swing = season * Double(seed % 25 - 12) / 100
            return (label, season, season + swing)
        }
    }

    private var teaserTotals: [(String, Int)] {
        let scale = Double(windowWeeks) / 4
        let base: [(String, Int)] = side == .goalie
            ? [("SV", 410), ("SA", 446), ("W", 6), ("SO", 1)]
            : [("P", 118), ("G", 42), ("SOG", 380), ("HITS", 190)]
        return base.map { label, value in
            (label, Int((Double(value) * scale).rounded()))
        }
    }

    /// Deterministic across launches, unlike `hashValue`.
    private static func stableSeed(_ text: String) -> Int {
        abs(text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
    }

    // MARK: - Aggregation

    /// One club's standard line: counting stats summed, rates rebuilt from the
    /// quantity they're a rate of. That is the same "numerators and
    /// denominators, never pre-divided rates" rule the backend rollup follows.
    private func teamLine(for roster: [Player]) -> [String: Double] {
        let pool = roster.filter { $0.positionGroup == side }
        guard !pool.isEmpty else { return [:] }

        var totals: [String: Double] = [:]
        for player in pool {
            for stat in player.standardStats ?? [] {
                let label = stat.label.uppercased()
                guard Self.summedLabels.contains(label),
                      let value = DashboardViewModel.rawNumeric(stat.value) else { continue }
                // Games played is per player, so summing it across a roster is
                // meaningless. Take the maximum, which is the club's own count.
                if label == "GP" {
                    totals["GP"] = max(totals["GP"] ?? 0, value)
                } else {
                    totals[label, default: 0] += value
                }
            }
        }
        return withDerivedRates(totals)
    }

    private static let summedLabels: Set<String> = Set(skaterCounts + goalieCounts)

    /// The rate stats, rebuilt from the summed counts.
    private func withDerivedRates(_ totals: [String: Double]) -> [String: Double] {
        var out = totals
        if let shots = totals["SOG"], shots > 0, let goals = totals["G"] {
            out["SH%"] = goals / shots * 100
        }
        if let faced = totals["SA"], faced > 0, let saves = totals["SV"] {
            out["SV%"] = saves / faced
        }
        return out
    }

    /// The other thirty-one, plus this one: the distribution a bar is drawn
    /// against.
    private func leagueLines() -> [[String: Double]] {
        Dictionary(grouping: leaguePlayers, by: \.team)
            .values
            .map { teamLine(for: $0) }
            .filter { !$0.isEmpty }
    }

    /// Rank against whichever clubs have the stat, however few that is.
    ///
    /// This used to require twelve clubs and return nil below that, which the
    /// caller turned into `percentile: 0` - a full-width empty bar reading as
    /// "worst in the league" on opening night, when the truth was "six clubs
    /// have played". A rank among the clubs that have a number is the honest answer
    /// at every point in the season.
    private func percentile(label: String, value: Double, league: [[String: Double]]) -> Int {
        var values = league.compactMap { $0[label] }
        if values.isEmpty { values = [value] }
        let below = values.reduce(0) { $0 + ($1 < value ? 1 : 0) }
        let equal = values.reduce(0) { $0 + ($1 == value ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        let oriented = Self.lowerIsBetterLabels.contains(label) ? 100 - raw : raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    // MARK: - Window

    /// Game-log key to the label it's displayed under. The rollup's own naming,
    /// so the two stay in step.
    private var countingWindowKeys: [(key: String, label: String)] {
        side == .goalie
            ? [("decision_win", "W"), ("saves", "SV"), ("shots_against", "SA"), ("shutout", "SO")]
            : [("points", "P"), ("goals", "G"), ("assists", "A"),
               ("shots_on_goal", "SOG"), ("hits", "HITS"), ("blocks", "BLK"), ("pim", "PIM")]
    }

    /// The club's logs from the trailing weeks.
    ///
    /// The window is anchored to the last date present in the data, never to
    /// today: anchoring to now would silently shrink the window to nothing
    /// all summer.
    private var sideLogs: [PlayerGameLog] {
        RecentFormWindow.logs(sideLogsAll, weeks: windowWeeks)
    }

    private var sideLogsAll: [PlayerGameLog] {
        logs.filter { $0.playerType.lowercased() == side.rawValue.lowercased() }
    }

    /// What the window heading says. "LAST 4 WEEKS" over a club that has played
    /// for ten days is a claim about days that do not exist yet.
    private var windowTitle: String {
        windowIsWholeSeason ? "SEASON TO DATE" : "LAST \(windowWeeks) WEEKS"
    }

    /// True when the club's games all fall inside the window, so "last four
    /// weeks" and "the season" are the same games.
    ///
    /// Early in the season that turned every rate row into "9.8% → 9.8%" next
    /// to a grey zero: the same number printed twice and a change measured
    /// against itself. The window is real, the comparison is not, so the
    /// comparison is what goes away.
    private var windowIsWholeSeason: Bool {
        sideLogs.count == sideLogsAll.count
    }

    /// Summed counting stats for the window, keyed by display label, plus the
    /// denominators the rates are rebuilt from.
    private func windowTotals() -> [String: Double] {
        let window = sideLogs
        guard !window.isEmpty else { return [:] }
        var totals: [String: Double] = [:]
        for log in window {
            for (key, label) in countingWindowKeys {
                if let value = log.metrics[key] ?? nil {
                    totals[label, default: 0] += value
                }
            }
            if let goals = log.metrics["goals"] ?? nil {
                totals["goals", default: 0] += goals
            }
        }
        return totals
    }

    /// The rate line rebuilt from the window's sums, the same identity the
    /// backend rollup uses, so the numbers agree with the Trends board.
    private func windowRates(_ totals: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        if side == .goalie {
            if let faced = totals["SA"], faced > 0, let saves = totals["SV"] { out["SV%"] = saves / faced }
        } else if let shots = totals["SOG"], shots > 0, let goals = totals["G"] {
            out["SH%"] = goals / shots * 100
        }
        return out
    }

    private func sortByOrder(_ a: String, _ b: String) -> Bool {
        let ai = order.firstIndex(of: a) ?? Int.max
        let bi = order.firstIndex(of: b) ?? Int.max
        return ai < bi
    }

    private func load() async {
        guard store.isPro, let fetch = fetchTeamGameLogs else { return }
        loading = true
        loadError = nil
        do {
            // Wide enough to cover the longest window, then trimmed to the
            // trailing weeks in `sideLogs`. Anchored to the
            // season's own end, not to today - see `gameLogWindowStart`.
            let since = StatScoutSeason.gameLogWindowStart(season: season)
            logs = try await fetch(team, season, seasonPhase, since)
        } catch {
            loadError = "Couldn't load team form. Pull to refresh."
        }
        loading = false
    }

    // MARK: - Formatting

    private func format(_ label: String, _ value: Double) -> String {
        switch label {
        case "SH%":
            return String(format: "%.1f%%", value)
        case "SV%":
            return RecentMetricKey.savePercentage(value)
        default:
            return Int(value.rounded()).formatted(.number.grouping(.automatic))
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(RinkPalette.inkTertiary)
            Text(message)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
