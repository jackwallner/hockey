#!/bin/bash
# Build a signed bundle and upload with fastlane's official Play API client.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-validate}"
credential="${PLAY_SERVICE_ACCOUNT_JSON:-}"
if [[ ! -f "$credential" ]]; then
  echo "Set PLAY_SERVICE_ACCOUNT_JSON to the private service-account JSON outside git." >&2
  exit 1
fi

case "$mode" in
  validate) track=internal; status=draft; validate=true ;;
  internal) track=internal; status=completed; validate=false ;;
  internal-draft) track=internal; status=draft; validate=false ;;
  production-draft) track=production; status=draft; validate=false ;;
  *) echo "Usage: $0 [validate|internal|internal-draft|production-draft]" >&2; exit 2 ;;
esac

package="$(python3 - "$repo/android/app/build.gradle.kts" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
match = re.search(r'applicationId\s*=\s*"([^"]+)"', text)
if not match:
    raise SystemExit("Cannot read applicationId from Gradle.")
print(match.group(1))
PY
)"

echo "Building and testing $package for Play $track ($status)."
"$repo/android/gradlew" -p "$repo/android" testDebugUnitTest bundleRelease --max-workers=2
bundle="$repo/android/app/build/outputs/bundle/release/app-release.aab"
signature_log="$(mktemp)"
trap 'rm -f "$signature_log"' EXIT
jarsigner -verify "$bundle" > "$signature_log" 2>&1
if ! grep -q 'jar verified' "$signature_log"; then
  echo "Bundle signature verification failed." >&2
  exit 1
fi

echo "Sending signed bundle to Google Play ($mode)."
FASTLANE_SKIP_UPDATE_CHECK=1 "$repo/scripts/fastlane-bin.sh" supply \
  --json_key "$credential" \
  --package_name "$package" \
  --aab "$bundle" \
  --track "$track" \
  --release_status "$status" \
  --validate_only "$validate" \
  --skip_upload_metadata true \
  --skip_upload_changelogs true \
  --skip_upload_images true \
  --skip_upload_screenshots true \
  --rescue_changes_not_sent_for_review false
