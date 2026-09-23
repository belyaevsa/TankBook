# Journeys walk - 2026-09-23 (the orchestrator)

Tree: `07f4f319`. Previous walk: `942406b1` (2026-09-19, second run). 320 commits since, almost all
of them the pump-reader tranche (PU) and annotator tooling; the rows that reach the app are PJ.39,
RV.114, RV.179, RV.288, RV.290, RV.292, RV.299, RV.302, RV.303, decision 11 (PU.54) and the PU rows
on the capture path (PU.29, PU.38, PU.53, PU.54, PU.62). Scope by the brief's four shapes: J4 and F2
(the capture path changed - shapes 1 and 4), plus the ticked-but-untrue re-check.

## Ticked-but-untrue: 0

| Row | Claim | Checked |
|---|---|---|
| RV.303 | a from-zero pull parks a record whose parent is missing and retries it | `SyncEngine+Pull.swift:16-28` (parked, `retryParked`); `sync.orphaned` in `LogEvents+SyncPull.swift`; `SyncPullOrderTests` 4 tests |
| RV.288 | the inbox withholds a cloud fuel reading whose numbers do not add up | `GatewayInboxPolicy.swift:239` calls `fuelNumbersAddUp` before the offer |
| RV.292 | the noise filter's unit-convention rule | `ReceiptNoiseFilter.swift` carries the `ДЛЯ` structural pattern |
| PU.53, PU.60, PU.62, PU.64 | shipped this week, each verified at its own commit | re-read at ship; not re-run |

## J4 - pump display photo

| Stage | Verdict | Evidence |
|---|---|---|
| a display is classified by structure, not strings | MET | `PumpDisplayCapture.classify`; PU.63 records that the text-line cap refuses text-heavy displays (pump-035, pump-112) - cited, not re-filed |
| the alpha notice while below the gate | MET | `L10n+PU29.swift`, `Localizable.xcstrings`; `PumpPhotoGate.allowsPumpPhoto` false |
| the gateway is asked with `kind: "pump"` | MET | `ManualFillUpView.swift:453` |
| the attachment records `pump-reader v1` | MET | `ScannedSavePlan.swift:85` |
| the text's reader paragraph | **DRIFT, fixed in the walk** | it said the law is the only judge and the unread fields arrive empty; since PU.54 a pair commits on a validated implied price, since PU.62 the rules arm fills what the reader refused, and since PU.53 a sideways display is read upright on a refusal. J4 rewritten; J4 carries no status line, so none is cleared |

## F2 - wrong data

| Stage | Verdict | Evidence |
|---|---|---|
| a disagreeing shown price surfaces as the F2 confirm (decision 11) | **MISSING - PJ.500** | the law marks `.priceDisagrees` (`PumpReadingLaw.swift:295`); no file in `ios/App` reads it; `CapturePipeline` drops every reason. Shape: docs naming behaviour with no call site. The promise in `EXTRACTION.md` and the type's comment are corrected to current truth in the walk |
| a cautioned pair (PU.59) | not built | PU.59 open; its risk (pump-019 read at 0 degrees) is named in its row |

## Partial rows (shape 4) - remainders all filed

PU.54 (closes with PU.59), PU.61 (composite constants need macOS 26 or a re-baseline - owner's
call), PU.65 (classify has the row-turn retry, not the levelling; off in the app), PU.66 (three
rounds refused; the lever is more owner-verified frames). No remainder without a row.

## Yield

1 row (`PJ.500`), 0 ticked-but-untrue, 2 doc drifts fixed in the walk (J4's reader paragraph,
decision 11's promise) and 1 code comment corrected (`PumpReadingTypes.priceDisagrees`).
