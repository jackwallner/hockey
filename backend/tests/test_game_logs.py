"""Per-game NHL log tests.

Rows must be raw counts keyed exactly as the contract lists (the rollup sums
them), the MoneyPuck join must group by short game id and player, and a final
game must wait until MoneyPuck's shot file contains it rather than ship a false
zero ixG.
"""

from datetime import datetime, timezone

import pandas as pd
import pytest

import ingest_game_logs as logs
from ingest_game_logs import (
    GOALIE_KEYS,
    SKATER_KEYS,
    ShotTables,
    build_game_rows,
    build_shot_tables,
    parse_play_by_play,
    short_game_id,
    toi_seconds,
)

NOW = datetime(2026, 10, 8, 12, tzinfo=timezone.utc)
GAME = {
    "game_id": "2025020001", "season": 2025, "season_type": "REG",
    "game_date": "2025-10-07", "week": 1,
}


def skater(pid, position="C", toi="19:42", **stats):
    base = {
        "playerId": pid, "position": position, "toi": toi, "goals": 0, "assists": 0,
        "points": 0, "plusMinus": 0, "pim": 0, "hits": 0, "powerPlayGoals": 0,
        "sog": 0, "blockedShots": 0, "giveaways": 0, "takeaways": 0,
    }
    base.update(stats)
    return base


def goalie(pid, toi="60:00", **stats):
    base = {
        "playerId": pid, "position": "G", "toi": toi, "starter": True, "decision": "W",
        "shotsAgainst": 20, "saves": 18, "goalsAgainst": 2,
    }
    base.update(stats)
    return base


def boxscore(home=None, away=None, last_period="REG"):
    empty = {"forwards": [], "defense": [], "goalies": []}
    return {
        "homeTeam": {"abbrev": "FLA"}, "awayTeam": {"abbrev": "CHI"},
        "gameOutcome": {"lastPeriodType": last_period},
        "playerByGameStats": {"homeTeam": home or empty, "awayTeam": away or empty},
    }


def tables(skaters=None, goalies=None):
    return ShotTables(skaters=skaters or {}, goalies=goalies or {}, games={20001})


def rows_by_player(rows):
    return {(r["player_id"], r["player_type"]): r for r in rows}


# --------------------------------------------------------------------------- #
def test_toi_parses_minutes_and_seconds():
    assert toi_seconds("19:42") == 1182
    assert toi_seconds("00:00") == 0
    assert toi_seconds(None) == 0
    assert toi_seconds("junk") == 0


def test_short_game_id_matches_the_moneypuck_shot_file():
    assert short_game_id("2025020001") == 20001
    assert short_game_id(2025030186) == 30186


def test_play_by_play_counts_faceoffs_primary_assists_and_blocked_attempts():
    pbp = {"plays": [
        {"typeDescKey": "faceoff", "details": {"winningPlayerId": 1, "losingPlayerId": 2}},
        {"typeDescKey": "faceoff", "details": {"winningPlayerId": 1, "losingPlayerId": 2}},
        {"typeDescKey": "faceoff", "details": {"winningPlayerId": 2, "losingPlayerId": 1}},
        {"typeDescKey": "goal", "details": {"scoringPlayerId": 3, "assist1PlayerId": 1, "assist2PlayerId": 2}},
        {"typeDescKey": "goal", "details": {"scoringPlayerId": 3}},
        {"typeDescKey": "blocked-shot", "details": {"shootingPlayerId": 3, "blockingPlayerId": 1}},
        {"typeDescKey": "shot-on-goal", "details": {"shootingPlayerId": 3}},
    ]}
    stats = parse_play_by_play(pbp)
    assert stats[1] == {"faceoffs_won": 2, "faceoffs_lost": 1, "primary_assists": 1, "blocked_attempts": 0}
    assert stats[2]["faceoffs_won"] == 1 and stats[2]["faceoffs_lost"] == 2
    assert stats[2]["primary_assists"] == 0
    assert stats[3]["blocked_attempts"] == 1


