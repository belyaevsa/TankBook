# Tankbook – Secrets & Data at Rest

*Where every secret lives on each tier, and what we deliberately do not defend against. Companion to `SYNC.md` (encryption stance), `API.md` (auth), `LOGGING.md` (never-log classes), `SCHEMA.md` (what is stored).*

## Threat model – stated honestly

| We defend against | How |
|---|---|
| Lost or stolen device | iOS Data Protection + Keychain accessibility classes tied to the device passcode |
| Another app on the device reading our data | App sandbox, private Keychain access group, no shared containers |
| Tokens leaking into backups or onto a second device | `…ThisDeviceOnly` Keychain classes – tokens are never in an iCloud/iTunes backup and never restore elsewhere |
| Network interception | TLS 1.2+ only, ATS enforced, no exceptions in Info.plist |
| Secrets extracted from the app binary | **There are none.** Anything shipped in an IPA is public – an IPA is a zip |
| A leaked server log revealing user data | The three logging classes (`LOGGING.md`) plus a redactor in the pipeline |

| We do **not** defend against | Why |
|---|---|
| A jailbroken/compromised device | The OS is the trust boundary. We will not ship anti-jailbreak theatre that a determined attacker bypasses in minutes and that breaks legitimate users |
| A user's own unencrypted computer backup | The local database lands in an unencrypted iTunes backup by design – it is the user's data on the user's machine. We surface the honest advice (encrypt your backup) rather than blocking restore |
| A malicious server operator | We are the operator; the promise is minimal collection and at-rest encryption, not zero-knowledge. E2E is a signed-off non-goal for v1 (`SYNC.md`) |

## iOS – what secrets exist, and where each lives

The list is deliberately short. **Every item not on it must not exist on the device.**

| Secret | Storage | Accessibility / protection |
|---|---|---|
| Access token (JWT, ~1h) | Keychain, `kSecClassGenericPassword` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Refresh token (rotating) | Keychain, separate item | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| `deviceId` (issued at sign-in) | Keychain | Same – it must survive reinstall-with-restore but never migrate to another device |
| Local database (`.sqlite` + WAL/SHM) | App container, **not** Keychain | `FileProtectionType.completeUntilFirstUserAuthentication` on all three files |
| Attachment renditions and thumbnails | App container | Same protection class |
| Nothing else | – | – |

**Why `AfterFirstUnlock…` and not `WhenUnlocked`:** background sync and silent APNs nudges (`NOTIFICATIONS.md`) run while the phone is locked; `WhenUnlocked` would break them after every reboot. `AfterFirstUnlock` keeps the data encrypted until the user has unlocked once since boot, which is the correct trade for a background-syncing app.

