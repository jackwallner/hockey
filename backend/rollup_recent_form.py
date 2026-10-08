"""Pre-aggregate per-game logs into rolling last-N-weeks windows.

Reads public.player_game_logs and writes public.player_recent_form: one row
per (player, phase, side of the ball, window length), holding the shared
league window ending on the latest available week, the equal-length window before
it, and the delta between them — the THEN / NOW / delta shape ported from the
baseball app's Baseball Savant-style rolling leaderboard.

Ported from baseball's rollup_recent_form.py with one structural change: the
NFL plays a single game a week, so a calendar-day window is meaningless here.
Windows use the league's latest week as a shared anchor, N in (3, 5, 8).
Players without an appearance in the current span are omitted. This keeps an
early-season performance from remaining on Trends after an injury or benching.
Regular season and postseason are anchored and ranked separately.

Game logs store raw counts, never pre-divided rates (see ingest_game_logs.py),
so window rates here are recomputed from summed numerators and denominators
rather than averaged from per-game rates — exact rather than approximate, and
the reason a metric with a zero denominator is omitted rather than reported
as a misleading 0.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import argparse
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Optional

from dotenv import load_dotenv
from supabase import create_client

from ingest import passer_rating, resolve_season

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

WINDOW_WEEKS = (3, 5, 8)

# Counting stats summed straight across the window. Game-log metric key -> the
# recent-form output key, chosen to match the season metric id suffix in
# NFL_CONTRACT.md so the client can point a "recent" bar at either table with
# one shared key.
SUM_KEYS: dict[str, str] = {
    "passing_yards": "pass_yards",
    "passing_tds": "pass_tds",
    "interceptions": "interceptions",
    "completions": "completions",
    "attempts": "attempts",
    "sacks_suffered": "sacks_suffered",
    "carries": "carries",
    "rushing_yards": "rush_yards",
    "rushing_tds": "rush_tds",
    "rushing_first_downs": "rush_first_downs",
    "receptions": "receptions",
    "targets": "targets",
    "receiving_yards": "rec_yards",
    "receiving_tds": "rec_tds",
    "receiving_yac": "yac",
    "def_sacks": "sacks",
    "def_interceptions": "def_ints",
    "def_pass_defended": "passes_defended",
    "def_fumbles_forced": "forced_fumbles",
    "def_tackles_for_loss": "tfl",
    "def_qb_hits": "qb_hits",
}
# Tackles is solo + assisted combined into one output key, not a 1:1 column.
TACKLE_KEYS = ("def_tackles_solo", "def_tackle_assists")
# Fumble rate covers ball security on either a carry or a catch.
FUMBLE_KEYS = ("rushing_fumbles", "receiving_fumbles")

# Optional NGS-derived per-game rates (see ingest_game_logs.py's optional
# weekly NGS join). Only present in a game log when that join succeeded;
# metric -> the raw-count game-log key that weights it across a window, the
# same "aggregate the rate weighted by its own denominator" approach the
# baseball app uses for its own per-game rate metrics.
WEIGHTED_NGS: dict[str, str] = {
    "cpoe": "attempts",
    "avg_time_to_throw": "attempts",
    "avg_separation": "targets",
    "avg_yac_above_expectation": "targets",
    "rush_yoe": "carries",
}

# Decimal places per metric, per the rollup contract. Counting stats default
# to 0 (see _places).
_PLACES: dict[str, int] = {
    "cmp_pct": 1, "ypa": 1, "int_rate": 1, "sack_rate": 1, "passer_rating": 1,
    "passing_epa": 2, "ypc": 1, "rushing_epa": 1, "fumble_rate": 1,
    "catch_pct": 1, "receiving_epa": 1, "racr": 2,
    "cpoe": 1, "avg_time_to_throw": 2, "avg_separation": 1,
    "avg_yac_above_expectation": 1, "rush_yoe": 1,
}


def _places(metric: str) -> int:
    return _PLACES.get(metric, 0)


def _client():
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)
    return create_client(url, key)


def _num(log: dict, key: str) -> float:
    """Read one raw-count metric off a game-log row's ``metrics`` blob."""
    metrics = log.get("metrics") or {}
    val = metrics.get(key)
    try:
        return float(val) if val is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


def _total(logs: list[dict], key: str) -> float:
    return sum(_num(log, key) for log in logs)


