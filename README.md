# Ma 間

In Japanese, ma is the space between two things. The pause between two notes, the quiet between two thoughts.

This app puts that kind of space between your thumb and the next feed. Open Instagram, YouTube, X, LinkedIn or TikTok and you land on a calm screen first, take one breath and answer a question from a topic you actually want to learn. Then the app opens for a few minutes. Or you let it be, and that counts too.

Ma runs on the iPhone. No account, no ads, no analytics. The only thing that ever leaves the phone is optional: in a friends circle, a random id, a nickname and daily numbers go to a small server (`server/`, open source like the rest). It speaks English and German and follows the language of your phone.

Website: https://senseiissei.github.io/ma/

## What's inside

**Boundaries.** As many block lists as you like, made of apps, categories and websites, each with its own time window, number of questions and unlock length. Start from a template (social media, morning calm, deep work, night) or from scratch. A boundary can have no way through at all, a daily limit of unlocks, rising friction (every unlock today costs one more question) and a short wait before the first question.

**Lockdown.** One tap blocks everything for 30 minutes up to the next morning, with no way through. Ending it early takes five right answers.

**The gate.** The blocked screen offers "Answer a question". Tapping it sends a notification that opens Ma: first a breath, then the questions, then the decision. "I'll leave it" sits right next to "Open", just as big.

**Open without Reels.** No iPhone app may change what another app shows, so Reels inside the Instagram app cannot be hidden. Instead the gate offers the website in Safari, where Ma Filter hides Instagram Reels, YouTube Shorts, X Trends, the LinkedIn feed and Facebook Reels. This works during focus too.

**Learn first, then practise.** New cards are taught before they are asked: the answer, why it is so and an example. A lesson introduces at most three new cards and practises them right away with eight exercise types (choice, reverse choice, true or not, fill the gap, pairs, sentence tiles, typing with typo tolerance, flash card), driven by a Leitner box per card. The gate only asks about cards you have already learned.

21 bundled topics in English and German across languages (English, Spanish, French, Italian, Korean, Japanese kana and phrases), knowledge (history, science, capitals, mental math, general knowledge), mind (psychology, Zen and Stoicism), tech (Python, Rust, Git and Linux) and life (first aid). More in the community gallery, your own by hand, by list, by JSON, or written by Apple's on-device model, which also explains any card in more depth.

**Focus.** Pomodoro with 25/5/15 minutes. During a round everything from your boundaries sleeps. Calm sounds synthesized on the phone (rain, brown noise, ocean, a night drone) keep playing when the screen locks, and Spotify shortcuts are one tap away. The timer sits in the Dynamic Island.

**Today.** Rings for the day, a morning check-in with mood and intention, an evening reflection, habits with streaks, breathing exercises, and a weekly review with your real Screen Time.

**Balance.** Short guided workouts with voice, water and a simple meal check, and a wind-down before bed with a reminder.

**Friends without a feed.** Optional circles by invite code. Members see each other's streaks and daily numbers and share a weekly challenge. No timeline, no content.

**Widgets and accessibility.** Home and Lock Screen widgets, Dynamic Type everywhere, VoiceOver labels for rings, timers and quiz answers, and Reduce Motion respected.

## How it is built

```
App/                      SwiftUI app (iOS 26)
Shared/                   code shared by the app and its extensions
  ScreenTime/             rules, unlocks, lockdown, pomodoro, scheduling
Extensions/
  ShieldConfig/           draws the blocked screen
  ShieldAction/           handles its buttons
  Monitor/                watches time windows and unlocks, even with the app closed
  Filter/                 Safari extension against Reels and Shorts
  Widgets/                widgets and the focus Live Activity
  Report/                 the weekly Screen Time report (ExtensionKit)
server/                   friends circles: Node 24, SQLite, no dependencies
site/, gallery/           the website and the community topics (GitHub Pages)
project.yml               XcodeGen spec, the Xcode project is generated from it
ci/                       signing helpers, export settings, the install page
scripts/                  icons, illustrations, deck validation
```

The illustrations are rendered locally with Flux 2 Klein in ComfyUI (`scripts/make_illustrations.py`), the icons are drawn in code (`scripts/make_art.py`).

Blocking runs on Apple's Screen Time frameworks (FamilyControls, ManagedSettings, DeviceActivity). Every boundary gets its own ManagedSettingsStore, and an unlock is a gap written into each of those stores. The extensions share an App Group container with the app, where every piece of state lives as a small JSON file.

Two quirks worth knowing:

- A blocked screen is not allowed to open an app. That is why the way to the question goes through a notification.
- DeviceActivity refuses intervals shorter than 15 minutes. Shorter unlocks and breaks are padded to 16 minutes, and the warning callback is aimed at the real moment.

Both languages live inline in the code through `tr("English", "Deutsch")` rather than in a String Catalog. The project is built without Xcode's catalog editor, and a mistyped catalog key would fall back to the wrong language without a word.

## Building without a Mac

Everything runs on GitHub Actions. Since the repo is public, the macOS runners cost nothing.

- Every push to `main` validates the decks and compiles the app unsigned.
- `Actions > iOS > Run workflow > device` builds a development version with the full Screen Time entitlement and publishes it on an install page for registered iPhones.
- `Actions > iOS > Run workflow > testflight` signs and uploads to TestFlight (needs Apple's Family Controls distribution approval).
- `Pages` publishes the website and gallery on their own.

Signing is automatic through an App Store Connect API key. For development builds one certificate is created once and kept encrypted in the Actions cache (`ci/dev_cert.py`), and every run first checks the bundle ids at Apple (`ci/bundle_ids.py`). The one-time setup is in [docs/SETUP.md](docs/SETUP.md).

## Your own decks

A deck is a JSON file:

```json
{
  "title": "Korean",
  "subtitle": "First words",
  "symbol": "韓",
  "category": "languages",
  "cards": [
    {
      "prompt": "물",
      "answer": "water",
      "accept": ["the water"],
      "distractors": ["fire", "tree", "rice"],
      "example": "I drink water.",
      "note": "mul. Sounds a bit like the English mull."
    }
  ]
}
```

Only `prompt` and `answer` are required. `example` has to contain the answer word for word, then you get gap exercises. In language decks an answer made of several space-separated parts becomes a sentence-building exercise. Bundled decks come as `deck-<id>.json` (German) and `deck-<id>.en.json` (English) with the same card ids; `python scripts/validate_decks.py` checks both. Community decks live in `gallery/`, pull requests welcome.

## License

MIT
