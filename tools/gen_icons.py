#!/usr/bin/env python3
"""Draw the app icon and write it out for every platform.

One drawing routine, many sizes: the web shell (icons/, favicon.png, plus the
maskable copies Android/Chrome install), the Android launcher mipmaps, the iOS
asset catalogue, and the Windows .ico used by windows/runner.

The picture is the app itself: a booklet page with its name band painted out
(the green band) and a leaf where the photo is.

    python tools\\gen_icons.py            # write every icon file
    python tools\\gen_icons.py --preview  # write one big PNG to preview.png

Redraw the whole set with this script; never edit the PNGs by hand, or the
platforms drift apart.
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

# Same colours the app uses (lib/main.dart): dark background, green primary.
BG = (18, 21, 15, 255)
CARD = (252, 252, 250, 255)
BAND = (46, 125, 50, 255)
LEAF = (27, 94, 32, 255)
MARGIN = 2048  # draw once at this size and scale down, for clean edges


def bezier(p0, p1, p2, p3, n):
    """n points along a cubic Bezier, as (x, y) pairs."""
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def leaf_polygon(cx, cy, w, h, tilt):
    """A leaf: pointed at both ends, widest near the middle, tilted `tilt` deg."""
    right = bezier((0, -h / 2), (w * .60, -h * .16), (w * .52, h * .26), (0, h / 2), 30)
    left = [( -x, y) for x, y in reversed(right[1:-1])]
    pts = right + left
    ca, sa = math.cos(tilt), math.sin(tilt)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def draw_icon(margin=MARGIN, full_bleed=False, shrink=1.0) -> Image.Image:
    """The icon itself. full_bleed: square, no transparency (iOS, maskable).
    shrink: maskable icons keep the glyph inside the safe zone."""
    s = margin
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Background
    if full_bleed:
        d.rectangle([0, 0, s, s], fill=BG)
    else:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.225), fill=BG)

    # Card, A4 portrait, sitting slightly below centre. The page and its
    # painted-out name band are drawn on their own layer and then clipped to a
    # rounded rectangle, so the band cannot poke past the corner radius.
    cw, ch = s * 0.44 * shrink, s * 0.62 * shrink
    cx, cy = s / 2, s * 0.52
    left, top, right, bottom = cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2
    r = cw * 0.07
    card = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rectangle([left, top, right, bottom], fill=CARD)
    cd.rectangle([left, top, right, top + ch * 0.18], fill=BAND)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([left, top, right, bottom], radius=r,
                                           fill=255)
    img.paste(card, (0, 0), mask)

    # Leaf
    d.polygon(leaf_polygon(cx, cy + ch * 0.09, cw * 0.46, ch * 0.46, math.radians(20)),
              fill=LEAF)
    # Midrib
    tip = (cx + ch * 0.46 / 2 * math.sin(math.radians(20)),
           cy + ch * 0.09 - ch * 0.46 / 2 * math.cos(math.radians(20)))
    base = (cx - ch * 0.46 / 2 * math.sin(math.radians(20)),
            cy + ch * 0.09 + ch * 0.46 / 2 * math.cos(math.radians(20)))
    d.line([base, tip], fill=CARD, width=max(2, int(s * 0.006)))

    return img


def write(path: Path, size: int, full_bleed=False, shrink=1.0):
    # Draw 4x bigger than needed (at least the base size) and scale down:
    # the leaf curves and the rounded corners stay smooth at 20 px.
    out = draw_icon(max(MARGIN, size * 4), full_bleed, shrink)
    out = out.resize((size, size), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, "PNG")
    print(f"  {path.relative_to(ROOT)}  {size}x{size}")


def main() -> int:
    preview = "--preview" in sys.argv
    if preview:
        draw_icon(full_bleed=True).resize((768, 768), Image.LANCZOS).save(
            ROOT / "preview.png", "PNG")
        print("  preview.png")
        return 0

    # --- web shell (installed as a PWA / Add to Home Screen) --------------
    write(ROOT / "web" / "favicon.png", 64)
    write(ROOT / "web" / "icons" / "Icon-192.png", 192)
    write(ROOT / "web" / "icons" / "Icon-512.png", 512)
    write(ROOT / "web" / "icons" / "Icon-maskable-192.png", 192,
          full_bleed=True, shrink=0.72)
    write(ROOT / "web" / "icons" / "Icon-maskable-512.png", 512,
          full_bleed=True, shrink=0.72)

    # --- Android launcher -------------------------------------------------
    for folder, px in (("mipmap-mdpi", 48), ("mipmap-hdpi", 72),
                       ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144),
                       ("mipmap-xxxhdpi", 192)):
        write(ROOT / "android" / "app" / "src" / "main" / "res" / folder
              / "ic_launcher.png", px)

    # --- iOS asset catalogue (opaque squares; iOS rounds them itself) -----
    ios = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, px in (
        ("Icon-App-20x20@1x", 20), ("Icon-App-20x20@2x", 40),
        ("Icon-App-20x20@3x", 60), ("Icon-App-29x29@1x", 29),
        ("Icon-App-29x29@2x", 58), ("Icon-App-29x29@3x", 87),
        ("Icon-App-40x40@1x", 40), ("Icon-App-40x40@2x", 80),
        ("Icon-App-40x40@3x", 120), ("Icon-App-60x60@2x", 120),
        ("Icon-App-60x60@3x", 180), ("Icon-App-76x76@1x", 76),
        ("Icon-App-76x76@2x", 152), ("Icon-App-83.5x83.5@2x", 167),
        ("Icon-App-1024x1024@1x", 1024),
    ):
        write(ios / f"{name}.png", px, full_bleed=True)

    # --- Windows taskbar / explorer --------------------------------------
    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    big = draw_icon()
    big.save(ico, "ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                                (64, 64), (128, 128), (256, 256)])
    print(f"  {ico.relative_to(ROOT)}  7 sizes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
