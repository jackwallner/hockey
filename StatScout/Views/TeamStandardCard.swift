import SwiftUI

/// The traditional line for a whole club, percentile-mapped against the other
/// 31.
///
/// The percentile card next to it answers "how good is this offence"; this
/// answers "what actually happened". The app already does this on a player
/// page, so a team not having it was the gap.
///
/// The ruler here is the league's thirty-two clubs, not its several hundred
/// players: a team's 6.9 yards per attempt means nothing against individual
/// quarterbacks' spread, and everything against the other clubs'.
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

    @State private var side: TeamRankingsCard.Side = .offense
    @State private var showingRecent = false
    @State private var windowGames: Int = 5
    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?

    // MARK: - Stat vocabulary

    /// Rate stats and the roster quantity each is a rate of. Summing a team's
    /// completions and attempts is exact; averaging its quarterbacks' completion
    /// percentages would weight a backup's 2-for-3 like a starter's season.
    ///
    /// Football's `standard_stats` carries composites (Cmp/Att, Rec/Tgt) rather
    /// than the separate denominators, so the rates below are derived from the
    /// game-log counts in the window path and from the composite split here.
    private static let rateWeights: [String: String] = [
        "CMP%": "ATT", "Y/A": "ATT", "INT%": "ATT",
        "Y/C": "CAR",
        "CATCH%": "TGT", "Y/R": "REC",
    ]

    private static let offenseOrder = [
        "CMP%", "Y/A", "INT%", "Y/C", "CATCH%", "Y/R",
        "PASS YDS", "PASS TD", "INT", "CAR", "RUSH YDS", "RUSH TD",
        "REC", "REC YDS", "REC TD", "G",
    ]
    private static let defenseOrder = [
        "TACKLES", "SACKS", "DEF INT", "G",
    ]

    /// Lower is better. Only one on an offensive line: interceptions thrown,
    /// and the rate of them.
    private static let lowerIsBetterLabels: Set<String> = ["INT", "INT%"]

    private var order: [String] {
        side == .defense ? Self.defenseOrder : Self.offenseOrder
    }

    private var rateLabels: [String] {
        order.filter { Self.rateWeights[$0] != nil }
    }

    private var countingLabels: [String] {
        order.filter { Self.rateWeights[$0] == nil }
    }

    private var window: RecentWindow {
        RecentWindow(rawValue: windowGames) ?? .five
    }

    /// What the card actually renders. The toggle survives a season change (it
    /// is view state, the season is a parameter), so a user who turned Recent on
    /// for the live season and then walked back to 2018 would otherwise sit in
    /// front of a permanently empty window.
    private var isRecent: Bool { showingRecent && supportsRecent }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            GridironSectionBar(title: "TEAM STANDARD STATS")

            GridironPickerRow {
                GridironSegmented(
                    segments: TeamRankingsCard.Side.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $side
                )
                .segmentCount(TeamRankingsCard.Side.allCases.count)
                if supportsRecent {
                    GridironSegmented(
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
            .padding(.horizontal, GridironGeo.padInline)
            .padding(.vertical, 8)
            .background(GridironPalette.surfaceAlt)

            if isRecent {
                GridironSegmented(
                    segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
                    selection: Binding(
                        get: { window },
                        set: { windowGames = $0.rawValue }
                    )
                )
                .padding(.horizontal, GridironGeo.padInline)
                .padding(.bottom, 8)
                .background(GridironPalette.surfaceAlt)
            }

            if isRecent {
                recentContent
            } else {
                seasonContent
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
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
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
                .padding(.horizontal, GridironGeo.padCard)
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
                GridironSubSectionBar(title: title)
                ForEach(Array(present.enumerated()), id: \.element) { offset, label in
                    let value = line[label] ?? 0
                    MetricBar(
                        metric: Metric(
                            id: "team-std-\(label)",
                            label: label,
                            value: format(label, value),
                            percentile: percentile(label: label, value: value, league: league),
                            category: side == .defense ? .defense : .passing
                        )
                    )
                    .padding(.horizontal, GridironGeo.padCard)
                    .padding(.vertical, 12)
                    .background((startIndex + offset) % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
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
                    headline: "See every club's last 3 / 5 / 8 games",
                    trigger: .teamView
                )
            }
        } else if loading {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.75)
                Text("Loading recent games…")
                    .font(GridironType.small)
                    .foregroundStyle(GridironPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let loadError {
            InlineLoadError(message: loadError) { await load() }
        } else {
            let totals = windowTotals()
            if totals.isEmpty {
                emptyState("No \(side.label.lowercased()) games in the last \(windowGames)")
            } else {
                let rates = windowRates(totals)
                let seasonLine = teamLine(for: players)

                // Season to window, not a percentile bar. Five games of team
                // yards per attempt sits outside the whole spread of thirty-two
                // *season* figures more often than not, so a bar drawn on that
                // ruler pins to 1 or 100 and says nothing. The move against the
                // club's own season number is the real information, and it's the
                // same framing the Trends board uses.
                if !rates.isEmpty {
                    GridironSubSectionBar(title: "RATE · \(windowTitle)")
                    ForEach(Array(rates.keys.sorted(by: sortByOrder).enumerated()), id: \.element) { index, label in
                        let now = rates[label] ?? 0
                        let then = seasonLine[label]
                        HStack(spacing: 10) {
                            Text(label)
                                .font(GridironType.bodyBold)
                                .foregroundStyle(GridironPalette.ink)
                                .frame(width: 68, alignment: .leading)
                            if let then, !windowIsWholeSeason {
                                Text("\(format(label, then)) → \(format(label, now))")
                                    .font(GridironType.small)
                                    .monospacedDigit()
                                    .foregroundStyle(GridironPalette.inkSecondary)
                            } else {
                                Text(format(label, now))
                                    .font(GridironType.small)
                                    .monospacedDigit()
                                    .foregroundStyle(GridironPalette.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            if let then, !windowIsWholeSeason {
                                TrendArrow(
                                    delta: now - then,
                                    decimals: 1,
                                    lowerIsBetter: Self.lowerIsBetterLabels.contains(label)
                                )
                            }
                        }
                        .padding(.horizontal, GridironGeo.padCard)
                        .frame(height: GridironGeo.rowHeight)
                        .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
                            alignment: .bottom
                        )
                    }
                    Text(
                        windowIsWholeSeason
                            ? "Every game this club has played so far."
                            : "Compared with the same club's season line."
                    )
                        .font(GridironType.micro)
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .padding(.horizontal, GridironGeo.padCard)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Counting stats get no bar. Five games of touchdowns against
                // thirty-two season totals would sit at the first percentile for
                // every club in the league, which says nothing.
                GridironSubSectionBar(title: "TOTALS · \(windowTitle)")
                let counts = countingWindowKeys.filter { totals[$0.label] != nil }
                ForEach(Array(counts.enumerated()), id: \.element.label) { index, entry in
                    HStack {
                        Text(entry.label)
                            .font(GridironType.bodyBold)
                            .foregroundStyle(GridironPalette.ink)
                        Spacer()
                        Text(String(format: "%.0f", totals[entry.label] ?? 0))
                            .font(GridironType.statSmall)
                            .monospacedDigit()
                            .foregroundStyle(GridironPalette.ink)
                    }
                    .padding(.horizontal, GridironGeo.padCard)
                    .frame(height: GridironGeo.rowHeight)
                    .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(GridironPalette.divider).frame(height: GridironGeo.hairline),
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
            GridironSubSectionBar(title: "RATE · LAST \(windowGames) GAMES")
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(GridironType.bodyBold)
                        .foregroundStyle(GridironPalette.ink)
                        .frame(width: 68, alignment: .leading)
                    Text("\(format(row.0, row.1)) → \(format(row.0, row.2))")
                        .font(GridironType.small)
                        .monospacedDigit()
                        .foregroundStyle(GridironPalette.inkSecondary)
                    Spacer(minLength: 0)
                    TrendArrow(delta: row.2 - row.1, decimals: 1)
                }
                .padding(.horizontal, GridironGeo.padCard)
                .frame(height: GridironGeo.rowHeight)
                .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
            }
            GridironSubSectionBar(title: "TOTALS · LAST \(windowGames) GAMES")
            ForEach(Array(teaserTotals.enumerated()), id: \.element.0) { index, row in
                HStack {
                    Text(row.0)
                        .font(GridironType.bodyBold)
                        .foregroundStyle(GridironPalette.ink)
                    Spacer()
                    Text("\(row.1)")
                        .font(GridironType.statSmall)
                        .monospacedDigit()
                        .foregroundStyle(GridironPalette.ink)
                }
                .padding(.horizontal, GridironGeo.padCard)
                .frame(height: GridironGeo.rowHeight)
                .background(index % 2 == 0 ? GridironPalette.surface : GridironPalette.surfaceAlt)
            }
        }
    }

    /// Season line to an invented window, per side and per window length. Built
    /// from *this* club's real season rates so the preview is the team the user
    /// is looking at, and so moving the Offense/Defense or 3/5/8 pickers visibly
    /// redraws it. Only the window column is fictional, and it stays behind the
    /// blur.
    private var teaserRows: [(String, Double, Double)] {
        let seasonLine = teamLine(for: players)
        let labels = rateLabels.filter { seasonLine[$0] != nil }
        let fallback: [(String, Double)] = side == .defense
            ? [("TACKLES", 62), ("SACKS", 2.4), ("DEF INT", 0.8)]
            : [("CMP%", 64.2), ("Y/A", 6.9), ("Y/C", 4.3), ("CATCH%", 65.1)]
        let base: [(String, Double)] = labels.isEmpty
            ? fallback
            : labels.prefix(4).map { ($0, seasonLine[$0] ?? 0) }

        return base.map { label, season in
            let seed = Self.stableSeed("\(label)-\(side.rawValue)-\(windowGames)-\(team)")
            // Plus or minus 12% of the season figure, the size of a real
            // five-game swing.
            let swing = season * Double(seed % 25 - 12) / 100
            return (label, season, season + swing)
        }
    }

    private var teaserTotals: [(String, Int)] {
        let scale = Double(windowGames) / 5
        return [("PASS YDS", 1_180), ("RUSH YDS", 545), ("PASS TD", 8), ("REC", 96)].map { label, value in
            (label, Int((Double(value) * scale).rounded()))
        }
    }

    /// Deterministic across launches, unlike `hashValue`.
    private static func stableSeed(_ text: String) -> Int {
        abs(text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
    }

    // MARK: - Aggregation

    /// One club's standard line: counting stats summed, rates rebuilt from the
    /// quantity they're a rate of.
    ///
    /// Football's standard line ships Cmp/Att and Rec/Tgt as composite strings,
    /// so those are split into their two counts first and the rates derived from
    /// the sums. That is the same "numerators and denominators, never
    /// pre-divided rates" rule the backend rollup follows.
    private func teamLine(for roster: [Player]) -> [String: Double] {
        let cats = side.categories
        let pool = roster.filter { p in cats.contains { p.matchesPlayerType(for: $0) } }
        guard !pool.isEmpty else { return [:] }

        var totals: [String: Double] = [:]

        for player in pool {
            for stat in player.standardStats ?? [] {
                let label = stat.label.uppercased()
                if label == "CMP/ATT" || label == "REC/TGT" {
                    let parts = stat.value.split(separator: "/").compactMap {
                        DashboardViewModel.rawNumeric(String($0))
                    }
                    guard parts.count == 2 else { continue }
                    if label == "CMP/ATT" {
                        totals["CMP", default: 0] += parts[0]
                        totals["ATT", default: 0] += parts[1]
                    } else {
                        totals["REC", default: 0] += parts[0]
                        totals["TGT", default: 0] += parts[1]
                    }
                    continue
                }
                guard let value = DashboardViewModel.rawNumeric(stat.value) else { continue }
                // Games played is per player, so summing it across a roster is
                // meaningless. Take the maximum, which is the club's own count.
                if label == "G" {
                    totals["G"] = max(totals["G"] ?? 0, value)
                } else {
                    totals[label, default: 0] += value
                }
            }
        }

        return withDerivedRates(totals)
    }

    /// The rate stats, rebuilt from the summed counts.
    private func withDerivedRates(_ totals: [String: Double]) -> [String: Double] {
        var out = totals
        if let att = totals["ATT"], att > 0 {
            if let cmp = totals["CMP"] { out["CMP%"] = cmp / att * 100 }
            if let yds = totals["PASS YDS"] { out["Y/A"] = yds / att }
            if let ints = totals["INT"] { out["INT%"] = ints / att * 100 }
        }
        if let car = totals["CAR"], car > 0, let yds = totals["RUSH YDS"] {
            out["Y/C"] = yds / car
        }
        if let tgt = totals["TGT"], tgt > 0, let rec = totals["REC"] {
            out["CATCH%"] = rec / tgt * 100
        }
        if let rec = totals["REC"], rec > 0, let yds = totals["REC YDS"] {
            out["Y/R"] = yds / rec
        }
        // Bookkeeping totals, never displayed on their own row.
        out["CMP"] = nil
        out["ATT"] = nil
        out["TGT"] = nil
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
    /// "worst in the league" on week one, when the truth was "six clubs have
    /// played". A rank among the clubs that have a number is the honest answer
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
        side == .defense
            ? [("def_tackles_solo", "TACKLES"), ("def_sacks", "SACKS"), ("def_interceptions", "DEF INT")]
            : [("passing_yards", "PASS YDS"), ("passing_tds", "PASS TD"),
               ("rushing_yards", "RUSH YDS"), ("rushing_tds", "RUSH TD"),
               ("receptions", "REC"), ("receiving_yards", "REC YDS")]
    }

    /// The club's last N *games*, not its last N log rows.
    ///
    /// The window is anchored to the last date present in the data, never to
    /// today: the NFL plays weekly, so anchoring to now would silently shrink
    /// the window to nothing for six days out of seven. And it counts distinct
    /// game dates rather than rows, because there is one row per player per
    /// game, so a row count is the window multiplied by the roster.
    private var sideLogs: [PlayerGameLog] {
        let onSide = logs.filter { side.includes(playerType: $0.playerType) }
        let gameDates = Set(onSide.map(\.gameDate)).sorted(by: >)
        let kept = Set(gameDates.prefix(windowGames))
        return onSide.filter { kept.contains($0.gameDate) }
    }

    /// What the window heading says. "LAST 5 GAMES" over a club that has played
    /// one is a claim about games that do not exist yet.
    private var windowTitle: String {
        windowIsWholeSeason ? "SEASON TO DATE" : "LAST \(windowGames) GAMES"
    }

    /// True when the club has played no more games than the window, so "last
    /// five" and "the season" are the same games.
    ///
    /// In week one that turned every rate row into "73.5% → 73.5%" next to a
    /// grey zero: the same number printed twice and a change measured against
    /// itself. The window is real, the comparison is not, so the comparison is
    /// what goes away.
    private var windowIsWholeSeason: Bool {
        let onSide = logs.filter { side.includes(playerType: $0.playerType) }
        return Set(onSide.map(\.gameDate)).count <= windowGames
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
            for key in ["attempts", "completions", "interceptions", "carries", "targets"] {
                if let value = log.metrics[key] ?? nil {
                    totals[key, default: 0] += value
                }
            }
            if side == .defense, let assists = log.metrics["def_tackle_assists"] ?? nil {
                totals["TACKLES", default: 0] += assists
            }
        }
        return totals
    }

    /// The rate line rebuilt from the window's sums, the same identity the
    /// backend rollup uses, so the numbers agree with the Trends board.
    private func windowRates(_ totals: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        let att = totals["attempts"] ?? 0
        let cmp = totals["completions"] ?? 0
        let ints = totals["interceptions"] ?? 0
        let car = totals["carries"] ?? 0
        let tgt = totals["targets"] ?? 0
        let rec = totals["REC"] ?? 0

        if att > 0 {
            out["CMP%"] = cmp / att * 100
            if let yds = totals["PASS YDS"] { out["Y/A"] = yds / att }
            out["INT%"] = ints / att * 100
        }
        if car > 0, let yds = totals["RUSH YDS"] { out["Y/C"] = yds / car }
        if tgt > 0 { out["CATCH%"] = rec / tgt * 100 }
        if rec > 0, let yds = totals["REC YDS"] { out["Y/R"] = yds / rec }
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
            // Wide enough to cover the longest window plus byes, then trimmed to
            // the last N distinct game dates in `sideLogs`. Anchored to the
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
        case "CMP%", "INT%", "CATCH%":
            return String(format: "%.1f%%", value)
        case "Y/A", "Y/C", "Y/R", "SACKS":
            return String(format: "%.1f", value)
        default:
            return Int(value.rounded()).formatted(.number.grouping(.automatic))
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(GridironPalette.inkTertiary)
            Text(message)
                .font(GridironType.small)
                .foregroundStyle(GridironPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
