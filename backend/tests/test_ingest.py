import json
import os
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest

import ingest

NOW = datetime(2026, 10, 8, tzinfo=timezone.utc)
CATEGORIES = {"Scoring", "Shot Quality", "Play Driving", "Goaltending"}


# --------------------------------------------------------------------------- #
# Synthetic MoneyPuck frames
# --------------------------------------------------------------------------- #
SKATER_DEFAULTS = {
    "games": 70, "icetime": 84000.0, "game_score": 70.0, "goals": 30.0,
    "assists1": 20.0, "assists2": 10.0, "points": 60.0, "sog": 200.0,
    "shot_attempts": 350.0, "ixg": 25.0, "hd_shots": 40.0, "unblocked": 280.0,
    "rebounds_created": 15.0, "blocks": 20.0, "hits": 50.0, "takeaways": 30.0,
    "giveaways": 40.0, "pim_mp": 20.0, "fo_won": 300.0, "fo_lost": 300.0,
}
SKATER_5V5_DEFAULTS = {
    "icetime_5v5": 60000.0, "xgf_5v5": 40.0, "xga_5v5": 30.0, "gf_5v5": 35.0,
    "ga_5v5": 30.0, "cf_5v5": 500.0, "ca_5v5": 400.0, "hdf_5v5": 60.0,
    "hda_5v5": 40.0, "off_xgf_5v5": 50.0, "off_xga_5v5": 60.0,
    "off_cf_5v5": 600.0, "off_ca_5v5": 600.0,
}
GOALIE_DEFAULTS = {
    "games": 50, "icetime": 180000.0, "xgoals_against": 130.0,
    "goals_against": 115.0, "shots_against": 1300.0, "hd_shots_against": 200.0,
    "hd_goals_against": 40.0, "rebounds_against": 130.0,
}
SKATER_COLS = {dst: src for src, dst in ingest.SKATER_ALL.items()}
SKATER_5V5_COLS = {dst: src for src, dst in ingest.SKATER_5V5.items()}
GOALIE_COLS = {dst: src for src, dst in ingest.GOALIE_ALL.items()}


def skater_rows(pid, name="Skater", team="EDM", pos="C", season=2025,
                five_on_five=True, **overrides):
    """The MoneyPuck situation rows for one skater (all, 5on5, 5on4, other)."""
    base = {"playerId": pid, "season": season, "name": name, "team": team, "position": pos}
    values = {**SKATER_DEFAULTS, **{k: v for k, v in overrides.items() if k in SKATER_DEFAULTS}}
    five = {**SKATER_5V5_DEFAULTS, **{k: v for k, v in overrides.items() if k in SKATER_5V5_DEFAULTS}}
    all_row = {**base, "situation": "all", **{SKATER_COLS[k]: v for k, v in values.items()}}
    rows = [all_row]
    if five_on_five:
        rows.append({**base, "situation": "5on5", **{SKATER_5V5_COLS[k]: v for k, v in five.items()}})
    rows.append({**base, "situation": "5on4", "I_F_points": overrides.get("pp_points", 20.0)})
    # The "other" situation must never leak into the totals.
    rows.append({**base, "situation": "other", "I_F_points": 999.0, "icetime": 999.0})
    return rows


def goalie_rows(pid, name="Goalie", team="NYR", season=2025, **overrides):
    base = {"playerId": pid, "season": season, "name": name, "team": team, "position": "G"}
    values = {**GOALIE_DEFAULTS, **overrides}
    return [
        {**base, "situation": "all", **{GOALIE_COLS[k]: v for k, v in values.items()}},
        {**base, "situation": "5on5", "goals": 999.0, "icetime": 999.0},
    ]


def frame(*groups) -> pd.DataFrame:
    return pd.DataFrame([row for group in groups for row in group])


@pytest.fixture
def skaters() -> pd.DataFrame:
    return frame(
        skater_rows(1, "Fwd One", "EDM", "C"),
        skater_rows(2, "Fwd Two", "EDM", "L", icetime=72000.0, points=30.0, goals=10.0),
        skater_rows(3, "Dman One", "NYR", "D", points=40.0, goals=8.0, giveaways=10.0),
        skater_rows(4, "Dman Two", "NYR", "D", points=20.0, goals=2.0, giveaways=50.0),
        skater_rows(5, "Fringe", "NYR", "R", icetime=6000.0, games=10),
    )


