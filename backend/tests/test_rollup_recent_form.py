"""Rolling last-N-weeks rollup tests.

The claim worth pinning down is exactness: game logs store raw counts, so a
window's rate has to equal a from-scratch recompute over the summed counts,
not an average of already-averaged per-game rates. The other load-bearing
behaviors are shared week windowing (not calendar days), a prior window that
doesn't overlap the current one, and metrics with a zero denominator being
left out rather than reported as a misleading 0.
"""

import pytest

from rollup_recent_form import _aggregate, _delta, _routable_logs, build_rows


def _log(game_date, week, metrics, player_id=1, player_type="qb", team="KC", plays=None, touches=None):
    return {
        "player_id": player_id,
        "season": 2025,
        "game_date": game_date,
        "week": week,
        "player_type": player_type,
        "team": team,
        "plays": plays if plays is not None else 0,
        "touches": touches if touches is not None else 0,
        "metrics": metrics,
    }


# --------------------------------------------------------------------------- #
# Exact window recomputation from raw counts
# --------------------------------------------------------------------------- #
def test_cmp_pct_is_recomputed_from_summed_counts_not_averaged():
    """25/40 one game and 15/20 the next is 40/60 = 66.7%, not the mean of
    62.5% and 75.0% (68.75%) — the error averaging per-game rates would give.
    """
    logs = [
        _log("2025-09-08", 1, {"completions": 25, "attempts": 40}),
        _log("2025-09-15", 2, {"completions": 15, "attempts": 20}),
    ]
    assert _aggregate(logs)["cmp_pct"] == pytest.approx(66.7, abs=0.05)


def test_ypa_and_int_rate_from_summed_counts():
    logs = [
        _log("2025-09-08", 1, {"attempts": 30, "passing_yards": 300, "interceptions": 1}),
        _log("2025-09-15", 2, {"attempts": 20, "passing_yards": 100, "interceptions": 1}),
    ]
    result = _aggregate(logs)
    assert result["ypa"] == pytest.approx(400 / 50, abs=0.05)
    assert result["int_rate"] == pytest.approx(100 * 2 / 50, abs=0.05)


def test_passing_epa_rate_divides_by_dropbacks_not_attempts_alone():
    logs = [
        _log("2025-09-08", 1, {"attempts": 30, "sacks_suffered": 2, "passing_epa": 10.0}),
        _log("2025-09-15", 2, {"attempts": 20, "sacks_suffered": 3, "passing_epa": 5.0}),
    ]
    result = _aggregate(logs)
    # 15.0 total EPA over (50 attempts + 5 sacks) = 55 dropbacks.
    assert result["passing_epa"] == pytest.approx(15.0 / 55, abs=0.005)


def test_rushing_epa_is_a_summed_total_not_a_rate():
    logs = [
        _log("2025-09-08", 1, {"carries": 10, "rushing_epa": 2.4}),
        _log("2025-09-15", 2, {"carries": 8, "rushing_epa": -1.1}),
    ]
    assert _aggregate(logs)["rushing_epa"] == pytest.approx(1.3, abs=0.05)


def test_fumble_rate_denominator_is_carries_plus_receptions():
    logs = [
        _log("2025-09-08", 1, {"carries": 15, "receptions": 3, "rushing_fumbles": 1, "receiving_fumbles": 0}),
    ]
    result = _aggregate(logs)
    assert result["fumble_rate"] == pytest.approx(100 * 1 / 18, abs=0.05)


def test_racr_divides_summed_rec_yards_by_summed_air_yards():
    logs = [
        _log("2025-09-08", 1, {"receiving_yards": 60, "receiving_air_yards": 40}),
        _log("2025-09-15", 2, {"receiving_yards": 40, "receiving_air_yards": 20}),
    ]
    assert _aggregate(logs)["racr"] == pytest.approx(100 / 60, abs=0.005)


def test_tackles_combine_solo_and_assists():
    logs = [
        _log("2025-09-08", 1, {"def_tackles_solo": 6, "def_tackle_assists": 2}, player_type="def"),
        _log("2025-09-15", 2, {"def_tackles_solo": 4, "def_tackle_assists": 1}, player_type="def"),
    ]
    assert _aggregate(logs)["tackles"] == 13


