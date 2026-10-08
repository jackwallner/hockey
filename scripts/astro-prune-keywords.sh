#!/bin/bash
# Remove Astro keywords not in scripts/astro-keywords-us.json (destructive).
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH=scripts
python3 <<'PY'
import json
from pathlib import Path
from astro_mcp import call, remove_keywords

config = json.loads(Path("scripts/.astro-app.json").read_text())
app_id = config["appId"]
store = config.get("store", "us")
mcp = "http://127.0.0.1:8089/mcp"

keep = set(json.loads(Path("scripts/astro-keywords-us.json").read_text())["keywords"])
kws = call(mcp, "get_app_keywords", {"appId": app_id, "store": store})
to_remove = sorted({k["keyword"] for k in kws} - keep)

if not to_remove:
    print("Nothing to prune — Astro matches astro-keywords-us.json")
    raise SystemExit(0)

print(f"Removing {len(to_remove)} keywords:")
for kw in to_remove:
    print(f"  - {kw}")

for i in range(0, len(to_remove), 50):
    batch = to_remove[i : i + 50]
    r = remove_keywords(mcp, app_id, store, batch)
    removed = r.get("removed", r.get("deleted", len(batch)))
    print(f"Batch {i//50+1}: done ({removed})")

remaining = call(mcp, "get_app_keywords", {"appId": app_id, "store": store})
print(f"Remaining: {len(remaining)} keywords")
PY
