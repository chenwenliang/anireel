#!/usr/bin/env python3
"""Generate AniReel's app icon, launch mark, brand mark and sample-work covers into the asset catalog.

Icon (D8, refined in Phase 7 / D9): flat duotone gradient (coral upper-left -> electric blue -> violet),
a solid white rounded letter A with a wide stance, round apex and round feet, and a large play
triangle knocked out of its middle (Ani = A, Reel = play). iOS icons are flat: no shadow.
Sample covers are painterly abstract stand-ins for the three styles, shown on the home feed while
the library is empty. Everything is drawn from scratch here; no third-party IP.
Rerun after tweaking: python3 scripts/make_placeholder_art.py  (needs Pillow)
"""

import json
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "AniReel" / "Resources" / "Assets.xcassets"
SUPERSAMPLE = 4

# Design tokens (AniReel/DesignSystem/Theme.swift mirrors these).
CORAL = (255, 107, 74)    # #FF6B4A
BLUE = (47, 107, 255)     # #2F6BFF
VIOLET = (139, 92, 246)   # #8B5CF6
CYAN = (34, 193, 238)     # #22C1EE
# Coral holds the upper-left ~40% of the icon, then melts into blue and violet.
MARK_GRADIENT = [(0.0, CORAL), (0.2, CORAL), (0.6, BLUE), (1.0, VIOLET)]
LAUNCH_BACKGROUND = (30, 22, 72)  # deep indigo


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def sample_stops(stops, t):
    t = min(max(t, 0.0), 1.0)
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0) if t1 > t0 else 0
            u = u * u * (3 - 2 * u)
            return lerp(c0, c1, u)
    return stops[-1][1]


def diagonal_gradient(size, stops):
    small = Image.new("RGB", (128, 128))
    for y in range(128):
        for x in range(128):
            small.putpixel((x, y), sample_stops(stops, (x + y) / 254))
    return small.resize((size, size), Image.BICUBIC)


def rounded_triangle(draw, points, radius, fill):
    """Union of the corner circles and the edges between them: a triangle with round corners."""
    draw.polygon(points, fill=fill)
    for a, b in zip(points, points[1:] + points[:1]):
        draw.line([a, b], fill=fill, width=round(radius * 2))
    for x, y in points:
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)


def mark_mask(s, scale=0.84):
    """The A mark as an 'L' mask of side s (white = mark), drawn at `scale` of the canvas around its centre."""
    shape = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(shape)

    def at(x, y):
        return (s * (0.5 + (x - 0.5) * scale), s * (0.5 + (y - 0.5) * scale))

    # Corner centres; the radius makes the round apex and the round outer feet.
    rounded_triangle(draw, [at(0.5, 0.235), at(0.835, 0.775), at(0.165, 0.775)], s * scale * 0.075, 255)
    # Gap between the legs, with a soft arch at the top.
    rounded_triangle(draw, [at(0.5, 0.735), at(0.66, 1.0), at(0.34, 1.0)], s * scale * 0.028, 0)
    # Play triangle: centroid on the vertical centre line of the A's body, so it reads centred.
    h, side, cy = 0.19, 0.22, 0.505
    left = 0.5 - h / 3
    rounded_triangle(draw, [at(left + 0.012, cy - side / 2 + 0.02), at(left + h - 0.02, cy),
                            at(left + 0.012, cy + side / 2 - 0.02)], s * scale * 0.02, 0)
    # Blur then re-threshold to soften the remaining sharp corners (inner feet).
    return shape.filter(ImageFilter.GaussianBlur(s * 0.012)).point(lambda v: 255 if v > 127 else 0)


