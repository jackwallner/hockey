"""Sync ``public.games`` from the NHL schedule endpoints. Stdlib only.

The refresh planner (``refresh_schedule.py``) runs this module's functions on a
bare runner before any dependency is installed, so nothing here imports pandas
or requests. The User-Agent and request pause mirror ``ingest.py``; a test pins
them together.

Two fetch paths, both on ``https://api-web.nhle.com/v1``:

* Full season, ``club-schedule-season/<TEAM>/<seasonId>``: 32 calls per season
  (every game appears under both clubs and is de-duplicated). The league
  ``schedule/<date>`` endpoint returns one week per call and needs about 37 to
  walk a season (Sep to mid June), so the per-club path is the cheaper one.
* Live scores, ``schedule/<date>``: one call returns the seven days starting at
  ``<date>``, which is all the 15-minute in-progress sync needs.

Rows follow the ``games`` section of ``HOCKEY_CONTRACT.md``: ``game_id`` is the
NHL id as text; ``game_type`` is ``REG`` or the playoff round (``R1``, ``R2``,
``CF``, ``SCF``, read from the round digit of the id); ``week`` counts 7-day
blocks from the Monday on or before ``regularSeasonStartDate`` (playoffs
continue the count); ``kickoff_at`` is ``startTimeUTC``; scores are written only
when ``gameState`` is ``FINAL`` or ``OFF``; ``overtime`` is a last period of
``OT`` or ``SO``. Preseason (gameType 1) and all-star games are skipped.

CLI: ``python backend/sync_games.py --season 2026`` (syncs that season and the
one before it; ``--only`` limits it to one season).
Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Iterable, Mapping, Optional
from urllib.error import URLError
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)
UTC = timezone.utc

API = "https://api-web.nhle.com/v1"
USER_AGENT = "Hockey StatScout (jackwallner+bb@gmail.com)"  # same as ingest.USER_AGENT
REQUEST_PAUSE_SECONDS = 0.3  # same as ingest.REQUEST_PAUSE_SECONDS
REQUEST_ATTEMPTS = 3
TIMEOUT_SECONDS = 30

FINAL_STATES = frozenset({"FINAL", "OFF"})
GAME_TYPE_REG = 2
GAME_TYPE_POST = 3
ROUND_CODES = {1: "R1", 2: "R2", 3: "CF", 4: "SCF"}

# The 32 clubs on the NHL codes (Utah replaced Arizona in 2024-25).
TEAMS = (
    "ANA BOS BUF CGY CAR CHI COL CBJ DAL DET EDM FLA LAK MIN MTL NSH NJD NYI "
    "NYR OTT PHI PIT SJS SEA STL TBL TOR UTA VAN VGK WSH WPG"
).split()
LAST_ARIZONA_SEASON = 2023


@dataclass(frozen=True)
class Game:
    game_id: str
    season: int
    season_type: str
    game_type: str
    week: int
    game_date: date
    kickoff_at: Optional[datetime]
    away_team: str
    home_team: str
    away_score: Optional[int]
    home_score: Optional[int]
    overtime: bool
    stadium: Optional[str]

    @property
    def is_final(self) -> bool:
        return self.away_score is not None and self.home_score is not None

    def as_row(self, synced_at: datetime) -> dict[str, Any]:
        return {
            "game_id": self.game_id,
            "season": self.season,
            "season_type": self.season_type,
            "game_type": self.game_type,
            "week": self.week,
            "game_date": self.game_date.isoformat(),
            "kickoff_at": self.kickoff_at.isoformat() if self.kickoff_at else None,
            "away_team": self.away_team,
            "home_team": self.home_team,
            "away_score": self.away_score,
            "home_score": self.home_score,
            "overtime": self.overtime,
            "stadium": self.stadium,
            "synced_at": synced_at.isoformat(),
        }


# --------------------------------------------------------------------------- #
# Pure helpers (unit-tested)
# --------------------------------------------------------------------------- #
def season_id(season: int) -> int:
    """NHL API seasonId for a start-year season (2025 -> 20252026)."""
    return int(f"{season}{season + 1}")


def monday_on_or_before(day: date) -> date:
    return day - timedelta(days=day.weekday())


def league_week(game_day: date, season_start: date) -> int:
    """1-based count of 7-day blocks from the Monday on or before the opener."""
    return (game_day - monday_on_or_before(season_start)).days // 7 + 1


def playoff_round(game_id: Any) -> Optional[str]:
    """Round code from an NHL playoff id (2025030186 -> round digit 1 -> R1)."""
    text = str(game_id)
    if len(text) != 10 or not text[7].isdigit():
        return None
    return ROUND_CODES.get(int(text[7]))


def _parse_utc(value: Any) -> Optional[datetime]:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def _score(team: Mapping[str, Any]) -> Optional[int]:
    value = team.get("score")
    return int(value) if value is not None else None


def _last_period_type(raw: Mapping[str, Any]) -> str:
    outcome = raw.get("gameOutcome") or {}
    period = raw.get("periodDescriptor") or {}
    return str(outcome.get("lastPeriodType") or period.get("periodType") or "").upper()


def parse_game(
    raw: Mapping[str, Any],
    season: int,
    season_start: date,
    day: Optional[date] = None,
) -> Optional[Game]:
    """One NHL schedule game as a ``Game``; None for preseason, all-star, no date."""
    game_type = raw.get("gameType")
    if game_type not in (GAME_TYPE_REG, GAME_TYPE_POST):
        return None
    if str(raw.get("gameScheduleState") or "OK").upper() == "CNCL":
        return None
    game_day = day
    if game_day is None and raw.get("gameDate"):
        game_day = date.fromisoformat(str(raw["gameDate"])[:10])
    if game_day is None:
        return None
    is_post = game_type == GAME_TYPE_POST
    code = (playoff_round(raw["id"]) if is_post else "REG")
    if code is None:
        return None
    away, home = raw.get("awayTeam") or {}, raw.get("homeTeam") or {}
    final = str(raw.get("gameState") or "").upper() in FINAL_STATES
    venue = (raw.get("venue") or {}).get("default")
    return Game(
        game_id=str(raw["id"]),
        season=season,
        season_type="POST" if is_post else "REG",
        game_type=code,
        week=league_week(game_day, season_start),
        game_date=game_day,
        kickoff_at=_parse_utc(raw.get("startTimeUTC")),
        away_team=str(away.get("abbrev") or ""),
        home_team=str(home.get("abbrev") or ""),
        away_score=_score(away) if final else None,
        home_score=_score(home) if final else None,
        overtime=final and _last_period_type(raw) in ("OT", "SO"),
        stadium=venue or None,
    )


def parse_games(
    raws: Iterable[Mapping[str, Any]],
    season: int,
    season_start: date,
) -> list[Game]:
    """Parse and de-duplicate by id (every game is listed under both clubs)."""
    games: dict[str, Game] = {}
    for raw in raws:
        game = parse_game(raw, season, season_start)
        if game is not None and game.away_team and game.home_team:
            games[game.game_id] = game
    return sorted(games.values(), key=lambda g: (g.game_date, g.game_id))


def parse_schedule_week(payload: Mapping[str, Any], season: int) -> list[Game]:
    """Games from a ``schedule/<date>`` payload, dated by their schedule day."""
    start = date.fromisoformat(str(payload["regularSeasonStartDate"]))
    games: list[Game] = []
    for entry in payload.get("gameWeek") or []:
        day = date.fromisoformat(str(entry["date"]))
        for raw in entry.get("games") or []:
            if _season_of(raw) != season:
                continue
            game = parse_game(raw, season, start, day)
            if game is not None and game.away_team and game.home_team:
                games.append(game)
    return games


def _season_of(raw: Mapping[str, Any]) -> int:
    """Start year of a game's seasonId (20252026 -> 2025)."""
    return int(str(raw.get("season") or "0")[:4])


