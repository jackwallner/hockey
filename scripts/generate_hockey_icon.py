#!/usr/bin/env python3
"""
Hockey StatScout app icon: the percentile-slider icon the StatScout family
shares, with a puck as the slider thumb.

Four horizontal percentile tracks on an ice-blue sheet, each filled to a
different value along the red-hot / blue-cold ramp the app uses, with a puck
sitting on the leading edge of every fill. Rendered at 4x and downsampled so
the puck's edge stays crisp at 40 px.
"""

import os

from PIL import Image, ImageDraw

SS = 4
SIZE = 1024
S = SIZE * SS

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "claude-design", "icon", "output")

# palette (from StatScout/Views/SavantDesign.swift, RinkPalette)
ICE_TOP   = (0xF4, 0xF7, 0xFB)
ICE       = (0xE1, 0xE8, 0xF0)
NAVY      = (0x05, 0x12, 0x29)
NAVY_TOP  = (0x0C, 0x1E, 0x3C)
HOT       = (0xC7, 0x21, 0x24)
WARM      = (0xD9, 0x5A, 0x3A)
MID       = (0x6B, 0x70, 0x7A)
COLD      = (0x1F, 0x54, 0xB8)
PUCK      = (0x12, 0x14, 0x18)
PUCK_TOP  = (0x2A, 0x2E, 0x36)
PUCK_EDGE = (0x3C, 0x41, 0x4B)

TRACK_LIGHT = (0xC9, 0xD3, 0xDF)
TRACK_DARK  = (0x1A, 0x2C, 0x4A)

RAMP = [HOT, WARM, MID, COLD]
FRACTIONS = [0.90, 0.72, 0.50, 0.28]

BAR_H = 118
BAR_GAP = 84
TRACK_X0 = 104
TRACK_X1 = 920
PUCK_W = 1.42      # puck width in multiples of BAR_H
PUCK_FACE = 0.42   # top-face height as a fraction of width (perspective)
PUCK_SIDE = 0.34   # visible side height as a fraction of width


def vgradient(top, bottom, w, h):
    img = Image.new("RGB", (1, max(2, h)))
    px = img.load()
    for y in range(img.height):
        t = y / (img.height - 1)
        px[0, y] = tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(3))
    return img.resize((w, h), Image.BILINEAR)


def draw_puck(base, cx, cy, halo, bar_h):
    """A puck seen slightly from above: a dark side band under a lighter top face."""
    w = bar_h * PUCK_W * SS
    face_h = w * PUCK_FACE
    side_h = w * PUCK_SIDE
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    top_cy = cy - side_h * 0.35
    bot_cy = top_cy + side_h

    # halo knocks the puck out of the track so it reads as a thumb on the bar
    pad = w * 0.09
    d.rounded_rectangle(
        [cx - w / 2 - pad, top_cy - face_h / 2 - pad, cx + w / 2 + pad, bot_cy + face_h / 2 + pad],
        radius=(face_h / 2 + pad), fill=halo)

    # side band: a rectangle between the two ellipse centres plus the bottom ellipse
    d.ellipse([cx - w / 2, bot_cy - face_h / 2, cx + w / 2, bot_cy + face_h / 2], fill=PUCK)
    d.rectangle([cx - w / 2, top_cy, cx + w / 2, bot_cy], fill=PUCK)
    # a thin lighter rim on the side band gives the cylinder its edge
    rim = max(2 * SS, int(w * 0.012))
    d.rectangle([cx - w / 2, top_cy, cx - w / 2 + rim, bot_cy], fill=PUCK_EDGE)
    d.rectangle([cx + w / 2 - rim, top_cy, cx + w / 2, bot_cy], fill=PUCK_EDGE)
    # top face
    d.ellipse([cx - w / 2, top_cy - face_h / 2, cx + w / 2, top_cy + face_h / 2], fill=PUCK_TOP)
    # inner ring on the face, like a real puck's logo well
    inset = w * 0.18
    ring = max(2 * SS, int(w * 0.018))
    d.ellipse([cx - w / 2 + inset, top_cy - face_h / 2 + inset * PUCK_FACE,
               cx + w / 2 - inset, top_cy + face_h / 2 - inset * PUCK_FACE],
              outline=PUCK_EDGE, width=ring)

    base.alpha_composite(layer)


def build(path, *, bg_top, bg_bottom, track, halo, fractions=FRACTIONS,
          bar_h=BAR_H, bar_gap=BAR_GAP):
    img = vgradient(bg_top, bg_bottom, S, S).convert("RGBA")
    draw = ImageDraw.Draw(img)

    n = len(fractions)
    total = n * bar_h + (n - 1) * bar_gap
    y0 = (SIZE - total) / 2

    for i, frac in enumerate(fractions):
        top = (y0 + i * (bar_h + bar_gap)) * SS
        bot = top + bar_h * SS
        r = bar_h * SS / 2
        x0, x1 = TRACK_X0 * SS, TRACK_X1 * SS
        draw.rounded_rectangle([x0, top, x1, bot], radius=r, fill=track)
        fill_x = x0 + (x1 - x0) * frac
        draw.rounded_rectangle([x0, top, fill_x, bot], radius=r, fill=RAMP[i])
        draw_puck(img, fill_x, (top + bot) / 2, halo, bar_h)

    img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(path)
    print("wrote", path)


def proof(src, path, label_bg):
    icon = Image.open(src).convert("RGB")
    sizes = [180, 120, 80, 60, 40]
    pad, gap = 40, 32
    w = pad * 2 + sum(sizes) + gap * (len(sizes) - 1)
    h = pad * 2 + max(sizes)
    sheet = Image.new("RGB", (w, h), label_bg)
    x = pad
    for s in sizes:
        m = Image.new("L", (s * 4, s * 4), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, s * 4 - 1, s * 4 - 1],
                                           radius=int(s * 4 * 0.2237), fill=255)
        m = m.resize((s, s), Image.LANCZOS)
        tile = icon.resize((s, s), Image.LANCZOS)
        sheet.paste(tile, (x, pad + (max(sizes) - s) // 2), m)
        x += s + gap
    sheet.save(path)
    print("wrote", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    build(os.path.join(OUT, "concept_a_ice.png"),
          bg_top=ICE_TOP, bg_bottom=ICE, track=TRACK_LIGHT, halo=ICE)
    build(os.path.join(OUT, "concept_b_navy.png"),
          bg_top=NAVY_TOP, bg_bottom=NAVY, track=TRACK_DARK, halo=NAVY)
    for name, bg in (("concept_a_ice", (0xF4, 0xF7, 0xFB)), ("concept_b_navy", (0x05, 0x12, 0x29))):
        proof(os.path.join(OUT, f"{name}.png"), os.path.join(OUT, f"proof_{name}.png"), bg)


if __name__ == "__main__":
    main()
