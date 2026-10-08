#!/bin/bash
# Resize screenshots to Apple App Store Connect dimensions
# Valid sizes: 1242×2688, 2688×1242, 1284×2778, 2778×1284
#
# Usage: ./scripts/resize_screenshots.sh [input_dir] [output_dir]
#   input_dir:  directory with source screenshots (default: current dir)
#   output_dir: directory for resized images (default: Screenshots/)

set -e

INPUT_DIR="${1:-.}"
OUTPUT_DIR="${2:-Screenshots}"

# Target dimensions (iPhone 16 Pro Max)
TARGET_W=1284
TARGET_H=2778

mkdir -p "$OUTPUT_DIR"

# Find and resize PNG screenshots
find "$INPUT_DIR" -maxdepth 1 -type f \( -iname "IMG*.PNG" -o -iname "IMG*.png" -o -iname "Simulator*.png" -o -iname "Screenshot*.png" \) | while read -r file; do
    filename=$(basename "$file" .PNG)
    filename=${filename%.png}
    echo "Resizing: $file → $OUTPUT_DIR/${filename}.png"
    sips -z "$TARGET_H" "$TARGET_W" "$file" --out "$OUTPUT_DIR/${filename}.png"
done

echo "Done. Resized screenshots saved to $OUTPUT_DIR/"