@pytest.fixture
def goalies() -> pd.DataFrame:
    return frame(
        goalie_rows(10, "Goalie One"),
        goalie_rows(11, "Goalie Two", goals_against=140.0, xgoals_against=120.0),
    )


@pytest.fixture
def skater_summary() -> pd.DataFrame:
    return pd.DataFrame([
        {"playerId": 1, "gameWinningGoals": 5, "ppGoals": 9, "ppPoints": 22, "shGoals": 1,
         "plusMinus": 17, "penaltyMinutes": 44, "shootsCatches": "L"},
        {"playerId": 3, "gameWinningGoals": 1, "ppGoals": 0, "ppPoints": 3, "shGoals": 0,
         "plusMinus": -4, "penaltyMinutes": 30, "shootsCatches": "R"},
    ])


@pytest.fixture
def goalie_summary() -> pd.DataFrame:
    return pd.DataFrame([
        {"playerId": 10, "gamesStarted": 49, "wins": 27, "losses": 17, "otLosses": 6,
         "shutouts": 3, "shootsCatches": "L"},
        {"playerId": 11, "gamesStarted": 45, "wins": 20, "losses": 20, "otLosses": 5,
         "shutouts": 1, "shootsCatches": "R"},
    ])


@pytest.fixture
def agg(skaters, goalies, skater_summary, goalie_summary) -> pd.DataFrame:
    return ingest.build_agg(skaters, goalies, skater_summary, goalie_summary)


def metric(row: dict, category: str, mid: str) -> dict:
    return next(m for m in row["metrics"] if m["id"].endswith(f"-{mid}") and m["category"] == category)


# --------------------------------------------------------------------------- #
# Season resolution
# --------------------------------------------------------------------------- #
def test_resolve_season_cli_wins():
    assert ingest.resolve_season(2022) == 2022


def test_resolve_season_env():
    with patch.dict(os.environ, {"STATCAST_SEASON": "2021"}, clear=False):
        assert ingest.resolve_season(None) == 2021


def test_resolve_season_out_of_range_falls_back():
    assert ingest.resolve_season(2007) == ingest.DEFAULT_SEASON
    assert ingest.resolve_season(ingest.DEFAULT_SEASON + 5) == ingest.DEFAULT_SEASON
    with patch.dict(os.environ, {"STATCAST_SEASON": "abc"}, clear=False):
        assert ingest.resolve_season(None) == ingest.DEFAULT_SEASON


def test_oldest_season_is_moneypucks_floor():
    assert ingest.resolve_season(2008) == 2008
    assert ingest.OLDEST_SUPPORTED_SEASON == 2008


def test_season_id_spans_two_years():
    assert ingest.season_id(2025) == 20252026
    assert ingest.season_id(2008) == 20082009


# --------------------------------------------------------------------------- #
# Identity helpers
# --------------------------------------------------------------------------- #
def test_player_type_from_position():
    for code in ("C", "L", "R", "W"):
        assert ingest.player_type_from_position(code) == "f"
    assert ingest.player_type_from_position("D") == "d"
    assert ingest.player_type_from_position("g") == "g"
    assert ingest.player_type_from_position("") == ""
    assert ingest.player_type_from_position(None) == ""


def test_normalize_team_maps_old_dotted_codes():
    assert ingest.normalize_team("L.A") == "LAK"
    assert ingest.normalize_team("T.B") == "TBL"
    assert ingest.normalize_team("PHX") == "ARI"
    assert ingest.normalize_team("EDM") == "EDM"
    assert ingest.normalize_team(None) == ""
    assert ingest.normalize_team(float("nan")) == ""


def test_headshot_url_uses_season_and_team():
    url = ingest.headshot_url(2025, "EDM", 8478402)
    assert url == "https://assets.nhle.com/mugs/nhl/20252026/EDM/8478402.png"
    assert ingest.headshot_url(2008, "S.J", 1).endswith("/20082009/SJS/1.png")
    assert ingest.headshot_url(2025, "", 1) is None


# --------------------------------------------------------------------------- #
# Value formatting
# --------------------------------------------------------------------------- #
def test_format_value():
    assert ingest.format_value(4918, "comma") == "4,918"
    assert ingest.format_value(27, "int") == "27"
    assert ingest.format_value(54.24, "pct1") == "54.2%"
    assert ingest.format_value(7.86, "dec1") == "7.9"
    assert ingest.format_value(0.176, "dec2") == "0.18"
    assert ingest.format_value(0.1034, "dec3") == "0.103"
    assert ingest.format_value(2.3, "signed1") == "+2.3"
    assert ingest.format_value(-1.2, "signed1") == "-1.2"
    assert ingest.format_value(None, "int") == ""
    assert ingest.format_value(float("nan"), "comma") == ""