def _aggregate(logs: list[dict]) -> dict[str, Any]:
    """Collapse a player's window of game rows into one set of metrics.

    Counting stats sum straight across the games. Rates are rebuilt from
    those sums (or, for the optional NGS metrics, from a value/denominator
    weighted average) rather than averaged from per-game rates, so the result
    matches a from-scratch recompute exactly. A rate whose denominator is zero
    across the window is omitted, not reported as 0 — the app needs to be
    able to tell "didn't throw a pass this window" from "threw for 0 yards".
    """
    if not logs:
        return {}

    result: dict[str, Any] = {}
    for game_key, out_key in SUM_KEYS.items():
        result[out_key] = int(round(_total(logs, game_key)))
    result["tackles"] = int(round(sum(_total(logs, k) for k in TACKLE_KEYS)))

    attempts = _total(logs, "attempts")
    sacks_suffered = _total(logs, "sacks_suffered")
    carries = _total(logs, "carries")
    receptions = _total(logs, "receptions")
    targets = _total(logs, "targets")
    pass_yards = _total(logs, "passing_yards")
    completions = _total(logs, "completions")
    interceptions = _total(logs, "interceptions")
    pass_tds = _total(logs, "passing_tds")
    rush_yards = _total(logs, "rushing_yards")
    rec_yards = _total(logs, "receiving_yards")
    receiving_air_yards = _total(logs, "receiving_air_yards")
    fumbles = sum(_total(logs, k) for k in FUMBLE_KEYS)
    passing_epa_sum = _total(logs, "passing_epa")
    rushing_epa_sum = _total(logs, "rushing_epa")
    receiving_epa_sum = _total(logs, "receiving_epa")

    if attempts > 0:
        result["cmp_pct"] = round(100 * completions / attempts, _places("cmp_pct"))
        result["ypa"] = round(pass_yards / attempts, _places("ypa"))
        result["int_rate"] = round(100 * interceptions / attempts, _places("int_rate"))
        rating = passer_rating(completions, attempts, pass_yards, pass_tds, interceptions)
        if rating is not None:
            result["passer_rating"] = rating

    dropbacks = attempts + sacks_suffered
    if dropbacks > 0:
        result["sack_rate"] = round(100 * sacks_suffered / dropbacks, _places("sack_rate"))
        result["passing_epa"] = round(passing_epa_sum / dropbacks, _places("passing_epa"))

    if carries > 0:
        result["ypc"] = round(rush_yards / carries, _places("ypc"))
        # Rush EPA is a window TOTAL, not a rate — reported whenever the
        # player actually carried the ball in the window, not divided by
        # anything.
        result["rushing_epa"] = round(rushing_epa_sum, _places("rushing_epa"))

    touches = carries + receptions
    if touches > 0:
        result["fumble_rate"] = round(100 * fumbles / touches, _places("fumble_rate"))

    if targets > 0:
        result["catch_pct"] = round(100 * receptions / targets, _places("catch_pct"))
        # Same total-not-rate treatment as rushing_epa, gated on targets
        # (the player was actually a receiving option) rather than divided.
        result["receiving_epa"] = round(receiving_epa_sum, _places("receiving_epa"))

    if receiving_air_yards:
        result["racr"] = round(rec_yards / receiving_air_yards, _places("racr"))

    # Optional NGS-derived rates: only present when ingest's weekly NGS join
    # populated them, so most game logs simply won't have these keys and the
    # loop below is a no-op for those players.
    for metric, denom_key in WEIGHTED_NGS.items():
        numer = 0.0
        denom = 0.0
        for log in logs:
            metrics = log.get("metrics") or {}
            value = metrics.get(metric)
            if value is None:
                continue
            weight = _num(log, denom_key)
            if weight <= 0:
                continue
            numer += float(value) * weight
            denom += weight
        if denom > 0:
            result[metric] = round(numer / denom, _places(metric))

    return result


def _delta(now: dict[str, Any], then: dict[str, Any]) -> dict[str, Any]:
    """Change from the prior window to the current one, for shared metrics."""
    out: dict[str, Any] = {}
    for metric, value in now.items():
        if metric in then:
            out[metric] = round(float(value) - float(then[metric]), _places(metric))
    return out


