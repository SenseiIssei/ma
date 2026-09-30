"""Turns raw iPhone screenshots into App Store images in Ma's night look.

Take the screenshots on the phone (side button + volume up), in the Night
appearance, and drop them into a folder named by language, sorted in the
order they should appear:

    screenshots/raw/en/1.png ... 6.png
    screenshots/raw/de/1.png ... 6.png

Then run from the repo root:

    python scripts/frame_screenshots.py

Output lands in screenshots/out/<lang>/, 1320 x 2868 (6.9 inch, the size App
Store Connect asks for first). Needs Pillow. The headline font is Segoe UI
on Windows or SF on a Mac, whatever is found first.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "screenshots" / "raw"
OUT = ROOT / "screenshots" / "out"
W, H = 1320, 2868

HEADLINES = {
    "en": [
        "A breath before the feed",
        "Answer one question, then decide",
        "Learn it first, then practise",
        "Boundaries that actually hold",
        "Deep focus, calm sounds",
        "Move, eat, sleep a little better",
    ],
    "de": [
        "Ein Atemzug vor dem Feed",
        "Eine Frage, dann entscheidest du",
        "Erst lernen, dann üben",
        "Grenzen, die wirklich halten",
        "Tiefer Fokus, ruhige Klänge",
        "Bewegen, essen, schlafen, ein bisschen besser",
    ],
}

FONTS = [
    "C:/Windows/Fonts/segoeuib.ttf",
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/SFNS.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

TOP = (27, 31, 74)       # Zen.sky, night
BOTTOM = (10, 14, 34)    # Zen.paper, night
ACCENT = (163, 161, 255) # Zen.shu, night
INK = (238, 240, 255)


def font(size):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def background():
    img = Image.new("RGB", (W, H), BOTTOM)
    px = img.load()
    for y in range(H):
        t = min(1.0, y / (H * 0.55))
        row = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = row
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W * 0.45, -H * 0.12, W * 1.25, H * 0.3), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    tint = Image.new("RGB", (W, H), ACCENT)
    return Image.composite(tint, img, glow)


def wrap(draw, text, fnt, width):
    words, lines, line = text.split(), [], ""
    for word in words:
        test = (line + " " + word).strip()
        if draw.textlength(test, font=fnt) <= width:
            line = test
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def frame(shot_path, headline):
    canvas = background()
    draw = ImageDraw.Draw(canvas)
    fnt = font(92)
    lines = wrap(draw, headline, fnt, W - 180)
    y = 170
    for line in lines:
        tw = draw.textlength(line, font=fnt)
        draw.text(((W - tw) / 2, y), line, font=fnt, fill=INK)
        y += 112

    shot = Image.open(shot_path).convert("RGB")
    target_w = int(W * 0.78)
    target_h = int(shot.height * target_w / shot.width)
    shot = shot.resize((target_w, target_h), Image.LANCZOS)
    radius = int(target_w * 0.11)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), radius=radius, fill=255)

    top = y + 90
    left = (W - target_w) // 2
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((left, top + 30, left + target_w, top + target_h + 30), radius=radius, fill=140)
    shadow = shadow.filter(ImageFilter.GaussianBlur(50))
    canvas = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), canvas, shadow)
    border = Image.new("RGB", (target_w + 16, target_h + 16), (46, 54, 110))
    bmask = Image.new("L", border.size, 0)
    ImageDraw.Draw(bmask).rounded_rectangle((0, 0, border.width - 1, border.height - 1), radius=radius + 8, fill=255)
    canvas.paste(border, (left - 8, top - 8), bmask)
    canvas.paste(shot, (left, top), mask)
    return canvas


def main():
    if not RAW.exists():
        print(f"Put screenshots into {RAW}/<en|de>/ first (see the docstring).")
        sys.exit(1)
    for lang_dir in sorted(p for p in RAW.iterdir() if p.is_dir()):
        heads = HEADLINES.get(lang_dir.name, HEADLINES["en"])
        shots = sorted(p for p in lang_dir.iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg"))
        out = OUT / lang_dir.name
        out.mkdir(parents=True, exist_ok=True)
        for i, shot in enumerate(shots):
            headline = heads[i] if i < len(heads) else ""
            frame(shot, headline).save(out / f"{i + 1:02d}.png")
            print(f"{lang_dir.name}/{i + 1:02d}.png  {headline}")


if __name__ == "__main__":
    main()