def test_signed1_never_prints_negative_zero():
    assert ingest.format_value(-0.04, "signed1") == "+0.0"
    assert ingest.format_value(0.0, "signed1") == "+0.0"


def test_sv3_drops_the_leading_zero():
    assert ingest.format_value(0.9153, "sv3") == ".915"
    assert ingest.format_value(0.9, "sv3") == ".900"
    assert ingest.format_value(1.0, "sv3") == "1.000"
    assert ingest.format_value(0.0, "sv3") == ".000"


def test_format_toi():
    assert ingest.format_toi(1182) == "19:42"
    assert ingest.format_toi(65.4) == "1:05"
    assert ingest.format_toi(None) == ""


# --------------------------------------------------------------------------- #
# Percentile computation (incl. inverted)
# --------------------------------------------------------------------------- #
def test_rank_percentiles_higher_is_better():
    pct = ingest.rank_percentiles(pd.Series({1: 10.0, 2: 20.0, 3: 30.0}), inverted=False)
    assert pct[3] > pct[2] > pct[1]
    assert pct[3] == 100


def test_rank_percentiles_inverted():
    # Lower raw value ranks highest when inverted (giveaways, GA).
    pct = ingest.rank_percentiles(pd.Series({1: 1.0, 2: 2.0, 3: 3.0}), inverted=True)
    assert pct[1] > pct[2] > pct[3]
    assert pct[1] == 100


def test_rank_percentiles_ignores_nan():
    pct = ingest.rank_percentiles(pd.Series({1: 5.0, 2: float("nan"), 3: 15.0}), inverted=False)
    assert 2 not in pct
    assert pct[3] == 100


# --------------------------------------------------------------------------- #
# Qualification thresholds
# --------------------------------------------------------------------------- #
def test_skater_season_threshold_is_200_minutes():
    assert ingest.qualifies({"icetime": 12000, "icetime_5v5": 0}, "Scoring", "f")
    assert not ingest.qualifies({"icetime": 11999, "icetime_5v5": 0}, "Scoring", "f")
    assert ingest.qualifies({"icetime": 12000}, "Shot Quality", "d")


def test_play_driving_also_needs_150_minutes_at_5on5():
    assert ingest.qualifies({"icetime": 20000, "icetime_5v5": 9000}, "Play Driving", "f")
    assert not ingest.qualifies({"icetime": 20000, "icetime_5v5": 8999}, "Play Driving", "f")
    assert not ingest.qualifies({"icetime": 11000, "icetime_5v5": 9000}, "Play Driving", "d")


def test_goalie_qualifies_on_minutes_or_games():
    assert ingest.qualifies({"icetime": 36000, "games": 1}, "Goaltending", "g")
    assert ingest.qualifies({"icetime": 100, "games": 10}, "Goaltending", "g")
    assert not ingest.qualifies({"icetime": 35999, "games": 9}, "Goaltending", "g")


def test_categories_only_apply_to_their_cohorts():
    row = {"icetime": 90000, "icetime_5v5": 90000, "games": 70}
    assert not ingest.qualifies(row, "Goaltending", "f")
    assert not ingest.qualifies(row, "Scoring", "g")
    assert not ingest.qualifies(row, "Scoring", "")


def test_postseason_uses_games():
    assert ingest.qualifies({"games": 4, "icetime": 1}, "Scoring", "f", "POST")
    assert not ingest.qualifies({"games": 3, "icetime": 99999}, "Scoring", "f", "POST")
    assert ingest.qualifies({"games": 2}, "Goaltending", "g", "POST")
    assert not ingest.qualifies({"games": 1}, "Goaltending", "g", "POST")


def test_career_thresholds_are_games_and_higher_than_season():
    assert ingest.qualifies({"games": 300}, "Scoring", "f", career=True)
    assert not ingest.qualifies({"games": 299, "icetime": 10**7}, "Scoring", "f", career=True)
    assert ingest.qualifies({"games": 100}, "Goaltending", "g", career=True)
    assert not ingest.qualifies({"games": 99}, "Goaltending", "g", career=True)


def test_career_playoff_bar_is_lower_than_career_regular():
    games = ingest.CAREER_POST_QUAL_SKATER_GP
    assert ingest.qualifies({"games": games}, "Scoring", "f", "POST", career=True)
    assert not ingest.qualifies({"games": games}, "Scoring", "f", "REG", career=True)