# --------------------------------------------------------------------------- #
# Zero-denominator metrics are omitted, not zeroed
# --------------------------------------------------------------------------- #
def test_passing_rates_omitted_when_no_attempts():
    logs = [_log("2025-09-08", 1, {"carries": 10, "rushing_yards": 40})]
    result = _aggregate(logs)
    assert "cmp_pct" not in result
    assert "ypa" not in result
    assert "int_rate" not in result
    assert "passer_rating" not in result
    assert result["rush_yards"] == 40


def test_sack_rate_and_passing_epa_omitted_when_no_dropbacks():
    logs = [_log("2025-09-08", 1, {"attempts": 0, "sacks_suffered": 0, "passing_epa": 0})]
    result = _aggregate(logs)
    assert "sack_rate" not in result
    assert "passing_epa" not in result


def test_ypc_and_rushing_epa_omitted_when_no_carries():
    logs = [_log("2025-09-08", 1, {"receptions": 3, "targets": 4})]
    result = _aggregate(logs)
    assert "ypc" not in result
    assert "rushing_epa" not in result


def test_racr_omitted_when_no_air_yards():
    logs = [_log("2025-09-08", 1, {"receiving_yards": 40, "receiving_air_yards": 0})]
    result = _aggregate(logs)
    assert "racr" not in result


def test_fumble_rate_omitted_when_no_touches():
    logs = [_log("2025-09-08", 1, {"attempts": 30, "carries": 0, "receptions": 0})]
    result = _aggregate(logs)
    assert "fumble_rate" not in result


def test_empty_input_produces_nothing():
    assert _aggregate([]) == {}
    assert build_rows([]) == []


# --------------------------------------------------------------------------- #
# Optional NGS-derived rates: weighted by their own denominator
# --------------------------------------------------------------------------- #
def test_cpoe_weighted_by_attempts_not_averaged_per_game():
    logs = [
        _log("2025-09-08", 1, {"attempts": 40, "cpoe": 10.0}),
        _log("2025-09-15", 2, {"attempts": 10, "cpoe": 0.0}),
    ]
    # (10*40 + 0*10) / 50 = 8.0, not the plain mean of 5.0.
    assert _aggregate(logs)["cpoe"] == pytest.approx(8.0, abs=0.05)


def test_ngs_metric_absent_when_game_logs_never_had_it():
    logs = [_log("2025-09-08", 1, {"attempts": 40})]
    assert "cpoe" not in _aggregate(logs)


# --------------------------------------------------------------------------- #
# League-anchored week windowing
# --------------------------------------------------------------------------- #
def test_window_takes_games_in_the_leagues_latest_n_weeks():
    logs = [
        _log("2025-09-08", 1, {"attempts": 10}),
        _log("2025-09-15", 2, {"attempts": 20}),
        _log("2025-09-22", 3, {"attempts": 30}),
        _log("2025-09-29", 4, {"attempts": 40}),
    ]
    rows = {r["window_weeks"]: r for r in build_rows(logs)}
    three = rows[3]
    assert three["games"] == 3
    assert three["metrics"]["attempts"] == 90  # weeks 2, 3, 4
    assert three["as_of"] == "2025-09-29"
    assert three["start_week"] == 2
    assert three["end_week"] == 4


def test_player_with_fewer_than_n_games_still_gets_a_row():
    """Two games on record: the 5-game window reports games=2, not skipped."""
    logs = [
        _log("2025-09-08", 1, {"attempts": 10}),
        _log("2025-09-15", 2, {"attempts": 20}),
    ]
    rows = {r["window_weeks"]: r for r in build_rows(logs)}
    assert set(rows.keys()) == {3, 5, 8}
    assert rows[5]["games"] == 2
    assert rows[5]["metrics"]["attempts"] == 30
    assert rows[8]["games"] == 2


def test_prior_window_is_the_n_weeks_immediately_before_current():
    dates = [
        "2025-09-08", "2025-09-15", "2025-09-22", "2025-09-29",
        "2025-10-06", "2025-10-13", "2025-10-20",
    ]
    logs = [_log(dates[wk - 1], wk, {"attempts": wk * 10}) for wk in range(1, 8)]
    rows = {r["window_weeks"]: r for r in build_rows(logs)}
    three = rows[3]
    # Current = weeks 5,6,7 (most recent 3); prior = weeks 2,3,4.
    assert three["metrics"]["attempts"] == (5 + 6 + 7) * 10
    assert three["prior_metrics"]["attempts"] == (2 + 3 + 4) * 10


