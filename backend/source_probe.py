"""Probe nflverse release metadata without downloading data files.

The refresh workflow runs this module every 30 minutes while the NFL season
is active.  A probe performs only tiny ``timestamp.json`` requests and HEAD
requests for the assets used by the current-season builder.  It records the
source generation through the Supabase RPC when credentials are available,
then tells GitHub Actions whether a full refresh is needed.

The probe intentionally does not decide that a season is complete.  A source
can publish a valid early week while another recently finished game is still
missing.  The full builder computes coverage from the schedule and the
publisher protects any already-live games from regression.

Environment:
    SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are optional for local probes
    and required by the scheduled workflow so the last successful fingerprint
    survives runner replacement.
    STATCAST_SEASON optionally selects the season; the calendar is used by
    default to preserve the existing workflow contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import sys
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Iterable, Mapping, Optional, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from urllib.parse import urlparse

logger = logging.getLogger(__name__)
UTC = timezone.utc

SOURCE_BASE = "https://github.com/nflverse/nflverse-data/releases/download"
SOURCE_REPOSITORY = "https://github.com/nflverse/nflverse-data"
DEFAULT_TIMEOUT_SECONDS = 20
USER_AGENT = "Gridiron-StatScout/source-probe"


class HTTPClient(Protocol):
    """Small interface that keeps probe tests independent of the network."""

    def get(self, url: str, *, timeout: int) -> "HTTPResponse": ...

    def head(self, url: str, *, timeout: int) -> "HTTPResponse": ...


class HTTPResponse(Protocol):
    status_code: int
    headers: Mapping[str, str]

    def read(self) -> bytes: ...


class UrllibResponse:
    """Adapter exposing the response fields used by ``UrllibHTTPClient``."""

    def __init__(self, response: Any) -> None:
        self._response = response
        self.status_code = int(response.status)
        self.headers = {str(k): str(v) for k, v in response.headers.items()}

    def read(self) -> bytes:
        return self._response.read()


class UrllibHTTPClient:
    """Dependency-free HTTP client for the lightweight probe job."""

    def _request(self, method: str, url: str, timeout: int) -> UrllibResponse:
        request = Request(
            url,
            method=method,
            headers={
                "Accept": "application/json, application/octet-stream, */*",
                "User-Agent": USER_AGENT,
            },
        )
        return UrllibResponse(urlopen(request, timeout=timeout))

    def get(self, url: str, *, timeout: int) -> UrllibResponse:
        return self._request("GET", url, timeout)

    def head(self, url: str, *, timeout: int) -> UrllibResponse:
        return self._request("HEAD", url, timeout)


@dataclass(frozen=True)
class AssetSpec:
    """One release asset and the tiny generation file that owns it."""

    name: str
    tag: str
    filename: str
    required: bool = False

    @property
    def timestamp_url(self) -> str:
        return f"{SOURCE_BASE}/{self.tag}/timestamp.json"

    @property
    def asset_url(self) -> str:
        return f"{SOURCE_BASE}/{self.tag}/{self.filename}"


@dataclass(frozen=True)
class AssetProbe:
    name: str
    tag: str
    filename: str
    required: bool
    timestamp_url: str
    asset_url: str
    status_code: int | None
    timestamp: str | None
    etag: str | None
    last_modified: str | None
    content_length: str | None
    error_code: str | None = None
    error_detail: str | None = None

    @property
    def source_published_at(self) -> datetime | None:
        return parse_source_timestamp(self.timestamp)

    @property
    def available(self) -> bool:
        return self.status_code is not None and 200 <= self.status_code < 300


@dataclass(frozen=True)
class SourceProbeResult:
    season: int
    checked_at: str
    assets: tuple[AssetProbe, ...]
    fingerprint: str
    source_published_at: str | None
    ready: bool
    error_code: str | None = None
    error_detail: str | None = None
    refresh_id: str | None = None
    changed: bool = False

    def as_dict(self) -> dict[str, Any]:
        result = asdict(self)
        result["assets"] = [asdict(asset) for asset in self.assets]
        return result


def resolve_season(value: Optional[int] = None, *, now: datetime | None = None) -> int:
    """Use the repository's September season rollover convention."""
    if value is not None:
        return int(value)
    raw = os.environ.get("STATCAST_SEASON", "").strip()
    if raw:
        return int(raw)
    current = now or datetime.now(UTC)
    return current.year if current.month >= 9 else current.year - 1