def build_rows(logs: list[dict]) -> list[dict]:
    """Build every active (player, phase, side, week-window) row."""
    anchors: dict[tuple[int, str], int] = {}
    for log in logs:
        week = log.get("week")
        if week is None:
            continue
        context = (int(log["season"]), str(log.get("season_type") or "REG"))
        anchors[context] = max(anchors.get(context, 0), int(week))

    by_player: dict[tuple[int, str, str], list[dict]] = {}
    for log in logs:
        phase = str(log.get("season_type") or "REG")
        key = (log["player_id"], phase, log["player_type"])
        by_player.setdefault(key, []).append(log)

    rows: list[dict] = []
    for (player_id, season_type, player_type), player_logs in by_player.items():
        player_logs = sorted(
            player_logs,
            key=lambda r: (r["game_date"], r.get("week") or 0),
            reverse=True,
        )
        season = player_logs[0]["season"]
        anchor = anchors.get((int(season), season_type))
        if anchor is None:
            continue

        for window in WINDOW_WEEKS:
            current_start = anchor - window + 1
            prior_start = anchor - (window * 2) + 1
            prior_end = current_start - 1
            current = [
                log for log in player_logs
                if current_start <= int(log.get("week") or -1) <= anchor
            ]
            prior = [
                log for log in player_logs
                if prior_start <= int(log.get("week") or -1) <= prior_end
            ]
            if not current:
                continue
            team = current[0].get("team")

            now_metrics = _aggregate(current)
            then_metrics = _aggregate(prior)

            rows.append({
                "player_id": player_id,
                "season": season,
                "season_type": season_type,
                "player_type": player_type,
                "window_weeks": window,
                "as_of": current[0]["game_date"],
                "start_week": current_start,
                "end_week": anchor,
                "team": team,
                "games": len(current),
                "plays": sum(int(r.get("plays") or 0) for r in current),
                "touches": sum(int(r.get("touches") or 0) for r in current),
                "metrics": now_metrics,
                "prior_metrics": then_metrics,
                "delta": _delta(now_metrics, then_metrics),
                "updated_at": datetime.now(UTC).isoformat(),
            })

    return rows


def _fetch_logs(client, season: int) -> list[dict]:
    """Page through every game log for the season.

    Unlike baseball's date-limited fetch, this pulls the whole season so both
    the current and prior shared week windows are available for either phase.
    A full NFL season of game logs is still small enough to page cheaply.
    """
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_game_logs")
            .select("*")
            .eq("season", season)
            .order("game_date", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )
        page = resp.data or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def _fetch_snapshot_player_ids(client, season: int) -> set[tuple[int, str]]:
    """Player and phase keys the app can resolve into a profile."""
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots")
            .select("id,season_type")
            .eq("season", season)
            .range(offset, offset + page_size - 1)
            .execute()
        )
        page = resp.data or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return {
        (int(row["id"]), str(row.get("season_type") or "REG"))
        for row in rows
    }


def _routable_logs(logs: list[dict], snapshot_ids: set[Any]) -> list[dict]:
    """Drop feed rows that cannot resolve to a player profile in the app."""
    return [
        row for row in logs
        if int(row["player_id"]) in snapshot_ids
        or (
            int(row["player_id"]),
            str(row.get("season_type") or "REG"),
        ) in snapshot_ids
    ]


def _upsert(client, rows: list[dict]) -> None:
    if not rows:
        return
    batch_size = 500
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        try:
            client.table("player_recent_form").upsert(
                batch,
                on_conflict=(
                    "player_id,season,season_type,player_type,window_weeks"
                ),
            ).execute()
        except Exception:
            logger.exception("Upsert failed for batch starting at %d", i)
            raise


def _table_exists(client) -> bool:
    """True once the player_recent_form migration has been applied.

    Between shipping this script and applying the migration, the table
    legitimately doesn't exist yet. Failing the whole nightly for that would
    also fail the snapshot and game-log ingests that share the job, so this
    one condition is a warn-and-skip. Every other error still fails loudly.
    """
    try:
        client.table("player_recent_form").select("player_id").limit(1).execute()
        return True
    except Exception as exc:  # noqa: BLE001 — inspecting the provider's message
        message = str(exc)
        if "player_recent_form" in message and (
            "PGRST205" in message
            or "does not exist" in message
            or "schema cache" in message
        ):
            return False
        raise


def run(season: Optional[int] = None) -> None:
    season = resolve_season(season)
    client = _client()

    if not _table_exists(client):
        logger.warning(
            "public.player_recent_form is missing — apply "
            "supabase/migrations/20260727000000_create_player_recent_form.sql. "
            "Skipping the rollup so the rest of the nightly still completes."
        )
        return

    logger.info("Fetching game logs for %d...", season)
    logs = _fetch_logs(client, season)
    logger.info("  %d game-log rows", len(logs))

    if not logs:
        logger.warning("No game logs for %d — nothing to roll up.", season)
        return

    snapshot_ids = _fetch_snapshot_player_ids(client, season)
    logs = _routable_logs(logs, snapshot_ids)
    logger.info("  %d routable game-log rows", len(logs))

    rows = build_rows(logs)
    logger.info("Built %d recent-form rows", len(rows))

    (
        client.table("player_recent_form")
        .delete()
        .eq("season", season)
        .execute()
    )
    _upsert(client, rows)
    logger.info("Done.")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="Season to roll up (default: current).")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    args = _parse_args()
    run(season=args.season)
