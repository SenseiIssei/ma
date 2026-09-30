"""Gives every companion a voice of their own and records their lines.

1. Voice design: Qwen3-TTS VoiceDesign turns the written description in
   App/Companion/Voice/voice_lines.json into a brand-new voice. Nobody real is
   cloned. A few takes of the reference sentence are made and the one whose
   pitch fits the character best (and that the speech recogniser reads back
   cleanly) becomes the voice.
2. Lines: Qwen3-TTS Base speaks every line in that designed voice. Whisper
   reads each take back; a take that drifts too far from the script is
   recorded again.
3. Every clip is trimmed, levelled and saved as AAC next to lines.json.

Needs the venv in F:/Tools/qwen-tts (Python 3.12, torch cu130, qwen-tts,
transformers, librosa, av). Run from the repo root:
    F:/Tools/qwen-tts/.venv/Scripts/python.exe scripts/make_voices.py          # all
    F:/Tools/qwen-tts/.venv/Scripts/python.exe scripts/make_voices.py mika pip # some
"""

import difflib
import gc
import json
import sys
from pathlib import Path

import av
import librosa
import numpy as np
import torch
from qwen_tts import Qwen3TTSModel
from transformers import pipeline

ROOT = Path(__file__).resolve().parent.parent
VOICE = ROOT / "App" / "Companion" / "Voice"
WORK = ROOT / "scripts" / ".companion" / "voice"
DATA = json.loads((VOICE / "voice_lines.json").read_text(encoding="utf-8"))

# Median pitch each voice should land in, in Hz.
PITCH = {
    "nyx": (200, 260), "kira": (170, 260), "ash": (120, 190), "luma": (250, 350), "dax": (80, 135),
    "nemu": (170, 260), "vale": (70, 125), "vesper": (85, 140), "aurel": (150, 230), "pip": (320, 600),
}
TAKES = 4
RETRIES = 3
OUT_RATE = 24000


def free() -> None:
    gc.collect()
    torch.cuda.empty_cache()


def load(name: str) -> Qwen3TTSModel:
    return Qwen3TTSModel.from_pretrained(name, device_map="cuda:0", dtype=torch.bfloat16, attn_implementation="sdpa")


def median_pitch(wav: np.ndarray, sr: int) -> float:
    f0, voiced, _ = librosa.pyin(wav.astype(np.float32), fmin=60, fmax=700, sr=sr)
    f0 = f0[voiced] if voiced is not None else f0
    f0 = f0[~np.isnan(f0)]
    return float(np.median(f0)) if len(f0) else 0.0


def normalize_ja(text: str) -> str:
    keep = [c for c in text if c.isalnum()]
    return "".join(keep)


def similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, normalize_ja(a), normalize_ja(b)).ratio()


def finish(wav: np.ndarray, sr: int) -> np.ndarray:
    """Trim silence, level to about -16 LUFS-ish peak, add short fades."""
    wav = wav.astype(np.float32)
    if sr != OUT_RATE:
        wav = librosa.resample(wav, orig_sr=sr, target_sr=OUT_RATE)
    wav, _ = librosa.effects.trim(wav, top_db=38)
    rms = float(np.sqrt(np.mean(wav ** 2))) or 1e-6
    wav = wav * min(0.12 / rms, 0.95 / (np.abs(wav).max() or 1e-6))
    fade = int(0.012 * OUT_RATE)
    if len(wav) > 2 * fade:
        wav[:fade] *= np.linspace(0, 1, fade)
        wav[-fade:] *= np.linspace(1, 0, fade)
    pad = np.zeros(int(0.06 * OUT_RATE), dtype=np.float32)
    return np.concatenate([pad, wav, pad])


def save_m4a(wav: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    container = av.open(str(path), "w", format="mp4")
    stream = container.add_stream("aac", rate=OUT_RATE)
    stream.layout = "mono"
    stream.bit_rate = 64000
    samples = (np.clip(wav, -1, 1) * 32767).astype(np.int16).reshape(1, -1)
    frame = av.AudioFrame.from_ndarray(samples, format="s16", layout="mono")
    frame.sample_rate = OUT_RATE
    for packet in stream.encode(frame):
        container.mux(packet)
    for packet in stream.encode(None):
        container.mux(packet)
    container.close()


def save_wav(wav: np.ndarray, sr: int, path: Path) -> None:
    import soundfile as sf
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), wav, sr)


# How each situation should sound, added to a preset voice's style.
CUE_EMOTION = {
    "morning": "元气地打招呼", "day": "轻松地打招呼", "evening": "放松地打招呼",
    "night": "轻声、带着困意地说", "proud": "自豪、赞赏地说", "cheer": "非常兴奋、充满干劲地大声说",
    "quest": "认真、坚定地说", "gentle": "温柔、体贴地轻声说", "thanks": "有点害羞、温和地说",
    "levelup": "激动、庆祝地说", "status": "平静、清楚地说", "listen": "随意、自然地说",
}