def current_asset_specs(season: int) -> tuple[AssetSpec, ...]:
    """Assets that can affect current snapshots, logs, or Recent Form.

    The three NGS assets and the PFR season table are optional inputs to the
    core feed.  They still participate in the fingerprint, so an enrichment
    publication triggers a refresh even when weekly player stats did not move.
    """
    specs: list[AssetSpec] = [
        AssetSpec(
            name="stats_player_week",
            tag="stats_player",
            # ingest.py and ingest_game_logs.py both call the default weekly
            # loader, which resolves to this asset.  Tracking the reg summary
            # file would miss postseason and late weekly corrections.
            filename=f"stats_player_week_{season}.parquet",
            required=True,
        ),
        AssetSpec(
            name="schedule",
            tag="schedules",
            filename="games.parquet",
            required=True,
        ),
    ]
    # Play-by-play feeds the advanced game pages (ingest_game_details.py).
    # Optional: a late pbp upload must not hold back the core player feed.
    specs.append(
        AssetSpec(
            name="pbp",
            tag="pbp",
            filename=f"play_by_play_{season}.parquet",
        )
    )
    if season >= 2016:
        specs.extend(
            AssetSpec(
                name=f"ngs_{stat_type}",
                tag="nextgen_stats",
                filename=f"ngs_{stat_type}.parquet",
            )
            for stat_type in ("passing", "rushing", "receiving")
        )
    if season >= 2018:
        specs.append(
            AssetSpec(
                name="pfr_advstats_def",
                tag="pfr_advstats",
                filename="advstats_season_def.parquet",
            )
        )
    return tuple(specs)


