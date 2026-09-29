# Ma 間

In Japanese, ma is the space between two things. The pause between two notes, the quiet between two thoughts.

This app puts that kind of space between your thumb and the next feed. Open Instagram, YouTube, X, LinkedIn or TikTok and you land on a calm screen first, take one breath and answer a question from a topic you actually want to learn. Then the app opens for a few minutes. Or you let it be, and that counts too.

Ma runs on the iPhone. No account, no ads, no analytics. The only thing that ever leaves the phone is optional: in a friends circle, a random id, a nickname and daily numbers go to a small server (`server/`, open source like the rest). It speaks English and German and follows the language of your phone.

## What's inside

**Boundaries.** As many block lists as you like, made of apps, categories and websites, each with its own time window (always, or say 22:00 to 07:00 on weekdays), its own number of questions and its own unlock length. Start from a template (social media, morning calm, deep work, night) or from scratch. A boundary can have no way through at all, a daily limit of unlocks, rising friction (every unlock today costs one more question) and a short wait before the first question. You can switch them on and off at any time; if you want, switching one off costs three right answers itself.

**Lockdown.** One tap blocks everything for 30 minutes up to the next morning, with no way through. Ending it early takes five right answers.

**The gate.** The blocked screen offers "Answer a question". Tapping it sends a notification that opens Ma: first a breath, then the questions, then the decision. "I'll leave it" sits right next to "Open", just as big.

**Duolingo-style learning.** From plain question and answer cards Ma builds eight kinds of exercise: multiple choice, reverse choice, true or not, fill the gap, match the pairs, build the sentence from tiles, type it yourself (with typo tolerance) and flash card. New cards are about recognising, cards you know well have to be recalled. Behind it sits a Leitner box per card.

Bundled topics: hiragana, everyday Japanese, building Japanese sentences, Zen and Stoicism, capital cities, Rust. Every deck ships in English and German. You can add your own topics in the app, paste whole lists at once or import JSON. The app also has a template to copy that lets any AI produce a deck on any subject.

**Focus.** Pomodoro with 25/5/15 minutes (adjustable). During a round everything from your boundaries sleeps, without exceptions if you choose. The timer keeps running when the app is closed.

**Reels filter for Safari.** Reels cannot be switched off inside the Instagram app, iOS lets no app do that. In the browser it works. Ma Filter hides Instagram Reels, YouTube Shorts, X Trends, the LinkedIn feed and Facebook Reels, and turns Shorts links into normal videos. Put the Instagram app inside a boundary and you get Instagram without Reels.

**Today.** Three rings for the day (focus, learning, habits), a morning check-in with mood and one intention, an evening reflection with three short questions, small daily habits with streaks, and breathing exercises (box, 4-7-8, calm) with haptics.

**Learn first, then practise.** New cards are taught before they are asked: the answer, why it is so and an example. A lesson introduces at most three new cards and practises them right away; the gate before an app only asks about cards you have already learned.

## How it is built

```
App/                      SwiftUI app (iOS 18)
Shared/                   code shared by the app and its extensions
  ScreenTime/             rules, unlocks, pomodoro, scheduling
Extensions/
  ShieldConfig/           draws the blocked screen
  ShieldAction/           handles its buttons
  Monitor/                watches time windows and unlocks, even with the app closed
  Filter/                 Safari extension against Reels and Shorts
project.yml               XcodeGen spec, the Xcode project is generated from it
ci/                       export settings and the install page
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
- `Actions > iOS > Run workflow > testflight` signs and uploads to TestFlight.

Signing is automatic through an App Store Connect API key: `xcodebuild` fetches the certificate and profiles from Apple itself. No certificate repo, no fastlane. The one-time setup is in [docs/SETUP.md](docs/SETUP.md).

## Your own decks

A deck is a JSON file:

```json
{
  "title": "Korean",
  "subtitle": "First words",
  "symbol": "韓",
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

Only `prompt` and `answer` are required. `example` has to contain the answer word for word, then you get gap exercises. An answer made of several space-separated parts becomes a sentence-building exercise. Bundled decks come as `deck-<id>.json` (German) and `deck-<id>.en.json` (English) with the same card ids; `python scripts/validate_decks.py` checks both.

## License

MIT
