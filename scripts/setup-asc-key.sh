#!/bin/bash
# Guide for setting up App Store Connect API Key
# Run this to check your setup and get instructions.
set -e

CREDS="$HOME/.hockey_credentials"
KEY_DIR="$HOME/.appstoreconnect"

source "$CREDS" 2>/dev/null || true

echo "=== App Store Connect API Key Setup Check ==="
echo ""

if [ -z "$ASC_ISSUER_ID" ] || [ -z "$ASC_API_KEY_ID" ]; then
  echo "❌  ASC_ISSUER_ID and/or ASC_API_KEY_ID are not set."
  echo ""
  echo "To set them up:"
  echo ""
  echo "  1. Go to https://appstoreconnect.apple.com/access/api"
  echo "  2. Click the '+' button next to 'Keys'"
  echo "  3. Name: StatScout CI"
  echo "  4. Role: App Manager"
  echo "  5. Download the .p8 file — you only get this once"
  echo ""
  echo "  6. Move the key file:"
  echo "     mkdir -p $KEY_DIR"
  echo "     mv ~/Downloads/AuthKey_<ID>.p8 $KEY_DIR/"
  echo ""
  echo "  7. Edit $CREDS and fill in:"
  echo "     ASC_ISSUER_ID=<your-issuer-id>"
  echo "     ASC_API_KEY_ID=<your-key-id>"
  echo "     ASC_KEY_PATH=\"\$HOME/.appstoreconnect/AuthKey_<ID>.p8\""
  echo ""
  exit 1
else
  echo "✓  ASC_ISSUER_ID is set"
  echo "✓  ASC_API_KEY_ID is set"
fi

if [ -f "$ASC_KEY_PATH" ]; then
  echo "✓  ASC_KEY_PATH points to existing file"
  echo ""
  echo "Ready to run: bundle exec fastlane upload_metadata"
else
  echo "❌  ASC_KEY_PATH file not found at: $ASC_KEY_PATH"
  echo ""
  echo "Copy your .p8 key file to that path, then run this check again."
  exit 1
fi
