import os
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

import ingest
import ingest_game_logs

NOW = datetime(2026, 7, 20, tzinfo=timezone.utc)


# --------------------------------------------------------------------------- #
# Season resolution
# --------------------------------------------------------------------------- #
def test_resolve_season_cli_wins():
    assert ingest.resolve_season(2022) == 2022


def test_resolve_season_env():
    with patch.dict(os.environ, {"STATCAST_SEASON": "2021"}, clear=False):
        assert ingest.resolve_season(None) == 2021


def test_resolve_season_out_of_range_falls_back():
    assert ingest.resolve_season(1990) == ingest.DEFAULT_SEASON
    assert ingest.resolve_season(ingest.DEFAULT_SEASON + 5) == ingest.DEFAULT_SEASON
    with patch.dict(os.environ, {"STATCAST_SEASON": "abc"}, clear=False):
        assert ingest.resolve_season(None) == ingest.DEFAULT_SEASON


# --------------------------------------------------------------------------- #
# GSIS id conversion
# --------------------------------------------------------------------------- #
def test_gsis_to_id():
    assert ingest.gsis_to_id("00-0034796") == 34796
    assert ingest.gsis_to_id("00-0000001") == 1
    assert ingest.gsis_to_id(None) is None
    assert ingest.gsis_to_id("") is None
    assert ingest.gsis_to_id(float("nan")) is None
    assert ingest.gsis_to_id("garbage") is None


def test_player_type_from_position():
    assert ingest.player_type_from_position("QB", "QB") == "qb"
    assert ingest.player_type_from_position("RB", "RB") == "rb"
    assert ingest.player_type_from_position("WR", "WR") == "wr"
    assert ingest.player_type_from_position("TE", "TE") == "te"
    assert ingest.player_type_from_position("OLB", "LB") == "def"
    assert ingest.player_type_from_position("CB", "DB") == "def"
    assert ingest.player_type_from_position("K", "SPEC") == "k"


# --------------------------------------------------------------------------- #
# Value formatting
# --------------------------------------------------------------------------- #
def test_format_value():
    assert ingest.format_value(4918, "comma") == "4,918"
    assert ingest.format_value(27, "int") == "27"
    assert ingest.format_value(68.34, "pct1") == "68.3%"
    assert ingest.format_value(7.86, "dec1") == "7.9"
    assert ingest.format_value(0.176, "dec2") == "0.18"
    assert ingest.format_value(2.3, "signed1") == "+2.3"
    assert ingest.format_value(-1.2, "signed1") == "-1.2"
    assert ingest.format_value(None, "int") == ""
    assert ingest.format_value(float("nan"), "comma") == ""


def test_passer_rating_perfect_and_zero_attempts():
    # Perfect passer rating is capped at 158.3.
    assert ingest.passer_rating(20, 20, 400, 6, 0) == 158.3
    assert ingest.passer_rating(0, 0, 0, 0, 0) is None


# --------------------------------------------------------------------------- #
# Percentile computation (incl. inverted)
# --------------------------------------------------------------------------- #
def test_rank_percentiles_higher_is_better():
    s = pd.Series({1: 10.0, 2: 20.0, 3: 30.0})
    pct = ingest.rank_percentiles(s, inverted=False)
    assert pct[3] > pct[2] > pct[1]
    assert pct[3] == 100


def test_rank_percentiles_inverted():
    # Lower raw value should rank highest when inverted (e.g. INT%).
    s = pd.Series({1: 1.0, 2: 2.0, 3: 3.0})
    pct = ingest.rank_percentiles(s, inverted=True)
    assert pct[1] > pct[2] > pct[3]
    assert pct[1] == 100


def test_rank_percentiles_ignores_nan():
    s = pd.Series({1: 5.0, 2: float("nan"), 3: 15.0})
    pct = ingest.rank_percentiles(s, inverted=False)
    assert 2 not in pct
    assert pct[3] == 100


