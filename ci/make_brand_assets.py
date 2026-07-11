#!/usr/bin/env python3
"""Regenerate the app icon and sign-in logo for the red/blue brand refresh.

Keeps the existing handshake glyph (extracted from the current Logo.png's
alpha channel as a mask) and recolors it: Facebook blue `#1877F2` for the
handshake, a solid `#FF0000` heart badge overlapping its top-right, matching
the in-app palette (Drokpo/Core/Brand.swift — blue is the accent, red is
reserved for like/love).

Usage (from a venv with Pillow installed):
    python3 ci/make_brand_assets.py

Run from the repo root; paths below are relative to it.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
LOGO_PATH = REPO_ROOT / "Drokpo/Resources/Assets.xcassets/Logo.imageset/Logo.png"
ICON_PATH = REPO_ROOT / "Drokpo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

BLUE = (24, 119, 242, 255)       # #1877F2 — Facebook blue, the app accent
BLUE_DARK = (14, 95, 204, 255)   # #0E5FCC — gradient bottom for the icon
RED = (255, 0, 0, 255)           # #FF0000 — YouTube red, like/love only
WHITE = (255, 250, 245, 255)


def load_glyph_mask() -> Image.Image:
    """Extract the handshake glyph's alpha channel, cropped to its bbox."""
    original = Image.open(LOGO_PATH).convert("RGBA")
    alpha = original.split()[-1]
    bbox = alpha.getbbox()
    return alpha.crop(bbox)


def colored_glyph(mask: Image.Image, color: tuple, target_width: int) -> Image.Image:
    """A solid-`color` RGBA image shaped by `mask`, scaled to `target_width`."""
    scale = target_width / mask.width
    target_height = round(mask.height * scale)
    resized_mask = mask.resize((target_width, target_height), Image.LANCZOS)
    solid = Image.new("RGBA", resized_mask.size, color)
    solid.putalpha(resized_mask)
    return solid


def heart_points(center: tuple, size: float, steps: int = 200) -> list:
    """Classic parametric heart curve, point-down, centered at `center`."""
    cx, cy = center
    scale = size / 34.0  # curve's natural extent is roughly [-16, 16] x [-17, 13]
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((cx + x * scale, cy - y * scale))
    return points


def draw_heart(canvas: Image.Image, center: tuple, size: float, halo: bool = True) -> None:
    """Paints a red heart badge onto `canvas`, with an optional white halo
    so it separates cleanly from whatever's behind it."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    if halo:
        draw.polygon(heart_points(center, size * 1.22), fill=WHITE)
    draw.polygon(heart_points(center, size), fill=RED)
    canvas.alpha_composite(layer)


def make_icon() -> None:
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    gradient = Image.new("L", (1, size))
    for y in range(size):
        t = y / (size - 1)
        gradient.putpixel((0, y), round(255 * (1 - t)))
    gradient = gradient.resize((size, size))

    top = Image.new("RGBA", (size, size), BLUE)
    bottom = Image.new("RGBA", (size, size), BLUE_DARK)
    canvas = Image.composite(top, bottom, gradient)

    mask = load_glyph_mask()
    glyph = colored_glyph(mask, WHITE, target_width=round(size * 0.58))
    glyph_pos = (
        round(size * 0.5 - glyph.width * 0.55),
        round(size * 0.58 - glyph.height * 0.5),
    )
    canvas.alpha_composite(glyph, glyph_pos)

    heart_center = (round(size * 0.74), round(size * 0.28))
    draw_heart(canvas, heart_center, size=size * 0.19)

    # App icon must have no alpha channel.
    canvas.convert("RGB").save(ICON_PATH)
    print(f"wrote {ICON_PATH} ({canvas.width}x{canvas.height}, RGB)")


def make_logo() -> None:
    size = 560
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    mask = load_glyph_mask()
    glyph = colored_glyph(mask, BLUE, target_width=round(size * 0.80))
    glyph_pos = (
        round(size * 0.48 - glyph.width * 0.55),
        round(size * 0.55 - glyph.height * 0.5),
    )
    canvas.alpha_composite(glyph, glyph_pos)

    heart_center = (round(size * 0.76), round(size * 0.24))
    draw_heart(canvas, heart_center, size=size * 0.20)

    canvas.save(LOGO_PATH)
    print(f"wrote {LOGO_PATH} ({canvas.width}x{canvas.height}, RGBA)")


if __name__ == "__main__":
    make_icon()
    make_logo()