**Why `ThisDeviceOnly` on every item:** it keeps tokens out of iCloud Keychain and out of device backups. A second device must complete its own sign-in and register its own `deviceId` – which is exactly what makes per-device revocation (`DELETE /account/devices/{id}` → `410` on that device's next pull) meaningful. A synced session would silently defeat it. **This corrects the earlier note in `SYNC.md` that iCloud Keychain stores the session: it must not.**

**Why the local DB uses Data Protection rather than SQLCipher:** file protection is enforced by the Secure Enclave-backed keybag with a key we never see, store, or can lose. Rolling our own encryption means owning a key, and an app that can lose the key to a user's seven-year fuel history has created a bigger risk than the one it removed. If a future threat model demands app-level encryption, it arrives as an opt-in with the key in the Keychain – not as a silent default.

**What must never ship in the bundle:** LLM/API keys (this is precisely why the `/extract` gateway is server-side), S3 credentials (clients only ever receive short-lived presigned URLs), the account-hash salt, database credentials, signing keys, and any endpoint carrying credentials in the URL. The Apple/Google client identifiers *are* in the bundle – they are public identifiers, not secrets, and the token exchange is verified server-side.

**Presigned URLs** are treated as secrets in flight: never logged (`LOGGING.md` Never class), never persisted, never written into a record payload.

**The allowlist domain is still a placeholder.** No public domain is registered for the app yet, so `HostAllowlist.allowedDomain` holds a stand-in. Until a real domain is bought and set there (and in `Config.default.json`), the allowlist protects a name we do not own - which an attacker could simply register. **Release blocker**, tracked in `CONFIG.md` → Guardrails.

**The auth token is bound to the host, not to the session.** `Authorization` is attached only when the request host is on the compiled-in allowlist, enforced in the HTTP client itself. This is what makes a redirected `apiBaseUrl` (`CONFIG.md`) unable to harvest a token even if every other guardrail failed: the request simply goes out unauthenticated. Never attach credentials to "whatever base URL is currently configured".

**The feedback queue (PJ.20).** A queued case - the feedback text and an optional `replyTo` address,
held while offline or rate-limited (docs/ERRORS.md -> About & feedback) - is user content, not a
secret. It lives in a JSON file (`feedback-queue.json`) in the same `Application Support/Tankbook`
container as the database, so it inherits the same `completeUntilFirstUserAuthentication` file
protection, and it is never synced, never uploaded except through `POST /feedback`, and never logged
(hard rule 12). It is purged from the file as each case is accepted (`202`).

## Backend – secret management

| Secret | Where |
|---|---|
| Postgres connection string | Environment / platform secret store, injected at runtime |
| S3 access key + secret | Same. Never in a **committed** file – see the generation rule below |
| Apple/Google public key endpoints | Not secret; token signatures verified against fetched JWKS with caching |

### The runtime config files are generated, never committed (2026-09-01)

`backend/src/Tankbook.Api/appsettings.json` and `appsettings.Development.json` are **gitignored**.
What is committed is `appsettings.template.json` and `appsettings.Development.template.json` – the
full structure with every secret value blank – and `backend/scripts/generate-appsettings.sh`, which
renders the real files from those templates plus the environment. This repo is public, and a
credential committed to it stays in history after it is deleted: the fix for a leak is revocation,
not a follow-up commit.

Two things about it were **measured**, and both shaped the design:

- **`appsettings.json` is load bearing for the test suite, not just for a running server.** With the
  file absent, `dotnet test` **aborts after 117 of 295 tests**. So CI cannot check out and build – the
  `backend` workflow generates first, and the full sequence was verified on a tree with both files
  removed.
- **`appsettings.Development.json` is not** (295/295 without it, because the suite runs in the
  `Testing` environment). It is generated anyway so a fresh clone works in one command.

An unset variable leaves the template's blank value rather than inventing one. That is safe because
`Program.cs`'s startup guard **refuses to start outside Development** with an unset or placeholder
secret – so a half-filled file fails loudly at boot instead of serving traffic with a key printed in
this repo. **The guard does not yet cover `S3:AccessKey`/`S3:SecretKey`**: a server with wrong
credentials starts and fails at the first attachment upload instead.

**The GitHub Actions secrets** the pipeline reads, mapped in `.github/workflows/backend.yml`:

| GitHub secret | Fills | Source |
|---|---|---|
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | `S3:AccessKey` / `S3:SecretKey` | `yc iam access-key create --service-account-name tankbook-storage` |
| `TANKBOOK_HASH_SALT` | `Tankbook:Logging:HashSalt` | Generated once; rotating it re-anonymises every account id (`LOGGING.md`) |
| `CONFIG_SIGNING_KEY` | `Config:SigningKey` | The Ed25519 seed signing config documents (`CONFIG.md`) |
| `AUTH_JWT_SIGNING_KEY` | `Auth:JwtSigningKeyBase64` | Base64 PKCS#8 RSA; tokens carry `kid`, so rotation does not invalidate live sessions |
| `LLM_API_KEY` | `LlmGateway:ApiKey` | The provider key that is precisely why the gateway is server-side |
| `POSTGRES_CONNECTION` | `ConnectionStrings:Postgres` | The deployed database |

The **script is the source of truth for that list**; this table names the same variables and must be
corrected with it. None is needed by the build-and-test job – it passes with every value blank, which
is what keeps a fork's pull request green, since fork PRs receive no secrets.

`LLM_BASE_URL` and `LLM_MODEL_ID` are read by the same script but are **not secrets** – a public API
host and a model name. They are defaulted in the committed template the way `Apns:Endpoint` is, and
stay overridable so a deploy can change provider or model without a commit. Do not add them to the
secret list; a value in the secret store that nobody needs to hide is a value nobody can review.

**`CONFIG_SIGNING_KEY` is deliberately NOT set in GitHub Secrets.** The value sitting in a local
`appsettings.json` is `ConfigSigningOptions.DevPlaceholderSeed` – the committed dev placeholder,
printed in this repo. Uploading it would let a production boot sail past the startup guard using a
keypair anyone reading the repo can reproduce and forge config documents with, which is precisely
the failure the guard exists to prevent. It needs a **freshly generated** keypair whose public half
is bundled into the app (`AppConfigService.bundledConfigPublicKey`), and until that exists a Release
build's config signature fails open to bundled defaults – the open ops item `SH.1` carries.

`Auth:AppleAudiences` / `Auth:GoogleAudiences` are deliberately **not** secrets – they are public
identifiers – but they are deploy-blocking, because the audience check fails closed.

**A verified signature is not a verified identity.** Apple's and Google's JWKS sign identity tokens
for *every* client on their platforms, so a signature proves only that the provider minted the
token – never that it was minted for **us**. `POST /auth/session` therefore checks the token's
`aud` against a per-provider allowlist (`Auth:AppleAudiences`, `Auth:GoogleAudiences`) and its
`iss` against the provider's issuers, **before** reading any other claim. Without that check,
anyone shipping an app with Google or Apple sign-in can collect their own users' id tokens and
replay them here to take over the matching Tankbook account – the confused-deputy takeover.

The allowlist **fails closed**: an unconfigured audience refuses every token
(`IdTokenOutcome.AudienceNotConfigured`) rather than accepting any, so the control cannot be
switched off by forgetting to deploy a setting. `Auth:AppleAudiences` is the app's **bundle id**;
`Auth:GoogleAudiences` is the Google **OAuth client id**. Neither is `Auth:Audience`, which is a
different thing entirely – the audience stamped on the access tokens this server mints.

**Device identity: a client-supplied id is an unverified claim, never authority (RV.41).** The
`device.deviceId` the client sends with `POST /auth/session` is its stored per-install identifier
(the Keychain `deviceId`, hard rule 11). The server reuses that row only when it already belongs to
the account authenticated by the verified id token - the reuse is bound to the account id, so a
device id belonging to another account is ignored and a fresh row minted. This is the same class of
mistake as the `PR.35` audience finding: a client-provided identifier is a claim about the caller,
and the only trusted identity in a session exchange is the verified id token. The fence is pinned by
the L2 test `AccountBCannotAttachAccountAsDeviceId` - without it the fix is a cross-account
take-over. **A revoked row re-attaches when its device returns**: the owner proved the account
again by presenting a valid id token, and re-attach is what makes a revoke → re-sign-in cycle on
one phone a single row rather than two. It cannot weaken revocation - a device without the account
holder's credentials can never sign in, so a stolen phone that was revoked stays out.

**Google sign-in carries no SDK** (decided 2026-09-01). The app runs OAuth 2.0 authorization-code
with PKCE through `ASWebAuthenticationSession`: `GoogleOAuth` (core, pure, unit-tested) builds the
request and validates the callback, `GoogleWebAuthenticator` (app) presents the browser and runs
the exchange. A Google iOS OAuth client is a **public client with no secret**, so nothing here
touches the no-secrets-in-the-bundle rule; the client id ships in `Info.plist` as the public
identifier it is. Two properties are load-bearing and pinned by tests: the `code_challenge` is the
SHA-256 of the verifier (not the verifier), and a callback whose `state` does not match the one
minted is refused. The token exchange deliberately uses a bare `URLSession` rather than
`TankbookHTTPClient` – it goes to Google, which `HostAllowlist` refuses by design, and it must
carry no Tankbook bearer.
| JWT signing key | Platform secret store, rotatable; tokens carry `kid` so rotation does not invalidate live sessions |
| Account-hash salt (`LOGGING.md`) | Platform secret store, dev default only in `appsettings.Development.json` |
| LLM provider API key | Platform secret store; never leaves the gateway process |

`appsettings.json` holds only placeholders (the committed dev signing-key placeholder, empty S3/Postgres credentials); `appsettings.Development.json` holds only local-dev values (`localhost`, `tankbook`, `minio`). A CI check greps for anything resembling a real credential.

**A committed placeholder is a refusal, not a warning (PR.34).** Outside Development the server
refuses to start if the account-hash salt (`Tankbook:Logging:HashSalt`) is unset or the committed
`change-me` placeholder, if `Config:SigningKey` is unset or the committed dev placeholder, or if
`Auth:JwtSigningKeyBase64` is unset. A warning is not a refusal: a production server that boots
hashing account ids with a salt printed in this repo, or signing config documents with a keypair
anyone who reads this repo can reproduce and forge, has already lost. The refusal names the setting
and how to supply it (the same next-step rule operators get, `ERRORS.md`). Development and the test
host are exempt; real deployments are not.

**A presigned PUT is bound to what was declared, not bearer-of-the-URL (PR.18).** `POST /blobs/begin`
mints a presigned PUT that signs the declared `contentType` and `size` into the URL, so the URL
cannot be reused to upload bytes of a different kind or length for its whole lifetime. The orphan
sweep (`SweepOrphansAsync` + `DeleteStalePendingAsync`) runs hourly across all accounts, so a
never-committed upload or an unreferenced blob is cleaned up rather than filling the store forever.

## Transport

TLS 1.2+ everywhere, ATS enforced with no per-domain exceptions. **Certificate pinning is deliberately not in v1**: it buys little against a device already trusting a rogue CA (the user installed it), and a rotation mistake bricks every installed client with no remote fix. Revisit only with a proper backup-pin rotation plan.

## Enforcement – checks, not intentions

- **Bundle scan (CI):** grep the built app for high-entropy strings and known key prefixes; fail on a hit.
- **Keychain attribute test:** assert every stored item is written with `AfterFirstUnlockThisDeviceOnly` and the app's own access group – a test, because a wrong constant compiles perfectly and fails silently in the field.
- **File protection test (PR.16 / PR.16b):** the class is set explicitly, not ridden on a default - `AppStore.makeRepository` applies `completeUntilFirstUserAuthentication` to the `.sqlite`, `-wal` and `-shm` files after the database opens (the WAL and SHM files are the ones people forget - protecting only the main file leaves recent writes readable), and the attachment writers apply the same class to the attachments directory. All six appliers (the database triple, the attachment directories via `VehiclePhotoStore` and `FileBackedBlobStore`, and the `ConfigCacheFile` / `VehicleCatalogCacheFile` / `ArchiveFileIO` atomic writers) route through the single `FileProtection` seam in TankbookCore. Two test halves hold the promise. (a) **Device truth** (`TankbookTests/FileProtectionTests`, app-target bundle, L2): `resourceValues(forKeys: [.fileProtectionKey])` equals the class on all three database files and on a written attachment. This half is correct on a real device and worthless on the iOS Simulator - the simulator does not emulate data protection and reports the class as a hard constant no matter what is set - so it stays for hardware but cannot fail on the only runtime CI has. (b) **Seam** (PR.16b): the same bundle's `*Seam*` tests, plus `FileProtectionSeamTests` in the SwiftPM core suite, swap `FileProtection.applier` for a recorder and assert the promised class was applied per file - a removed applier leaves the file unrecorded and fails the test naming it; a `.none` class fails the class assert. Both halves were proved by mutation: PR.16's removal of the attribute fails (a) on hardware, and PR.16b's removal of the `setAttributes` call fails (b) on the simulator.
- **Seed-harness gate (PJ.7g):** the whole UI-test seed harness - the DB seeds, the stub
  Keychain session (`SettingsTestSeed.stubSession`, `WelcomeGate`), the seeded/offline transports
  and the config seed - is compiled under `#if DEBUG`, so a RELEASE build contains none of it and
  has no launch argument that can write a session or seed a vehicle. Hard rule 11 is the authority:
  nothing outside the real sign-in flow writes a Keychain session, and a seed that could ship would
  be a second writer. The gate is enforced two ways, so neither a stray reference nor a
  compiled-in-but-unreferenced seed can slip through: a `xcodebuild -configuration Release build`
  (a reference to a gated seed type outside `#if DEBUG` is a "cannot find type in scope" compile
  error) and `TankbookTests/ReleaseSeedGateTests`, a `#if`-aware source scan that fails when any
  enumerated seed symbol appears on a line the compiler emits in RELEASE - the case a compile alone
  cannot catch, where a seed type is gated off its call sites but still ships in the binary.
- **No-secrets-committed check (CI):** the appsettings/scripts grep above.
- **Sign-out test:** signing out removes every Keychain item and leaves the local database intact (the user keeps their log; only sync stops – `JOURNEYS.md` J11a). Since PR.2, sign-out also issues `DELETE /auth/session` **best-effort**, so a handed-over phone does not keep a 90-day refresh chain valid on the server; the Keychain clear still runs even when that request fails (offline sign-out signs out locally, hard rule 1).
- **Refresh-race serialisation (PR.1):** a `401` on any bearer endpoint triggers one in-flight refresh through a single shared `SessionRefresher` actor. The server rotates refresh tokens and revokes the chain on reuse, so two concurrent refreshes would sign the user out; the actor makes every concurrent caller await the one in-flight refresh. A rejected refresh clears the session and surfaces "sign in again", never "update the app".
- **Revocation test:** a device revoked server-side gets `410`, discards its tokens, and stops syncing without destroying local data.


## Import files at rest (added 2026-08-27)

Hard rule 9's named exception, `POST /import/parse`, is the one endpoint that reads domain
meaning - and it **stores what it is given**. That asymmetry with the LLM gateway was deliberate
and signed off until 2026-09-03, when the LLM call ledger amendment reversed it: both now store
(see "LLM call ledger" below). The import terms are written here rather than left to the
implementation.

| | `/extract` (LLM gateway) | `/import/parse` |
|---|---|---|
| Uploaded artifact | image | third-party export file (CSV etc.) |
| Written to storage | **yes, as the call ledger's prompt rendition** (amended 2026-09-03) | **yes** - blob storage, so a review can be resumed |
| Retention | **30 days** (the row survives; only the content is purged) | **30 days**, then purged |

**Why 30 days and not less.** It matches the tombstone and undo window already in the product, so
a user has one number to remember for "how long can I get it back", and a broken import reported
days later can still be diagnosed against the real input.

**What that file contains, stated plainly, because it is the reason this needs a rule at all**: an
export from a fuel-tracking app holds dates, odometer readings, amounts, stations and sometimes
coordinates - the same class of data as the entries themselves, in one document. It is stored under
the account's at-rest encryption exactly as attachments are, and under the **device identity** when
the user has no account (import must work signed out - hard rule 1's exception does not extend to
requiring a sign-in).

**Purge is a job, not a hope.** It runs on the same hosted-service pattern as the account purge
(`AccountPurgeHostedService`), and the deletion is asserted by a test the same way: a file past the
cutoff is gone, and a file inside it survives. A retention promise with no test is a promise that
quietly stops being true.

**Deleting the account deletes these too.** They are the account's data and fall under the
signed-off delete-account-deletes-everything stance.

## LLM call ledger (added 2026-09-03)

Hard rule 9's amendment: every call to an LLM gate (`/extract` today, `/agent/turn` when v2
lands) is recorded in a table, because the gateway spends real money per call on the user's behalf
and no other record of what was sent, what came back, or what it cost exists anywhere. An
unmetered, unauditable spend path was judged worse than the storage it avoids. The terms, written
here because they are commitments:

