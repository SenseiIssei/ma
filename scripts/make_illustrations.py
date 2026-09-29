"""Renders Ma's illustrations with a local ComfyUI (Flux 2 Klein) and puts
them into the asset catalog as JPEG image sets.

Needs ComfyUI running on 127.0.0.1:8188 and the comfy_api helper from
F:/Projects/web/cozy-orbit-wallpaper/tools. Run from the repo root:
    python scripts/make_illustrations.py            # all
    python scripts/make_illustrations.py Morning    # one
"""

import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, "F:/Projects/web/cozy-orbit-wallpaper/tools")
import comfy_api as comfy  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Assets.xcassets" / "Illustrations"

STYLE = (
    "soft 3D render, minimal modern app illustration, smooth matte clay shapes, "
    "gentle pastel gradient background in lavender, periwinkle blue and soft peach, "
    "soft diffused studio lighting, subtle shadows, generous negative space, calm and "
    "optimistic mood, clean composition, no text, no letters"
)
NEGATIVE = "text, watermark, logo, letters, clutter, harsh light, people, faces, asian symbols, kanji"

# name: (subject, width, height, seed)
SCENES = {
    "Welcome": ("a calm open doorway made of soft rounded arches with warm light glowing through, a few round stepping stones leading to it, ", 1024, 1024, 21),
    "Block": ("a smartphone resting under a soft transparent glass dome on a round pedestal, gentle glow, ", 1024, 1024, 22),
    "Learn": ("a small stack of rounded books with a softly glowing light bulb above and a few floating pastel spheres, ", 1024, 1024, 23),
    "Focus": ("a minimal rounded hourglass with softly glowing sand next to a small succulent, ", 1024, 1024, 24),
    "Breathe": ("soft translucent concentric spheres floating like bubbles in the air, airy and light, ", 1024, 1024, 25),
    "Habits": ("a small watering can pouring water onto a sprouting plant, a glass of water and a rolled yoga mat nearby, ", 1024, 1024, 26),
    "Empty": ("a single smooth pebble on soft sand with a tiny green sprout growing beside it, ", 1024, 1024, 27),
    "Morning": ("sunrise over soft rolling pastel hills, a round warm sun rising, a calm morning sky, wide landscape, ", 1536, 768, 31),
    "Day": ("a bright soft sky with a few round fluffy clouds over gentle rolling hills, wide landscape, ", 1536, 768, 32),
    "Evening": ("dusk over soft rolling hills, a glowing crescent moon and a few tiny stars, deep lavender sky, wide landscape, ", 1536, 768, 33),
}


def render(name: str) -> None:
    subject, width, height, seed = SCENES[name]
    workflow = comfy.flux2_klein(subject + STYLE, NEGATIVE, width=width, height=height, seed=seed, prefix=f"ma_{name.lower()}")
    files, seconds = comfy.run(workflow)
    target = CATALOG / f"Illustration{name}.imageset"
    target.mkdir(parents=True, exist_ok=True)
    image = Image.open(files[0]).convert("RGB")
    image.save(target / f"{name.lower()}.jpg", quality=84, optimize=True, progressive=True)
    (target / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name.lower()}.jpg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n", encoding="utf-8")
    print(f"{name}: {width}x{height} in {seconds:.0f}s")


def main() -> None:
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "properties": {"provides-namespace": False},
    }, indent=2) + "\n", encoding="utf-8")
    for name in sys.argv[1:] or SCENES:
        render(name)


if __name__ == "__main__":
    main()
