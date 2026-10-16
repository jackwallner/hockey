#!/usr/bin/env python3
"""Android launcher icon from the iOS app icon (no redrawing, so they never drift).

The iOS icon is three percentile bars over a dark vertical gradient. The
adaptive background layer extends that gradient to the full 108dp canvas; the
foreground is the bars and pucks keyed off it, scaled so the iOS square
covers the central 66dp and the bars clear a circular mask. A white
silhouette is the themed-icon monochrome layer. Also writes the 512px Play icon.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "StatScout/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
RES = ROOT / "android/app/src/main/res"
DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
INNER_DP = 66


def edge_colour(icon: Image.Image, y: int) -> tuple[int, int, int]:
    return icon.getpixel((6, max(0, min(icon.height - 1, y))))


def keyed(icon: Image.Image, monochrome: bool) -> Image.Image:
    out = Image.new("RGBA", icon.size)
    src, dst = icon.load(), out.load()
    for y in range(icon.height):
        bg = edge_colour(icon, y)
        for x in range(icon.width):
            r, g, b = src[x, y]
            distance = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            if monochrome:
                # Fills only; the dark tracks and pucks sit too close to the background to key cleanly.
                dst[x, y] = (255, 255, 255, max(0, min(255, (distance - 40) * 4)))
            else:
                dst[x, y] = (r, g, b, min(255, distance * 12))
    return out


def background(icon: Image.Image, px: int) -> Image.Image:
    inner = round(px * INNER_DP / 108)
    top = (px - inner) // 2
    canvas = Image.new("RGB", (px, px))
    for y in range(px):
        source_y = round((y - top) / inner * icon.height)
        colour = edge_colour(icon, source_y)
        for x in range(px):
            canvas.putpixel((x, y), colour)
    return canvas


def layer(art: Image.Image, px: int) -> Image.Image:
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    inner = round(px * INNER_DP / 108)
    canvas.paste(art.resize((inner, inner), Image.LANCZOS), ((px - inner) // 2, (px - inner) // 2))
    return canvas


def main() -> None:
    icon = Image.open(SOURCE).convert("RGB")
    small = icon.resize((512, 512), Image.LANCZOS)
    colour, white = keyed(small, False), keyed(small, True)
    for name, px in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        layer(colour, px).save(folder / "ic_launcher_foreground.png")
        layer(white, px).save(folder / "ic_launcher_monochrome.png")
        background(small, px).save(folder / "ic_launcher_background.png")
    xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(xml)
    (anydpi / "ic_launcher_round.xml").write_text(xml)
    assets = ROOT / "android/play-assets"
    assets.mkdir(parents=True, exist_ok=True)
    small.save(assets / "icon-512.png")
    print("wrote adaptive icon layers and play-assets/icon-512.png")


if __name__ == "__main__":
    main()
