"""Probe MoneyPuck file metadata without downloading data files.

The refresh workflow runs this module whenever the schedule planner says a probe
is worth it. A probe performs only HEAD requests for the MoneyPuck files the
current-season builder reads: the season summary ``skaters.csv``,
``goalies.csv`` and ``teams.csv`` (regular season and, once it exists, the
playoffs) and ``shots_<season>.zip``. Each is fingerprinted by ETag,
Last-Modified and Content-Length. The NHL web API has no cheap change marker,
so its endpoints are polled by the builder and are not fingerprinted. The probe
records the source generation through the Supabase RPC when credentials are
available, then tells GitHub Actions whether a full refresh is needed.

The probe intentionally does not decide that a season is complete. MoneyPuck
can publish a night's files while another game is still missing; the builder
measures coverage against the ``games`` table and the publisher protects any
already-live games from regression.

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

MONEYPUCK_SUMMARY = "https://moneypuck.com/moneypuck/playerData/seasonSummary/{season}/{phase}/{kind}.csv"
MONEYPUCK_SHOTS = "https://peter-tanner.com/moneypuck/downloads/shots_{season}.zip"
DEFAULT_TIMEOUT_SECONDS = 20
USER_AGENT = "Hockey StatScout (jackwallner+bb@gmail.com)"  # same as ingest.USER_AGENT
PROJECT_HOST = "swlalptdamfccgjmpbyb.supabase.co"


class HTTPClient(Protocol):
    """Small interface that keeps probe tests independent of the network."""

    def head(self, url: str, *, timeout: int) -> "HTTPResponse": ...


class HTTPResponse(Protocol):
    status_code: int
    headers: Mapping[str, str]


class UrllibResponse:
    """Adapter exposing the response fields used by ``UrllibHTTPClient``."""

    def __init__(self, status: int, headers: Mapping[str, Any]) -> None:
        self.status_code = int(status)
        self.headers = {str(k): str(v) for k, v in headers.items()}


class UrllibHTTPClient:
    """Dependency-free HTTP client for the lightweight probe job."""

    def head(self, url: str, *, timeout: int) -> UrllibResponse:
        request = Request(
            url,
            method="HEAD",
            headers={"Accept": "*/*", "User-Agent": USER_AGENT},
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                return UrllibResponse(response.status, response.headers)
        except HTTPError as error:  # 404 for a phase with no file yet is data, not a failure
            return UrllibResponse(error.code, error.headers)


@dataclass(frozen=True)
class AssetSpec:
    """One MoneyPuck file and whether the build cannot run without it."""

    name: str
    url: str
    required: bool = False


@dataclass(frozen=True)
class AssetProbe:
    name: str
    url: str
    required: bool
    status_code: int | None
    etag: str | None
    last_modified: str | None
    content_length: str | None
    error_code: str | None = None
    error_detail: str | None = None

    @property
    def source_published_at(self) -> datetime | None:
        return parse_source_timestamp(self.last_modified)

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
    """MoneyPuck files that can affect snapshots, logs, Recent Form or ratings.

    The regular-season skaters, goalies and shots files gate readiness. The
    teams file feeds ratings only, and every playoff file is absent until the
    postseason starts, so none of those hold back the core feed. They still
    join the fingerprint: a playoff file appearing starts a refresh.
    """
    specs: list[AssetSpec] = []
    for phase in ("regular", "playoffs"):
        for kind in ("skaters", "goalies", "teams"):
            specs.append(AssetSpec(
                name=f"{kind}_{phase}",
                url=MONEYPUCK_SUMMARY.format(season=season, phase=phase, kind=kind),
                required=phase == "regular" and kind != "teams",
            ))
    specs.append(AssetSpec("shots", MONEYPUCK_SHOTS.format(season=season), required=True))
    return tuple(specs)


def parse_source_timestamp(value: str | None) -> datetime | None:
    """Parse an HTTP ``Last-Modified`` date into UTC."""
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(str(value).strip())
    except (TypeError, ValueError, OverflowError):
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


def probe_asset(client: HTTPClient, spec: AssetSpec) -> AssetProbe:
    """Probe one file with a single HEAD request."""
    try:
        response = client.head(spec.url, timeout=DEFAULT_TIMEOUT_SECONDS)
    except Exception as exc:  # noqa: BLE001 - return a durable pending status
        return AssetProbe(
            name=spec.name, url=spec.url, required=spec.required, status_code=None,
            etag=None, last_modified=None, content_length=None,
            error_code=_error_code(exc), error_detail=_error_detail(exc),
        )
    status = int(response.status_code)
    ok = 200 <= status < 300
    return AssetProbe(
        name=spec.name,
        url=spec.url,
        required=spec.required,
        status_code=status,
        etag=_header(response.headers, "etag"),
        last_modified=_header(response.headers, "last-modified"),
        content_length=_header(response.headers, "content-length"),
        error_code=None if ok else f"http_{status}",
        error_detail=None if ok else f"asset status {status}",
    )


def fingerprint_assets(assets: Iterable[AssetProbe]) -> str:
    """Return a stable content generation from file metadata.

    ``date`` is deliberately absent. Response dates change on every probe,
    while the ETag, Last-Modified and length change when a file is regenerated.
    The status stays in, so an optional file appearing (the playoffs) or a
    required one vanishing starts a refresh.
    """
    values = [
        {
            "name": asset.name,
            "url": asset.url,
            "required": asset.required,
            "status_code": asset.status_code,
            "etag": asset.etag,
            "last_modified": asset.last_modified,
            "content_length": asset.content_length,
        }
        for asset in sorted(assets, key=lambda item: item.name)
    ]
    encoded = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def probe_sources(
    season: int,
    *,
    client: HTTPClient | None = None,
    checked_at: datetime | None = None,
) -> SourceProbeResult:
    """Probe all current-season files and return a JSON-safe result."""
    http = client or UrllibHTTPClient()
    assets = tuple(probe_asset(http, spec) for spec in current_asset_specs(season))
    required_failures = [asset for asset in assets if asset.required and not asset.available]
    source_times = [asset.source_published_at for asset in assets if asset.source_published_at]
    return SourceProbeResult(
        season=season,
        checked_at=(checked_at or datetime.now(UTC)).astimezone(UTC).isoformat(),
        assets=assets,
        fingerprint=fingerprint_assets(assets),
        source_published_at=max(source_times).isoformat() if source_times else None,
        ready=not required_failures,
        error_code=required_failures[0].error_code if required_failures else None,
        error_detail=required_failures[0].error_detail if required_failures else None,
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
            raise RuntimeError("Scheduled probe requires Supabase credentials")
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
    if urlparse(base_url).hostname != PROJECT_HOST:
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
