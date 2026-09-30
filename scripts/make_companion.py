"""Renders the companion's portraits with a local ComfyUI and an anime
SDXL checkpoint (NoobAI-XL or Illustrious-XL), then puts them into the
asset catalog.

The base portrait is drawn once; every expression is an img2img pass over
it with a moderate denoise, so face, hair and coat stay the same person.

Needs ComfyUI on 127.0.0.1:8188 and the comfy_api helper from
F:/Projects/web/cozy-orbit-wallpaper/tools. Run from the repo root:
    python scripts/make_companion.py explore      # a few candidates to pick from
    python scripts/make_companion.py              # base + all expressions
"""

import json
import random
import shutil
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, "F:/Projects/web/cozy-orbit-wallpaper/tools")
import comfy_api as comfy  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Assets.xcassets" / "Companion"
COMFY_INPUT = Path("F:/Tools/ComfyUI/input")
WORK = ROOT / "scripts" / ".companion"

CHECKPOINT = "NoobAI-XL-v1.1.safetensors"

QUALITY = "masterpiece, best quality, amazing quality, very aesthetic, absurdres, newest"
STYLE = (
    "korean webtoon style, manhwa, sharp clean lineart, dramatic cel shading, "
    "dark fantasy hunter, glowing blue and violet magic particles, rim lighting, "
    "deep midnight blue background, night sky, subtle stars"
)
FACE = (
    "detailed face, beautiful detailed eyes, visible pupils, glowing irises, "
    "softly lit face, clear facial features"
)
# Two companions to choose from; both original designs.
CHARACTERS = {
    "Nyx": (
        "1girl, solo, young woman, (short black hair:1.3), bob cut, side bangs, violet eyes, "
        "black high-collar long coat with glowing lavender trim, dark fitted armor underneath, "
        "silver shoulder guard, black fingerless gloves"
    ),
    "Kael": (
        "1boy, solo, young man, short messy black hair, dark blue eyes, "
        "black hooded long coat with glowing blue trim, dark leather armor underneath, "
        "black fingerless gloves, calm confident look"
    ),
}
NEGATIVE = (
    "worst quality, low quality, lowres, normal quality, bad anatomy, bad hands, extra fingers, "
    "missing fingers, deformed, blurry, jpeg artifacts, text, watermark, signature, logo, username, "
    "nsfw, cleavage, revealing clothes, chibi, 3d, realistic, photo, multiple people, "
    "empty eyes, blank eyes, no pupils, shadowed face, dark face, creepy"
)

# expression: (extra tags, denoise, seed offset)
EXPRESSIONS = {
    "Neutral": ("calm expression, slight smile, looking at viewer", 0.0, 0),
    "Proud": ("proud confident grin, crossed arms, bright glowing eyes, triumphant", 0.55, 1),
    "Cheer": ("excited open mouth smile, fist raised, energetic, sparkling particles", 0.6, 2),
    "Serious": ("serious determined expression, narrowed eyes, intense stare, closed mouth", 0.5, 3),
    "Gentle": ("gentle warm smile, soft eyes, head tilt, relaxed", 0.5, 4),
    "Rest": ("eyes closed, peaceful smile, relaxed, moonlight, calm night", 0.5, 5),
}


def txt2img(prompt: str, width: int, height: int, seed: int, prefix: str) -> dict:
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["1", 1]}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": NEGATIVE, "clip": ["1", 1]}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "5": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0],
                                                   "latent_image": ["4", 0], "seed": seed, "steps": 28, "cfg": 5.5,
                                                   "sampler_name": "euler_ancestral", "scheduler": "normal", "denoise": 1.0}},
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": prefix}},
    }


def img2img(image: str, prompt: str, denoise: float, seed: int, prefix: str) -> dict:
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["1", 1]}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": NEGATIVE, "clip": ["1", 1]}},
        "4": {"class_type": "LoadImage", "inputs": {"image": image}},
        "8": {"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["1", 2]}},
        "5": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0],
                                                   "latent_image": ["8", 0], "seed": seed, "steps": 30, "cfg": 5.5,
                                                   "sampler_name": "euler_ancestral", "scheduler": "normal", "denoise": denoise}},
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": prefix}},
    }


def prompt(who: str, extra: str) -> str:
    return f"{QUALITY}, {CHARACTERS[who]}, {extra}, {FACE}, upper body, {STYLE}"


def explore(who: str, count: int = 6) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    for index in range(count):
        seed = random.randrange(2**31)
        files, seconds = comfy.run(txt2img(prompt(who, EXPRESSIONS["Neutral"][0]), 832, 1216, seed, "ma_companion_explore"))
        target = WORK / f"explore_{who}_{index}_{seed}.png"
        shutil.copy(files[0], target)
        print(f"{target.name} in {seconds:.0f}s")


def save(name: str, source: Path) -> None:
    target = CATALOG / f"Companion{name}.imageset"
    target.mkdir(parents=True, exist_ok=True)
    image = Image.open(source).convert("RGB")
    image.save(target / f"{name.lower()}.jpg", quality=86, optimize=True, progressive=True)
    (target / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name.lower()}.jpg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n", encoding="utf-8")


# The portraits picked from `explore`.
SEEDS = {"Nyx": 1936032050, "Kael": 1763398590}


def build(who: str) -> None:
    seed = SEEDS[who]
    WORK.mkdir(parents=True, exist_ok=True)
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "properties": {"provides-namespace": False},
    }, indent=2) + "\n", encoding="utf-8")

    files, seconds = comfy.run(txt2img(prompt(who, EXPRESSIONS["Neutral"][0]), 832, 1216, seed, f"ma_{who.lower()}_base"))
    base = WORK / f"{who.lower()}_neutral.png"
    shutil.copy(files[0], base)
    shutil.copy(base, COMFY_INPUT / f"ma_{who.lower()}_base.png")
    save(f"{who}Neutral", base)
    print(f"{who} Neutral in {seconds:.0f}s")

    for name, (extra, denoise, offset) in EXPRESSIONS.items():
        if name == "Neutral":
            continue
        files, seconds = comfy.run(img2img(f"ma_{who.lower()}_base.png", prompt(who, extra), denoise,
                                           seed + offset, f"ma_{who.lower()}_{name.lower()}"))
        shutil.copy(files[0], WORK / f"{who.lower()}_{name.lower()}.png")
        save(f"{who}{name}", Path(files[0]))
        print(f"{who} {name} in {seconds:.0f}s")


if __name__ == "__main__":
    if sys.argv[1:2] == ["explore"]:
        explore(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 6)
    else:
        for who in sys.argv[1:] or SEEDS:
            build(who)
