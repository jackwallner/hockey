from datetime import date, datetime, timedelta, timezone

import pytest

from refresh_schedule import Game, decide, games_from_rows, next_check_at

UTC = timezone.utc
START = datetime(2026, 11, 10, 0, 0, tzinfo=UTC)  # 7:00 PM EST puck drop
STATS = "2026020200"


def game(game_id=STATS, start=START, away=None, home=None):
    return Game(
        game_id=game_id, season=2026, season_type="REG", game_type="REG", week=7,
        game_date=date(2026, 11, 9), kickoff_at=start, away_team="EDM", home_team="CGY",
        away_score=away, home_score=home, overtime=False, stadium=None,
    )


def run(now, games, with_stats=(), last_probe=None, last_sync=None, last_full=None):
    return decide(
        now=now, games=games, games_with_stats=set(with_stats),
        last_probe_at=last_probe, last_sync_at=last_sync, last_full_sync_at=last_full,
    )


def settled(now):
    """Sync stamps that leave no schedule sync due, so a test sees the probe only."""
    return {"last_sync": now, "last_full": now}


# --------------------------------------------------------------------------- #
# Probe cadence
# --------------------------------------------------------------------------- #
def test_nothing_is_probed_early_in_the_game():
    now = START + timedelta(hours=2)
    final_ish = [game()]
    assert not run(now, final_ish, last_probe=now - timedelta(minutes=45), **settled(now)).probe


def test_post_game_window_probes_every_thirty_minutes_from_two_and_a_half_hours():
    now = START + timedelta(hours=3)
    assert run(now, [game()], last_probe=now - timedelta(minutes=31), **settled(now)).probe
    assert not run(now, [game()], last_probe=now - timedelta(minutes=10), **settled(now)).probe


def test_window_opens_at_two_and_a_half_hours_sharp():
    games = [game()]
    before = START + timedelta(hours=2, minutes=20)
    after = START + timedelta(hours=2, minutes=30)
    last = lambda t: t - timedelta(minutes=35)  # noqa: E731
    assert not run(before, games, last_probe=last(before), **settled(before)).probe
    assert run(after, games, last_probe=last(after), **settled(after)).probe


def test_dense_window_closes_at_twelve_hours_and_goes_hourly():
    games = [game(away=2, home=3)]
    now = START + timedelta(hours=20)
    assert not run(now, games, with_stats=[STATS], last_probe=now - timedelta(minutes=35), **settled(now)).probe
    assert run(now, games, with_stats=[STATS], last_probe=now - timedelta(minutes=62), **settled(now)).probe


def test_after_thirty_six_hours_a_quiet_game_falls_back_to_six_hourly_in_season():
    games = [game(away=2, home=3)]
    now = START + timedelta(hours=48)
    assert not run(now, games, with_stats=[STATS], last_probe=now - timedelta(hours=5), **settled(now)).probe
    assert run(now, games, with_stats=[STATS], last_probe=now - timedelta(hours=6), **settled(now)).probe


def test_a_final_still_missing_its_stats_keeps_hourly_checks_for_five_days():
    games = [game(away=2, home=3)]
    now = START + timedelta(hours=60)
    assert run(now, games, last_probe=now - timedelta(minutes=62), **settled(now)).probe
    assert not run(now, games, with_stats=[STATS], last_probe=now - timedelta(minutes=62), **settled(now)).probe
    late = START + timedelta(days=6)
    assert not run(late, games, last_probe=late - timedelta(minutes=62), **settled(late)).probe


def test_off_season_baseline_is_daily():
    now = datetime(2026, 8, 15, 12, 0, tzinfo=UTC)
    assert not run(now, [game(start=now - timedelta(days=60))], last_probe=now - timedelta(hours=7), **settled(now)).probe
    assert run(now, [game(start=now - timedelta(days=60))], last_probe=now - timedelta(hours=23, minutes=58), **settled(now)).probe


@pytest.mark.parametrize("year,month,cadence", [
    (2026, 10, 360), (2027, 1, 360), (2027, 6, 360), (2026, 7, 1440), (2026, 9, 1440),
])
def test_in_season_months_are_october_through_june(year, month, cadence):
    now = datetime(year, month, 15, 12, tzinfo=UTC)
    games = [game(start=now - timedelta(days=30), away=1, home=0)]
    decision = run(now, games, with_stats=[STATS], last_probe=now, **settled(now))
    assert decision.probe_reason.endswith(f"(every {cadence}m)")


def test_cron_delay_tolerance():
    now = START + timedelta(hours=4)
    assert run(now, [game()], last_probe=now - timedelta(minutes=27), **settled(now)).probe


def test_never_probed_probes():
    now = START + timedelta(days=30)
    assert run(now, [game(away=1, home=0)], with_stats=[STATS], **settled(now)).probe


