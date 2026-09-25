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

**Decisions taken:** none yet on the preset (see Runs 2-3: the latency finding did not hold). **Next runs** (the owner, with the next beta and its
shipped model): a night pump, a display in glare, a long or faded receipt. Production's preset moves
to `speed` only if those read the same (SH.9).

## Runs 2-3 – 2026-09-25, two displays the reader has never read (daylight)

Two more pump runs on the iPhone 12, same seven presets. **Run 2** (`capture-lab/2026-09-25-151248-pump-tft.json`):
the Tokheim at Terminal whose numbers are drawn on a **TFT screen** - rendered digits beside a
cycling advert, the fill in the corpus as `pump-337` (72,80 / 35,00 at 2,080). **Run 3**
(`capture-lab/2026-09-25-165315-pump-black-lcd.json`): the Neste **black-LCD board head**, pump 3,
the fill in the corpus as `pump-339` (29,99 / 15,31, no transaction price), through reflections.

| Preset | Run 2 capture ms | Run 2 - phone build | Run 3 capture ms | Run 3 - phone build | Both runs - `HEAD`, RowSeg | Both runs - `HEAD`, the previous object detector |
|---|---|---|---|---|---|---|
| default | 555 | **wrong**: 2.08 L at 35 €/L (litres and price swapped, 72.80 closes) | 628 | nothing | nothing | nothing |
| quality | 953 | right 72.80 / 35 / 2.08 | 1476 | **wrong**: 1 L | nothing | nothing |
| speed | 958 | total and price right, no litres | 1364 | **wrong**: 1 L | nothing | nothing |
| metered | 671 | nothing | 1290 | **wrong**: 1 L | nothing | nothing |
| locked | 469 | nothing | 600 | **wrong**: 1 L | nothing | nothing |
| zoom2x | 517 | nothing | 643 | nothing | nothing | nothing |
| high1080 | 786 | total only | 975 | nothing | nothing | nothing |

`HEAD` = 670d71e9 (RowSeg shipped, PU.86/PU.88 in), `pump-read` from the tree, currency `EUR`.

**What they showed.**
- **The phone's build committed wrong readings on both displays** - a swapped litres/price pair the
  arithmetic cannot catch (F2's residue, a second shape of it after Run 1's tenfold price), and a
  one-litre reading four times. **`HEAD` commits nothing on all 14 shots**: no wrong number, and no
  right one either.
- **The gap is locating the rows, not the law.** On the TFT screen both locators frame the advert's
  text and fields that are not the numbers (`t:113`, `u:02.489`); on the black LCD they take board
  cells and reflections for the transaction rows (`l:2.068`, `b:1.999`). The shipped RowSeg and the
  object detector it replaced fail the same way - neither has seen a TFT screen, and the black LCD
  is two stills in the corpus. This is data the locator needs (`pump-337`/`video-051` and
  `pump-332`..`335`/`339`/`340` are now in the corpus), not a preset.
- **The preset is not the lever here**: every preset fails alike at `HEAD`.
- **Run 1's latency finding did not hold.** `speed` captured faster than `default` in Run 1
  (410 / 369 against 540 / 947 ms) and slower in both new runs (958 against 555, 1364 against
  628 ms). Across the four scenes `speed` is faster twice and slower twice; the capture time per
  preset is dominated by the scene and the order the lab shoots in, not the preset. **There is no
  evidence yet for moving production off `default`** (SH.9).
- GPS absent from every photo, as in Run 1.

