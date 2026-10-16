#!/usr/bin/env python3
"""Composite raw Android captures into Google Play screenshots and the feature graphic.

Same headlines and panels as the App Store set (fastlane/screenshots/en-US):
a large two-line headline over alternating midnight and cream gradients, with
the real capture below. Play rejects anything longer than 2:1, so frames are
1080x1920. Reads android/play-assets/raw/ (1080x2400 captures of the debug
build's fictional fixture feed) and writes android/play-assets/screenshots/
and android/play-assets/feature-graphic.png.

Capture recipe: System UI demo mode on, then the capture-gated instrumented
test `StoreScreenshotTest` (`am instrument -e class ...StoreScreenshotTest`), which drives the
debug build's fixture feed with Pro unlocked and writes
`/sdcard/Android/data/com.jackwallner.hockey/files/screens/*.png`; pull them
into android/play-assets/raw/.

Usage: python3 scripts/play_screenshot_compositor.py
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "android" / "play-assets"
RAW = ASSETS / "raw"
OUT = ASSETS / "screenshots"
ICON = ROOT / "StatScout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
SFNS = "/System/Library/Fonts/SFNS.ttf"

W, H = 1080, 1920
# Navy scoreboard, from the app icon and the App Store set's theme.
DARK = ((12, 30, 60), (5, 18, 41))
LIGHT = ((238, 242, 247), (201, 214, 232))
CREAM_TEXT = (244, 246, 250)
INK = (12, 26, 51)
BEZEL = (8, 14, 26)
TAGLINE = (188, 202, 226)


@dataclass
class Shot:
    raw: str
    out: str
    headline: tuple[str, str]
    dark: bool


SHOTS = [
    Shot("01_league_leaders.png", "01-see-who-drives-the-offense", ("See who really", "drives the offense"), True),
    Shot("02_player_profile.png", "02-read-the-whole-player", ("Read the whole player", "in one scroll"), False),
    Shot("04_trends.png", "03-know-who-is-hot-right-now", ("Know who is hot", "before the box score"), True),
    Shot("05_game_detail.png", "04-see-how-every-game-was-won", ("See how every game", "was really won"), False),
    Shot("03_goalie_profile.png", "05-rate-goalies-on-what-they-faced", ("Rate goalies on the", "shots they faced"), True),
    Shot("07_comparison.png", "06-settle-any-player-debate", ("Settle any", "player debate"), False),
    Shot("06_team.png", "07-scout-every-club-in-a-tap", ("Scout every club", "in a tap"), True),
]


def sans(size: int, weight: int = 600) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(SFNS, size)
    try:
        # Axes: Width, Optical Size, GRAD, Weight.
        font.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])
    except (OSError, ValueError):
        pass
    return font


def gradient(size: tuple[int, int], stops: tuple[tuple[int, int, int], tuple[int, int, int]]) -> Image.Image:
    width, height = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    top, bottom = stops
    for y in range(height):
        t = y / height
        draw.line([(0, y), (width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (img.width - 1, img.height - 1)], radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def render(shot: Shot) -> Path:
    canvas = gradient((W, H), DARK if shot.dark else LIGHT)
    draw = ImageDraw.Draw(canvas)
    size = 92
    while size > 60 and max(draw.textlength(line, font=sans(size, 600)) for line in shot.headline) > W - 96:
        size -= 2
    head = sans(size, 600)
    for i, line in enumerate(shot.headline):
        draw.text((W / 2, 120 + i * 104), line, font=head, fill=CREAM_TEXT if shot.dark else INK, anchor="mm")

    raw = Image.open(RAW / shot.raw).convert("RGB")
    if raw.size != (1080, 2400):
        raise ValueError(f"{shot.raw} is {raw.size}, expected 1080x2400")
    top, bezel = 290, 16
    screen_h = H - top - 60 - 2 * bezel
    screen_w = round(screen_h * raw.width / raw.height)
    screen = rounded(raw.resize((screen_w, screen_h), Image.LANCZOS), 26)
    frame_w, frame_h = screen_w + 2 * bezel, screen_h + 2 * bezel
    left = (W - frame_w) // 2

    shadow = Image.new("RGBA", (frame_w + 160, frame_h + 160), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([(80, 96), (frame_w + 80, frame_h + 96)], radius=42, fill=(0, 0, 0, 120 if shot.dark else 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.paste(shadow, (left - 80, top - 80), shadow)
    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([(0, 0), (frame_w - 1, frame_h - 1)], radius=42, fill=BEZEL)
    canvas.paste(frame, (left, top), frame)
    canvas.paste(screen, (left + bezel, top + bezel), screen)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{shot.out}.png"
    canvas.save(path, "PNG")
    return path


def feature_graphic() -> Path:
    fw, fh = 1024, 500
    img = gradient((fw, fh), DARK)
    draw = ImageDraw.Draw(img)
    icon = rounded(Image.open(ICON).convert("RGB").resize((132, 132), Image.LANCZOS), 30)
    img.paste(icon, (64, 82), icon)
    draw.text((64, 250), "StatScout", font=sans(76, 700), fill=CREAM_TEXT)
    tagline = sans(32, 500)
    draw.text((66, 352), "NHL expected goals and", font=tagline, fill=TAGLINE)
    draw.text((66, 394), "percentile bars.", font=tagline, fill=TAGLINE)

    board = Image.open(RAW / "01_league_leaders.png").convert("RGB").crop((30, 700, 1050, 1610))
    board = rounded(board.resize((round(board.width * 380 / board.height), 380), Image.LANCZOS), 26)
    img.paste(board, (fw - board.width - 56, (fh - board.height) // 2), board)
    path = ASSETS / "feature-graphic.png"
    img.save(path, "PNG")
    return path


def main() -> None:
    for shot in SHOTS:
        print(render(shot))
    print(feature_graphic())


if __name__ == "__main__":
    main()