def test_scale_prorates_only_the_full_season_tier():
    row = {"icetime": 1500, "icetime_5v5": 1200, "games": 5}
    assert not ingest.qualifies(row, "Scoring", "f")
    assert ingest.qualifies(row, "Scoring", "f", scale=0.1)
    assert ingest.qualifies(row, "Play Driving", "f", scale=0.1)
    # Postseason and career bars ignore scale.
    assert not ingest.qualifies({"games": 3}, "Scoring", "f", "POST", scale=0.1)


def test_qualification_scale_follows_the_median_club():
    games = pd.DataFrame({
        "team": ["A", "A", "B", "B", "C", "C"],
        "games": [10, 8, 10, 10, 9, 3],
    })
    scale = ingest.qualification_scale(games, ingest.DEFAULT_SEASON)
    assert scale == pytest.approx(10 / 82)


def test_one_early_game_does_not_move_the_bar_and_the_floor_holds():
    games = pd.DataFrame({"team": ["A", "B", "C"], "games": [1, 1, 1]})
    assert ingest.qualification_scale(games, ingest.DEFAULT_SEASON) == ingest.QUAL_SCALE_FLOOR


def test_a_finished_season_keeps_its_full_bar():
    games = pd.DataFrame({"team": ["A", "B"], "games": [48, 48]})  # the 2012-13 lockout
    assert ingest.qualification_scale(games, ingest.DEFAULT_SEASON - 1) == 1.0
    assert ingest.qualification_scale(pd.DataFrame(), ingest.DEFAULT_SEASON) == 1.0


def test_has_opportunity_needs_volume_and_a_matching_cohort():
    assert ingest.has_opportunity({"games": 1, "icetime": 600}, "Scoring", "f")
    assert not ingest.has_opportunity({"games": 0, "icetime": 0}, "Scoring", "f")
    assert not ingest.has_opportunity({"games": 3, "icetime": 600}, "Goaltending", "f")
    assert not ingest.has_opportunity({"games": 3, "icetime": 600, "icetime_5v5": 0}, "Play Driving", "f")
    assert ingest.has_opportunity({"games": 3, "icetime_5v5": 300}, "Play Driving", "d")


# --------------------------------------------------------------------------- #
# Aggregation: additive totals and derived rates
# --------------------------------------------------------------------------- #
def test_skater_derived_rates(agg):
    row = agg.loc[1]
    assert row["player_type"] == "f"
    assert row["points_per_60"] == pytest.approx(60 / (84000 / 3600))
    assert row["gax"] == pytest.approx(30 - 25.0)
    assert row["shooting_pct"] == pytest.approx(15.0)
    assert row["xg_per_shot"] == pytest.approx(25 / 280)
    assert row["assists"] == 30
    assert row["primary_points"] == 50
    assert row["pp_points"] == 20
    assert row["game_score_per_gp"] == pytest.approx(1.0)


def test_play_driving_rates_come_from_5on5_counts(agg):
    row = agg.loc[1]
    assert row["xgf_pct"] == pytest.approx(40 / 70 * 100)
    assert row["rel_xgf_pct"] == pytest.approx(40 / 70 * 100 - 50 / 110 * 100)
    assert row["cf_pct"] == pytest.approx(500 / 900 * 100)
    assert row["rel_cf_pct"] == pytest.approx(500 / 900 * 100 - 50.0)
    assert row["hdcf_pct"] == pytest.approx(60.0)
    assert row["gf_pct"] == pytest.approx(35 / 65 * 100)
    assert row["xgf_per_60"] == pytest.approx(40 / (60000 / 3600))
    assert row["xga_per_60"] == pytest.approx(30 / (60000 / 3600))


def test_the_other_situation_never_leaks_into_totals(agg):
    assert agg.loc[1, "points"] == 60  # not 60 + 999
    assert agg.loc[1, "icetime"] == 84000


def test_goalie_derived_rates(agg):
    row = agg.loc[10]
    assert row["player_type"] == "g"
    assert row["gsax"] == pytest.approx(130 - 115)
    assert row["gsax_per_60"] == pytest.approx(15 / 50)
    assert row["sv_pct"] == pytest.approx(1 - 115 / 1300)
    assert row["gaa"] == pytest.approx(115 / 50)
    assert row["hd_sv_pct"] == pytest.approx(1 - 40 / 200)
    assert row["g_xga_per_60"] == pytest.approx(130 / 50)
    assert row["rebound_pct"] == pytest.approx(10.0)
    assert row["saves"] == 1185
    assert row["wins"] == 27 and row["shutouts"] == 3


