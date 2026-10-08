#!/usr/bin/env python3
"""Minimal App Store Connect API helper: generates a JWT and makes requests.

Usage: asc_api.py <METHOD> <path-or-url> [json-body]
Requires env ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (see ~/.hockey_credentials).
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

import jwt  # pyjwt

KEY_ID = os.environ["ASC_API_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.path.expandvars(os.environ["ASC_KEY_PATH"])
BASE = "https://api.appstoreconnect.apple.com"


def token() -> str:
    with open(KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})


def request(method: str, path: str, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    req.add_header("Content-Type", "application/json")
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


if __name__ == "__main__":
    method, path = sys.argv[1].upper(), sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    status, resp = request(method, path, body)
    print(status)
    print(json.dumps(resp, indent=2))
