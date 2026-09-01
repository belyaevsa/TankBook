# Tankbook - App Store submission metadata

*What goes where for an App Store release. Companion to `docs/SITE.md` (the URLs
below are pages that exist and are live), `docs/SECURITY.md` and `docs/LOGGING.md`
(what the privacy answers must be true to), and `docs/TASKS.md` P6.6.*

## The distinction that saves a rejection

**Almost none of the listing lives in this repo.** Name, subtitle, description,
keywords, category, age rating, screenshots, the support and marketing URLs and
the privacy answers are all **App Store Connect** fields, typed into the web UI.
What the repository controls is narrow and exact:

| In the repo | Where |
|---|---|
| Bundle version and build number | `project.yml` -> `info.properties` |
| Permission usage strings | `project.yml` -> `info.properties` |
| Export-compliance answer | `project.yml` -> `ITSAppUsesNonExemptEncryption` |
| **Privacy manifest** | `ios/App/Resources/PrivacyInfo.xcprivacy` |

Everything else below is prepared text to paste into App Store Connect.

## URLs - all live as of 2026-08-28

| App Store Connect field | Value |
|---|---|
| Marketing URL | `https://tankbook.live/` |
| Support URL | `https://tankbook.live/support/` |
| Privacy Policy URL | `https://tankbook.live/privacy/` |
| Terms (EULA, optional) | `https://tankbook.live/terms/` |
| Account deletion (**required** when the app supports accounts) | `https://tankbook.live/delete-account/` |

The deletion URL is not optional politeness: Apple requires an app offering
account creation to document deletion, and to offer it in-app. Ours is a
tombstone - devices learn via `410` and the local log stays on the phone - and
`/delete-account/` says exactly that in both languages.

## The privacy answers must agree in THREE places

App Store review compares them, and a mismatch is what gets caught:

1. `ios/App/Resources/PrivacyInfo.xcprivacy` (in this repo)
2. The App Store Connect privacy questionnaire
3. `https://tankbook.live/privacy/`

The manifest declares, and the other two must match:

- **No tracking**, and no tracking domains. There is no ad SDK, no analytics SDK
  and no third-party network call in the app at all.
- **Email address** - collected **only** when the user signs in, which is
  optional. Linked to the user, App Functionality, not tracking.
- **Other user content** (the synced record stream: vehicles, fill-ups, services,
  expenses) - same conditions.
- Nothing at all is collected from a signed-out user. The app is fully usable
  with no account and the local database is authoritative (hard rule 1).
- **Required-reason API**: `UserDefaults`, reason **CA92.1** (the app's own
  preferences). The other four categories - file timestamps, disk space, system
  boot time, active keyboards - were checked against the source and are genuinely
  unused, so they are correctly absent rather than defensively listed.

## Two answers to verify before the first submission

**`ITSAppUsesNonExemptEncryption: false`.** Currently set, and defensible: the app
uses HTTPS/TLS provided by the OS, Keychain, and file protection - all standard
exempt uses. It also verifies an Ed25519 signature on the config document, which
is authentication rather than data encryption. **This is a legal declaration, so
confirm it deliberately rather than inheriting it.** If in doubt, France's
declaration requirement is the usual reason to answer differently.

**`UIBackgroundModes` is deliberately NOT set.** `docs/NOTIFICATIONS.md` specifies
silent APNs nudges, which need `remote-notification` - but the client half is not
implemented (nothing calls `registerForRemoteNotifications`), and **declaring a
background mode the app does not use is itself a rejection reason**. Add
`remote-notification` in the same change that wires silent push, not before.

## What is still missing for a submission

- **An App Store id.** Until one exists, the in-app update button stays hidden
  behind an empty `appStoreId` and the site emits no `apple-itunes-app` banner -
  both deliberate, so nothing links to a page that does not exist.
- **Screenshots** at the required device sizes, EN and RU. The repo's
  `design/screenshots/` set is engineering evidence, not store art: it is
  captured at one size and carries a simulator status bar.
- **The listing copy itself**, which is bound by `docs/SITE.md`'s copy rule -
  never "zero typing", never "automatic" as the headline verb. The corpus numbers
  that forced that rule apply on a store page exactly as they do on the landing
  page, and a store listing is harder to correct than a website.
- **Age rating, category** (Finance or Travel - decide deliberately; the category
  affects who finds it), and the export-compliance answer above.

## Release checklist (written 2026-08-30 for SH.2; the "why" is the point of each line)

The Apple developer portal has three doors – **Certificates, IDs & Profiles**, **App Store
Connect**, **Services** – and each artefact has exactly one home. Nothing store-related is typed
twice, and nothing that lives in this repo is re-declared on the portal by hand.

### 1 · Certificates, IDs & Profiles (identity – once per app, rarely touched)