def test_summary_fields_merge_by_player_id(agg):
    assert agg.loc[1, "plus_minus"] == 17
    assert agg.loc[1, "handedness"] == "L"
    assert agg.loc[3, "handedness"] == "R"
    assert pd.isna(agg.loc[2, "plus_minus"])
    assert agg.loc[2, "handedness"] == ""


def test_headshots_use_the_latest_season_and_team(agg):
    assert agg.loc[1, "image_url"].endswith("/20252026/EDM/1.png")


def test_build_agg_without_summary_still_builds(skaters, goalies):
    out = ingest.build_agg(skaters, goalies)
    assert set(out["player_type"]) == {"f", "d", "g"}
    assert "plus_minus" not in out.columns or out["plus_minus"].isna().all()


def test_build_agg_empty_inputs():
    assert ingest.build_agg(pd.DataFrame(), pd.DataFrame()).empty
    assert ingest.build_agg(None, None).empty


def test_career_pools_seasons_before_deriving_rates():
    older = frame(skater_rows(1, season=2023, team="T.B", ixg=10.0, goals=20.0, icetime=60000.0, games=60))
    newer = frame(skater_rows(1, season=2024, team="EDM", ixg=30.0, goals=20.0, icetime=60000.0, games=60))
    out = ingest.build_agg(pd.concat([older, newer], ignore_index=True), pd.DataFrame())
    row = out.loc[1]
    assert row["games"] == 120
    assert row["goals"] == 40
    assert row["ixg"] == pytest.approx(40.0)
    assert row["ixg_per_60"] == pytest.approx(40.0 / (120000 / 3600))
    assert row["team"] == "EDM"                 # latest season's team
    assert row["image_url"].endswith("/20242025/EDM/1.png")


def test_a_traded_player_in_both_files_keeps_his_busier_role():
    sk = frame(skater_rows(7, icetime=300.0, games=2))
    go = frame(goalie_rows(7))
    out = ingest.build_agg(sk, go)
    assert out.loc[7, "player_type"] == "g"


# --------------------------------------------------------------------------- #
# Standard stats
# --------------------------------------------------------------------------- #
def stats_by_label(row) -> dict:
    return {s["label"]: s["value"] for s in ingest.build_standard_stats(row)}


def test_skater_standard_stats(agg):
    stats = stats_by_label(agg.loc[1])
    assert stats["GP"] == "70"
    assert stats["G"] == "30" and stats["A"] == "30" and stats["P"] == "60"
    assert stats["+/-"] == "+17"
    assert stats["PIM"] == "44"          # NHL summary wins over MoneyPuck's 20
    assert stats["PPG"] == "9" and stats["PPP"] == "22"
    assert stats["SHG"] == "1" and stats["GWG"] == "5"
    assert stats["SOG"] == "200" and stats["Sh%"] == "15.0%"
    assert stats["TOI/GP"] == "20:00"
    assert stats["Hits"] == "50" and stats["Blk"] == "20"
    assert stats["FO%"] == "50.0%"


def test_standard_stats_omit_what_has_no_source(agg):
    stats = stats_by_label(agg.loc[2])
    assert "+/-" not in stats and "PPP" not in stats and "GWG" not in stats
    assert stats["PIM"] == "20"          # falls back to MoneyPuck
    assert stats["G"] == "10"


def test_faceoff_pct_needs_fifty_faceoffs(skaters):
    sk = frame(skater_rows(1, fo_won=20.0, fo_lost=29.0))
    out = ingest.build_agg(sk, pd.DataFrame())
    assert "FO%" not in stats_by_label(out.loc[1])


def test_negative_plus_minus_keeps_its_sign(agg):
    assert stats_by_label(agg.loc[3])["+/-"] == "-4"


def test_goalie_standard_stats(agg):
    stats = stats_by_label(agg.loc[10])
    assert [s["label"] for s in ingest.build_standard_stats(agg.loc[10])] == [
        "GP", "GS", "W", "L", "OT", "GAA", "SV%", "SO", "SA", "SV",
    ]
    assert stats["GAA"] == "2.30" and stats["SV%"] == ".912"
    assert stats["SA"] == "1300" and stats["SV"] == "1185"
    assert stats["W"] == "27" and stats["SO"] == "3"


