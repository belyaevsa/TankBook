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
