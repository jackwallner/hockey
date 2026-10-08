"""Rolling 2/4/8-week rollup tests.

The claim worth pinning down is exactness: game logs store raw counts, so a
window's rate has to equal a from-scratch recompute over the summed counts,
not an average of per-game rates. The other load-bearing behaviors are the
league anchor (latest game date for the phase, not each player's own), the
equal-length non-overlapping prior span, and metrics with a zero denominator
being left out rather than reported as a misleading 0.
"""

from datetime import datetime, timezone

import pytest

from rollup_recent_form import (
    WINDOW_WEEKS,
    _aggregate,
    _anchors,
    _delta,
    _routable_logs,
    _week_of,
    build_rows,
)

NOW = datetime(2026, 10, 8, tzinfo=timezone.utc)

SKATER_RATES = {
    "points_per_60", "goals_per_60", "ixg_per_60", "gax", "shooting_pct",
    "shots_per_60", "hd_shots_per_60", "blocks_per_60", "hits_per_60",
}
SKATER_TOTALS = {"goals", "assists", "points", "shots_on_goal", "ixg", "games"}
GOALIE_RATES = {"sv_pct", "gaa", "gsax", "gsax_per_60", "hd_sv_pct", "shots_against_per_60"}
GOALIE_TOTALS = {"saves", "goals_against", "games", "wins"}


def _log(game_date, metrics, *, week=1, player_id=1, player_type="f", team="EDM",
         season_type="REG", plays=0, touches=0):
    return {
        "player_id": player_id, "season": 2025, "season_type": season_type,
        "game_date": game_date, "week": week, "player_type": player_type,
        "team": team, "plays": plays, "touches": touches, "metrics": metrics,
    }


def _skater(date, **metrics):
    base = {"goals": 0, "assists": 0, "points": 0, "shots_on_goal": 0, "shot_attempts": 0,
            "ixg": 0.0, "hd_shots": 0, "hits": 0, "blocks": 0, "toi_seconds": 1200}
    base.update(metrics)
    return base


# --------------------------------------------------------------------------- #
# Exact window recomputation from raw counts
# --------------------------------------------------------------------------- #
def test_per_60_rates_divide_summed_counts_by_summed_ice_time():
    """1 point in 10 minutes then 1 in 30 is 2 over 40 = 3.0/60, not the mean of 6.0 and 2.0."""
    logs = [
        _log("2025-10-10", _skater("x", points=1, toi_seconds=600)),
        _log("2025-10-12", _skater("x", points=1, toi_seconds=1800)),
    ]
    assert _aggregate(logs)["points_per_60"] == pytest.approx(3.0)


def test_shooting_pct_is_goals_over_shots_on_goal():
    logs = [
        _log("2025-10-10", _skater("x", goals=1, shots_on_goal=2)),
        _log("2025-10-12", _skater("x", goals=1, shots_on_goal=6)),
    ]
    assert _aggregate(logs)["shooting_pct"] == pytest.approx(25.0)


def test_gax_is_goals_minus_ixg_and_totals_are_summed():
    logs = [
        _log("2025-10-10", _skater("x", goals=2, assists=1, points=3, ixg=1.2, shots_on_goal=5)),
        _log("2025-10-12", _skater("x", goals=0, assists=2, points=2, ixg=0.9, shots_on_goal=3)),
    ]
    result = _aggregate(logs)
    assert result["gax"] == pytest.approx(2 - 2.1)
    assert (result["goals"], result["assists"], result["points"], result["shots_on_goal"]) == (2, 3, 5, 8)
    assert result["ixg"] == pytest.approx(2.1)
    assert result["games"] == 2


def test_shots_per_60_counts_shot_attempts():
    logs = [_log("2025-10-10", _skater("x", shot_attempts=10, hd_shots=2, hits=3, blocks=1, toi_seconds=1800))]
    result = _aggregate(logs)
    assert result["shots_per_60"] == pytest.approx(20.0)
    assert result["hd_shots_per_60"] == pytest.approx(4.0)
    assert result["hits_per_60"] == pytest.approx(6.0)
    assert result["blocks_per_60"] == pytest.approx(2.0)


def test_skater_keys_are_exactly_the_contracts():
    result = _aggregate([_log("2025-10-10", _skater("x", goals=1, shots_on_goal=2))])
    assert set(result) == SKATER_RATES | SKATER_TOTALS


