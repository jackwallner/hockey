from datetime import datetime, timezone

import pandas as pd
import pytest

import team_ratings as tr
from ingest_enrichment import (
    active_contracts,
    build_player_profiles,
    build_team_ratings,
    latest_injuries,
    season_snaps,
)

NOW = datetime(2026, 9, 26, tzinfo=timezone.utc)


def schedule(games, season=2026):
    return pd.DataFrame([
        {
            "game_id": f"{season}_{week:02d}_{away}_{home}",
            "season": season, "game_type": "REG", "week": week,
            "away_team": away, "home_team": home,
            "away_score": away_score, "home_score": home_score,
            "location": location,
        }
        for week, away, home, away_score, home_score, location in games
    ])


def pbp_for(games, epa_by_team, season=2026):
    """Ten dropbacks and ten runs per offense per game, each at a fixed EPA."""
    rows = []
    for week, away, home, *_ in games:
        game_id = f"{season}_{week:02d}_{away}_{home}"
        for team in (away, home):
            for kind in ("pass", "run"):
                for _ in range(10):
                    rows.append({
                        "game_id": game_id, "season_type": "REG", "posteam": team,
                        "epa": epa_by_team[team], "play_type": kind,
                        "pass": 1 if kind == "pass" else 0,
                        "rush": 1 if kind == "run" else 0,
                        "qb_dropback": 1 if kind == "pass" else 0,
                    })
    return pd.DataFrame(rows)


GAMES = [
    (1, "AAA", "BBB", 10, 30, "Home"),
    (1, "CCC", "DDD", 20, 20, "Home"),
    (2, "BBB", "CCC", 27, 13, "Home"),
    (2, "DDD", "AAA", 17, 14, "Home"),
]
EPA = {"AAA": -0.2, "BBB": 0.25, "CCC": 0.0, "DDD": 0.05}


def test_ratings_read_like_a_point_spread_and_centre_on_zero():
    rows = tr.team_game_rows(pbp_for(GAMES, EPA), schedule(GAMES))
    ratings = tr.rate(rows)
    assert set(ratings) == {"AAA", "BBB", "CCC", "DDD"}
    assert sum(r.rating for r in ratings.values()) == pytest.approx(0, abs=1e-6)
    assert ratings["BBB"].rating > ratings["DDD"].rating > ratings["AAA"].rating
    assert (ratings["BBB"].wins, ratings["BBB"].losses) == (2, 0)
    assert (ratings["CCC"].wins, ratings["CCC"].losses, ratings["CCC"].ties) == (0, 1, 1)
    assert ratings["AAA"].points_for == 24


def test_schedule_adjustment_is_off_after_week_one_and_full_by_week_ten():
    assert tr.sos_weight(1) == 0
    assert tr.sos_weight(10) == 1
    assert tr.sos_weight(20) == 1
    assert 0 < tr.sos_weight(5) < 1


def test_last_season_counts_as_five_games_of_evidence():
    assert tr.prior_weight(0) == 1
    assert tr.prior_weight(10) == pytest.approx(1 / 3)
    assert tr.prior_weight(17) == pytest.approx(5 / 22)
    assert tr.prior_weight(1) > tr.prior_weight(2) > tr.prior_weight(8)


