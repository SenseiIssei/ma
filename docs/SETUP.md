# Einrichtung

Einmal durchgehen, danach baut jeder Knopfdruck in GitHub Actions eine neue Version. Alles davon geht im Browser, ein Mac wird nie gebraucht.

## 1. Family Controls bei Apple beantragen

Ohne Apples Freigabe gibt es die Bildschirmzeit-Schnittstelle nur für Development-Builds. Die reichen für das eigene iPhone, aber nicht für TestFlight oder den App Store.

Antrag: https://developer.apple.com/contact/request/family-controls-distribution

Einmal pro Bundle-ID stellen, die Family Controls nutzt:

- `com.sensei.ma`
- `com.sensei.ma.shieldconfig`
- `com.sensei.ma.shieldaction`
- `com.sensei.ma.monitor`

Als Begründung reicht die ehrliche: eine App, mit der man sich selbst Social Media sperrt und vor dem Entsperren eine Lernfrage beantwortet. Apple antwortet meist innerhalb von ein bis zwei Wochen. Bis dahin läuft Schritt 5 mit dem `device`-Build.

## 2. App Group und Capabilities im Developer-Portal

Die App Store Connect API kann keine App Groups anlegen, das ist der einzige Handgriff im Portal.

1. https://developer.apple.com/account/resources/identifiers/list/applicationGroup öffnen, `+`, App Group `group.com.sensei.ma` anlegen.
2. Den Workflow einmal mit `device` starten (Schritt 4). Der Lauf legt die fünf Bundle-IDs an und schaltet an, was die API anschalten kann. Er darf beim Signieren noch scheitern.
3. Jede der fünf IDs öffnen (`com.sensei.ma`, `.shieldconfig`, `.shieldaction`, `.monitor`, `.filter`):
   - **App Groups** anhaken, auf "Configure" und `group.com.sensei.ma` zuweisen.
   - Bei allen außer `.filter`: **Family Controls (Development)** anhaken. Nach Apples Freigabe steht dort zusätzlich die Distribution-Variante.

## 3. Secrets im Repo

Unter Settings > Secrets and variables > Actions. Die ersten sechs sind dieselben wie bei Lovebyte, der match-Speicher `Lovebyte-certs` kann weiterverwendet werden.

| Secret | Inhalt |
|---|---|
| `ASC_KEY_ID` | Key ID des App Store Connect API Keys |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | Inhalt der `.p8`-Datei |
| `MATCH_PASSWORD` | Passwort, mit dem match die Zertifikate verschlüsselt |
| `MATCH_GIT_URL` | `https://github.com/SenseiIssei/Lovebyte-certs.git` |
| `MATCH_GIT_TOKEN` | GitHub-Token mit Lese- und Schreibrecht auf dieses Repo |
| `DEVICE_UDID` | UDID des iPhones (siehe unten) |
| `DEVICE_NAME` | optional, Name für das Gerät im Portal |

Mit der GitHub CLI geht das auch so, der Wert wird dann abgefragt statt in der Shell-History zu landen:

```bash
gh secret set DEVICE_UDID -R SenseiIssei/ma
```

**UDID unter Windows finden:** iPhone per Kabel anschließen, die App "Apple Geräte" (oder iTunes) öffnen, auf das Gerät gehen und so lange auf die Seriennummer klicken, bis die UDID erscheint. Rechtsklick kopiert sie.

## 4. Bauen

GitHub > Actions > iOS > Run workflow, dann `lane` wählen:

- `check`: kompiliert nur. Läuft ohnehin bei jedem Push.
- `device`: signierte Development-IPA. Liegt danach unter dem Lauf als Artifact `Ma-device-<nummer>`.
- `testflight`: App-Store-Build nach TestFlight. Erst nach Schritt 1, und nachdem in App Store Connect eine App mit der Bundle-ID `com.sensei.ma` angelegt wurde.

Jeder Lauf hat ein Zeitlimit, ein hängender Build kostet also nie Stunden.

## 5. Development-Build aufs iPhone

Die IPA ist für genau das iPhone mit der hinterlegten UDID signiert. Drei Wege von Windows aus:

- **ideviceinstaller** (libimobiledevice, Open Source): `ideviceinstaller -i Ma.ipa` bei angeschlossenem iPhone.
- **3uTools** oder **iMazing**: IPA auf das Gerät ziehen. Wichtig ist nur, dass das Tool nicht neu signiert, sonst fehlt die Family-Controls-Berechtigung.
- **Über eine eigene HTTPS-Seite** mit `itms-services`-Link und `manifest.plist`, falls das iPhone nicht am PC hängen soll.

Danach auf dem iPhone unter Einstellungen > Datenschutz & Sicherheit den **Entwicklermodus** einschalten, neu starten, fertig.

## 6. Safari-Filter einschalten

Einstellungen > Apps > Safari > Erweiterungen > Ma Filter: einschalten und für instagram.com, youtube.com, x.com, linkedin.com, facebook.com und tiktok.com erlauben.

## Grenzen des Systems

- Reels in der nativen Instagram-App lassen sich nicht ausblenden. Keine App darf in eine andere hineingreifen. Der Weg ist die Grenze auf die App plus Instagram im Browser.
- Eine Grenze nimmt höchstens 50 einzelne Apps auf. Für mehr die Kategorie wählen.
- Ma kann nur sperren, was Bildschirmzeit sperren kann. Wer die Berechtigung in den iOS-Einstellungen entzieht, hebt alle Grenzen auf. Das ist Absicht: Aufheben soll immer möglich sein.