def test_rates_are_omitted_when_the_denominator_is_zero():
    no_shots = _aggregate([_log("2025-10-10", _skater("x"))])
    assert "shooting_pct" not in no_shots
    assert no_shots["goals"] == 0  # a total of zero is real, not missing
    no_ice = _aggregate([_log("2025-10-10", _skater("x", toi_seconds=0))])
    assert not any(key.endswith("_per_60") for key in no_ice)
    assert "gax" in no_ice


def _goalie(**metrics):
    base = {"shots_against": 30, "saves": 28, "goals_against": 2, "xga": 2.5,
            "hd_shots_against": 4, "hd_goals_against": 1, "toi_seconds": 3600, "decision_win": 1}
    base.update(metrics)
    return base


def test_goalie_rates_from_summed_counts():
    logs = [
        _log("2025-10-10", _goalie(), player_type="g"),
        _log("2025-10-12", _goalie(shots_against=10, saves=10, goals_against=0, xga=0.5,
                                   hd_shots_against=1, hd_goals_against=0, toi_seconds=1800,
                                   decision_win=0), player_type="g"),
    ]
    result = _aggregate(logs, "g")
    assert result["sv_pct"] == pytest.approx(1 - 2 / 40, abs=5e-4)
    assert result["gaa"] == pytest.approx(2 / 1.5, abs=5e-3)
    assert result["gsax"] == pytest.approx(3.0 - 2, abs=5e-3)
    assert result["gsax_per_60"] == pytest.approx(1 / 1.5, abs=5e-3)
    assert result["hd_sv_pct"] == pytest.approx(1 - 1 / 5, abs=5e-4)
    assert result["shots_against_per_60"] == pytest.approx(40 / 1.5, abs=0.05)
    assert (result["saves"], result["goals_against"], result["games"], result["wins"]) == (38, 2, 2, 1)


def test_goalie_keys_are_exactly_the_contracts():
    assert set(_aggregate([_log("2025-10-10", _goalie(), player_type="g")], "g")) == GOALIE_RATES | GOALIE_TOTALS


def test_goalie_without_high_danger_shots_has_no_hd_sv_pct():
    result = _aggregate([_log("2025-10-10", _goalie(hd_shots_against=0, hd_goals_against=0), player_type="g")], "g")
    assert "hd_sv_pct" not in result
    assert "sv_pct" in result


def test_delta_covers_only_shared_metrics_and_rounds():
    assert _delta({"gax": 1.25, "goals": 3}, {"gax": 0.5}) == {"gax": 0.75}
    assert _delta({"goals": 3}, {}) == {}


# --------------------------------------------------------------------------- #
# League-anchored windows
# --------------------------------------------------------------------------- #
def _rows(logs, window=2, player_id=1):
    return [r for r in build_rows(logs, NOW) if r["window_weeks"] == window and r["player_id"] == player_id]


def test_windows_are_two_four_and_eight_weeks():
    assert WINDOW_WEEKS == (2, 4, 8)
    logs = [_log("2025-11-30", _skater("x", points=1), week=9)]
    assert sorted(r["window_weeks"] for r in build_rows(logs, NOW)) == [2, 4, 8]


def test_current_span_is_the_half_open_block_ending_on_the_anchor():
    anchor = "2025-11-30"
    logs = [
        _log("2025-11-30", _skater("x", goals=1, points=1), week=9),            # anchor day: in
        _log("2025-11-17", _skater("x", goals=1, points=1), week=7),            # anchor - 13d: in
        _log("2025-11-16", _skater("x", goals=1, points=1), week=7),            # anchor - 14d: prior
        _log("2025-11-03", _skater("x", goals=1, points=1), week=3),            # anchor - 27d: prior
        _log("2025-11-02", _skater("x", goals=1, points=1), week=3),            # anchor - 28d: outside
    ]
    row = _rows(logs)[0]
    assert row["as_of"] == anchor
    assert row["games"] == 2 and row["metrics"]["goals"] == 2
    assert row["prior_metrics"]["goals"] == 2
    assert row["delta"]["goals"] == 0


