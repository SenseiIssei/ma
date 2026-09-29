# Ma 間

Ma ist im Japanischen der Raum zwischen zwei Dingen. Die Pause zwischen zwei Tönen, die leere Fläche im Steingarten.

Diese App schiebt so einen Raum zwischen den Daumen und den nächsten Feed. Wer Instagram, YouTube, X, LinkedIn oder TikTok öffnen will, landet erst auf einem ruhigen Papierbildschirm, atmet einmal durch und beantwortet eine Frage aus einem Thema, das er wirklich lernen will. Danach ist die App ein paar Minuten offen. Oder man lässt es, und im Garten liegt ein Kiesel mehr.

Ma läuft komplett auf dem iPhone. Kein Konto, kein Server, keine Analyse.

## Was drin ist

**Grenzen (結界).** Beliebig viele Sperrlisten mit Apps, Kategorien und Websites, jede mit eigenem Zeitfenster (immer, oder z. B. 22:00 bis 07:00 an Werktagen), eigener Anzahl Fragen und eigener Freigabedauer. Eine Grenze kann auch ganz ohne Ausweg sein. Ein- und ausschalten geht jederzeit, auf Wunsch kostet das Ausschalten selbst drei richtige Antworten.

**Die Schranke.** Auf dem gesperrten Bildschirm steht "Frage beantworten". Ein Tipp schickt eine Mitteilung, die Ma öffnet: erst ein Atemzug, dann die Fragen, dann die Entscheidung. "Ich lass es doch" steht gleichwertig neben "Öffnen".

**Lernen im Duolingo-Stil.** Aus schlichten Frage-Antwort-Karten baut Ma acht Übungsarten: Auswahl, umgekehrte Auswahl, stimmt oder stimmt nicht, Lückentext, Paare finden, Satz aus Kacheln bauen, selbst tippen (mit Tippfehler-Toleranz) und Karteikarte. Neue Karten werden erkannt, sichere Karten müssen abgerufen werden. Dahinter steckt eine Leitner-Box pro Karte.

Mitgeliefert: Hiragana, Japanisch Alltag, japanische Sätze bauen, Zen und Stoa, Hauptstädte, Rust. Eigene Themen legt man in der App an, fügt ganze Listen auf einmal ein oder importiert JSON. Die App hat eine Vorlage zum Kopieren, mit der jede beliebige KI ein Deck zu jedem Thema erzeugt.

**Fokus (集中).** Pomodoro mit 25/5/15 Minuten (einstellbar). Während einer Runde schläft alles aus den Grenzen, auf Wunsch ohne jede Ausnahme. Der Timer ist ein Ensō, das sich über die Runde selbst malt, und läuft auch weiter, wenn die App geschlossen ist.

**Reels-Filter für Safari.** Reels lassen sich in der Instagram-App nicht abschalten, das erlaubt iOS keiner App. Im Browser geht es. Ma Filter blendet Instagram Reels, YouTube Shorts, X Trends, den LinkedIn-Feed und Facebook Reels aus und leitet Shorts-Links auf normale Videos um. Zusammen mit einer Grenze auf die Instagram-App ergibt das Instagram ohne Reels.

**Heute (今日).** Ein Karesansui-Garten, der den Tag zeigt: jede Fokusrunde ein Stein, jeder widerstandene Impuls ein Kiesel, die Lernserie als Moos.

## Wie es gebaut ist

```
App/                      SwiftUI-App (iOS 18)
Shared/                   Code, den App und Erweiterungen teilen
  ScreenTime/             Regeln, Freigaben, Pomodoro, Zeitplanung
Extensions/
  ShieldConfig/           gestaltet den Sperrbildschirm
  ShieldAction/           reagiert auf dessen Buttons
  Monitor/                wacht über Zeitfenster und Freigaben, auch bei geschlossener App
  Filter/                 Safari-Erweiterung gegen Reels und Shorts
project.yml               XcodeGen, daraus entsteht das Xcode-Projekt
fastlane/                 Signieren und Hochladen
```

Die Sperren laufen über Apples Screen-Time-Frameworks (FamilyControls, ManagedSettings, DeviceActivity). Jede Grenze bekommt einen eigenen ManagedSettingsStore, eine Freigabe ist eine Lücke, die in jeden dieser Stores geschrieben wird. Die Erweiterungen teilen sich mit der App einen App-Group-Container, in dem jeder Zustand als kleine JSON-Datei liegt.

Zwei Eigenheiten, die man kennen sollte:

- Ein Sperrbildschirm darf keine App öffnen. Deshalb geht der Weg zur Frage über eine Mitteilung.
- DeviceActivity akzeptiert keine Intervalle unter 15 Minuten. Kürzere Freigaben und Pausen werden auf 16 Minuten aufgefüllt, und der Warn-Callback wird auf den echten Zeitpunkt gelegt.

## Bauen ohne Mac

Alles läuft auf GitHub Actions. Weil das Repo öffentlich ist, kosten die macOS-Runner nichts.

- Jeder Push auf `main` prüft die Decks und kompiliert die App unsigniert.
- `Actions > iOS > Run workflow > device` baut eine signierte IPA für das eigene iPhone.
- `Actions > iOS > Run workflow > testflight` lädt nach TestFlight hoch.

Die einmalige Einrichtung (Apple-Portal, Secrets, Installation aufs iPhone) steht in [docs/SETUP.md](docs/SETUP.md).

## Eigene Decks

Ein Deck ist eine JSON-Datei:

```json
{
  "title": "Koreanisch",
  "subtitle": "Erste Wörter",
  "symbol": "韓",
  "cards": [
    {
      "prompt": "물",
      "answer": "Wasser",
      "accept": ["das Wasser"],
      "distractors": ["Feuer", "Baum", "Reis"],
      "example": "Ich trinke Wasser.",
      "note": "mul. Klingt fast wie das englische mull."
    }
  ]
}
```

Nur `prompt` und `answer` sind Pflicht. `example` muss die Antwort wörtlich enthalten, dann gibt es Lückentexte. Eine Antwort aus mehreren durch Leerzeichen getrennten Teilen wird zur Satzbau-Übung. `python scripts/validate_decks.py` prüft die mitgelieferten Decks.

## Lizenz

MIT
