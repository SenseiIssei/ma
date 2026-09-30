# Companions

Ten original characters keep the person company in the Balance tab: Nyx, Kira, Ash, Luma, Dax, June, Vale, Vesper, Aurel and Pip. Each one has a portrait in six moods, a short idle animation, a Japanese voice with German and English subtitles, and a personality the on-device model is asked to keep.

None of them is a character from an existing series. The look is inspired by dark fantasy manhwa in general.

## How an answer comes together

1. `CompanionSnapshot` collects the numbers: level, XP, weekly burn, the next planned session, quests, weight trend, last workout, steps, learning streak, habits.
2. `CompanionIntent` reads what the message is about (plan, tired, motivate, weight, quests, thanks...) and picks a `VoiceCue`.
3. With Apple Intelligence, `CompanionBrain` streams an answer from the on-device model. It gets the character's persona and the numbers as instructions. Without it, `CompanionScript` builds a plain answer from the same numbers.
4. At the same time a recorded line for that cue plays in the character's voice. Its subtitle shows over the portrait and at the top of the chat bubble. Tapping the subtitle plays the line again.

Everything runs on the iPhone. The chat history is stored in the App Group (`companion-chat.json`).

## Making the assets

All assets are made on a local PC with an RTX-class GPU. Nothing is sent to a cloud service.

| What | Tool | Script |
|---|---|---|
| Portraits, 6 moods each | ComfyUI with NoobAI-XL (SDXL anime checkpoint), txt2img for the base, img2img at about 0.5 denoise for the moods | `python scripts/make_companion.py [Name ...]` |
| Candidates for a new character | same | `python scripts/make_companion.py explore Name 4` |
| Idle loops (81 frames, 16 fps) | ComfyUI with Wan 2.2 I2V 14B and the Lightning LoRA, first frame = last frame, colours pulled back to frame one | `F:/Tools/ComfyUI/.venv/Scripts/python.exe scripts/make_companion.py loops` |
| Voices and lines | Nyx, Kira, Luma, June and Pip: Qwen3-TTS VoiceDesign creates the voice from the written description in `voice_lines.json`, Qwen3-TTS Base speaks every line in it. Ash, Dax, Vale, Vesper and Aurel: Qwen3-TTS CustomVoice with a built-in voice (Dylan, Ryan, Uncle_Fu, Aiden, Eric), a speaking style per character and an emotion per situation. Whisper small reads every take back; bad takes are recorded again | `F:/Tools/qwen-tts/.venv/Scripts/python.exe scripts/make_voices.py [name ...]` |

Designed voices tend to come out high, male descriptions included, so the men use the built-in voices, which stay in a real male range (about 120 to 160 Hz). No real person's voice was cloned.

## Adding a character

1. Add the look to `CHARACTERS` in `scripts/make_companion.py`, run `explore`, pick a seed and put it in `SEEDS`.
2. Run the script for that name, then `loops`.
3. Add 24 lines (12 cues, 2 each) to `App/Companion/Voice/voice_lines.json`. Then either a voice description (Chinese works best), a reference sentence and a pitch range in `PITCH`, or a built-in voice under `presets` and a speaking style under `styles`. Run the voice script.
4. Add a case to `CompanionID` with role, tagline and persona.

## Licences of the tools

Qwen3-TTS: Apache 2.0. Wan 2.2: Apache 2.0. Whisper: MIT. NoobAI-XL: Fair AI Public License 1.0-SD, which allows using generated images.
