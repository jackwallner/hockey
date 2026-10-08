"""Career rollup: the parts that are easy to get subtly wrong.

The rollup reuses `aggregate_seasons` / `build_snapshot_rows` wholesale, so what
needs its own coverage is the pooling of multi-season sources - where a total and
an average look identical in code and differ by a factor of the season count.
"""

from datetime import datetime, timezone

import pandas as pd
import pytest

import ingest
import rollup_all_time as rollup

NOW = datetime(2026, 7, 29, tzinfo=timezone.utc)


def _ngs_rushing_rows() -> pd.DataFrame:
    """Two seasons of week-0 NGS rushing rows for one back."""
    return pd.DataFrame([
        {
            "season": 2023, "season_type": "REG", "week": 0,
            "player_gsis_id": "00-0000002", "rush_attempts": 200,
            "rush_yards_over_expected": 100.0,
            "rush_yards_over_expected_per_att": 0.5,
            "efficiency": 3.0,
        },
        {
            "season": 2024, "season_type": "REG", "week": 0,
            "player_gsis_id": "00-0000002", "rush_attempts": 100,
            "rush_yards_over_expected": 50.0,
            "rush_yards_over_expected_per_att": 0.5,
            "efficiency": 4.0,
        },
    ])


def test_career_ryoe_is_summed_not_averaged(monkeypatch):
    """RYOE is a yardage total. Averaging it reports one season as a career."""
    rows = _ngs_rushing_rows()

    def fake_load(seasons, stat_type):
        if stat_type == "rushing":
            return rows[rows["season"] == seasons[0]]
        return pd.DataFrame()

    monkeypatch.setattr(rollup.nfl, "load_nextgen_stats", fake_load)

    agg = pd.DataFrame(index=[2], data={"name": ["Back One"]})
    out = rollup._merge_career_ngs(agg, 2023, 2024)

    # 100 + 50, not (100 + 50) / 2.
    assert out.loc[2]["rush_yoe"] == pytest.approx(150.0)


def test_career_ngs_averages_are_volume_weighted(monkeypatch):
    """A 100-attempt season must not weigh the same as a 400-attempt one."""
    rows = pd.DataFrame([
        {
            "season": 2023, "season_type": "REG", "week": 0,
            "player_gsis_id": "00-0000001", "attempts": 400,
            "avg_time_to_throw": 2.50,
            "completion_percentage_above_expectation": 4.0,
        },
        {
            "season": 2024, "season_type": "REG", "week": 0,
            "player_gsis_id": "00-0000001", "attempts": 100,
            "avg_time_to_throw": 3.50,
            "completion_percentage_above_expectation": -1.0,
        },
    ])

    def fake_load(seasons, stat_type):
        if stat_type == "passing":
            return rows[rows["season"] == seasons[0]]
        return pd.DataFrame()

    monkeypatch.setattr(rollup.nfl, "load_nextgen_stats", fake_load)

    agg = pd.DataFrame(index=[1], data={"name": ["QB One"]})
    out = rollup._merge_career_ngs(agg, 2023, 2024)

    # (400*2.50 + 100*3.50) / 500 = 2.70; a flat mean would give 3.00.
    assert out.loc[1]["avg_time_to_throw"] == pytest.approx(2.70, abs=0.001)
    # (400*4.0 + 100*-1.0) / 500 = 3.0; a flat mean would give 1.5.
    assert out.loc[1]["cpoe_ngs"] == pytest.approx(3.0, abs=0.001)


