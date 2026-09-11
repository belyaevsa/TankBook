# RV.181 - nothing is ever dispatched to a share destination, on the device

**Scenarios: J13 · selling the car (export), J8b · look at the receipt again (share a photo).**
Reported again by the product owner on 2026-09-11 from the latest release build: *"still can't
share photo or export data"*. The row was skipped on 2026-09-10 pending device evidence; the
evidence path - the diagnostics export - goes through the same share sheet, so it cannot arrive.
**This brief changes the presentation shape to the one known to work, and makes the outcome
readable on screen without a share.**

## What the tree does today, and the hypothesis

Every share is `ActivityView` (`Shared/ActivityView.swift`): a `UIViewControllerRepresentable`
whose host controller `present`s a `UIActivityViewController` once it is in a window. Every call
site puts that inside a SwiftUI `.sheet(item:)`. The receipt photo is the deepest case:
`ReceiptCardView` `.sheet` -> `AttachmentViewerView` `.sheet(item: $shareable)` -> `ActivityView`
host -> `present(activity)`. **Three modal levels.** The export (`ExportFlow.swift:32`) and the
diagnostics bundle (`DiagnosticsPreviewView.swift:38`) are two levels.

`Coordinator.finish` runs `completion` and then **`dismissSheet()`**. For *Save to Files* and
*Copy*, the whole activity completes inside the activity controller, so dismissing the host after
is harmless - which is exactly why *Save to Files worked under both shapes* on the simulator. For
Messages, Mail, AirDrop-with-compose and every third-party share extension, the activity controller
dismisses ITSELF first and the destination's UI is presented **from the presenting controller** -
the SwiftUI-hosted `ShareHostController`. If the host sheet is torn down at that moment (SwiftUI
re-evaluating `.sheet(item:)`, or `finish` firing on an intermediate callback), the destination UI
is dismissed with it and nothing is dispatched. **This is a hypothesis.** The orchestrator's earlier
"no presenter" diagnosis was withdrawn; do not treat this one as proven either. It is, however,
the well-known failure shape for `UIActivityViewController` inside nested SwiftUI sheets, and the
fix below removes the shape whether or not the mechanism is exactly this.

## Build

1. **Present from the top-most presented controller of the key window, not from a sheet host.**
   Replace `ActivityView`'s sheet-hosted presentation with a `SharePresenter` (a small
   `@MainActor` helper) that finds the key window's root, walks `presentedViewController` to the
   top, and calls `present(activity)` there. Call sites stop wrapping it in `.sheet`; they call
   `SharePresenter.present(items:completion:)` from their button action. No SwiftUI sheet is
   involved in the share at all, so nothing SwiftUI does can tear the destination down. Keep
   `ShareOutcome` and the shape-only logging exactly as they are.
2. **Single-item photo and PDF shares use `ShareLink`** (`AttachmentViewerView` only) - the
   SwiftUI-native path with no presentation of ours. The export keeps UIKit because it shares a
   directory plus separate CSV files, which `ShareLink` cannot carry. Say in code why the two
   differ (one reason, at `ActivityView`).
3. **Make the outcome readable without a share.** The diagnostics preview (`DiagnosticsPreviewView`)
   is on-screen text with `.textSelection(.enabled)`; ensure the last `share` outcome lines - the
   operation, `outcome`, `activity=`, `error=` - are in that preview text, so the owner can
   screenshot them after a failed share. If the preview already includes recent log lines, say
   so; if not, add the last N `ui` lines to it (shape only, hard rule 12).
4. `docs/ERRORS.md` -> the share rows, and the `ActivityView` doc comment: replace the "deliberate
   choice, not a proven fix" paragraph with what the code does now and the reason.

## Tests

- **L1**: `SharePresenter.topMost(from:)` walks a presented chain to the top (a UIKit unit test
  with stacked controllers).
- **L4 `ExportUITests` / `EditEntryUITests`**: the share sheet appears from each door and *Copy*
  completes with a `completed` outcome logged - the simulator cannot prove a destination
  dispatch, **say so plainly**; what it can prove is that the sheet is presented from the top-most
  controller and the outcome is logged.
- **L4**: the diagnostics preview contains a `share` line after a share.
- No screenshots unless a screen changed.

## Mutation - named

Present from the sheet host again on one door; the top-most L1 goes red, and the L4 asserting the
presenter is the window's top-most controller goes red. Byte-identical restore; verbatim.

## The device step, for the owner - write it into the report

After this ships: one share attempt of a receipt photo to Messages on the iPhone 13, then Settings
-> About -> the diagnostics preview, screenshot of the `share` line. That is the evidence that
either closes the row or names the destination error.

## Vacuous traps

- Asserting the sheet appears. It always appeared; the dispatch is what fails.
- Keeping a `.sheet` around the new presenter "for dismissal" - that is the shape being removed.