# --------------------------------------------------------------------------- #
# Qualification thresholds
# --------------------------------------------------------------------------- #
def test_qualifies():
    assert ingest.qualifies({"attempts": 200}, "Passing", "qb")
    assert not ingest.qualifies({"attempts": 100}, "Passing", "qb")
    assert ingest.qualifies({"carries": 80}, "Rushing", "rb")
    assert not ingest.qualifies({"carries": 79}, "Rushing", "rb")
    assert ingest.qualifies({"targets": 40}, "Receiving", "wr")
    assert not ingest.qualifies({"targets": 39}, "Receiving", "wr")
    assert ingest.qualifies({"games": 8}, "Defense", "def")
    assert not ingest.qualifies({"games": 8}, "Defense", "qb")  # wrong type
    assert not ingest.qualifies({"games": 7}, "Defense", "def")


def test_week_one_of_a_live_season_qualifies_on_a_prorated_bar():
    # The 2026 opener: one game played, nobody near 150 attempts.
    agg = pd.DataFrame({"games": [1, 1, 1]})
    scale = ingest.qualification_scale(agg, 2026)
    assert scale == pytest.approx(1 / 17)
    assert ingest.qualifies({"attempts": 33}, "Passing", "qb", scale=scale)
    assert not ingest.qualifies({"attempts": 2}, "Passing", "qb", scale=scale)
    assert ingest.qualifies({"carries": 10}, "Rushing", "rb", scale=scale)
    assert ingest.qualifies({"targets": 3}, "Receiving", "wr", scale=scale)
    assert ingest.qualifies({"games": 1}, "Defense", "def", scale=scale)
    assert not ingest.qualifies({"games": 0}, "Defense", "def", scale=scale)


def test_one_thursday_game_does_not_raise_the_league_bar():
    # 30 clubs have played two games, the Thursday pair three.
    teams = [f"T{i}" for i in range(32)]
    agg = pd.DataFrame({
        "team": teams + teams,
        "games": [3 if i < 2 else 2 for i in range(32)] + [1] * 32,
    })
    assert ingest.qualification_scale(agg, 2026) == pytest.approx(2 / 17)


def test_bye_weeks_follow_the_median_club():
    teams = [f"T{i}" for i in range(32)]
    agg = pd.DataFrame({"team": teams, "games": [5 if i < 4 else 6 for i in range(32)]})
    assert ingest.qualification_scale(agg, 2026) == pytest.approx(6 / 17)


def test_a_finished_season_keeps_its_full_qualification_bar():
    assert ingest.qualification_scale(
        pd.DataFrame({"team": ["KC", "BUF", "KC"], "games": [17, 17, 3]}), 2025
    ) == 1.0
    assert ingest.qualification_scale(pd.DataFrame({"games": [17, 12]}), 2025) == 1.0
    assert ingest.qualification_scale(pd.DataFrame({"games": [16, 9]}), 2019) == 1.0
    assert ingest.qualification_scale(pd.DataFrame(), 2026) == 1.0


def test_postseason_uses_phase_appropriate_qualification_floors():
    assert ingest.qualifies({"attempts": 20}, "Passing", "qb", "POST")
    assert ingest.qualifies({"carries": 8}, "Rushing", "rb", "POST")
    assert ingest.qualifies({"targets": 4}, "Receiving", "wr", "POST")
    assert ingest.qualifies({"games": 1}, "Defense", "def", "POST")
    assert not ingest.qualifies({"attempts": 19}, "Passing", "qb", "POST")


def test_receiving_qualification_falls_back_when_targets_are_unreliable():
    row = {"targets": 0, "receptions": 25, "targets_reliable": False}
    assert ingest.qualifies(row, "Receiving", "wr")
    assert not ingest.qualifies({**row, "receptions": 24}, "Receiving", "wr")


