from datetime import datetime, timezone

import pandas as pd
import pytest

import ingest_game_details as gd
from ingest_game_logs import build_shot_tables

NOW = datetime(2026, 10, 8, tzinfo=timezone.utc)
GAME = {
    "game_id": "2026020001", "season": 2026, "season_type": "REG", "week": 1,
    "away_team": "FLA", "home_team": "CAR", "away_score": 1, "home_score": 2, "overtime": False,
}


def shot(**overrides):
    row = {
        "game_id": 20001, "event": "SHOT", "period": 1, "time": 100, "xGoal": 0.05, "goal": 0,
        "team": "AWAY", "teamCode": "FLA", "shooterPlayerId": 1, "shooterName": "Away Skater",
        "goalieIdForShot": 31, "shotType": "WRIST", "arenaAdjustedShotDistance": 30.0,
        "shotDistance": 30.0, "shotRebound": 0, "shotRush": 0, "shotOnEmptyNet": 0,
        "shotWasOnGoal": 1, "homeSkatersOnIce": 5, "awaySkatersOnIce": 5,
        "homeEmptyNet": 0, "awayEmptyNet": 0, "shotID": 0,
    }
    row.update(overrides)
    return row


def shots_frame():
    """FLA 1 (one xG 0.30 goal, one shot on the power play), CAR 2 (one empty-net goal)."""
    return pd.DataFrame([
        shot(time=100, xGoal=0.05, shotID=1),
        shot(time=400, xGoal=0.30, goal=1, event="GOAL", shotType="SNAP", arenaAdjustedShotDistance=20.0,
             shooterPlayerId=2, shooterName="Away Sniper", shotID=2),
        shot(time=700, xGoal=0.10, team="HOME", teamCode="CAR", shooterPlayerId=11, shooterName="Home One",
             goalieIdForShot=30, event="MISS", shotWasOnGoal=0, shotID=3),
        shot(time=1300, period=2, xGoal=0.40, goal=1, event="GOAL", team="HOME", teamCode="CAR",
             shooterPlayerId=12, shooterName="Home Two", goalieIdForShot=30, shotRebound=1, shotType="TIP",
             arenaAdjustedShotDistance=8.0, shotID=4),
        shot(time=2000, period=2, xGoal=0.08, awaySkatersOnIce=4, shotID=5),
        shot(time=3590, period=3, xGoal=0.02, goal=1, event="GOAL", team="HOME", teamCode="CAR",
             shooterPlayerId=11, shooterName="Home One", goalieIdForShot=0, shotOnEmptyNet=1, awayEmptyNet=1,
             awaySkatersOnIce=6, shotType="WRIST", arenaAdjustedShotDistance=150.0, shotID=6),
    ])


def box_player(pid, name, toi, position="C", **stats):
    row = {
        "playerId": pid, "name": {"default": name}, "position": position, "toi": toi,
        "goals": 0, "assists": 0, "points": 0, "sog": 0, "hits": 0, "blockedShots": 0,
        "pim": 0, "powerPlayGoals": 0,
    }
    row.update(stats)
    return row


def goalie(pid, name, toi, saves, against, shots_against):
    return {
        "playerId": pid, "name": {"default": name}, "position": "G", "toi": toi,
        "saves": saves, "goalsAgainst": against, "shotsAgainst": shots_against, "starter": True,
    }


def boxscore():
    return {
        "gameType": 2,
        "periodDescriptor": {"number": 3, "periodType": "REG"},
        "clock": {"secondsRemaining": 0},
        "awayTeam": {"abbrev": "FLA", "sog": 2},
        "homeTeam": {"abbrev": "CAR", "sog": 1},
        "playerByGameStats": {
            "awayTeam": {
                "forwards": [
                    box_player(1, "A. Skater", "18:00", sog=1, hits=2),
                    box_player(2, "A. Sniper", "05:00", goals=1, assists=0, points=1, sog=1, powerPlayGoals=1),
                ],
                "defense": [box_player(3, "A. Blueliner", "20:00", "D", assists=1, points=1, blockedShots=2, pim=2)],
                "goalies": [goalie(30, "A. Goalie", "59:50", 0, 1, 1)],
            },
            "homeTeam": {
                "forwards": [box_player(11, "H. One", "17:30", goals=1, points=1, sog=1)],
                "defense": [box_player(12, "H. Two", "21:00", "D", goals=1, points=1)],
                "goalies": [goalie(31, "H. Goalie", "60:00", 2, 1, 3)],
            },
        },
    }