def test_shot_tables_group_by_game_and_player_with_a_high_danger_threshold():
    shots = pd.DataFrame([
        {"game_id": 20001, "xGoal": 0.50, "goal": 1, "shooterPlayerId": 10, "goalieIdForShot": 99},
        {"game_id": 20001, "xGoal": 0.20, "goal": 0, "shooterPlayerId": 10, "goalieIdForShot": 99},
        {"game_id": 20001, "xGoal": 0.19, "goal": 0, "shooterPlayerId": 10, "goalieIdForShot": 99},
        {"game_id": 20002, "xGoal": 0.30, "goal": 0, "shooterPlayerId": 10, "goalieIdForShot": 98},
        {"game_id": 20001, "xGoal": 0.90, "goal": 1, "shooterPlayerId": 11, "goalieIdForShot": 0},
    ])
    built = build_shot_tables(shots)
    assert built.games == {20001, 20002}
    first = built.skaters[(20001, 10)]
    assert first["ixg"] == pytest.approx(0.89)
    assert (first["attempts"], first["hd"]) == (3, 2)
    assert built.skaters[(20002, 10)]["attempts"] == 1
    goalie = built.goalies[(20001, 99)]
    assert goalie["xga"] == pytest.approx(0.89)
    assert (goalie["hd"], goalie["hd_goals"]) == (2, 1)
    # An empty net has no goalie, so it is nobody's xGA.
    assert (20001, 0) not in built.goalies


def test_empty_shot_file_builds_empty_tables():
    built = build_shot_tables(pd.DataFrame(columns=list(logs.SHOT_COLUMNS)))
    assert built.games == set() and built.skaters == {}


# --------------------------------------------------------------------------- #
def test_skater_row_has_exactly_the_contract_keys_and_raw_counts():
    box = boxscore(home={
        "forwards": [skater(1, goals=1, assists=2, points=3, sog=4, hits=2, blockedShots=1,
                            takeaways=1, giveaways=2, pim=2, plusMinus=-1, powerPlayGoals=1)],
        "defense": [], "goalies": [],
    })
    pbp = {1: {"faceoffs_won": 8, "faceoffs_lost": 5, "primary_assists": 1, "blocked_attempts": 2}}
    shots = tables(skaters={(20001, 1): {"ixg": 0.84321, "attempts": 6, "hd": 2}})
    rows = build_game_rows(GAME, box, pbp, shots, NOW)
    assert len(rows) == 1
    row = rows[0]
    assert set(row["metrics"]) == set(SKATER_KEYS)
    assert row["metrics"] == {
        "goals": 1, "assists": 2, "primary_assists": 1, "points": 3,
        "shots_on_goal": 4, "shot_attempts": 8, "ixg": 0.843, "hd_shots": 2,
        "hits": 2, "blocks": 1, "takeaways": 1, "giveaways": 2, "pim": 2,
        "plus_minus": -1, "pp_goals": 1, "faceoffs_won": 8, "faceoffs_lost": 5,
        "toi_seconds": 1182,
    }
    assert "points_per_60" not in row["metrics"]
    assert row["plays"] == 19
    assert row["touches"] == 8  # unblocked attempts + the shooter's blocked ones


def test_row_identity_and_context_columns():
    box = boxscore(away={"forwards": [skater(7)], "defense": [], "goalies": []})
    row = build_game_rows(GAME, box, {}, tables(), NOW)[0]
    assert row["player_id"] == 7 and row["player_type"] == "f"
    assert (row["season"], row["season_type"]) == (2025, "REG")
    assert (row["game_id"], row["game_date"], row["week"]) == ("2025020001", "2025-10-07", 1)
    assert (row["team"], row["opponent"]) == ("CHI", "FLA")
    assert row["updated_at"] == NOW.isoformat()


def test_home_player_faces_the_away_club():
    box = boxscore(home={"forwards": [skater(7)], "defense": [], "goalies": []})
    row = build_game_rows(GAME, box, {}, tables(), NOW)[0]
    assert (row["team"], row["opponent"]) == ("FLA", "CHI")


