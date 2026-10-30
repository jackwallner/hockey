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


# TestFlight release for StatScout. The shared fleet script does the work: bump the
# build in project.yml, xcodegen, archive Release signed with the App Store
# Connect API key, upload, then commit and push the bump once Apple accepts it.
# Flags (--upload-only, --no-bump, --clean, --post-archive) and credentials are
# documented in ~/ios/release/testflight.sh. --local: the Supabase keys must never
# reach GitHub's public runner logs, and GitHub cannot build without them.
exec "$HOME/ios/release/testflight.sh" --project StatScout.xcodeproj --scheme StatScout --clean --local "$@"