def test_career_pfr_defense_sums_totals_and_weights_rates(monkeypatch):
    per_season = {
        2023: pd.DataFrame([{
            "def_pressures": 30.0, "def_hurries": 10.0, "def_qb_knockdowns": 8.0,
            "def_cmp_pct_allowed": 0.60, "def_yds_per_tgt_allowed": 7.0,
            "def_rating_allowed": 90.0, "def_missed_tkl_pct": 0.10,
            "def_targets_allowed": 100.0, "def_combined_tackles": 80.0,
        }], index=[4]),
        2024: pd.DataFrame([{
            "def_pressures": 20.0, "def_hurries": 5.0, "def_qb_knockdowns": 4.0,
            "def_cmp_pct_allowed": 0.70, "def_yds_per_tgt_allowed": 9.0,
            "def_rating_allowed": 110.0, "def_missed_tkl_pct": 0.20,
            "def_targets_allowed": 50.0, "def_combined_tackles": 40.0,
        }], index=[4]),
    }

    monkeypatch.setattr(rollup, "load_pfr_defense", lambda season: per_season[season])

    agg = pd.DataFrame(index=[4], data={"name": ["Def One"]})
    out = rollup._merge_career_pfr_defense(agg, 2023, 2024)

    # Totals add.
    assert out.loc[4]["def_pressures"] == pytest.approx(50.0)
    assert out.loc[4]["def_targets_allowed"] == pytest.approx(150.0)
    # Rates are target-weighted and scaled to percentages exactly once:
    # (100*0.60 + 50*0.70) / 150 = 0.6333 -> 63.33
    assert out.loc[4]["def_cmp_pct_allowed"] == pytest.approx(63.33, abs=0.01)
    # (100*7 + 50*9) / 150 = 7.667
    assert out.loc[4]["def_yds_per_tgt_allowed"] == pytest.approx(7.667, abs=0.01)
    # Missed tackles weight by combined tackles: (80*0.10 + 40*0.20)/120 = 0.1333
    assert out.loc[4]["def_missed_tkl_pct"] == pytest.approx(13.33, abs=0.01)


def test_career_pfr_defense_applies_volume_cut(monkeypatch):
    thin = pd.DataFrame([{
        "def_pressures": 5.0,
        "def_cmp_pct_allowed": 0.50,
        "def_yds_per_tgt_allowed": 6.0,
        "def_rating_allowed": 70.0,
        "def_missed_tkl_pct": 0.05,
        "def_targets_allowed": 4.0,
        "def_combined_tackles": 6.0,
    }], index=[4])

    monkeypatch.setattr(rollup, "load_pfr_defense", lambda season: thin)

    agg = pd.DataFrame(index=[4], data={"name": ["Def One"]})
    out = rollup._merge_career_pfr_defense(agg, 2023, 2023)

    assert pd.isna(out.loc[4]["def_cmp_pct_allowed"])
    assert pd.isna(out.loc[4]["def_missed_tkl_pct"])
    assert out.loc[4]["def_pressures"] == pytest.approx(5.0)


def test_career_agg_relabels_every_season_to_the_sentinel(weekly_df, monkeypatch):
    """`aggregate_seasons` filters to one season, so pooled rows must carry the
    sentinel or the career pass would aggregate nothing."""
    seasons = []
    for season in (2023, 2024):
        frame = weekly_df.copy()
        frame["season"] = season
        seasons.append(frame)

    monkeypatch.setattr(
        rollup, "load_all_weekly", lambda first, last: pd.concat(seasons, ignore_index=True)
    )
    monkeypatch.setattr(rollup, "load_headshots", lambda: {})
    monkeypatch.setattr(rollup, "_merge_career_ngs", lambda agg, first, last: agg)
    monkeypatch.setattr(rollup, "_merge_career_pfr_defense", lambda agg, first, last: agg)

    agg = rollup.build_career_agg(2023, 2024)

    assert not agg.empty
    # Two identical seasons pooled: the QB's attempts should have doubled.
    single = ingest.aggregate_seasons(weekly_df, 2025)
    assert agg.loc[1]["attempts"] == pytest.approx(single.loc[1]["attempts"] * 2)


def test_all_time_rows_use_the_sentinel_season(weekly_df):
    agg = ingest.aggregate_seasons(weekly_df, 2025)
    agg["image_url"] = None
    # Inflate volumes so the fixture clears the career bar.
    for column, value in (("attempts", 3000), ("carries", 900), ("targets", 700),
                          ("games", 150)):
        if column in agg.columns:
            agg[column] = value

    rows = ingest.build_snapshot_rows(agg, ingest.ALL_TIME_SEASON, NOW)

    assert rows
    assert all(row["season"] == ingest.ALL_TIME_SEASON for row in rows)
