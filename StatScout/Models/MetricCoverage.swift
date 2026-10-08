import Foundation

/// What the data can and cannot say about a given season.
///
/// StatScout carries every season from 2000 on, but the *advanced* metrics don't
/// all reach that far back, because the sources don't. Next Gen Stats begin in
/// 2016 (2018 for rushing-over-expected), CPOE needs the play-by-play air-yards
/// tracking that starts in 2006, Pro-Football-Reference's advanced defensive
/// table starts in 2018, and nflverse's `targets` column is simply blank for
/// 2003-2008, which takes every target-derived receiving metric with it.
///
/// Without this, those gaps read as bugs. A user who opens 2004, sees a receiving
/// board with no Target Share and no Catch%, and is told nothing, has been given
/// a reason to distrust the numbers that *are* there. Naming the limit is what
/// makes the rest of the board credible - and it is a limit of the public record,
/// not of the app.
///
/// The season numbers here mirror the constants in `backend/ingest.py`; the
/// coverage table in `handoff/NFL_CONTRACT.md` is the shared reference.
enum MetricCoverage {
    /// Next Gen Stats: Time to Throw, Aggressiveness, Intended Air Yds,
    /// Separation, YAC+.
    static let nextGenFirstSeason = 2016
    /// NGS rushing-over-expected (RYOE) arrived two years after the rest.
    static let rushingOverExpectedFirstSeason = 2018
    /// CPOE needs pbp air-yards tracking.
    static let cpoeFirstSeason = 2006
    /// PFR advanced defence: pressures, coverage allowed, missed-tackle rate.
    static let advancedDefenseFirstSeason = 2018
    /// Seasons where nflverse reports essentially no targets, so Target Share,
    /// WOPR, RACR, Catch% and EPA/Tgt cannot be computed. Receivers in these
    /// years are qualified by receptions instead.
    static let missingTargetSeasons = 2003...2008

    /// One short sentence explaining what this season is missing, or nil when
    /// the season has the full metric set.
    ///
    /// Deliberately at most two clauses. A season that predates several sources
    /// at once would otherwise produce a paragraph nobody reads, so the oldest
    /// and most sweeping limit is the one named.
    static func note(for season: Int, category: MetricCategory? = nil) -> String? {
        // The career rollup spans every era, so it is bounded by all of them at
        // once; saying so once is more honest than listing four start years.
        if StatScoutSeason.isAllTime(season) {
            return "Career totals span 2000 onward. Advanced metrics cover only the seasons their source tracked, so rate metrics are averaged over those years."
        }

        if let category, category == .defense {
            return season < advancedDefenseFirstSeason
                ? "Advanced defensive stats (pressures, coverage allowed, missed tackles) start in \(advancedDefenseFirstSeason)."
                : nil
        }

        if let category, category == .receiving, missingTargetSeasons.contains(season) {
            return "The play-by-play record has no target data for \(missingTargetSeasons.lowerBound)-\(missingTargetSeasons.upperBound), so target-based metrics are unavailable and receivers are ranked by receptions."
        }

        if missingTargetSeasons.contains(season) {
            return "Next Gen Stats start in \(nextGenFirstSeason). Target data is also missing league-wide for \(missingTargetSeasons.lowerBound)-\(missingTargetSeasons.upperBound)."
        }

        if season < cpoeFirstSeason {
            return "Only EPA and traditional stats reach \(season). CPOE starts in \(cpoeFirstSeason) and Next Gen Stats in \(nextGenFirstSeason)."
        }

        if season < nextGenFirstSeason {
            return "Next Gen Stats (Time to Throw, Separation, YAC+) start in \(nextGenFirstSeason)."
        }

        if season < rushingOverExpectedFirstSeason {
            return "Rushing Yards Over Expected starts in \(rushingOverExpectedFirstSeason)."
        }

        return nil
    }

    /// The live season's own gap: a source that exists for this year but has
    /// not published yet. `note(for:)` can only say what a year predates, so at
    /// 2026 Week 3, with Pro-Football-Reference's advanced defensive table not
    /// yet out, the defensive boards said nothing about why two thirds of the
    /// league had no advanced line.
    static func pendingNote(
        category: MetricCategory,
        advancedDefenseStatus: String?,
        nextGenStatus: String?
    ) -> String? {
        func pending(_ status: String?) -> Bool {
            guard let status = status?.lowercased() else { return false }
            return status != "ready" && status != "not_applicable" && status != "unavailable"
        }
        if category == .defense, pending(advancedDefenseStatus) {
            return "Advanced defensive stats (pressures, coverage allowed, missed tackles) publish once Pro-Football-Reference posts them for this season, usually within the first month. Until then defenders are ranked on production."
        }
        if category != .defense, pending(nextGenStatus) {
            return "Next Gen Stats (CPOE, separation, RYOE) for the latest games are still arriving."
        }
        return nil
    }

    /// Whether a metric is expected to exist at all in this season. Lets a
    /// caller distinguish "nobody qualified" from "not tracked yet".
    static func isTracked(_ label: String, in season: Int) -> Bool {
        if StatScoutSeason.isAllTime(season) { return true }
        switch label {
        case "Time to Throw", "Aggressiveness", "Intended Air Yds", "Separation", "YAC+":
            return season >= nextGenFirstSeason
        case "RYOE":
            return season >= rushingOverExpectedFirstSeason
        case "CPOE":
            return season >= cpoeFirstSeason
        case "Pressures", "Hurries", "QB KD", "Cmp% Allowed",
             "Yds/Tgt Allowed", "Rating Allowed", "Missed Tkl%":
            return season >= advancedDefenseFirstSeason
        case "Target Share", "WOPR", "RACR", "Catch%", "EPA/Tgt":
            return !missingTargetSeasons.contains(season)
        default:
            return true
        }
    }
}
