"""Draws Ma's artwork: the app icon, the shield ensō and the Safari icons.

Everything is generated so the repo holds the recipe, not just the pixels.
Run from the repo root:  python scripts/make_art.py
Needs Pillow. The seal glyph uses a Japanese font if one is found.
"""

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PAPER = (244, 239, 230)
INK = (31, 29, 27)
SHU = (200, 65, 44)

FONT_CANDIDATES = [
    "C:/Windows/Fonts/YuGothB.ttc",
    "/System/Library/Fonts/ヒラギノ明朝 ProN.ttc",
    "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc",
]


def enso(size, ink=INK, width=0.085, gap=0.07, seed=3, supersample=4):
    """Returns an RGBA brush-stroke circle, `size` pixels square."""
    s = size * supersample
    img = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(img)
    rng = random.Random(seed)
    cx = cy = s / 2
    base_w = s * width
    radius = s / 2 - base_w * 1.1
    start = -math.pi / 2 - 0.5
    sweep = 2 * math.pi * (1 - gap)
    steps = 1400

    def pos(u, offset=0.0):
        a = start + sweep * u
        wob = 1 + 0.014 * math.sin(u * 7.3 + 0.8) + 0.006 * math.sin(u * 23)
        r = (radius + offset) * wob
        return cx + r * math.cos(a), cy + r * math.sin(a)

    def w(u):
        landing = min(1.0, u * 14)
        fading = 1 - (u ** 2.4) * 0.72
        pulse = 0.9 + 0.1 * math.sin(u * 11)
        return base_w * max(0.12, (0.45 + 0.55 * landing) * fading * pulse)

    for i in range(steps + 1):
        u = i / steps
        x, y = pos(u)
        r = w(u) / 2
        draw.ellipse((x - r, y - r, x + r, y + r), fill=255)

    # Dry brush: carve thin gaps into the tail so the bristles show.
    for strand in range(6):
        off = rng.uniform(-0.38, 0.38)
        begin = rng.uniform(0.55, 0.8)
        thickness = base_w * rng.uniform(0.02, 0.05)
        pts = []
        for i in range(steps + 1):
            u = i / steps
            if u < begin:
                continue
            spread = off * (1 + (u - begin) * 1.6)
            pts.append(pos(u, w(u) * spread))
        if len(pts) > 1:
            draw.line(pts, fill=0, width=max(1, int(thickness)))

    # A few ink speckles where the brush lifted.
    for _ in range(6):
        u = rng.uniform(0.95, 1.0)
        x, y = pos(u, rng.uniform(-1, 1) * base_w * 0.35)
        r = rng.uniform(0.002, 0.006) * s
        draw.ellipse((x - r, y - r, x + r, y + r), fill=255)

    img = img.filter(ImageFilter.GaussianBlur(supersample * 0.35))
    img = img.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), ink + (0,))
    out.putalpha(img)
    return out


def washi(size, seed=7):
    img = Image.new("RGB", (size, size), PAPER)
    draw = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(int(size * size / 900)):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        length = rng.uniform(4, 16) * size / 1024
        a = rng.uniform(0, math.pi)
        shade = int(rng.uniform(214, 230))
        draw.line((x, y, x + math.cos(a) * length, y + math.sin(a) * length), fill=(shade, shade - 5, shade - 14), width=1)
    return img


def seal(size, glyph="間"):
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((0, 0, s - 1, s - 1), radius=s * 0.2, fill=SHU + (255,))
    inset = s * 0.08
    draw.rounded_rectangle((inset, inset, s - inset, s - inset), radius=s * 0.15, outline=PAPER + (150,), width=max(2, s // 60))
    font = None
    for candidate in FONT_CANDIDATES:
        try:
            font = ImageFont.truetype(candidate, int(s * 0.6))
            break
        except OSError:
            continue
    if font:
        box = draw.textbbox((0, 0), glyph, font=font)
        tw, th = box[2] - box[0], box[3] - box[1]
        draw.text(((s - tw) / 2 - box[0], (s - th) / 2 - box[1]), glyph, font=font, fill=PAPER + (255,))
    img = img.rotate(3, resample=Image.BICUBIC, expand=True)
    return img.resize((int(size * img.width / s), int(size * img.height / s)), Image.LANCZOS)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def colorset(path, light, dark):
    def comp(rgb):
        return {"color-space": "srgb", "components": {
            "red": f"0x{rgb[0]:02X}", "green": f"0x{rgb[1]:02X}", "blue": f"0x{rgb[2]:02X}", "alpha": "1.000"}}
    write_json(path / "Contents.json", {
        "colors": [
            {"idiom": "universal", "color": comp(light)},
            {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark)},
        ],
        "info": {"author": "xcode", "version": 1},
    })


def main():
    info = {"info": {"author": "xcode", "version": 1}}

    # App icon: paper, ink ensō, the red seal tucked into the gap.
    assets = ROOT / "App" / "Assets.xcassets"
    write_json(assets / "Contents.json", info)
    icon = washi(1024)
    ring = enso(820, width=0.09)
    icon.paste(ring, (102, 102), ring)
    stamp = seal(150)
    icon.paste(stamp, (1024 - 102 - stamp.width + 10, 1024 - 102 - stamp.height + 10), stamp)
    icon_dir = assets / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").save(icon_dir / "icon-1024.png")
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        **info,
    })
    colorset(assets / "AccentColor.colorset", SHU, (217, 87, 63))
    colorset(assets / "LaunchPaper.colorset", PAPER, (21, 20, 18))

    # Shield icon: ink ensō on transparent, 60 pt at 3x.
    shield = ROOT / "Extensions" / "ShieldConfig" / "Assets.xcassets"
    write_json(shield / "Contents.json", info)
    shield_set = shield / "ShieldEnso.imageset"
    shield_set.mkdir(parents=True, exist_ok=True)
    enso(180, width=0.1).save(shield_set / "enso@3x.png")
    write_json(shield_set / "Contents.json", {
        "images": [{"filename": "enso@3x.png", "idiom": "universal", "scale": "3x"}],
        **info,
    })

    # Safari extension icons.
    resources = ROOT / "Extensions" / "Filter" / "Resources"
    for px in (48, 96, 128, 256, 512):
        canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        ring = enso(px, width=0.12)
        canvas.alpha_composite(ring)
        dot = max(2, px // 9)
        ImageDraw.Draw(canvas).ellipse((px - dot * 2.2, px - dot * 2.2, px - dot * 0.2, px - dot * 0.2), fill=SHU + (255,))
        canvas.save(resources / f"icon-{px}.png")

    print("art written")


if __name__ == "__main__":
    main()
