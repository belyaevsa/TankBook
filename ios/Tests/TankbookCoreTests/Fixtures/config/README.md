# Config canonicalization + signature parity fixture

Generated 2026-08-23 by running the **real server-side semantics** (`backend/src/Tankbook.Api/Config/ConfigCanonicalizer.cs`
plus BouncyCastle Ed25519, the same library `ConfigSigner` uses) over `parity.document.json`,
then verifying the result in Swift CryptoKit. Both directions were checked; both negative
controls (tampered document byte, tampered signature byte) were rejected.

This closes the cross-language question that cost three agent runs. **Do not re-investigate
whether BouncyCastle and CryptoKit agree on Ed25519 – they do, and this fixture is the evidence.**
The real risk was always canonicalization, which is what these bytes pin down.

| File | What it is |
|---|---|
| `parity.document.json` | Source document, **keys deliberately out of lexicographic order**, as a server might serve it |
| `parity.canonical.json` | Expected canonical bytes – exactly 788 bytes, **no trailing newline** |
| `parity.signature.b64` | Ed25519 signature over `parity.canonical.json`, base64 |
| `parity.publickey.b64` | Matching 32-byte public key, base64 |

## What this fixture deliberately exercises

- **`1e3` stays `1e3`** and **`9007199254740993` stays exact** (it is above 2^53). Canonicalization
  rule 5 emits each number as its *source token*; anything that round-trips numbers through `Double`
  produces different bytes here and every signature check fails. This is the trap.
- **Cyrillic maintenance text is emitted as raw UTF-8**, not `\uXXXX` escapes
  (`JavaScriptEncoder.UnsafeRelaxedJsonEscaping`).
- Keys sorted **ordinal** at every nesting level, including inside `flags` and `unknownFutureKey.nested`.
- An empty object, a mixed-type array (order preserved – JSON defines no canonical array order),
  and an unknown top-level key that must survive.

## Test-only key

The signing seed is bytes `0x01..0x20` (`AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=`). It is a
fixture key with no production meaning and is deliberately reproducible. The **real** public key is
bundled in the app binary; it is never fetched at runtime, because an attacker who can move
`apiBaseUrl` could otherwise serve their own (`docs/CONFIG.md` → "Threat: the cache file is tampered with").

## Regenerating

The generator is not checked in – it was a throwaway console project. To rebuild: canonicalize
`parity.document.json` with `ConfigCanonicalizer.Canonicalize`, sign the bytes with an
`Ed25519Signer` over the seed above, and write the three outputs. Any change to these bytes means
the canonicalization contract changed, which is a **breaking change for every deployed client** and
needs the same review as an API change.
