#!/bin/bash
# Verify all 91 Astro stores have keywords; sync any that don't.
set -uo pipefail
cd "$(dirname "$0")/.."
export PYTHONUNBUFFERED=1
LOG="scripts/astro-verify.log"

log() { echo "$(date -u +%H:%M:%S) $1" | tee -a "$LOG"; }

until python3 -c "import sys; sys.path.insert(0,'scripts'); from astro_mcp import ping; exit(0 if ping() else 1)"; do
  log "waiting for Astro MCP..."
  sleep 15
done

log "MCP up — auditing 91 stores"
python3 <<'PY' | tee -a "$LOG"
import json, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, "scripts")
from astro_mcp import call, ping

app_id = "6763945657"
stores = [s["code"] for s in json.load(open("scripts/astro-stores-2026.json"))["stores"]]
need = []
for store in stores:
    for attempt in range(3):
        if not ping():
            time.sleep(10)
            continue
        try:
            kws = call("http://127.0.0.1:8089/mcp", "get_app_keywords", {"appId": app_id, "store": store}, timeout=60)
            n = len(kws) if isinstance(kws, list) else 0
            if n < 15:
                need.append(store)
            break
        except Exception:
            time.sleep(5)
    else:
        need.append(store)
    time.sleep(0.5)

print(f"need_sync={len(need)}: {','.join(need)}")
Path("/tmp/baseball-astro-need.txt").write_text("\n".join(need))
PY

while read -r store; do
  [[ -z "$store" ]] && continue
  for attempt in 1 2 3 4 5 6; do
    log "sync $store attempt $attempt"
    python3 scripts/astro-sync-all-stores.py --store "$store" >>"$LOG" 2>&1 && break
    sleep $((attempt * 5))
  done
  sleep 4
done < /tmp/baseball-astro-need.txt

log "full summary pass"
python3 scripts/astro-sync-all-stores.py >>"$LOG" 2>&1

python3 <<'PY' | tee -a "$LOG"
import json, sys, time
sys.path.insert(0, "scripts")
from astro_mcp import call
app_id = "6763945657"
stores = [s["code"] for s in json.load(open("scripts/astro-stores-2026.json"))["stores"]]
ok = low = err = 0
for store in stores:
    try:
        n = len(call("http://127.0.0.1:8089/mcp", "get_app_keywords", {"appId": app_id, "store": store}, timeout=45))
        if n >= 15: ok += 1
        else: low += 1; print(f"LOW {store}={n}")
    except Exception:
        err += 1
    time.sleep(0.3)
s = json.load(open("scripts/astro-keywords-by-store/_summary.json"))
print(f"COMPLETE ok={ok}/91 low={low} err={err} summary_storeCount={s.get('storeCount')}")
PY
log "DONE"