- **One row per provider call - success and failure.** The row carries caller (account and
  device), model, vendor, outcome, a success/error category, prompt and completion token counts,
  whether thinking was enabled and its response, and the cost. The unit prices are **snapshotted
  onto the row** (hard rule 3's rate-snapshot logic applied to a second kind of money): a vendor
  price rise must never silently rewrite what an earlier call cost.
- **The prompt for `/extract` is the image - measured ~774 KB on the wire, so it does not live in
  a column.** The rendition is stored in blob storage and referenced by `sha256` from the row.
  `sha256` is content-addressed, so an identical image uploaded again dedupes to the same hash -
  a weak re-identification path, accepted deliberately rather than redesigned around.
- **Retention is 30 days**, the same number as the tombstone/undo window and `/import/parse`'s
  file, so one number governs "how long can I get it back". The retention purge deletes the
  prompt/response/thinking bodies and the rendition blob; the row - the spend ledger - survives.
  Purge is a job, not a hope: it runs on the account/import purge pattern and is asserted by a
  test on both sides of the cutoff.
- **`DELETE /account` purges the content and keeps the references.** The rendition blob and the
  prompt/response/thinking bodies go; the row survives carrying timestamps, model, vendor,
  tokens, cost, outcome and the `sha256`. **`accountId` stays on the surviving row on purpose**
  (product owner, 2026-09-03): per-account cost history survives deletion, so the spend ledger
  stays intact while nothing of the user's receipt remains. This is a deliberate choice, written
  here rather than implied - the surviving row's `accountId` references an account that no longer
  exists, and that is the point.
- **No endpoint reads the ledger.** It is written by the gateway and read by no query, search or
  stats API - the ledger exists for auditing, not for serving. Hard rule 12 still governs the
  logs: the table stores content by this explicit amendment, but the logs carry only ids, counts,
  durations, model ids and outcome codes - never a prompt, a response body, a station, an amount
  or an image.

## The delivery outbox (added 2026-09-04)

Hard rule 9's third amendment. A result the gateway computed but could not hand back - the client
vanished mid-request, which production shows as nginx `499` - is queued for the device that asked
for it and deleted once collected. It exists **because** the ledger must stay write-only: the
obvious fix is to let the device read its answer back from `llm_calls`, and RV.33's amendment
says the ledger is *"written by the gateway and read by no endpoint"* - turning the audit record
into a delivery channel reverses that days after it was written. The outbox is a separate, opaque,
per-device queue instead.

The terms, written here because they are commitments:

- **Opaque bytes addressed to a device.** The row is `{ id, account_id, device_id, payload,
  created_at }`, and `payload` is the extract response plus the device's own correlation token,
  stored as `bytea`. The server never reads a field of it, never queries by meaning, and offers
  no search or stats over it - the same shape as `GET /blobs/{sha256}`: retrieve-what-you-are-
  entitled-to.
- **Drain-and-ack, at-least-once.** `GET /v1/outbox` drains without deleting; `DELETE
  /v1/outbox/{id}` acks one collected row. A device that dies between read and ack re-drains the
  same rows and dedupes by row id, so a redelivered answer never becomes a second item. A row is
  deleted once collected, never re-delivered forever.
- **Retention is 30 days**, the same number as the tombstone/undo window, `/import/parse`'s file
  and the call ledger's content, so one number governs "how long can I get it back". Purge is a
  job, not a hope - the same hosted-service pattern as the other purges, asserted by a test on
  both sides of the cutoff.
- **Requires an account** (so does `/extract`): a guest never has an outbox. **`DELETE /account`
  purges it**, like every other content store - the `account_id` foreign key cascades, and the
  account purge also deletes the rows explicitly, which is the tested guarantee.
- **Nothing is logged but shape** (hard rule 12): counts, ids, outcome codes, a byte count.
  Never a payload, never a domain value. The three log events are `outbox.enqueue`,
  `outbox.drain` and `outbox.purge`.
- **It licenses nothing further.** A result that arrives here is a *suggestion* - the device
  feeds it through the same inbox policy as any in-process late answer, and an answer whose entry
  was never saved is acked and dropped. No screen is gated on the outbox (hard rule 1).

## Passphrase-protected exports (added 2026-08-27)

A user-held per-car archive (`docs/SCHEMA.md` -> Backup format) can be passphrase-protected at
export time - **never required** (a mandatory user-held key is a way to lose your own data). The
terms, written here because the choice of KDF is a security decision:

- **`manifest.json` is never sealed.** It must open for the restore UI before the passphrase is
  known; `passphraseProtected: true` in the manifest is what tells the reader data.json is sealed.
- **AES-GCM (CryptoKit)** seals `data.json` as one box and each attachment blob as its own box.
  Every box embeds its own random 16-byte salt, so the same passphrase can seal any number of files
  without reusing a nonce, and each file is self-contained.
- **Key derivation is PBKDF2-SHA256, 100 000 iterations, 32-byte key** (CommonCrypto's
  `CCKeyDerivationPBKDF`). PBKDF2 over HKDF because the input is a human passphrase - a KDF with
  an iteration count is the right tool, not a key-expansion shortcut. A wrong passphrase (or a
  tampered box) fails GCM authentication and is reported as `wrong_passphrase` - the app cannot
  and should not distinguish the two.
- **The passphrase never leaves the device.** Sealing and opening happen in `ArchiveCrypto` in
  TankbookCore; there is no server round-trip and no passphrase is ever logged (hard rule 12).
  The passphrase itself is never stored - forgetting it is losing the archive, which is the trade
  an optional passphrase exists to make.