# --------------------------------------------------------------------------- #
# Snapshot rows
# --------------------------------------------------------------------------- #
def test_build_snapshot_rows_shape(agg):
    rows = ingest.build_snapshot_rows(agg, 2025, NOW, "REG")
    by_id = {r["id"]: r for r in rows}
    assert set(by_id) == {1, 2, 3, 4, 10, 11}          # the fringe skater is unqualified
    row = by_id[1]
    assert row["season"] == 2025 and row["season_type"] == "REG"
    assert row["source"] == "moneypuck"
    assert row["player_type"] == "f" and row["position"] == "C"
    assert row["handedness"] == "L" and row["team"] == "EDM"
    assert row["games"] == [] and row["updated_at"] == NOW.isoformat()
    assert {m["category"] for m in row["metrics"]} == {"Scoring", "Shot Quality", "Play Driving"}
    assert {m["category"] for m in by_id[10]["metrics"]} == {"Goaltending"}
    assert all("qualified" not in m for m in row["metrics"])


def test_metric_ids_and_categories_follow_the_contract(agg):
    rows = ingest.build_snapshot_rows(agg, 2025, NOW, "REG")
    for row in rows:
        for m in row["metrics"]:
            assert m["category"] in CATEGORIES
            slug = m["category"].lower().replace(" ", "-")
            assert m["id"].startswith(f"{slug}-{row['id']}-")
            assert 1 <= m["percentile"] <= 100
    assert metric(next(r for r in rows if r["id"] == 1), "Shot Quality", "ixg")["id"] == "shot-quality-1-ixg"


def test_value_formatting(agg):
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(agg, 2025, NOW, "REG")}
    assert metric(rows[1], "Shot Quality", "gax")["value"] == "+5.0"
    assert metric(rows[1], "Shot Quality", "xg_per_shot")["value"] == "0.089"
    assert metric(rows[1], "Play Driving", "xgf_pct")["value"] == "57.1%"
    assert metric(rows[10], "Goaltending", "sv_pct")["value"] == ".912"
    assert metric(rows[10], "Goaltending", "gsax")["value"] == "+15.0"


def test_percentiles_are_ranked_inside_the_cohort(agg):
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(agg, 2025, NOW, "REG")}
    # Defensemen: 3 has more points than 4. Forwards: 1 has more than 2.
    assert metric(rows[3], "Scoring", "points")["percentile"] == 100
    assert metric(rows[4], "Scoring", "points")["percentile"] == 50
    assert metric(rows[1], "Scoring", "points")["percentile"] == 100
    assert metric(rows[2], "Scoring", "points")["percentile"] == 50


def test_inverted_metrics_rank_low_values_higher(agg):
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(agg, 2025, NOW, "REG")}
    # Dman 3 has 10 giveaways, dman 4 has 50.
    assert metric(rows[3], "Play Driving", "giveaways")["percentile"] == 100
    assert metric(rows[4], "Play Driving", "giveaways")["percentile"] == 50
    # Goalie 10 allowed fewer goals than goalie 11.
    assert metric(rows[10], "Goaltending", "goals_against")["percentile"] == 100
    assert metric(rows[10], "Goaltending", "gaa")["percentile"] == 100


def test_goalie_workload_is_not_inverted(agg):
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(agg, 2025, NOW, "REG")}
    # Same icetime and shots; goalie 11 has the lower xGA so goalie 10 is busier.
    assert metric(rows[10], "Goaltending", "xga_per_60")["percentile"] == 100


def test_xga_per_60_is_inverted_for_skaters_only(agg):
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(agg, 2025, NOW, "REG")}
    # Skaters all share the same 5on5 xGA/60 here, so ties split to 50 either way.
    assert metric(rows[1], "Play Driving", "xga_per_60")["label"] == "xGA/60"


def test_missing_values_are_skipped_not_zeroed(skaters):
    sk = skaters[skaters["playerId"] != 5]
    agg = ingest.build_agg(sk, pd.DataFrame())              # no summary, no goalies
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(agg, 2025, NOW, "REG")}
    assert not any(m["id"].endswith("-wins") for m in rows[1]["metrics"])


def test_skater_without_5on5_ice_time_has_no_play_driving():
    sk = frame(skater_rows(1, five_on_five=False))
    agg = ingest.build_agg(sk, pd.DataFrame())
    rows = ingest.build_snapshot_rows(agg, 2025, NOW, "REG")
    assert {m["category"] for m in rows[0]["metrics"]} == {"Scoring", "Shot Quality"}


