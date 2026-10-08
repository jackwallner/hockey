"""Build and atomically publish one current NHL season refresh.

The source probe creates a ``data_refresh_runs`` row before this command is
started. This command builds the live season's snapshots, per-game logs and
Recent Form in memory, stages all rows under that refresh ID, validates
coverage, and asks Postgres to publish the three sets together. The serving
tables are never modified directly by this path.

Snapshots are rebuilt in full from MoneyPuck and the NHL summary each time.
Game logs are incremental: the serving rows already published for the season are
kept, only finals in ``public.games`` with no rows yet are fetched (boxscore,
play-by-play and the MoneyPuck shot file, see ``ingest_game_logs.py``), and the
union is staged, because the publisher replaces a season's logs wholesale and
refuses a revision that drops a game. ``--full-logs`` rebuilds every final (rows it
produces replace the published ones; a final it cannot rebuild keeps its old rows).
Recent Form is then computed over the union. Finals MoneyPuck has not published
yet wait for the next refresh and show as partial coverage.

Coverage: ``expected_games`` is the finals in the games table for the season and
``observed_games`` the finals that have game-log rows.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable
from urllib.parse import urlparse

from dotenv import load_dotenv
from supabase import create_client

from ingest import (
    DEFAULT_SEASON,
    build_agg_for_season,
    build_snapshot_rows,
    qualification_scale,
)
from ingest_game_logs import build_new_rows, fetch_final_games
from rollup_recent_form import _routable_logs, build_rows
from source_probe import PROJECT_HOST, probe_sources

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc
STAGE_TABLES = (
    "player_snapshots_refresh",
    "player_game_logs_refresh",
    "player_recent_form_refresh",
)
# The staging table's columns; serving rows carry extra provenance columns.
LOG_COLUMNS = (
    "player_id,season,season_type,game_id,game_date,week,player_type,team,"
    "opponent,plays,touches,metrics,updated_at"
)
LOG_KEY = ("player_id", "season", "season_type", "game_date", "player_type")
STAGE_BATCH = 500


class CandidateNotReady(RuntimeError):
    """Raised when a source read cannot produce a safe serving revision."""


@dataclass(frozen=True)
class Coverage:
    max_week: int | None
    max_game_date: str | None
    expected_games: int
    observed_games: int
    coverage_status: str


@dataclass(frozen=True)
class Candidate:
    season: int
    season_types: tuple[str, ...]
    snapshots: tuple[dict[str, Any], ...]
    game_logs: tuple[dict[str, Any], ...]
    recent_form: tuple[dict[str, Any], ...]
    coverage: Coverage
    shots_status: str
    summary_status: str


def _source_status_rank(status: str) -> int:
    return {
        "unknown": 0,
        "not_applicable": 1,
        "ready": 2,
        "pending": 3,
        "degraded": 4,
    }.get(status, 0)


def _merge_status(*statuses: str) -> str:
    return max(statuses, key=_source_status_rank, default="unknown")


def compute_coverage(finals: list[dict[str, Any]], logs: list[dict[str, Any]]) -> Coverage:
    """Finals in the games table against the finals that have game-log rows."""
    final_ids = {str(game["game_id"]) for game in finals}
    logged = {str(row["game_id"]) for row in logs if row.get("game_id")}
    observed = final_ids & logged
    weeks = [int(row["week"]) for row in logs if row.get("week") is not None]
    dates = [str(row["game_date"])[:10] for row in logs]
    return Coverage(
        max_week=max(weeks) if weeks else None,
        max_game_date=max(dates) if dates else None,
        expected_games=len(final_ids),
        observed_games=len(observed),
        coverage_status="complete" if len(final_ids) <= len(observed) else "partial",
    )


def _validate_unique(rows: Iterable[dict[str, Any]], keys: tuple[str, ...], label: str) -> None:
    seen: set[tuple[Any, ...]] = set()
    for row in rows:
        key = tuple(row.get(column) for column in keys)
        if any(value is None or value == "" for value in key):
            raise CandidateNotReady(f"{label} has an incomplete key: {key}")
        if key in seen:
            raise CandidateNotReady(f"{label} has duplicate key: {key}")
        seen.add(key)


def fetch_serving_logs(client: Any, season: int) -> list[dict[str, Any]]:
    """The game-log rows currently published for the season."""
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        page = (
            client.table("player_game_logs")
            .select(LOG_COLUMNS)
            .eq("season", season)
            .order("game_date")
            .order("player_id")
            .order("player_type")
            .range(offset, offset + 999)
            .execute()
            .data
        ) or []
        rows.extend(page)
        if len(page) < 1000:
            return rows
        offset += 1000


def merge_logs(existing: list[dict[str, Any]], new: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Union keyed on the table's primary key; a freshly built row wins."""
    merged = {tuple(row[k] for k in LOG_KEY): row for row in existing}
    merged.update({tuple(row[k] for k in LOG_KEY): row for row in new})
    return list(merged.values())


