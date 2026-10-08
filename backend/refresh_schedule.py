"""Decide from the NHL schedule whether a refresh probe is worth running.

The workflow fires every 30 minutes in season as a backup to its own timer
chain, and this gate turns most firings into a two-second no-op. Start times
are known for the whole season, so the useful moments are predictable:
MoneyPuck regenerates its files after the night's games (roughly 03:00 to 09:00
ET) and the NHL boxscore is final within minutes of the horn.

Probe cadence, measured from the last recorded probe (``last_checked_at``):

* Every 30 minutes from 2.5 hours after any game's start until 12 hours after.
* Hourly from 12 hours until 36 hours after any game's start.
* A final game still missing its player stats is also checked hourly until five
  days after its start (MoneyPuck can publish a game late).
* Otherwise every 6 hours in season (October to June) and daily off season.

The schedule itself is re-synced every 15 minutes while a game is in progress
(one call, scores only) and once a day in full (``sync_games.py``).

Stdlib only, so the gate runs on the bare runner without installing anything.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Iterable, Mapping, Optional
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

from sync_games import Game, resolve_season, sync_full, sync_recent

logger = logging.getLogger(__name__)
UTC = timezone.utc

PROJECT_HOST = "swlalptdamfccgjmpbyb.supabase.co"
USER_AGENT = "Hockey StatScout (jackwallner+bb@gmail.com)"
TIMEOUT_SECONDS = 30

# GitHub delays scheduled runs by a few minutes, so a cadence counts as met a
# little early rather than slipping a whole cycle.
TOLERANCE = timedelta(minutes=4)

POST_GAME_START = timedelta(hours=2, minutes=30)
POST_GAME_DENSE_END = timedelta(hours=12)
POST_GAME_HOURLY_END = timedelta(hours=36)
MISSING_STATS_GIVE_UP = timedelta(days=5)
DENSE_CADENCE = timedelta(minutes=30)
HOURLY_CADENCE = timedelta(hours=1)
IN_SEASON_CADENCE = timedelta(hours=6)
OFF_SEASON_CADENCE = timedelta(hours=24)
IN_SEASON_MONTHS = frozenset({10, 11, 12, 1, 2, 3, 4, 5, 6})

LIVE_SYNC_START = timedelta(minutes=-15)
LIVE_SYNC_END = timedelta(hours=4)
LIVE_SYNC_CADENCE = timedelta(minutes=15)
FULL_SYNC_CADENCE = timedelta(hours=24)


@dataclass(frozen=True)
class Decision:
    probe: bool
    probe_reason: str
    sync_games: bool
    sync_reason: str
    next_check_at: Optional[datetime] = None
    sync_full: bool = False


def _int(value: Any) -> Optional[int]:
    text = str(value).strip() if value is not None else ""
    if not text:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def games_from_rows(rows: Iterable[Mapping[str, Any]]) -> list[Game]:
    """Rebuild games read back from the Supabase table."""
    games: list[Game] = []
    for row in rows:
        kickoff = row.get("kickoff_at")
        games.append(Game(
            game_id=str(row["game_id"]),
            season=int(row["season"]),
            season_type=str(row.get("season_type") or "REG"),
            game_type=str(row.get("game_type") or "REG"),
            week=int(row["week"]),
            game_date=datetime.fromisoformat(str(row["game_date"])[:10]).date(),
            kickoff_at=_parse_ts(kickoff),
            away_team=str(row.get("away_team") or ""),
            home_team=str(row.get("home_team") or ""),
            away_score=_int(row.get("away_score")),
            home_score=_int(row.get("home_score")),
            overtime=bool(row.get("overtime")),
            stadium=row.get("stadium"),
        ))
    return games


def _due(last: Optional[datetime], now: datetime, cadence: timedelta) -> bool:
    return last is None or now - last >= cadence - TOLERANCE


def baseline_cadence(now: datetime) -> tuple[str, timedelta]:
    if now.month in IN_SEASON_MONTHS:
        return "in-season check", IN_SEASON_CADENCE
    return "off-season daily check", OFF_SEASON_CADENCE


def probe_cadence(
    games: Iterable[Game],
    now: datetime,
    games_with_stats: set[str],
) -> tuple[str, timedelta]:
    """The shortest cadence any game currently asks for, with its reason."""
    best = baseline_cadence(now)
    for game in games:
        if game.kickoff_at is None:
            continue
        since = now - game.kickoff_at
        if since < POST_GAME_START:
            continue
        candidates: list[tuple[str, timedelta]] = []
        if since < POST_GAME_DENSE_END:
            candidates.append((f"{game.game_id} post-game window", DENSE_CADENCE))
        elif since < POST_GAME_HOURLY_END:
            candidates.append((f"{game.game_id} post-game backup", HOURLY_CADENCE))
        if game.is_final and game.game_id not in games_with_stats and since < MISSING_STATS_GIVE_UP:
            candidates.append((f"{game.game_id} final, stats not in", HOURLY_CADENCE))
        for candidate in candidates:
            if candidate[1] < best[1]:
                best = candidate
    return best


def sync_cadence(games: Iterable[Game], now: datetime) -> tuple[str, timedelta]:
    """15 minutes while any game is in progress, else the daily full sync."""
    for game in games:
        if game.kickoff_at is None or game.is_final:
            continue
        if LIVE_SYNC_START <= now - game.kickoff_at < LIVE_SYNC_END:
            return f"{game.game_id} in progress", LIVE_SYNC_CADENCE
    return "daily schedule sync", FULL_SYNC_CADENCE


def _full_due(now: datetime, last_full_sync_at: Optional[datetime]) -> bool:
    """The daily full sync; the first one is due when no full sync was ever stamped."""
    return _due(last_full_sync_at, now, FULL_SYNC_CADENCE)


def decide(
    *,
    now: datetime,
    games: list[Game],
    games_with_stats: set[str],
    last_probe_at: Optional[datetime],
    last_sync_at: Optional[datetime],
    last_full_sync_at: Optional[datetime] = None,
    force: bool = False,
) -> Decision:
    sync_reason, sync_every = sync_cadence(games, now)
    probe_reason, probe_every = probe_cadence(games, now, games_with_stats)
    if force:
        return Decision(True, "forced", True, "forced", sync_full=True)
    full = _full_due(now, last_full_sync_at)
    recent = _due(last_sync_at, now, sync_every) and sync_every < FULL_SYNC_CADENCE
    reason = "no full sync on record" if full and last_full_sync_at is None else sync_reason
    return Decision(
        probe=_due(last_probe_at, now, probe_every),
        probe_reason=f"{probe_reason} (every {int(probe_every.total_seconds() // 60)}m)",
        sync_games=full or recent,
        sync_reason=f"{reason} ({'full' if full else 'scores'})" if full or recent else reason,
        sync_full=full,
    )


# Games the planner reads: finals still owed stats (five days) and tonight's
# slate plus the next day's, which the 24-hour look-ahead below can reach.
PLAN_LOOKBACK = timedelta(days=6)
PLAN_LOOKAHEAD = timedelta(days=2)
STEP = timedelta(minutes=5)
HORIZON = timedelta(hours=24)


def next_check_at(
    *,
    now: datetime,
    games: list[Game],
    games_with_stats: set[str],
    last_probe_at: Optional[datetime],
    last_sync_at: Optional[datetime],
    last_full_sync_at: Optional[datetime] = None,
) -> datetime:
    """The first moment after ``now`` when a probe or a schedule sync is due.

    GitHub drops scheduled runs under load, so the workflow schedules its own
    next run from this answer instead of trusting cron. Callers pass ``last_*``
    as ``now`` for anything that ran this time.
    """
    t = now + STEP
    while t <= now + HORIZON:
        _, probe_every = probe_cadence(games, t, games_with_stats)
        _, sync_every = sync_cadence(games, t)
        live = sync_every < FULL_SYNC_CADENCE and _due(last_sync_at, t, sync_every)
        if (
            _due(last_probe_at, t, probe_every)
            or live
            or _full_due(t, last_full_sync_at)
        ):
            return t
        t += STEP
    return now + HORIZON


# ---------------------------------------------------------------------------
# Network


class Supabase:
    def __init__(self, url: str, key: str) -> None:
        if urlparse(url).hostname != PROJECT_HOST:
            raise RuntimeError("Refusing to use a different Supabase project")
        self.url = url.rstrip("/")
        self.key = key

    def _request(self, method: str, path: str, *, params: Any = None,
                 body: Any = None, prefer: str | None = None) -> Any:
        query = f"?{urlencode(params)}" if params else ""
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        }
        if prefer:
            headers["Prefer"] = prefer
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = Request(f"{self.url}/rest/v1/{path}{query}", data=data, method=method, headers=headers)
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            payload = response.read()
        return json.loads(payload) if payload else None

    def games(self, seasons: Iterable[int], since: date, until: date) -> list[dict[str, Any]]:
        """Games dated in ``[since, until]``; the table holds 2,700 and PostgREST caps a page at 1,000."""
        listed = ",".join(str(s) for s in seasons)
        query = [
            ("select", "*"), ("season", f"in.({listed})"),
            ("game_date", f"gte.{since.isoformat()}"), ("game_date", f"lte.{until.isoformat()}"),
            ("limit", "1000"),
        ]
        return self._request("GET", "games", params=query) or []

    def last_sync_at(self) -> Optional[datetime]:
        rows = self._request("GET", "games", params={"select": "synced_at", "order": "synced_at.desc", "limit": "1"}) or []
        return _parse_ts(rows[0].get("synced_at")) if rows else None

    def last_full_sync_at(self, today: date) -> Optional[datetime]:
        """Latest sync stamp on a game older than the score window.

        The score-only sync touches yesterday onward, so only a full sync
        refreshes older rows and their stamp tells the two apart.
        """
        rows = self._request("GET", "games", params={
            "select": "synced_at",
            "game_date": f"lt.{(today - timedelta(days=1)).isoformat()}",
            "order": "synced_at.desc",
            "limit": "1",
        }) or []
        return _parse_ts(rows[0].get("synced_at")) if rows else None

    def last_probe_at(self) -> Optional[datetime]:
        rows = self._request("GET", "data_refresh_status", params={"select": "last_checked_at", "limit": "1"}) or []
        return _parse_ts(rows[0].get("last_checked_at")) if rows else None

    def games_with_stats(self, game_ids: list[str]) -> set[str]:
        if not game_ids:
            return set()
        listed = ",".join(game_ids)
        rows = self._request("GET", "player_game_logs", params={
            "select": "game_id",
            "game_id": f"in.({listed})",
            "player_type": "eq.g",
            "limit": "1000",
        }) or []
        return {str(row["game_id"]) for row in rows if row.get("game_id")}

    def upsert_games(self, rows: list[dict[str, Any]]) -> None:
        for start in range(0, len(rows), 500):
            self._request(
                "POST", "games",
                params={"on_conflict": "game_id"},
                body=rows[start:start + 500],
                prefer="resolution=merge-duplicates,return=minimal",
            )


def _parse_ts(value: Any) -> Optional[datetime]:
    """Parse a Postgres timestamptz; pads odd fraction widths for Python < 3.11."""
    if not value:
        return None
    text = re.sub(r"\.(\d+)", lambda m: "." + m.group(1)[:6].ljust(6, "0"), str(value).replace("Z", "+00:00"))
    parsed = datetime.fromisoformat(text)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def recent_game_ids(games: Iterable[Game], now: datetime) -> list[str]:
    return [
        g.game_id for g in games
        if g.is_final and g.kickoff_at is not None
        and timedelta(0) <= now - g.kickoff_at < MISSING_STATS_GIVE_UP
    ]


def run(now: datetime, *, force: bool, dry_run: bool) -> Decision:
    db = Supabase(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    season = resolve_season(now)
    seasons = (season - 1, season)

    def decide_now(games: list[Game], *, last_sync: Optional[datetime], last_full: Optional[datetime]) -> Decision:
        return decide(
            now=now,
            games=games,
            games_with_stats=db.games_with_stats(recent_game_ids(games, now)),
            last_probe_at=db.last_probe_at(),
            last_sync_at=last_sync,
            last_full_sync_at=last_full,
            force=force,
        )

    window = (now.date() - PLAN_LOOKBACK, now.date() + PLAN_LOOKAHEAD)
    games = games_from_rows(db.games(seasons, *window))
    last_sync, last_full = db.last_sync_at(), db.last_full_sync_at(now.date())
    decision = decide_now(games, last_sync=last_sync, last_full=last_full)
    if decision.sync_games and not dry_run:
        if decision.sync_full:
            count = sync_full(db, season, now)
            last_full = now
        else:
            count = sync_recent(db, season, now)
        logger.info("Synced %d games (%s)", count, decision.sync_reason)
        last_sync = now
        games = games_from_rows(db.games(seasons, *window))
        # A score that just landed can shorten the probe cadence.
        decision = decide_now(games, last_sync=now, last_full=last_full)
    upcoming = next_check_at(
        now=now,
        games=games,
        games_with_stats=db.games_with_stats(recent_game_ids(games, now)),
        last_probe_at=now if decision.probe else db.last_probe_at(),
        last_sync_at=last_sync,
        last_full_sync_at=last_full,
    )
    return Decision(
        decision.probe, decision.probe_reason, decision.sync_games, decision.sync_reason,
        upcoming, decision.sync_full,
    )


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Decide without writing the games table.")
    parser.add_argument("--github-output", default=None)
    args = parser.parse_args()

    now = datetime.now(UTC)
    try:
        decision = run(now, force=args.force, dry_run=args.dry_run)
    except Exception:  # noqa: BLE001 - never let the planner block a probe
        logger.exception("Schedule planner failed; probing anyway")
        decision = Decision(True, "planner error", False, "planner error", now + timedelta(minutes=30))

    wait = int(((decision.next_check_at or now + timedelta(minutes=30)) - now).total_seconds())
    logger.info("probe=%s (%s); next check in %dm", decision.probe, decision.probe_reason, wait // 60)
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as output:
            output.write(f"probe={str(decision.probe).lower()}\n")
            output.write(f"reason={decision.probe_reason}\n")
            output.write(f"wait_seconds={max(60, wait)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
