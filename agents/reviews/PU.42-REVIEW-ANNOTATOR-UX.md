# PU.42-REVIEW-ANNOTATOR-UX - what would make the pump annotator faster and better

Read-only review. One file written: this one. No tool, corpus or doc changes. I did not run the
page (agents cannot see it); every claim names a line, a route or a convention, and the two
"what I could not answer" items are separated out at the end.

## Verdict

The annotator is unusually good for one HTML file and one Python file: it already encodes the two
hard-won lessons of this corpus - "tracking carries the still's quads, a frame only says where
they went" (`keepShape`, `index.html:70` / `:573`) and "a human placement is a pin, nothing else
moves" (`saveAnchor`, `index.html:665`) - and it wires the reader, the tracker and the SQLite
store into the loop so the owner never touches a shell (`/api/read`, `server.py:534`; `start_retrack`,
`server.py:220`; `WRITE_LOCK`, `server.py:56`). The corrections ledger (`corrections.jsonl`,
`server.py:396-464`) is a provenance system most bespoke tools never get. Where the time goes is
not the drawing - `A` / `✦ auto` (`index.html:751`) already pre-places rows with the CSV's truth -
it is the *redundant re-confirmation of the same head forty times*, the *silent acceptance of a
reader misread as the display string*, and the *eye travel between three disconnected panels*
(image, window cards, `#out` text dump) that the owner must join by hand. The two risks that
actually bite are both silent: a `▶ read` pre-fill that puts the reader's value into `text` where
the convention says `text` is what the display SHOWS (`_about`), and a `whole run` label that
propagates to dozens of frames with no per-frame check (`server.py:415-426`). Both are one
wrong-keypress away from poisoning the oracle.

---

## Part A - the UX lens (one expert annotating hundreds of items)

Ranked by seconds saved per still / frame / clip.

### A1. A "same-head template" instead of redrawing the same three boxes 40 times
**What:** a button and key that pre-place the still's windows from the last still of the same
make/head (or a named fixture), reusing field + quad geometry and leaving only the text to type.

**Why it matters here:** PU.13 measured 47 Gilbarco and 40 Wayne fixtures, the Circle K EE face
repeating 40+ times with the same window layout; `A` re-runs the live path (2.4 s a photo,
`server.py:556` building `pump-read` on first use) and still produces row boxes the owner "usually
needs to tighten" (`README.md:97-100`). Copying quads across a head costs a fraction of a live-path
run and lands on boxes the owner already approved, so the margins match PU.13's measured convention
(right margin median 0.00) instead of re-negotiating them each time.

**Cost:** M (one `/api/template/<name>` route that reads a make's last reviewed entry, one button,
the make is derivable from the filename token the same way `corrections-report.py` attributes make).

**Evidence:** stills-per-hour on the batch-6 set (`pump-242..273`, 32 stills of three heads) before
vs after; the number of stills where `A`'s first new box is selected for tightening
(`index.html:766`) should fall to near zero on templated heads.

### A2. One "next thing that needs me" hop across still -> frames -> tracking -> next still
**What:** a single key/button that advances through the whole work queue: finish the still's windows
(`✓ Save & next`), then if the still has a Live record with untracked or unreviewed tracking, open its
Frames view, then to the next item in the `work` filter.

**Why it matters here:** the "processed" state on a still (`reviewed`, `index.html:78`) and the
"tracking ok/bad" state on its Live record (`index.html:87-90`) are two separate statuses the owner
must remember to visit; the `work` filter (`index.html:58`) lists them but the walk between them is
manual (`▶` to play a Live, `View frames` to enter, `Esc` back, `J`/`K` on). A still with a Live
record that is never marked tracking-ok silently stays "Live, tracking unreviewed" and its frames
are never reviewed.

**Cost:** S (a state machine over the already-computed `fixtures` list; both filters and both views
exist).

**Evidence:** zero fixtures in `liveunchecked` at the end of a session (`/api/fixtures` returns
`tracking` and `tracked`); time per Live record (should approach "walk the frames once").

