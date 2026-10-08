import json
import math
from datetime import datetime, timedelta, timezone

import pandas as pd
import pytest

import ingest_enrichment as ie
import team_ratings as tr

NOW = datetime(2026, 10, 8, tzinfo=timezone.utc)


# ---- ratings fixtures -----------------------------------------------------------
def schedule(games, season=2026):
    """(week, away, home, away_score, home_score, overtime) -> a games frame."""
    return pd.DataFrame([
        {
            "game_id": f"{season}02{index:04d}", "week": week, "away_team": away, "home_team": home,
            "away_score": away_score, "home_score": home_score, "overtime": overtime,
        }
        for index, (week, away, home, away_score, home_score, overtime) in enumerate(games, start=1)
    ])


def totals_for(games, xg_by_team, season=2026):
    """Shot-file totals: each club creates its fixed xG, goals follow the score."""
    rows = {}
    for index, (_week, away, home, away_score, home_score, _ot) in enumerate(games, start=1):
        if away_score is None:
            continue
        rows[20000 + index] = {
            "away_xg": xg_by_team[away], "home_xg": xg_by_team[home],
            "away_goals": away_score, "home_goals": home_score, "last_goal": 3000.0,
        }
    return pd.DataFrame.from_dict(rows, orient="index")


GAMES = [
    (1, "AAA", "BBB", 1, 4, False),
    (1, "CCC", "DDD", 2, 2 + 1, True),   # CCC loses in overtime
    (2, "BBB", "CCC", 2, 3, False),
    (2, "DDD", "AAA", 2, 1, False),
]
XG = {"AAA": 2.0, "BBB": 3.4, "CCC": 2.8, "DDD": 3.0}


def rated(games=GAMES, xg=XG, **kwargs):
    rows = tr.team_game_rows(schedule(games), totals_for(games, xg))
    return tr.rate(rows, **kwargs), rows


# ---- shot totals ------------------------------------------------------------------
def test_shot_totals_sum_xg_and_goals_by_side_and_find_the_last_goal():
    shots = pd.DataFrame([
        {"game_id": 20001, "team": "AWAY", "xGoal": 0.2, "goal": 0, "time": 100},
        {"game_id": 20001, "team": "AWAY", "xGoal": 0.3, "goal": 1, "time": 400},
        {"game_id": 20001, "team": "HOME", "xGoal": 0.5, "goal": 1, "time": 3700},
        {"game_id": 20002, "team": "HOME", "xGoal": 0.1, "goal": 0, "time": 50},
    ])
    totals = tr.game_shot_totals(shots)
    first = totals.loc[20001]
    assert (first["away_xg"], first["home_xg"]) == pytest.approx((0.5, 0.5))
    assert (first["away_goals"], first["home_goals"], first["last_goal"]) == (1, 1, 3700)
    assert totals.loc[20002]["away_xg"] == 0 and totals.loc[20002]["last_goal"] == 0
    assert tr.game_shot_totals(shots.iloc[0:0]).empty


def test_a_shootout_counts_its_regulation_and_overtime_goals_tied():
    games = [(1, "AAA", "BBB", 2, 3, True)]
    totals = pd.DataFrame([{"away_xg": 2.0, "home_xg": 2.5, "away_goals": 2, "home_goals": 2, "last_goal": 3400.0}],
                          index=[20001])
    rows = tr.team_game_rows(schedule(games), totals)
    home = rows[rows["team"] == "BBB"].iloc[0]
    assert home["goals_for"] == 2 and home["score_for"] == 3  # the shootout goal is a tiebreak, not scoring
    assert home["seconds"] == tr.SHOOTOUT_SECONDS


def test_game_length_is_what_was_played():
    assert tr.game_seconds(False, False, 0) == 3600
    assert tr.game_seconds(True, True, 3400) == 3900
    assert tr.game_seconds(True, False, 3745) == 3745


def test_games_without_shot_data_or_a_score_are_skipped():
    games = GAMES + [(3, "AAA", "BBB", None, None, False)]
    rows = tr.team_game_rows(schedule(games), totals_for(GAMES, XG))
    assert len(rows) == 8
    assert tr.team_game_rows(schedule(GAMES), pd.DataFrame()).empty


# ---- rating math ------------------------------------------------------------------
def test_ratings_read_like_a_goal_line_and_centre_on_zero():
    ratings, _ = rated()
    assert set(ratings) == {"AAA", "BBB", "CCC", "DDD"}
    assert sum(r.rating for r in ratings.values()) == pytest.approx(0, abs=1e-9)
    assert ratings["BBB"].rating > ratings["CCC"].rating > ratings["AAA"].rating
    for r in ratings.values():
        assert r.rating == pytest.approx(r.offense + r.defense)


