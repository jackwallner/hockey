#!/usr/bin/env bash
# Capture the App Review screenshot for the in-app purchases.
#
# Usage:
#   scripts/capture-paywall-review.sh <simulator-udid> [<output.png>]
#
# Runs StatScoutPaywallReviewUITests (the real paywall, yearly plan selected,
# priced from StatScout.storekit) and exports its XCTAttachment to
# <output.png>, default build/paywall-review.png, at the device's native size.
# Headless: never opens Simulator.app.
set -euo pipefail

UDID="${1:?usage: capture-paywall-review.sh <simulator-udid> [<output.png>]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${2:-$ROOT/build/paywall-review.png}"
RESULT="$ROOT/build/paywall-review-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$ROOT/build" "$(dirname "$OUT")"
cd "$ROOT"

xcodebuild test \
    -project StatScout.xcodeproj \
    -scheme StatScoutUITests \
    -destination "id=$UDID" \
    -derivedDataPath "$ROOT/build/DerivedData-ui" \
    -resultBundlePath "$RESULT" \
    -only-testing:StatScoutUITests/StatScoutPaywallReviewUITests \
    SUPABASE_URL="${SUPABASE_URL:-}" \
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$STAGE"

python3 -I - "$STAGE" "$OUT" <<'PY'
import json
import pathlib
import shutil
import sys

stage = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
manifest = json.loads((stage / "manifest.json").read_text())
for entry in manifest:
    for attachment in entry.get("attachments", []):
        if attachment.get("suggestedHumanReadableName", "").startswith("paywall-review"):
            shutil.copyfile(stage / attachment["exportedFileName"], out)
            print(f"wrote {out}")
            raise SystemExit(0)
raise SystemExit("paywall-review attachment not found")
PY
