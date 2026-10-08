import Foundation

/// What the data can and cannot say about a given season.
///
/// StatScout carries every season from 2008-09 on, which is where MoneyPuck's
/// expected-goals model starts. Inside that range every metric exists for every
/// season, so the only gaps worth naming are the career rollup, which blends
/// them all, and a live season whose source files have not caught up with the
/// games already played.
///
/// The season numbers here mirror the constants in `backend/ingest.py`; see
/// `project-docs/architecture/HOCKEY_CONTRACT.md`.
enum MetricCoverage {
    /// One short sentence explaining what this season is missing, or nil when
    /// the season has the full metric set.
    static func note(for season: Int, category: MetricCategory? = nil) -> String? {
        guard StatScoutSeason.isAllTime(season) else { return nil }
        return "Career totals span \(SeasonLabel.display(StatScoutSeason.earliest)) onward. Rate metrics are averaged over every season a player qualified."
    }

    /// The live season's own gap: a source that exists for this year but has
    /// not published yet. MoneyPuck regenerates its files after the night's
    /// games and the NHL summary posts separately, so either can lag.
    static func pendingNote(
        shotsStatus: String?,
        summaryStatus: String?
    ) -> String? {
        func pending(_ status: String?) -> Bool {
            guard let status = status?.lowercased() else { return false }
            return status != "ready" && status != "not_applicable" && status != "unavailable"
        }
        if pending(shotsStatus) {
            return "Expected goals for the latest games are still arriving from MoneyPuck. Shot-based metrics will catch up after the next update."
        }
        if pending(summaryStatus) {
            return "NHL standard stats (+/-, power-play points, game-winners) for the latest games are still arriving."
        }
        return nil
    }

    /// Whether a metric is expected to exist at all in this season. Every
    /// metric reaches back to the start of the dataset.
    static func isTracked(_ label: String, in season: Int) -> Bool { true }
}
