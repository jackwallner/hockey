from datetime import datetime, timezone

import pytest

import refresh
from ingest_game_logs import GameBatch
from refresh import (
    Candidate,
    CandidateNotReady,
    Coverage,
    _validate_unique,
    compute_coverage,
    content_hash,
    merge_logs,
)

NOW = datetime(2026, 10, 8, 18, 0, tzinfo=timezone.utc)


def final(game_id):
    return {"game_id": game_id}


def log(game_id, player_id=1, game_date="2026-10-07", week=2, **extra):
    return {
        "player_id": player_id, "season": 2026, "season_type": "REG", "game_id": game_id,
        "game_date": game_date, "week": week, "player_type": "f", "team": "EDM",
        "opponent": "CGY", "plays": 20, "touches": 4, "metrics": {"goals": 1},
        "updated_at": "2026-10-08T00:00:00+00:00", **extra,
    }


# --------------------------------------------------------------------------- #
# Coverage: finals in the games table against finals with game-log rows
# --------------------------------------------------------------------------- #
def test_coverage_is_complete_when_every_final_has_rows():
    coverage = compute_coverage([final("a"), final("b")], [log("a"), log("b", game_date="2026-10-09", week=3)])
    assert coverage == Coverage(3, "2026-10-09", 2, 2, "complete")


def test_a_final_without_rows_makes_coverage_partial():
    coverage = compute_coverage([final("a"), final("b")], [log("a")])
    assert (coverage.expected_games, coverage.observed_games) == (2, 1)
    assert coverage.coverage_status == "partial"


def test_logs_for_games_missing_from_the_table_do_not_count_as_observed():
    coverage = compute_coverage([final("a")], [log("a"), log("zz")])
    assert (coverage.expected_games, coverage.observed_games) == (1, 1)


def test_no_logs_means_no_week_or_date():
    coverage = compute_coverage([final("a")], [])
    assert (coverage.max_week, coverage.max_game_date, coverage.coverage_status) == (None, None, "partial")


def test_no_finals_is_complete():
    assert compute_coverage([], []).coverage_status == "complete"


# --------------------------------------------------------------------------- #
def test_merge_keeps_published_rows_and_lets_a_new_row_win():
    old = [log("a", player_id=1), log("a", player_id=2)]
    new = [{**log("a", player_id=2), "metrics": {"goals": 9}}, log("b", player_id=1, game_date="2026-10-09")]
    merged = merge_logs(old, new)
    assert len(merged) == 3
    assert next(r for r in merged if r["player_id"] == 2)["metrics"] == {"goals": 9}


def test_candidate_key_validation_rejects_duplicate_rows():
    rows = [{"id": 1, "season": 2026, "season_type": "REG"}]
    _validate_unique(rows, ("id", "season", "season_type"), "snapshots")
    with pytest.raises(RuntimeError, match="duplicate key"):
        _validate_unique(rows * 2, ("id", "season", "season_type"), "snapshots")


def test_candidate_key_validation_rejects_incomplete_keys():
    with pytest.raises(CandidateNotReady, match="incomplete key"):
        _validate_unique([{"id": None, "season": 2026}], ("id", "season"), "snapshots")


# --------------------------------------------------------------------------- #
def _candidate(stamp: str, goals=205, **overrides):
    values = dict(
        season=2026,
        season_types=("REG",),
        snapshots=({"id": 1, "season": 2026, "updated_at": stamp, "standard_stats": [{"label": "G", "value": goals}]},),
        game_logs=({"player_id": 1, "game_date": "2026-10-10", "updated_at": stamp, "metrics": {"ixg": 1.0}},),
        recent_form=({"player_id": 1, "window_weeks": 2, "updated_at": stamp},),
        coverage=Coverage(1, "2026-10-10", 2, 2, "complete"),
        shots_status="ready",
        summary_status="ready",
    )
    values.update(overrides)
    return Candidate(**values)


def test_content_hash_ignores_build_timestamps():
    assert content_hash(_candidate("2026-10-09T10:00:00Z")) == content_hash(_candidate("2026-10-09T17:49:00Z"))


def test_content_hash_changes_with_a_stat():
    assert content_hash(_candidate("x", 205)) != content_hash(_candidate("x", 206))


def test_content_hash_treats_a_whole_number_float_like_an_int():
    """The same ixG read back from Postgres (1.0) and freshly built (1) must hash alike."""
    as_int = _candidate("x", game_logs=({"player_id": 1, "game_date": "d", "metrics": {"ixg": 1}},))
    as_float = _candidate("x", game_logs=({"player_id": 1, "game_date": "d", "metrics": {"ixg": 1.0}},))
    assert content_hash(as_int) == content_hash(as_float)


