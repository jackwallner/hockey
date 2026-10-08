"""Prune floor arithmetic, exercised against a stub PostgREST client.

The prune is the one script in the pipeline whose whole job is deleting, and it
is no longer run nightly - it goes months between invocations and then runs once,
by hand, against production. So the season it decides to keep is worth pinning
down here rather than discovering afterwards.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import prune_history


class _Result:
    def __init__(self, data, count=None):
        self.data = data
        self.count = count


class _Query:
    """Just enough of the PostgREST builder for prune_history's three calls."""

    def __init__(self, table, counting=False):
        self.table = table
        self.counting = counting
        self.below = None
        self.deleting = False

    def order(self, _column, desc=False):
        return self

    def limit(self, _n):
        return self

    def lt(self, _column, value):
        self.below = value
        return self

    def delete(self):
        self.deleting = True
        return self

    def execute(self):
        matching = [s for s in self.table.seasons if self.below is None or s < self.below]
        if self.deleting:
            # PostgREST caps a delete, and prune() loops until the tail is gone;
            # deleting in pages here is what exercises that loop.
            for season in sorted(set(matching))[:1]:
                self.table.seasons = [s for s in self.table.seasons if s != season]
            return _Result([])
        if self.counting:
            return _Result([], count=len(matching))
        newest = max(matching) if matching else None
        return _Result([] if newest is None else [{"season": newest}])


class _Table:
    def __init__(self, seasons):
        self.seasons = list(seasons)

    def select(self, *_args, **kwargs):
        return _Query(self, counting=kwargs.get("count") == "exact")

    def delete(self):
        return _Query(self).delete()


class _Client:
    def __init__(self, seasons):
        self.tables = {name: _Table(seasons) for name in prune_history.TABLES}

    def table(self, name):
        return self.tables[name]


def _seasons(client, table="player_game_logs"):
    return sorted(set(client.tables[table].seasons))


def test_keeps_the_two_newest_seasons_by_default():
    client = _Client([2023, 2023, 2024, 2025])
    assert prune_history.oldest_kept_season(client, "player_game_logs", prune_history.DEFAULT_KEEP) == 2024


def test_keep_one_cuts_to_the_live_season():
    client = _Client([2023, 2024, 2025])
    assert prune_history.oldest_kept_season(client, "player_game_logs", 1) == 2025


def test_fewer_seasons_than_asked_for_keeps_them_all():
    client = _Client([2025, 2025])
    assert prune_history.oldest_kept_season(client, "player_game_logs", 2) == 2025


def test_empty_table_has_no_floor():
    client = _Client([])
    assert prune_history.oldest_kept_season(client, "player_game_logs", 2) is None


def test_prune_leaves_last_season_alone():
    """The regression that matters: Recent Form is offered on two seasons."""
    client = _Client([2019, 2020, 2024, 2025])
    prune_history.prune(client, "player_game_logs", dry_run=False)
    assert _seasons(client) == [2024, 2025]


def test_prune_is_a_no_op_the_second_time():
    client = _Client([2024, 2025])
    assert prune_history.prune(client, "player_game_logs", dry_run=False) == 0
    assert _seasons(client) == [2024, 2025]


def test_dry_run_deletes_nothing():
    client = _Client([2019, 2024, 2025])
    assert prune_history.prune(client, "player_game_logs", dry_run=True) == 1
    assert _seasons(client) == [2019, 2024, 2025]