def teams_for(season: int) -> list[str]:
    return ["ARI" if t == "UTA" and season <= LAST_ARIZONA_SEASON else t for t in TEAMS]


# --------------------------------------------------------------------------- #
# Network (stdlib)
# --------------------------------------------------------------------------- #
def fetch_json(url: str) -> dict[str, Any]:
    """GET JSON with the fleet User-Agent, a polite pause and retries."""
    last_error: Optional[Exception] = None
    for attempt in range(1, REQUEST_ATTEMPTS + 1):
        try:
            request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                payload = json.loads(response.read().decode("utf-8"))
            time.sleep(REQUEST_PAUSE_SECONDS)
            return payload
        except (URLError, TimeoutError, ValueError) as error:
            last_error = error
            logger.warning("GET %s failed (attempt %d): %s", url, attempt, error)
            time.sleep(2 ** attempt)
    raise RuntimeError(f"GET {url} failed after {REQUEST_ATTEMPTS} attempts") from last_error


def season_start_date(season: int) -> date:
    """``regularSeasonStartDate`` of a season (any October day returns it)."""
    payload = fetch_json(f"{API}/schedule/{season}-10-15")
    return date.fromisoformat(str(payload["regularSeasonStartDate"]))


def fetch_season(season: int) -> list[Game]:
    """Every regular-season and playoff game scheduled so far (32 club calls)."""
    start = season_start_date(season)
    raws: list[Mapping[str, Any]] = []
    for team in teams_for(season):
        payload = fetch_json(f"{API}/club-schedule-season/{team}/{season_id(season)}")
        raws.extend(payload.get("games") or [])
    games = parse_games(raws, season, start)
    logger.info("NHL schedule %s: %d games from %d club calls", season, len(games), len(TEAMS))
    return games


def fetch_recent(season: int, today: date) -> list[Game]:
    """The seven days starting yesterday: scores for games that just ended."""
    payload = fetch_json(f"{API}/schedule/{(today - timedelta(days=1)).isoformat()}")
    return parse_schedule_week(payload, season)


def resolve_season(now: datetime) -> int:
    raw = os.environ.get("STATCAST_SEASON", "").strip()
    if raw:
        return int(raw)
    return now.year if now.month >= 9 else now.year - 1


def sync_full(db: Any, season: int, now: datetime) -> int:
    """Upsert the live and previous seasons. Returns the games written."""
    games: list[Game] = []
    for year in (season - 1, season):
        games.extend(fetch_season(year))
    db.upsert_games([g.as_row(now) for g in games])
    return len(games)


def sync_recent(db: Any, season: int, now: datetime) -> int:
    games = fetch_recent(season, now.date())
    db.upsert_games([g.as_row(now) for g in games])
    return len(games)


def main() -> int:
    from refresh_schedule import Supabase  # lazy: refresh_schedule imports this module

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="Live season (start year).")
    parser.add_argument("--only", action="store_true", help="Sync just --season, not the one before.")
    parser.add_argument("--recent", action="store_true", help="One-call score refresh instead of a full sync.")
    args = parser.parse_args()
    now = datetime.now(UTC)
    season = args.season if args.season is not None else resolve_season(now)
    db = Supabase(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    if args.recent:
        count = sync_recent(db, season, now)
    elif args.only:
        games = fetch_season(season)
        db.upsert_games([g.as_row(now) for g in games])
        count = len(games)
    else:
        count = sync_full(db, season, now)
    logger.info("Synced %d games", count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