| Step | Where | Why |
|---|---|---|
| **Identifier**: register the App ID `app.tankbook.Tankbook` (explicit, not wildcard) | Identifiers → App IDs | The bundle id in `project.yml` (`bundleIdPrefix: app.tankbook`) is the app's identity everywhere: builds, TestFlight, the store record, Sign in with Apple's `aud` claim. It cannot change after the first upload |
| Enable the **Sign in with Apple** capability on that App ID | Identifiers → the App ID → Capabilities | The app signs in with `ASAuthorizationController` only (`AppIDTokenProvider.swift`); without the capability the request fails at runtime, and the entitlement must match |
| Do **not** enable Push Notifications, Background Modes, Associated Domains yet | – | Nothing in the app calls `registerForRemoteNotifications`; declaring what the app does not use is a rejection reason (`UIBackgroundModes` note above). PR.20 adds push and the capability together |
| **Certificates**: none by hand | Certificates | Let Xcode manage them (automatic signing). The distribution certificate is created on first archive with the team selected. Manual certificates only for CI (SH.2's later half) |
| **Profiles**: none by hand | Profiles | Same – automatic signing generates the App Store profile. Manual profiles rot |
| **Devices**: add your iPhone 12 (the iOS 18 floor device) and the phone you test on | Devices | Development builds and ad-hoc installs need the UDID registered; TestFlight builds do not |
| **Keys**: one **App Store Connect API key** (role App Manager), stored in the platform secret store – never in the repo | Keys | Lets `xcodebuild -exportArchive` / `altool` upload without a session; needed the day CI uploads builds. Not needed for a first manual upload from Xcode |

Repo side of this section: `project.yml` gets `DEVELOPMENT_TEAM: <team id>`, `CODE_SIGN_STYLE: Automatic`, and an entitlements file `ios/App/Tankbook.entitlements` carrying `com.apple.developer.applesignin = [Default]`. All three are committed – an IPA is a zip and none of these is a secret.

### 2 · App Store Connect (the listing and the builds)

| Step | Where | What you type, and its source of truth |
|---|---|---|
| **Create the app record**: name `Tankbook`, primary language English, bundle id from step 1, SKU `tankbook-ios` | Apps → + | The App Store id this creates goes into `AppConfigService.compiledAppStoreID` and the site's `params.appStoreId` – the two places that deliberately stay empty until it exists |
| **App Information**: subtitle, category (Finance vs Travel – decide; see above), content rights, age rating questionnaire, Privacy Policy URL `https://tankbook.live/privacy/` | App Information | Copy comes from this document; the URL from the live site |
| **Pricing**: Free, all territories except where you decide otherwise | Pricing and Availability | `VISION.md`: free tier fully usable; Pro is v2 |
| **App Privacy** questionnaire | App Privacy | Must agree with `PrivacyInfo.xcprivacy` (in the build) and `tankbook.live/privacy/` – the three-way rule above. Data collected: email (account, when signed in), device id, the synced records; none for tracking; none linked to identity beyond the account itself |
| **Localizations**: add Russian; description, keywords, promotional text, What's New – EN and RU | Version → Localizable | Copy bound by `SITE.md`'s rule: never "zero typing", never "automatic" as the verb; never name the QR (VISION, 2026-08-30) |
| **Screenshots**: 6.9" (1320×2868) required; 6.5" optional; EN and RU sets | Version → App Previews and Screenshots | **Not the `design/screenshots/` files** – those are engineering evidence at one size with a simulator status bar. Store art is captured on the iPhone 17 Pro Max simulator with `simctl status_bar override` (9:41, full battery), dark theme, from the same seeds the capture script uses, and kept under `design/store/` so they are reproducible |
| **App icon** | – | Nothing to upload: App Store Connect reads the 1024 px icon from the build's asset catalog (`AppIcon.appiconset`). The generated alternative stays in `design/brand/alt-pistol-plug/` and is not uploaded |
| **Support URL / Marketing URL** | Version | `https://tankbook.live/support/` · `https://tankbook.live/` |
| **Export compliance** | Version → build → compliance | Answered once by `ITSAppUsesNonExemptEncryption: false` in the build; confirm the legal declaration deliberately (above) |
| **Sign-in demo account** for App Review | Version → App Review Information | Review must be able to exercise Sign in with Apple; provide notes that the app is fully usable without an account, and that sync needs the backend (SH.1) to be up during review |
| **TestFlight**: internal group (you, the floor device), then external with Beta App Review; "What to Test" per build | TestFlight | Internal testers get the build minutes after upload; external needs a review pass. The launch-readiness walk (SH.3) runs on the TestFlight build, not on a debug install |

### 3 · Services

Nothing today. **Push Notifications** and **CloudKit** stay untouched (no push client yet; CloudKit was rejected by decision – the backend is the sync hub). **Xcode Cloud** is an option for SH.2's CI half but the self-hosted runner that builds the site is the current plan.

### 4 · Repo side, before the first archive

1. `project.yml`: `DEVELOPMENT_TEAM`, automatic signing, the entitlements file; `CFBundleVersion` becomes a build number that increases on every upload (the archive step sets it from a counter or the commit count – App Store Connect rejects a reused build number).
2. `xcodegen generate && xcodebuild -scheme Tankbook -configuration Release archive -archivePath build/Tankbook.xcarchive`, then `-exportArchive` with `method: app-store-connect` and upload (Xcode Organizer or `xcrun altool`/the API key). Record the exact commands in `scripts/release.sh` so SH.2 has one documented path.
3. Backend (SH.1): set **`Auth:AppleAudiences`** to the bundle id (`app.tankbook.Tankbook`) and **`Auth:GoogleAudiences`** to the Google iOS OAuth client id. These are the audiences of *incoming* Apple/Google id tokens, and they **fail closed** – until they are set, `POST /auth/session` refuses every sign-in with `AudienceNotConfigured`, so this is a deploy-blocking setting rather than a hardening nicety. Do **not** confuse either with `Auth:Audience`, which is the audience stamped on the access tokens this server mints and is unrelated (that conflation is what this line said until 2026-09-01, and following it would have changed our own token audience while validating nothing). Google *is* wired in the app as of SH.4 – set `TANKBOOK_GOOGLE_CLIENT_ID` at build time, or the Sign in screen ships with the Apple button alone.
4. After the record exists: the App Store id into `compiledAppStoreID`, the site `params.appStoreId`, and `CONFIG.md`'s `appUpdate` document.

### 5 · Why in this order

Identity first because the bundle id and the Sign in with Apple capability are immutable inputs to everything after; the store record second because it yields the App Store id the app and the site are waiting for; the archive last because it is the only step that can be repeated freely. Screenshots and copy can be prepared in parallel with all of it – they are typed into App Store Connect, never built.