def test_offense_and_defense_blend_expected_goals_and_goals_evenly():
    # One game a club: no schedule adjustment, so the pure blend shows through.
    one = [(1, "AAA", "BBB", 1, 4, False), (1, "CCC", "DDD", 2, 2, False)]
    rows = tr.team_game_rows(schedule(one), totals_for(one, {"AAA": 2.0, "BBB": 3.0, "CCC": 2.5, "DDD": 2.5}))
    single = tr.rate(rows)
    league_xg = (2.0 + 3.0 + 2.5 + 2.5) / 4
    league_goals = (1 + 4 + 2 + 2) / 4
    expected = 0.5 * (3.0 - league_xg) + 0.5 * (4 - league_goals)
    assert single["BBB"].offense == pytest.approx(expected)
    allowed = 0.5 * (league_xg - 2.0) + 0.5 * (league_goals - 1)
    assert single["BBB"].defense == pytest.approx(allowed)


def test_record_counts_overtime_losses_apart_from_regulation_losses():
    ratings, _ = rated()
    assert (ratings["BBB"].wins, ratings["BBB"].losses, ratings["BBB"].otl) == (1, 1, 0)
    assert (ratings["CCC"].wins, ratings["CCC"].losses, ratings["CCC"].otl) == (1, 0, 1)
    assert (ratings["DDD"].wins, ratings["DDD"].losses, ratings["DDD"].otl) == (2, 0, 0)
    assert ratings["AAA"].goals_for == 2 and ratings["AAA"].goals_against == 6  # official scores


def test_schedule_adjustment_ramps_in_over_twenty_games():
    assert tr.sos_weight(1) == 0
    assert tr.sos_weight(tr.FULL_SOS_GAMES) == 1
    assert tr.sos_weight(82) == 1
    assert 0 < tr.sos_weight(10) < 1


def test_schedule_adjustment_is_off_after_one_game_and_moves_ratings_when_full():
    one = [(1, "AAA", "BBB", 1, 4, False), (1, "CCC", "DDD", 2, 2, False)]
    rows = tr.team_game_rows(schedule(one), totals_for(one, XG))
    assert all(r.schedule == pytest.approx(0) for r in tr.rate(rows).values())
    triangle = [(1, "AAA", "BBB", 0, 3, False), (2, "BBB", "CCC", 1, 2, False), (3, "CCC", "AAA", 1, 4, False)]
    rows = tr.team_game_rows(schedule(triangle), totals_for(triangle, {"AAA": 3.0, "BBB": 2.0, "CCC": 2.5}))
    full = tr.rate(rows, full_schedule_weight=True)
    assert any(abs(r.schedule) > 1e-6 for r in full.values())
    assert sum(r.rating for r in full.values()) == pytest.approx(0, abs=1e-9)


def test_last_season_counts_as_twenty_games_of_evidence():
    assert tr.prior_weight(0) == 1
    assert tr.prior_weight(20) == pytest.approx(0.5)
    assert tr.prior_weight(82) == pytest.approx(20 / 102)
    assert tr.prior_weight(1) > tr.prior_weight(2) > tr.prior_weight(8)


def test_prior_is_regressed_and_this_season_is_shrunk():
    prior, _ = rated(full_schedule_weight=True)
    current, rows = rated(prior=prior)
    plain = tr.rate(rows)
    weight = tr.prior_weight(current["BBB"].games)
    expected_offense = (
        (1 - weight) * tr.CURRENT_SHRINK * plain["BBB"].offense
        + weight * prior["BBB"].offense * tr.PRIOR_REGRESSION
    )
    assert current["BBB"].prior_weight == pytest.approx(weight)
    assert current["BBB"].offense == pytest.approx(expected_offense)
    assert prior["BBB"].prior_weight == 0


def test_preseason_is_last_season_regressed_halfway():
    prior, _ = rated(full_schedule_weight=True)
    start = tr.preseason(prior)
    assert start["BBB"].rating == pytest.approx(prior["BBB"].rating * 0.5)
    assert start["BBB"].games == 0 and start["BBB"].prior_weight == 1


# ---- projections ------------------------------------------------------------------
def test_home_ice_is_worth_a_fifth_of_a_goal():
    even = tr.average_club("X")
    margin, win = tr.project(even, even)
    assert margin == pytest.approx(0.2)
    assert win == pytest.approx(1 / (1 + math.exp(-0.2 / 0.9)))
    margin, win = tr.project(even, even, neutral=True)
    assert margin == 0 and win == pytest.approx(0.5)


def test_a_one_goal_edge_is_about_a_seventy_five_twenty_five_game():
    strong = tr.TeamRating("S", 10, 1.0, 0.5, 0.5, 0, 0, 0, 0, 0, 0, 0)
    weak = tr.average_club("W")
    margin, win = tr.project(strong, weak, neutral=True)
    assert margin == pytest.approx(1.0)
    assert win == pytest.approx(0.752, abs=0.002)
    _, reverse = tr.project(weak, strong, neutral=True)
    assert reverse == pytest.approx(1 - win)