### A3. Label propagation with verification, not silent "whole run"
**What:** after `⇧⏎` on a run, step through the run's frames with the just-typed label overlaid,
advancing on `→`/`⏎`, and only mark the run owner-labelled when the owner has seen each frame -
with a "skip, arithmetic closes" shortcut.

**Why it matters here:** `saveVideoLabel` (`server.py:383-426`) writes the label to the whole run
whenever `#vlRun` is checked (default on, `index.html:103`), and a wrong typed digit then covers
every frame of the run - none of which will ever re-surface as "attention" because `frameStates`
(`index.html:272`) sees them all carrying a consistent `source`. The `copied` attribution
(`index.html:358-364`) exists precisely because the tool already treats silent propagation as risky;
propagation with a per-frame glance is the same instinct applied to the run.

**Cost:** M (a per-frame confirm loop inside `saveVideoLabel`; the strip already renders every frame).

**Evidence:** the corrections ledger shows near-zero `text` corrections that changed a `via: run`
or `copied` label - today the ledger is the only signal, and it only fires when the owner *revisits*
a frame; a run-confirm pass would show wrong digits *before* they cover a run.

### A4. Keyboard nudge for the selected quad
**What:** arrow keys move the selected window by a screen pixel (shift = 0.1 of a row height),
`⌥`+arrows move the active corner, at the current zoom.

**Why it matters here:** corner placement is mouse-only (`hitCorner` / `corner` drag,
`index.html:551-555` / `:583`), with corner dots drawn at 6/zoom px and a 10/zoom px hit radius
(`index.html:499` / `:554`) - at the 4x zoom the digits need, the target is small and the
"drag, overshoot, drag back" loop dominates still annotation. The turn handle already proves the
keyboard-is-precise pattern (`[`/`]`/`{`/`}` at `index.html:789`); a nudge extends it to position,
which is the operation that actually sets the left/right margins PU.13 cares about.

**Cost:** S (a few branches in the existing `keydown` handler; the drag path already computes
image-space deltas).

**Evidence:** the median right-margin dispersion across a freshly-annotated batch (PU.13's
margin table) should shrink toward the 0.00 median; time per still should drop because corners
stop needing three mouse passes.

### A5. The `▶ read` pre-fill must not silently put the reader's value into `text`
**What:** default `▶ read` on a still to the same semantics as `A` - CSV truth for the transaction
fields, empty for `board` - and show the reader's committed value only as a *separate* hint with a
red/green diff against `#csv`; never pre-fill when the reader committed `?` or nothing.

**Why it matters here:** `runReader` (`index.html:738`) fills `w.text = c[f] ?? raw(f)` - the
reader's committed read - while `autoAnnotate` (`index.html:761`) deliberately writes the CSV's
truth "so a misread cannot be frozen in" (`README.md:98-100`). Two sibling buttons with opposite
trust semantics is exactly the trap this corpus has already paid for once (`pump-003`'s string was
the computed truth, not the display, PU.13 finding 1). The ledger records the correction if the
owner catches it (`server.py:456-462`), but the convention `text is what the display SHOWS`
(`_about`) is violated the moment it is accepted.