def play_by_play():
    return {
        "homeTeam": {"id": 12}, "awayTeam": {"id": 13},
        "rosterSpots": [
            {"playerId": 1, "firstName": {"default": "Alex"}, "lastName": {"default": "Skater"}},
            {"playerId": 11, "firstName": {"default": "Hank"}, "lastName": {"default": "One"}},
        ],
        "plays": [
            {"typeDescKey": "blocked-shot", "situationCode": "1551",
             "details": {"eventOwnerTeamId": 13, "shootingPlayerId": 1}},
            {"typeDescKey": "blocked-shot", "situationCode": "1451",
             "details": {"eventOwnerTeamId": 13, "shootingPlayerId": 1}},
            {"typeDescKey": "blocked-shot", "situationCode": "1551",
             "details": {"eventOwnerTeamId": 12, "shootingPlayerId": 11}},
            {"typeDescKey": "goal", "details": {"assist1PlayerId": 3, "scoringPlayerId": 2}},
        ],
    }


def right_rail():
    return {"teamGameStats": [
        {"category": "faceoffWins", "awayValue": "20/50", "homeValue": "30/50"},
        {"category": "powerPlay", "awayValue": "1/3", "homeValue": "0/2"},
        {"category": "pim", "awayValue": 4, "homeValue": 6},
        {"category": "hits", "awayValue": 9, "homeValue": 7},
        {"category": "blockedShots", "awayValue": 5, "homeValue": 3},
    ]}


def build():
    frame = shots_frame()
    return gd.build_game_row(
        GAME, frame, build_shot_tables(frame), boxscore(), play_by_play(), right_rail(), NOW
    )


# ---- descriptions and clocks ------------------------------------------------
def test_clock_is_elapsed_time_in_the_period():
    assert gd.clock_text(263, 1) == "4:23"
    assert gd.clock_text(1202, 2) == "0:02"
    assert gd.clock_text(3895, 4) == "4:55"
    assert gd.clock_text(4805, 5) == "0:05"  # second overtime of a playoff game


def test_description_reads_shot_type_distance_and_flags():
    text = gd.shot_description({"shotType": "SNAP", "arenaAdjustedShotDistance": 20.0, "shotRebound": 1})
    assert text == "Snap shot, slot, rebound"
    empty = gd.shot_description({"shotType": "WRIST", "arenaAdjustedShotDistance": 150.0, "shotOnEmptyNet": 1})
    assert empty == "Wrist shot, long range, empty net"
    assert gd.shot_description({"shotType": float("nan"), "shotDistance": 5.0, "shotRush": 1}) == "Shot, in close, rush"


def test_distance_bands_are_ordered_by_feet():
    labels = [gd.distance_band(feet) for feet in (3, 20, 35, 55, 80)]
    assert labels == ["in close", "slot", "mid-range", "from the point", "long range"]


# ---- the xG race --------------------------------------------------------------
def test_race_accumulates_and_ends_with_the_official_score():
    race = gd.xg_race(gd.ordered_shots(shots_frame()), 1, 2, 3600)
    assert len(race) == 7  # six shots plus the end of the game
    assert race[1] == [400, 0.35, 0.0, 1, 0]
    assert race[3] == [1300, 0.35, 0.5, 1, 1]
    assert race[-1] == [3600, 0.43, 0.52, 1, 2]
    assert all(len(point) == 5 for point in race)
    times = [point[0] for point in race]
    assert times == sorted(times)


def test_a_shootout_finish_carries_the_official_score_not_the_shot_goals():
    tied = gd.xg_race(gd.ordered_shots(shots_frame()), 2, 2, 3900)
    assert tied[-1][0] == 3900 and tied[-1][3:] == [2, 2]
    # Shot-file goals alone (1-2) would have read as a regulation result.
    unknown = gd.xg_race(gd.ordered_shots(shots_frame()), None, None, 3600)
    assert unknown[-1][3:] == [1, 2]


def test_a_game_with_no_shots_still_has_an_ending():
    race = gd.xg_race(gd.ordered_shots(shots_frame().iloc[0:0]), 0, 0, 3600)
    assert race == [[3600, 0.0, 0.0, 0, 0]]


