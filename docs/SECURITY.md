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

`appsettings.json` holds empty placeholders; `appsettings.Development.json` holds only local-dev values (`localhost`, `tankbook`, `minio`). A CI check greps for anything resembling a real credential.

## Transport

TLS 1.2+ everywhere, ATS enforced with no per-domain exceptions. **Certificate pinning is deliberately not in v1**: it buys little against a device already trusting a rogue CA (the user installed it), and a rotation mistake bricks every installed client with no remote fix. Revisit only with a proper backup-pin rotation plan.

## Enforcement – checks, not intentions

- **Bundle scan (CI):** grep the built app for high-entropy strings and known key prefixes; fail on a hit.
- **Keychain attribute test:** assert every stored item is written with `AfterFirstUnlockThisDeviceOnly` and the app's own access group – a test, because a wrong constant compiles perfectly and fails silently in the field.
- **File protection test:** after opening the database, assert the protection attribute on the `.sqlite`, `-wal` and `-shm` files (the WAL and SHM files are the ones people forget – protecting only the main file leaves recent writes readable).
- **No-secrets-committed check (CI):** the appsettings/scripts grep above.
- **Sign-out test:** signing out removes every Keychain item and leaves the local database intact (the user keeps their log; only sync stops – `JOURNEYS.md` J11a).
- **Revocation test:** a device revoked server-side gets `410`, discards its tokens, and stops syncing without destroying local data.
