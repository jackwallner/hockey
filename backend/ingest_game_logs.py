"""
Per-player-per-game NHL ingest. Powers player game logs and the 2/4/8-week
Trends windows (``rollup_recent_form.py``).

One ``public.player_game_logs`` row per player per game, keyed
``(player_id, season, season_type, game_date, player_type)`` with ``game_id``
(the NHL id as text) alongside. Rows are raw counts, never rates, so a window
rate is recomputed exactly from summed numerators and denominators. ``plays`` is
time on ice in whole minutes and ``touches`` is shot attempts (skaters) or shots
against (goalies). Metric keys are exactly the contract's:

  skaters  goals, assists, primary_assists, points, shots_on_goal,
           shot_attempts, ixg, hd_shots, hits, blocks, takeaways, giveaways,
           pim, plus_minus, pp_goals, faceoffs_won, faceoffs_lost, toi_seconds
  goalies  shots_against, saves, goals_against, xga, hd_shots_against,
           hd_goals_against, toi_seconds, decision_win, shutout, started

Three sources per game, joined on the NHL player id:

* NHL boxscore ``gamecenter/<id>/boxscore``: the counting stats and ice time.
* NHL play-by-play ``gamecenter/<id>/play-by-play``: faceoff counts (the
  boxscore carries only a percentage), primary assists (``assist1PlayerId``)
  and the shooter's blocked attempts. The contract named the boxscore alone;
  that cannot supply faceoffs won and lost, and MoneyPuck's shot file leaves
  blocked attempts out, which would put the per-game ``shot_attempts`` below
  the season total in ``player_snapshots``.
* MoneyPuck ``shots_<season>.zip`` (downloaded once per run into
  ``backend/.cache/``): expected goals per shot. Per game and shooter it gives
  ixG, unblocked attempts and high-danger shots (xG >= 0.2, which reproduces
  MoneyPuck's own high-danger count); per game and goalie it gives xGA, high
  danger shots against and high-danger goals against. ``shot_attempts`` is the
  unblocked attempts plus the play-by-play blocked ones, which matches
  MoneyPuck's season ``I_F_shotAttempts``.

A final game is ingested only once MoneyPuck's shot file contains it, so a row
never carries a false zero ixG. Games not yet in the file are left for the next
run (the refresh probe fingerprints the shot file, so it runs when they land).

Incremental by default: only finals in ``public.games`` with no game-log rows
yet. ``--full`` re-ingests the whole season and prunes rows it no longer
produced. ``--season N`` overrides the resolved season.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import os
import sys
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterable, Iterator, Mapping, Optional

import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

from ingest import DEFAULT_SEASON, chunks, http_get, player_type_from_position, resolve_season

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

NHL_API = "https://api-web.nhle.com/v1/gamecenter/{game_id}/{kind}"
SHOTS_URL = "https://peter-tanner.com/moneypuck/downloads/shots_{season}.zip"
HIGH_DANGER_XG = 0.2
UPSERT_BATCH = 200
LOG_BATCH_GAMES = 25  # games ingested between upserts in the CLI

SKATER_KEYS = (
    "goals", "assists", "primary_assists", "points", "shots_on_goal",
    "shot_attempts", "ixg", "hd_shots", "hits", "blocks", "takeaways",
    "giveaways", "pim", "plus_minus", "pp_goals", "faceoffs_won",
    "faceoffs_lost", "toi_seconds",
)
GOALIE_KEYS = (
    "shots_against", "saves", "goals_against", "xga", "hd_shots_against",
    "hd_goals_against", "toi_seconds", "decision_win", "shutout", "started",
)
SHOT_COLUMNS = ("game_id", "xGoal", "goal", "shooterPlayerId", "goalieIdForShot")
STORE_PLACES = 3

_shots_memo: dict[int, pd.DataFrame] = {}


# --------------------------------------------------------------------------- #
# Pure helpers (unit-tested; no network)
# --------------------------------------------------------------------------- #
def toi_seconds(text: Any) -> int:
    """``"19:42"`` -> 1182; blank or malformed -> 0."""
    try:
        minutes, seconds = str(text).split(":")[:2]
        return int(minutes) * 60 + int(seconds)
    except (ValueError, TypeError):
        return 0


def short_game_id(game_id: Any) -> int:
    """NHL id -> MoneyPuck shot-file id (2025020001 -> 20001)."""
    return int(str(game_id)[4:])


def _int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


@dataclass
class ShotTables:
    """Per (short game id, player id) sums from the MoneyPuck shot file."""

    skaters: dict[tuple[int, int], dict[str, float]] = field(default_factory=dict)
    goalies: dict[tuple[int, int], dict[str, float]] = field(default_factory=dict)
    games: set[int] = field(default_factory=set)


def build_shot_tables(shots: pd.DataFrame) -> ShotTables:
    """Group the shot file by game and shooter / goalie."""
    tables = ShotTables()
    if shots.empty:
        return tables
    frame = shots.copy()
    frame["hd"] = (frame["xGoal"] >= HIGH_DANGER_XG).astype(int)
    frame["hd_goal"] = frame["hd"] * frame["goal"].fillna(0).astype(int)
    tables.games = {int(g) for g in frame["game_id"].dropna().unique()}

    shooters = frame[frame["shooterPlayerId"].notna()]
    grouped = shooters.groupby(["game_id", "shooterPlayerId"]).agg(
        ixg=("xGoal", "sum"), attempts=("xGoal", "size"), hd=("hd", "sum")
    )
    for (game, player), row in grouped.iterrows():
        tables.skaters[(int(game), int(player))] = {
            "ixg": float(row["ixg"]), "attempts": int(row["attempts"]), "hd": int(row["hd"]),
        }

    goalies = frame[frame["goalieIdForShot"].fillna(0) > 0]
    grouped = goalies.groupby(["game_id", "goalieIdForShot"]).agg(
        xga=("xGoal", "sum"), hd=("hd", "sum"), hd_goals=("hd_goal", "sum")
    )
    for (game, player), row in grouped.iterrows():
        tables.goalies[(int(game), int(player))] = {
            "xga": float(row["xga"]), "hd": int(row["hd"]), "hd_goals": int(row["hd_goals"]),
        }
    return tables


def parse_play_by_play(pbp: Mapping[str, Any]) -> dict[int, dict[str, int]]:
    """Per player: faceoffs won/lost, primary assists, blocked shot attempts."""
    stats: dict[int, dict[str, int]] = {}

    def bump(player: Any, key: str) -> None:
        if player:
            row = stats.setdefault(int(player), {
                "faceoffs_won": 0, "faceoffs_lost": 0, "primary_assists": 0, "blocked_attempts": 0,
            })
            row[key] += 1

    for play in pbp.get("plays") or []:
        kind = play.get("typeDescKey")
        details = play.get("details") or {}
        if kind == "faceoff":
            bump(details.get("winningPlayerId"), "faceoffs_won")
            bump(details.get("losingPlayerId"), "faceoffs_lost")
        elif kind == "goal":
            bump(details.get("assist1PlayerId"), "primary_assists")
        elif kind == "blocked-shot":
            bump(details.get("shootingPlayerId"), "blocked_attempts")
    return stats


def _skater_row(
    player: Mapping[str, Any],
    group_type: str,
    shots: Mapping[str, float],
    play: Mapping[str, int],
) -> Optional[dict[str, Any]]:
    seconds = toi_seconds(player.get("toi"))
    if seconds <= 0:
        return None
    attempts = int(shots.get("attempts", 0)) + int(play.get("blocked_attempts", 0))
    metrics = {
        "goals": _int(player.get("goals")),
        "assists": _int(player.get("assists")),
        "primary_assists": int(play.get("primary_assists", 0)),
        "points": _int(player.get("points")),
        "shots_on_goal": _int(player.get("sog")),
        "shot_attempts": attempts,
        "ixg": round(float(shots.get("ixg", 0.0)), STORE_PLACES),
        "hd_shots": int(shots.get("hd", 0)),
        "hits": _int(player.get("hits")),
        "blocks": _int(player.get("blockedShots")),
        "takeaways": _int(player.get("takeaways")),
        "giveaways": _int(player.get("giveaways")),
        "pim": _int(player.get("pim")),
        "plus_minus": _int(player.get("plusMinus")),
        "pp_goals": _int(player.get("powerPlayGoals")),
        "faceoffs_won": int(play.get("faceoffs_won", 0)),
        "faceoffs_lost": int(play.get("faceoffs_lost", 0)),
        "toi_seconds": seconds,
    }
    return {
        "player_id": int(player["playerId"]),
        "player_type": player_type_from_position(player.get("position")) or group_type,
        "plays": seconds // 60,
        "touches": attempts,
        "metrics": metrics,
    }


def _goalie_row(
    player: Mapping[str, Any],
    shots: Mapping[str, float],
    sole_goalie: bool,
    shootout: bool,
) -> Optional[dict[str, Any]]:
    seconds = toi_seconds(player.get("toi"))
    if seconds <= 0:
        return None
    against = _int(player.get("goalsAgainst"))
    won = str(player.get("decision") or "").upper() == "W"
    shots_against = _int(player.get("shotsAgainst"))
    metrics = {
        "shots_against": shots_against,
        "saves": _int(player.get("saves")),
        "goals_against": against,
        "xga": round(float(shots.get("xga", 0.0)), STORE_PLACES),
        "hd_shots_against": int(shots.get("hd", 0)),
        "hd_goals_against": int(shots.get("hd_goals", 0)),
        "toi_seconds": seconds,
        "decision_win": int(won),
        # A shutout needs the whole game with no goals against; a shootout win
        # is not one.
        "shutout": int(won and against == 0 and sole_goalie and not shootout),
        "started": int(bool(player.get("starter"))),
    }
    return {
        "player_id": int(player["playerId"]),
        "player_type": "g",
        "plays": seconds // 60,
        "touches": shots_against,
        "metrics": metrics,
    }


def build_game_rows(
    game: Mapping[str, Any],
    boxscore: Mapping[str, Any],
    pbp_stats: Mapping[int, Mapping[str, int]],
    tables: ShotTables,
    now: datetime,
) -> list[dict[str, Any]]:
    """Every player-game row for one final game (pure)."""
    short = short_game_id(game["game_id"])
    shootout = str((boxscore.get("gameOutcome") or {}).get("lastPeriodType") or "").upper() == "SO"
    teams = {
        "homeTeam": (boxscore["homeTeam"].get("abbrev"), boxscore["awayTeam"].get("abbrev")),
        "awayTeam": (boxscore["awayTeam"].get("abbrev"), boxscore["homeTeam"].get("abbrev")),
    }
    rows: list[dict[str, Any]] = []
    for side, (team, opponent) in teams.items():
        stats = (boxscore.get("playerByGameStats") or {}).get(side) or {}
        goalies = stats.get("goalies") or []
        played = [g for g in goalies if toi_seconds(g.get("toi")) > 0]
        built: list[Optional[dict[str, Any]]] = []
        for group, group_type in (("forwards", "f"), ("defense", "d")):
            for player in stats.get(group) or []:
                key = (short, int(player["playerId"]))
                built.append(_skater_row(
                    player, group_type,
                    tables.skaters.get(key, {}), pbp_stats.get(int(player["playerId"]), {}),
                ))
        for player in goalies:
            key = (short, int(player["playerId"]))
            built.append(_goalie_row(player, tables.goalies.get(key, {}), len(played) == 1, shootout))
        for row in built:
            if row is None:
                continue
            rows.append({
                **row,
                "season": int(game["season"]),
                "season_type": game["season_type"],
                "game_id": str(game["game_id"]),
                "game_date": str(game["game_date"])[:10],
                "week": game.get("week"),
                "team": team,
                "opponent": opponent,
                "updated_at": now.isoformat(),
            })
    return rows


# --------------------------------------------------------------------------- #
# Network
# --------------------------------------------------------------------------- #
def load_shot_tables(season: int, live: bool) -> Optional[ShotTables]:
    """MoneyPuck shot file for the season, grouped; None when it is not published.

    Downloaded once per process. Finished seasons also live in
    ``backend/.cache/`` so a re-ingest does not download 20 MB again.
    """
    if season not in _shots_memo:
        content = http_get(SHOTS_URL.format(season=season), cache=not live)
        if not content:
            return None
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            name = next(n for n in archive.namelist() if n.endswith(".csv"))
            frame = pd.read_csv(archive.open(name), usecols=lambda c: c in SHOT_COLUMNS)
        logger.info("MoneyPuck shots %s: %d rows", season, len(frame))
        _shots_memo[season] = frame
    return build_shot_tables(_shots_memo[season])


def fetch_gamecenter(game_id: str, kind: str) -> Optional[dict[str, Any]]:
    content = http_get(NHL_API.format(game_id=game_id, kind=kind))
    return json.loads(content) if content else None


def fetch_final_games(client: Any, season: int) -> list[dict[str, Any]]:
    """Finals in ``public.games`` for the season, oldest first."""
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        page = (
            client.table("games")
            .select("game_id,season,season_type,game_date,week,away_team,home_team")
            .eq("season", season)
            .not_.is_("home_score", "null")
            .not_.is_("away_score", "null")
            .order("game_date")
            .order("game_id")
            .range(offset, offset + 999)
            .execute()
            .data
        ) or []
        rows.extend(page)
        if len(page) < 1000:
            return rows
        offset += 1000


def logged_game_ids(client: Any, season: int) -> set[str]:
    """Game ids that already have rows (read off the goalie rows, 2 to 3 per game)."""
    ids: set[str] = set()
    offset = 0
    while True:
        page = (
            client.table("player_game_logs")
            .select("game_id")
            .eq("season", season)
            .eq("player_type", "g")
            .order("game_id")
            .range(offset, offset + 999)
            .execute()
            .data
        ) or []
        ids.update(str(r["game_id"]) for r in page if r.get("game_id"))
        if len(page) < 1000:
            return ids
        offset += 1000


@dataclass
class GameBatch:
    """Rows built in one pass plus the finals that had to wait."""

    rows: list[dict[str, Any]] = field(default_factory=list)
    done: list[str] = field(default_factory=list)
    pending: list[str] = field(default_factory=list)
    shots_status: str = "ready"


def iter_game_rows(
    games: Iterable[Mapping[str, Any]],
    tables: Optional[ShotTables],
    now: datetime,
    pending: list[str],
) -> Iterator[tuple[str, list[dict[str, Any]]]]:
    """Yield ``(game_id, rows)`` for each game whose three sources are ready.

    Games missing from the shot file, or whose NHL payloads are unavailable,
    are appended to ``pending`` and retried by the next run.
    """
    for game in games:
        game_id = str(game["game_id"])
        if tables is None or short_game_id(game_id) not in tables.games:
            pending.append(game_id)
            continue
        try:
            boxscore = fetch_gamecenter(game_id, "boxscore")
            pbp = fetch_gamecenter(game_id, "play-by-play")
        except Exception:  # noqa: BLE001 - one bad game must not stop the rest
            logger.exception("NHL payloads failed for %s", game_id)
            pending.append(game_id)
            continue
        if not boxscore or not pbp:
            pending.append(game_id)
            continue
        rows = build_game_rows(game, boxscore, parse_play_by_play(pbp), tables, now)
        if not rows:
            pending.append(game_id)
            continue
        yield game_id, rows


def build_new_rows(
    client: Any,
    season: int,
    now: datetime,
    *,
    full: bool = False,
    live: Optional[bool] = None,
) -> GameBatch:
    """Build rows for finals without logs (all finals when ``full``), in memory."""
    live = season >= DEFAULT_SEASON if live is None else live
    finals = fetch_final_games(client, season)
    logged = set() if full else logged_game_ids(client, season)
    todo = [g for g in finals if str(g["game_id"]) not in logged]
    batch = GameBatch()
    if not todo:
        return batch
    tables = load_shot_tables(season, live)
    for game_id, rows in iter_game_rows(todo, tables, now, batch.pending):
        batch.rows.extend(rows)
        batch.done.append(game_id)
        if len(batch.done) % 100 == 0:
            logger.info("  %d/%d games built", len(batch.done), len(todo))
    batch.shots_status = "ready" if tables is not None and not batch.pending else "pending"
    logger.info("Built %d rows for %d games (%d pending)", len(batch.rows), len(batch.done), len(batch.pending))
    return batch


def upsert(client: Any, rows: list[dict[str, Any]]) -> None:
    for batch in chunks(rows, UPSERT_BATCH):
        client.table("player_game_logs").upsert(
            batch, on_conflict="player_id,season,season_type,game_date,player_type"
        ).execute()


def run(full: bool = False, cli_season: Optional[int] = None) -> None:
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)
    season = resolve_season(cli_season)
    now = datetime.now(UTC)
    finals = fetch_final_games(client, season)
    if not finals:
        logger.info("No final games in public.games for %s; run sync_games.py first.", season)
        return
    logged = set() if full else logged_game_ids(client, season)
    todo = [g for g in finals if str(g["game_id"]) not in logged]
    logger.info("%s: %d finals, %d to ingest%s", season, len(finals), len(todo), " (full)" if full else "")
    if not todo:
        return

    tables = load_shot_tables(season, live=season >= DEFAULT_SEASON)
    pending: list[str] = []
    written = 0
    buffer: list[dict[str, Any]] = []
    for count, (_game_id, rows) in enumerate(iter_game_rows(todo, tables, now, pending), start=1):
        buffer.extend(rows)
        if count % LOG_BATCH_GAMES == 0:
            upsert(client, buffer)
            written += len(buffer)
            buffer = []
            logger.info("  %d games ingested", count)
    upsert(client, buffer)
    written += len(buffer)
    logger.info("Upserted %d game-log rows for %s (%d games still pending).", written, season, len(pending))

    if full and not pending:
        response = (
            client.table("player_game_logs")
            .delete()
            .eq("season", season)
            .lt("updated_at", now.isoformat())
            .execute()
        )
        logger.info("Pruned %d stale game-log rows for %s.", len(response.data or []), season)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="Re-ingest the whole season, not incremental.")
    parser.add_argument("--season", type=int, default=None, help="Season (starting year) to ingest.")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    args = _parse_args()
    run(full=args.full, cli_season=args.season)
