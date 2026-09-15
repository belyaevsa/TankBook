# App Review reply – 2026-09-15 (v1.0, build 1344)

*The text below goes verbatim into the App Store Connect reply AND into App Review Information →
Notes. Bracketed items are for the product owner to fill before sending. Companion to `STORE.md` §5
and §6, which carry the reasoning behind every claim here; the two must never disagree.*

---

Thank you for the review. Below is the information requested, in the order asked. The same text is
now in the Notes field of App Review Information.

## 1. Screen recording

A screen recording from a physical iPhone [model] running iOS [version] is attached: [link or
attachment name]. It starts at app launch and shows, in this order:

1. First launch with an empty garage, adding a car (no account needed).
2. Logging a fill-up two ways: photographing a fuel receipt (the reading pre-fills the form, the user
   confirms) and typing one by hand.
3. Home, the log and Trends showing the cost and consumption figures derived from those entries.
4. Logging a service visit from a photographed workshop invoice, and a reminder created from it.
5. Export from Settings → Your data (works with no account, always free).
6. **Sign in** (Settings → Sign in → Sign in with Apple), which is also registration – there is no
   separate sign-up. Sync then runs against our backend.
7. **Account deletion** (Settings → Account → Delete account), in-app, with the confirmation and the
   30-day grace period stated on screen. Local data stays on the phone.
8. Sign out.

The app has no user-generated content shared between users (nothing a user writes is shown to
anyone else, so there is no reporting or blocking mechanism – see §5 of our notes on age rating), and
no paid content or features in this version.

## 2. Purpose and audience

Tankbook is a personal car cost log for drivers who keep their own car: fuel, service, parts and
other expenses, with consumption and cost-per-kilometre derived from what they record. The problem it
solves is that this history is usually kept nowhere, or kept in an app that loses it on a phone
change or locks it behind a subscription. Tankbook is **local-first**: every feature works without an
account or a network connection, the data lives on the device, and export is always available and
free. Capturing a receipt with the camera reduces typing; typing remains an equal
path. An optional account adds sync and restore across the user's own devices.

Target audience: private car owners, 18+, in Europe and the English- and Russian-speaking markets
(the app ships in English and Russian). Rated 4+; no ads, no tracking, no in-app purchases.

## 3. Setting up and accessing the main features

No credentials are required. The app is fully functional signed out; sign-in is optional and only
enables sync between the user's devices.

- **First run**: tap "Add a car", pick a make/model or type one, save. The Home screen and the
  capture button are then live.
- **Log a fill-up**: the centre button opens the camera for a receipt, or use "Type it"
  from the Home header for the manual form. Any values a scan pre-fills are editable before saving.
- **Log a service, expense, reminder**: same capture button, or Home header → Type it → Service /
  Expense; reminders live in Garage → the car → Reminders.
- **Import from another app** (Settings → Your data → Import): a sample file is attached –
  `sample-import-fuel.csv` (My Fuel Manager format). Import parsing is the one feature that needs a
  connection; the review and commit happen on the device.
- **Sign in** (Settings → Sign in): Sign in with Apple or Google, with the reviewer's own Apple ID –
  signing in creates the account, there is no separate registration and no demo account is needed.
  [Optional: a Google test account – email / password – if a Google flow needs to be exercised
  without a reviewer's own Google account.]
- **Delete the account**: Settings → Account → Delete account.
- **Cloud reading**: photographed documents are also read by a cloud model when the phone is online
  (Settings → Reading shows the setting and the daily quota). This is on by default and needs no
  setup.

## 4. External services

- Sign in with Apple and Google Sign-In (OAuth 2.0 with PKCE, no SDK) – optional account creation
  and sign-in; both offered side by side.
- Our own backend at `api.tankbook.live` (ASP.NET Core, PostgreSQL, S3-compatible storage, hosted at
  [provider, region]) – sync and restore of the user's own records and receipt images, account
  management. Used only when signed in; the server validates structure and does not interpret the
  user's data.
- DeepSeek vision model, called through our backend – reads a photographed receipt or invoice into
  form fields. API keys stay server-side; images are kept 30 days for auditing, then purged.
- European Central Bank and Bank of Russia public reference rates – currency conversion, fetched by
  our backend.
- Apple Push Notification service – silent sync nudges when signed in; reminder notifications are
  local.

No analytics, advertising, crash-reporting or payment SDKs.

## 5. Regional differences

None. The app functions identically in every region. It is localised in English and Russian (the
language follows the device setting), and currency and units default from the device locale and are
editable by the user. No content is region-gated and no feature is enabled or disabled by region.

## 6. Regulated industry / protected material

Not applicable. The app is not in a regulated industry and contains no third-party protected
material. Car makes and models appear as plain text (nominative use); exchange rates are public
central-bank data, credited in the app. Encryption: only Apple frameworks (CryptoKit, CommonCrypto)
for an optional passphrase-protected export; `ITSAppUsesNonExemptEncryption` is `false`.

## On the common issues

- **2.1 access**: no account is required for any feature; sign-in uses the reviewer's own Apple ID
  and creates the account. [A Google test account is provided above if required.]
- **2.3.3 screenshots**: the store screenshots show the app in use (Home, capture, Trends, Garage).
- **3.1.1 In-App Purchase**: this version has no in-app purchases and declares none.
- **3.2**: the app is for the general public, not for a specific business.
