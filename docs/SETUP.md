# Einrichtung

Einmal durchgehen, danach baut ein Knopfdruck in GitHub Actions eine neue TestFlight-Version. Alles davon geht im Browser, ein Mac wird nie gebraucht.

## 1. Identifier im Developer-Portal

Certificates, Identifiers & Profiles > Identifiers.

**App Group:** Filter oben rechts auf "App Groups", `+`, Description `Ma`, Identifier `group.com.sensei.ma`.

**Fünf App IDs** (Filter auf "App IDs", `+`, App, Bundle ID "Explicit"):

| Description | Bundle ID | App Groups | Family Controls |
|---|---|---|---|
| Ma | `com.sensei.ma` | ja | ja |
| Ma Shield | `com.sensei.ma.shieldconfig` | ja | ja |
| Ma Action | `com.sensei.ma.shieldaction` | ja | ja |
| Ma Monitor | `com.sensei.ma.monitor` | ja | ja |
| Ma Filter | `com.sensei.ma.filter` | ja | nein |

Danach jede ID öffnen, bei App Groups auf **Configure** und `group.com.sensei.ma` zuweisen, speichern.

Zertifikate und Provisioning Profiles legst du nicht an. Die erzeugt der Build selbst.

## 2. Family Controls Distribution beantragen

Ohne Apples Freigabe gibt es die Bildschirmzeit-Schnittstelle nur in Development-Builds, und TestFlight scheitert beim Signieren.

Den Antrag stellst du im Reiter **Capability Requests** der jeweiligen App ID oder über https://developer.apple.com/contact/request/family-controls-distribution, einmal für jede ID mit Family Controls (alle außer `.filter`).

Als Begründung reicht die ehrliche: eine App, mit der man sich selbst Social Media sperrt und vor dem Entsperren eine Lernfrage beantwortet. Apple antwortet meist innerhalb von ein bis zwei Wochen.

## 3. App Store Connect

- **Lizenzvereinbarung akzeptieren**, falls oben ein gelbes Banner steht. Sonst werden Uploads abgelehnt.
- **App anlegen:** Apps > `+` > Neue App, iOS, Bundle-ID `com.sensei.ma`, SKU `ma`. Der Store-Name muss eindeutig sein, "Ma" allein ist vergeben.
- **API-Key:** Benutzer und Zugriff > Integrationen > App Store Connect API > Team-Schlüssel > `+`, Rolle **Admin**. Mit weniger Rechten darf Xcode keine Zertifikate erstellen. Die `.p8`-Datei gibt es nur einmal zum Herunterladen. Key ID und Issuer ID notieren.

## 4. Secrets im Repo

Jeder Befehl fragt den Wert verdeckt ab:

```bash
gh secret set ASC_KEY_ID -R SenseiIssei/ma
```

```bash
gh secret set ASC_ISSUER_ID -R SenseiIssei/ma
```

```bash
gh secret set ASC_KEY_P8 -R SenseiIssei/ma < "C:\Users\jakob\Downloads\AuthKey_XXXXXXXXXX.p8"
```

## 5. Bauen und installieren

GitHub > Actions > iOS > Run workflow > `testflight`.

Der Lauf archiviert, signiert automatisch, exportiert und lädt hoch. Nach etwa zehn bis zwanzig Minuten Verarbeitung bei Apple erscheint der Build in App Store Connect unter TestFlight. Dort trägst du dich als **interner Tester** ein. Auf dem iPhone installierst du die App **TestFlight** und darüber Ma.

Jeder Lauf hat ein Zeitlimit, ein hängender Build kostet also nie Stunden.

## 6. Safari-Filter einschalten

Einstellungen > Apps > Safari > Erweiterungen > Ma Filter: einschalten und für instagram.com, youtube.com, x.com, linkedin.com, facebook.com und tiktok.com erlauben.

## Grenzen des Systems

- Reels in der nativen Instagram-App lassen sich nicht ausblenden. Keine App darf in eine andere hineingreifen. Der Weg ist die Grenze auf die App plus Instagram im Browser.
- Eine Grenze nimmt höchstens 50 einzelne Apps auf. Für mehr die Kategorie wählen.
- Ma kann nur sperren, was Bildschirmzeit sperren kann. Wer die Berechtigung in den iOS-Einstellungen entzieht, hebt alle Grenzen auf. Das ist Absicht: Aufheben soll immer möglich sein.
