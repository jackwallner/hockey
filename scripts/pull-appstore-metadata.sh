#!/bin/bash
# Pull current metadata from App Store Connect into ./fastlane/metadata/.
# Run this BEFORE editing locally so subsequent `upload-appstore-metadata.sh`
# pushes don't clobber ASC web-UI edits. Snapshots prior state into
# ./fastlane/metadata.bak.<timestamp>/ so you can diff/restore.
# Skips screenshots (use the upload script to push those).
set -e
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.hockey_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH must be set" >&2
  echo "       see ~/.hockey_credentials" >&2
  exit 1
fi

if [[ ! -d fastlane ]]; then
  echo "error: fastlane/ not configured in $(pwd)" >&2
  exit 1
fi

# Snapshot existing metadata so the user has an undo path.
if [[ -d fastlane/metadata ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BAK="fastlane/metadata.bak.$STAMP"
  cp -R fastlane/metadata "$BAK"
  echo "snapshot: $BAK"
fi

# Build a temp JSON API key file in the format `fastlane deliver` expects.
TMPKEY="$(mktemp -t asc_api_key.XXXXXX.json)"
trap 'rm -f "$TMPKEY"' EXIT
P8_CONTENTS="$(cat "$ASC_KEY_PATH")"
python3 - "$ASC_API_KEY_ID" "$ASC_ISSUER_ID" "$P8_CONTENTS" "$TMPKEY" <<'PY'
import json, sys
key_id, issuer_id, p8, out = sys.argv[1:5]
json.dump({"key_id": key_id, "issuer_id": issuer_id, "key": p8, "in_house": False}, open(out, "w"))
PY

DELIVER_EXTRA=()
if [[ -n "${ASC_APP_VERSION:-}" ]]; then
  DELIVER_EXTRA+=(--app_version "$ASC_APP_VERSION")
fi

FL="$(dirname "$0")/fastlane-bin.sh"
chmod +x "$FL"
if [[ -x "$FL" ]] || command -v fastlane >/dev/null; then
  exec "$FL" deliver download_metadata \
    --api_key_path "$TMPKEY" \
    --metadata_path ./fastlane/metadata \
    --force true \
    --skip_screenshots true \
    "${DELIVER_EXTRA[@]}" \
    "$@"
else
  echo "error: fastlane not installed (brew install fastlane)" >&2
  exit 1
fi