# --------------------------------------------------------------------------- #
# Aggregation from a synthetic weekly DataFrame
# --------------------------------------------------------------------------- #
def test_aggregate_excludes_postseason(weekly_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    qb = agg.loc[1]
    # 4 REG games of 40 attempts = 160; the POST game (50 att) is excluded.
    assert qb["attempts"] == 160
    assert qb["games"] == 4


def test_aggregate_can_select_postseason(weekly_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025, "POST")
    qb = agg.loc[1]
    assert qb["attempts"] == 50
    assert qb["games"] == 1


def test_aggregate_derived_rates(weekly_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    qb = agg.loc[1]
    # cmp% = 100/160 = 62.5, ypa = 1200/160 = 7.5
    assert round(qb["cmp_pct"], 1) == 62.5
    assert round(qb["ypa"], 1) == 7.5
    # EPA/play uses dropbacks, including sacks suffered.
    assert round(qb["passing_epa_per_play"], 4) == round(qb["passing_epa"] / (160 + qb["sacks_suffered"]), 4)
    # int_rate = 4/160 = 2.5%
    assert round(qb["int_rate"], 2) == 2.5
    rb = agg.loc[2]
    # ypc = 440/100 = 4.4, explosive = 16/100 = 16%, fumble = 4/100 = 4%
    assert round(rb["ypc"], 1) == 4.4
    assert round(rb["rushing_epa_per_carry"], 4) == round(rb["rushing_epa"] / 100, 4)
    assert round(rb["explosive_rush_rate"], 1) == 16.0
    assert round(rb["fumble_rate"], 1) == 4.0
    wr = agg.loc[3]
    # catch% = 32/48 = 66.7; receiving EPA is normalized per target.
    assert round(wr["catch_pct"], 1) == 66.7
    assert round(wr["receiving_epa_per_target"], 4) == round(wr["receiving_epa"] / 48, 4)


def test_aggregate_player_type_and_team(weekly_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    assert agg.loc[1]["player_type"] == "qb"
    assert agg.loc[4]["player_type"] == "def"
    assert agg.loc[1]["team"] == "KC"


def test_aggregate_omits_metrics_without_historical_source_columns(weekly_df):
    old_schema = weekly_df.drop(columns=[
        "rushing_10",
        "receiving_yards_after_catch",
        "target_share",
        "air_yards_share",
        "def_qb_hits",
    ]).copy()
    old_schema["season"] = 2015

    agg = ingest.aggregate_seasons(old_schema, 2015)

    assert "explosive_rush_rate" not in agg.columns
    assert "rec_yac" not in agg.columns
    assert "target_share_pct" not in agg.columns
    assert "wopr" not in agg.columns
    assert "qb_hits" not in agg.columns
    assert "rushing_epa_per_carry" in agg.columns
    assert "receiving_epa_per_target" in agg.columns


def test_merge_ngs(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    agg = ingest.merge_ngs(agg, ngs_passing_df, ngs_rushing_df, ngs_receiving_df, 2025)
    assert round(agg.loc[1]["cpoe"], 1) == 3.4
    assert round(agg.loc[1]["avg_time_to_throw"], 2) == 2.75
    assert round(agg.loc[2]["rush_yoe"], 1) == 120.5
    assert round(agg.loc[3]["avg_separation"], 1) == 3.2


def test_build_agg_skips_ngs_before_2016(weekly_df):
    old_weekly = weekly_df.copy()
    old_weekly["season"] = 2015
    with patch("ingest.nfl.load_player_stats", return_value=old_weekly):
        with patch("ingest.nfl.load_nextgen_stats") as load_ngs:
            with patch("ingest.load_headshots", return_value={}):
                agg = ingest.build_agg_for_season(2015)

    assert not agg.empty
    load_ngs.assert_not_called()
    assert "cpoe" not in agg.columns


def test_build_agg_requests_only_selected_ngs_season(weekly_df):
    empty_ngs = pd.DataFrame()
    with patch("ingest.nfl.load_player_stats", return_value=weekly_df):
        with patch("ingest.nfl.load_nextgen_stats", return_value=empty_ngs) as load_ngs:
            with patch("ingest.load_headshots", return_value={}):
                with patch("ingest.load_pfr_defense", return_value=pd.DataFrame()):
                    ingest.build_agg_for_season(2025)

    assert load_ngs.call_count == 3
    assert all(call.args[0] == [2025] for call in load_ngs.call_args_list)


def test_build_agg_skips_pfr_defense_for_postseason(weekly_df):
    """PFR's advanced defensive table is regular season only."""
    with patch("ingest.nfl.load_player_stats", return_value=weekly_df):
        with patch("ingest.nfl.load_nextgen_stats", return_value=pd.DataFrame()):
            with patch("ingest.load_headshots", return_value={}):
                with patch("ingest.load_pfr_defense") as load_pfr:
                    ingest.build_agg_for_season(2025, "POST")

    load_pfr.assert_not_called()


# --------------------------------------------------------------------------- #
# CPOE: weekly-derived, attempt-weighted, and preferred over NGS
# --------------------------------------------------------------------------- #
def test_cpoe_is_attempt_weighted_not_flat_mean(weekly_df):
    """A 5-attempt week must not count as much as a 40-attempt one."""
    df = weekly_df.copy()
    qb = df[df["player_id"] == "00-0000001"].copy()
    if len(qb) < 2:  # fixture has one row per player; synthesise a second week
        second = qb.iloc[[0]].copy()
        second["week"] = qb["week"].max() + 1
        qb = pd.concat([qb, second], ignore_index=True)
    qb = qb.reset_index(drop=True)
    qb.loc[0, ["attempts", "passing_cpoe"]] = [40, 5.0]
    qb.loc[1, ["attempts", "passing_cpoe"]] = [5, -10.0]

    agg = ingest.aggregate_seasons(qb, 2025)

    # Weighted: (40*5 + 5*-10) / 45 = 3.33. A flat mean would give -2.5.
    assert round(agg.loc[1]["cpoe"], 2) == 3.33


def test_weekly_cpoe_wins_over_ngs(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df):
    """One CPOE definition across the whole range, so 2016 isn't a seam."""
    df = weekly_df.copy()
    df.loc[df["player_id"] == "00-0000001", "passing_cpoe"] = 7.5

    agg = ingest.aggregate_seasons(df, 2025)
    agg = ingest.merge_ngs(agg, ngs_passing_df, ngs_rushing_df, ngs_receiving_df, 2025)

    # The NGS fixture says 3.4; the weekly feed says 7.5 and must win.
    assert round(agg.loc[1]["cpoe"], 1) == 7.5
    assert round(agg.loc[1]["cpoe_ngs"], 1) == 3.4


def test_ngs_cpoe_fills_gap_when_weekly_missing(
    weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df
):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    agg = ingest.merge_ngs(agg, ngs_passing_df, ngs_rushing_df, ngs_receiving_df, 2025)
    assert round(agg.loc[1]["cpoe"], 1) == 3.4


# --------------------------------------------------------------------------- #
# Advanced defence (PFR)
# --------------------------------------------------------------------------- #
def _pfr_def_frame(**overrides):
    base = {
        "def_pressures": 40.0,
        "def_hurries": 15.0,
        "def_qb_knockdowns": 10.0,
        "def_cmp_pct_allowed": 0.62,
        "def_yds_per_tgt_allowed": 7.1,
        "def_rating_allowed": 88.4,
        "def_missed_tkl_pct": 0.09,
        "def_targets_allowed": 60.0,
        "def_combined_tackles": 70.0,
    }
    base.update(overrides)
    return pd.DataFrame([base], index=[4])


def test_pfr_defense_scales_fractions_to_percentages():
    agg = pd.DataFrame(index=[4], data={"name": ["Def One"]})
    out = ingest.merge_pfr_defense(agg, _pfr_def_frame())

    assert round(out.loc[4]["def_cmp_pct_allowed"], 1) == 62.0
    assert round(out.loc[4]["def_missed_tkl_pct"], 1) == 9.0
    # Counting stats pass through untouched.
    assert out.loc[4]["def_pressures"] == 40.0


def test_low_target_coverage_rates_are_dropped():
    """A corner thrown at three times is not a 33%-completion defender."""
    agg = pd.DataFrame(index=[4], data={"name": ["Def One"]})
    out = ingest.merge_pfr_defense(agg, _pfr_def_frame(def_targets_allowed=3.0))

    assert pd.isna(out.loc[4]["def_cmp_pct_allowed"])
    assert pd.isna(out.loc[4]["def_yds_per_tgt_allowed"])
    assert pd.isna(out.loc[4]["def_rating_allowed"])
    # Pressures are a total, not a rate, so they survive.
    assert out.loc[4]["def_pressures"] == 40.0


def test_low_tackle_volume_drops_missed_tackle_rate():
    agg = pd.DataFrame(index=[4], data={"name": ["Def One"]})
    out = ingest.merge_pfr_defense(agg, _pfr_def_frame(def_combined_tackles=5.0))
    assert pd.isna(out.loc[4]["def_missed_tkl_pct"])


def test_pfr_defense_merge_is_a_noop_when_empty():
    agg = pd.DataFrame(index=[4], data={"name": ["Def One"]})
    assert ingest.merge_pfr_defense(agg, pd.DataFrame()).equals(agg)


# --------------------------------------------------------------------------- #
# Career qualification
# --------------------------------------------------------------------------- #
def test_career_thresholds_are_higher_than_season():
    one_season = {"attempts": 400, "carries": 200, "targets": 120, "games": 17,
                  "targets_reliable": True}

    assert ingest.qualifies(one_season, "Passing", "qb")
    assert not ingest.qualifies(one_season, "Passing", "qb", career=True)

    a_career = {"attempts": 3000, "carries": 900, "targets": 700, "games": 150,
                "targets_reliable": True}
    assert ingest.qualifies(a_career, "Passing", "qb", career=True)
    assert ingest.qualifies(a_career, "Rushing", "rb", career=True)
    assert ingest.qualifies(a_career, "Receiving", "wr", career=True)
    assert ingest.qualifies(a_career, "Defense", "def", career=True)


def test_career_playoff_thresholds_are_games_not_seasons():
    """Regression: reusing the regular-season career bar for playoff careers left
    exactly one qualifying passer in league history."""
    # Five playoff starts' worth of volume - a real playoff career, but nowhere
    # near a regular-season career.
    run = {"attempts": 180, "carries": 80, "targets": 55, "receptions": 35,
           "games": 10, "targets_reliable": True}

    assert ingest.qualifies(run, "Passing", "qb", "POST", career=True)
    assert ingest.qualifies(run, "Rushing", "rb", "POST", career=True)
    assert ingest.qualifies(run, "Receiving", "wr", "POST", career=True)
    assert ingest.qualifies(run, "Defense", "def", "POST", career=True)

    # The same volumes must still fail a regular-season career.
    assert not ingest.qualifies(run, "Passing", "qb", "REG", career=True)
    assert not ingest.qualifies(run, "Defense", "def", "REG", career=True)

    # And one hot playoff game is still not a playoff career.
    single = {"attempts": 40, "carries": 20, "targets": 12, "games": 1,
              "targets_reliable": True}
    assert not ingest.qualifies(single, "Passing", "qb", "POST", career=True)
    assert not ingest.qualifies(single, "Defense", "def", "POST", career=True)
    # ...though it clears the ordinary single-postseason bar.
    assert ingest.qualifies(single, "Passing", "qb", "POST")


def test_career_receiving_falls_back_to_receptions_when_targets_unreliable():
    row = {"receptions": 250, "targets": 0, "targets_reliable": False}
    assert ingest.qualifies(row, "Receiving", "wr", career=True)
    row["receptions"] = 60
    assert not ingest.qualifies(row, "Receiving", "wr", career=True)


def test_all_time_season_uses_career_thresholds(weekly_df):
    """build_snapshot_rows switches tiers off the sentinel season alone."""
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    agg["image_url"] = None

    season_rows = ingest.build_snapshot_rows(agg, 2025, NOW)
    career_rows = ingest.build_snapshot_rows(agg, ingest.ALL_TIME_SEASON, NOW)

    assert season_rows, "fixture should qualify for a single season"
    # The same fixture volumes are nowhere near a career, so nothing qualifies.
    assert not career_rows


# --------------------------------------------------------------------------- #
# Snapshot row building
# --------------------------------------------------------------------------- #
def _build_rows(weekly_df, ngs_p, ngs_r, ngs_rec):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    agg = ingest.merge_ngs(agg, ngs_p, ngs_r, ngs_rec, 2025)
    agg["image_url"] = None
    return ingest.build_snapshot_rows(agg, 2025, NOW)


def test_live_season_ships_every_player_with_a_qualified_flag(
    weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df
):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    agg = ingest.merge_ngs(agg, ngs_passing_df, ngs_rushing_df, ngs_receiving_df, 2025)
    agg["image_url"] = None
    rows = ingest.build_snapshot_rows(agg, 2025, NOW, live=True)
    by_id = {r["id"]: r for r in rows}

    # The sub-threshold WR (id 5, 5 targets) ships, flagged unqualified.
    receiving = [m for m in by_id[5]["metrics"] if m["category"] == "Receiving"]
    assert receiving
    assert not any(m["qualified"] for m in receiving)
    # The QB clears the passing bar but not the rushing one; both lines ship.
    qb = by_id[1]["metrics"]
    assert all(m["qualified"] for m in qb if m["category"] == "Passing")
    assert [m for m in qb if m["category"] == "Rushing"]
    assert not any(m["qualified"] for m in qb if m["category"] == "Rushing")


def test_has_opportunity_needs_volume_and_a_matching_type():
    assert ingest.has_opportunity({"attempts": 1}, "Passing", "qb")
    assert not ingest.has_opportunity({"attempts": 0}, "Passing", "qb")
    assert not ingest.has_opportunity({"carries": 3}, "Rushing", "k")
    assert ingest.has_opportunity({"games": 1}, "Defense", "def")
    assert not ingest.has_opportunity({"games": 1}, "Defense", "wr")


def test_build_snapshot_rows_shape(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df):
    rows = _build_rows(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df)
    by_id = {r["id"]: r for r in rows}
    # The sub-threshold WR (id 5, 5 targets) is dropped (no metrics).
    assert 5 not in by_id
    # QB present with Passing metrics.
    qb = by_id[1]
    assert qb["player_type"] == "qb"
    cats = {m["category"] for m in qb["metrics"]}
    assert "Passing" in cats
    # Rushing QB also gets Rushing? QB carries = 20 total < 80, so no.
    assert "Rushing" not in cats
    # Every metric has the contract shape.
    for m in qb["metrics"]:
        assert set(m) == {"id", "label", "value", "percentile", "category"}
        assert 1 <= m["percentile"] <= 100
    rb = by_id[2]
    assert next(m for m in rb["metrics"] if m["label"] == "EPA/Rush")["value"]
    wr = by_id[3]
    assert next(m for m in wr["metrics"] if m["label"] == "EPA/Tgt")["value"]
    # Season label and source.
    assert qb["season"] == 2025
    assert qb["source"] == "nflverse"
    assert qb["handedness"] == ""


def test_build_snapshot_inverted_metric_present(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df):
    rows = _build_rows(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df)
    qb = next(r for r in rows if r["id"] == 1)
    int_metric = next(m for m in qb["metrics"] if m["label"] == "INT%")
    # Only one qualified passer, so it ranks 100 by default; value formatted as %.
    assert int_metric["value"].endswith("%")


def test_build_snapshot_value_formatting(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df):
    rows = _build_rows(weekly_df, ngs_passing_df, ngs_rushing_df, ngs_receiving_df)
    qb = next(r for r in rows if r["id"] == 1)
    pass_yds = next(m for m in qb["metrics"] if m["label"] == "Pass Yds")
    assert pass_yds["value"] == "1,200"  # 4 games * 300


def test_build_standard_stats(weekly_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    stats = ingest.build_standard_stats(agg.loc[1])
    labels = {s["label"] for s in stats}
    assert "G" in labels
    assert "Cmp/Att" in labels
    cmp_att = next(s for s in stats if s["label"] == "Cmp/Att")
    assert cmp_att["value"] == "100/160"


# --------------------------------------------------------------------------- #
# Game logs
# --------------------------------------------------------------------------- #
def test_build_game_log_rows(weekly_df):
    sched = {
        "2025_01_KC_DEN": "2025-09-07", "2025_02_KC_DEN": "2025-09-14",
        "2025_03_KC_LV": "2025-09-21", "2025_04_KC_LV": "2025-09-28",
    }
    rows = ingest_game_logs.build_game_log_rows(weekly_df, sched, 2025, NOW)
    qb_rows = [r for r in rows if r["player_id"] == 1]
    # Only 4 QB games have scheduled dates in the map; POST game (week 20) not mapped.
    assert len(qb_rows) == 4
    r0 = qb_rows[0]
    assert r0["game_date"] == "2025-09-07"
    assert r0["player_type"] == "qb"
    assert r0["plays"] == 45  # 40 att + 5 carries (week 1)
    assert r0["touches"] == 30  # 25 cmp + 5 carries
    assert r0["metrics"]["passing_yards"] == 300
    assert "epa_total" in r0["metrics"]


def test_build_game_log_rows_skips_unmapped_games(weekly_df):
    rows = ingest_game_logs.build_game_log_rows(weekly_df, {}, 2025, NOW)
    assert rows == []


def test_schedule_map():
    sched = pd.DataFrame([
        {"game_id": "2025_01_KC_DEN", "gameday": "2025-09-07"},
        {"game_id": "2025_02_SF_SEA", "gameday": "2025-09-14"},
    ])
    m = ingest_game_logs.schedule_map(sched)
    assert m["2025_01_KC_DEN"] == "2025-09-07"


# --------------------------------------------------------------------------- #
# Upsert batching / main flow
# --------------------------------------------------------------------------- #
def test_chunks():
    rows = [{"id": i} for i in range(350)]
    batches = list(ingest.chunks(rows, 150))
    assert [len(b) for b in batches] == [150, 150, 50]


def test_main_upserts_batches():
    rows = [{"id": i, "player_type": "qb"} for i in range(200)]
    mock_client = MagicMock()
    mock_table = MagicMock()
    mock_client.table.return_value = mock_table
    mock_table.upsert.return_value = mock_table
    mock_table.select.return_value = mock_table
    mock_table.eq.return_value = mock_table
    mock_table.execute.return_value = MagicMock(data=[])
    with patch.dict(os.environ, {"SUPABASE_URL": "https://t.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "k"}):
        with patch("ingest.create_client", return_value=mock_client):
            with patch("ingest.build_agg_for_season", return_value=pd.DataFrame({"x": [1]})):
                with patch("ingest.build_snapshot_rows", return_value=rows):
                    with patch("sys.argv", ["ingest.py", "--season", "2025"]):
                        ingest.main()
    assert mock_table.upsert.call_count == 2  # 200 rows / 150 batch


def test_main_exits_when_no_rows():
    mock_client = MagicMock()
    with patch.dict(os.environ, {"SUPABASE_URL": "https://t.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "k"}):
        with patch("ingest.create_client", return_value=mock_client):
            with patch("ingest.build_agg_for_season", return_value=pd.DataFrame()):
                with patch("ingest.build_snapshot_rows", return_value=[]):
                    with patch("sys.argv", ["ingest.py", "--season", "2025"]):
                        with pytest.raises(SystemExit) as exc:
                            ingest.main()
    assert exc.value.code == 1
