from datetime import date, datetime, timezone

import pytest

import ingest
import sync_games
from sync_games import (
    league_week,
    monday_on_or_before,
    parse_game,
    parse_games,
    parse_schedule_week,
    playoff_round,
    teams_for,
)

UTC = timezone.utc
START_2025 = date(2025, 10, 7)  # a Tuesday


def raw(game_id=2025020001, **overrides):
    game = {
        "id": game_id,
        "season": 20252026,
        "gameType": 2,
        "gameDate": "2025-10-07",
        "venue": {"default": "Amerant Bank Arena"},
        "startTimeUTC": "2025-10-07T21:00:00Z",
        "gameState": "OFF",
        "gameScheduleState": "OK",
        "periodDescriptor": {"number": 3, "periodType": "REG"},
        "awayTeam": {"abbrev": "CHI", "score": 2},
        "homeTeam": {"abbrev": "FLA", "score": 3},
    }
    game.update(overrides)
    return game


def test_request_politeness_matches_the_ingest_helpers():
    assert sync_games.USER_AGENT == ingest.USER_AGENT
    assert sync_games.REQUEST_PAUSE_SECONDS == ingest.REQUEST_PAUSE_SECONDS


def test_week_one_starts_on_the_monday_before_the_opener():
    assert monday_on_or_before(START_2025) == date(2025, 10, 6)
    assert league_week(date(2025, 10, 7), START_2025) == 1
    assert league_week(date(2025, 10, 12), START_2025) == 1
    assert league_week(date(2025, 10, 13), START_2025) == 2


def test_an_opener_on_a_monday_starts_its_own_week():
    assert league_week(date(2026, 9, 28), date(2026, 9, 28)) == 1
    assert league_week(date(2026, 9, 29), date(2026, 9, 28)) == 1
    assert league_week(date(2026, 10, 5), date(2026, 9, 28)) == 2


def test_playoff_weeks_continue_the_regular_season_count():
    assert league_week(date(2026, 4, 16), START_2025) == 28
    assert league_week(date(2026, 4, 18), START_2025) == 28
    assert league_week(date(2026, 6, 14), START_2025) == 36


@pytest.mark.parametrize("game_id,code", [
    (2025030186, "R1"), (2025030211, "R2"), (2025030311, "CF"), (2025030411, "SCF"),
])
def test_playoff_round_comes_from_the_round_digit(game_id, code):
    assert playoff_round(game_id) == code


def test_playoff_round_rejects_a_malformed_id():
    assert playoff_round("2025") is None
    assert playoff_round(2025030911) is None


def test_playoff_game_maps_round_and_phase():
    game = parse_game(raw(2025030411, gameType=3, gameDate="2026-06-02"), 2025, START_2025)
    assert (game.season_type, game.game_type, game.week) == ("POST", "SCF", 35)


def test_regular_season_game_fields():
    game = parse_game(raw(), 2025, START_2025)
    assert game.game_id == "2025020001"
    assert (game.season_type, game.game_type, game.week) == ("REG", "REG", 1)
    assert (game.away_team, game.home_team) == ("CHI", "FLA")
    assert (game.away_score, game.home_score) == (2, 3)
    assert game.stadium == "Amerant Bank Arena"
    assert game.kickoff_at == datetime(2025, 10, 7, 21, 0, tzinfo=UTC)
    assert game.game_date == date(2025, 10, 7)
    assert game.is_final and not game.overtime


def test_game_date_is_the_local_date_not_the_utc_date():
    late = raw(startTimeUTC="2025-10-08T02:00:00Z", gameDate="2025-10-07")
    game = parse_game(late, 2025, START_2025)
    assert game.game_date == date(2025, 10, 7)
    assert game.kickoff_at == datetime(2025, 10, 8, 2, 0, tzinfo=UTC)


@pytest.mark.parametrize("state", ["FUT", "PRE", "LIVE", "CRIT"])
def test_scores_are_withheld_until_the_game_is_final(state):
    game = parse_game(raw(gameState=state), 2025, START_2025)
    assert game.away_score is None and game.home_score is None
    assert not game.is_final and not game.overtime


@pytest.mark.parametrize("state", ["FINAL", "OFF"])
def test_both_final_states_publish_scores(state):
    game = parse_game(raw(gameState=state), 2025, START_2025)
    assert game.is_final


@pytest.mark.parametrize("period,overtime", [("REG", False), ("OT", True), ("SO", True)])
def test_overtime_is_a_last_period_of_ot_or_so(period, overtime):
    game = parse_game(raw(periodDescriptor={"periodType": period}), 2025, START_2025)
    assert game.overtime is overtime


def test_the_game_outcome_wins_over_the_period_descriptor():
    game = parse_game(
        raw(periodDescriptor={"periodType": "REG"}, gameOutcome={"lastPeriodType": "SO"}),
        2025, START_2025,
    )
    assert game.overtime


def test_an_unfinished_game_is_never_overtime():
    game = parse_game(raw(gameState="LIVE", periodDescriptor={"periodType": "OT"}), 2025, START_2025)
    assert not game.overtime


@pytest.mark.parametrize("game_type", [1, 4, 19])
def test_preseason_and_all_star_games_are_skipped(game_type):
    assert parse_game(raw(gameType=game_type), 2025, START_2025) is None


def test_cancelled_games_are_skipped():
    assert parse_game(raw(gameScheduleState="CNCL"), 2025, START_2025) is None


def test_games_are_deduplicated_across_both_clubs():
    games = parse_games([raw(), raw(), raw(2025020002, gameDate="2025-10-08")], 2025, START_2025)
    assert [g.game_id for g in games] == ["2025020001", "2025020002"]


def test_schedule_week_dates_games_by_their_schedule_day_and_skips_other_seasons():
    payload = {
        "regularSeasonStartDate": "2025-10-07",
        "gameWeek": [
            {"date": "2025-10-13", "games": [
                {k: v for k, v in raw(2025020010).items() if k != "gameDate"},
                raw(2025010001, gameType=1),
                raw(2026020001, season=20262027),
            ]},
            {"date": "2025-10-14", "games": []},
        ],
    }
    games = parse_schedule_week(payload, 2025)
    assert [(g.game_id, g.game_date, g.week) for g in games] == [("2025020010", date(2025, 10, 13), 2)]


def test_row_shape_matches_the_games_table():
    row = parse_game(raw(), 2025, START_2025).as_row(datetime(2025, 10, 8, tzinfo=UTC))
    assert set(row) == {
        "game_id", "season", "season_type", "game_type", "week", "game_date",
        "kickoff_at", "away_team", "home_team", "away_score", "home_score",
        "overtime", "stadium", "synced_at",
    }
    assert row["game_date"] == "2025-10-07"


def test_arizona_is_polled_for_seasons_up_to_2023_and_utah_after():
    assert "ARI" in teams_for(2023) and "UTA" not in teams_for(2023)
    assert "UTA" in teams_for(2025) and "ARI" not in teams_for(2025)
    assert len(teams_for(2025)) == 32


def test_season_id():
    assert sync_games.season_id(2025) == 20252026
