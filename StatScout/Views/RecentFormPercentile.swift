import Foundation

/// Maps a raw metric value onto the league's full-season percentile scale by
/// reusing Gridiron's own value→percentile calibration. Built entirely from the
/// in-memory league pool: for each metric we collect every qualified player's
/// (raw season value, season percentile) pair, sort by value, and interpolate.
///
/// This lets the Recent Form card draw a recent-window bar on the *same ruler*
/// as the player's season bar - so a hot 15-day stretch reads as "playing like
/// a 92" against the league norm, in context of the player's season line.
struct LeaguePercentileCurve {
    /// (value, percentile) points sorted ascending by value.
    private let points: [(value: Double, pct: Double)]

    /// Two points are enough to interpolate between, and two is what an
    /// opening week provides. The old floor of five drew no recent bar at all
    /// for a metric only a handful of players had yet, which read as a broken
    /// card rather than as a thin league sample.
    init?(points raw: [(Double, Double)]) {
        let sorted = raw.sorted { $0.0 < $1.0 }
        guard sorted.count >= 2 else { return nil }
        self.points = sorted.map { (value: $0.0, pct: $0.1) }
    }

    /// Interpolate the percentile (1-100) for a value. Direction is encoded in
    /// the points themselves (lower-is-better metrics ramp percentile down as
    /// value rises), so no per-metric direction flag is needed here.
    func percentile(for v: Double) -> Int {
        if v <= points.first!.value { return clamp(points.first!.pct) }
        if v >= points.last!.value { return clamp(points.last!.pct) }
        for i in 1..<points.count where v <= points[i].value {
            let (v0, p0) = (points[i - 1].value, points[i - 1].pct)
            let (v1, p1) = (points[i].value, points[i].pct)
            let t = v1 == v0 ? 0 : (v - v0) / (v1 - v0)
            return clamp(p0 + t * (p1 - p0))
        }
        return clamp(points.last!.pct)
    }

    private func clamp(_ p: Double) -> Int { max(1, min(100, Int(p.rounded()))) }
}

/// A set of per-metric curves for one player population, keyed by the season
/// metric label ("Pass Yds", "Rush Yds", …).
struct LeaguePercentileCurves {
    private let byLabel: [String: LeaguePercentileCurve]

    func curve(for label: String) -> LeaguePercentileCurve? { byLabel[label] }

    /// Build curves from the league pool filtered to the players who appear in
    /// any of the supplied categories. Only metrics with both a parseable raw
    /// value and a percentile contribute points.
    @MainActor
    init(players: [Player], categories: [MetricCategory], labels: [String]) {
        let pool = players.filter { player in
            categories.contains { player.matchesPlayerType(for: $0) }
        }
        var result: [String: LeaguePercentileCurve] = [:]
        for label in labels {
            var pts: [(Double, Double)] = []
            for player in pool {
                guard let m = player.metrics.first(where: { $0.label == label && categories.contains($0.category) }),
                      let v = DashboardViewModel.rawNumeric(m.value) else { continue }
                pts.append((v, Double(m.percentile)))
            }
            if let curve = LeaguePercentileCurve(points: pts) {
                result[label] = curve
            }
        }
        byLabel = result
    }
}