def build_snapshots(season: int, now: datetime) -> tuple[list[dict[str, Any]], str]:
    """REG and POST snapshot rows plus the merged NHL summary status."""
    live = season == DEFAULT_SEASON
    rows: list[dict[str, Any]] = []
    statuses: list[str] = []
    for phase in ("REG", "POST"):
        enrichment: dict[str, str] = {}
        agg = build_agg_for_season(season, phase, live=live, enrichment_status=enrichment)
        if agg.empty:
            logger.info("No %s snapshot source rows for %s", phase, season)
            continue
        scale = qualification_scale(agg, season) if phase == "REG" else 1.0
        rows.extend(build_snapshot_rows(agg, season, now, phase, qual_scale=scale, live=live))
        statuses.append(enrichment.get("summary", "unknown"))
    return rows, _merge_status(*statuses) if statuses else "unknown"


def build_candidate(
    season: int,
    *,
    client: Any,
    now: datetime | None = None,
    full_logs: bool = False,
) -> Candidate:
    """Build all output rows without writing to Supabase."""
    now = (now or datetime.now(UTC)).astimezone(UTC)
    logger.info("Building snapshots for %s", season)
    snapshot_rows, summary_status = build_snapshots(season, now)
    if not snapshot_rows:
        raise CandidateNotReady(f"no snapshot rows built for {season}")

    existing = fetch_serving_logs(client, season)
    shots_status = "ready"
    try:
        batch = build_new_rows(client, season, now, full=full_logs, live=season == DEFAULT_SEASON)
        new_rows = batch.rows
    except Exception:  # noqa: BLE001 - keep serving the logs already published
        logger.exception("Could not build new game logs; keeping the published ones")
        new_rows, shots_status = [], "degraded"
    game_log_rows = merge_logs(existing, new_rows)
    finals = fetch_final_games(client, season)
    coverage = compute_coverage(finals, game_log_rows)
    if shots_status == "ready" and coverage.coverage_status == "partial":
        shots_status = "pending"
    logger.info(
        "Game logs: %d rows, games=%d/%d max_week=%s max_game_date=%s (%s, shots %s)",
        len(game_log_rows), coverage.observed_games, coverage.expected_games,
        coverage.max_week, coverage.max_game_date, coverage.coverage_status, shots_status,
    )
    if not game_log_rows:
        raise CandidateNotReady(f"no game-log rows built for {season}")
    if any(row.get("season") != season for row in snapshot_rows + game_log_rows):
        raise CandidateNotReady("Candidate contains a different season")

    snapshot_keys = {
        (int(row["id"]), str(row.get("season_type") or "REG"))
        for row in snapshot_rows
    }
    season_types = tuple(sorted({str(row.get("season_type") or "REG") for row in snapshot_rows}))
    game_log_rows = [
        row for row in game_log_rows
        if str(row.get("season_type") or "REG") in season_types
    ]
    recent_rows = _routable_logs(build_rows(game_log_rows, now), snapshot_keys)
    if not recent_rows:
        raise CandidateNotReady(f"no Recent Form rows resolve for {season}")

    _validate_unique(snapshot_rows, ("id", "season", "season_type"), "snapshots")
    _validate_unique(game_log_rows, LOG_KEY, "game logs")
    _validate_unique(
        recent_rows,
        ("player_id", "season", "season_type", "player_type", "window_weeks"),
        "Recent Form",
    )
    return Candidate(
        season=season,
        season_types=season_types,
        snapshots=tuple(snapshot_rows),
        game_logs=tuple(game_log_rows),
        recent_form=tuple(recent_rows),
        coverage=coverage,
        shots_status=shots_status,
        summary_status=summary_status,
    )


