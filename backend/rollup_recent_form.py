"""Pre-aggregate per-game logs into league-anchored 2, 4 and 8 week windows.

Reads public.player_game_logs and writes public.player_recent_form: one row per
(player, phase, player type, window length), holding the current window, the
equal-length window before it, and the delta between them (the THEN / NOW /
delta shape ported from the baseball app's rolling leaderboard).

Windows are measured in days off a league anchor, not off each player's own
games. The anchor is the latest ``game_date`` with any log row for that season
and phase; the current span for an ``N``-week window is
``(anchor - 7N days, anchor]`` and the previous span is the equal-length block
before it. A player without an appearance in the current span is omitted, so a
hot streak in October does not linger on Trends after an injury. Regular season
and postseason are anchored and ranked separately.

Game logs store raw counts, never pre-divided rates (see ingest_game_logs.py),
so every rate here is recomputed from summed numerators and denominators, which
is exact where averaging per-game rates is not. A metric whose denominator is
zero across the window is omitted rather than reported as a misleading 0.

Keys are the contract's. Skaters: points_per_60, goals_per_60, ixg_per_60, gax,
shooting_pct, shots_per_60, hd_shots_per_60, blocks_per_60, hits_per_60 and the
totals goals, assists, points, shots_on_goal, ixg, games. Goalies: sv_pct, gaa,
gsax, gsax_per_60, hd_sv_pct, shots_against_per_60 and the totals saves,
goals_against, games, wins. ``shots_per_60`` counts shot attempts, matching the
season ``Shots/60``; ``shooting_pct`` is 0 to 100 and ``sv_pct`` a fraction,
matching the season snapshot values.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable, Optional

from dotenv import load_dotenv
from supabase import create_client

from ingest import resolve_season

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

WINDOW_WEEKS = (2, 4, 8)
PAGE_SIZE = 1000
UPSERT_BATCH = 500

# Decimal places per output key; totals not listed are whole numbers.
_PLACES: dict[str, int] = {
    "points_per_60": 2, "goals_per_60": 2, "ixg_per_60": 2, "gax": 2,
    "shooting_pct": 1, "shots_per_60": 1, "hd_shots_per_60": 1,
    "blocks_per_60": 1, "hits_per_60": 1, "ixg": 2,
    "sv_pct": 3, "gaa": 2, "gsax": 2, "gsax_per_60": 2, "hd_sv_pct": 3,
    "shots_against_per_60": 1,
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
    value = (log.get("metrics") or {}).get(key)
    try:
        return float(value) if value is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


def _total(logs: list[dict], key: str) -> float:
    return sum(_num(log, key) for log in logs)


def _rate(numer: float, denom: float, key: str, scale: float = 1.0) -> Optional[float]:
    """``scale * numer / denom`` rounded for ``key``; None on a zero denominator."""
    if denom <= 0:
        return None
    return round(scale * numer / denom, _places(key))


def _put(result: dict[str, Any], key: str, value: Optional[float]) -> None:
    if value is not None:
        result[key] = value


def _aggregate_skater(logs: list[dict]) -> dict[str, Any]:
    hours = _total(logs, "toi_seconds") / 3600
    goals = _total(logs, "goals")
    ixg = _total(logs, "ixg")
    sog = _total(logs, "shots_on_goal")
    result: dict[str, Any] = {
        "goals": int(round(goals)),
        "assists": int(round(_total(logs, "assists"))),
        "points": int(round(_total(logs, "points"))),
        "shots_on_goal": int(round(sog)),
        "ixg": round(ixg, _places("ixg")),
        "gax": round(goals - ixg, _places("gax")),
        "games": len(logs),
    }
    per_hour = {
        "points_per_60": "points", "goals_per_60": "goals", "ixg_per_60": "ixg",
        "shots_per_60": "shot_attempts", "hd_shots_per_60": "hd_shots",
        "blocks_per_60": "blocks", "hits_per_60": "hits",
    }
    for out_key, game_key in per_hour.items():
        _put(result, out_key, _rate(_total(logs, game_key), hours, out_key))
    _put(result, "shooting_pct", _rate(goals, sog, "shooting_pct", 100))
    return result


def _aggregate_goalie(logs: list[dict]) -> dict[str, Any]:
    hours = _total(logs, "toi_seconds") / 3600
    against = _total(logs, "goals_against")
    shots = _total(logs, "shots_against")
    gsax = _total(logs, "xga") - against
    result: dict[str, Any] = {
        "saves": int(round(_total(logs, "saves"))),
        "goals_against": int(round(against)),
        "games": len(logs),
        "wins": int(round(_total(logs, "decision_win"))),
    }
    if shots > 0:
        result["sv_pct"] = round(1 - against / shots, _places("sv_pct"))
    hd_shots = _total(logs, "hd_shots_against")
    if hd_shots > 0:
        result["hd_sv_pct"] = round(1 - _total(logs, "hd_goals_against") / hd_shots, _places("hd_sv_pct"))
    if hours > 0:
        result["gsax"] = round(gsax, _places("gsax"))
        _put(result, "gaa", _rate(against, hours, "gaa"))
        _put(result, "gsax_per_60", _rate(gsax, hours, "gsax_per_60"))
        _put(result, "shots_against_per_60", _rate(shots, hours, "shots_against_per_60"))
    return result


def _aggregate(logs: list[dict], player_type: str = "f") -> dict[str, Any]:
    """Collapse a player's window of game rows into one set of metrics."""
    if not logs:
        return {}
    return _aggregate_goalie(logs) if player_type == "g" else _aggregate_skater(logs)