def test_team_ratings_rows_rank_and_project_unplayed_games():
    played = GAMES
    upcoming = [(3, "AAA", "BBB", None, None, False), (3, "CCC", "DDD", None, None, False)]
    teams, projections = ie.build_team_ratings(
        2026, schedule(played + upcoming), totals_for(played, XG),
        schedule(played, 2025), totals_for(played, XG), NOW,
    )
    assert [row["rank"] for row in teams] == [1, 2, 3, 4]
    assert teams[0]["team"] == "BBB"
    assert teams[0]["through_week"] == 2
    assert {p["game_id"] for p in projections} == {"2026020005", "2026020006"}
    assert all(0 < p["home_win_prob"] < 1 for p in projections)
    ccc = next(r for r in teams if r["team"] == "CCC")
    assert (ccc["wins"], ccc["losses"], ccc["ties"]) == (1, 0, 1)
    assert (ccc["points_for"], ccc["points_against"]) == (5, 5)
    home_bbb = next(p for p in projections if p["home_team"] == "BBB")
    assert home_bbb["home_margin"] > 0 and home_bbb["home_win_prob"] > 0.5


def test_a_season_with_no_finals_starts_from_last_season_and_rates_every_club():
    upcoming = [(1, "AAA", "BBB", None, None, False), (1, "EEE", "CCC", None, None, False)]
    teams, projections = ie.build_team_ratings(
        2026, schedule(upcoming), pd.DataFrame(), schedule(GAMES, 2025), totals_for(GAMES, XG), NOW,
    )
    assert {row["team"] for row in teams} == {"AAA", "BBB", "CCC", "EEE"}  # DDD is off the schedule
    assert all(row["games"] == 0 and row["through_week"] == 0 for row in teams)
    assert next(r for r in teams if r["team"] == "EEE")["rating"] == 0  # a new club starts average
    assert len(projections) == 2
    assert sorted(r["rank"] for r in teams) == [1, 2, 3, 4]


# ---- profiles -----------------------------------------------------------------------
LANDING = {
    "playerId": 8478402, "sweaterNumber": 97, "heightInInches": 74, "weightInPounds": 193,
    "birthDate": "1997-01-13", "birthCity": {"default": "Richmond Hill"},
    "birthStateProvince": {"default": "Ontario", "fr": "Ontario"}, "birthCountry": "CAN",
    "draftDetails": {"year": 2015, "teamAbbrev": "EDM", "round": 1, "pickInRound": 1, "overallPick": 1},
    "seasonTotals": [
        {"season": 20112012, "leagueAbbrev": "OHL"},
        {"season": 20152016, "leagueAbbrev": "NHL"},
        {"season": 20162017, "leagueAbbrev": "NHL"},
    ],
}


def test_birthplace_uses_region_codes_for_canada_and_the_us_only():
    assert ie.birthplace(LANDING) == "Richmond Hill, ON, CAN"
    us = {"birthCity": {"default": "Buffalo"}, "birthStateProvince": {"default": "New York"}, "birthCountry": "USA"}
    assert ie.birthplace(us) == "Buffalo, NY, USA"
    sweden = {"birthCity": {"default": "Gavle"}, "birthStateProvince": {"default": "Gavleborgs lan"}, "birthCountry": "SWE"}
    assert ie.birthplace(sweden) == "Gavle, SWE"
    assert ie.birthplace({"birthCity": {"default": "Prague"}, "birthCountry": "CZE"}) == "Prague, CZE"
    assert ie.birthplace({"birthCountry": "CAN"}) is None


def test_landing_gives_bio_draft_and_the_first_nhl_season():
    bio = ie.parse_landing(LANDING)
    assert bio["jersey"] == 97 and bio["height_in"] == 74 and bio["weight_lb"] == 193
    assert bio["birth_date"] == "1997-01-13" and bio["rookie_season"] == 2015
    assert (bio["draft_year"], bio["draft_round"], bio["draft_pick"], bio["draft_team"]) == (2015, 1, 1, "EDM")
    undrafted = ie.parse_landing({"sweaterNumber": 7})
    assert undrafted["draft_year"] is None and undrafted["rookie_season"] is None and undrafted["birthplace"] is None


def test_bios_are_cached_for_thirty_days(tmp_path, monkeypatch):
    monkeypatch.setattr(ie, "PROFILE_CACHE_DIR", tmp_path)
    monkeypatch.delenv("HOCKEY_NO_CACHE", raising=False)
    calls = []

    def fake_get(url, params=None, cache=False):
        calls.append(url)
        return json.dumps(LANDING).encode()

    monkeypatch.setattr(ie, "http_get", fake_get)
    assert ie.load_bio(8478402, NOW)["jersey"] == 97
    assert ie.load_bio(8478402, NOW + timedelta(days=29))["jersey"] == 97
    assert len(calls) == 1
    assert ie.load_bio(8478402, NOW + timedelta(days=31))["jersey"] == 97
    assert len(calls) == 2


