#!/usr/bin/env bash
# Capture the product-only App Store screenshot set from the real app.
#
# Usage:
#   scripts/capture-screenshots.sh <simulator-udid> <raw-dir> [<final-dir>]
#
# Runs StatScoutScreenshotUITests against the DEBUG fixture provider (invented
# players and games, no network) and exports the eight XCTAttachment PNGs
# (01_league_leaders .. 08_standings) into <raw-dir> at the device's native
# size. With <final-dir>, each is also normalized to 1320x2868 RGB with no alpha
# channel, the iPhone 6.9" App Store size, with no text or frame added.
# Runs are headless and never open Simulator.app.
set -euo pipefail

UDID="${1:?usage: capture-screenshots.sh <simulator-udid> <raw-dir> [<final-dir>]}"
OUT="${2:?usage: capture-screenshots.sh <simulator-udid> <raw-dir> [<final-dir>]}"
FINAL="${3:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT="$ROOT/build/screenshots-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
STAGE="$(mktemp -d)"
STATUS=0

cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$ROOT/build" "$OUT"
# CAPTURE_ONLY=testCapture05GameDetail re-runs one capture and keeps the rest.
ONLY="${CAPTURE_ONLY:-}"
if [[ -z "$ONLY" ]]; then
    find "$OUT" -maxdepth 1 -type f -name '0[1-8]_*.png' -delete
fi
# Keep the fan context stable even if the app fixture hook is being iterated.
# These are fictional fixture IDs and local simulator defaults only.
xcrun simctl spawn "$UDID" defaults write com.jackwallner.hockey favorites.playerIds -array 12001 12008 12013
xcrun simctl spawn "$UDID" defaults write com.jackwallner.hockey favoriteTeam SEA
xcrun simctl spawn "$UDID" defaults write com.jackwallner.hockey hasCompletedOnboarding -bool YES

cd "$ROOT"

# Export whatever completed before a UI assertion fails. The shell still returns
# the test status, making a partial run useful during iteration but unsafe as a
# canonical capture.
xcodebuild test \
    -project StatScout.xcodeproj \
    -scheme StatScoutUITests \
    -destination "id=$UDID" \
    -derivedDataPath "$ROOT/build/DerivedData-ui" \
    -resultBundlePath "$RESULT" \
    -only-testing:"StatScoutUITests/StatScoutScreenshotUITests${ONLY:+/$ONLY}" \
    SUPABASE_URL="${SUPABASE_URL:-}" \
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
    || STATUS=$?

if [[ ! -d "$RESULT" ]]; then
    echo "xcodebuild did not create a result bundle" >&2
    exit "${STATUS:-1}"
fi

xcrun xcresulttool export attachments \
    --path "$RESULT" \
    --output-path "$STAGE"

python3 - "$STAGE" "$OUT" <<'PY'
import json
import pathlib
import shutil
import sys

stage = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
manifest_path = stage / "manifest.json"
if not manifest_path.exists():
    raise SystemExit("xcresult attachment manifest is missing")

manifest = json.loads(manifest_path.read_text())
copied = []
for entry in manifest:
    for attachment in entry.get("attachments", []):
        source_name = attachment.get("exportedFileName", "")
        suggested = attachment.get("suggestedHumanReadableName", "")
        source = stage / source_name
        if not source.exists() or source.suffix.lower() != ".png" or not suggested:
            continue
        stem = pathlib.Path(suggested).stem
        if not stem[:2].isdigit():
            continue
        # XCTest appends an attachment index and UUID to its suggested name,
        # for example 01_league_leaders_0_<uuid>. Keep the product manifest
        # stable across every run.
        if "_0_" in stem:
            stem = stem.split("_0_", 1)[0]
        destination = out / f"{stem}.png"
        shutil.copyfile(source, destination)
        copied.append(destination.name)

print(f"wrote {len(copied)} screenshots to {out}")
if copied:
    print("\n".join(sorted(copied)))
PY

if [[ -n "$FINAL" ]]; then
    mkdir -p "$FINAL"
    python3 - "$OUT" "$FINAL" <<'PY'
import pathlib
import sys

from PIL import Image

raw = pathlib.Path(sys.argv[1])
final = pathlib.Path(sys.argv[2])
for source in sorted(raw.glob("0[1-8]_*.png")):
    image = Image.open(source).convert("RGB")
    image = image.resize((1320, 2868), Image.LANCZOS)
    image.save(final / source.name, format="PNG")
    print(f"normalized {source.name} -> {final / source.name}")
PY
fi

if [[ "$STATUS" -ne 0 ]]; then
    echo "screenshot UI tests failed; partial captures remain in $OUT" >&2
    exit "$STATUS"
fi