**Cost:** S (reorder `runReader`'s fill to prefer `row[f]`; the reader read is already in `#out`).

**Evidence:** the reader-prefill accuracy split in `corrections-report.py` - today it counts the
owner's corrections to a reader proposal; with the change, a reader proposal should be corrected
only when it disagrees with the CSV, i.e. the "classifier miss" bucket should drop sharply on
transaction fields.

### A6. "What did I change today" and in-page undo
**What:** a session panel listing this run's saves and corrections, and Ctrl+Z / a "revert to last
save" that restores the previous DB row for the open fixture.

**Why it matters here:** every save is already a DB row under `WRITE_LOCK` and a dump, so the
previous entry is one `SELECT` away; the corrections ledger (`corrections.jsonl`) is *written* but
never *shown*. A mis-delete (`⌫`, `index.html:802`) or a bad drag is recoverable today only by
`confirm('Discard unsaved changes?')` (`index.html:169`) or by re-drawing - the ledger will happily
record the accidental change as if it were a judgement.

**Cost:** M (a `previous` query in `corpus_db`, a small panel; the ledger read is trivial).

**Evidence:** count of corrections that were reverted within the same session (today unmeasurable -
the tool records no revert); owner-reported "I fat-fingered a delete" incidents should go to zero.

### A7. The list: group by make/head, and a heldout/unreviewed-aware progress count
**What:** a `group by make` toggle in the list, and `#counts` (`index.html:151`) extended to show
per-split and "Live, tracking unreviewed" tallies.

**Why it matters here:** the list is filename-ordered only, and the owner batches by head (A1); the
counts line shows `processed / with windows / empty` but not the number the owner actually has left
to do (`liveunchecked`). The `▶`/`▶?` marker (`index.html:158`) carries the Live state but the owner
cannot sort or count it.

**Cost:** S (grouping key is the make token already used elsewhere; counts come from `fixtures`).

**Evidence:** owner time to find the next thing; the `work` filter's residual count should be the
first thing on screen and drop to zero before a batch is "done".

### A8. Forecourt (touch) annotation
**What:** bind the server to the LAN when asked (`--bind 0.0.0.0`) and add a tap-to-place / tap-corner
touch path.

**Why it matters here:** the server is loopback-only by design (`server.py:15`), and every interaction
is mouse+drag (`canvas.onmousedown`, `index.html:561`) with no touch handling; annotating a display at
the pump while the LCD is still lit (glare, mid-count) is exactly where a still camera falls short and
the owner's eye does not.

**Cost:** L (touch events are a parallel input path; the value is marginal against the rest of this list).

**Evidence:** none cheap - this is the one item I would only fund after A1-A7 land.

---

## Part B - the annotation-expert lens (a corpus a model can learn from and be measured on)

Ranked by impact on downstream accuracy and honesty of measurement.

### B1. Show the warped strip and the slicer's cells live while adjusting a quad
**What:** while a corner or the turn handle is dragged, render the slicer's per-cell boxes (the
`readCells` overlay, `index.html:508`) and the cell count / pitch next to the cursor, and flag a
quad the slicer cannot count (leading blank not separated, comma in the wrong cell) before Save.

**Why it matters here:** the consumers are the slicer's leading-blank logic, the detector's boxes and
the classifier's per-cell crops (`docs/EXTRACTION.md` -> "The pump reader"; `REPORT.md` PU.34b), and
PU.13 measured exactly what a hand-drawn quad gets wrong - left slack up to +1.74 pitch on fixed-cell
heads, a miscounted leading zero, a comma the slicer drops (`pump-026`). Today the slicer's verdict is
only visible *after* a `▶ read`, i.e. the owner tightens blind and the corpus learns the owner's
margins. The overlay already exists; it is just gated behind a read.

**Cost:** M (drive `readCells` from a throttled `/api/read` on the selected window while dragging,
or re-slice the one window client-side via the same tool).

**Evidence:** the slicer count-agreement on newly-annotated windows (`PU.4 slicer` count agreement in
`REPORT.md`) should rise on the next batch; PU.13-style margin/padding drift should stop appearing
because it is visible at draw time.

### B2. Derive or enforce the text conventions instead of typing them
**What:** a live indicator that the typed string's digit count differs from the slicer's measured
cell count, a one-key "pad to the head's convention" (Scheidt zero-pad, Wayne none), and a warning
when a typed comma/dp conflicts with the slicer's mark placement.

**Why it matters here:** every `pump-003`-class error in PU.13 was a string typed with the wrong
cell count or a dropped/missing separator that `pump-windows-check.py` cannot see (board strings have
no validator - the script scores only `total/liters/unitPrice`, `pump-windows-check.py:33`). The
slicer already returns the cell count per window; the tool just never shows it against the text.

