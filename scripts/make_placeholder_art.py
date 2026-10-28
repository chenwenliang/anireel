#!/usr/bin/env python3
"""Generate AniReel's original placeholder app icon and launch mark into the asset catalog.

Artwork is drawn from scratch here (gradient, film frame, sparkle, brush swoosh); no third-party IP.
Rerun after tweaking: python3 scripts/make_placeholder_art.py  (needs Pillow)
"""

import json
import pathlib

from PIL import Image, ImageDraw, ImageFilter

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "AniReel" / "Resources" / "Assets.xcassets"
SUPERSAMPLE = 4

GRADIENT = [(255, 138, 91), (226, 80, 143), (106, 75, 216)]
LAUNCH_BACKGROUND = (26, 20, 38)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def diagonal_gradient(size):
    small = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            small.putpixel((x, y), lerp(GRADIENT[0], GRADIENT[1], t * 2) if t < 0.5 else lerp(GRADIENT[1], GRADIENT[2], t * 2 - 1))
    return small.resize((size, size), Image.BICUBIC)


def sparkle(draw, cx, cy, r, fill):
    w = r * 0.22
    draw.polygon([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w),
                  (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w)], fill=fill)


def mark(size, color):
    """Film frame with sprocket holes, a sparkle and a brush swoosh, on transparency."""
    s = size * SUPERSAMPLE
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    stroke = round(s * 0.045)
    inset = s * 0.16
    draw.rounded_rectangle([inset, inset, s - inset, s - inset], radius=s * 0.12, outline=color, width=stroke)
    for i in range(4):
        y = inset + s * 0.1 + i * (s - 2 * inset - s * 0.2) / 3
        for x in (inset + s * 0.06, s - inset - s * 0.06):
            draw.rounded_rectangle([x - s * 0.025, y - s * 0.03, x + s * 0.025, y + s * 0.03], radius=s * 0.01, fill=color)
    sparkle(draw, s * 0.5, s * 0.45, s * 0.17, color)
    sparkle(draw, s * 0.64, s * 0.33, s * 0.055, color)
    draw.arc([s * 0.3, s * 0.48, s * 0.72, s * 0.78], start=200, end=330, fill=color, width=round(s * 0.04))
    return image.resize((size, size), Image.LANCZOS)


def app_icon():
    size = 1024
    icon = diagonal_gradient(size).convert("RGBA")
    shadow = mark(size, (40, 10, 60, 110)).filter(ImageFilter.GaussianBlur(10))
    icon.alpha_composite(shadow, (0, 12))
    icon.alpha_composite(mark(size, (255, 255, 255, 255)))
    return icon.convert("RGB")


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def main():
    info = {"author": "xcode", "version": 1}
    write_json(ASSETS / "Contents.json", {"info": info})

    icon_dir = ASSETS / "AppIcon.appiconset"
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": info,
    })
    app_icon().save(icon_dir / "AppIcon.png", optimize=True)

    mark_dir = ASSETS / "LaunchMark.imageset"
    mark_dir.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        name = f"LaunchMark@{scale}x.png"
        mark(120 * scale, (255, 255, 255, 235)).save(mark_dir / name, optimize=True)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    write_json(mark_dir / "Contents.json", {"images": images, "info": info})

    r, g, b = (c / 255 for c in LAUNCH_BACKGROUND)
    write_json(ASSETS / "LaunchBackground.colorset" / "Contents.json", {
        "colors": [{"color": {"color-space": "srgb", "components": {
            "alpha": "1.000", "red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}"}}, "idiom": "universal"}],
        "info": info,
    })
    print(f"wrote {ASSETS.relative_to(REPO)}")


if __name__ == "__main__":
    main()
