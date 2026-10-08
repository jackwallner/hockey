#!/usr/bin/env bash
# Capture the product-only Football 1.2 screenshot set from the real app.
#
# Usage:
#   scripts/capture-v1.2-screenshots.sh <simulator-udid> <output-dir>
#
# The same adapter works for the iPhone App Store set and an iPad proof run.
# The manifest owns the expected raw dimensions, while the test owns only real
# app navigation and screenshots. Runs are headless and never open Simulator.app.
set -euo pipefail

UDID="${1:?usage: capture-v1.2-screenshots.sh <simulator-udid> <output-dir>}"
OUT="${2:?usage: capture-v1.2-screenshots.sh <simulator-udid> <output-dir>}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT="$ROOT/build/screenshots-v1.2-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
STAGE="$(mktemp -d)"
STATUS=0

cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$ROOT/build" "$OUT"
find "$OUT" -maxdepth 1 -type f -name '0[1-7]_*.png' -delete
# Keep the fan context stable even if the app fixture hook is being iterated.
# These are fictional fixture IDs and local simulator defaults only.
xcrun simctl spawn "$UDID" defaults write com.jackwallner.football favorites.playerIds -array 12001 12007 12011
xcrun simctl spawn "$UDID" defaults write com.jackwallner.football favorites.team KC
xcrun simctl spawn "$UDID" defaults write com.jackwallner.football hasCompletedOnboarding -bool YES

cd "$ROOT"
VERSION="$(awk '/MARKETING_VERSION/ {gsub(/[":]/, "", $2); print $2; exit}' project.yml)"

# Export whatever completed before a UI assertion fails. The shell still returns
# the test status, making a partial run useful during iteration but unsafe as a
# canonical capture.
xcodebuild test \
    -project StatScout.xcodeproj \
    -scheme StatScoutUITests \
    -destination "id=$UDID" \
    -derivedDataPath "$ROOT/build/DerivedData12" \
    -resultBundlePath "$RESULT" \
    -only-testing:StatScoutUITests/StatScoutV12ScreenshotUITests \
    TEST_RUNNER_SCREENSHOT_APP_VERSION="$VERSION" \
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

if [[ "$STATUS" -ne 0 ]]; then
    echo "screenshot UI tests failed; partial captures remain in $OUT" >&2
    exit "$STATUS"
fi