def test_the_anchor_is_the_leagues_latest_game_not_the_players():
    logs = [
        _log("2025-11-30", _skater("x"), player_id=2, week=9),  # someone else played on the anchor
        _log("2025-11-10", _skater("x", goals=1), player_id=1, week=6),
    ]
    assert _rows(logs, window=2, player_id=1) == []  # outside (11-16, 11-30]
    assert len(_rows(logs, window=4, player_id=1)) == 1


def test_a_player_without_a_current_appearance_is_omitted_entirely():
    logs = [
        _log("2025-11-30", _skater("x"), player_id=2, week=9),
        _log("2025-10-01", _skater("x"), player_id=1, week=1),
    ]
    assert [r for r in build_rows(logs, NOW) if r["player_id"] == 1] == []


def test_each_phase_has_its_own_anchor():
    logs = [
        _log("2026-04-10", _skater("x", goals=1), week=28, player_id=1),
        _log("2026-05-20", _skater("x", goals=2), week=33, player_id=1, season_type="POST"),
        _log("2026-05-21", _skater("x", goals=3), week=33, player_id=2, season_type="POST"),
    ]
    reg = [r for r in build_rows(logs, NOW) if r["season_type"] == "REG" and r["window_weeks"] == 2]
    post = [r for r in build_rows(logs, NOW) if r["season_type"] == "POST" and r["window_weeks"] == 2]
    assert len(reg) == 1 and reg[0]["as_of"] == "2026-04-10"
    assert len(post) == 2


def test_row_shape_and_summed_plays_and_touches():
    logs = [
        _log("2025-11-30", _skater("x", goals=1), week=9, plays=20, touches=5, team="EDM"),
        _log("2025-11-26", _skater("x", goals=2), week=9, plays=18, touches=7, team="CGY"),
    ]
    row = _rows(logs)[0]
    assert set(row) == {
        "player_id", "season", "season_type", "player_type", "window_weeks", "as_of",
        "start_week", "end_week", "team", "games", "plays", "touches", "metrics",
        "prior_metrics", "delta", "updated_at",
    }
    assert (row["plays"], row["touches"], row["games"]) == (38, 12, 2)
    assert row["team"] == "EDM"  # the latest game's club
    assert row["prior_metrics"] == {} and row["delta"] == {}
    assert row["updated_at"] == NOW.isoformat()


def test_goalies_roll_up_with_goalie_keys():
    logs = [_log("2025-11-30", _goalie(), week=9, player_type="g")]
    row = _rows(logs)[0]
    assert row["player_type"] == "g"
    assert set(row["metrics"]) == GOALIE_RATES | GOALIE_TOTALS


def test_prior_window_feeds_the_delta():
    logs = [
        _log("2025-11-30", _skater("x", goals=3, points=3), week=9),
        _log("2025-11-18", _skater("x", goals=1, points=1), week=7),
        _log("2025-11-10", _skater("x", goals=1, points=1), week=6),
    ]
    row = _rows(logs, window=4)[0]
    assert row["metrics"]["goals"] == 5
    row2 = _rows(logs, window=2)[0]
    assert row2["metrics"]["goals"] == 4  # 11-30 and 11-18
    assert row2["prior_metrics"]["goals"] == 1
    assert row2["delta"]["goals"] == 3


def test_week_labels_count_from_the_anchors_league_week():
    logs = [_log("2025-11-30", _skater("x"), week=9)]
    row = _rows(logs, window=2)[0]
    assert (row["start_week"], row["end_week"]) == (8, 9)
    row8 = _rows(logs, window=8)[0]
    assert (row8["start_week"], row8["end_week"]) == (2, 9)


def test_week_of_clamps_at_one_and_needs_an_anchor_week():
    from datetime import date
    assert _week_of(date(2025, 9, 1), date(2025, 10, 12), 1) == 1
    assert _week_of(date(2025, 10, 12), date(2025, 10, 12), None) is None
    assert _anchors([_log("2025-10-12", {}, week=1)]) == {(2025, "REG"): (date(2025, 10, 12), 1)}


def test_rows_that_cannot_resolve_to_a_snapshot_are_dropped():
    rows = [
        {"player_id": 1, "season_type": "REG"},
        {"player_id": 2, "season_type": "REG"},
        {"player_id": 1, "season_type": "POST"},
    ]
    assert _routable_logs(rows, {(1, "REG")}) == [rows[0]]
