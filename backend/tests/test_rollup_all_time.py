"""Career rollup: the parts that are easy to get subtly wrong.

The rollup reuses ``ingest.build_agg`` / ``build_snapshot_rows`` wholesale, so
what needs its own coverage is the pooling of multi-season sources, where a
total and a rate look identical in code and differ by the season count.
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

import ingest
import rollup_all_time as rollup
from test_ingest import frame, goalie_rows, skater_rows

NOW = datetime(2026, 10, 8, tzinfo=timezone.utc)


def season_sources(season: int, season_type: str, cache: bool, status=None):
    """Two seasons of one forward, one goalie; the playoffs only have 2024."""
    if season_type == "POST" and season == 2023:
        empty = pd.DataFrame()
        return empty, empty, empty, empty
    skaters = frame(skater_rows(1, season=season, games=60, icetime=60000.0, ixg=10.0 * (season - 2022),
                                goals=20.0, team="T.B" if season == 2023 else "EDM"))
    goalies = frame(goalie_rows(10, season=season, games=60, goals_against=100.0))
    summary = pd.DataFrame([{"playerId": 1, "plusMinus": 5, "gameWinningGoals": 2, "shootsCatches": "L"}])
    goalie_summary = pd.DataFrame([{"playerId": 10, "wins": 30, "shutouts": 2, "gamesStarted": 58}])
    return skaters, goalies, summary, goalie_summary


def test_concat_frames_skips_empty_inputs():
    a = pd.DataFrame({"x": [1]})
    assert len(rollup.concat_frames([a, pd.DataFrame(), None, a])) == 2
    assert rollup.concat_frames([pd.DataFrame(), None]).empty


def test_load_range_pools_every_season_and_caches_only_finished_ones():
    seen = []

    def fake(season, season_type, cache, status=None):
        seen.append((season, cache))
        return season_sources(season, season_type, cache)

    with patch.object(rollup, "load_season_sources", side_effect=fake):
        skaters, goalies, sk_sum, g_sum = rollup.load_range(2023, 2024, "REG")
    assert len(skaters[skaters["situation"] == "all"]) == 2
    assert len(goalies[goalies["situation"] == "all"]) == 2
    assert len(sk_sum) == 2 and len(g_sum) == 2
    assert seen == [(2023, True), (2024, True)]


def test_career_totals_add_across_seasons():
    with patch.object(rollup, "load_season_sources", side_effect=season_sources):
        agg = rollup.build_career_agg(2023, 2024, "REG")
    skater = agg.loc[1]
    assert skater["games"] == 120
    assert skater["goals"] == 40
    assert skater["ixg"] == pytest.approx(10.0 + 20.0)
    assert skater["plus_minus"] == 10 and skater["gwg"] == 4        # NHL summary is summed too
    assert skater["team"] == "EDM"
    goalie = agg.loc[10]
    assert goalie["goals_against"] == 200
    assert goalie["wins"] == 60 and goalie["shutouts"] == 4


def test_career_rates_are_derived_from_pooled_numerators():
    with patch.object(rollup, "load_season_sources", side_effect=season_sources):
        agg = rollup.build_career_agg(2023, 2024, "REG")
    assert agg.loc[1, "ixg_per_60"] == pytest.approx(30.0 / (120000 / 3600))
    assert agg.loc[10, "gaa"] == pytest.approx(200 / (360000 / 3600))


def test_career_postseason_skips_seasons_without_a_file():
    with patch.object(rollup, "load_season_sources", side_effect=season_sources):
        agg = rollup.build_career_agg(2023, 2024, "POST")
    assert agg.loc[1, "games"] == 60


def test_career_rows_use_season_zero_and_career_thresholds():
    with patch.object(rollup, "load_season_sources", side_effect=season_sources):
        agg = rollup.build_career_agg(2023, 2024, "REG")
    # 120 skater GP and 120 goalie GP: the goalie clears 100, the skater misses 300.
    rows = ingest.build_snapshot_rows(agg, ingest.ALL_TIME_SEASON, NOW, "REG")
    assert [r["id"] for r in rows] == [10]
    assert rows[0]["season"] == 0 and rows[0]["season_type"] == "REG"


def test_a_failed_season_download_aborts_the_rollup():
    def boom(season, season_type, cache, status=None):
        raise RuntimeError("GET failed")

    with patch.object(rollup, "load_season_sources", side_effect=boom):
        with pytest.raises(RuntimeError):
            rollup.load_range(2023, 2024, "REG")


def test_main_dry_run_never_touches_supabase():
    with patch.object(rollup, "load_season_sources", side_effect=season_sources), \
            patch.object(rollup, "create_client") as create, \
            patch("sys.argv", ["rollup_all_time.py", "--dry-run", "--from", "2023", "--to", "2024",
                               "--season-type", "REG"]):
        rollup.main()
    create.assert_not_called()


def test_main_writes_then_prunes_each_phase():
    client = MagicMock()
    with patch.object(rollup, "load_season_sources", side_effect=season_sources), \
            patch.object(rollup, "create_client", return_value=client), \
            patch.dict("os.environ", {"SUPABASE_URL": "http://x", "SUPABASE_SERVICE_ROLE_KEY": "k"}), \
            patch.object(rollup, "upsert_rows") as upsert, \
            patch.object(rollup, "prune_orphans", return_value=0) as prune, \
            patch("sys.argv", ["rollup_all_time.py", "--from", "2023", "--to", "2024", "--season-type", "REG"]):
        rollup.main()
    assert upsert.call_count == 1
    assert prune.call_args.args[2:] == (ingest.ALL_TIME_SEASON, "REG")