def lines_of(who: str):
    counters: dict[str, int] = {}
    for line in (l for l in DATA["lines"] if l["who"] == who):
        counters[line["cue"]] = counters.get(line["cue"], 0) + 1
        yield f"{who}_{line['cue']}_{counters[line['cue']]}", line


def record(name: str, text: str, speak, hear, report: list) -> None:
    """Up to RETRIES takes; the one Whisper reads back best is kept."""
    best = None
    for attempt in range(RETRIES):
        torch.manual_seed(2000 + attempt)
        wav, sr = speak()
        heard_text = hear(wav, sr)
        heard = similarity(heard_text, text)
        sane = len(wav) / sr < 1.2 + 0.35 * len(text)  # longer means it rambled
        score = heard + (0 if sane else -1)
        if best is None or score > best[0]:
            best = (score, wav, sr, heard_text)
        if heard >= 0.85 and sane:
            break
    score, wav, sr, heard_text = best
    save_m4a(finish(wav, sr), VOICE / f"{name}.m4a")
    report.append(f"{name}\t{score:.2f}\t{text}\t{heard_text}")
    print(f"{name}: {score:.2f}", flush=True)


def main(names: list[str], redesign: set[str]) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    asr = pipeline("automatic-speech-recognition", model="openai/whisper-small", device="cuda:0", dtype=torch.float16)

    def hear(wav: np.ndarray, sr: int) -> str:
        audio = librosa.resample(wav.astype(np.float32), orig_sr=sr, target_sr=16000)
        return asr({"raw": audio, "sampling_rate": 16000}, generate_kwargs={"language": "japanese", "task": "transcribe"})["text"]

    presets: dict[str, str] = DATA.get("presets", {})
    designed = [w for w in names if w not in presets]
    report: list[str] = []

    # 1. Design voices that do not have a reference yet (or are asked to be redone).
    todo = [w for w in designed if w in redesign or not (WORK / f"{w}_reference.wav").exists()]
    if todo:
        design = load("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign")
        for who in todo:
            text, instruct = DATA["reference"][who], DATA["voices"][who]
            low, high = PITCH[who]
            best = None
            for take in range(TAKES):
                torch.manual_seed(1000 + take)
                wavs, sr = design.generate_voice_design(text=text, language="Japanese", instruct=instruct)
                wav = np.asarray(wavs[0], dtype=np.float32)
                pitch = median_pitch(wav, sr)
                heard = similarity(hear(wav, sr), text)
                score = heard + (0.5 if low <= pitch <= high else 0) - abs(pitch - (low + high) / 2) / 1000
                print(f"{who} take {take}: pitch {pitch:.0f} Hz, read back {heard:.2f}", flush=True)
                save_wav(wav, sr, WORK / f"{who}_design_{take}.wav")
                if best is None or score > best[0]:
                    best = (score, wav, sr, take)
            _, wav, sr, take = best
            save_wav(wav, sr, WORK / f"{who}_reference.wav")
            print(f"{who}: take {take} is the voice", flush=True)
        del design
        free()

    # 2. Designed voices speak their lines through the clone model.
    if designed:
        base = load("Qwen/Qwen3-TTS-12Hz-1.7B-Base")
        for who in designed:
            prompt = base.create_voice_clone_prompt(ref_audio=str(WORK / f"{who}_reference.wav"),
                                                    ref_text=DATA["reference"][who], x_vector_only_mode=False)
            for name, line in lines_of(who):
                def speak(text=line["ja"]):
                    wavs, sr = base.generate_voice_clone(text=text, language="Japanese", voice_clone_prompt=prompt)
                    return np.asarray(wavs[0], dtype=np.float32), sr
                record(name, line["ja"], speak, hear, report)
        del base
        free()

    # 3. The men use Qwen's preset voices, which stay reliably low, with a
    #    style for the character and an emotion for the situation.
    chosen = [w for w in names if w in presets]
    if chosen:
        custom = load("Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
        for who in chosen:
            for name, line in lines_of(who):
                instruct = f"{DATA['styles'][who]}，这句话要{CUE_EMOTION[line['cue']]}。"
                def speak(text=line["ja"], instruct=instruct, speaker=presets[who]):
                    wavs, sr = custom.generate_custom_voice(text=text, language="Japanese", speaker=speaker, instruct=instruct)
                    return np.asarray(wavs[0], dtype=np.float32), sr
                record(name, line["ja"], speak, hear, report)

    with open(WORK / "report.tsv", "a", encoding="utf-8") as handle:
        handle.write("\n".join(report) + "\n")


if __name__ == "__main__":
    args = sys.argv[1:]
    redo = {a.split("=", 1)[1] for a in args if a.startswith("--redesign=")}
    who = [a for a in args if not a.startswith("--")]
    main(who or list(DATA["voices"]), redo)
