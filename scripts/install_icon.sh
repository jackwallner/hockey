#!/usr/bin/env bash
# Install a chosen 1024x1024 icon into the app's asset catalog.
# Usage: scripts/install_icon.sh claude-design/icon/output/concept_b_cream.png
set -euo pipefail

SRC="${1:?usage: scripts/install_icon.sh <path-to-1024-png>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO/StatScout/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

[ -f "$SRC" ] || { echo "no such file: $SRC" >&2; exit 1; }

dims=$(sips -g pixelWidth -g pixelHeight "$SRC" | awk '/pixel/ {print $2}' | paste -sd x -)
[ "$dims" = "1024x1024" ] || { echo "expected 1024x1024, got $dims" >&2; exit 1; }

# App Store rejects icons with an alpha channel; flatten onto white and strip it.
tmp="$(mktemp -d)"
sips -s format png --setProperty formatOptions best "$SRC" --out "$tmp/flat.png" >/dev/null
python3 - "$tmp/flat.png" "$DEST" <<'PY'
import sys
from PIL import Image

src, dest = sys.argv[1], sys.argv[2]
img = Image.open(src)
if img.mode in ("RGBA", "LA", "P"):
    img = img.convert("RGBA")
    bg = Image.new("RGB", img.size, (255, 255, 255))
    bg.paste(img, mask=img.split()[-1])
    img = bg
else:
    img = img.convert("RGB")
img.save(dest, "PNG")
PY
rm -rf "$tmp"

echo "installed $SRC -> $DEST"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$DEST"
echo "next: xcodegen generate && source ~/.hockey_credentials && bash scripts/testflight.sh"