def test_postseason_rows_use_the_games_bar(skaters):
    sk = frame(skater_rows(1, games=4, icetime=300.0), skater_rows(2, games=3, icetime=9000.0))
    agg = ingest.build_agg(sk, pd.DataFrame())
    rows = ingest.build_snapshot_rows(agg, 2025, NOW, "POST")
    assert [r["id"] for r in rows] == [1]
    assert rows[0]["season_type"] == "POST"


def test_live_season_ships_every_player_with_a_qualified_flag(skaters, goalies):
    sk = skaters.copy()
    agg = ingest.build_agg(sk, goalies)
    rows = {r["id"]: r for r in ingest.build_snapshot_rows(
        agg, ingest.DEFAULT_SEASON, NOW, "REG", qual_scale=1.0, live=True)}
    assert 5 in rows                                          # the fringe skater ships
    assert all("qualified" in m for r in rows.values() for m in r["metrics"])
    assert all(not m["qualified"] for m in rows[5]["metrics"])
    assert all(m["qualified"] for m in rows[1]["metrics"])
    # A prorated bar lets the fringe skater qualify.
    prorated = {r["id"]: r for r in ingest.build_snapshot_rows(
        agg, ingest.DEFAULT_SEASON, NOW, "REG", qual_scale=0.1, live=True)}
    assert all(m["qualified"] for m in prorated[5]["metrics"])


def test_all_time_season_uses_career_thresholds():
    sk = frame(
        skater_rows(1, games=320, icetime=300000.0),
        skater_rows(2, games=250, icetime=300000.0),
    )
    agg = ingest.build_agg(sk, pd.DataFrame())
    rows = ingest.build_snapshot_rows(agg, ingest.ALL_TIME_SEASON, NOW, "REG")
    assert [r["id"] for r in rows] == [1]
    assert rows[0]["season"] == 0


def test_empty_agg_builds_no_rows():
    assert ingest.build_snapshot_rows(pd.DataFrame(), 2025, NOW) == []


# --------------------------------------------------------------------------- #
# Loaders (network mocked)
# --------------------------------------------------------------------------- #
def test_chunks():
    assert list(ingest.chunks([1, 2, 3, 4, 5], 2)) == [[1, 2], [3, 4], [5]]


class FakeResponse:
    def __init__(self, status=200, content=b"", payload=None):
        self.status_code = status
        self.content = json.dumps(payload).encode() if payload is not None else content

    def raise_for_status(self):
        if self.status_code >= 400:
            raise ingest.requests.HTTPError(str(self.status_code))


def test_http_get_sends_a_named_user_agent_and_caches(tmp_path):
    with patch.object(ingest, "CACHE_DIR", tmp_path), \
            patch.object(ingest, "REQUEST_PAUSE_SECONDS", 0), \
            patch.object(ingest.requests, "get", return_value=FakeResponse(content=b"abc")) as get:
        assert ingest.http_get("https://example.invalid/x.csv", cache=True) == b"abc"
        assert ingest.http_get("https://example.invalid/x.csv", cache=True) == b"abc"
    assert get.call_count == 1
    assert "jackwallner+bb@gmail.com" in get.call_args.kwargs["headers"]["User-Agent"]


def test_http_get_does_not_cache_when_not_asked(tmp_path):
    with patch.object(ingest, "CACHE_DIR", tmp_path), \
            patch.object(ingest, "REQUEST_PAUSE_SECONDS", 0), \
            patch.object(ingest.requests, "get", return_value=FakeResponse(content=b"abc")) as get:
        ingest.http_get("https://example.invalid/y.csv")
        ingest.http_get("https://example.invalid/y.csv")
    assert get.call_count == 2 and not list(tmp_path.iterdir())


def test_http_get_returns_none_on_404(tmp_path):
    with patch.object(ingest, "CACHE_DIR", tmp_path), \
            patch.object(ingest, "REQUEST_PAUSE_SECONDS", 0), \
            patch.object(ingest.requests, "get", return_value=FakeResponse(status=404)):
        assert ingest.http_get("https://example.invalid/z.csv", cache=True) is None


def test_load_moneypuck_reads_only_needed_columns():
    csv = b"playerId,season,name,team,position,situation,icetime,junk\n1,2025,A,EDM,C,all,100,x\n"
    with patch.object(ingest, "http_get", return_value=csv) as get:
        out = ingest.load_moneypuck("skaters", 2025, "POST")
    assert "junk" not in out.columns and out.loc[0, "icetime"] == 100
    assert get.call_args.args[0].endswith("/seasonSummary/2025/playoffs/skaters.csv")