def test_a_missing_bio_is_empty_and_not_cached(tmp_path, monkeypatch):
    monkeypatch.setattr(ie, "PROFILE_CACHE_DIR", tmp_path)
    monkeypatch.delenv("HOCKEY_NO_CACHE", raising=False)
    monkeypatch.setattr(ie, "http_get", lambda url, params=None, cache=False: None)
    assert ie.load_bio(1, NOW) == {}
    assert list(tmp_path.iterdir()) == []

    def boom(url, params=None, cache=False):
        raise RuntimeError("down")

    monkeypatch.setattr(ie, "http_get", boom)
    assert ie.load_bio(1, NOW) == {}


def logs_frame():
    def row(pid, team, kind, date, toi):
        return {"player_id": pid, "team": team, "player_type": kind, "game_date": date, "toi": toi}

    return pd.DataFrame([
        row(1, "EDM", "f", "2026-10-01", 1200), row(1, "EDM", "f", "2026-10-03", 1300),
        row(2, "EDM", "d", "2026-10-01", 1500), row(2, "EDM", "d", "2026-10-03", 1500),
        row(3, "EDM", "g", "2026-10-01", 3600),
        # Traded: two games in Toronto, then a game in Edmonton.
        row(4, "TOR", "f", "2026-10-01", 900), row(4, "TOR", "f", "2026-10-02", 900),
        row(4, "EDM", "f", "2026-10-03", 1000),
        row(5, "EDM", "f", "2026-10-03", 0),
    ])


def test_ice_time_totals_per_game_and_share_of_the_clubs_skater_time():
    ice = ie.ice_time(logs_frame())
    assert ice[1]["toi_seconds"] == 2500 and ice[1]["toi_per_gp"] == 1250.0
    edmonton_skaters = 1200 + 1300 + 1500 + 1500 + 1000
    assert ice[1]["toi_share"] == pytest.approx(2500 / edmonton_skaters, abs=1e-4)
    assert ice[3]["toi_seconds"] == 3600 and ice[3]["toi_share"] is None  # goalies have no skater share
    # A traded player's share is his time with the latest club over that club's total.
    assert ice[4]["toi_seconds"] == 2800
    assert ice[4]["toi_share"] == pytest.approx(1000 / edmonton_skaters, abs=1e-4)
    assert 5 not in ice  # played no minutes
    assert ie.ice_time(pd.DataFrame()) == {}


def test_special_teams_ice_time_comes_from_the_five_on_four_rows():
    skaters = pd.DataFrame([
        {"playerId": 1, "situation": "all", "icetime": 9000.0},
        {"playerId": 1, "situation": "5on4", "icetime": 1234.4},
        {"playerId": 1, "situation": "4on5", "icetime": 300.0},
        {"playerId": 2, "situation": "5on4", "icetime": 60.0},
    ])
    special = ie.special_teams_toi(skaters)
    assert special[1] == {"pp_toi_seconds": 1234, "pk_toi_seconds": 300}
    assert special[2] == {"pp_toi_seconds": 60}
    assert ie.special_teams_toi(pd.DataFrame()) == {}


def test_profiles_cover_every_requested_player_even_without_sources():
    bios = {1: ie.parse_landing(LANDING)}
    ice = ie.ice_time(logs_frame())
    rows = ie.build_player_profiles(2026, {1, 99}, bios, ice, {1: {"pp_toi_seconds": 100, "pk_toi_seconds": 5}}, NOW)
    assert [row["player_id"] for row in rows] == [1, 99]
    first, nobody = rows
    assert first["jersey"] == 97 and first["birthplace"] == "Richmond Hill, ON, CAN"
    assert first["rookie_season"] == 2015 and first["years_exp"] == 11
    assert first["toi_per_gp"] == 1250.0 and first["pp_toi_seconds"] == 100 and first["pk_toi_seconds"] == 5
    assert all(value is None for key, value in nobody.items() if key not in ("player_id", "season", "updated_at"))
    assert set(first) == set(nobody)
    assert not any(key.startswith(("contract", "injury", "snap")) for key in first)
    only_logs = ie.build_player_profiles(2026, {2}, {}, ice, {}, NOW)[0]
    assert only_logs["toi_seconds"] == 3000 and only_logs["jersey"] is None  # ice time needs no bio


def test_a_rookie_has_zero_years_of_experience():
    bio = {"rookie_season": 2026}
    row = ie.build_player_profiles(2026, {9}, {9: bio}, {}, {}, NOW)[0]
    assert row["years_exp"] == 0