def test_a_skater_missing_from_the_shot_file_gets_zero_ixg_not_an_error():
    box = boxscore(home={"forwards": [skater(1, sog=2)], "defense": [], "goalies": []})
    row = build_game_rows(GAME, box, {}, tables(), NOW)[0]
    assert row["metrics"]["ixg"] == 0 and row["metrics"]["shot_attempts"] == 0
    assert row["metrics"]["faceoffs_won"] == 0
    assert row["metrics"]["primary_assists"] == 0


def test_player_type_follows_the_position_code():
    box = boxscore(home={
        "forwards": [skater(1, "C"), skater(2, "L"), skater(3, "R")],
        "defense": [skater(4, "D")],
        "goalies": [],
    })
    kinds = {r["player_id"]: r["player_type"] for r in build_game_rows(GAME, box, {}, tables(), NOW)}
    assert kinds == {1: "f", 2: "f", 3: "f", 4: "d"}


def test_a_listed_skater_without_ice_time_is_dropped():
    box = boxscore(home={"forwards": [skater(1, toi="00:00")], "defense": [], "goalies": []})
    assert build_game_rows(GAME, box, {}, tables(), NOW) == []


def test_goalie_row_has_exactly_the_contract_keys():
    box = boxscore(home={"forwards": [], "defense": [], "goalies": [goalie(30)]})
    shots = tables(goalies={(20001, 30): {"xga": 2.31234, "hd": 5, "hd_goals": 1}})
    row = build_game_rows(GAME, box, {}, shots, NOW)[0]
    assert set(row["metrics"]) == set(GOALIE_KEYS)
    assert row["metrics"] == {
        "shots_against": 20, "saves": 18, "goals_against": 2, "xga": 2.312,
        "hd_shots_against": 5, "hd_goals_against": 1, "toi_seconds": 3600,
        "decision_win": 1, "shutout": 0, "started": 1,
    }
    assert row["player_type"] == "g"
    assert row["plays"] == 60
    assert row["touches"] == 20  # shots against


def test_the_unused_backup_goalie_has_no_row():
    box = boxscore(home={"forwards": [], "defense": [], "goalies": [
        goalie(30), goalie(31, toi="00:00", starter=False, decision=None, shotsAgainst=0, saves=0, goalsAgainst=0),
    ]})
    rows = build_game_rows(GAME, box, {}, tables(), NOW)
    assert [r["player_id"] for r in rows] == [30]


def test_shutout_needs_a_win_no_goals_and_the_only_goalie():
    clean = goalie(30, goalsAgainst=0, saves=20)
    box = boxscore(home={"forwards": [], "defense": [], "goalies": [clean]})
    assert build_game_rows(GAME, box, {}, tables(), NOW)[0]["metrics"]["shutout"] == 1

    split = boxscore(home={"forwards": [], "defense": [], "goalies": [
        goalie(30, toi="30:00", goalsAgainst=0), goalie(31, toi="30:00", goalsAgainst=0, starter=False),
    ]})
    assert all(r["metrics"]["shutout"] == 0 for r in build_game_rows(GAME, split, {}, tables(), NOW))

    loss = boxscore(home={"forwards": [], "defense": [], "goalies": [goalie(30, goalsAgainst=0, decision="L")]})
    assert build_game_rows(GAME, loss, {}, tables(), NOW)[0]["metrics"]["shutout"] == 0


def test_a_shootout_win_is_not_a_shutout():
    box = boxscore(
        home={"forwards": [], "defense": [], "goalies": [goalie(30, toi="65:00", goalsAgainst=0)]},
        last_period="SO",
    )
    assert build_game_rows(GAME, box, {}, tables(), NOW)[0]["metrics"]["shutout"] == 0


