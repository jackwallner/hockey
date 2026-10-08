#!/usr/bin/env python3
"""
Gridiron StatScout app icon: football sibling of the baseball percentile-slider icon.

Four horizontal percentile tracks, each filled to a different value, with a football
sitting on the leading edge of every fill like a slider thumb. Rendered at 4x and
downsampled so the football's points and laces stay clean.
"""

import math
import os

from PIL import Image, ImageDraw

SS = 4                      # supersample factor
SIZE = 1024
S = SIZE * SS

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "claude-design", "icon", "output")

# --- palette (from StatScout/Views/SavantDesign.swift) ---
MIDNIGHT        = (0x09, 0x14, 0x12)
MIDNIGHT_TOP    = (0x0D, 0x1F, 0x1B)
TURF            = (0x14, 0x5C, 0x33)
PERF_HIGH       = (0x05, 0x75, 0x33)
LEATHER         = (0x7A, 0x3B, 0x1A)
LEATHER_LIGHT   = (0x92, 0x48, 0x1E)
LEATHER_DARK    = (0x5A, 0x2A, 0x10)
GOLD            = (0xD6, 0xA1, 0x30)
CANVAS          = (0xF0, 0xED, 0xE3)
PERF_LOW        = (0xB2, 0x33, 0x14)

TRACK_DARK      = (0x20, 0x2C, 0x28)
TRACK_LIGHT     = (0xDB, 0xD7, 0xC9)

# ramp variants: fill colour per bar, high percentile first
RAMP_HEAT = [PERF_HIGH, TURF, GOLD, PERF_LOW]
RAMP_TWO  = [PERF_HIGH, TURF, (0xC2, 0x51, 0x2A), (0x8C, 0x28, 0x10)]

FRACTIONS = [0.90, 0.72, 0.50, 0.28]
FRACTIONS_3 = [0.85, 0.58, 0.30]

# --- geometry, in 1024 space ---
BAR_H     = 118
BAR_GAP   = 84
TRACK_X0  = 104
TRACK_X1  = 920
BALL_TILT = -24            # degrees, clockwise
BALL_LONG = 1.66           # multiples of BAR_H; real ball is 11" x 6.7"
BALL_SHORT = 1.01


def vesica(cx, cy, half_len, half_h, tilt_deg, steps=360):
    """Prolate football outline: two circular arcs meeting at sharp points."""
    R = (half_len ** 2 + half_h ** 2) / (2 * half_h)
    dy = R - half_h                       # arc centre offset from the long axis
    span = math.asin(half_len / R)         # half sweep of each arc

    pts = []
    # upper arc: centre (0, +dy), bulges to -half_h
    for i in range(steps + 1):
        a = -span + (2 * span) * i / steps
        pts.append((R * math.sin(a), dy - R * math.cos(a)))
    # lower arc, back the other way
    for i in range(steps + 1):
        a = span - (2 * span) * i / steps
        pts.append((R * math.sin(a), -dy + R * math.cos(a)))

    t = math.radians(tilt_deg)
    cos_t, sin_t = math.cos(t), math.sin(t)
    return [(cx + x * cos_t - y * sin_t, cy + x * sin_t + y * cos_t) for x, y in pts]


def scaled_vesica(cx, cy, half_len, half_h, tilt, k):
    return vesica(cx, cy, half_len * k, half_h * k, tilt)


def vgradient(top, bottom, w, h):
    img = Image.new("RGB", (1, max(2, h)))
    px = img.load()
    for y in range(img.height):
        t = y / (img.height - 1)
        px[0, y] = tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(3))
    return img.resize((w, h), Image.BILINEAR)


def gradient_bg(top, bottom):
    return vgradient(top, bottom, S, S)