def mark(size, color):
    """The A mark in `color` on transparency."""
    alpha = mark_mask(size * SUPERSAMPLE).resize((size, size), Image.LANCZOS).point(lambda v: v * color[3] // 255)
    image = Image.new("RGBA", (size, size), color[:3] + (0,))
    image.putalpha(alpha)
    return image


def app_icon():
    size = 1024
    icon = diagonal_gradient(size, MARK_GRADIENT).convert("RGBA")
    icon.alpha_composite(mark(size, (255, 255, 255, 255)))
    return icon.convert("RGB")


# --- Sample-work covers (720x1280, painterly abstract) -------------------------------------------

COVER_W, COVER_H = 720, 1280


def vertical_gradient(w, h, stops):
    small = Image.new("RGB", (1, 256))
    for y in range(256):
        small.putpixel((0, y), sample_stops(stops, y / 255))
    return small.resize((w, h), Image.BICUBIC)


def dabs(image, rng, count, palette, region, size_range, alpha_range, blur):
    """Scattered soft brush dabs, the 'painted' texture."""
    # Transparent pixels carry the first palette colour so blurred edges don't fringe dark.
    layer = Image.new("RGBA", image.size, palette[0] + (0,))
    draw = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = region
    for _ in range(count):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        w = rng.uniform(*size_range)
        h = w * rng.uniform(0.35, 0.8)
        color = rng.choice(palette) + (rng.randint(*alpha_range),)
        angle = rng.uniform(-0.5, 0.5)
        pts = []
        for i in range(18):
            t = i / 18 * 2 * math.pi
            px, py = math.cos(t) * w / 2, math.sin(t) * h / 2
            pts.append((x + px * math.cos(angle) - py * math.sin(angle), y + px * math.sin(angle) + py * math.cos(angle)))
        draw.polygon(pts, fill=color)
    image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def hill(draw, base_y, amplitude, phase, freq, fill, w=COVER_W, h=COVER_H):
    pts = [(0, h)]
    for x in range(0, w + 1, 8):
        pts.append((x, base_y + amplitude * math.sin(x / w * math.pi * freq + phase)))
    pts.append((w, h))
    draw.polygon(pts, fill=fill)


def cover_painted():
    """Hand-painted pastoral: warm sky, soft sun, rolling hills, cloud dabs."""
    rng = random.Random(7)
    image = vertical_gradient(COVER_W, COVER_H, [(0, (120, 182, 236)), (0.45, (250, 214, 170)), (1, (246, 186, 140))]).convert("RGBA")
    glow = Image.new("RGBA", image.size, (255, 240, 200, 0))
    ImageDraw.Draw(glow).ellipse([380, 330, 620, 570], fill=(255, 240, 200, 230))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
    dabs(image, rng, 70, [(255, 255, 255), (255, 244, 230), (230, 236, 250)], (0, 80, COVER_W, 520), (90, 220), (90, 170), 6)
    layer = Image.new("RGBA", image.size, (92, 148, 88, 0))
    draw = ImageDraw.Draw(layer)
    hill(draw, 760, 50, 0.4, 1.4, (128, 172, 112, 255))
    hill(draw, 860, 60, 2.1, 1.8, (92, 148, 88, 255))
    hill(draw, 990, 45, 4.0, 2.2, (70, 124, 74, 255))
    image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2)))
    dabs(image, rng, 160, [(160, 200, 120), (110, 160, 90), (200, 220, 140)], (0, 760, COVER_W, COVER_H), (30, 90), (60, 140), 3)
    dabs(image, rng, 40, [(255, 236, 200)], (0, 700, COVER_W, 900), (40, 110), (40, 90), 10)
    return image.convert("RGB")


def outlined_blob(draw, box, fill, outline, width):
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def star(draw, cx, cy, r, fill, outline, width):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.48
        t = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + rr * math.cos(t), cy + rr * math.sin(t)))
    draw.polygon(pts, fill=fill, outline=outline, width=width)


def cover_chibi():
    """Chibi pop: candy pastels, big rounded shapes with thick outlines, stars."""
    rng = random.Random(11)
    s = SUPERSAMPLE // 2
    w, h = COVER_W * s, COVER_H * s
    image = vertical_gradient(w, h, [(0, (255, 205, 226)), (0.5, (255, 232, 196)), (1, (198, 226, 255))]).convert("RGBA")
    draw = ImageDraw.Draw(image)
    ink = (70, 44, 82, 255)
    line = 9 * s
    for _ in range(14):
        r = rng.uniform(26, 60) * s
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=rng.choice([(255, 255, 255, 120), (255, 240, 250, 140)]))
    outlined_blob(draw, [-120 * s, 860 * s, 840 * s, 1600 * s], (255, 168, 196, 255), ink, line)
    outlined_blob(draw, [150 * s, 380 * s, 570 * s, 800 * s], (255, 226, 160, 255), ink, line)
    for ex in (280, 440):
        draw.ellipse([(ex - 22) * s, 560 * s, (ex + 22) * s, 612 * s], fill=ink)
        draw.ellipse([(ex - 8) * s, 568 * s, (ex + 4) * s, 582 * s], fill=(255, 255, 255, 255))
    draw.ellipse([210 * s, 630 * s, 262 * s, 662 * s], fill=(255, 140, 160, 200))
    draw.ellipse([458 * s, 630 * s, 510 * s, 662 * s], fill=(255, 140, 160, 200))
    draw.arc([330 * s, 610 * s, 390 * s, 660 * s], 20, 160, fill=ink, width=7 * s)
    for cx, cy, r, color in [(130, 260, 56, (255, 214, 102)), (590, 220, 40, (140, 210, 255)),
                             (600, 760, 34, (182, 156, 255)), (110, 830, 30, (255, 214, 102))]:
        star(draw, cx * s, cy * s, r * s, color + (255,), ink, 7 * s)
    return image.resize((COVER_W, COVER_H), Image.LANCZOS).convert("RGB")