def test_projection_adds_home_field_except_on_neutral_sites():
    even = tr.TeamRating("X", 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    margin, win = tr.project(even, even)
    assert margin == pytest.approx(tr.HOME_FIELD)
    assert win > 0.5
    margin, win = tr.project(even, even, neutral=True)
    assert margin == 0
    assert win == pytest.approx(0.5)


def test_team_ratings_rows_rank_and_project_unplayed_games():
    played = GAMES
    upcoming = [(3, "AAA", "BBB", None, None, "Home"), (3, "CCC", "DDD", None, None, "Neutral")]
    sched = schedule(played + upcoming)
    teams, projections = build_team_ratings(
        2026, sched, pbp_for(played, EPA), schedule(played, 2025), pbp_for(played, EPA, 2025), NOW
    )
    assert [row["rank"] for row in teams] == [1, 2, 3, 4]
    assert teams[0]["team"] == "BBB"
    assert teams[0]["through_week"] == 2
    assert {p["game_id"] for p in projections} == {"2026_03_AAA_BBB", "2026_03_CCC_DDD"}
    home_bbb = next(p for p in projections if p["home_team"] == "BBB")
    assert home_bbb["home_margin"] > 0 and home_bbb["home_win_prob"] > 0.5


def test_a_season_with_no_finals_starts_from_last_season():
    upcoming = [(1, "AAA", "BBB", None, None, "Home")]
    teams, projections = build_team_ratings(
        2026, schedule(upcoming), pd.DataFrame(), schedule(GAMES, 2025), pbp_for(GAMES, EPA, 2025), NOW
    )
    assert len(teams) == 4
    assert all(row["games"] == 0 for row in teams)
    assert len(projections) == 1


def test_active_contract_takes_the_newest_signing():
    contracts = pd.DataFrame([
        {"gsis_id": "00-0038543", "is_active": True, "apy": 1.9, "apy_cap_pct": 0.009, "years": 4,
         "year_signed": 2023, "value": 14.4, "guaranteed": 14.4},
        {"gsis_id": "00-0038543", "is_active": True, "apy": 42.15, "apy_cap_pct": 0.14, "years": 4,
         "year_signed": 2026, "value": 168.6, "guaranteed": 120.0},
        {"gsis_id": "00-0000009", "is_active": False, "apy": 10.0, "apy_cap_pct": 0.04, "years": 2,
         "year_signed": 2020, "value": 20.0, "guaranteed": 5.0},
    ])
    deals = active_contracts(contracts)
    assert set(deals) == {38543}
    assert deals[38543]["contract_apy"] == 42.15
    assert deals[38543]["contract_cap_pct"] == 0.14


def test_snap_share_counts_games_the_player_missed():
    snaps = pd.DataFrame([
        # Two KC games; the linebacker played every snap of the first and missed the second.
        {"game_id": "g1", "game_type": "REG", "week": 1, "team": "KC", "pfr_player_id": "LB01",
         "offense_snaps": 0, "offense_pct": 0, "defense_snaps": 60, "defense_pct": 1.0,
         "st_snaps": 5, "st_pct": 0.2},
        {"game_id": "g1", "game_type": "REG", "week": 1, "team": "KC", "pfr_player_id": "CB01",
         "offense_snaps": 0, "offense_pct": 0, "defense_snaps": 30, "defense_pct": 0.5,
         "st_snaps": 0, "st_pct": 0},
        {"game_id": "g2", "game_type": "REG", "week": 2, "team": "KC", "pfr_player_id": "CB01",
         "offense_snaps": 0, "offense_pct": 0, "defense_snaps": 70, "defense_pct": 1.0,
         "st_snaps": 0, "st_pct": 0},
    ])
    rows = season_snaps(snaps, {"LB01": 1, "CB01": 2})
    assert rows[1]["def_snaps"] == 60
    assert rows[1]["team_games"] == 2
    assert rows[1]["def_snap_pct"] == pytest.approx(60 / 130, abs=1e-3)
    assert rows[2]["def_snap_pct"] == pytest.approx(100 / 130, abs=1e-3)
    assert rows[1]["off_snap_pct"] is None


def test_latest_injury_report_wins():
    injuries = pd.DataFrame([
        {"gsis_id": "00-0000001", "game_type": "REG", "week": 2, "report_status": "Questionable",
         "report_primary_injury": "Ankle", "practice_primary_injury": None, "practice_status": "Limited"},
        {"gsis_id": "00-0000001", "game_type": "REG", "week": 3, "report_status": "Out",
         "report_primary_injury": "Hamstring", "practice_primary_injury": None, "practice_status": "DNP"},
    ])
    rows = latest_injuries(injuries)
    assert rows[1] == {"injury_week": 3, "injury_status": "Out", "injury": "Hamstring", "practice_status": "DNP"}


def test_profiles_cover_every_requested_player_even_without_sources():
    players = pd.DataFrame([{
        "gsis_id": "00-0000001", "pfr_id": "QB01", "jersey_number": 17, "birth_date": "1998-05-17",
        "height": 77, "weight": 237, "college_name": "Wyoming", "years_of_experience": 8,
        "rookie_season": 2018, "draft_year": 2018, "draft_round": 1, "draft_pick": 7, "draft_team": "BUF",
    }])
    rows = build_player_profiles(
        2026, {1, 2}, players, pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), NOW
    )
    assert [row["player_id"] for row in rows] == [1, 2]
    assert rows[0]["jersey"] == 17 and rows[0]["college"] == "Wyoming" and rows[0]["draft_pick"] == 7
    assert rows[0]["birth_date"] == "1998-05-17"
    assert rows[1]["jersey"] is None
    assert rows[1]["contract_apy"] is None
    assert set(rows[0]) == set(rows[1])


def test_missing_play_by_play_rates_on_the_scoreboard_alone():
    rows = tr.team_game_rows(pd.DataFrame(), schedule(GAMES))
    ratings = tr.rate(rows)
    # BBB outscored opponents by 34 in two games; AAA by -23.
    assert ratings["BBB"].rating == pytest.approx(34 / 2 - 0, abs=6)
    assert ratings["BBB"].rating > ratings["AAA"].rating
    assert abs(ratings["BBB"].rating) > 5
