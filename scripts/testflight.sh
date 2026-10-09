#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="StatScout"
ARCHIVE_PATH="$PROJECT_DIR/build/StatScout.xcarchive"

cd "$PROJECT_DIR"

# Supabase config is injected into Info.plist at build time from the environment
# (project.yml: SUPABASE_URL/SUPABASE_ANON_KEY = $(...)). If these aren't set the
# archive bakes in empty/garbage values and the shipped app can't reach the
# backend. Auto-source the canonical creds file, then hard-fail if still missing.
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  [ -f "$HOME/.hockey_credentials" ] && source "$HOME/.hockey_credentials"
fi
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "error: SUPABASE_URL / SUPABASE_ANON_KEY not set and not found in ~/.hockey_credentials." >&2
  echo "       Set them in the environment or that file before shipping." >&2
  exit 1
fi
# Hockey has its own Supabase account, separate from the other StatScout apps.
# A stale `source ~/.hockey_credentials` in the shell would otherwise bake the
# wrong project into the archive and ship an app pointed at baseball data, which
# fails silently (valid host, valid key, zero NFL rows). Pin the project ref.
FOOTBALL_PROJECT_REF="swlalptdamfccgjmpbyb"
case "$SUPABASE_URL" in
  *"$FOOTBALL_PROJECT_REF"*) ;;
  *)
    echo "error: SUPABASE_URL does not point at the Hockey project ($FOOTBALL_PROJECT_REF)." >&2
    echo "       Got: $SUPABASE_URL" >&2
    echo "       Run: source ~/.hockey_credentials && bash scripts/testflight.sh" >&2
    exit 1
    ;;
esac
export SUPABASE_URL SUPABASE_ANON_KEY

# Auto-increment build number so TestFlight never rejects a duplicate
echo "==> Bumping build number..."
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *"\(.*\)".*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
echo "    $CURRENT_BUILD -> $NEXT_BUILD"

echo "==> Regenerating Xcode project..."
if command -v xcodegen &> /dev/null; then
  xcodegen generate
else
  echo "warning: xcodegen not found. Using existing StatScout.xcodeproj."
fi

echo "==> Cleaning..."
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" clean

# Sign with the ASC API key when available, not Xcode's Apple ID session.
AUTH=()
if [ -n "$ASC_KEY_PATH" ] && [ -n "$ASC_API_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_API_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  export ASC_KEY_PATH ASC_API_KEY_ID ASC_ISSUER_ID
fi

echo "==> Archiving..."
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" -configuration Release archive -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo "==> Exporting & Uploading..."
exec "$DIR/upload-testflight.sh" "$ARCHIVE_PATH"