**Cost:** M (surface the reader's `cells` count next to the `data-t` input; a per-make pad helper).

**Evidence:** zero board-string reversals in the next PU review; the string-vs-ink `|delta|` table
PU.13 produced (148 windows with |delta| >= 2) should collapse on windows annotated with the counter
visible.

### B3. Arithmetic cross-check as a live indicator on stills
**What:** a check/red mark next to `#csv` (`index.html:184`) computed from `liters x unitPrice ~ total`
as soon as the three fields have text, mirroring what `frameStates` already does for videos
(`index.html:282`).

**Why it matters here:** the check currently runs only when the owner clicks `Check`
(`index.html:120`, `pump-windows-check.py:110-115`), so `pump-031`-style disagreements
(`csvDisagrees`) and `pump-074`-style "legible display, blank CSV" are discovered at save/check time,
not at typing time. The video path proves the logic; the still path just lacks the indicator.

**Cost:** S (port `frameStates`' arithmetic test to the still entry; it is the same three fields).

**Evidence:** `csvDisagrees`/`notOnDisplay` entries should be set at the moment they are visible
rather than after a `Check` run; fewer "does the arithmetic close?" round-trips per still.

### B4. Record per-window provenance (who/what placed each quad and text, at what zoom)
**What:** a `placedBy` / `source` marker per window (`hand`, `auto`, `reader`, `tracker`,
`interpolation`) and a `zoom` stamp, persisted through `clean_entry` (`corpus_db.py:881`) and
surfaced in the card, so the training and scoring code can read it.

**Why it matters here:** today `clean_entry` keeps only `field/text/legibility/quad`
(`corpus_db.py:885-890`), so a window the owner accepted as auto-placed is indistinguishable from one
they drew by hand - yet PU.13's whole margin/padding bias analysis is a property of the owner's
*hand*, and a `track`ed or `A`-placed box's tightness is the machine's. The corrections ledger
records *corrections* (a moved quad's IoU, `corpus_db.py:1010`), never the initial placement. Round 10
already rebalances the sampler by source fixture (`REPORT.md` round 10); it cannot rebalance by
placement provenance because the field does not exist.

**Cost:** M (schema column + `clean_entry` passthrough + one line in the card; consumers opt in).

**Evidence:** the sampler's `--cap-fixture`/`--hard-weight` distribution (`REPORT.md` PU.36b) can be
made provenance-aware; the inter-rater estimate in B5 stops conflating the machine's boxes with the
owner's.

### B5. Heldout badge and "reviewed but changed since" honesty
**What:** read `split.csv` and badge heldout fixtures in the list; when a heldout entry is edited
after `reviewed`, clear the reviewed flag (or mark `reviewed:false` + a warning) so a changed heldout
still never measures silently.

**Why it matters here:** decision 9 makes a heldout still measure only once `reviewed`
(`docs/EXTRACTION.md`, `PumpReaderTestSupport.isHeldout`), and the four night stills moved to heldout
*before* any train (`pump-275/277/280/281`). The annotator neither shows which fixtures are heldout
nor prevents the owner from re-editing a reviewed heldout window without re-flagging - the one state
that silently corrupts every heldout number. A blind golden re-annotation (the 30-window subset PU.13
asked for, `agents/reviews/PU.13-REVIEW-ANNOTATIONS.md` item 3) also needs the tool to present a
fixture as "unseen" and record the second pass.

**Cost:** M (read `split.csv` in `/api/fixtures`, a badge, a `reviewed`-clearing on edit).

**Evidence:** heldout score stability - the day's heldout run should not move because an auto-placed
box was re-tightened after review; a golden pass yields the inter-rater error rate every downstream
metric inherits.

### B6. Keyframe + interpolation + per-frame confidence for video labels
**What:** label a run by its two end keyframes and let the middle fill by the arithmetic closure
(flagged, not owner-labelled); show the reader's per-frame margin/confidence next to a label, and
mark interpolated frames distinctly from owner-typed ones.

**Why it matters here:** the running-display clips' whole value is the per-frame arithmetic oracle
(`pump-live/README.md` Batch 5: "total == round(liters x 1.729, 2)"), and today the owner either
types each frame (`⌥←`/`⌥→`) or trusts `whole run` propagation. There is no keyframe model, no
interpolation, and no per-frame confidence - the three things a frame-labelling tool for a *running*
quantity always has. The `source` field (`arithmetic`/`owner`/`copied`, `server.py:403-423`) is the
right vocabulary; it just is not used for interpolation.

**Cost:** M (a keyframe pair + closure fill inside `saveVideoLabel`, a strip colour for
interpolated).

**Evidence:** labelled frames per clip per hour; the `via: run` bucket in the ledger should shrink
relative to `via: copied` (the owner stops typing each frame).

### B7. Mark negatives and hard cases so consumers use them correctly
**What:** first-class markers (beyond `negative` and `notOnDisplay`) for idle heads (commit `0.00`),
`CLOSED`/`-00-` text, glare partials, mid-count frames, and the off-by-a-cent truncation family, each
with a "how a scorer must treat this" consequence.

**Why it matters here:** PU.13 finding 6 showed four cells are un-winnable for an honest reader and
`pump-016/017` idle heads are "winnable by committing zero" while the reward is currently backwards;
`pump-263` is a negative with `CLOSED` in the sum window (`pump-live/README.md` Batch 6). These cases
are *facts about the display* the consumers must branch on, and today they live only in prose or in a
filename. The tool is where the owner sees them and where they should be asserted.

**Cost:** M (a marker vocabulary on the entry + the check script consuming it).

**Evidence:** the scorer's precision floor becomes reachable (PU.13: 97.8 % cap) because the
un-winnable cells are declared rather than silently charged to the model.

### B8. A one-click dataset card / audit
**What:** extend `⤓ dump` (or a `Card` button) to print the summary a dataset card needs - counts
per make and split, heldout vs train, reviewed vs pending vs unreviewed, the known-exception list,
the corrections-ledger totals, and the inter-rater estimate once B5 exists.

**Why it matters here:** `dump` already reports files written, check exit and git-dirty files
(`server.py:519-529`); `corrections-report.py` already produces the tracker IoU and prefill-accuracy
histograms. No single surface prints the provenance-and-completeness facts a future reader of this
corpus would need in one place - and every REPORT.md round currently reconstructs them by hand.

**Cost:** S (aggregate the queries `corrections-report.py` already runs).

**Evidence:** one click reproduces the "corpus shape" paragraph PU.13 had to measure (456 windows /
114 fixtures / makes); the dataset card becomes a CI-checkable artifact.

---

## Do these five first

1. **B1 - live slicer strip + cell count while adjusting** (M): the single highest-accuracy lever;
   makes PU.13's margin/padding bias visible at draw time instead of in a quarterly review.
2. **A5 - `▶ read` defaults to CSV truth with a diff indicator** (S): stops the one silent path that
   writes a misread into `text`, the convention `_about` forbids.
3. **B3 - live arithmetic cross-check on stills** (S): the same three fields the video path already
   checks; surfaces `csvDisagrees`/blank-CSV cases at typing time.
4. **A4 - keyboard nudge for the selected quad** (S): corners are the cost centre; a nudge removes
   the drag-overshoot-drag loop at the zoom the digits need.
5. **B5 - heldout badge + clear-reviewed-on-edit** (M): the cheapest guard against silently corrupting
   every heldout number, and the precondition for the golden re-annotation PU.13 already asked for.

## Questions I could not answer without seeing the page

1. Are the corner dots (6/zoom px) and the 10/zoom hit radius actually hard to hit at 4x, or is the
   mouse path already fast enough that A4 is marginal?
2. Does the owner in practice rely on `▶ read`'s pre-fill on stills, or only on `A`/`✦ auto`? (The
   risk in A5 is only real if `▶ read` is used for stills, not just videos.)
3. Does the owner work stills->frames in one pass per fixture, or all stills first then all frames?
   (Determines whether A2's single-hop advance is worth building now.)
4. What is the actual seconds-per-still and seconds-per-run today? (I have no telemetry; the
   "evidence" numbers above need a before measurement to be verified.)
5. Would the owner actually annotate on a phone/tablet at the forecourt, or is the desktop the
   intended surface? (Decides whether A8 is a real ask or scope creep.)
6. When the owner re-tightens a reviewed heldout box, is that intentional and should it re-open the
   fixture for re-review, or should heldout be locked once reviewed? (B5's exact policy.)