def test_load_moneypuck_missing_phase_is_empty():
    with patch.object(ingest, "http_get", return_value=None):
        assert ingest.load_moneypuck("skaters", 2026, "POST").empty


def test_load_nhl_summary_paginates_until_a_short_page():
    pages = {
        0: {"total": 130, "data": [{"playerId": i} for i in range(100)]},
        100: {"total": 130, "data": [{"playerId": i} for i in range(100, 130)]},
    }
    seen = []

    def fake_get(url, params=None, cache=False):
        seen.append(params)
        return json.dumps(pages[params["start"]]).encode()

    with patch.object(ingest, "http_get", side_effect=fake_get):
        out = ingest.load_nhl_summary("skater", 2025, "REG")
    assert len(out) == 130
    assert [p["start"] for p in seen] == [0, 100]
    assert seen[0]["cayenneExp"] == "seasonId=20252026 and gameTypeId=2"
    assert seen[0]["limit"] == 100


def test_summary_failure_degrades_when_a_status_dict_is_supplied(skaters):
    status: dict = {}
    with patch.object(ingest, "load_moneypuck", return_value=skaters), \
            patch.object(ingest, "load_nhl_summary", side_effect=RuntimeError("boom")):
        sk, _g, sk_sum, _gs = ingest.load_season_sources(2025, "REG", False, status)
    assert not sk.empty and sk_sum.empty and status["summary"] == "degraded"
    with patch.object(ingest, "load_moneypuck", return_value=skaters), \
            patch.object(ingest, "load_nhl_summary", side_effect=RuntimeError("boom")):
        with pytest.raises(RuntimeError):
            ingest.load_season_sources(2025, "REG", False, None)


def test_build_agg_for_season_caches_only_finished_seasons(skaters, goalies):
    calls = []

    def fake_sources(season, season_type, cache, status=None):
        calls.append((season, cache))
        return skaters, goalies, pd.DataFrame(), pd.DataFrame()

    with patch.object(ingest, "load_season_sources", side_effect=fake_sources):
        ingest.build_agg_for_season(2025, "REG")
        ingest.build_agg_for_season(ingest.DEFAULT_SEASON, "REG", live=True)
    assert calls == [(2025, True), (ingest.DEFAULT_SEASON, False)]


# --------------------------------------------------------------------------- #
# main()
# --------------------------------------------------------------------------- #
def test_main_upserts_batches(agg):
    client = MagicMock()
    with patch.object(ingest, "SUPABASE_URL", "http://x"), \
            patch.object(ingest, "SUPABASE_SERVICE_ROLE_KEY", "k"), \
            patch.object(ingest, "create_client", return_value=client), \
            patch.object(ingest, "build_agg_for_season", return_value=agg), \
            patch.object(ingest, "stored_ids", return_value=[]), \
            patch.object(ingest, "chunks", side_effect=lambda lst, n: iter([lst])), \
            patch("sys.argv", ["ingest.py", "--season", "2025", "--season-type", "REG"]):
        ingest.main()
    client.table.assert_any_call("player_snapshots")
    upsert = client.table.return_value.upsert
    assert upsert.called
    assert upsert.call_args.kwargs["on_conflict"] == "id,season,season_type"


def test_main_exits_when_no_rows():
    client = MagicMock()
    with patch.object(ingest, "SUPABASE_URL", "http://x"), \
            patch.object(ingest, "SUPABASE_SERVICE_ROLE_KEY", "k"), \
            patch.object(ingest, "create_client", return_value=client), \
            patch.object(ingest, "build_agg_for_season", return_value=pd.DataFrame()), \
            patch("sys.argv", ["ingest.py", "--season", "2025"]):
        with pytest.raises(SystemExit) as exit_info:
            ingest.main()
    assert exit_info.value.code == 1


def test_stored_ids_pages_past_the_row_cap():
    client = MagicMock()
    chain = client.table.return_value.select.return_value.eq.return_value.eq.return_value.order.return_value
    chain.range.return_value.execute.side_effect = [
        MagicMock(data=[{"id": i} for i in range(1000)]),
        MagicMock(data=[{"id": 1000}]),
    ]
    assert len(ingest.stored_ids(client, 2025, "REG")) == 1001
