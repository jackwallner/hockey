"""Build and atomically publish one current NFL season refresh.

The source probe creates a ``data_refresh_runs`` row before this command is
started.  This command downloads the current season once, computes snapshots,
per-game logs, and Recent Form in memory, stages all rows under that refresh
ID, validates coverage, and asks Postgres to publish the three sets together.
The serving tables are never modified directly by this path.

The current season is deliberately rebuilt in full.  The 2026 feed is small,
and a full read is the safest inexpensive way to capture late corrections and
new NGS/PFR enrichment while the durable game identity remains date-compatible
with the existing app schema.
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
from datetime import date, datetime, timezone
from typing import Any, Iterable, Optional
from urllib.parse import urlparse

import nflreadpy as nfl
import pandas as pd
import polars as pl
from dotenv import load_dotenv
from supabase import create_client

from ingest import (
    DEFAULT_SEASON,
    _to_pandas as _snapshot_to_pandas,
    build_agg_for_season,
    build_snapshot_rows,
    qualification_scale,
    resolve_season,
)
from ingest_game_logs import (
    _load_ngs_lookups,
    build_game_log_rows,
    schedule_map,
)
from rollup_recent_form import _routable_logs, build_rows
from source_probe import probe_sources

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc
STAGE_TABLES = (
    "player_snapshots_refresh",
    "player_game_logs_refresh",
    "player_recent_form_refresh",
)


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
    ngs_status: str
    pfr_status: str


def _to_pandas(frame: Any) -> pd.DataFrame:
    if isinstance(frame, pl.DataFrame):
        return frame.to_pandas()
    return frame


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


def _safe_date(value: Any) -> date | None:
    if value is None or pd.isna(value):
        return None
    try:
        return pd.to_datetime(value, errors="coerce").date()
    except (TypeError, ValueError, OverflowError):
        return None


def _coverage(weekly: pd.DataFrame, schedule: pd.DataFrame, season: int, now: datetime) -> Coverage:
    """Measure source coverage while allowing a week to arrive game by game."""
    if weekly is None or weekly.empty:
        return Coverage(None, None, 0, 0, "partial")

    scheduled: dict[str, date] = {}
    expected_ids: set[str] = set()
    for _, row in schedule.iterrows():
        if row.get("season") is not None and not pd.isna(row.get("season")):
            try:
                if int(row.get("season")) != season:
                    continue
            except (TypeError, ValueError):
                continue
        game_id = row.get("game_id")
        game_date = _safe_date(row.get("gameday"))
        if game_id is None or game_date is None:
            continue
        game_id = str(game_id)
        scheduled[game_id] = game_date
        game_type = str(row.get("game_type") or "").upper()
        # The player weekly feed is regular/postseason data.  Exclude known
        # preseason rows from the expected completed-game denominator, while
        # retaining rows with a missing type for old schedule releases.
        if game_type in {"PRE", "PRESEASON"}:
            continue
        # Same-day fixtures are not completed games. Prefer posted scores;
        # old schedule formats without score columns fall back to prior dates.
        has_scores = "home_score" in schedule.columns and "away_score" in schedule.columns
        completed = (
            pd.notna(row.get("home_score")) and pd.notna(row.get("away_score"))
            if has_scores else game_date < now.date()
        )
        if completed:
            expected_ids.add(game_id)

    source_ids: set[str] = set()
    if "game_id" in weekly.columns:
        source_ids = {
            str(value)
            for value in weekly["game_id"].dropna().tolist()
            if str(value).strip()
        }
    observed_ids = source_ids.intersection(scheduled)
    expected_count = len(expected_ids)
    observed_count = len(observed_ids)

    source_rows = weekly
    if observed_ids and "game_id" in weekly.columns:
        source_rows = weekly[weekly["game_id"].astype(str).isin(observed_ids)]
    max_week: int | None = None
    if "week" in source_rows.columns:
        weeks = pd.to_numeric(source_rows["week"], errors="coerce").dropna()
        if not weeks.empty:
            max_week = int(weeks.max())
    dates = [scheduled[game_id] for game_id in observed_ids if game_id in scheduled]
    max_date = max(dates).isoformat() if dates else None
    status = "complete" if expected_count <= observed_count else "partial"
    return Coverage(max_week, max_date, expected_count, observed_count, status)


def _validate_unique(rows: Iterable[dict[str, Any]], keys: tuple[str, ...], label: str) -> None:
    seen: set[tuple[Any, ...]] = set()
    for row in rows:
        key = tuple(row.get(column) for column in keys)
        if any(value is None or value == "" for value in key):
            raise CandidateNotReady(f"{label} has an incomplete key: {key}")
        if key in seen:
            raise CandidateNotReady(f"{label} has duplicate key: {key}")
        seen.add(key)


def build_candidate(season: int, *, now: datetime | None = None) -> Candidate:
    """Build all output rows without touching Supabase."""
    now = (now or datetime.now(UTC)).astimezone(UTC)
    logger.info("Loading weekly player stats and schedule for %s", season)
    weekly = _snapshot_to_pandas(nfl.load_player_stats([season]))
    schedule_frame = _snapshot_to_pandas(nfl.load_schedules([season]))
    if weekly is None or weekly.empty:
        raise CandidateNotReady(f"weekly player stats are empty for {season}")
    sched = schedule_map(schedule_frame)
    coverage = _coverage(weekly, schedule_frame, season, now)
    logger.info(
        "Source coverage: games=%d/%d max_week=%s max_game_date=%s (%s)",
        coverage.observed_games,
        coverage.expected_games,
        coverage.max_week,
        coverage.max_game_date,
        coverage.coverage_status,
    )

    live = season == DEFAULT_SEASON
    snapshot_rows: list[dict[str, Any]] = []
    phase_ngs: list[str] = []
    phase_pfr: list[str] = []
    for phase in ("REG", "POST"):
        enrichment: dict[str, str] = {}
        agg = build_agg_for_season(
            season,
            phase,
            live=live,
            weekly_frame=weekly,
            enrichment_status=enrichment,
        )
        if agg.empty:
            logger.info("No %s snapshot source rows for %s", phase, season)
            continue
        scale = qualification_scale(agg, season) if phase == "REG" else 1.0
        rows = build_snapshot_rows(
            agg,
            season,
            now,
            phase,
            qual_scale=scale,
            live=live,
        )
        if rows:
            snapshot_rows.extend(rows)
        phase_ngs.append(enrichment.get("ngs", "unknown"))
        phase_pfr.append(enrichment.get("pfr", "unknown"))

    if not snapshot_rows:
        raise CandidateNotReady(f"no snapshot rows built for {season}")

    log_enrichment: dict[str, str] = {}
    ngs_pass, ngs_rush, ngs_rec = _load_ngs_lookups(season, log_enrichment)
    game_log_rows = build_game_log_rows(
        weekly,
        sched,
        season,
        now,
        ngs_pass,
        ngs_rush,
        ngs_rec,
    )
    if not game_log_rows:
        raise CandidateNotReady(f"no game-log rows built for {season}")
    if coverage.observed_games == 0 or not coverage.max_game_date:
        raise CandidateNotReady("Source games do not resolve to the current schedule")
    if any(row.get("season") != season for row in snapshot_rows + game_log_rows):
        raise CandidateNotReady("Candidate contains a different season")

    snapshot_keys = {
        (int(row["id"]), str(row.get("season_type") or "REG"))
        for row in snapshot_rows
    }
    recent_rows = _routable_logs(build_rows(game_log_rows), snapshot_keys)
    if not recent_rows:
        raise CandidateNotReady(f"no Recent Form rows resolve for {season}")

    season_types = tuple(sorted({str(row.get("season_type") or "REG") for row in snapshot_rows}))
    game_log_rows = [
        row for row in game_log_rows
        if str(row.get("season_type") or "REG") in season_types
    ]
    recent_rows = [
        row for row in recent_rows
        if str(row.get("season_type") or "REG") in season_types
    ]
    _validate_unique(snapshot_rows, ("id", "season", "season_type"), "snapshots")
    _validate_unique(
        game_log_rows,
        ("player_id", "season", "season_type", "game_date", "player_type"),
        "game logs",
    )
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
        ngs_status=_merge_status(*(phase_ngs + [log_enrichment.get("ngs", "unknown")])),
        pfr_status=_merge_status(*phase_pfr) if phase_pfr else "unknown",
    )


# Build-time stamps differ on every run even when no stat changed.
VOLATILE_ROW_KEYS = frozenset({"updated_at", "refresh_id", "source_published_at", "published_at"})


def content_hash(candidate: Candidate) -> str:
    """Hash the serving output, ignoring build timestamps.

    Two builds of identical football produce the same hash, so a source
    re-upload that changes no stat can be recorded without republishing.
    """
    digest = hashlib.sha256()
    for label, rows in (
        ("snapshots", candidate.snapshots),
        ("game_logs", candidate.game_logs),
        ("recent_form", candidate.recent_form),
    ):
        normalized = sorted(
            json.dumps(
                {k: v for k, v in row.items() if k not in VOLATILE_ROW_KEYS},
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
    if urlparse(url).hostname != "qwkmpwnhrejsuplcwxrb.supabase.co":
        raise RuntimeError("Refusing to publish outside the Football Supabase project")
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
    for offset in range(0, len(values), 250):
        client.table(table).insert(values[offset : offset + 250]).execute()
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


def publish(refresh_id: str, *, season: int | None = None, now: datetime | None = None) -> dict[str, Any]:
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
        candidate = build_candidate(target_season, now=now)
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
                "p_ngs_status": candidate.ngs_status,
                "p_pfr_status": candidate.pfr_status,
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
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = _parse_args()
    publish(args.refresh_id, season=args.season)
    return 0


if __name__ == "__main__":
    sys.exit(main())
