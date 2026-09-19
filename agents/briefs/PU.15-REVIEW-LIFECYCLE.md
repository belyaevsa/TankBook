# PU.15-REVIEW-LIFECYCLE - the full lifecycle of a pump photo, from shutter to stored entry

**Read-only.** You write exactly ONE file: `agents/reviews/PU.15-REVIEW-LIFECYCLE.md`. No code.
No `/tmp`.

## What this is

Walk one pump-display photograph through the WHOLE product, stage by stage, and say at each
stage what exists, what is missing, what can go wrong, and what the user sees when it does.
This is a product-and-architecture review, not a model review (two sibling reviews cover the
model: `agents/briefs/PU.11-REVIEW-IMPL.md`, `PU.12-REVIEW-DATA.md`).

Read, in order: `CLAUDE.md` (hard rules 1, 7, 9, 12, 13, 15), `docs/JOURNEYS.md` → J4 and the
failure journeys F2/F3/F4, `docs/SCREENMAP.md` (capture → confirm), `docs/ERRORS.md` (pump rows),
`docs/EXTRACTION.md` → "The pump reader" and the pump paragraphs, `docs/VISION.md` → the pump
feature row, `docs/LOGGING.md`, `docs/CONFIG.md` (the feature flag), `docs/TASKS.md` → PU and
P2.7, `ml/pump-reader/REPORT.md` (the numbers), and the code under
`ios/App/Sources/Capture/`, `ios/App/Sources/ConfirmManual/`,
`ios/Sources/TankbookCore/Extraction/` (incl. `PumpReader/`, `PumpExtractor.swift`, `Gateway/`),
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift`.

## The lifecycle to walk

1. **Capture.** How does the user get to "photograph the pump"? Is it a peer door next to
   typing (rule 15)? Camera guidance (framing, glare, distance)? Burst vs single frame? What
   resolution reaches the reader, and is EXIF orientation handled?
2. **Classification.** How is a frame recognised as a pump display rather than a receipt
   (`ExtractionSource`)? What happens when it is wrong?
3. **Locate → warp → slice → classify → decode → cross-check** (the reader; today the locator
   is a stub and decode is unbuilt): where does each stage run (device/cloud), on what thread,
   with what latency budget, and what does it hand on. Where would a per-stage diagnostic go
   (`docs/LOGGING.md`: never a domain value; ids, counts, codes, durations only).
4. **The gate and the flag.** `PumpPhotoGate` + the remote config flag: who can turn pump mode
   on, what the caption says (PJ.12b), what a user on a build below the gate experiences.
5. **The cloud arm.** When does `/extract` get the frame, what does the ledger store (rule 9's
   LLM ledger amendment), what is the offline path (rule 1, F3), and how do the two readings
   merge.
6. **Confirm.** How the pre-fill is presented as a suggestion (rule 13), which fields are
   editable, how a nil/abstain shows, what the cross-check outcome looks like, what the user
   does on a mismatch (F2), how the odometer (never on the pump) is asked for.
7. **Persistence and after.** What is stored (FillUp fields, the attachment, the reading
   provenance), what sync carries, what the 30-day undo covers, what "re-scan" means later.
8. **Feedback loop.** When the user corrects a read, does anything learn from it, and what
   would it take (privacy classes in `docs/LOGGING.md`; rule 12) to collect corrected cells
   into a future training set with consent.
9. **Measurement.** How the corpus, the ratchet and the gate connect to the shipped build; what
   number tells us the feature is working in production (and whether such a number exists).

## Report

`agents/reviews/PU.15-REVIEW-LIFECYCLE.md`: a stage table (stage · exists? · owner file ·
failure mode · what the user sees · gap), then the gaps ranked by user impact, each with a
proposed row (title, journey id, the check that closes it), then **"What I would need to know
or have"** - ranked questions to the product owner about the intended experience (e.g. burst
capture, guidance overlay, whether a pump photo may be sent to the cloud by default, what to do
when the reader and the receipt disagree).