def test_game_end_follows_the_period_and_clock():
    regulation = {"periodDescriptor": {"number": 3, "periodType": "REG"}, "clock": {"secondsRemaining": 0}}
    assert gd.game_end_seconds(regulation) == 3600
    overtime = {"gameType": 2, "periodDescriptor": {"number": 4, "periodType": "OT"}, "clock": {"secondsRemaining": 5}}
    assert gd.game_end_seconds(overtime) == 3895
    shootout = {"periodDescriptor": {"number": 5, "periodType": "SO"}, "clock": {"secondsRemaining": 0}}
    assert gd.game_end_seconds(shootout) == 3900
    double_ot = {"gameType": 3, "periodDescriptor": {"number": 5, "periodType": "OT"}, "clock": {"secondsRemaining": 300}}
    assert gd.game_end_seconds(double_ot) == 4800 + 900  # 15:00 into the second overtime
    assert gd.game_end_seconds(None, 3700) == 3700


# ---- big plays ----------------------------------------------------------------
def test_big_plays_keep_every_goal_and_the_five_best_chances():
    rows = [shot(time=t, xGoal=x, shotID=t) for t, x in
            ((10, 0.01), (20, 0.50), (30, 0.20), (40, 0.30), (50, 0.15), (60, 0.25), (70, 0.12), (80, 0.40))]
    rows += [shot(time=90, xGoal=0.01, goal=1, team="HOME", teamCode="CAR", shotID=90),
             shot(time=95, xGoal=0.03, event="MISS", shotWasOnGoal=0, shotID=95)]
    plays = gd.big_plays(gd.ordered_shots(pd.DataFrame(rows)))
    xgs = [p["xg"] for p in plays]
    assert len(plays) == 6  # five best non-goals plus the goal
    assert sorted(xgs) == [0.01, 0.2, 0.25, 0.3, 0.4, 0.5]  # the 0.15, 0.12 and 0.03 chances are out
    assert [p["clock"] for p in plays] == ["0:20", "0:30", "0:40", "1:00", "1:20", "1:30"]
    assert plays[-1]["result"] == "GOAL" and plays[-1]["team"] == "CAR"
    assert {p["result"] for p in plays} <= {"GOAL", "SAVE", "MISS", "BLOCK"}


def test_big_play_fields_match_the_contract():
    plays = gd.big_plays(gd.ordered_shots(shots_frame()))
    goal = next(p for p in plays if p["player_id"] == 12)
    assert goal == {
        "period": 2, "clock": "1:40", "team": "CAR", "description": "Tip-in, in close, rebound",
        "xg": 0.4, "result": "GOAL", "player_id": 12, "shooter": "Home Two",
    }
    empty_net = next(p for p in plays if p["player_id"] == 11 and p["result"] == "GOAL")
    assert empty_net["description"] == "Wrist shot, long range, empty net"
    miss = next(p for p in plays if p["result"] == "MISS")
    assert miss["player_id"] == 11


# ---- team stats ----------------------------------------------------------------
def test_team_totals_split_five_on_five_and_leave_out_empty_net_strength():
    totals = gd.team_shot_totals(shots_frame())
    assert totals["AWAY"]["xg"] == pytest.approx(0.43)
    assert totals["AWAY"]["xg_5v5"] == pytest.approx(0.35)  # the 4-skater shot is not 5v5
    assert totals["HOME"]["xg_5v5"] == pytest.approx(0.50)  # the empty-net goal is not 5v5
    assert totals["HOME"]["goals"] == 2 and totals["AWAY"]["goals"] == 1
    assert totals["HOME"]["hd"] == 1 and totals["AWAY"]["hd"] == 1
    assert totals["AWAY"]["sog"] == 3 and totals["HOME"]["sog"] == 2


def test_blocked_attempts_are_credited_to_the_shooting_team():
    blocked = gd.blocked_attempts(play_by_play())
    assert blocked["AWAY"] == {"all": 2, "5v5": 1}
    assert blocked["HOME"] == {"all": 1, "5v5": 1}
    assert gd.blocked_attempts(None)["HOME"] == {"all": 0, "5v5": 0}