# --------------------------------------------------------------------------- #
# Schedule sync cadence
# --------------------------------------------------------------------------- #
def test_game_in_progress_syncs_scores_every_fifteen_minutes():
    now = START + timedelta(hours=1)
    decision = run(now, [game()], last_probe=now, last_sync=now - timedelta(minutes=16), last_full=now)
    assert decision.sync_games and not decision.sync_full
    quiet = run(now, [game()], last_probe=now, last_sync=now - timedelta(minutes=5), last_full=now)
    assert not quiet.sync_games


def test_a_finished_game_no_longer_triggers_score_syncs():
    now = START + timedelta(hours=1)
    decision = run(now, [game(away=1, home=0)], last_probe=now, last_sync=now - timedelta(minutes=20), last_full=now)
    assert not decision.sync_games


def test_score_syncs_stop_four_hours_after_the_start():
    now = START + timedelta(hours=4, minutes=5)
    decision = run(now, [game()], last_probe=now, last_sync=now - timedelta(minutes=20), last_full=now)
    assert not decision.sync_games


def test_full_sync_is_daily_even_when_score_syncs_keep_the_latest_stamp_fresh():
    now = START + timedelta(hours=1)
    decision = run(now, [game()], last_probe=now, last_sync=now - timedelta(minutes=5),
                   last_full=now - timedelta(hours=25))
    assert decision.sync_games and decision.sync_full


def test_full_sync_not_due_inside_a_day():
    now = START + timedelta(days=2)
    decision = run(now, [game(away=1, home=0)], last_probe=now, last_sync=now, last_full=now - timedelta(hours=20))
    assert not decision.sync_games


def test_a_table_never_fully_synced_syncs_in_full_immediately_and_force_wins():
    now = START
    empty = run(now, [], last_sync=None, last_full=None)
    assert empty.sync_games and empty.sync_full
    assert "no full sync" in empty.sync_reason
    forced = decide(now=now, games=[], games_with_stats=set(), last_probe_at=now,
                    last_sync_at=now, last_full_sync_at=now, force=True)
    assert forced.probe and forced.sync_games and forced.sync_full


# --------------------------------------------------------------------------- #
# Next check
# --------------------------------------------------------------------------- #
def test_next_check_lands_on_the_post_game_window():
    now = START + timedelta(minutes=30)
    at = next_check_at(now=now, games=[game(away=1, home=2)], games_with_stats={STATS},
                       last_probe_at=now, last_sync_at=now, last_full_sync_at=now)
    assert START + timedelta(hours=2, minutes=30) - timedelta(minutes=35) <= at <= START + timedelta(hours=2, minutes=35)


def test_next_check_is_within_fifteen_minutes_while_a_game_is_live():
    now = START + timedelta(hours=1)
    at = next_check_at(now=now, games=[game()], games_with_stats=set(),
                       last_probe_at=now, last_sync_at=now, last_full_sync_at=now)
    assert at - now <= timedelta(minutes=15)


def test_next_check_is_six_hours_when_quiet_in_season():
    now = START + timedelta(days=6)
    at = next_check_at(now=now, games=[game(away=1, home=2)], games_with_stats={STATS},
                       last_probe_at=now, last_sync_at=now, last_full_sync_at=now)
    assert timedelta(hours=5) <= at - now <= timedelta(hours=6)


def test_next_check_is_daily_off_season():
    now = datetime(2026, 8, 1, 12, tzinfo=UTC)
    at = next_check_at(now=now, games=[game(start=datetime(2026, 6, 10, tzinfo=UTC), away=1, home=2)],
                       games_with_stats={STATS}, last_probe_at=now, last_sync_at=now, last_full_sync_at=now)
    assert timedelta(hours=23) <= at - now <= timedelta(hours=24)


# --------------------------------------------------------------------------- #
def test_games_read_back_from_the_table():
    rows = [{
        "game_id": "2026020200", "season": 2026, "season_type": "REG", "game_type": "REG",
        "week": 7, "game_date": "2026-11-09", "kickoff_at": "2026-11-10T00:00:00+00:00",
        "away_team": "EDM", "home_team": "CGY", "away_score": None, "home_score": 3,
        "overtime": False, "stadium": "Saddledome",
    }]
    (parsed,) = games_from_rows(rows)
    assert parsed.kickoff_at == START and parsed.game_date == date(2026, 11, 9)
    assert not parsed.is_final  # one score missing is not a final
    assert parsed.home_score == 3


def test_timestamps_with_short_fractions_parse_on_old_pythons():
    from refresh_schedule import _parse_ts

    assert _parse_ts("2026-10-08T18:35:32.64747+00:00") == datetime(2026, 10, 8, 18, 35, 32, 647470, tzinfo=UTC)
    assert _parse_ts("2026-10-08T18:35:32Z") == datetime(2026, 10, 8, 18, 35, 32, tzinfo=UTC)
    assert _parse_ts(None) is None
