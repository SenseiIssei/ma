"""Renders the companion's portraits with a local ComfyUI and an anime
SDXL checkpoint (NoobAI-XL or Illustrious-XL), then puts them into the
asset catalog.

The base portrait is drawn once; every expression is an img2img pass over
it with a moderate denoise, so face, hair and coat stay the same person.

Needs ComfyUI on 127.0.0.1:8188 and the comfy_api helper from
F:/Projects/web/cozy-orbit-wallpaper/tools. Run from the repo root:
    python scripts/make_companion.py explore      # a few candidates to pick from
    python scripts/make_companion.py              # base + all expressions
    python scripts/make_companion.py loops        # idle videos (needs the bases)
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
    "dark fantasy, glowing magic particles, rim lighting, night"
)
FACE = (
    "detailed face, beautiful detailed eyes, visible pupils, glowing irises, "
    "softly lit face, clear facial features"
)
# Ten companions, all original designs, each with its own palette and
# silhouette so they stay apart at a glance: character tags, then scene.
CHARACTERS = {
    "Nyx": (
        "1girl, solo, young woman, long silver hair, single braid over shoulder, violet eyes, "
        "crescent moon earring, black high-collar coat with silver star embroidery, glowing lavender runes, "
        "fingerless gloves",
        "night sky with a large crescent moon, violet and deep blue palette",
    ),
    "Vale": (
        "1boy, solo, mature man, 40s, short dark hair with grey streaks, stubble, eyepatch over right eye, "
        "amber eye, dark plate armor with gold trim, fur-lined cloak, veteran warrior",
        "warm amber embers, dark bronze palette",
    ),
    "Pip": (
        "no humans, solo, animal focus, small cute fox spirit, fluffy white fur with glowing cyan tail tips, "
        "three tails, big sparkling cyan eyes, tiny blue scarf, floating in the air",
        "magical cyan wisps, starry night sky, cyan and indigo palette",
    ),
    "Kira": (
        "1girl, solo, young woman, short spiky two-tone hair black and electric yellow, sharp yellow eyes, "
        "confident smirk, small lightning bolt face paint under one eye, black bomber jacket with yellow lining, "
        "boxing hand wraps, silver ear piercings, punk",
        "electric yellow lightning sparks, dark city rooftop at night, black and neon yellow palette",
    ),
    "Ash": (
        "1boy, solo, young man, messy white hair, heterochromia, one red eye one blue eye, cocky grin, "
        "sleek black armored coat with purple glowing seams, shadow soldiers silhouettes behind him",
        "purple shadow smoke, black and violet palette",
    ),
    "Luma": (
        "1girl, solo, android girl, short bob hair pastel cyan with glowing fiber optic tips, "
        "holographic visor over one eye, white and silver mechanical armor, visible robot joints on the neck, "
        "floating holographic screens with charts, calm analytical expression",
        "clean futuristic holographic interface, white and cyan palette",
    ),
    "Dax": (
        "1boy, solo, tall muscular young man, tan skin, short white buzz cut, green eyes, wide friendly grin, "
        "glowing green line tattoos on forearms, black compression shirt, towel around neck, dumbbell on shoulder",
        "gym at night with green neon lights, green and charcoal palette",
    ),
    "Nemu": (
        "1girl, solo, young woman, messy lavender hair, sleepy half-closed eyes, small yawn, "
        "oversized hoodie with cat ear hood, big headphones around neck, holding a game controller, cozy",
        "cozy dark bedroom lit by monitor glow and fairy lights, soft pink and purple palette",
    ),
    "Vesper": (
        "1boy, solo, handsome young man, long straight black hair, crimson eyes, pale skin, elegant smirk, "
        "victorian aristocrat coat black and deep red with gold buttons, lace cravat, vampire, one gloved hand raised dramatically",
        "gothic cathedral window with a blood red moon, crimson and black palette",
    ),
    "Aurel": (
        "1boy, solo, androgynous young man, long flowing pale gold hair, soft gold eyes, serene smile, "
        "white and gold librarian robes, floating glowing book, halo ring of golden runes behind the head, small white wings",
        "floating books and warm golden light, ivory and gold palette",
    ),
}
NEGATIVE = (
    "worst quality, low quality, lowres, normal quality, bad anatomy, bad hands, extra fingers, "
    "missing fingers, deformed, blurry, jpeg artifacts, text, watermark, signature, logo, username, "
    "nsfw, cleavage, revealing clothes, midriff, chibi, 3d, realistic, photo, multiple people, "
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


# Pip is an animal; faces and poses from the human list would break it.
PIP_EXPRESSIONS = {
    "Neutral": "calm, happy, looking at viewer",
    "Proud": "proud, chest puffed out, confident smug face, sparkling eyes",
    "Cheer": "excited, jumping, open mouth, very happy, sparkles",
    "Serious": "serious, focused eyes, determined",
    "Gentle": "gentle smile, soft eyes, head tilt, cute",
    "Rest": "sleeping, eyes closed, curled up, peaceful",
}


def prompt(who: str, extra: str, expression: str = "Neutral") -> str:
    looks, scene = CHARACTERS[who]
    if who == "Pip":
        return f"{QUALITY}, {looks}, {PIP_EXPRESSIONS[expression]}, cute, full body, {scene}, {STYLE}"
    return f"{QUALITY}, {looks}, {extra}, {FACE}, upper body, {scene}, {STYLE}"


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
SEEDS = {
    "Nyx": 51156248, "Vale": 776372639, "Pip": 294980275,
    "Kira": 262924397, "Ash": 382233022, "Luma": 494094586, "Dax": 1913769077,
    "Nemu": 456848475, "Vesper": 155380552, "Aurel": 1160940172,
}


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
        files, seconds = comfy.run(img2img(f"ma_{who.lower()}_base.png", prompt(who, extra, name), denoise,
                                           seed + offset, f"ma_{who.lower()}_{name.lower()}"))
        shutil.copy(files[0], WORK / f"{who.lower()}_{name.lower()}.png")
        save(f"{who}{name}", Path(files[0]))
        print(f"{who} {name} in {seconds:.0f}s")


# Idle loops for the chat header: Wan 2.2 image-to-video with the neutral
# portrait as first and last frame, then every frame's colours pulled back
# to the first one, because Wan drifts towards brown halfway through.
LOOP_PROMPT = ("anime character idle animation, gentle breathing, hair moving softly in the wind, "
               "glowing trim pulsing softly, magic particles drifting upward, subtle blinking, calm, looping, "
               "static camera, consistent colors")
LOOP_NEGATIVE = ("camera movement, zoom, fast motion, morphing, distorted face, color shift, brown, faded colors, "
                 "extra limbs, text, watermark")
LOOP_SEEDS = {name: 7 for name in SEEDS}
MEDIA = ROOT / "App" / "Companion" / "Media"


def steady_colors(source: str, target: Path) -> None:
    import av  # PyAV; ComfyUI's venv has it
    import numpy as np

    frames = [f.to_ndarray(format="rgb24").astype(np.float32) for f in av.open(source).decode(video=0)]
    ref = frames[0].reshape(-1, 3)
    ref_mean, ref_std = ref.mean(0), ref.std(0)
    out = av.open(str(target), "w")
    stream = out.add_stream("h264", rate=16)
    stream.width, stream.height, stream.pix_fmt = frames[0].shape[1], frames[0].shape[0], "yuv420p"
    stream.options = {"crf": "20", "movflags": "+faststart"}
    for frame in frames:
        flat = frame.reshape(-1, 3)
        fixed = (frame - flat.mean(0)) / (flat.std(0) + 1e-6) * ref_std + ref_mean
        for packet in stream.encode(av.VideoFrame.from_ndarray(np.clip(fixed, 0, 255).astype(np.uint8), format="rgb24")):
            out.mux(packet)
    for packet in stream.encode():
        out.mux(packet)
    out.close()


def loop(who: str) -> None:
    MEDIA.mkdir(parents=True, exist_ok=True)
    workflow = comfy.wan14b_loop(f"ma_{who.lower()}_base.png", LOOP_PROMPT, LOOP_NEGATIVE, width=512, height=752,
                                 length=81, seed=LOOP_SEEDS[who], fps=16, prefix=f"ma_{who.lower()}_loop")
    files, seconds = comfy.run(workflow)
    video = next(f for f in files if f.endswith(".mp4"))
    steady_colors(video, MEDIA / f"{who.lower()}_loop.mp4")
    print(f"{who} loop in {seconds:.0f}s")


if __name__ == "__main__":
    if sys.argv[1:2] == ["explore"]:
        explore(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 6)
    elif sys.argv[1:2] == ["loops"]:
        # Run with ComfyUI's Python, it has PyAV and numpy.
        for who in sys.argv[2:] or LOOP_SEEDS:
            loop(who)
    else:
        for who in sys.argv[1:] or SEEDS:
            build(who)