def cover_npr():
    """2.5D cel look: flat colour bands, ink outlines, paper grain."""
    rng = random.Random(23)
    s = SUPERSAMPLE // 2
    w, h = COVER_W * s, COVER_H * s
    image = Image.new("RGBA", (w, h))
    draw = ImageDraw.Draw(image)
    bands = [(64, 76, 140), (98, 104, 186), (150, 132, 214), (236, 164, 160), (252, 206, 168)]
    for i, color in enumerate(bands):
        draw.rectangle([0, i * h * 0.12, w, (i + 1) * h * 0.12], fill=color + (255,))
    draw.rectangle([0, len(bands) * h * 0.12, w, h], fill=bands[-1] + (255,))
    draw.ellipse([w * 0.58, h * 0.2, w * 0.86, h * 0.36], fill=(255, 244, 222, 255))
    ink = (28, 24, 48, 255)
    line = 5 * s

    def ridge(base, peaks, fill):
        pts = [(0, h)] + [(w * x, h * y) for x, y in peaks] + [(w, h)]
        draw.polygon(pts, fill=fill)
        draw.line([(w * x, h * y) for x, y in peaks], fill=ink, width=line, joint="curve")

    ridge(0.6, [(0, 0.58), (0.2, 0.44), (0.38, 0.55), (0.6, 0.4), (0.82, 0.52), (1, 0.46)], (86, 92, 164, 255))
    ridge(0.7, [(0, 0.7), (0.25, 0.6), (0.5, 0.68), (0.72, 0.58), (1, 0.66)], (60, 66, 128, 255))
    # A row of flat-shaded blocks (rooftops), light side / shadow side.
    x = -0.02
    while x < 1.0:
        bw = rng.uniform(0.1, 0.17)
        top = rng.uniform(0.66, 0.74)
        draw.rectangle([w * x, h * top, w * (x + bw * 0.62), h], fill=(244, 196, 170, 255), outline=ink, width=line)
        draw.rectangle([w * (x + bw * 0.62), h * top, w * (x + bw), h], fill=(196, 140, 150, 255), outline=ink, width=line)
        for wy in range(3):
            wy0 = top + 0.035 + wy * 0.06
            draw.rectangle([w * (x + bw * 0.18), h * wy0, w * (x + bw * 0.42), h * (wy0 + 0.028)], fill=(255, 226, 150, 255), outline=ink, width=3 * s)
        x += bw
    image = image.resize((COVER_W, COVER_H), Image.LANCZOS)
    grain = Image.effect_noise((COVER_W, COVER_H), 22).convert("RGBA")
    grain.putalpha(18)
    image.alpha_composite(grain)
    return image.convert("RGB")


COVERS = {"SampleCoverGhibli": cover_painted, "SampleCoverChibi": cover_chibi, "SampleCoverNPR": cover_npr}


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def write_scaled_mark(name, points, color, info):
    directory = ASSETS / f"{name}.imageset"
    directory.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        file_name = f"{name}@{scale}x.png"
        mark(points * scale, color).save(directory / file_name, optimize=True)
        images.append({"filename": file_name, "idiom": "universal", "scale": f"{scale}x"})
    write_json(directory / "Contents.json", {"images": images, "info": info})


def main():
    info = {"author": "xcode", "version": 1}
    write_json(ASSETS / "Contents.json", {"info": info})

    icon_dir = ASSETS / "AppIcon.appiconset"
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": info,
    })
    app_icon().save(icon_dir / "AppIcon.png", optimize=True)

    write_scaled_mark("LaunchMark", 120, (255, 255, 255, 235), info)
    # Opaque white mark; screens tint or mask it with the mark gradient.
    write_scaled_mark("BrandMark", 96, (255, 255, 255, 255), info)

    for name, draw_cover in COVERS.items():
        directory = ASSETS / f"{name}.imageset"
        directory.mkdir(parents=True, exist_ok=True)
        draw_cover().save(directory / f"{name}.jpg", quality=86, optimize=True)
        write_json(directory / "Contents.json", {
            "images": [{"filename": f"{name}.jpg", "idiom": "universal"}],
            "info": info,
        })

    r, g, b = (c / 255 for c in LAUNCH_BACKGROUND)
    write_json(ASSETS / "LaunchBackground.colorset" / "Contents.json", {
        "colors": [{"color": {"color-space": "srgb", "components": {
            "alpha": "1.000", "red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}"}}, "idiom": "universal"}],
        "info": info,
    })
    print(f"wrote {ASSETS.relative_to(REPO)}")


if __name__ == "__main__":
    main()
