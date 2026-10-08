"""Per-game aggregation tests for the NFL Recent Form pipeline.

The subtle cases worth pinning down: raw counts (never pre-divided rates) so
a downstream window rollup can recompute an exact rate, the week column
carrying through for the recent-form labelling, and the optional Next Gen
Stats weekly join being additive (present when the join has data, silently
absent otherwise) rather than something that can corrupt the primary metrics.
"""

from datetime import datetime, timezone

import pandas as pd
import pytest

from ingest_game_logs import build_game_log_rows, ngs_weekly_lookup, schedule_map

NOW = datetime(2026, 2, 1, tzinfo=timezone.utc)


def _weekly_row(**overrides):
    row = {
        "player_id": "00-0000001",
        "player_display_name": "Test QB",
        "position": "QB",
        "position_group": "QB",
        "team": "KC",
        "opponent_team": "DEN",
        "game_id": "2025_01_KC_DEN",
        "season": 2025,
        "week": 1,
        "season_type": "REG",
        "completions": 25,
        "attempts": 40,
        "passing_yards": 300,
        "passing_tds": 3,
        "passing_interceptions": 1,
        "sacks_suffered": 2,
        "sack_yards_lost": 14,
        "passing_first_downs": 15,
        "passing_air_yards": 250,
        "passing_epa": 8.123,
        "carries": 2,
        "rushing_yards": 6,
        "rushing_tds": 0,
        "rushing_first_downs": 0,
        "rushing_fumbles": 0,
        "rushing_fumbles_lost": 0,
        "rushing_epa": -0.5,
        "receptions": 0,
        "targets": 0,
        "receiving_yards": 0,
        "receiving_tds": 0,
        "receiving_yards_after_catch": 0,
        "receiving_first_downs": 0,
        "receiving_air_yards": 0,
        "receiving_fumbles": 0,
        "receiving_epa": 0.0,
        "def_tackles_solo": 0,
        "def_tackle_assists": 0,
        "def_sacks": 0,
        "def_interceptions": 0,
        "def_pass_defended": 0,
        "def_fumbles_forced": 0,
        "def_tackles_for_loss": 0,
        "def_qb_hits": 0,
    }
    row.update(overrides)
    return row


@pytest.fixture
def sched():
    return {"2025_01_KC_DEN": "2025-09-08"}


def test_raw_counts_are_not_pre_divided(sched):
    """cmp% must NOT show up anywhere here — the rollup derives it later."""
    weekly = pd.DataFrame([_weekly_row()])
    rows = build_game_log_rows(weekly, sched, 2025, NOW)
    metrics = rows[0]["metrics"]
    assert metrics["completions"] == 25
    assert metrics["attempts"] == 40
    assert metrics["passing_yards"] == 300
    assert "cmp_pct" not in metrics
    assert "ypa" not in metrics


def test_epa_categories_stored_separately_and_summed():
    weekly = pd.DataFrame([_weekly_row(passing_epa=8.0, rushing_epa=-0.5, receiving_epa=0.0)])
    rows = build_game_log_rows(weekly, {"2025_01_KC_DEN": "2025-09-08"}, 2025, NOW)
    metrics = rows[0]["metrics"]
    assert metrics["passing_epa"] == pytest.approx(8.0)
    assert metrics["rushing_epa"] == pytest.approx(-0.5)
    assert metrics["receiving_epa"] == pytest.approx(0.0)
    assert metrics["epa_total"] == pytest.approx(7.5)


def test_week_column_populated_from_weekly_frame(sched):
    weekly = pd.DataFrame([_weekly_row(week=7)])
    rows = build_game_log_rows(weekly, sched, 2025, NOW)
    assert rows[0]["week"] == 7


def test_defensive_row_included_even_with_zero_plays(sched):
    """A defender with no offensive plays must not be dropped."""
    weekly = pd.DataFrame([_weekly_row(
        player_id="00-0000004", position="LB", position_group="LB",
        completions=0, attempts=0, carries=0, targets=0,
        def_tackles_solo=6, def_tackle_assists=2, def_sacks=1.0,
    )])
    rows = build_game_log_rows(weekly, sched, 2025, NOW)
    assert len(rows) == 1
    assert rows[0]["player_type"] == "def"
    assert rows[0]["plays"] == 0
    assert rows[0]["metrics"]["def_tackles_solo"] == 6


def test_row_with_no_plays_and_no_defense_is_dropped(sched):
    weekly = pd.DataFrame([_weekly_row(completions=0, attempts=0, carries=0, targets=0)])
    rows = build_game_log_rows(weekly, sched, 2025, NOW)
    assert rows == []


def test_row_dropped_when_game_not_in_schedule():
    weekly = pd.DataFrame([_weekly_row(game_id="2025_99_UNKNOWN")])
    rows = build_game_log_rows(weekly, {}, 2025, NOW)
    assert rows == []


def test_schedule_map_extracts_iso_date():
    schedule = pd.DataFrame([{"game_id": "2025_01_KC_DEN", "gameday": "2025-09-08"}])
    assert schedule_map(schedule) == {"2025_01_KC_DEN": "2025-09-08"}


# --------------------------------------------------------------------------- #
# Optional Next Gen Stats weekly join
# --------------------------------------------------------------------------- #
def test_ngs_weekly_lookup_indexes_by_gsis_and_week():
    ngs = pd.DataFrame([
        {"player_gsis_id": "00-0000001", "week": 1, "completion_percentage_above_expectation": 3.4,
         "avg_time_to_throw": 2.75},
        {"player_gsis_id": "00-0000001", "week": 2, "completion_percentage_above_expectation": -1.1,
         "avg_time_to_throw": 2.9},
    ])
    cols = {"completion_percentage_above_expectation": "cpoe", "avg_time_to_throw": "avg_time_to_throw"}
    lookup = ngs_weekly_lookup(ngs, cols)
    assert lookup[("00-0000001", 1)]["cpoe"] == pytest.approx(3.4)
    assert lookup[("00-0000001", 2)]["avg_time_to_throw"] == pytest.approx(2.9)


def test_ngs_weekly_lookup_skips_missing_columns():
    ngs = pd.DataFrame([{"player_gsis_id": "00-0000001", "week": 1}])
    assert ngs_weekly_lookup(ngs, {"avg_separation": "avg_separation"}) == {}


def test_ngs_weekly_lookup_handles_empty_frame():
    assert ngs_weekly_lookup(pd.DataFrame(), {"cpoe": "cpoe"}) == {}


def test_ngs_metrics_fold_into_matching_game_row(sched):
    weekly = pd.DataFrame([_weekly_row(week=1)])
    ngs_pass = {("00-0000001", 1): {"cpoe": 3.4, "avg_time_to_throw": 2.75}}
    rows = build_game_log_rows(weekly, sched, 2025, NOW, ngs_pass=ngs_pass)
    metrics = rows[0]["metrics"]
    assert metrics["cpoe"] == pytest.approx(3.4)
    assert metrics["avg_time_to_throw"] == pytest.approx(2.75)


def test_ngs_metrics_absent_when_join_has_no_match(sched):
    weekly = pd.DataFrame([_weekly_row(week=1)])
    rows = build_game_log_rows(weekly, sched, 2025, NOW, ngs_pass={})
    metrics = rows[0]["metrics"]
    assert "cpoe" not in metrics
    assert "avg_time_to_throw" not in metrics