def draw_laces(draw, cx, cy, half_len, half_h, tilt, colour, bar_h):
    """One spine plus four cross-stitches, consistent weight and spacing."""
    t = math.radians(tilt)
    cos_t, sin_t = math.cos(t), math.sin(t)

    def to_canvas(x, y):
        return (cx + x * cos_t - y * sin_t, cy + x * sin_t + y * cos_t)

    # short, evenly spaced stitches on a thin spine: the one element that has to
    # survive 40px, so keep every stroke the same weight and well above 12px @1024
    spine_half = half_len * 0.34
    spine_w = round(bar_h * 0.072 * SS)
    draw.line([to_canvas(-spine_half, 0), to_canvas(spine_half, 0)],
              fill=colour, width=spine_w)

    stitch_half = half_h * 0.42
    n = 4
    for i in range(n):
        x = -spine_half + (2 * spine_half) * (i + 0.5) / n
        draw.line([to_canvas(x, -stitch_half), to_canvas(x, stitch_half)],
                  fill=colour, width=spine_w)


def draw_football(base, cx, cy, halo_colour, lace_colour, bar_h):
    half_len = bar_h * BALL_LONG / 2 * SS
    half_h = bar_h * BALL_SHORT / 2 * SS

    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # a halo in the background colour knocks the ball out of the track, so it
    # reads as a thumb sitting on the bar rather than a sticker glued over it
    d.polygon(scaled_vesica(cx, cy, half_len, half_h, BALL_TILT, 1.10), fill=halo_colour)

    # leather body, one subtle top-to-bottom shade for form, no gloss
    body = vesica(cx, cy, half_len, half_h, BALL_TILT)
    xs = [p[0] for p in body]
    ys = [p[1] for p in body]
    bx, by = int(min(xs)), int(min(ys))
    bw, bh = int(max(xs)) - bx + 1, int(max(ys)) - by + 1
    mask = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(mask).polygon([(x - bx, y - by) for x, y in body], fill=255)
    layer.paste(vgradient(LEATHER_LIGHT, LEATHER_DARK, bw, bh), (bx, by), mask)

    draw_laces(ImageDraw.Draw(layer), cx, cy, half_len, half_h, BALL_TILT, lace_colour, bar_h)

    base.alpha_composite(layer)


def build(path, *, bg_top, bg_bottom, track, ramp, halo, laces=CANVAS,
          fractions=FRACTIONS, bar_h=BAR_H, bar_gap=BAR_GAP):
    img = gradient_bg(bg_top, bg_bottom).convert("RGBA")
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
        draw.rounded_rectangle([x0, top, fill_x, bot], radius=r, fill=ramp[i])

        draw_football(img, fill_x, (top + bot) / 2, halo, laces, bar_h)

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
        # iOS-style squircle mask, approximated with a rounded rect at 4x
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

    build(os.path.join(OUT, "concept_a_dark.png"),
          bg_top=MIDNIGHT_TOP, bg_bottom=MIDNIGHT, track=TRACK_DARK,
          ramp=RAMP_HEAT, halo=MIDNIGHT)

    build(os.path.join(OUT, "concept_b_two_hue.png"),
          bg_top=MIDNIGHT_TOP, bg_bottom=MIDNIGHT, track=TRACK_DARK,
          ramp=RAMP_TWO, halo=MIDNIGHT)

    build(os.path.join(OUT, "concept_c_cream.png"),
          bg_top=(0xF6, 0xF3, 0xE9), bg_bottom=CANVAS, track=TRACK_LIGHT,
          ramp=RAMP_HEAT, halo=CANVAS)

    build(os.path.join(OUT, "concept_d_three_bar.png"),
          bg_top=MIDNIGHT_TOP, bg_bottom=MIDNIGHT, track=TRACK_DARK,
          ramp=[PERF_HIGH, GOLD, PERF_LOW], halo=MIDNIGHT,
          fractions=FRACTIONS_3, bar_h=152, bar_gap=106)

    for name in ("concept_a_dark", "concept_b_two_hue", "concept_c_cream",
                 "concept_d_three_bar"):
        src = os.path.join(OUT, f"{name}.png")
        proof(src, os.path.join(OUT, f"proof_{name}_light.png"), (0xE8, 0xE8, 0xE8))
        proof(src, os.path.join(OUT, f"proof_{name}_dark.png"), (0x18, 0x18, 0x1A))


if __name__ == "__main__":
    main()
