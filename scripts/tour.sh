#!/usr/bin/env bash
# Visual QA tour: runs StatScoutTourUITests on a leased simulator and exports
# every screenshot attachment, numbered in tour order, into build/tour/.
#
# Usage:
#   scripts/tour.sh <simulator-udid> [<test-name>]
#
# Pass a test such as testT03StatsAdvanced to re-run one section; its frames
# replace that section's files and the rest are kept.
set -euo pipefail

UDID="${1:?usage: tour.sh <simulator-udid> [<test-name>]}"
ONLY="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/tour"
RESULT="$ROOT/build/tour-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
STAGE="$(mktemp -d)"
STATUS=0
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$OUT"
cd "$ROOT"

# A hung element query can stall a run for the whole test timeout; cap the build
# so whatever was captured before the stall is still exported below.
perl -e 'alarm 1200; exec @ARGV' xcodebuild test \
    -project StatScout.xcodeproj \
    -scheme StatScoutUITests \
    -destination "id=$UDID" \
    -derivedDataPath "$ROOT/build/DerivedData-ui" \
    -resultBundlePath "$RESULT" \
    -only-testing:"StatScoutUITests/StatScoutTourUITests${ONLY:+/$ONLY}" \
    SUPABASE_URL="${SUPABASE_URL:-}" \
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
    || STATUS=$?

[[ -d "$RESULT" ]] || { echo "xcodebuild did not create a result bundle" >&2; exit "${STATUS:-1}"; }

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$STAGE"

python3 - "$STAGE" "$OUT" <<'PY'
import json
import pathlib
import re
import shutil
import sys

stage = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
manifest = json.loads((stage / "manifest.json").read_text())
copied = []
for entry in manifest:
    for attachment in entry.get("attachments", []):
        source = stage / attachment.get("exportedFileName", "")
        stem = pathlib.Path(attachment.get("suggestedHumanReadableName", "")).stem
        match = re.match(r"^(\d\d)-(\d\d)_(.+?)(?:_\d+_[0-9A-F-]{36})?$", stem)
        if not source.exists() or source.suffix.lower() != ".png" or not match:
            continue
        section, step, name = match.groups()
        for old in out.glob(f"{section}-{step}_*.png"):
            old.unlink()
        destination = out / f"{section}-{step}_{name}.png"
        shutil.copyfile(source, destination)
        copied.append(destination.name)
print(f"wrote {len(copied)} tour screens to {out}")
PY
exit "$STATUS"
