# PU.42-REVIEW-ANNOTATOR-UX - what would make the pump annotator faster and better

**Read-only.** You write exactly ONE file: `agents/reviews/PU.42-REVIEW-ANNOTATOR-UX.md`. No edits
to the tool, the corpus or the docs - name what you would change, why, and what it costs. No
`/tmp`; scratch, if you need any, is `ml/pump-reader/.out/review-ux/`.

## What this is

`tools/pump-annotate/` (`index.html`, `server.py`, `README.md`) is the in-house annotator for the
pump-display corpus: one product owner draws number windows (quads + the text the display shows)
on ~280 stills, corrects the per-frame labels of ~26 running-display clips and ~170 Live records,
and reviews what the app's own reader (`ios/Sources/PumpReadTool`, the "live path") places by
itself. The corpus is SQLite-first (`scripts/corpus_db.py`; the text files are its dump). The
goal of the tool is **speed and ease of annotation for one expert user** - it is not a product.

Read, in this order:

1. `tools/pump-annotate/README.md` - what the tool does today, every control and key.
2. `tools/pump-annotate/index.html` - the whole page (one file, ~700 lines): list, canvas, window
   cards, frames view, video labels, anchors, playback, auto-annotate, the turn handle.
3. `tools/pump-annotate/server.py` - the endpoints; what a save triggers (tracking, retrack,
   the reader run); what is and is not persisted.
4. `Spike/ReceiptSpike/fixtures/pump/windows.json` `_about`, and `scripts/pump-windows-check.py`
   - the annotation conventions the tool must produce.
5. `docs/EXTRACTION.md` -> "The pump reader" and decisions 9-10; `ml/pump-reader/REPORT.md` -
   what the annotations feed (glyph classifier from window cells, row detector from boxes,
   the heldout measurement) and what quality of quad the consumers actually need.
6. `agents/reviews/PU.13-REVIEW-ANNOTATIONS.md` - the last look at annotation quality: the
   biases found (margins, padding inconsistency) are the defects the tool should prevent.
7. `Spike/ReceiptSpike/fixtures/pump-live/README.md` batches 6-7 - the last two days of intake:
   32 + 8 stills auto-annotated by the reader with `pendingWindows`, and what the owner then has
   to do by hand.

Run the tool if you want to see its HTTP surface (`ml/pump-reader/.venv/bin/python
tools/pump-annotate/server.py 8790`, then `curl` the `/api/*` routes); you cannot see the page.

## The two lenses

Give the review in two parts, each a ranked list. For every item: **what** (one sentence),
**why it matters here** (tie it to a concrete thing in the code, the conventions or the
consumers - not a generic UX maxim), **cost** (S / M / L in this codebase), and **evidence you
would accept that it helped** (a number the tool or the corpus can produce).

### A. The UX lens - one expert annotating hundreds of items

Think in throughput: seconds per still, per frame, per clip; how many hands, clicks, key
presses and eye movements one annotation costs; where the owner has to remember something the
tool knows; where a mistake is easy and its correction slow. Consider at least:

- the flow through a batch (list -> open -> draw/adjust -> type -> mark -> next): what is
  redundant, what could be pre-filled, what could be batched across similar stills of the same
  head (the Circle K Gilbarco face repeats 40+ times);
- the frames view: labelling a 300-frame clip, runs, anchors, the "next attention" jump, what
  the strip shows and what it should;
- keyboard vs mouse: what is only on one of them; the handle and corner sizes at the zoom
  levels the digits need; the turn handle; snapping or magnetism the quads could use;
- what the reader's pre-fill (`A` / `▶ read` / `⇧R`) should look like to be trusted quickly
  (confidence, margins, a diff against the CSV truth) and where it should NOT pre-fill;
- feedback: what the owner cannot see at a glance (unsaved state, what a save triggered, a
  tracking that failed, a check that would fail on save);
- undo, history, "what did I change today";
- the list: filters, sort, progress, the rail modes;
- anything that would let the owner annotate on the phone or tablet at the forecourt.

### B. The annotation-expert lens - producing a corpus a model can learn from and be measured on

Think like someone who has run labelling for OCR / 7-segment / object-detection datasets.
Consider at least:

- **quad quality**: what the consumers need (the slicer's leading-blank logic, the detector's
  boxes, the classifier's per-cell crops) versus what a hand-drawn quad delivers; tightness
  and margin conventions; whether the tool should show the warped strip and the slicer's cells
  live while adjusting; whether it should refuse or warn on a quad the slicer cannot count;
- **text conventions**: zero padding, comma vs point, leading blanks, `partial`, board cells,
  `notOnDisplay`, `csvDisagrees` - which of these the tool should enforce or derive rather than
  let the owner type; the arithmetic cross-check (litres x price = total) as a live indicator;
- **consistency across annotators and days** (there is one annotator, but the reader now
  auto-places boxes, so there are effectively two): inter-annotator agreement measures, a
  "golden" subset re-annotated blind, drift detection;
- **review workflow**: unreviewed vs reviewed vs heldout (a heldout still measures only once
  reviewed - `PumpReaderTestSupport.isHeldout`); what a review pass should show and log;
  sampling for QA; how to keep the heldout set honest when auto-annotation exists;
- **video labels**: the arithmetic-closure labelling, runs, owner corrections, anchors - what a
  good frame-labelling tool does that this one does not (interpolation, keyframes, propagation
  with verification, per-frame confidence);
- **negatives and hard cases**: idle heads, CLOSED text, glare partials, mid-count frames, the
  off-by-a-cent displays - how they should be marked so the consumers use them correctly;
- **provenance**: who/what placed each quad and text (hand, reader, tracker, interpolation),
  when, at what zoom - and why the training and measurement code should read it;
- **export and audit**: what a dataset card for this corpus would list and what the tool
  should be able to print.

## What NOT to do

- Do not propose a rewrite in a framework, a new server, or a hosted labelling product. The
  tool is one HTML file and one Python file on purpose; proposals stay in that shape.
- Do not propose changes to the corpus conventions themselves (the `_about` format, decision
  9's split) - propose how the tool should serve them.
- Do not pad with generic advice (dark mode, accessibility audits, "add tests"). Every item
  names a line, a control, a route or a convention it changes.

## Output

`agents/reviews/PU.42-REVIEW-ANNOTATOR-UX.md`: a one-paragraph verdict on the tool as it is
(what it does well, where the time goes), then part A and part B as ranked lists in the format
above, then a short "do these five first" section with the cheapest high-yield items across
both lenses, then a list of the questions you could not answer without seeing the page (so
the owner can answer them).
