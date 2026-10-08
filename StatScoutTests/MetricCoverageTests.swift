import XCTest
@testable import Gridiron_StatScout

/// The coverage notes exist so a gap in an old season reads as a limit of the
/// public record rather than as a broken app. These tests pin the boundaries to
/// the same years the pipeline uses.
final class MetricCoverageTests: XCTestCase {
    func testCurrentSeasonHasNoCoverageCaveat() {
        XCTAssertNil(MetricCoverage.note(for: StatScoutSeason.current))
    }

    func testPreNextGenSeasonIsExplained() {
        let note = MetricCoverage.note(for: 2012)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("2016") == true)
    }

    func testPreCpoeSeasonNamesTheOlderLimit() {
        let note = MetricCoverage.note(for: 2001)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("2006") == true)
    }

    func testMissingTargetSeasonsAreCalledOut() {
        for season in 2003...2008 {
            let note = MetricCoverage.note(for: season, category: .receiving)
            XCTAssertNotNil(note, "\(season) should carry a note")
            XCTAssertTrue(
                note?.contains("target") == true,
                "\(season) note should mention targets: \(note ?? "nil")"
            )
        }
        // 2009 has targets again. It still predates Next Gen Stats, so it keeps a
        // note - just not one about targets.
        let note2009 = MetricCoverage.note(for: 2009, category: .receiving)
        XCTAssertFalse(note2009?.contains("target") == true, "2009 has targets: \(note2009 ?? "nil")")
        // And a modern season has no caveat at all.
        XCTAssertNil(MetricCoverage.note(for: 2024, category: .receiving))
    }

    func testDefenseNoteTracksPfrStart() {
        XCTAssertNotNil(MetricCoverage.note(for: 2017, category: .defense))
        XCTAssertNil(MetricCoverage.note(for: 2018, category: .defense))
    }

    func testAllTimeExplainsItSpansEras() {
        let note = MetricCoverage.note(for: StatScoutSeason.allTime)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("Career") == true)
    }

    // MARK: - isTracked

    func testIsTrackedMatchesSourceStartYears() {
        XCTAssertFalse(MetricCoverage.isTracked("Separation", in: 2015))
        XCTAssertTrue(MetricCoverage.isTracked("Separation", in: 2016))

        XCTAssertFalse(MetricCoverage.isTracked("RYOE", in: 2017))
        XCTAssertTrue(MetricCoverage.isTracked("RYOE", in: 2018))

        XCTAssertFalse(MetricCoverage.isTracked("CPOE", in: 2005))
        XCTAssertTrue(MetricCoverage.isTracked("CPOE", in: 2006))

        XCTAssertFalse(MetricCoverage.isTracked("Pressures", in: 2017))
        XCTAssertTrue(MetricCoverage.isTracked("Pressures", in: 2018))
    }

    func testTargetDerivedMetricsAreUntrackedInTheGapOnly() {
        XCTAssertTrue(MetricCoverage.isTracked("Target Share", in: 2002))
        XCTAssertFalse(MetricCoverage.isTracked("Target Share", in: 2005))
        XCTAssertTrue(MetricCoverage.isTracked("Target Share", in: 2009))
    }

    /// Stats with no source limit are tracked everywhere, including the career
    /// rollup, which spans every era by definition.
    func testUnboundedMetricsAreAlwaysTracked() {
        XCTAssertTrue(MetricCoverage.isTracked("EPA/Play", in: 2000))
        XCTAssertTrue(MetricCoverage.isTracked("Pass Yds", in: 2000))
        XCTAssertTrue(MetricCoverage.isTracked("Separation", in: StatScoutSeason.allTime))
    }
}