# --------------------------------------------------------------------------- #
# build_candidate wiring (network and database replaced)
# --------------------------------------------------------------------------- #
def _snapshot(pid=1, phase="REG"):
    return {"id": pid, "season": 2026, "season_type": phase, "updated_at": "x"}


@pytest.fixture
def wired(monkeypatch):
    state = {
        "snapshots": ([_snapshot(1)], "ready"),
        "existing": [log("a")],
        "batch": GameBatch(rows=[log("b", game_date="2026-10-09", week=3)], done=["b"]),
        "finals": [final("a"), final("b")],
    }
    monkeypatch.setattr(refresh, "build_snapshots", lambda season, now: state["snapshots"])
    monkeypatch.setattr(refresh, "fetch_serving_logs", lambda client, season: state["existing"])
    monkeypatch.setattr(refresh, "fetch_final_games", lambda client, season: state["finals"])

    def new_rows(client, season, now, **kwargs):
        state["kwargs"] = kwargs
        if isinstance(state["batch"], Exception):
            raise state["batch"]
        return state["batch"]

    monkeypatch.setattr(refresh, "build_new_rows", new_rows)
    return state


def build(wired, **kwargs):
    return refresh.build_candidate(2026, client=object(), now=NOW, **kwargs)


def test_candidate_stages_the_published_rows_plus_the_new_finals(wired):
    candidate = build(wired)
    assert {r["game_id"] for r in candidate.game_logs} == {"a", "b"}
    assert candidate.coverage == Coverage(3, "2026-10-09", 2, 2, "complete")
    assert candidate.shots_status == "ready" and candidate.summary_status == "ready"
    assert candidate.season_types == ("REG",)
    assert {r["window_weeks"] for r in candidate.recent_form} == {2, 4, 8}


def test_finals_moneypuck_has_not_published_show_as_pending_and_partial(wired):
    wired["batch"] = GameBatch(rows=[], pending=["b"])
    candidate = build(wired)
    assert candidate.coverage.coverage_status == "partial"
    assert candidate.shots_status == "pending"
    assert {r["game_id"] for r in candidate.game_logs} == {"a"}


def test_a_shot_file_failure_keeps_the_published_logs_and_reports_degraded(wired):
    wired["batch"] = RuntimeError("shots download failed")
    candidate = build(wired)
    assert candidate.shots_status == "degraded"
    assert {r["game_id"] for r in candidate.game_logs} == {"a"}


def test_full_logs_flag_reaches_the_ingest(wired):
    build(wired, full_logs=True)
    assert wired["kwargs"]["full"] is True


def test_no_snapshots_is_not_ready(wired):
    wired["snapshots"] = ([], "unknown")
    with pytest.raises(CandidateNotReady, match="no snapshot rows"):
        build(wired)


def test_no_game_logs_is_not_ready(wired):
    wired["existing"], wired["batch"], wired["finals"] = [], GameBatch(), []
    with pytest.raises(CandidateNotReady, match="no game-log rows"):
        build(wired)


def test_logs_for_a_phase_without_snapshots_are_not_published(wired):
    wired["existing"] = [log("a"), {**log("p", player_id=1), "season_type": "POST"}]
    candidate = build(wired)
    assert {r["season_type"] for r in candidate.game_logs} == {"REG"}


def test_recent_form_only_includes_players_with_a_snapshot(wired):
    wired["existing"] = [log("a", player_id=1), log("a", player_id=2)]
    candidate = build(wired)
    assert {r["player_id"] for r in candidate.recent_form} == {1}
    assert len(candidate.game_logs) == 3  # logs are kept for every player


def test_summary_statuses_merge_to_the_worst():
    assert refresh._merge_status("ready", "degraded", "pending") == "degraded"
    assert refresh._merge_status("ready", "pending") == "pending"
    assert refresh._merge_status() == "unknown"


# --------------------------------------------------------------------------- #
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
    client = _FlakyRPC([RuntimeError("{'code': 504, 'details': 'Gateway Timeout'}")])
    assert refresh._rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None) == {"status": "unchanged"}
    assert client.calls == 2


def test_rpc_treats_already_applied_retry_as_done():
    client = _FlakyRPC([RuntimeError("504 Gateway Timeout"), RuntimeError("refresh x is already unchanged")])
    assert refresh._rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None) == {"status": "already_applied"}


def test_rpc_does_not_retry_real_errors():
    client = _FlakyRPC([RuntimeError("refresh output differs from the live revision")])
    with pytest.raises(RuntimeError):
        refresh._rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None)
    assert client.calls == 1


def test_refusing_a_different_supabase_project(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://qwkmpwnhrejsuplcwxrb.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "key")
    with pytest.raises(RuntimeError, match="Hockey"):
        refresh._client()