def test_rail_gives_special_teams_and_faceoffs():
    rail = gd.parse_rail(right_rail())
    assert rail["AWAY"]["faceoff_wins"] == 20 and rail["AWAY"]["faceoff_total"] == 50
    assert (rail["AWAY"]["pp_goals"], rail["AWAY"]["pp_opportunities"]) == (1, 3)
    assert rail["HOME"]["pim"] == 6 and rail["HOME"]["blocks"] == 3
    empty = gd.parse_rail(None)
    assert empty["AWAY"]["pp_opportunities"] is None and empty["AWAY"]["hits"] is None


def test_team_stats_use_rail_totals_and_count_blocked_attempts():
    stats = build()["team_stats"]
    away, home = stats["away"], stats["home"]
    assert away["xg"] == 0.43 and home["xg"] == 0.52
    assert away["xg_5v5"] == 0.35
    assert away["xgf_pct_5v5"] == pytest.approx(0.35 / 0.85, abs=1e-4)
    # 5v5 attempts: FLA 2 unblocked + 1 blocked, CAR 2 unblocked (the empty-net shot is not 5v5) + 1 blocked.
    assert away["cf_pct_5v5"] == pytest.approx(0.5)
    assert away["shot_attempts"] == 3 + 2 and home["shot_attempts"] == 3 + 1
    assert away["goals"] == 1 and home["goals"] == 2
    assert away["gax"] == pytest.approx(1 - 0.43)
    assert (away["pp_goals"], away["pp_opportunities"]) == (1, 3)
    assert away["faceoff_pct"] == 0.4 and home["faceoff_pct"] == 0.6
    assert (away["hits"], away["blocks"], away["pim"]) == (9, 5, 4)
    assert away["sog"] == 2 and home["sog"] == 1
    assert away["hd_chances"] == 1


def test_missing_rail_falls_back_to_boxscore_sums():
    frame = shots_frame()
    row = gd.build_game_row(GAME, frame, build_shot_tables(frame), boxscore(), play_by_play(), None, NOW)
    away = row["team_stats"]["away"]
    assert (away["hits"], away["blocks"], away["pim"]) == (2, 2, 2)
    assert away["pp_goals"] == 1
    assert away["pp_opportunities"] is None and away["faceoff_pct"] is None


# ---- players -------------------------------------------------------------------
def test_player_lines_join_boxscore_shots_and_blocked_attempts():
    players = {p["player_id"]: p for p in build()["players"]}
    assert set(players) == {1, 2, 3, 11, 12, 30, 31}
    skater = players[1]
    assert skater["role"] == "skater" and skater["team"] == "FLA" and skater["toi"] == 1080
    assert skater["name"] == "Alex Skater"  # the play-by-play roster has the full name
    assert skater["shot_attempts"] == 2 + 2  # two unblocked in the shot file, two blocked in the play-by-play
    assert players[3]["name"] == "A. Blueliner"  # boxscore initials when the roster lacks him
    sniper = players[2]
    assert sniper["goals"] == 1 and sniper["ixg"] == 0.3 and sniper["gax"] == pytest.approx(0.7)
    assert sniper["ixg_per_60"] == pytest.approx(0.3 * 3600 / 300, abs=1e-3)
    assert sniper["hd_shots"] == 1


def test_goalie_lines_have_xga_gsax_and_save_percentage():
    players = {p["player_id"]: p for p in build()["players"]}
    away_goalie, home_goalie = players[30], players[31]
    assert away_goalie["role"] == "goalie" and away_goalie["position"] == "G"
    # CAR's shots at him: the miss and the goal; the empty-net goal has no goalie.
    assert away_goalie["xga"] == pytest.approx(0.5)
    assert away_goalie["gsax"] == pytest.approx(0.5 - 1)
    assert away_goalie["sv_pct"] == 0.0
    assert home_goalie["xga"] == pytest.approx(0.43)
    assert home_goalie["sv_pct"] == pytest.approx(2 / 3, abs=1e-4)
    assert home_goalie["shots_against"] == 3 and home_goalie["saves"] == 2


def test_players_who_did_not_play_are_left_out():
    box = boxscore()
    box["playerByGameStats"]["homeTeam"]["goalies"].append(goalie(99, "Backup", "00:00", 0, 0, 0))
    frame = shots_frame()
    row = gd.build_game_row(GAME, frame, build_shot_tables(frame), box, play_by_play(), right_rail(), NOW)
    assert 99 not in {p["player_id"] for p in row["players"]}