# Build-time stamps differ on every run even when no stat changed.
VOLATILE_ROW_KEYS = frozenset({"updated_at", "refresh_id", "source_published_at", "published_at"})


def _canonical(value: Any) -> Any:
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, dict):
        return {k: _canonical(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_canonical(v) for v in value]
    return value


def content_hash(candidate: Candidate) -> str:
    """Hash the serving output, ignoring build timestamps.

    Two builds of identical hockey produce the same hash, so a source
    regeneration that changes no stat can be recorded without republishing.
    Whole-number floats hash as integers: the same value read back from
    Postgres and freshly built must not look different.
    """
    digest = hashlib.sha256()
    for label, rows in (
        ("snapshots", candidate.snapshots),
        ("game_logs", candidate.game_logs),
        ("recent_form", candidate.recent_form),
    ):
        normalized = sorted(
            json.dumps(
                _canonical({k: v for k, v in row.items() if k not in VOLATILE_ROW_KEYS}),
                sort_keys=True,
                separators=(",", ":"),
                default=str,
            )
            for row in rows
        )
        digest.update(label.encode())
        for line in normalized:
            digest.update(line.encode())
            digest.update(b"\n")
    return digest.hexdigest()


def _live_content_hash(client: Any) -> str | None:
    response = (
        client.table("data_refresh_state")
        .select("last_success_content_hash")
        .eq("singleton", True)
        .limit(1)
        .execute()
    )
    rows = getattr(response, "data", None) or []
    return rows[0].get("last_success_content_hash") if rows else None


def _client():
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    if urlparse(url).hostname != PROJECT_HOST:
        raise RuntimeError("Refusing to publish outside the Hockey Supabase project")
    return create_client(url, key)


def _response_data(response: Any) -> Any:
    payload = getattr(response, "data", response)
    if isinstance(payload, list) and len(payload) == 1:
        return payload[0]
    return payload


RPC_ATTEMPTS = 3
TRANSIENT_MARKERS = ("504", "502", "503", "Gateway Timeout", "Bad Gateway", "Service Unavailable", "timed out")


def _is_transient(error: Exception) -> bool:
    text = str(error)
    return any(marker in text for marker in TRANSIENT_MARKERS)


def _rpc(client: Any, function: str, params: dict[str, Any], *, sleep=time.sleep) -> Any:
    """Call a publisher RPC, retrying gateway blips.

    On 2026-09-14 a two-row ``mark_data_refresh_unchanged`` call hit a 5s
    Supabase gateway timeout and failed the whole refresh. The RPCs lock the
    run row, so a retry after a call that did commit is refused with "is
    already <status>"; that means the first attempt landed and counts as done.
    """
    for attempt in range(RPC_ATTEMPTS):
        try:
            response = client.rpc(function, params).execute()
            return _response_data(response)
        except Exception as error:  # noqa: BLE001 - classify, then re-raise
            if attempt > 0 and "is already" in str(error):
                logger.info("%s already applied by an earlier attempt", function)
                return {"status": "already_applied"}
            if attempt + 1 >= RPC_ATTEMPTS or not _is_transient(error):
                raise
            logger.warning("%s transient failure (%s); retrying", function, str(error)[:120])
            sleep(2 + attempt * 4)
    raise RuntimeError("unreachable")


def _stage_rows(client: Any, table: str, refresh_id: str, rows: Iterable[dict[str, Any]]) -> int:
    values = [{"refresh_id": refresh_id, **row} for row in rows]
    if not values:
        return 0
    # Clear a previous attempt's payload before retrying the same refresh ID.
    client.table(table).delete().eq("refresh_id", refresh_id).execute()
    for offset in range(0, len(values), STAGE_BATCH):
        client.table(table).insert(values[offset : offset + STAGE_BATCH]).execute()
    return len(values)


def _run_metadata(client: Any, refresh_id: str) -> dict[str, Any]:
    response = (
        client.table("data_refresh_runs")
        .select("refresh_id,season,source_fingerprint,source_published_at,status")
        .eq("refresh_id", refresh_id)
        .limit(1)
        .execute()
    )
    rows = getattr(response, "data", None) or []
    if not rows:
        raise RuntimeError(f"refresh run {refresh_id} does not exist")
    return rows[0]


def publish(
    refresh_id: str,
    *,
    season: int | None = None,
    now: datetime | None = None,
    full_logs: bool = False,
) -> dict[str, Any]:
    """Build, stage, validate, and atomically publish a refresh."""
    client = _client()
    metadata = _run_metadata(client, refresh_id)
    target_season = int(season if season is not None else metadata["season"])
    if metadata.get("status") not in ("building", "validated"):
        raise RuntimeError(f"refresh run {refresh_id} is {metadata.get('status')}")
    try:
        source_before = probe_sources(target_season)
        if not source_before.ready or source_before.fingerprint != metadata["source_fingerprint"]:
            raise CandidateNotReady("Source generation changed after the probe; retry the new generation")
        candidate = build_candidate(target_season, client=client, now=now, full_logs=full_logs)
        source_after = probe_sources(target_season)
        if not source_after.ready or source_after.fingerprint != source_before.fingerprint:
            raise CandidateNotReady("Source changed during the build; keeping the live revision")
        output_hash = content_hash(candidate)
        if output_hash == _live_content_hash(client):
            result = _rpc(
                client,
                "mark_data_refresh_unchanged",
                {"p_refresh_id": refresh_id, "p_content_hash": output_hash},
            )
            logger.info("Source re-upload changed no stats; live revision kept: %s", result)
            return result
        snapshot_count = _stage_rows(client, STAGE_TABLES[0], refresh_id, candidate.snapshots)
        log_count = _stage_rows(client, STAGE_TABLES[1], refresh_id, candidate.game_logs)
        recent_count = _stage_rows(client, STAGE_TABLES[2], refresh_id, candidate.recent_form)
        _rpc(
            client,
            "update_data_refresh_build",
            {
                "p_refresh_id": refresh_id,
                "p_season_types": list(candidate.season_types),
                "p_max_week": candidate.coverage.max_week,
                "p_max_game_date": candidate.coverage.max_game_date,
                "p_expected_games": candidate.coverage.expected_games,
                "p_observed_games": candidate.coverage.observed_games,
                "p_snapshot_rows": snapshot_count,
                "p_game_log_rows": log_count,
                "p_recent_form_rows": recent_count,
                "p_shots_status": candidate.shots_status,
                "p_summary_status": candidate.summary_status,
            },
        )
        client.table("data_refresh_runs").update({"content_hash": output_hash}).eq(
            "refresh_id", refresh_id
        ).execute()
        result = _rpc(client, "publish_data_refresh", {"p_refresh_id": refresh_id})
        if not isinstance(result, dict) or result.get("status") not in ("published", "degraded"):
            raise RuntimeError(f"atomic publish rejected refresh {refresh_id}: {result}")
        logger.info("Published refresh %s: %s", refresh_id, result)
        return result
    except Exception as exc:
        detail = str(exc).strip()[:4000] or type(exc).__name__
        logger.exception("Refresh %s failed; serving data remains unchanged", refresh_id)
        try:
            _rpc(
                client,
                "fail_data_refresh",
                {
                    "p_refresh_id": refresh_id,
                    "p_error_code": type(exc).__name__,
                    "p_error_detail": detail,
                },
            )
        except Exception:
            logger.exception("Could not persist failed refresh status")
        raise


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh-id", required=True)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--full-logs", action="store_true", help="Rebuild every final's game logs, not just new ones.")
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    args = _parse_args()
    publish(args.refresh_id, season=args.season, full_logs=args.full_logs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
