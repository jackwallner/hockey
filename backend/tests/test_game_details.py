from datetime import datetime, timezone

import pandas as pd

from ingest_game_details import attach_percentiles, build_rows, team_stats


def play(**overrides):
    row = {
        "game_id": "2026_01_BUF_HOU", "season": 2026, "season_type": "REG", "week": 1,
        "home_team": "HOU", "away_team": "BUF", "posteam": "BUF", "defteam": "HOU",
        "qtr": 1, "quarter_seconds_remaining": 900, "time": "15:00", "down": 1,
        "yardline_100": 75, "play_type": "pass", "pass": 1, "rush": 0, "qb_dropback": 1,
        "sack": 0, "epa": 0.5, "wpa": 0.01, "home_wp": 0.5, "yards_gained": 8,
        "air_yards": 6, "cpoe": 10.0, "pass_oe": 20.0, "qb_epa": 0.5,
        "passer_player_id": "00-0034857", "passer_player_name": "J.Allen",
        "rusher_player_id": None, "rusher_player_name": None,
        "receiver_player_id": "00-0036000", "receiver_player_name": "D.Kincaid",
        "third_down_converted": 0, "third_down_failed": 0, "interception": 0,
        "fumble_lost": 0, "fixed_drive": 1, "fixed_drive_result": "Punt", "desc": "pass",
    }
    row.update(overrides)
    return row


def frame():
    return pd.DataFrame([
        play(),
        play(play_type="run", **{"pass": 0}, rush=1, qb_dropback=0, epa=-0.4, yards_gained=12,
             air_yards=None, cpoe=None, passer_player_id=None, receiver_player_id=None,
             rusher_player_id="00-0037000", rusher_player_name="J.Cook", down=2),
        play(sack=1, epa=-1.5, qb_epa=-1.5, yards_gained=-7, air_yards=None, cpoe=None,
             receiver_player_id=None, down=3, third_down_failed=1, wpa=-0.2),
        play(yardline_100=12, epa=2.0, qb_epa=2.0, yards_gained=25, fixed_drive=2,
             fixed_drive_result="Touchdown", down=1, wpa=0.3, quarter_seconds_remaining=100),
        play(play_type="punt", **{"pass": 0}, epa=0.1, qb_dropback=0),
        play(posteam="HOU", defteam="BUF", epa=0.1, qb_epa=0.1, passer_player_id="00-0039163",
             passer_player_name="C.Stroud", interception=1, fixed_drive=3),
    ])


def test_team_stats_use_offensive_plays_only():
    stats = team_stats(frame(), "BUF")
    assert stats["plays"] == 4
    assert stats["dropbacks"] == 3
    assert stats["carries"] == 1
    assert stats["success_rate"] == 0.5
    assert stats["explosive_plays"] == 2
    assert stats["sack_rate"] == round(1 / 3, 3)
    assert stats["third_down_attempts"] == 1 and stats["third_down_rate"] == 0.0
    assert stats["red_zone_trips"] == 1 and stats["red_zone_td_rate"] == 1.0
    assert stats["early_down_pass_rate"] == round(2 / 3, 3)


def test_build_rows_ranks_and_keeps_counts_plain():
    rows = build_rows(frame(), datetime(2026, 9, 14, tzinfo=timezone.utc))
    game = rows[0]
    away, home = game["team_stats"]["away"], game["team_stats"]["home"]
    assert isinstance(away["plays"], int)
    assert away["epa_per_play"]["value"] == 0.15
    assert away["epa_per_play"]["pct"] > home["epa_per_play"]["pct"]
    assert home["turnovers"]["pct"] < away["turnovers"]["pct"]
    roles = {(p["role"], p["name"]) for p in game["players"]}
    assert ("passer", "J.Allen") in roles and ("rusher", "J.Cook") in roles
    assert game["big_plays"][0]["home_wpa"] == -0.3
    assert max(point[0] for point in game["win_probability"]) == 800


def test_percentiles_skip_low_volume_lines():
    rows = [{"x": 1.0, "n": 20}, {"x": 2.0, "n": 20}, {"x": 9.0, "n": 1}]
    attach_percentiles(rows, [("x", True)], eligible=lambda r: r["n"] >= 10)
    assert rows[1]["x"]["pct"] > rows[0]["x"]["pct"]
    assert rows[2]["x"] == {"value": 9.0, "pct": None}
