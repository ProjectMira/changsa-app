#!/usr/bin/env python3
"""Regenerate the app icon and sign-in logo for the red-ground brand.

YouTube red `#FF0000` ground, handshake in Facebook blue `#1877F2` (the app
accent, see Drokpo/Core/Brand.swift) with a thin white halo so the glyph
stays legible on the red. No heart badge.

The glyph source is ci/assets/handshake_glyph.png, a committed grayscale
mask. Do NOT re-extract it from Logo.png — that file's alpha is now a
rounded red tile, not the handshake.

Usage (from a venv with Pillow installed, run from the repo root):
    python3 ci/make_brand_assets.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
GLYPH_PATH = REPO_ROOT / "ci/assets/handshake_glyph.png"
LOGO_PATH = REPO_ROOT / "Drokpo/Resources/Assets.xcassets/Logo.imageset/Logo.png"
ICON_PATH = REPO_ROOT / "Drokpo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

RED = (255, 0, 0, 255)        # #FF0000 — YouTube red, the brand ground
BLUE = (24, 119, 242, 255)    # #1877F2 — Facebook blue, the app accent
WHITE = (255, 255, 255, 255)  # halo

CORNER_RADIUS_RATIO = 0.224   # iOS-style rounded tile for the in-app logo
SUPERSAMPLE = 4               # draw the tile at 4x, LANCZOS down for AA corners


def load_glyph_mask() -> Image.Image:
    """The committed handshake mask, tightly cropped, grayscale."""
    mask = Image.open(GLYPH_PATH).convert("L")
    return mask.crop(mask.getbbox())


def haloed_glyph(target_width: int) -> Image.Image:
    """Blue handshake over a thin white halo, as an RGBA layer.

    The halo is the mask dilated with MaxFilter (kernel must be odd).
    The mask is padded first so the dilation doesn't clip at the edges
    of the bbox-tight mask.
    """
    mask = load_glyph_mask()
    scale = target_width / mask.width
    mask = mask.resize((target_width, round(mask.height * scale)), Image.LANCZOS)

    halo_px = max(3, round(target_width * 0.015))
    pad = halo_px + 2
    padded = Image.new("L", (mask.width + 2 * pad, mask.height + 2 * pad), 0)
    padded.paste(mask, (pad, pad))
    halo_mask = padded.filter(ImageFilter.MaxFilter(2 * halo_px + 1))

    layer = Image.new("RGBA", padded.size, (0, 0, 0, 0))
    halo = Image.new("RGBA", padded.size, WHITE)
    halo.putalpha(halo_mask)
    glyph = Image.new("RGBA", padded.size, BLUE)
    glyph.putalpha(padded)
    layer.alpha_composite(halo)
    layer.alpha_composite(glyph)
    return layer


def centered(canvas_size: int, layer: Image.Image) -> tuple:
    return ((canvas_size - layer.width) // 2, (canvas_size - layer.height) // 2)


def make_icon() -> None:
    """1024x1024 flat red, centered blue handshake, saved RGB (no alpha)."""
    size = 1024
    canvas = Image.new("RGBA", (size, size), RED)
    layer = haloed_glyph(target_width=round(size * 0.61))
    canvas.alpha_composite(layer, centered(size, layer))

    # App icon must have no alpha channel.
    canvas.convert("RGB").save(ICON_PATH)
    print(f"wrote {ICON_PATH} ({canvas.width}x{canvas.height}, RGB)")


def make_logo() -> None:
    """560x560 RGBA: red rounded tile (mini app icon), blue handshake."""
    size = 560
    big = size * SUPERSAMPLE
    tile = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=round(big * CORNER_RADIUS_RATIO), fill=RED
    )
    canvas = tile.resize((size, size), Image.LANCZOS)

    layer = haloed_glyph(target_width=round(size * 0.63))
    canvas.alpha_composite(layer, centered(size, layer))
    canvas.save(LOGO_PATH)
    print(f"wrote {LOGO_PATH} ({canvas.width}x{canvas.height}, RGBA)")


if __name__ == "__main__":
    make_icon()
    make_logo()