def test_prior_window_shorter_than_n_still_aggregates_whats_there():
    """5 games on record: the 3-game window's prior only has 2 to draw on."""
    logs = [
        _log("2025-09-01", 1, {"attempts": 10}),
        _log("2025-09-08", 2, {"attempts": 20}),
        _log("2025-09-15", 3, {"attempts": 30}),
        _log("2025-09-22", 4, {"attempts": 40}),
        _log("2025-09-29", 5, {"attempts": 50}),
    ]
    rows = {r["window_weeks"]: r for r in build_rows(logs)}
    three = rows[3]
    assert three["games"] == 3
    assert three["metrics"]["attempts"] == 40 + 50 + 30  # weeks 3,4,5
    assert three["prior_metrics"]["attempts"] == 10 + 20  # only weeks 1,2 remain


def test_player_inactive_before_current_window_is_excluded():
    logs = [
        _log("2025-09-01", 1, {"attempts": 10}),
        _log("2025-09-08", 2, {"attempts": 20}),
        _log("2025-09-15", 3, {"attempts": 30}),
        _log(
            "2025-10-20",
            8,
            {"attempts": 30},
            player_id=2,
        ),
    ]
    rows = build_rows(logs)
    player_one = [row for row in rows if row["player_id"] == 1]
    assert all(row["window_weeks"] != 3 for row in player_one)


def test_players_and_sides_stay_independent():
    logs = [
        _log("2025-09-08", 1, {"attempts": 30}, player_id=1, player_type="qb"),
        _log("2025-09-08", 1, {"def_tackles_solo": 5, "def_tackle_assists": 1}, player_id=2, player_type="def"),
    ]
    rows = build_rows(logs)
    by_key = {
        (r["player_id"], r["player_type"], r["window_weeks"]): r
        for r in rows
    }
    assert by_key[(1, "qb", 3)]["metrics"]["attempts"] == 30
    assert by_key[(2, "def", 3)]["metrics"]["tackles"] == 6


def test_unroutable_players_are_excluded_before_rollup():
    logs = [
        _log("2025-09-08", 1, {"attempts": 30}, player_id=1),
        _log("2025-09-08", 1, {"attempts": 20}, player_id=2),
    ]
    assert [row["player_id"] for row in _routable_logs(logs, {2})] == [2]


def test_games_plays_touches_and_team_recorded():
    logs = [
        _log("2025-09-08", 1, {"attempts": 30}, plays=32, touches=25, team="KC"),
        _log("2025-09-15", 2, {"attempts": 20}, plays=22, touches=18, team="KC"),
    ]
    row = next(r for r in build_rows(logs) if r["window_weeks"] == 3)
    assert row["games"] == 2
    assert row["plays"] == 54
    assert row["touches"] == 43
    assert row["team"] == "KC"


# --------------------------------------------------------------------------- #
# Delta
# --------------------------------------------------------------------------- #
def test_delta_only_covers_metrics_present_in_both_windows():
    now = {"cmp_pct": 70.0, "racr": 1.5}
    then = {"cmp_pct": 60.0}
    assert _delta(now, then) == {"cmp_pct": 10.0}


def test_delta_reflects_current_minus_prior_window():
    # Weeks 1-3 (prior, 50% cmp) then weeks 4-6 (current, 75% cmp).
    logs = [
        _log("2025-09-01", 1, {"attempts": 20, "completions": 10}),
        _log("2025-09-08", 2, {"attempts": 20, "completions": 10}),
        _log("2025-09-15", 3, {"attempts": 20, "completions": 10}),
        _log("2025-09-22", 4, {"attempts": 20, "completions": 15}),
        _log("2025-09-29", 5, {"attempts": 20, "completions": 15}),
        _log("2025-10-06", 6, {"attempts": 20, "completions": 15}),
    ]
    row = next(r for r in build_rows(logs) if r["window_weeks"] == 3)
    assert row["metrics"]["cmp_pct"] == pytest.approx(75.0)
    assert row["prior_metrics"]["cmp_pct"] == pytest.approx(50.0)
    assert row["delta"]["cmp_pct"] == pytest.approx(25.0)
