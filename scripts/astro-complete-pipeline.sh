#!/bin/bash
# Resume and finish astro go pipeline: sync 91 → prune → tier1 → summary
set -uo pipefail
cd "$(dirname "$0")/.."
export PYTHONUNBUFFERED=1
LOG="scripts/astro-pipeline.log"

log() { echo "$1" | tee -a "$LOG"; }

if ! python3 -c "import sys; sys.path.insert(0,'scripts'); from astro_mcp import ping; exit(0 if ping() else 1)"; then
  log "ERROR: Astro MCP not reachable — open Astro app"
  exit 1
fi

sync_store() {
  local store="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    log "==> sync $store (attempt $attempt)"
    if python3 scripts/astro-sync-all-stores.py --store "$store" >>"$LOG" 2>&1; then
      return 0
    fi
    sleep $((attempt * 5))
  done
  log "FAIL sync $store after 5 attempts"
  return 1
}

log "=== RESUME SYNC $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
python3 <<'PY' > /tmp/baseball-remaining-stores.txt
import json
from pathlib import Path
stores = [s["code"] for s in json.load(open("scripts/astro-stores-2026.json"))["stores"]]
done = {p.stem for p in Path("scripts/astro-keywords-by-store").glob("*.json") if p.stem != "_summary"}
for s in stores:
    if s not in done:
        print(s)
PY

FAILED=()
while read -r store; do
  [[ -z "$store" ]] && continue
  sync_store "$store" || FAILED+=("$store")
  sleep 3
done < /tmp/baseball-remaining-stores.txt

log "=== FULL SYNC SUMMARY PASS ==="
for attempt in 1 2 3; do
  if python3 scripts/astro-sync-all-stores.py >>"$LOG" 2>&1; then
    break
  fi
  sleep 15
done

SC=$(python3 -c "import json; print(json.load(open('scripts/astro-keywords-by-store/_summary.json')).get('storeCount',0))" 2>/dev/null || echo 0)
log "summary storeCount=$SC"

log "=== PRUNE ALL STORES ==="
./scripts/astro-prune-all-stores.sh >>"$LOG" 2>&1 || true

log "=== TIER1 SECOND PASS ==="
python3 scripts/astro-tier1-second-pass.py >>"$LOG" 2>&1 || true

log "=== ASTRO DONE $(date -u +%Y-%m-%dT%H:%M:%SZ) failed=${FAILED[*]:-none} ==="
