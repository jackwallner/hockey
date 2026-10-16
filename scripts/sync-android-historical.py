#!/usr/bin/env python3
"""Write the Android copy of the bundled historical players.

Reads StatScout/Data/players-historical.json (the same export the iOS plist is
built from, see scripts/export_historical.py) and writes a compact gzip JSON
array to android/app/src/main/assets/players-historical.bin. Fields the app
never reads (refresh and publish stamps, empty games, per-metric ids) are
dropped; the Kotlin decoder derives ids. Rerun after every
export_historical.py run.
"""
from __future__ import annotations

import gzip
import json
import pathlib
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "StatScout" / "Data" / "players-historical.json"
TARGET = ROOT / "android" / "app" / "src" / "main" / "assets" / "players-historical.bin"


def compact(player: dict[str, Any]) -> dict[str, Any]:
    out = {k: player[k] for k in ("id", "name", "team", "position", "handedness", "updated_at") if k in player}
    for key in ("season", "season_type", "player_type", "source"):
        if player.get(key) is not None:
            out[key] = player[key]
    out["metrics"] = [
        {k: m[k] for k in ("label", "value", "category", "percentile", "qualified", "rankable") if m.get(k) is not None}
        for m in player.get("metrics", [])
    ]
    if player.get("standard_stats") is not None:
        out["standard_stats"] = [{"label": s["label"], "value": s["value"]} for s in player["standard_stats"]]
    if player.get("games"):
        out["games"] = player["games"]
    return out


def main() -> None:
    players = json.loads(SOURCE.read_text())
    rows = [compact(p) for p in players]
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode()
    with gzip.GzipFile(TARGET, "wb", compresslevel=9, mtime=0) as fh:
        fh.write(payload)
    print(f"{len(rows)} players, {len(payload) / 1e6:.1f} MB JSON, {TARGET.stat().st_size / 1e6:.1f} MB gzip -> {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
