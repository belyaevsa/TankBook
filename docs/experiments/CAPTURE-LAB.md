# Capture lab – experiment results

*The results log of the `captureLab` beta experiment (`docs/CONFIG.md` → "Build channels and
experiments"). Each run is the lab's own `run.json`, committed under `capture-lab/`; the photos stay
out of git (they enter the corpus only through `corpus-intake`). A run is judged twice: by what the
phone's build committed, and by what `HEAD`'s reader commits on the same bytes - the lab's photos are
exactly what the camera delivered, minus the location.*

**The question the experiment answers:** which capture preset production should use, and whether the
reader on the phone commits what the reader in the tree commits. It ends in the owner's decision to
promote the lab, remove it, or change the production preset (SH.9).

## Run 1 – 2026-09-25, one fill, pump and receipt (daylight)

One Circle K fill in Estonia, shot on an iPhone 12 (`iPhone13,1`, the device floor) under all seven
presets: the Gilbarco Veeder-Root display (`0030,02` € / `0014,00` L at `2,144`) and its receipt
(14.00 L × 2.144 EUR/L = 30.02 EUR). Logs: `capture-lab/2026-09-25-101706-pump.json`,
`capture-lab/2026-09-25-101833-receipt.json`. The phone ran a beta build from before PU.74/PU.85.

| Preset | Capture ms (pump / receipt) | Bytes (pump) | Pump - phone build | Pump - `HEAD`, shipped detector | Pump - `HEAD`, PixelLink segmenter | Receipt - phone build |
|---|---|---|---|---|---|---|
| default (production) | 540 / 947 | 3.30 MB | **wrong** 300.16 / 14 / 21.44 | 30.02 / 14 / 2.144 | 30.02 / 14 / 2.144 | 30.02 / 14 / 2.144, lock |
| quality | 729 / 627 | 3.47 MB | **wrong** | right | refused (cell count) | right, lock |
| speed | **410 / 369** | 2.52 MB | **wrong** | right | refused | right, lock |
| metered | 610 / 606 | 3.42 MB | **wrong** | right | refused | right, lock |
| locked | 479 / 470 | 3.11 MB | nothing | right | refused | right, lock |
| zoom2x | 481 / 455 | 1.70 MB | **wrong** | right | right | right, lock |
| high1080 | 994 / 749 | 0.55 MB | **wrong** | right | refused | right, lock |

`HEAD` = 976bc82e, `pump-read` built from a clean export with the request's currency `EUR` (the app
passes the locale's; without one PU.74's table abstains as `currencyUnmeasured` on every shot).

**What it showed.**
- **The phone's build committed a wrong, self-consistent triple on 6 of 7 pump shots** - the price's
  four cells `2144` placed as 21.44, the total derived from it (14 × 21.44 = 300.16). The arithmetic
  check cannot catch it: F2's residue case. `HEAD` reads all seven right; the fix is PU.74 (measured
  per-currency conventions) and PU.85 (a placement goes with the window's cell count). One shot's
  misread digit (`7014.00` on `quality`) is repaired by the arithmetic.
- **The PixelLink segmenter (PU.76 spike) never committed a wrong number and refused 5 of 7** - its
  boxes take in an extra cell (`7003002`, `12144`), so the count is impossible. The same framing loss
  the spike measured on the corpus.
- **The receipt read right under every preset.**
- **Location stripping works on the device**: no GPS tag in any photo, the rest of the EXIF kept.
- **Presets:** every preset read the same, so the choice is cost. `speed` captured fastest on both
  scenes (−130 / −578 ms against `default`, −24 % bytes); `high1080` is smallest but slowest to capture.
  One daylight scene per kind does not show `speed` is safe at night or in glare.
- **The lab itself:** the shutter sat below the preset list, a scroll away from the preview - the
  owner could not see what was being shot while pressing it. Moved under the preview (SH.8).

**Decisions taken:** none yet on the preset. **Next runs** (the owner, with the next beta and its
shipped model): a night pump, a display in glare, a long or faded receipt. Production's preset moves
to `speed` only if those read the same (SH.9).
