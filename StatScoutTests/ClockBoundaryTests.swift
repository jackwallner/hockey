import XCTest
@testable import Hockey_StatScout

/// Date logic pinned to a fixed clock and explicit zones, never the machine's.
///
/// Every test names the past fix it guards, or says it is a new guard.
final class ClockBoundaryTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func local(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                       _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: Season rollover

    /// New guard (the rule is the one backend/ingest.py::resolve_season uses):
    /// an NHL season is named for the year it opens in, and the new one is the
    /// default from 1 September, local midnight, a month before opening night.
    func testSeasonFlipsAtLocalMidnightOnSeptemberFirst() {
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2026, 8, 31, 23, 59, 59), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 8, 31, 23, 59, 59), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 9, 1, 0, 0, 0), calendar: la), 2027)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 9, 1, 0, 0, 1), calendar: la), 2027)
    }

    /// New guard: the same instant is a different season either side of the
    /// date line of the zone it is read in, which is why the calendar is
    /// injected.
    func testSeasonFollowsTheViewersZoneAcrossTheFlip() {
        let instantAfterUTCMidnight = instant("2027-09-01T03:00:00Z")
        XCTAssertEqual(StatScoutSeason.season(on: instantAfterUTCMidnight, calendar: utc), 2027)
        XCTAssertEqual(StatScoutSeason.season(on: instantAfterUTCMidnight, calendar: la), 2026)
    }

    /// New guard: the season runs through New Year, the Stanley Cup Final in
    /// June and the whole summer until the next 1 September, and never
    /// resolves older than the season the app shipped with.
    func testSeasonHoldsThroughNewYearThePlayoffsAndTheSummer() {
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2026, 12, 31, 23, 59, 59), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 1, 1), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 6, 20), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 7, 1), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2019, 10, 1), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2026, 3, 14), calendar: la), 2026)
    }

    /// New guard: neither DST changeover moves the flip.
    func testSeasonIsUnaffectedByTheDSTChangeovers() {
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 3, 14, 1, 59, 59), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 3, 14, 3, 0, 0), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2026, 11, 1, 1, 30, 0), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 11, 7, 1, 30, 0), calendar: la), 2027)
    }

    // MARK: Game-log window

    /// New guard (ported from football 8ca22e7): once the season is over the
    /// window is anchored to 1 July, the day count is calendar days, and so it
    /// starts at local midnight across the spring-forward day.
    func testWindowIsAnchoredToTheSeasonsEndAndStartsAtLocalMidnight() {
        let start = StatScoutSeason.gameLogWindowStart(
            season: 2026, days: 120, now: local(la, 2027, 9, 15), calendar: la
        )
        XCTAssertEqual(start, local(la, 2027, 3, 3))
        XCTAssertEqual(la.component(.hour, from: start), 0)
    }

    func testLiveWindowTracksTheClockAcrossTheFallBackDay() {
        let start = StatScoutSeason.gameLogWindowStart(
            season: 2026, days: 60, now: local(la, 2026, 12, 1), calendar: la
        )
        XCTAssertEqual(start, local(la, 2026, 10, 2))
        XCTAssertEqual(la.component(.hour, from: start), 0)
        // The last second before 1 July still tracks the clock; 1 July stops it.
        let cap = local(la, 2027, 7, 1)
        let before = StatScoutSeason.gameLogWindowStart(season: 2026, days: 10, now: cap.addingTimeInterval(-1), calendar: la)
        let at = StatScoutSeason.gameLogWindowStart(season: 2026, days: 10, now: cap, calendar: la)
        let after = StatScoutSeason.gameLogWindowStart(season: 2026, days: 10, now: cap.addingTimeInterval(86_400), calendar: la)
        XCTAssertLessThan(before, at)
        XCTAssertEqual(at, after)
    }

    // MARK: Game status

    private func game(_ id: String, kickoff: Date, phase: SeasonPhase = .regular, gameType: String = "REG") -> Game {
        Game(id: id, season: 2026, seasonPhase: phase, gameType: gameType, week: 1, kickoff: kickoff,
             awayTeam: "SEA", homeTeam: "EDM")
    }

    /// 6c893d6: with no live feed a game is in progress for 3 hours 15
    /// minutes from puck drop, then awaits a score. The drop itself is already
    /// in progress.
    func testGameStatusBoundaries() {
        let drop = instant("2026-10-09T02:00:00Z")
        let night = game("g", kickoff: drop)
        XCTAssertEqual(night.status(now: drop.addingTimeInterval(-1)), .upcoming)
        XCTAssertEqual(night.status(now: drop), .inProgress)
        XCTAssertEqual(night.status(now: drop.addingTimeInterval(3.25 * 3_600 - 1)), .inProgress)
        XCTAssertEqual(night.status(now: drop.addingTimeInterval(3.25 * 3_600)), .awaitingScore)
    }

    // MARK: The day a fan means by "tonight"

    /// 6c893d6: the front door is today's slate from 2 PM local, or as soon
    /// as a puck has dropped; until then, with nothing started, last night's
    /// finals. Exact edges, in a fixed zone.
    func testFrontDoorSwitchesToTonightAtTwoPMOrFirstPuckDrop() {
        let games = [
            game("last", kickoff: local(la, 2026, 10, 7, 19)),
            game("tonight", kickoff: local(la, 2026, 10, 8, 19)),
        ]
        func day(_ now: Date) -> Date? { GameDay.current(in: games, now: now, calendar: la)?.date }
        let oct7 = la.startOfDay(for: local(la, 2026, 10, 7))
        let oct8 = la.startOfDay(for: local(la, 2026, 10, 8))

        XCTAssertEqual(day(local(la, 2026, 10, 8, 0, 0, 0)), oct7, "midnight: still last night")
        XCTAssertEqual(day(local(la, 2026, 10, 8, 13, 59, 59)), oct7)
        XCTAssertEqual(day(local(la, 2026, 10, 8, 14, 0, 0)), oct8)
        XCTAssertEqual(day(local(la, 2026, 10, 8, 18, 59, 59)), oct8)
        XCTAssertEqual(day(local(la, 2026, 10, 8, 23, 59, 59)), oct8)
        XCTAssertEqual(day(local(la, 2026, 10, 9, 0, 0, 0)), oct8, "no games on the 9th: the most recent day")
    }

    /// An early start flips the front door before 2 PM: a 12:30 PM puck drop
    /// (Saturday matinee) is tonight's slate from the drop on, not before.
    func testAMatineeBringsTheFrontDoorForwardFromPuckDrop() {
        let games = [
            game("last", kickoff: local(la, 2026, 10, 9, 19)),
            game("matinee", kickoff: local(la, 2026, 10, 10, 12, 30)),
        ]
        func day(_ now: Date) -> Date? { GameDay.current(in: games, now: now, calendar: la)?.date }
        XCTAssertEqual(day(local(la, 2026, 10, 10, 12, 29, 59)), la.startOfDay(for: local(la, 2026, 10, 9)))
        XCTAssertEqual(day(local(la, 2026, 10, 10, 12, 30, 0)), la.startOfDay(for: local(la, 2026, 10, 10)))
    }

    /// New guard: the 2 PM rule is a wall-clock hour, so on the two DST
    /// changeover days it is 13 or 14 real hours into the day, and still
    /// switches at 2 PM on the clock.
    func testFrontDoorStillSwitchesAtTwoPMOnTheChangeoverDays() {
        for (year, month, day) in [(2026, 11, 1), (2027, 3, 14)] {
            let tonight = local(la, year, month, day, 19)
            let lastNight = la.date(byAdding: .day, value: -1, to: tonight)!
            let games = [game("last", kickoff: lastNight), game("tonight", kickoff: tonight)]
            func current(_ hour: Int, _ minute: Int) -> Date? {
                GameDay.current(in: games, now: local(la, year, month, day, hour, minute), calendar: la)?.date
            }
            XCTAssertEqual(current(13, 59), la.startOfDay(for: lastNight), "\(month)/\(day) 1:59 PM")
            XCTAssertEqual(current(14, 0), la.startOfDay(for: tonight), "\(month)/\(day) 2:00 PM")
        }
    }

    /// 6c893d6: relative labels follow the calendar day, not 24-hour spans,
    /// so on the 25-hour fall-back day "Yesterday" and "Tomorrow" still name
    /// the neighbouring dates.
    func testRelativeLabelsFollowCalendarDaysAcrossTheChangeover() {
        let now = local(la, 2026, 11, 1, 23, 30)
        func label(_ month: Int, _ day: Int) -> String {
            GameDay(date: la.startOfDay(for: local(la, 2026, month, day)), phase: .regular).label(now: now, calendar: la)
        }
        XCTAssertEqual(label(11, 1), "Today")
        XCTAssertEqual(label(10, 31), "Yesterday")
        XCTAssertEqual(label(11, 2), "Tomorrow")
        let spring = local(la, 2027, 3, 14, 23, 30)
        func springLabel(_ day: Int) -> String {
            GameDay(date: la.startOfDay(for: local(la, 2027, 3, day)), phase: .regular).label(now: spring, calendar: la)
        }
        XCTAssertEqual(springLabel(13), "Yesterday")
        XCTAssertEqual(springLabel(15), "Tomorrow")
    }

    /// 6c893d6: a night game belongs to the viewer's calendar day. A 10:30 PM
    /// Pacific puck drop is the 8th in Los Angeles and the 9th in Eastern
    /// time, and the day it lands on is the one the slate groups it under.
    func testALateGameBelongsToTheViewersCalendarDay() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let late = game("late", kickoff: local(la, 2026, 10, 8, 22, 30))
        XCTAssertEqual(GameDay.day(of: late, calendar: la), la.startOfDay(for: local(la, 2026, 10, 8)))
        XCTAssertEqual(GameDay.day(of: late, calendar: eastern), eastern.startOfDay(for: local(eastern, 2026, 10, 9)))
        let days = GameDay.days(in: [late], calendar: eastern)
        XCTAssertEqual(days.first?.games(from: [late], calendar: eastern).map(\.id), ["late"])
        XCTAssertEqual(days.first?.games(from: [late], calendar: la).map(\.id), [])
    }

    /// 6c893d6: before the season the front door is the first night, after the
    /// final it is the last, with the playoffs a separate day on the same
    /// date. Preseason, regular season, playoffs, offseason in one pass.
    func testFrontDoorThroughThePreseasonRegularSeasonPlayoffsAndOffseason() {
        let opener = game("opener", kickoff: local(la, 2026, 10, 7, 19))
        let finale = game("finale", kickoff: local(la, 2027, 4, 16, 19))
        let cup = game("cup", kickoff: local(la, 2027, 6, 18, 17), phase: .playoffs, gameType: "SCF")
        let games = [cup, finale, opener]
        func day(_ now: Date) -> GameDay? { GameDay.current(in: games, now: now, calendar: la) }

        XCTAssertEqual(day(local(la, 2026, 9, 1))?.date, la.startOfDay(for: local(la, 2026, 10, 7)), "preseason: first night")
        XCTAssertEqual(day(local(la, 2026, 12, 25, 9))?.date, la.startOfDay(for: local(la, 2026, 10, 7)), "mid-season gap: last day with games")
        XCTAssertEqual(day(local(la, 2027, 4, 16, 20))?.phase, .regular)
        XCTAssertEqual(day(local(la, 2027, 6, 18, 17, 30))?.phase, .playoffs, "Cup Final night")
        XCTAssertEqual(day(local(la, 2027, 8, 1))?.phase, .playoffs, "offseason: the last day there was")
        XCTAssertEqual(day(local(la, 2027, 8, 1))?.date, la.startOfDay(for: local(la, 2027, 6, 18)))
    }

    // MARK: Eastern days

    /// 6c893d6: the NHL files a game under its Eastern date. A game date is
    /// Eastern midnight (04:00Z in daylight time, 05:00Z in standard time,
    /// midnight on the changeover days still before the 2 AM switch) and
    /// round-trips to the same date key whatever zone the phone is in.
    func testGameDatesAreEasternMidnightAndKeyBackToTheSameDate() throws {
        for (raw, utcInstant) in [
            ("2026-10-11", "2026-10-11T04:00:00Z"), ("2026-11-01", "2026-11-01T04:00:00Z"),
            ("2026-11-02", "2026-11-02T05:00:00Z"), ("2027-03-14", "2027-03-14T05:00:00Z"),
            ("2027-03-15", "2027-03-15T04:00:00Z"),
        ] {
            let parsed = try XCTUnwrap(DataFreshness.parseDate(raw), raw)
            XCTAssertEqual(parsed, instant(utcInstant), raw)
            XCTAssertEqual(LiveScoreClient.dateKey(parsed), raw)
        }
    }

    /// Late-night games key by the Eastern date: 11:30 PM Eastern is the same
    /// date key, and the first minute after Eastern midnight is the next.
    func testDateKeyTurnsOverAtEasternMidnight() {
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2026-11-02T04:59:59Z")), "2026-11-01")
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2026-11-02T05:00:00Z")), "2026-11-02")
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2027-03-14T04:59:59Z")), "2027-03-13")
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2027-03-14T05:00:00Z")), "2027-03-14")
    }

    /// 02a20f41 (football, same decoder): variable fractional seconds.
    func testTimestampsParseWithAnyFractionalPrecision() {
        let expected = instant("2026-10-09T05:37:56Z")
        for raw in [
            "2026-10-09T05:37:56+00:00", "2026-10-09T05:37:56Z", "2026-10-09T05:37:56.9+00:00",
            "2026-10-09T05:37:56.93+00:00", "2026-10-09T05:37:56.93411+00:00",
            "2026-10-08T22:37:56.934113-07:00",
        ] {
            let parsed = DataFreshness.parseDate(raw)
            XCTAssertNotNil(parsed, raw)
            XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 1, raw)
        }
    }

    // MARK: Recent windows

    private func log(_ date: String) throws -> PlayerGameLog {
        let json = """
        {"player_id":1,"season":2026,"season_type":"REG","game_date":"\(date)","player_type":"f",
         "plays":18,"touches":3,"metrics":{}}
        """
        return try JSONDecoder().decode(PlayerGameLog.self, from: Data(json.utf8))
    }

    /// New guard: the trailing window is `weeks` * 7 calendar days before the
    /// newest game, exclusive at the far edge, so a four-week window is
    /// exactly 28 dates ending on the newest, across the fall-back day.
    func testTrailingWindowIsCalendarDaysBeforeTheNewestGame() throws {
        let first = local(la, 2026, 10, 5)
        let dates = (0..<35).map { offset -> String in
            let day = la.date(byAdding: .day, value: offset, to: first)!
            let parts = la.dateComponents([.year, .month, .day], from: day)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        XCTAssertEqual(dates.last, "2026-11-08")
        let logs = try dates.map(log)
        for calendar in [la, utc] {
            let window = RecentFormWindow.logs(logs, weeks: 4, calendar: calendar)
            XCTAssertEqual(window.count, 28, calendar.timeZone.identifier)
            XCTAssertEqual(window.last?.gameDate, try log("2026-10-12").gameDate)
            XCTAssertEqual(window.first?.gameDate, try log("2026-11-08").gameDate, "newest first")
        }
        XCTAssertTrue(RecentFormWindow.logs([], weeks: 4, calendar: la).isEmpty)
    }

    // MARK: Ages and weekly deltas

    private func profile(born: String) throws -> PlayerProfile {
        let json = #"[{"player_id":1,"season":2026,"birth_date":"\#(born)"}]"#
        return try XCTUnwrap(JSONDecoder.statScout.decode([PlayerProfile].self, from: Data(json.utf8)).first)
    }

    /// Age differenced the UTC-midnight birth date in the machine's zone, so
    /// in Pacific time a player turned a year older at 5 PM the evening before
    /// his birthday (the football fix in 73ae5f2, same code).
    func testAgeTurnsOverOnTheBirthdayInTheViewersZone() throws {
        let player = try profile(born: "2000-09-24")
        XCTAssertEqual(player.age(on: local(la, 2026, 9, 23, 20, 0), calendar: la), 25)
        XCTAssertEqual(player.age(on: local(la, 2026, 9, 23, 23, 59, 59), calendar: la), 25)
        XCTAssertEqual(player.age(on: local(la, 2026, 9, 24, 0, 0, 0), calendar: la), 26)
        let leap = try profile(born: "2000-02-29")
        XCTAssertEqual(leap.age(on: local(la, 2027, 2, 28, 23, 59), calendar: la), 26)
        XCTAssertEqual(leap.age(on: local(la, 2027, 3, 1), calendar: la), 27)
    }

    func testWeeklyDeltaWindowEdge() {
        let now = instant("2026-11-03T12:00:00Z")
        func trend(_ id: String, ageSeconds: TimeInterval, delta: Int) -> GameTrend {
            GameTrend(id: id, date: now.addingTimeInterval(-ageSeconds), opponent: "EDM",
                      summary: "", percentileDelta: delta, keyMetric: "P/60")
        }
        let player = Player(
            playerId: 1, name: "T", team: "SEA", position: "C", handedness: "", updatedAt: now,
            metrics: [], standardStats: [],
            games: [
                trend("edge", ageSeconds: 7 * 86_400, delta: 4),
                trend("just-out", ageSeconds: 7 * 86_400 + 1, delta: 50),
                trend("fresh", ageSeconds: 60, delta: -1),
            ]
        )
        XCTAssertEqual(player.weeklyDelta(asOf: now), 3)
    }

    // MARK: Non-Gregorian device calendars

    private func calendar(_ id: Calendar.Identifier, zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: id)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// Overnight audit 2026-10-30 (H1): a phone set to region Thailand uses the
    /// Buddhist calendar, so the season resolved to 2569 and nothing loaded;
    /// Hebrew gave 5786, and Japanese hid behind the 2026 floor until the
    /// rollover, then stuck. The season rule is Gregorian whatever calendar
    /// the viewer uses.
    func testSeasonIsGregorianOnEveryDeviceCalendar() {
        let date = local(la, 2026, 10, 30, 12)
        let ids: [Calendar.Identifier] = [.buddhist, .japanese, .islamicUmmAlQura, .persian, .hebrew, .republicOfChina]
        for id in ids {
            XCTAssertEqual(StatScoutSeason.season(on: date, calendar: calendar(id)), 2026, "\(id)")
            XCTAssertEqual(StatScoutSeason.season(on: local(la, 2027, 10, 15), calendar: calendar(id)), 2027, "\(id)")
        }
        XCTAssertEqual(StatScoutSeason.season(on: local(la, 2028, 8, 31, 23), calendar: calendar(.buddhist)), 2027)
    }

    /// H1: the zone of the device calendar still decides the day.
    func testSeasonKeepsTheDeviceZoneOnANonGregorianCalendar() {
        let instantAfterUTCMidnight = instant("2027-09-01T00:30:00Z")
        XCTAssertEqual(StatScoutSeason.season(on: instantAfterUTCMidnight, calendar: calendar(.buddhist, zone: "UTC")), 2027)
        XCTAssertEqual(StatScoutSeason.season(on: instantAfterUTCMidnight, calendar: calendar(.buddhist)), 2026)
    }

    /// H1: team game logs were requested "since 2569-...".
    func testGameLogWindowIsGregorianOnABuddhistCalendar() {
        let now = local(la, 2026, 10, 30, 12)
        let buddhist = StatScoutSeason.gameLogWindowStart(season: 2026, days: 10, now: now, calendar: calendar(.buddhist))
        let gregorian = StatScoutSeason.gameLogWindowStart(season: 2026, days: 10, now: now, calendar: la)
        XCTAssertEqual(buddhist, gregorian)
        XCTAssertEqual(la.component(.year, from: buddhist), 2026)
    }

    /// H1: a 1997 birthday read 572 under Buddhist and -1989 under Japanese.
    func testAgeIsGregorianOnEveryDeviceCalendar() throws {
        let player = try profile(born: "1997-01-13")
        let date = local(la, 2026, 10, 30, 12)
        for id in [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura, .hebrew] {
            XCTAssertEqual(player.age(on: date, calendar: calendar(id)), 29, "\(id)")
        }
    }

    /// H1: fixed-format feed dates parsed into 1483 on a Thai-region phone.
    /// Meaningful under `-testRegion TH` as well as on a Gregorian host.
    func testFeedDayParsesAsGregorianOnAnyRegion() throws {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let parsed = try XCTUnwrap(DataFreshness.parseDate("2026-10-29"))
        XCTAssertEqual(eastern.dateComponents([.year, .month, .day], from: parsed),
                       DateComponents(year: 2026, month: 10, day: 29))
    }

    /// H1: `RecentForm.asOf` landed in 1483 too.
    func testRecentFormAsOfIsGregorianEastern() throws {
        let json = #"{"player_id":1,"season":2026,"season_type":"REG","player_type":"f","window_weeks":4,"as_of":"2026-10-28"}"#
        let row = try JSONDecoder.statScout.decode(RecentForm.self, from: Data(json.utf8))
        let asOf = try XCTUnwrap(row.asOf)
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(eastern.dateComponents([.year, .month, .day, .hour], from: asOf),
                       DateComponents(year: 2026, month: 10, day: 28, hour: 0))
    }

    /// H1: the shared feed-day formatter cannot fall back to the device's
    /// calendar or locale.
    func testFeedDayFormatterIsGregorianAndPOSIX() {
        let formatter = DateFormatter.feedDay
        XCTAssertEqual(formatter.calendar.identifier, .gregorian)
        XCTAssertEqual(formatter.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(formatter.timeZone.identifier, "America/New_York")
    }

    /// H1: `StatScoutSeason.current` itself, on whatever host runs the suite.
    func testCurrentSeasonIsAGregorianYear() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let year = eastern.component(.year, from: .now)
        XCTAssertTrue((year - 1...year).contains(StatScoutSeason.current), "\(StatScoutSeason.current)")
    }
}