def _delta(now: dict[str, Any], then: dict[str, Any]) -> dict[str, Any]:
    """Change from the prior window to the current one, for shared metrics."""
    return {
        metric: round(float(value) - float(then[metric]), _places(metric))
        for metric, value in now.items()
        if metric in then
    }


def _day(value: Any) -> date:
    return date.fromisoformat(str(value)[:10])


def _anchors(logs: list[dict]) -> dict[tuple[int, str], tuple[date, Optional[int]]]:
    """Per (season, phase): the latest game date and that date's league week."""
    anchors: dict[tuple[int, str], tuple[date, Optional[int]]] = {}
    for log in logs:
        context = (int(log["season"]), str(log.get("season_type") or "REG"))
        day = _day(log["game_date"])
        if context not in anchors or day > anchors[context][0]:
            anchors[context] = (day, log.get("week"))
    return anchors


def _week_of(day: date, anchor: date, anchor_week: Optional[int]) -> Optional[int]:
    """League week of ``day`` given the anchor's own week (7-day blocks from Monday)."""
    if anchor_week is None:
        return None
    blocks = (anchor - timedelta(days=anchor.weekday()) - (day - timedelta(days=day.weekday()))).days // 7
    return max(1, int(anchor_week) - blocks)


def build_rows(logs: list[dict], now: Optional[datetime] = None) -> list[dict]:
    """Build every active (player, phase, type, window) row."""
    stamp = (now or datetime.now(UTC)).isoformat()
    anchors = _anchors(logs)

    by_player: dict[tuple[int, str, str], list[dict]] = {}
    for log in logs:
        key = (log["player_id"], str(log.get("season_type") or "REG"), log["player_type"])
        by_player.setdefault(key, []).append(log)

    rows: list[dict] = []
    for (player_id, season_type, player_type), player_logs in by_player.items():
        player_logs = sorted(player_logs, key=lambda r: str(r["game_date"]), reverse=True)
        season = int(player_logs[0]["season"])
        anchor, anchor_week = anchors[(season, season_type)]
        for window in WINDOW_WEEKS:
            span = timedelta(days=7 * window)
            current = [r for r in player_logs if anchor - span < _day(r["game_date"]) <= anchor]
            prior = [r for r in player_logs if anchor - 2 * span < _day(r["game_date"]) <= anchor - span]
            if not current:
                continue
            now_metrics = _aggregate(current, player_type)
            then_metrics = _aggregate(prior, player_type)
            rows.append({
                "player_id": player_id,
                "season": season,
                "season_type": season_type,
                "player_type": player_type,
                "window_weeks": window,
                "as_of": str(current[0]["game_date"])[:10],
                "start_week": _week_of(anchor - span + timedelta(days=1), anchor, anchor_week),
                "end_week": anchor_week,
                "team": current[0].get("team"),
                "games": len(current),
                "plays": sum(int(r.get("plays") or 0) for r in current),
                "touches": sum(int(r.get("touches") or 0) for r in current),
                "metrics": now_metrics,
                "prior_metrics": then_metrics,
                "delta": _delta(now_metrics, then_metrics),
                "updated_at": stamp,
            })
    return rows


def _paged(fetch_page: Callable[[int, int], list[dict]]) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while True:
        page = fetch_page(offset, offset + PAGE_SIZE - 1) or []
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            return rows
        offset += PAGE_SIZE


def fetch_logs(client: Any, season: int) -> list[dict]:
    """Every game log for the season (both phases), in a stable order."""
    return _paged(lambda lo, hi: (
        client.table("player_game_logs")
        .select("*")
        .eq("season", season)
        .order("game_date", desc=True)
        .order("player_id")
        .order("player_type")
        .range(lo, hi)
        .execute()
        .data
    ))


def fetch_snapshot_keys(client: Any, season: int) -> set[tuple[int, str]]:
    """(player id, phase) pairs the app can resolve into a profile."""
    rows = _paged(lambda lo, hi: (
        client.table("player_snapshots")
        .select("id,season_type")
        .eq("season", season)
        .order("id")
        .order("season_type")
        .range(lo, hi)
        .execute()
        .data
    ))
    return {(int(row["id"]), str(row.get("season_type") or "REG")) for row in rows}


def _routable_logs(logs: list[dict], snapshot_ids: set[Any]) -> list[dict]:
    """Drop rows that cannot resolve to a player profile in the app.

    Works on game logs (``player_id``) and recent-form rows alike.
    """
    return [
        row for row in logs
        if int(row["player_id"]) in snapshot_ids
        or (int(row["player_id"]), str(row.get("season_type") or "REG")) in snapshot_ids
    ]


def _upsert(client: Any, rows: list[dict]) -> None:
    for i in range(0, len(rows), UPSERT_BATCH):
        client.table("player_recent_form").upsert(
            rows[i:i + UPSERT_BATCH],
            on_conflict="player_id,season,season_type,player_type,window_weeks",
        ).execute()


def run(season: Optional[int] = None) -> None:
    season = resolve_season(season)
    client = _client()

    logger.info("Fetching game logs for %d...", season)
    logs = fetch_logs(client, season)
    logger.info("  %d game-log rows", len(logs))
    if not logs:
        logger.warning("No game logs for %d; nothing to roll up.", season)
        return

    rows = build_rows(_routable_logs(logs, fetch_snapshot_keys(client, season)))
    logger.info("Built %d recent-form rows", len(rows))
    client.table("player_recent_form").delete().eq("season", season).execute()
    _upsert(client, rows)
    logger.info("Done.")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="Season to roll up (default: current).")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    run(season=_parse_args().season)