# ---- percentiles ---------------------------------------------------------------
def test_percentiles_rank_higher_as_better_and_split_ties():
    rows = [{"x": 1.0}, {"x": 2.0}, {"x": 2.0}, {"x": 4.0}]
    gd.attach_percentiles(rows, [("x", True)])
    assert [r["x"]["pct"] for r in rows] == [13, 50, 50, 88]
    assert rows[0]["x"]["value"] == 1.0


def test_percentiles_skip_low_volume_lines():
    rows = [{"x": 1.0, "n": 20}, {"x": 2.0, "n": 20}, {"x": 9.0, "n": 1}, {"x": None, "n": 20}]
    gd.attach_percentiles(rows, [("x", True)], eligible=lambda r: r["n"] >= 10)
    assert rows[1]["x"]["pct"] > rows[0]["x"]["pct"]
    assert rows[2]["x"] == {"value": 9.0, "pct": None}
    assert rows[3]["x"] is None


def test_ranking_stored_values_again_moves_percentiles_with_the_pool():
    rows = [{"x": 1.0}, {"x": 3.0}]
    gd.attach_percentiles(rows, [("x", True)])
    assert rows[1]["x"]["pct"] == 75
    rows.append({"x": 5.0})
    gd.attach_percentiles(rows, [("x", True)])
    assert [r["x"]["pct"] for r in rows] == [17, 50, 83]
    assert rows[0]["x"]["value"] == 1.0


def test_team_games_are_ranked_against_the_same_phase_only():
    def game(game_id, phase, xg):
        side = {key: 0 for key, _ in gd.TEAM_METRICS}
        return {"game_id": game_id, "season_type": phase, "players": [],
                "team_stats": {"away": dict(side, xg=xg), "home": dict(side, xg=xg + 1)}}

    games = [game("a", "REG", 1.0), game("b", "REG", 3.0), game("c", "POST", 2.0)]
    gd.rate_games(games)
    assert games[0]["team_stats"]["away"]["xg"]["pct"] < games[1]["team_stats"]["away"]["xg"]["pct"]
    post = games[2]["team_stats"]
    assert post["home"]["xg"]["pct"] > post["away"]["xg"]["pct"]
    assert games[0]["team_stats"]["home"]["xg"] == {"value": 2.0, "pct": 38}


def test_player_percentiles_need_enough_ice_time():
    row = build()
    row["players"].append({**row["players"][0], "player_id": 77, "toi": 120, "ixg": 9.0})
    gd.rate_games([row])
    short = next(p for p in row["players"] if p["player_id"] == 77)
    assert short["ixg"] == {"value": 9.0, "pct": None}
    regular = next(p for p in row["players"] if p["player_id"] == 1)
    assert regular["ixg"]["pct"] is not None
    goalie_line = next(p for p in row["players"] if p["player_id"] == 30)
    assert set(goalie_line["xga"]) == {"value", "pct"}


def test_unchanged_ranks_are_not_rewritten():
    first, second = build(), build()
    second["game_id"] = "2026020002"
    stored = {first["game_id"]: first, second["game_id"]: second}
    gd.rate_games(list(stored.values()))
    before = {gid: gd._signature(row) for gid, row in stored.items()}
    assert gd.changed_rows(stored, before) == []
    gd.rate_games(list(stored.values()))
    assert gd.changed_rows(stored, before) == []
    stored[first["game_id"]]["team_stats"]["away"]["xg"]["pct"] = 1
    assert [r["game_id"] for r in gd.changed_rows(stored, before)] == [first["game_id"]]


def test_row_shape_matches_the_contract():
    row = build()
    assert row["season_type"] == "REG" and row["week"] == 1
    assert set(row["team_stats"]) == {"away", "home"}
    assert set(row["team_stats"]["away"]) == {
        "xg", "xg_5v5", "xgf_pct_5v5", "cf_pct_5v5", "hd_chances", "sog", "shot_attempts", "goals",
        "gax", "pp_goals", "pp_opportunities", "faceoff_pct", "hits", "blocks", "pim",
    }
    assert row["win_probability"][-1][3:] == [1, 2]
    assert all(len(p) == 5 for p in row["win_probability"])
    assert {"period", "clock", "team", "description", "xg", "result", "player_id", "shooter"} == set(row["big_plays"][0])
