# Setup

Go through this once. After that, one click in GitHub Actions builds a new TestFlight version. All of it happens in the browser; you never need a Mac.

The identifiers below are the ones this repo uses. If you fork it, replace `com.sensei.ma`, the team ID in `project.yml` and `ci/ExportOptions.plist` with your own.

## 1. Identifiers in the developer portal

Certificates, Identifiers & Profiles > Identifiers.

**App Group:** switch the filter in the top right to "App Groups", `+`, description `Ma`, identifier `group.com.sensei.ma`.

**Five App IDs** (filter on "App IDs", `+`, App, bundle ID "Explicit"):

| Description | Bundle ID | App Groups | Family Controls |
|---|---|---|---|
| Ma | `com.sensei.ma` | yes | yes |
| Ma Shield | `com.sensei.ma.shieldconfig` | yes | yes |
| Ma Action | `com.sensei.ma.shieldaction` | yes | yes |
| Ma Monitor | `com.sensei.ma.monitor` | yes | yes |
| Ma Filter | `com.sensei.ma.filter` | yes | no |

Then open each ID, click **Configure** next to App Groups, assign `group.com.sensei.ma` and save.

You do not create certificates or provisioning profiles. The build makes them itself.

## 2. Request Family Controls distribution

Without Apple's approval the Screen Time API only works in development builds, and TestFlight fails at signing.

Request it in the **Capability Requests** tab of each App ID, or through https://developer.apple.com/contact/request/family-controls-distribution, once for every ID that uses Family Controls (all except `.filter`).

The honest reason is enough: an app you use to block social media for yourself, which asks a learning question before unlocking. Apple usually answers within one or two weeks.

## 3. App Store Connect

- **Accept the license agreement** if a yellow banner shows at the top. Otherwise uploads get rejected.
- **Create the app:** Apps > `+` > New App, iOS, bundle ID `com.sensei.ma`, SKU `ma`. The store name must be unique; plain "Ma" is taken.
- **API key:** Users and Access > Integrations > App Store Connect API > Team Keys > `+`, role **Admin**. With fewer rights Xcode is not allowed to create certificates. The `.p8` file can only be downloaded once. Note down the Key ID and the Issuer ID.

## 4. Repository secrets

Each command asks for the value without echoing it:

```bash
gh secret set ASC_KEY_ID -R SenseiIssei/ma
```

```bash
gh secret set ASC_ISSUER_ID -R SenseiIssei/ma
```

```bash
gh secret set ASC_KEY_P8 -R SenseiIssei/ma < "C:\Users\you\Downloads\AuthKey_XXXXXXXXXX.p8"
```

## 5. Build and install

GitHub > Actions > iOS > Run workflow > `testflight`.

The run archives, signs automatically, exports and uploads. After ten to twenty minutes of processing at Apple the build shows up in App Store Connect under TestFlight. Add yourself there as an **internal tester**, install the **TestFlight** app on the iPhone and install Ma through it.

Every job has a time limit, so a hanging build never costs hours.

## 6. Switch on the Safari filter

Settings > Apps > Safari > Extensions > Ma Filter: switch it on and allow it for instagram.com, youtube.com, x.com, linkedin.com, facebook.com and tiktok.com.

## Limits of the system

- Reels inside the native Instagram app cannot be hidden. No app may reach into another one. The way around is a boundary on the app plus Instagram in the browser.
- One boundary holds at most 50 individual apps. For more, pick the category.
- Ma can only block what Screen Time can block. Revoking the permission in iOS Settings lifts every boundary. That is on purpose: letting go should always be possible.
