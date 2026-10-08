import pandas as pd
import pytest


@pytest.fixture
def weekly_df() -> pd.DataFrame:
    """Small synthetic weekly player_stats frame (2 games each for a few players)."""
    base = {c: 0 for c in [
        "completions", "attempts", "passing_yards", "passing_tds",
        "passing_interceptions", "sacks_suffered", "passing_air_yards",
        "passing_first_downs", "passing_epa", "rushing_10",
        "carries", "rushing_yards", "rushing_tds", "rushing_first_downs",
        "rushing_epa", "rushing_fumbles",
        "receptions", "targets", "receiving_yards", "receiving_tds",
        "receiving_air_yards", "receiving_yards_after_catch",
        "receiving_first_downs", "receiving_epa",
        "def_tackles_solo", "def_tackle_assists", "def_sacks",
        "def_interceptions", "def_pass_defended", "def_fumbles_forced",
        "def_tackles_for_loss", "def_qb_hits",
        "target_share", "air_yards_share",
    ]}

    def row(**kw):
        r = dict(base)
        r.update(kw)
        return r

    records = []
    # QB: two games, 100 att total (below 150 pass qualifier when doubled? make 160).
    for wk in (1, 2):
        records.append(row(
            player_id="00-0000001", player_display_name="Test QB", position="QB",
            position_group="QB", team="KC", opponent_team="DEN",
            game_id=f"2025_0{wk}_KC_DEN", season=2025, week=wk, season_type="REG",
            completions=25, attempts=40, passing_yards=300, passing_tds=3,
            passing_interceptions=1, sacks_suffered=2, passing_epa=8.0,
            carries=5, rushing_yards=20, rushing_tds=0, rushing_10=1, rushing_first_downs=2,
        ))
    # Give the QB a third+fourth game to clear 150 attempts (160 total needs >=4 games of 40).
    for wk in (3, 4):
        records.append(row(
            player_id="00-0000001", player_display_name="Test QB", position="QB",
            position_group="QB", team="KC", opponent_team="LV",
            game_id=f"2025_0{wk}_KC_LV", season=2025, week=wk, season_type="REG",
            completions=25, attempts=40, passing_yards=300, passing_tds=3,
            passing_interceptions=1, sacks_suffered=2, passing_epa=8.0,
        ))
    # RB: 4 games, 25 carries each = 100 (>= 80 qualifier).
    for wk in (1, 2, 3, 4):
        records.append(row(
            player_id="00-0000002", player_display_name="Test RB", position="RB",
            position_group="RB", team="SF", opponent_team="SEA",
            game_id=f"2025_0{wk}_SF_SEA", season=2025, week=wk, season_type="REG",
            carries=25, rushing_yards=110, rushing_tds=1, rushing_10=4,
            rushing_first_downs=6, rushing_fumbles=1, rushing_epa=2.0,
            receptions=3, targets=4, receiving_yards=25,
        ))
    # WR: 4 games, 12 targets each = 48 (>= 40 qualifier).
    for wk in (1, 2, 3, 4):
        records.append(row(
            player_id="00-0000003", player_display_name="Test WR", position="WR",
            position_group="WR", team="MIN", opponent_team="GB",
            game_id=f"2025_0{wk}_MIN_GB", season=2025, week=wk, season_type="REG",
            receptions=8, targets=12, receiving_yards=110, receiving_tds=1,
            receiving_air_yards=90, receiving_yards_after_catch=40,
            receiving_first_downs=5, receiving_epa=3.0,
            target_share=0.25, air_yards_share=0.30,
        ))
    # LB: 10 games, defense (>= 8 games qualifier).
    for wk in range(1, 11):
        records.append(row(
            player_id="00-0000004", player_display_name="Test LB", position="LB",
            position_group="LB", team="BAL", opponent_team="CIN",
            game_id=f"2025_{wk:02d}_BAL_CIN", season=2025, week=wk, season_type="REG",
            def_tackles_solo=6, def_tackle_assists=2, def_sacks=1.0,
            def_interceptions=0, def_pass_defended=1, def_tackles_for_loss=1,
            def_qb_hits=2,
        ))
    # A POST-season QB row that must be excluded from aggregation.
    records.append(row(
        player_id="00-0000001", player_display_name="Test QB", position="QB",
        position_group="QB", team="KC", opponent_team="BUF",
        game_id="2025_20_KC_BUF", season=2025, week=20, season_type="POST",
        completions=30, attempts=50, passing_yards=400, passing_tds=4,
    ))
    # A sub-threshold WR (only 1 game, 5 targets) — must NOT qualify for Receiving.
    records.append(row(
        player_id="00-0000005", player_display_name="Scrub WR", position="WR",
        position_group="WR", team="NYJ", opponent_team="NE",
        game_id="2025_01_NYJ_NE", season=2025, week=1, season_type="REG",
        receptions=2, targets=5, receiving_yards=15,
    ))

    return pd.DataFrame(records)


@pytest.fixture
def ngs_passing_df() -> pd.DataFrame:
    return pd.DataFrame([{
        "season": 2025, "season_type": "REG", "week": 0,
        "player_gsis_id": "00-0000001",
        "completion_percentage_above_expectation": 3.4,
        "avg_time_to_throw": 2.75, "aggressiveness": 12.1,
        "avg_intended_air_yards": 8.4,
    }])


@pytest.fixture
def ngs_rushing_df() -> pd.DataFrame:
    return pd.DataFrame([{
        "season": 2025, "season_type": "REG", "week": 0,
        "player_gsis_id": "00-0000002",
        "rush_yards_over_expected": 120.5,
    }])


@pytest.fixture
def ngs_receiving_df() -> pd.DataFrame:
    return pd.DataFrame([{
        "season": 2025, "season_type": "REG", "week": 0,
        "player_gsis_id": "00-0000003",
        "avg_separation": 3.2, "avg_yac_above_expectation": 0.6,
    }])
