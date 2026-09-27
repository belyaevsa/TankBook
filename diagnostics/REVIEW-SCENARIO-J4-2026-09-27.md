# REVIEW-SCENARIO – J4 · No receipt – pump display photo (2026-09-27)

Walked by the orchestrator (the method is `agents/briefs/REVIEW-SCENARIO.md`), for PU.6's last
item. **Scope of this run: the pump-photo half of J4** – the preview, the tip, the classification,
the reader and its law, the gate, the notices, the verify screen, the attachment, the gateway and
the success metric – because that is what PU.6's flip changed. The station half (PJ.19, RV.150,
RV.156, PJ.55, RV.115/RV.180) was not re-walked in this run and is not judged here.

## Verdict

**NOT IMPLEMENTED.** Thirteen rows naming J4 are still open beside PU.6 (below), and one promise has
no measurement path (PJ.503). No promise in scope is unowned: every gap below already has a row.
The status line in `docs/JOURNEYS.md` is not touched.

## Ticked rows found untrue

None in scope. Two defects of the SEQUENCE surfaced in the days before this walk and are fixed.
Neither was caught by a test:

| Found | What the user met | Fixed by |
|---|---|---|
| Owner's phone, Capture Lab Run 4 | Every euro pump read nothing on a phone whose region is Russia – the reader was given the region's currency | PU.98 (`42bc060a`) |
| PU.93's family measurement | A dark-LCD pump the reader refused was parsed as a receipt and pre-filled a false 1.0 L (`EUR/1L`), 2079 L, or a board cell as the price | PU.93 (`cdceb3d5`) |

## Promise-to-code map

| Promise (J4 text) | State | Evidence |
|---|---|---|
| Preview: *Display in view* / *Move closer* (2× tap) / *Tilt to show the whole display*, fill-up mode only; a hint, never a gate | MET | `App/Sources/Capture/CaptureGuidanceCaption.swift:12` (fill-up only), `:26` (caption slot), `:71`, `:84`, `:87`, `:89`; logged `CaptureView.swift:426` |
| First-use tip "no receipt? Shoot the pump" | MET | `CaptureGuidanceCaption.swift:38`, `App/Sources/Capture/CapturePumpTip.swift:3` |
| A display is recognised by structure (two+ large rows), on capture, attach, re-attach and replace | MET | `CapturePipeline.swift:73-96`; the seven callers pass through `process` (PU.98's list) |
| The law: `volume × price = total` closing uniquely; the pair tier with a shown price within 5 %; an amber notice when the shown price differs | MET | `PumpReadingLaw.resolve`; `CaptureVerifyView.swift:117` (`pumpPriceDiffers`) |
| A field the reader refused is filled from the receipt parser where it read one | MET, and measured | `CapturePipeline.composed`; PU.61's `PumpCompositeArmsTests`: the fallthrough fills 0 cells on the heldout set |
| Sideways display read upright | MET | `CapturePipeline.swift:126` (`displayRotationCW`), `CaptureVerifySession.swift:63` |
| The ship gate: ≥ 99 % of filled fields right over ≥ 60 % coverage | MET | `PumpPhotoGate.allowsPumpPhoto`; reader 121/122 of 183 (0.992, 0.667); composite 120/123 with one real miss (`pump-063`, cautioned) – PU.61 |
| Below the gate the sheet says alpha | MET (not shown while the flag is on) | `ConfirmPrefill.swift:261`, `ManualFillUpView.swift:167`, `CaptureVerifyView.swift:115` |
| Nothing read → *"Couldn't read the pump display – type the numbers…"* | MET for a display the reader recognised | `CaptureVerifyView.swift:109`, `EmptyScanCaption.swift:53` |
| "A pump photo never runs the receipt parser in silence" | **PARTIAL** | A display the locator does not recognise (the dark LCDs `pump-332/339/340`) is classified as a receipt, parsed as one, and says *"Couldn't read this one"* – honest, and since PU.93 it commits nothing wrong, but it is not named as a pump. Owned by PU.91 (the locator on dark LCDs) and PU.92 (TFT) |
| Photo kind recorded (`pump-reader v1`), entry `.pumpPhoto`, gateway `kind: "pump"` | MET | `ScannedSavePlan.swift:85`, `CapturePipeline.swift:124`, `ManualFillUpView.swift:455` |
| The cloud reads a pump as a pump | **PARTIAL** | `kind: "pump"` is sent, but the server shares the receipt prompt – RV.289 |
| Verify screen: photo upright, zoomable, three numbers to check before the entry opens | MET | `CaptureVerifyView.swift` (PJ.505, PJ.506) |
| Success metric: pump-photo share of captures ≥ 15 % | **MISSING** (owned) | No measurement path – PJ.503, the owner's call |
| Success metric: ≥ 99 % of filled fields right | MET as a gate | PU.61 |
| Station half (suggestion ladder, creation door, favourite, save stamp, brand) | N/A in this run | Not re-walked; shipped rows PJ.19, RV.156, PJ.55, RV.150, RV.115/RV.180 |

## Sequence trace – one user, one pump, no receipt

1. Opens Capture in fill-up mode → the tip, then the preview hint once rows are in view. **Carried.**
2. Shoots → the reader classifies and reads under **the car's currency** (was: the region's –
   PU.98). **Carried since PU.98.**
3. The reader commits → verify screen, upright, the numbers to check → Confirm with `.pumpPhoto`.
   **Carried.**
4. The reader refuses a display it recognised → *"Couldn't read the pump display"*, fields empty,
   typing is the peer door. **Carried.**
5. The locator does not recognise the display (dark LCD, TFT) → the photo is a receipt; since
   PU.93 it commits nothing wrong on the dark LCD and reads the TFT through Vision (50 of 51).
   **The fact "this is a pump" stops being carried here** – owned by PU.91 / PU.92.
6. Save → the attachment carries `pump-reader v1`; the gateway call carries `kind: "pump"`. The
   cloud answer uses the receipt prompt (RV.289). **Partial.**

## Open rows naming J4 (none new)

SH.9 (the production capture preset), SH.10, PJ.503 (the share metric), RV.289 (the cloud's pump
prompt), RV.295, PU.40, PU.41, PU.59 (the cautioned pair – `pump-063` is its live case), PU.77, PU.90,
PU.91, PU.92, PU.94; and PU.6, which closes with this report.

## Proposed rows

None: every gap in scope is already owned by a row above.

## Not settled

- Whether the one real composite miss (`pump-063`, a cautioned pair total) should count against the
  gate or be excluded because it reaches Confirm flagged – PU.59's question, the owner's call.
- The station half, for the run that finds J4 READY FOR REVIEW.
