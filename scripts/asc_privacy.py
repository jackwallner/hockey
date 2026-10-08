#!/usr/bin/env python3
"""App Privacy (data usage) answers, which the public ASC API does not expose.

The "Data Collection" questionnaire lives on App Store Connect's internal *iris*
host rather than on `api.appstoreconnect.apple.com`, which is why every
`/v1/apps/<id>/appDataUsages` path against the public base returns
`PATH_ERROR`. fastlane reaches it through `Spaceship::ConnectAPI::Tunes`; this
does the same thing with the same ASC API key, so a submission is not blocked on
"Answers to what data your app collects and how it's used are needed."

Usage:
  asc_privacy.py show <app_id>              # current answers + publish state
  asc_privacy.py options                    # category / purpose / protection ids
  asc_privacy.py copy <from_app> <to_app>   # mirror another app's answers
  asc_privacy.py publish <app_id>           # mark the answers published

Auth: iris does *not* accept an ASC API key - it answers 401 NOT_AUTHORIZED for a
perfectly valid team JWT, which is why `fastlane deliver` reports "You must have
published answers to your app's data usages" and cannot fix it itself. It needs a
web session cookie:

    fastlane spaceauth -u <apple-id>     # prints an export line, needs a 2FA code
    export FASTLANE_SESSION='...'        # paste it
    python3 scripts/asc_privacy.py copy 6763945657 6792930447   # baseball -> football
    python3 scripts/asc_privacy.py publish 6792930447

Falls back to the API key when FASTLANE_SESSION is unset, which is enough for
nothing on iris but keeps the failure legible.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # pyjwt

BASE = "https://appstoreconnect.apple.com/iris"
SESSION = os.environ.get("FASTLANE_SESSION", "")


def token() -> str:
    key_id = os.environ["ASC_API_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    key_path = os.path.expandvars(os.environ["ASC_KEY_PATH"])
    with open(key_path) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def cookie_header() -> str:
    """`fastlane spaceauth` emits a Ruby YAML dump of the cookie jar. Only the
    name/value pairs matter to us, so pull them out rather than parsing YAML."""
    pairs = re.findall(r"name:\s*(\S+)\s*\n\s*value:\s*(\S+)", SESSION)
    if not pairs:
        pairs = re.findall(r"(myacinfo|DES\w+|dqsid|itctx|woinst|wosid)=([^;\s]+)", SESSION)
    return "; ".join(f"{n}={v}" for n, v in pairs)


def request(method: str, path: str, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if SESSION:
        req.add_header("Cookie", cookie_header())
    else:
        req.add_header("Authorization", f"Bearer {token()}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    # iris has required this on most routes since July 2021; spaceship sends the
    # same literal.
    req.add_header("x-csrf-itc", "[asc-ui]")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def usages(app_id: str):
    status, resp = request(
        "GET",
        f"/v1/apps/{app_id}/dataUsages?limit=200"
        "&include=category,purposes,dataProtections",
    )
    if status != 200:
        raise SystemExit(f"dataUsages failed ({status}): {json.dumps(resp)[:600]}")
    return resp


def publish_state(app_id: str):
    status, resp = request("GET", f"/v1/apps/{app_id}/dataUsagesPublishState")
    if status != 200:
        raise SystemExit(f"publish state failed ({status}): {json.dumps(resp)[:600]}")
    return resp


def triples(payload) -> set:
    """Each answer is a (category, purpose, protection) triple; ids are stable
    strings like `DATA_NOT_COLLECTED`, so they copy between apps verbatim."""
    out = set()
    for row in payload.get("data", []):
        rel = row.get("relationships", {})

        def one(name):
            d = rel.get(name, {}).get("data")
            if isinstance(d, list):
                return d[0]["id"] if d else None
            return d["id"] if d else None

        out.add((one("category"), one("purpose"), one("dataProtection")))
    return out


def post_usage(app_id, category, purpose, protection):
    rel = {"app": {"data": {"type": "apps", "id": app_id}}}
    if category:
        rel["category"] = {"data": {"type": "appDataUsageCategories", "id": category}}
    if purpose:
        rel["purpose"] = {"data": {"type": "appDataUsagePurposes", "id": purpose}}
    if protection:
        rel["dataProtection"] = {
            "data": {"type": "appDataUsageDataProtections", "id": protection}
        }
    return request(
        "POST", "/v1/appDataUsages", {"data": {"type": "appDataUsages", "relationships": rel}}
    )


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cmd = sys.argv[1]

    if cmd == "show":
        app = sys.argv[2]
        payload = usages(app)
        for t in sorted(triples(payload), key=lambda x: tuple(v or "" for v in x)):
            print("  ", t)
        print("publish:", json.dumps(publish_state(app).get("data", {}).get("attributes")))

    elif cmd == "options":
        for path, label in [
            ("/v1/appDataUsageCategories?limit=200", "CATEGORIES"),
            ("/v1/appDataUsagePurposes?limit=200", "PURPOSES"),
            ("/v1/appDataUsageDataProtections?limit=200", "PROTECTIONS"),
        ]:
            status, resp = request("GET", path)
            print(f"--- {label} ({status})")
            for row in resp.get("data", []):
                print("  ", row["id"], row.get("attributes", {}))

    elif cmd == "copy":
        src, dst = sys.argv[2], sys.argv[3]
        want = triples(usages(src))
        have = triples(usages(dst))
        print(f"source has {len(want)} answers, target has {len(have)}")
        for t in sorted(want - have, key=lambda x: tuple(v or "" for v in x)):
            status, resp = post_usage(dst, *t)
            print(status, t, "" if status < 300 else json.dumps(resp)[:300])

    elif cmd == "publish":
        app = sys.argv[2]
        state = publish_state(app)["data"]
        status, resp = request(
            "PATCH",
            f"/v1/appDataUsagesPublishState/{state['id']}",
            {
                "data": {
                    "type": "appDataUsagesPublishState",
                    "id": state["id"],
                    "attributes": {"published": True},
                }
            },
        )
        print(status, json.dumps(resp)[:400])

    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
