package com.jackwallner.hockey

import com.jackwallner.hockey.data.DashboardViewModel.QualifierLevel
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameProjection
import com.jackwallner.hockey.model.LeagueDivision
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.PlayerProfile
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandardStat
import com.jackwallner.hockey.model.StandingsRow
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.leagueTeamAbbreviations
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EnrichmentTest {
    private val current = StatScoutSeason.current

    private fun player(id: Int, type: String = "f", team: String = "SEA", metrics: List<Metric>, stats: List<StandardStat> = emptyList()) =
        testPlayer(
            id, "P$id", team, if (type == "g") "G" else if (type == "d") "D" else "C", current,
            type = type, metrics = metrics, standard = stats,
        )

    private fun m(label: String, value: String, pct: Int, category: MetricCategory, qualified: Boolean? = null, rankable: Boolean? = null) =
        metric(label, value, pct, category, qualified, rankable, id = "$label-$pct-$value")

    private fun array(json: String) = (Json.parseToJsonElement(json) as JsonArray).map { it as JsonObject }

    @Test
    fun zeroCountingStatIsUnrankedButRatesAndNonZeroCountsAreNot() {
        assertTrue(m("G", "0", 47, MetricCategory.SCORING).isUnranked)
        assertTrue(m("Takeaways", "0", 41, MetricCategory.PLAY_DRIVING).isUnranked)
        assertTrue(m("SO", "0", 41, MetricCategory.GOALTENDING).isUnranked)
        assertFalse(m("G", "12", 80, MetricCategory.SCORING).isUnranked)
        assertFalse("a rate at zero is a real rank", m("P/60", "0.00", 50, MetricCategory.SCORING).isUnranked)
        assertFalse("a percentage at zero is a real rank", m("Sh%", "0.0%", 50, MetricCategory.SCORING).isUnranked)
        assertFalse("advanced totals keep their rank", m("ixG", "0.0", 50, MetricCategory.SHOT_QUALITY).isUnranked)
        assertTrue(m("PIM", "0", 47, MetricCategory.PLAY_DRIVING, rankable = false).isUnranked)
    }

    @Test
    fun overallPercentileLeavesUnrankedZerosOut() {
        val defenseman = player(
            1, type = "d",
            metrics = listOf(
                m("Blocks", "40", 20, MetricCategory.PLAY_DRIVING),
                m("Hits", "0", 47, MetricCategory.PLAY_DRIVING),
                m("Takeaways", "0", 41, MetricCategory.PLAY_DRIVING),
            ),
        )
        assertEquals(20, defenseman.overallPercentile)
        assertEquals("Blocks", defenseman.headlineMetric?.label)
    }

    private fun final(id: String, day: Int, away: String, home: String, a: Int, h: Int, overtime: Boolean = false) = Game(
        id = id, season = 2026, week = 1, kickoff = Instant.ofEpochSecond(1_791_000_000L + day * 86_400L),
        awayTeam = away, homeTeam = home, awayScore = a, homeScore = h, overtime = overtime,
    )

    @Test
    fun standingsCountRecordsPointsDifferentialAndStreak() {
        val games = listOf(
            final("1", 1, "SEA", "VAN", 4, 2),
            final("2", 2, "EDM", "SEA", 3, 2, overtime = true),
            final("3", 3, "SEA", "CGY", 1, 4),
            Game(id = "4", season = 2026, week = 1, kickoff = null, awayTeam = "VAN", homeTeam = "SEA"),
        )
        val table = StandingsRow.build(games, listOf("SEA", "VAN", "EDM", "CGY"))
        val seattle = table.getValue("SEA")
        assertEquals("wins, losses, then overtime losses", "1-1-1", seattle.record)
        assertEquals(1, seattle.otLosses)
        assertEquals("two for a win, one for an overtime loss", 3, seattle.points)
        assertEquals(3, seattle.games)
        assertEquals(7, seattle.goalsFor)
        assertEquals(9, seattle.goalsAgainst)
        assertEquals(-2, seattle.differential)
        assertEquals("L1", seattle.streak)
        assertEquals("OT1", StandingsRow.build(games.take(2), listOf("SEA")).getValue("SEA").streak)
        assertEquals("1-0-0", table.getValue("CGY").record)
        assertEquals("W1", table.getValue("CGY").streak)
        assertEquals(2, table.getValue("EDM").points)
        assertEquals(0, table.getValue("VAN").points)
        assertEquals("0-1-0", table.getValue("VAN").record)
        assertEquals(
            "points, then points percentage, then goal differential",
            listOf("SEA", "CGY", "EDM", "VAN"), StandingsRow.ordered(table.values.toList()).map { it.team },
        )
    }

    @Test
    fun divisionPlaceUsesTheStandingsOrderWithinTheDivision() {
        val games = listOf(
            final("1", 1, "SEA", "VAN", 4, 2),
            final("2", 2, "EDM", "SEA", 3, 2, overtime = true),
            final("3", 3, "CGY", "EDM", 1, 4),
            final("4", 4, "BOS", "TOR", 3, 1),
        )
        val table = StandingsRow.build(games, leagueTeamAbbreviations)
        val seattle = StandingsRow.divisionPlace("SEA", table)
        assertEquals("EDM has 4 points, SEA 3, VAN and CGY none", 2, seattle?.first)
        assertEquals(LeagueDivision.PACIFIC, seattle?.second)
        assertEquals(1, StandingsRow.divisionPlace("EDM", table)?.first)
        assertEquals(LeagueDivision.ATLANTIC, StandingsRow.divisionPlace("BOS", table)?.second)
        assertNull("a club that has not played has no place", StandingsRow.divisionPlace("ANA", table))
        assertNull(StandingsRow.divisionPlace("ZZZ", table))
    }

    @Test
    fun ordinalsHandleTeensAndSuffixes() {
        val cases = listOf(1 to "1ST", 2 to "2ND", 3 to "3RD", 4 to "4TH", 8 to "8TH", 11 to "11TH", 12 to "12TH", 21 to "21ST", 22 to "22ND")
        for ((number, text) in cases) assertEquals(text, StandingsRow.ordinal(number))
    }

    @Test
    fun standingsLeavePlayoffGamesAndUnknownClubsOut() {
        val playoff = Game(
            id = "p", season = 2026, seasonPhase = SeasonPhase.PLAYOFFS, gameType = "R1", week = 28,
            kickoff = Instant.ofEpochSecond(1_791_000_000L), awayTeam = "SEA", homeTeam = "EDM", awayScore = 1, homeScore = 0,
        )
        val table = StandingsRow.build(listOf(playoff, final("x", 1, "SEA", "ZZZ", 2, 1)), listOf("SEA", "EDM"))
        assertEquals("1-0-0", table.getValue("SEA").record)
        assertEquals(0, table.getValue("EDM").games)
        assertEquals(0.0, table.getValue("EDM").winPercentage, 0.0)
        assertNull(table["ZZZ"])
        assertEquals(1.0, table.getValue("SEA").winPercentage, 0.0001)
    }

    @Test
    fun profileDecodesTheFeedRow() {
        val json = """
            [{"player_id":8000001,"season":2026,"jersey":97,"birth_date":"1997-01-13","height_in":73,"weight_lb":194,
              "birthplace":"Fictionville, ON, CAN","years_exp":11,"rookie_season":2015,"draft_year":2015,"draft_round":1,
              "draft_pick":1,"draft_team":"EDM","toi_seconds":126200,"toi_per_gp":1262.4,"pp_toi_seconds":20000,
              "pk_toi_seconds":2000,"toi_share":0.123,"is_rookie":true,"updated_at":"2026-10-08T18:54:32.1+00:00","unknown_column":1}]
        """.trimIndent()
        val profile = PlayerProfile.fromJson(array(json).first())
        assertEquals(97, profile.jersey)
        assertEquals("6'1\", 194 lb", profile.sizeLabel)
        assertEquals("Fictionville, ON, CAN", profile.birthplace)
        assertEquals("2015 Rd 1, #1 overall", profile.draftLabel)
        assertEquals("21:02", profile.toiPerGameLabel)
        assertEquals(126_200, profile.toiSeconds)
        assertEquals("a fractional average must not drop the row", 1262, profile.toiPerGame)
        assertEquals(true, profile.isRookie)
        assertEquals(0.123, profile.toiShare!!, 0.0001)
        assertEquals("3:20 PP · 0:20 PK", profile.specialTeamsLabel(100))
        assertNull(profile.specialTeamsLabel(0))
        assertEquals(29, profile.age(LocalDate.of(2026, 10, 8)))
    }

    @Test
    fun profileWithOnlyTheKeyColumnsDecodesAndHidesTheRest() {
        val profile = PlayerProfile.fromJson(array("""[{"player_id":8000002,"season":2026,"years_exp":2}]""").first())
        assertNull(profile.sizeLabel)
        assertNull(profile.toiPerGameLabel)
        assertNull(profile.age())
        assertEquals("Undrafted", profile.draftLabel)
        assertNull(PlayerProfile(playerId = 1, season = 2026).draftLabel)
    }

    @Test
    fun projectionLabelsTheFavourite() {
        val rows = array(
            """[{"game_id":"g","home_margin":-0.6,"home_win_prob":0.446},{"game_id":"h","home_margin":0.1,"home_win_prob":0.52},{"game_id":"i","home_margin":0.0,"home_win_prob":0.502}]""",
        ).map { GameProjection.fromJson(it) }
        assertEquals("SEA 55%", rows[0].label("EDM", "SEA"))
        assertEquals(0.554, rows[0].winProbability("SEA", "EDM"), 0.0001)
        assertEquals(0.446, rows[0].winProbability("EDM", "EDM"), 0.0001)
        assertEquals("EDM 52%", rows[1].label("EDM", "SEA"))
        assertEquals("Toss-up", rows[2].label("EDM", "SEA"))
    }

    @Test
    fun teamRatingDecodesAndSigns() {
        val json = """[{"season":2026,"team":"SEA","rank":1,"games":6,"through_week":2,"rating":0.71,"offense":0.39,"defense":0.32,"schedule":-0.08,"wins":4,"losses":1,"ties":1,"points_for":22,"points_against":14,"updated_at":"2026-10-08T18:54:32+00:00"}]"""
        val rating = TeamRating.fromJson(array(json).first())
        assertEquals("the ties column holds overtime losses", 1, rating.ties)
        assertEquals("+0.71", TeamRating.signed(rating.rating))
        assertEquals("0.00", TeamRating.signed(-0.004))
        assertEquals("-0.37", TeamRating.signed(-0.37))
    }

    @Test
    fun qualifiedBoardsHideSmallSamplesAndCarryVolume() = runTest {
        val regular = player(
            1, type = "d", metrics = listOf(m("xGF%", "52.0%", 70, MetricCategory.PLAY_DRIVING, qualified = true)),
            stats = listOf(StandardStat("GP", "10", "gp"), StandardStat("TOI/GP", "22:00", "toi")),
        )
        val cameo = player(2, type = "d", metrics = listOf(m("xGF%", "70.0%", 99, MetricCategory.PLAY_DRIVING, qualified = false)))
        val vm = dashboard(MockProvider(listOf(regular, cameo)))
        vm.load()
        vm.selectedPosition = PlayerPositionGroup.DEFENSE
        vm.qualifierLevel = QualifierLevel.QUALIFIED

        assertEquals(listOf(1), vm.leaderboard.map { it.playerId })
        assertEquals("220 min", vm.volumeCaption(regular, MetricCategory.PLAY_DRIVING))
        vm.qualifierLevel = QualifierLevel.ALL
        assertEquals("the small sample sinks below the qualified player", listOf(1, 2), vm.leaderboard.map { it.playerId })
    }

    @Test
    fun profilesLoadForTheLiveSeasonOnly() = runTest {
        val skater = player(1, metrics = listOf(m("ixG", "5.0", 70, MetricCategory.SHOT_QUALITY, qualified = true)))
        fun provider(profile: PlayerProfile) = object : MockProvider(listOf(skater)) {
            override suspend fun fetchPlayerProfiles(season: Int) = listOf(profile)
        }
        val vm = dashboard(provider(PlayerProfile(playerId = 1, season = current, toiPerGame = 1_200)))
        vm.load()
        assertEquals("20:00", vm.profile(skater)?.toiPerGameLabel)

        val stale = dashboard(provider(PlayerProfile(playerId = 1, season = current - 1)))
        stale.load()
        assertNull("a profile from another season is not this player's", stale.profile(skater))
    }

    @Test
    fun qualificationIsPerMetric() = runTest {
        val winger = player(
            1,
            metrics = listOf(
                m("P/60", "3.1", 90, MetricCategory.SCORING, qualified = true),
                m("ixG/60", "1.1", 99, MetricCategory.SHOT_QUALITY, qualified = false),
            ),
        )
        val vm = dashboard(MockProvider(listOf(winger)))
        vm.load()
        vm.selectedPosition = PlayerPositionGroup.FORWARD
        vm.qualifierLevel = QualifierLevel.QUALIFIED
        vm.setUserSortMetric("ixG/60")
        assertTrue("qualified for P/60 is not qualified for ixG/60", vm.leaderboard.isEmpty())
        vm.setUserSortMetric("P/60")
        assertEquals(listOf(1), vm.leaderboard.map { it.playerId })
    }
}
