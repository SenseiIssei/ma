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
    "nyx": (200, 260), "kira": (190, 280), "ash": (120, 190), "luma": (250, 350), "dax": (80, 135),
    "june": (180, 250), "vale": (70, 125), "vesper": (85, 140), "aurel": (150, 230), "pip": (320, 550),
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


def main(names: list[str]) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    asr = pipeline("automatic-speech-recognition", model="openai/whisper-small", device="cuda:0",
                   torch_dtype=torch.float16)

    def hear(wav: np.ndarray, sr: int) -> str:
        audio = librosa.resample(wav.astype(np.float32), orig_sr=sr, target_sr=16000)
        return asr({"raw": audio, "sampling_rate": 16000}, generate_kwargs={"language": "japanese", "task": "transcribe"})["text"]

    # 1. Design the voices.
    design = load("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign")
    references = {}
    for who in names:
        text, instruct = DATA["reference"][who], DATA["voices"][who]
        low, high = PITCH[who]
        best = None
        for take in range(TAKES):
            torch.manual_seed(1000 + take)
            wavs, sr = design.generate_voice_design(text=text, language="Japanese", instruct=instruct)
            wav = np.asarray(wavs[0], dtype=np.float32)
            pitch = median_pitch(wav, sr)
            heard = similarity(hear(wav, sr), text)
            in_range = low <= pitch <= high
            score = heard + (0.5 if in_range else 0) - abs(pitch - (low + high) / 2) / 1000
            print(f"{who} take {take}: pitch {pitch:.0f} Hz, read back {heard:.2f}", flush=True)
            save_wav(wav, sr, WORK / f"{who}_design_{take}.wav")
            if best is None or score > best[0]:
                best = (score, wav, sr, take)
        _, wav, sr, take = best
        path = WORK / f"{who}_reference.wav"
        save_wav(wav, sr, path)
        references[who] = path
        print(f"{who}: take {take} is the voice", flush=True)
    del design
    free()

    # 2. Record the lines in those voices.
    base = load("Qwen/Qwen3-TTS-12Hz-1.7B-Base")
    report = []
    for who in names:
        prompt = base.create_voice_clone_prompt(ref_audio=str(references[who]), ref_text=DATA["reference"][who],
                                                x_vector_only_mode=False)
        counters: dict[str, int] = {}
        for line in (l for l in DATA["lines"] if l["who"] == who):
            counters[line["cue"]] = counters.get(line["cue"], 0) + 1
            name = f"{who}_{line['cue']}_{counters[line['cue']]}"
            best = None
            for attempt in range(RETRIES):
                torch.manual_seed(2000 + attempt)
                wavs, sr = base.generate_voice_clone(text=line["ja"], language="Japanese", voice_clone_prompt=prompt)
                wav = np.asarray(wavs[0], dtype=np.float32)
                heard_text = hear(wav, sr)
                heard = similarity(heard_text, line["ja"])
                # Very long clips mean the model rambled on.
                length = len(wav) / sr
                sane = length < 1.2 + 0.35 * len(line["ja"])
                score = heard + (0 if sane else -1)
                if best is None or score > best[0]:
                    best = (score, wav, sr, heard_text)
                if heard >= 0.8 and sane:
                    break
            score, wav, sr, heard_text = best
            save_m4a(finish(wav, sr), VOICE / f"{name}.m4a")
            report.append(f"{name}\t{score:.2f}\t{line['ja']}\t{heard_text}")
            print(f"{name}: {score:.2f}", flush=True)
    (WORK / "report.tsv").write_text("\n".join(report) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:] or list(DATA["voices"]))
