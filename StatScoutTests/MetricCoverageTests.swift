import XCTest
@testable import Hockey_StatScout

/// The coverage notes exist so a gap reads as a limit of the public record
/// rather than as a broken app. Every metric exists for every season from
/// 2008-09, so only the career rollup and a live season that is still
/// catching up carry a note.
final class MetricCoverageTests: XCTestCase {
    func testCurrentSeasonHasNoCoverageCaveat() {
        XCTAssertNil(MetricCoverage.note(for: StatScoutSeason.current))
    }

    func testEverySeasonInRangeHasNoCoverageCaveat() {
        for season in StatScoutSeason.earliest...StatScoutSeason.current {
            for category in MetricCategory.allCases {
                XCTAssertNil(MetricCoverage.note(for: season, category: category), "\(season) \(category)")
            }
        }
    }

    func testAllTimeExplainsItSpansEras() {
        let note = MetricCoverage.note(for: StatScoutSeason.allTime)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("Career") == true)
        XCTAssertTrue(note?.contains("2008-09") == true, "the note names the first season in 2008-09 form")
    }

    // MARK: - Pending sources

    func testPendingNoteNamesTheSourceThatIsLate() {
        let shots = MetricCoverage.pendingNote(shotsStatus: "pending", summaryStatus: "ready")
        XCTAssertTrue(shots?.contains("MoneyPuck") == true)
        let summary = MetricCoverage.pendingNote(shotsStatus: "ready", summaryStatus: "pending")
        XCTAssertTrue(summary?.contains("NHL") == true)
        XCTAssertNil(MetricCoverage.pendingNote(shotsStatus: "ready", summaryStatus: "not_applicable"))
        XCTAssertNil(MetricCoverage.pendingNote(shotsStatus: nil, summaryStatus: nil))
    }

    // MARK: - isTracked

    /// Every metric reaches back to the start of the dataset, the career
    /// rollup included.
    func testEveryMetricIsTrackedInEverySeason() {
        for label in ["ixG", "GSAx", "xGF%", "P"] {
            XCTAssertTrue(MetricCoverage.isTracked(label, in: StatScoutSeason.earliest))
            XCTAssertTrue(MetricCoverage.isTracked(label, in: StatScoutSeason.current))
            XCTAssertTrue(MetricCoverage.isTracked(label, in: StatScoutSeason.allTime))
        }
    }

    func testDatasetFloorMatchesMoneyPucksFirstSeason() {
        XCTAssertEqual(StatScoutSeason.earliest, 2008)
        XCTAssertEqual(SeasonLabel.display(StatScoutSeason.earliest), "2008-09")
    }
}
