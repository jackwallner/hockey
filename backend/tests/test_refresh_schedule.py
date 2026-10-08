from datetime import date, datetime, timedelta, timezone

from refresh_schedule import Game, decide, kickoff_utc, next_check_at, parse_games_csv

UTC = timezone.utc
KICKOFF = datetime(2026, 9, 13, 17, 0, tzinfo=UTC)  # 1:00 PM EDT


def game(game_id="2026_01_BUF_HOU", kickoff=KICKOFF, away=None, home=None):
    return Game(
        game_id=game_id, season=2026, season_type="REG", game_type="REG", week=1,
        game_date=date(2026, 9, 13), kickoff_at=kickoff, away_team="BUF", home_team="HOU",
        away_score=away, home_score=home, overtime=False, stadium=None,
    )


def run(now, games, with_stats=(), last_probe=None, last_sync=None):
    return decide(
        now=now, games=games, games_with_stats=set(with_stats),
        last_probe_at=last_probe, last_sync_at=last_sync,
    )


def test_kickoff_is_eastern_wall_clock():
    assert kickoff_utc("2026-09-13", "13:00") == KICKOFF
    assert kickoff_utc("2026-12-06", "13:00") == datetime(2026, 12, 6, 18, 0, tzinfo=UTC)
    assert kickoff_utc("2026-09-13", "") is None


def test_parse_games_csv_maps_types_and_blank_scores():
    text = (
        "game_id,season,game_type,week,gameday,gametime,away_team,away_score,home_team,home_score,overtime,stadium\n"
        "2026_01_NO_DET,2026,REG,1,2026-09-13,13:00,NO,30,DET,31,1,Ford Field\n"
        "2026_01_DAL_NYG,2026,REG,1,2026-09-13,20:20,DAL,,NYG,,,MetLife Stadium\n"
        "2026_19_KC_BUF,2026,WC,19,2027-01-09,16:30,KC,NA,BUF,NA,NA,\n"
        "2024_01_KC_BAL,2024,REG,1,2024-09-05,20:20,BAL,20,KC,27,0,\n"
    )
    games = {g.game_id: g for g in parse_games_csv(text, [2026])}
    assert set(games) == {"2026_01_NO_DET", "2026_01_DAL_NYG", "2026_19_KC_BUF"}
    assert games["2026_01_NO_DET"].is_final and games["2026_01_NO_DET"].overtime
    assert not games["2026_01_DAL_NYG"].is_final
    assert games["2026_19_KC_BUF"].season_type == "POST"
    assert games["2026_19_KC_BUF"].game_type == "WC"


def test_quiet_tuesday_waits_for_daily_check():
    now = KICKOFF + timedelta(days=5)
    games = [game(away=36, home=31)]
    assert not run(now, games, with_stats=["2026_01_BUF_HOU"], last_probe=now - timedelta(hours=2)).probe
    assert run(now, games, with_stats=["2026_01_BUF_HOU"], last_probe=now - timedelta(hours=21)).probe


def test_post_game_window_probes_every_fifteen_minutes():
    now = KICKOFF + timedelta(hours=4)
    decision = run(now, [game()], last_probe=now - timedelta(minutes=14))
    assert decision.probe
    assert not run(now, [game()], last_probe=now - timedelta(minutes=5)).probe


def test_game_in_progress_does_not_probe_but_syncs_scores():
    now = KICKOFF + timedelta(hours=2)
    decision = run(now, [game()], last_probe=now - timedelta(hours=1), last_sync=now - timedelta(minutes=15))
    assert not decision.probe
    assert decision.sync_games


def test_final_without_stats_keeps_backup_checks():
    games = [game(away=36, home=31)]
    late = KICKOFF + timedelta(hours=20)
    assert run(late, games, last_probe=late - timedelta(minutes=30)).probe
    assert not run(late, games, with_stats=["2026_01_BUF_HOU"], last_probe=late - timedelta(minutes=30)).probe

    very_late = KICKOFF + timedelta(hours=60)
    assert not run(very_late, games, last_probe=very_late - timedelta(minutes=60)).probe
    assert run(very_late, games, last_probe=very_late - timedelta(minutes=120)).probe


def test_enrichment_window_checks_every_three_hours():
    now = KICKOFF + timedelta(days=2)
    games = [game(away=36, home=31)]
    stats = ["2026_01_BUF_HOU"]
    assert not run(now, games, with_stats=stats, last_probe=now - timedelta(hours=2)).probe
    assert run(now, games, with_stats=stats, last_probe=now - timedelta(hours=3)).probe


def test_empty_schedule_syncs_immediately_and_force_wins():
    now = KICKOFF
    assert run(now, [], last_sync=now).sync_games
    forced = decide(now=now, games=[], games_with_stats=set(), last_probe_at=now, last_sync_at=now, force=True)
    assert forced.probe and forced.sync_games


def test_cron_delay_tolerance():
    now = KICKOFF + timedelta(hours=4)
    assert run(now, [game()], last_probe=now - timedelta(minutes=12)).probe


def test_next_check_lands_on_the_post_game_window():
    now = KICKOFF + timedelta(hours=1)
    at = next_check_at(now=now, games=[game()], games_with_stats=set(), last_probe_at=now, last_sync_at=now)
    # In progress: the schedule re-syncs in 15 minutes for the final score.
    assert at - now <= timedelta(minutes=15)
    at = next_check_at(now=now, games=[game(away=1, home=2)], games_with_stats={"2026_01_BUF_HOU"},
                       last_probe_at=now, last_sync_at=now)
    assert KICKOFF + timedelta(hours=3, minutes=30) <= at <= KICKOFF + timedelta(hours=3, minutes=35)


def test_next_check_is_daily_when_quiet():
    now = KICKOFF + timedelta(days=6)
    at = next_check_at(now=now, games=[game(away=1, home=2)], games_with_stats={"2026_01_BUF_HOU"},
                       last_probe_at=now, last_sync_at=now)
    assert timedelta(hours=19) <= at - now <= timedelta(hours=20)