def parse_source_timestamp(value: str | None) -> datetime | None:
    """Parse nflverse's ``YYYY-MM-DD HH:MM:SS EDT`` timestamp format."""
    if not value:
        return None
    text = str(value).strip()
    # ``parsedate_to_datetime`` understands the common RFC form and timezone
    # abbreviations such as GMT.  nflverse uses EDT/EST, which it treats as an
    # unknown timezone, so normalize the two values first.
    normalized = text.replace(" EDT", " -0400").replace(" EST", " -0500")
    try:
        parsed = parsedate_to_datetime(normalized)
    except (TypeError, ValueError, OverflowError):
        parsed = None
    if parsed is None:
        try:
            parsed = datetime.fromisoformat(normalized.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _header(headers: Mapping[str, str], name: str) -> str | None:
    for key, value in headers.items():
        if key.lower() == name.lower():
            return str(value).strip() or None
    return None


def _error_code(exc: BaseException) -> str:
    if isinstance(exc, HTTPError):
        return f"http_{exc.code}"
    if isinstance(exc, (URLError, TimeoutError)):
        return "network_error"
    return "probe_error"


def _error_detail(exc: BaseException) -> str:
    detail = str(exc).strip()
    return detail[:500] if detail else type(exc).__name__


def _read_timestamp(client: HTTPClient, spec: AssetSpec) -> tuple[str | None, str | None, str | None]:
    try:
        response = client.get(spec.timestamp_url, timeout=DEFAULT_TIMEOUT_SECONDS)
        if not 200 <= response.status_code < 300:
            return None, f"http_{response.status_code}", f"timestamp status {response.status_code}"
        payload = json.loads(response.read().decode("utf-8"))
        value = payload.get("last_updated")
        if value is None:
            return None, "invalid_timestamp", "timestamp.json has no last_updated"
        return str(value), None, None
    except Exception as exc:  # noqa: BLE001 - one unavailable asset must be recorded
        return None, _error_code(exc), _error_detail(exc)


def probe_asset(client: HTTPClient, spec: AssetSpec) -> AssetProbe:
    """Probe one timestamp and one asset HEAD request."""
    timestamp, timestamp_error, timestamp_detail = _read_timestamp(client, spec)
    try:
        response = client.head(spec.asset_url, timeout=DEFAULT_TIMEOUT_SECONDS)
        status = int(response.status_code)
        if not 200 <= status < 300:
            return AssetProbe(
                **asdict(
                    AssetProbe(
                        name=spec.name,
                        tag=spec.tag,
                        filename=spec.filename,
                        required=spec.required,
                        timestamp_url=spec.timestamp_url,
                        asset_url=spec.asset_url,
                        status_code=status,
                        timestamp=timestamp,
                        etag=_header(response.headers, "etag"),
                        last_modified=_header(response.headers, "last-modified"),
                        content_length=_header(response.headers, "content-length"),
                        error_code=timestamp_error or f"http_{status}",
                        error_detail=timestamp_detail or f"asset status {status}",
                    )
                )
            )
        return AssetProbe(
            name=spec.name,
            tag=spec.tag,
            filename=spec.filename,
            required=spec.required,
            timestamp_url=spec.timestamp_url,
            asset_url=spec.asset_url,
            status_code=status,
            timestamp=timestamp,
            etag=_header(response.headers, "etag"),
            last_modified=_header(response.headers, "last-modified"),
            content_length=_header(response.headers, "content-length"),
            error_code=timestamp_error,
            error_detail=timestamp_detail,
        )
    except Exception as exc:  # noqa: BLE001 - return a durable pending status
        return AssetProbe(
            name=spec.name,
            tag=spec.tag,
            filename=spec.filename,
            required=spec.required,
            timestamp_url=spec.timestamp_url,
            asset_url=spec.asset_url,
            status_code=None,
            timestamp=timestamp,
            etag=None,
            last_modified=None,
            content_length=None,
            error_code=timestamp_error or _error_code(exc),
            error_detail=timestamp_detail or _error_detail(exc),
        )


# nflverse republishes games.parquet roughly every 30 minutes (odds, weather,
# kickoff tweaks) even when no player stat moved. Completed games reach the app
# only through stats_player_week, so the schedule gates readiness but does not
# start a new data generation. Coverage still reads the schedule at build time.
UNFINGERPRINTED_ASSETS = frozenset({"schedule"})


def fingerprint_assets(assets: Iterable[AssetProbe]) -> str:
    """Return a stable content generation from release metadata.

    ``date`` is deliberately absent.  GitHub response dates change on every
    probe, while the source timestamp, ETag, Last-Modified, and length change
    when an asset is replaced.  Including the status and all optional assets
    also makes enrichment-only corrections trigger a refresh.
    """
    values = [
        {
            "name": asset.name,
            "tag": asset.tag,
            "filename": asset.filename,
            "required": asset.required,
            "status_code": asset.status_code,
            "timestamp": asset.timestamp,
            "etag": asset.etag,
            "last_modified": asset.last_modified,
            "content_length": asset.content_length,
        }
        for asset in sorted(assets, key=lambda item: item.name)
        if asset.name not in UNFINGERPRINTED_ASSETS
    ]
    encoded = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def probe_sources(
    season: int,
    *,
    client: HTTPClient | None = None,
    checked_at: datetime | None = None,
) -> SourceProbeResult:
    """Probe all current-season assets and return a JSON-safe result."""
    http = client or UrllibHTTPClient()
    specs = current_asset_specs(season)
    assets = tuple(probe_asset(http, spec) for spec in specs)
    required_failures = [asset for asset in assets if asset.required and not asset.available]
    source_times = [asset.source_published_at for asset in assets if asset.source_published_at]
    source_published_at = max(source_times).isoformat() if source_times else None
    error_code = required_failures[0].error_code if required_failures else None
    error_detail = required_failures[0].error_detail if required_failures else None
    return SourceProbeResult(
        season=season,
        checked_at=(checked_at or datetime.now(UTC)).astimezone(UTC).isoformat(),
        assets=assets,
        fingerprint=fingerprint_assets(assets),
        source_published_at=source_published_at,
        ready=not required_failures,
        error_code=error_code,
        error_detail=error_detail,
    )


def _rpc_url(base_url: str, function: str) -> str:
    return f"{base_url.rstrip('/')}/rest/v1/rpc/{function}"


def _rpc(
    base_url: str,
    service_key: str,
    function: str,
    params: Mapping[str, Any],
) -> Any:
    request = Request(
        _rpc_url(base_url, function),
        data=json.dumps(dict(params), separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    with urlopen(request, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
        payload = response.read()
    if not payload:
        return None
    return json.loads(payload.decode("utf-8"))


def record_probe(result: SourceProbeResult, *, force: bool = False) -> SourceProbeResult:
    """Persist probe state and, when needed, create a building refresh run."""
    base_url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not base_url or not service_key:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            raise RuntimeError("Scheduled probe requires Football Supabase credentials")
        if result.ready:
            return SourceProbeResult(
                **{
                    **result.as_dict(),
                    "assets": result.assets,
                    "refresh_id": str(uuid.uuid4()),
                    "changed": True,
                }
            )
        return result
    if urlparse(base_url).hostname != "qwkmpwnhrejsuplcwxrb.supabase.co":
        raise RuntimeError("Refusing to update a different Supabase project")

    params = {
        "p_season": result.season,
        "p_source_fingerprint": result.fingerprint,
        "p_source_assets": [asdict(asset) for asset in result.assets],
        "p_source_published_at": result.source_published_at,
        "p_ready": result.ready,
        "p_force": force,
        "p_error_code": result.error_code,
        "p_error_detail": result.error_detail,
    }
    try:
        payload = _rpc(base_url, service_key, "record_data_refresh_probe", params)
        if isinstance(payload, list):
            payload = payload[0] if payload else {}
        payload = payload if isinstance(payload, dict) else {}
        return SourceProbeResult(
            **{
                **result.as_dict(),
                "assets": result.assets,
                "refresh_id": payload.get("refresh_id"),
                "changed": bool(payload.get("changed", False)),
            }
        )
    except Exception as exc:
        raise RuntimeError("Could not persist the source probe state") from exc


def write_github_output(path: str, result: SourceProbeResult) -> None:
    """Write stable step outputs without relying on shell interpolation."""
    values = {
        "season": result.season,
        "ready": str(result.ready).lower(),
        "changed": str(result.changed).lower(),
        "refresh_id": result.refresh_id or "",
        "fingerprint": result.fingerprint,
        "source_published_at": result.source_published_at or "",
        "error_code": result.error_code or "",
    }
    with open(path, "a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--force", action="store_true", help="Refresh even when the fingerprint is unchanged.")
    parser.add_argument("--github-output", default=None, help="Write GitHub Actions step outputs to this path.")
    parser.add_argument("--json", action="store_true", help="Print the complete probe result as JSON.")
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = _parse_args()
    failed = False
    try:
        result = probe_sources(resolve_season(args.season))
        result = record_probe(result, force=args.force)
    except Exception as exc:  # noqa: BLE001 - the scheduled probe must not hide a source outage
        failed = True
        logger.exception("Source probe failed")
        result = SourceProbeResult(
            season=resolve_season(args.season),
            checked_at=datetime.now(UTC).isoformat(),
            assets=(),
            fingerprint="",
            source_published_at=None,
            ready=False,
            error_code=_error_code(exc),
            error_detail=_error_detail(exc),
        )
    if args.github_output:
        write_github_output(args.github_output, result)
    print(json.dumps(result.as_dict(), sort_keys=True))
    if args.json:
        print(json.dumps(result.as_dict(), indent=2, sort_keys=True))
    # A source being unavailable is an expected pending state.  It is stored
    # for the status endpoint and retried on the next scheduled probe.
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
