from datetime import datetime, timezone

import pandas as pd
import pytest

from refresh import _coverage, _validate_unique


NOW = datetime(2026, 9, 12, 18, 0, tzinfo=timezone.utc)


def test_coverage_allows_a_valid_early_week_when_another_game_is_pending():
    schedule = pd.DataFrame([
        {"season": 2026, "game_id": "2026_01_A_B", "gameday": "2026-09-10", "game_type": "REG"},
        {"season": 2026, "game_id": "2026_01_C_D", "gameday": "2026-09-13", "game_type": "REG"},
    ])
    weekly = pd.DataFrame([
        {"season": 2026, "game_id": "2026_01_A_B", "week": 1},
    ])

    coverage = _coverage(weekly, schedule, 2026, NOW)

    assert coverage.expected_games == 1
    assert coverage.observed_games == 1
    assert coverage.coverage_status == "complete"
    assert coverage.max_week == 1
    assert coverage.max_game_date == "2026-09-10"


def test_coverage_marks_missing_completed_source_games_partial():
    schedule = pd.DataFrame([
        {"season": 2026, "game_id": "2026_01_A_B", "gameday": "2026-09-10", "game_type": "REG"},
        {"season": 2026, "game_id": "2026_01_C_D", "gameday": "2026-09-11", "game_type": "REG"},
    ])
    weekly = pd.DataFrame([
        {"season": 2026, "game_id": "2026_01_A_B", "week": 1},
    ])

    coverage = _coverage(weekly, schedule, 2026, NOW)

    assert coverage.expected_games == 2
    assert coverage.observed_games == 1
    assert coverage.coverage_status == "partial"


def test_coverage_does_not_count_preseason_games():
    schedule = pd.DataFrame([
        {"season": 2026, "game_id": "2026_00_A_B", "gameday": "2026-08-28", "game_type": "PRE"},
    ])
    weekly = pd.DataFrame([
        {"season": 2026, "game_id": "2026_00_A_B", "week": 0},
    ])

    coverage = _coverage(weekly, schedule, 2026, NOW)

    assert coverage.expected_games == 0
    assert coverage.observed_games == 1


def test_candidate_key_validation_rejects_duplicate_rows():
    rows = [{"id": 1, "season": 2026, "season_type": "REG"}]
    _validate_unique(rows, ("id", "season", "season_type"), "snapshots")
    with pytest.raises(RuntimeError, match="duplicate key"):
        _validate_unique(rows * 2, ("id", "season", "season_type"), "snapshots")


def _candidate(stamp: str, passing_yards: int = 205):
    from refresh import Candidate, Coverage

    return Candidate(
        season=2026,
        season_types=("REG",),
        snapshots=({"id": 1, "season": 2026, "updated_at": stamp, "standard_stats": [{"label": "Pass Yds", "value": passing_yards}]},),
        game_logs=({"player_id": 1, "game_date": "2026-09-10", "updated_at": stamp},),
        recent_form=({"player_id": 1, "window_weeks": 3, "updated_at": stamp},),
        coverage=Coverage(1, "2026-09-10", 2, 2, "complete"),
        ngs_status="ready",
        pfr_status="pending",
    )


def test_content_hash_ignores_build_timestamps():
    from refresh import content_hash

    assert content_hash(_candidate("2026-09-13T10:00:00Z")) == content_hash(_candidate("2026-09-13T17:49:00Z"))


def test_content_hash_changes_with_a_stat():
    from refresh import content_hash

    assert content_hash(_candidate("x", 205)) != content_hash(_candidate("x", 206))


class _FlakyRPC:
    def __init__(self, errors):
        self.errors = list(errors)
        self.calls = 0

    def rpc(self, function, params):
        return self

    def execute(self):
        self.calls += 1
        if self.errors:
            raise self.errors.pop(0)
        return type("R", (), {"data": [{"status": "unchanged"}]})()


def test_rpc_retries_gateway_timeouts():
    from refresh import _rpc
    client = _FlakyRPC([RuntimeError("{'code': 504, 'details': 'Gateway Timeout'}")])
    assert _rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None) == {"status": "unchanged"}
    assert client.calls == 2


def test_rpc_treats_already_applied_retry_as_done():
    from refresh import _rpc
    client = _FlakyRPC([RuntimeError("504 Gateway Timeout"), RuntimeError("refresh x is already unchanged")])
    assert _rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None) == {"status": "already_applied"}


def test_rpc_does_not_retry_real_errors():
    import pytest
    from refresh import _rpc
    client = _FlakyRPC([RuntimeError("refresh output differs from the live revision")])
    with pytest.raises(RuntimeError):
        _rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None)
    assert client.calls == 1