# --------------------------------------------------------------------------- #
def _patch_sources(monkeypatch, *, box=True, pbp=True):
    full = boxscore(home={"forwards": [skater(1)], "defense": [], "goalies": [goalie(30)]})

    def fetch(game_id, kind):
        if kind == "boxscore":
            return full if box else None
        return {"plays": []} if pbp else None

    monkeypatch.setattr(logs, "fetch_gamecenter", fetch)


def _game(game_id):
    return {**GAME, "game_id": game_id}


def test_a_final_missing_from_the_shot_file_waits(monkeypatch):
    _patch_sources(monkeypatch)
    pending: list[str] = []
    built = list(logs.iter_game_rows([_game("2025020001"), _game("2025020002")], tables(), NOW, pending))
    assert [g for g, _ in built] == ["2025020001"]
    assert pending == ["2025020002"]


def test_no_shot_file_defers_every_game(monkeypatch):
    _patch_sources(monkeypatch)
    pending: list[str] = []
    assert list(logs.iter_game_rows([_game("2025020001")], None, NOW, pending)) == []
    assert pending == ["2025020001"]


@pytest.mark.parametrize("kwargs", [{"box": False}, {"pbp": False}])
def test_missing_nhl_payloads_defer_the_game(monkeypatch, kwargs):
    _patch_sources(monkeypatch, **kwargs)
    pending: list[str] = []
    assert list(logs.iter_game_rows([_game("2025020001")], tables(), NOW, pending)) == []
    assert pending == ["2025020001"]


def test_a_failing_game_does_not_stop_the_rest(monkeypatch):
    def fetch(game_id, kind):
        if game_id == "2025020001":
            raise RuntimeError("boom")
        return boxscore(home={"forwards": [skater(1)], "defense": [], "goalies": []}) if kind == "boxscore" else {"plays": []}

    monkeypatch.setattr(logs, "fetch_gamecenter", fetch)
    shots = ShotTables(games={20001, 20002})
    pending: list[str] = []
    built = list(logs.iter_game_rows([_game("2025020001"), _game("2025020002")], shots, NOW, pending))
    assert [g for g, _ in built] == ["2025020002"]
    assert pending == ["2025020001"]


def test_incremental_build_skips_games_that_already_have_rows(monkeypatch):
    _patch_sources(monkeypatch)
    finals = [_game("2025020001"), _game("2025020002")]
    monkeypatch.setattr(logs, "fetch_final_games", lambda client, season: finals)
    monkeypatch.setattr(logs, "logged_game_ids", lambda client, season: {"2025020001"})
    monkeypatch.setattr(logs, "load_shot_tables", lambda season, live: ShotTables(games={20001, 20002}))
    batch = logs.build_new_rows(object(), 2025, NOW)
    assert batch.done == ["2025020002"] and batch.pending == []
    assert {r["game_id"] for r in batch.rows} == {"2025020002"}
    assert batch.shots_status == "ready"


def test_full_build_redoes_every_final_and_reports_pending(monkeypatch):
    _patch_sources(monkeypatch)
    finals = [_game("2025020001"), _game("2025020003")]
    monkeypatch.setattr(logs, "fetch_final_games", lambda client, season: finals)
    monkeypatch.setattr(logs, "logged_game_ids", lambda client, season: {"2025020001"})
    monkeypatch.setattr(logs, "load_shot_tables", lambda season, live: ShotTables(games={20001}))
    batch = logs.build_new_rows(object(), 2025, NOW, full=True)
    assert batch.done == ["2025020001"] and batch.pending == ["2025020003"]
    assert batch.shots_status == "pending"


def test_nothing_to_do_makes_no_network_calls(monkeypatch):
    monkeypatch.setattr(logs, "fetch_final_games", lambda client, season: [_game("2025020001")])
    monkeypatch.setattr(logs, "logged_game_ids", lambda client, season: {"2025020001"})

    def boom(*args, **kwargs):
        raise AssertionError("downloaded the shot file with nothing to ingest")

    monkeypatch.setattr(logs, "load_shot_tables", boom)
    assert logs.build_new_rows(object(), 2025, NOW).rows == []
