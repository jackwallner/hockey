#!/bin/bash
# UI Test Script - Launches simulator, tests season picker, analyzes screenshots

set -e

DEVICE_ID="5A80E4BE-5F97-49AF-B93D-E9E512E00196"
APP_BUNDLE="/Users/jackwallner/Library/Developer/Xcode/DerivedData/StatScout-bccpdbdlzemicsdkjsqzlnhwrlak/Build/Products/Debug-iphonesimulator/Baseball Savvy StatScout.app"
BUNDLE_ID="com.jackwallner.baseball"
TEST_DIR="/tmp/statscout_ui_test"
REPORT_FILE="$TEST_DIR/test_report.txt"

mkdir -p $TEST_DIR
echo "StatScout UI Test Report" > $REPORT_FILE
echo "=========================" >> $REPORT_FILE
echo "Started: $(date)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "1. Booting simulator..."
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || echo "Already booted"
sleep 3

echo "2. Installing app..."
xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE"
sleep 2

echo "3. Launching app..."
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
sleep 8

echo "4. Capturing initial screenshot..."
xcrun simctl io "$DEVICE_ID" screenshot "$TEST_DIR/01_initial.png"

# Use simctl to tap on the year picker (approximate coordinates for iPhone 17)
# The year picker should be in the top right area of the leaderboard section
echo "5. Tapping season picker..."
# Tap at coordinates where year picker should be (top right of screen, below nav bar)
xcrun simctl io "$DEVICE_ID" sendevent --type=touch --x=1000 --y=150 --pressure=1
echo "   Tapped at 1000,150"
sleep 2

# Menu should be open now - capture it
echo "6. Capturing menu open screenshot..."
xcrun simctl io "$DEVICE_ID" screenshot "$TEST_DIR/02_menu_open.png"

# Try OCR analysis
echo "7. Running OCR analysis..."
python3 << 'PYEOF'
import pytesseract
from PIL import Image
import sys

test_dir = "/tmp/statscout_ui_test"

# Check if tesseract is installed
try:
    version = pytesseract.get_tesseract_version()
    print(f"Tesseract version: {version}")
except Exception as e:
    print(f"Tesseract not available: {e}")
    print("Installing with brew...")
    import subprocess
    subprocess.run(["brew", "install", "tesseract"], check=False)
    version = pytesseract.get_tesseract_version()
    print(f"Tesseract version after install: {version}")

# Analyze initial screenshot
print("\nAnalyzing initial screenshot...")
img = Image.open(f"{test_dir}/01_initial.png")
text = pytesseract.image_to_string(img)
print(f"Detected text (first 500 chars): {text[:500]}")

# Check for year format (should be "2026" not "2,026")
if "2,026" in text or "2,025" in text or "2,024" in text:
    print("ERROR: Found comma in year format!")
    sys.exit(1)
elif "2026" in text or "2025" in text:
    print("SUCCESS: Year format looks correct (no comma)")
else:
    print("WARNING: Could not detect year in screenshot")

# Check for "LEADERBOARD" text
if "LEADERBOARD" in text.upper():
    print("SUCCESS: Found LEADERBOARD section")
else:
    print("WARNING: LEADERBOARD text not found")

# Analyze menu open screenshot
print("\nAnalyzing menu open screenshot...")
img2 = Image.open(f"{test_dir}/02_menu_open.png")
text2 = pytesseract.image_to_string(img2)
print(f"Detected text (first 500 chars): {text2[:500]}")

# Check if menu is open (should show year options)
years_found = []
for year in range(2000, 2027):
    if str(year) in text2:
        years_found.append(year)

if len(years_found) > 0:
    print(f"SUCCESS: Found years in menu: {years_found}")
else:
    print("WARNING: No years found in menu")

# Save results
with open(f"{test_dir}/ocr_results.txt", "w") as f:
    f.write("=== Initial Screenshot OCR ===\n")
    f.write(text)
    f.write("\n\n=== Menu Open Screenshot OCR ===\n")
    f.write(text2)
    f.write(f"\n\nYears found in menu: {years_found}\n")

print("\nOCR analysis complete!")
PYEOF

echo ""
echo "8. Test complete!"
echo "Screenshots saved to: $TEST_DIR"
echo "- 01_initial.png: Initial app state"
echo "- 02_menu_open.png: After tapping year picker"
echo "- ocr_results.txt: OCR analysis results"
echo ""
echo "To view screenshots:"
echo "  open $TEST_DIR/*.png"
