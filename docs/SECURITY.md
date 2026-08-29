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

## Backend – secret management

| Secret | Where |
|---|---|
| Postgres connection string | Environment / platform secret store, injected at runtime |
| S3 access key + secret | Same. Never in `appsettings*.json` |
| Apple/Google public key endpoints | Not secret; token signatures verified against fetched JWKS with caching |
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
- **File protection test:** after opening the database, assert the protection attribute on the `.sqlite`, `-wal` and `-shm` files (the WAL and SHM files are the ones people forget – protecting only the main file leaves recent writes readable).
- **No-secrets-committed check (CI):** the appsettings/scripts grep above.
- **Sign-out test:** signing out removes every Keychain item and leaves the local database intact (the user keeps their log; only sync stops – `JOURNEYS.md` J11a).
- **Revocation test:** a device revoked server-side gets `410`, discards its tokens, and stops syncing without destroying local data.


## Import files at rest (added 2026-08-27)

Hard rule 9's named exception, `POST /import/parse`, is the one endpoint that reads domain
meaning - and unlike the LLM gateway it **stores what it is given**. That asymmetry is deliberate
and signed off, so the terms are written here rather than left to the implementation.

| | `/extract` (LLM gateway) | `/import/parse` |
|---|---|---|
| Uploaded artifact | image | third-party export file (CSV etc.) |
| Written to storage | **never** | **yes** - blob storage, so a review can be resumed |
| Retention | none (transient) | **30 days**, then purged |

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

