#!/bin/bash
# Push screenshots + metadata to App Store Connect via fastlane 2.234+ (Deliverfile languages).
set -e
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.hockey_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH must be set" >&2
  exit 1
fi

if [[ -z "${ASC_APP_VERSION:-}" ]]; then
  echo "==> Resolving draft ASC version"
  eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
fi

FL="$(dirname "$0")/fastlane-bin.sh"
chmod +x "$FL"
exec "$FL" upload_metadata "$@"
