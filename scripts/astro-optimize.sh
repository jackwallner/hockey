#!/bin/bash
# Re-sync optimized keywords + print pop/diff/rank report.
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH=scripts
STORE="${ASTRO_STORE:-us}"
MCP_URL="${ASTRO_MCP_URL:-http://127.0.0.1:8089/mcp}"
APP_ID="$(python3 -c "import json; print(json.load(open('scripts/.astro-app.json'))['appId'])")"

python3 <<PY
import json, time
from pathlib import Path
from astro_mcp import add_keywords, call

mcp = "$MCP_URL"
app_id = "$APP_ID"
store = "$STORE"
data = json.loads(Path("scripts/astro-keywords-us.json").read_text())
keywords = data["keywords"]

for i in range(0, len(keywords), 25):
    batch = keywords[i : i + 25]
    r = call(mcp, "add_keywords", {"appId": app_id, "store": store, "keywords": batch}, req_id=200 + i, timeout=60)
    print(f"Batch {i//25+1}: added={r.get('added')} skipped={r.get('skipped')}")
    time.sleep(1.5)

kws = call(mcp, "get_app_keywords", {"appId": app_id, "store": store})
for k in kws:
    pop = k.get("popularity", 0) or 0
    diff = k.get("difficulty", 50) or 50
    rank = k.get("currentRanking", 1000)
    k["_ratio"] = pop / max(diff, 1)
    k["_tier"] = "A" if rank < 100 else "B" if rank < 300 else "C" if rank < 1000 else "D"

ranked = sorted(kws, key=lambda x: (x["_tier"], x.get("currentRanking", 9999)))
print("\n=== TIER A/B (rank < 300) ===")
for k in [x for x in ranked if x["_tier"] in ("A", "B")]:
    print(f"  #{k['currentRanking']:4} pop={k.get('popularity',0):2} diff={k.get('difficulty',0):3} ratio={k['_ratio']:.2f} {k['keyword']}")

print("\n=== TIER C (100-999) high pop/diff opportunity ===")
c = sorted([x for x in ranked if x["_tier"] == "C"], key=lambda x: -x["_ratio"])[:12]
for k in c:
    print(f"  #{k['currentRanking']:4} pop={k.get('popularity',0):2} diff={k.get('difficulty',0):3} ratio={k['_ratio']:.2f} {k['keyword']}")

print("\n=== TIER D stuck @1000 — top pop/diff to watch ===")
d = sorted([x for x in ranked if x["_tier"] == "D"], key=lambda x: -x["_ratio"])[:15]
for k in d:
    print(f"  pop={k.get('popularity',0):2} diff={k.get('difficulty',0):3} ratio={k['_ratio']:.2f} {k['keyword']}")

print(f"\nTotal tracked: {len(kws)}")
PY
