import XCTest
@testable import Gridiron_StatScout

/// Where a team card's rolling game-log window starts.
///
/// The window used to be measured back from *today*, which only works while the
/// season is being played: an NFL season ends in February and the next does not
/// kick off until September, so from about March onward the fetch reached into an
/// empty stretch of calendar, came back with nothing, and every Recent control on
/// a team page reported "No offense data in the last 5 games" for a season the
/// app was happily showing season totals for.
final class GameLogWindowTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Mid-season: the window still tracks the live date, because the newest game
    /// is the one just played.
    func testDuringTheSeasonTheWindowIsAnchoredToToday() {
        let now = date(2025, 12, 1)
        let start = StatScoutSeason.gameLogWindowStart(season: 2025, days: 120, now: now)
        XCTAssertEqual(start, calendar.date(byAdding: .day, value: -120, to: now))
    }

    /// The offseason, which is where this broke. August 2026 is five months past
    /// the 2025 season's last game, so a window measured from today contains no
    /// games at all; anchored to the season's end it reaches back into December.
    func testAfterTheSeasonTheWindowIsAnchoredToTheSeasonsEnd()  {
        let now = date(2026, 8, 17)
        let start = StatScoutSeason.gameLogWindowStart(season: 2025, days: 120, now: now)
        XCTAssertLessThan(start, now)
        XCTAssertEqual(start, calendar.date(byAdding: .day, value: -120, to: date(2026, 3, 1)))
        // The window has to reach the last game actually played - the 2025
        // regular season ended in the first week of January 2026.
        XCTAssertLessThan(start, date(2026, 1, 4))
    }

    /// A past season is the same case as the offseason, all year round: the
    /// window follows the season, never the clock.
    func testAPastSeasonNeverDependsOnTheCurrentDate() {
        let early = StatScoutSeason.gameLogWindowStart(season: 2022, now: date(2026, 8, 17))
        let late = StatScoutSeason.gameLogWindowStart(season: 2022, now: date(2030, 1, 1))
        XCTAssertEqual(early, late)
        XCTAssertLessThan(early, date(2023, 1, 8))
    }

    /// Wide enough to slice the longest window (8 games) out of, byes included -
    /// a team plays about 17 games over 18 weeks, so 120 days covers roughly the
    /// back half of a season.
    func testWindowSpansEnoughWeeksForTheLongestSlice() {
        let now = date(2026, 8, 17)
        let start = StatScoutSeason.gameLogWindowStart(season: 2025, now: now)
        let weeks = calendar.dateComponents([.day], from: start, to: date(2026, 3, 1)).day! / 7
        XCTAssertGreaterThanOrEqual(weeks, 12)
    }
}
