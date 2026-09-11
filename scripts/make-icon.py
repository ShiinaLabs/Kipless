#!/usr/bin/env python3
"""Renders Kipless.icns's source artwork into the AppIcon asset catalog.

Kipless is a menu bar utility, so the icon is a plain macOS rounded square with
a bolt on it — the same mark the menu bar shows, so the two read as one thing.

Run from the repository root:

    python3 scripts/make-icon.py
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path("Kipless/Assets.xcassets/AppIcon.appiconset")

# Rendered once at high resolution and scaled down, so the squircle edge and the
# bolt's diagonals are antialiased properly at 16pt.
MASTER = 4096

# macOS icons sit in an 824x824 rounded square on a 1024x1024 canvas.
INSET = 100 / 1024
CORNER = 185.4 / 824

TOP = (0x7A, 0x6B, 0xFF)
BOTTOM = (0x38, 0x2B, 0xC4)

# A lightning bolt, as fractions of its own bounding box.
BOLT = [
    (0.52, 0.00),
    (0.10, 0.56),
    (0.40, 0.56),
    (0.30, 1.00),
    (0.90, 0.44),
    (0.60, 0.44),
]
BOLT_HEIGHT = 0.50  # of the canvas

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        gradient.putpixel(
            (0, y),
            tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)),
        )
    return gradient.resize((size, size), Image.Resampling.NEAREST)


def squircle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    inset = round(INSET * size)
    radius = round(CORNER * (size - 2 * inset))
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=radius,
        fill=255,
    )
    return mask


def white_layer(alpha: Image.Image) -> Image.Image:
    """A white RGBA layer that fades in and out with `alpha`."""
    layer = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    layer.putalpha(alpha)
    return layer


def black_layer(alpha: Image.Image) -> Image.Image:
    """A black RGBA layer that fades in and out with `alpha`."""
    layer = Image.new("RGBA", alpha.size, (0, 0, 0, 0))
    layer.putalpha(alpha)
    return layer


def bolt_points(size: int) -> list[tuple[float, float]]:
    height = BOLT_HEIGHT * size
    width = height * 0.80
    cx, cy = size / 2, size / 2
    return [
        (cx - width / 2 + ux * width, cy - height / 2 + uy * height)
        for ux, uy in BOLT
    ]


def render_master() -> Image.Image:
    size = MASTER

    # Base: vertical gradient, built full-bleed. The macOS rounded square is
    # applied as the final alpha, so nothing painted afterwards can spill into
    # the transparent corners.
    icon = vertical_gradient(size, TOP, BOTTOM).convert("RGBA")

    # Soft light from the top, the way the macOS icon grid is lit.
    gloss = Image.new("L", (size, size), 0)
    gloss_draw = ImageDraw.Draw(gloss)
    for y in range(size // 2):
        gloss_draw.line([(0, y), (size, y)], fill=round(26 * (1 - y / (size / 2))))
    icon = Image.alpha_composite(icon, white_layer(gloss))

    points = bolt_points(size)

    # The bolt's own shadow, so it does not sit flat against the gradient.
    shadow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow).polygon(
        [(x + size * 0.006, y + size * 0.012) for x, y in points], fill=90
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.012))
    icon = Image.alpha_composite(icon, black_layer(shadow))

    ImageDraw.Draw(icon).polygon(points, fill=(255, 255, 255, 255))

    icon.putalpha(squircle_mask(size))
    return icon


def main() -> None:
    master = render_master()
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size in SIZES.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(OUT / name)
    print(f"wrote {len(SIZES)} images to {OUT}")


if __name__ == "__main__":
    main()
