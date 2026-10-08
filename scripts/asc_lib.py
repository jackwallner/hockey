"""Shared App Store Connect API helpers for ASO scripts."""
from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError:
    jwt = None  # type: ignore

API = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
STATE_FILE = Path(__file__).parent / ".asc-state.json"

EDITABLE_STATES = frozenset(
    {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
    }
)


def load_credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("ASC_API_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    key_path = os.environ.get("ASC_KEY_PATH")
    if not all([key_id, issuer_id, key_path]):
        creds_path = Path.home() / ".hockey_credentials"
        if creds_path.exists():
            for line in creds_path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
        key_id = os.environ.get("ASC_API_KEY_ID")
        issuer_id = os.environ.get("ASC_ISSUER_ID")
        key_path = os.environ.get("ASC_KEY_PATH")
    if not all([key_id, issuer_id, key_path]):
        raise SystemExit("error: set ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH")
    return key_id, issuer_id, key_path


def bearer_token(key_id: str, issuer_id: str, key_path: str) -> str:
    if jwt is None:
        raise SystemExit("error: pip install PyJWT cryptography")
    iat = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": iat, "exp": iat + 1200, "aud": "appstoreconnect-v1"},
        open(key_path).read(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class ASCClient:
    def __init__(self, token: str):
        self.token = token

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        url = f"{API}{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            err = e.read().decode()
            raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e

    def get(self, path: str) -> dict:
        return self.request("GET", path)

    def post(self, path: str, body: dict) -> dict:
        return self.request("POST", path, body)

    def patch(self, path: str, body: dict) -> dict:
        return self.request("PATCH", path, body)


def list_all(client: ASCClient, path: str) -> list[dict]:
    items: list[dict] = []
    url_path = path
    while url_path:
        data = client.get(url_path)
        items.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        url_path = next_url.replace(API, "") if next_url else ""
    return items


def bundle_id_from_appfile() -> str:
    appfile = ROOT / "fastlane/Appfile"
    if appfile.exists():
        for line in appfile.read_text().splitlines():
            if "app_identifier" in line:
                return line.split('"')[1]
    raise SystemExit("error: could not read app_identifier from fastlane/Appfile")


def find_app(client: ASCClient, bundle_id: str) -> dict:
    bid = urllib.parse.quote(bundle_id, safe="")
    data = client.get(f"/apps?filter[bundleId]={bid}")
    apps = data.get("data", [])
    if not apps:
        raise SystemExit(f"error: no app for bundle id {bundle_id}")
    return apps[0]


def list_versions(client: ASCClient, app_id: str) -> list[dict]:
    return list_all(client, f"/apps/{app_id}/appStoreVersions")


def find_version_by_string(client: ASCClient, app_id: str, version_string: str) -> dict | None:
    for v in list_versions(client, app_id):
        if v.get("attributes", {}).get("versionString") == version_string:
            return v
    return None


def find_editable_version(client: ASCClient, app_id: str) -> dict | None:
    for state in EDITABLE_STATES:
        for v in list_versions(client, app_id):
            if v.get("attributes", {}).get("appStoreState") == state:
                return v
    return None


def find_editable_app_info(client: ASCClient, app_id: str) -> dict | None:
    """Prefer PREPARE_FOR_SUBMISSION appInfo (created by deliver 2.234+ on draft versions)."""
    infos = list_all(client, f"/apps/{app_id}/appInfos")
    if not infos:
        return None
    for state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED"):
        for info in infos:
            if info.get("attributes", {}).get("appStoreState") == state:
                return info
    return infos[0]


def find_live_version(client: ASCClient, app_id: str) -> dict | None:
    live = [v for v in list_versions(client, app_id) if v.get("attributes", {}).get("appStoreState") == "READY_FOR_SALE"]
    if not live:
        return None
    return sorted(live, key=lambda x: x["attributes"].get("versionString", ""), reverse=True)[0]


def bump_version(version_string: str) -> str:
    parts = version_string.split(".")
    while len(parts) < 3:
        parts.append("0")
    try:
        parts[-1] = str(int(parts[-1]) + 1)
    except ValueError:
        parts.append("1")
    return ".".join(parts)


def create_draft_version(client: ASCClient, app_id: str, version_string: str) -> dict:
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version_string},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    return client.post("/appStoreVersions", body)["data"]


def ensure_draft_version(client: ASCClient, app_id: str, preferred: str | None = None) -> dict:
    editable = find_editable_version(client, app_id)
    if editable:
        return editable
    live = find_live_version(client, app_id)
    base = preferred or (live["attributes"]["versionString"] if live else "1.0.0")
    candidate = bump_version(base)
    for _ in range(8):
        if find_version_by_string(client, app_id, candidate):
            candidate = bump_version(candidate)
            continue
        try:
            return create_draft_version(client, app_id, candidate)
        except RuntimeError as e:
            if "already been used" in str(e) or "ENTITY_ERROR" in str(e):
                candidate = bump_version(candidate)
                continue
            raise
    raise SystemExit("error: could not create a new draft ASC version")


def save_state(draft_version: str, live_version: str | None, app_id: str) -> None:
    STATE_FILE.write_text(
        json.dumps(
            {
                "appId": app_id,
                "draftVersion": draft_version,
                "liveVersion": live_version,
                "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
            indent=2,
        )
        + "\n"
    )


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def read_meta(locale: str, field: str) -> str:
    p = META / locale / f"{field}.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def fastlane_locale_dirs() -> list[str]:
    skip = {"review_information"}
    return sorted(
        d.name
        for d in META.iterdir()
        if d.is_dir() and d.name not in skip and not d.name.endswith(".txt")
    )


def description_for_locale(locale: str, source: str = "en-US") -> str:
    desc = read_meta(locale, "description") or read_meta(source, "description")
    if len(desc) < 10:
        desc = (
            read_meta("en-US", "description")
            or "One Tap Headache Tracker — migraine and headache diary with Apple Watch logging."
        )
    return desc[:4000]
