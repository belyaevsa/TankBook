# Pump window annotator

A local web page for `Spike/ReceiptSpike/fixtures/pump/windows.json` - the
quads that tell the locator ratchets where the number windows are and what
each display shows. It is the manual step of `.claude/skills/corpus-intake`
(step 3), which also carries the annotation conventions.

**Writes go through the database** (product owner, 2026-09-21): every Save,
anchor, label and correction is a row in `fixtures/corpus.sqlite`
(`scripts/corpus_db.py`), and the JSON is dumped from it in the same byte
format the old writers used, so the committed files stay readable and the
ratchets keep reading them unchanged. `corpus_db.py import` is the one
direction back from the files to the database; it rebuilds the database when it
is missing or older. `pump_reader.track` saves its record through
`corpus_db.save_tracked`, which dumps `frames/<stem>/windows.json`.

    python3 tools/pump-annotate/server.py
    # open http://127.0.0.1:8765/

Stdlib only. HEIC fixtures are converted with macOS `sips` (or Pillow when
the ml venv runs it); the converted images are cached under
`~/Library/Caches/tankbook-pump-annotate/` by content hash.

- Left: every fixture in `expected.csv` (grey = no windows yet). `J`/`K` walk it.
  A heldout still (`fixtures.split`, decision 9) carries a small `H` badge
  ("heldout - measured once reviewed"); `#counts` tallies
  `heldout N (M reviewed)`.
- Middle: drag a rectangle to add a window (the first three go to
  total / liters / unitPrice and pre-fill the text from `expected.csv`; the rest
  are `board`); click to select; drag a corner to adjust; drag inside to move;
  `1`-`4` set the field; `⌫` deletes.
- **Nudge** (window selected, not typing): `←↑→↓` move the whole quad by one
  screen pixel at the current zoom (`⇧` = 10 px); `⌥`+arrow moves only the
  active corner - the last one dragged, else corner 0, shown as the filled dot.
  `Esc` deselects. In the frames view the horizontal arrows belong to the
  frames - `←`/`→` step, `⇧←` copies the previous label, `⇧→` jumps to the next
  run - so a horizontal nudge there is `,`/`.` (`⇧` = 10 px); `↑`/`↓` and
  `⌥`+arrow work as on a still. Entering the frames view deselects. `?` (or the
  **keys** button) opens the help screen with every key in one place; `Esc` or
  `?` closes it.
- Right: the text as the display SHOWS it (zero padding, comma), `partial`
  legibility, `rotationCW` (rotates the view only - quads stay in image space),
  `notOnDisplay` and `csvDisagrees`.
- **Live arithmetic** beside the CSV line: when the still's total, liters and
  unitPrice windows all carry text, the page shows `✓ closes` or
  `✗ liters x price = computed, shown total`, from the WINDOW texts (never the
  CSV row) and the same law `frameStates` runs on video frames. It is
  informational - it never blocks Save, because the corpus has legitimate
  off-by-a-cent displays.
- `processed` (`P`) marks the entry as checked by a human - `reviewed: true` in
  the JSON - and `✓ Save & next` (`⏎`) sets it, saves and opens the next one in
  the filtered list; the list filter separates empty / not processed / processed.
  Editing a `reviewed` heldout entry's windows (a quad or a text) clears
  `reviewed` on save and the page says so - a changed heldout still never
  measures silently; a save with identical windows keeps it.
- A `▶` in the list marks a still with a Live record (blue = tracking unreviewed,
  green = ok, red = bad; `▶?` = not tracked yet); the filter has *with Live record* and
  *Live, tracking unreviewed*.
- A `▶?` beside a still means it has a Live record whose frames are not
  tracked yet - tracking carries the STILL's windows into the frames, so a
  still with no windows has nothing to track. Draw (or `A`) and Save: the save
  tracks every paired record in the background (and re-tracks when the quads
  changed); **↻ track** beside *View frames* does the same by hand.
- A window drawn on the still after the last track run is on no frame yet. In
  the frames view it is **carried** onto each frame at the still's quad, drawn
  dashed and named in the frame line; drag it into place and `⇧⏎` pins it like
  any quad, or Save the still (or `↻ track`) to track it properly.
- **Every window edit on a still is a ledger row** (`pump-live/corrections.jsonl`, the
  `corrections` table): a moved quad (`kind: quad`, with who placed it - `auto`, `reader`,
  `tracker`, `template` or `operator` - and the IoU), a window drawn (`add`) and one deleted
  (`delete`, carrying the window it was). A window carried onto a frame and pinned there is an
  `add` on the frame. `scripts/corrections-report.py` counts them per kind and placer.
- **Not a window** (`n`, or the checkbox beside `+ window`): a drawn box is a judged negative
  - a board cell that is not the price, a totem, a keypad, a reflected display - kept on the
  entry as `negatives` (quad, `source`, `reason`), drawn grey and dashed, listed as chips. After
  `R` (the live path) the dashed rows are proposals to judge: **click** one to adopt it as a
  window (`placedBy: reader`, the ledger's `add` names the reader), **⇧-click** to reject it as
  a negative (`source: reader`). The locator's ranker (PU.24) needs judged boxes on both sides;
  `detdata.py` writes them to `negatives.json`. `pump-windows-check` refuses a negative over a window.
- **Skip a frame** (`x` in the frames view): the frame shows no display - a hand, the nozzle, a
  glare pass. Persisted at once (`skipped` on the frame, a `skip` ledger row) and the strip
  hatches it red; the glyph extractor, the detector export and the video read leave it out.
  Cheaper than an anchor and honest where an anchor would have to lie. `x` again un-skips.
- **Focusing any control on a window card** (the field select, the text, the
  partial box) selects that window: the card lights and its quad thickens on
  the picture, without the panel re-rendering under the cursor.
- **Live record / View frames** (shown when the still has a Live record and
  `pump_reader.frames` + `pump_reader.track` have run): steps through the
  record's tracked frames with the carried quads drawn (`←`/`→`, slider,
  `Esc` back), and a frame strip (grey = tracked, white outline = anchor).
  Mark **tracking ok / bad** on the still; `bad` makes the glyph extractor
  skip that record; `⇧⏎` in the frames view marks tracking ok and saves - that
  is a Live record's "processed" (also the **✓ tracking ok** button). A wrong
  quad on a frame is dragged into place like a video's and saved with **Save
  frame** (`⇧⏎` while the frame is edited, or just wait - a drag saves itself):
  the frame is **pinned** as an anchor (`liveAnchors` on the still's entry in
  `windows.json`, kept by every later save of the still) and nothing else
  moves. **↻ re-track all** (in the toolbar above the image) is the separate,
  explicit action that re-registers every non-pinned frame to the still and
  its nearest anchors; **↻ from here** does the same for the current frame and
  the ones after it only, so the frames you already checked keep their quads.
  A pinned frame is never moved by either. **keep shape** (toolbar, on by
  default) makes a corner drag on a frame move the whole window: the still (or
  a video's reference frame) defines a window's shape and a frame only says
  where it went, so every frame's quad carries the same margins - the
  detector learns those edges, and hand-resized frames taught it noise.
- **Videos** (`🎞`, filter *videos*): the running-display clips from
  `pump-live/videos.json`. Their "still" is the hand-annotated reference frame;
  *View frames* steps the tracked frames, and the frame's numbers are typed
  **on the window cards, exactly as on a still** - one place for the text, not
  two. On a frame the card's field and box belong to the reference (a frame
  carries the reference's windows, so the select and the delete are read-only
  there); only the text is the frame's own, and the reader's unconfirmed
  pre-fill shows yellow with the proposal repeated under the quad line. The
  frame row carries the reader's **margin** for that frame (the lowest cell
  margin of the total and liters windows, from `readings`; `–` when none); an
  `arithmetic` frame under the classifier's verify floor
  (`PumpReader.minimumMeanMargin`) is marked attention. Correct the cards and
  **Save this frame's numbers** (`⇧⏎`; `⌥←`/`⌥→` step frames from an input);
  owner labels are kept by every re-run of the reader. Stored in
  `pump-live/video-labels.json`.
  - **A run is labelled by its keyframes.** `⌥⏎` saves the frame as `owner` and
    fills the frames between it and the nearest earlier owner-labelled frame of
    the run with the arithmetic closure at the clip's constant price: liters and
    total interpolated by frame index, snapped to a pair where
    `total == round(liters x price, 2)`, monotone in both, written
    `source: interpolated` (the teal strip colour). A frame with no closing pair
    within 0.02 L of its interpolation is left unlabelled and stays attention.
    A later write to a frame invalidates the interpolations it bounds.
  - **`whole run` is a confirm loop, not a one-shot write.** With it checked,
    `⇧⏎` saves the typed frame and then shows the run's next frame with the typed
    label overlaid: `→` or `⏎` confirms one frame (`owner`, `via: run`), `⌥⏎`
    confirms the rest only while the arithmetic closes on each frame's existing
    `arithmetic` reading (it stops on the first that does not and says why), and
    `Esc` leaves the loop with the rest unlabelled. The ledger line for a run
    write carries `confirmed: N` and `interpolated: M`.
- **⟳ retrack + read all** (video frame label row): retracks the clip from its
  anchors and then runs the reader over every tracked frame
  (`PumpVideoReadTests` with `PUMP_VIDEO_READ_ONLY=<stem>`), rewriting the
  `arithmetic` labels. Frames with an owner label, frames anchored by hand and
  a video marked reviewed are skipped - the run never touches what a human
  wrote. An `interpolated` frame is skipped only while the nearest owner
  keyframe on both sides is still `owner`; otherwise it is regenerated as
  `arithmetic` (a changed keyframe makes the interpolation stale). Progress
  shows in the status line (`retracking…`, `reading…`).
- **The rail** (far left): 🖼 photos (every still), ▶ Live photos (stills with a
  Live record - opening one lands on its frames), 🎞 movies (the running-display
  clips and the 4K held-display records). The filter and search apply inside the
  chosen mode; the mode is remembered per browser.
- **Playback** (toolbar above the image): ▶ / ⏸ (`space` when not typing), ⏮ ⏭
  step, fps, **loop**, and **autoplay** - when on, a Live photo or movie starts
  playing the moment it opens. Stepping or dragging a quad pauses.
- **Turn a box** (drag the ring handle above the selected box, shift snaps to
  whole degrees; `[` / `]` by 1°, `{` / `}` by 0.1°; ↺ ↻ on the window's card,
  shift for 0.1°): rotates the selected window's quad about its centre
  so a skewed number gets a level box without dragging four corners. Works on
  a still's windows and on a video frame's (where it counts as a quad edit).
- **live slicers** (toolbar switch, remembered per browser): while the selected
  box is dragged, nudged or turned, the slicer's cells are drawn on it exactly
  as the reader will cut them, with `cells N · dp at k · matches text / text
  has M · 20 ms` in the toolbar. A resident `pump-read --slice-serve` answers
  (`slicer.py`; the optimised build under `ios/.build/opt`, made on first use -
  the first request on a still also pays its decode, ~100-400 ms); no model
  runs and nothing is written. Off, the overlay only appears after ▶ read.
  Board cells slice too (each keyed by its index, so four board cells keep
  four overlays); only ▶ read leaves boards out, because the law never reads one.
- In the frames view the zoom and scroll survive stepping frames (one
  record's frames share a size); the first frame of a record fits, `0` refits.
- **Zoom** (`+` / `-` / the slider) keeps the selected window - else the
  centroid of all windows - at the same spot in the viewport, so zooming in
  lands on the digits instead of the image's top-left corner; `0` refits.
- **⇤ boxes from previous** (`C`, on a frame): copies the previous frame's
  quads (never its numbers) onto this one - for a frame the tracker drifted on
  when the one before was right - and counts as a quad edit, so `⇧⏎` (or a drag) pins it as an
  anchor and the retrack registers the neighbours to it.
- **One Save, in the toolbar's second row.** Its label and its target follow the
  view, because the view is what you are looking at: on a still **Save** writes
  the annotation; on a video frame **Save frame's numbers** writes that frame's
  label; on a Live record's frame **⚓ Pin frame** pins its boxes as a tracking
  anchor. `⌘S` and `⇧⏎` run whichever one is showing. The still behind a frame
  is saved by leaving the frames view (`Esc`) - there is no second button that
  looks the same and writes somewhere else.
- **The toolbar has two rows.** Row 1 is the frame player and the per-view
  switches (play, fps, autoplay, loop, live slicers, keep shape). **Row 2 is
  what does not change with the image**: the one Save and **✓ & next**, **↶
  undo**, **⟲ reload**, the zoom (**−** / **fit** / **+**, with the factor
  beside it) and the retrack group - **↻ track** on a still with a Live record,
  **↻ re-track all** / **↻ from here** on a frame, **⟳ retrack + read all** on a
  video frame. A button with no meaning in the current view is hidden, not
  disabled, so the row reads as what can be done now. The right panel keeps only
  what is about THIS image: its windows, its negatives, its CSV row, its record.
- **The title bar** is the top line: the fixture, the record, the frame and
  where it sits (`1/1184`), plus the frame's inliers or the record's tracked
  count. Nothing else names them - not the toolbar, not the right panel, not the
  banner, which says only `ready` or `unsaved changes`.
- **Against the truth row** (right panel, below the notes) is the checker's
  questions about this entry, each with its answer beside it - not a standing
  form. While every asserted field has a window and matches, it says so in one
  line and offers nothing.
  - *"the truth row says 1.689 and no window is drawn"* → draw one, or press
    **the display does not show it**. A missing window is ambiguous - the face
    has no such field, the window is not drawn yet, or it was missed - and only
    the operator can say which; that judgement is `notOnDisplay`, and the
    checker then stops asking for the window. A head with no price window (the
    board cell IS the price) is the usual case.
  - *"the display reads 32,58, the truth row says 32.50"* → fix the text, or
    press **say why they differ** and write which side is right: the display, or
    the receipt the truth row came from (`csvDisagrees`). Clearing the reason
    removes the disagreement.
  - The **truth row** is the fixture's entry in the database (`expected.csv` is
    its dump) - the page says "truth row" everywhere, because the CSV stopped
    being the write store on 2026-09-21.
- **Where each control lives.** The **toolbar** carries what is the same
  whatever is open (Save, next, undo, reload, zoom, retrack, View frames). The
  **frames bar** under the image carries what acts on the frame you are looking
  at: **⏮ where I left**, **go to** a frame by number, ← same as previous, next
  attention, ▶ read, whole run, ⇤ boxes from previous, ✓ tracking ok, and the
  frame's own state (margin, source, anchor/skip). The **right panel** carries
  the image's annotation, top down: the window cards first, then `+ window` and
  the negatives, then the CSV row and the arithmetic it is checked against, then
  processed / rotate, then the record it belongs to (which record, tracking
  verdict), then notOnDisplay and csvDisagrees.
- The **frame scrubber** is the full-width slider under the strip - a coarse
  jump across a long record, where the strip's ticks are a fine one. The
  **record picker** appears only on a still that has more than one Live record;
  with a single record its name is printed instead of a select with one option.
- **⏮ where I left** jumps to the last frame you **saved** in this record - a
  label, a keyframe or an anchor - remembered per record in this browser. Not
  the last frame merely looked at: scrolling past forty frames is not progress.
  The button hides when there is nothing to resume or you are already there.
- **go to** takes a frame number (1-based, the count beside it names the total
  and the current file) - the way to a frame the strip would take a long scroll
  to reach.
- **The frames bar sits under the image**, not in the right panel: always
  present so the picture never jumps when the frames view opens, filled only in
  that view. It scrolls horizontally and **keeps the current frame in the
  middle**, so the neighbours a run is judged against are always the ones on
  screen; the ticks are tall enough to hit, the legend under them carries the
  colours and the frame count. Click a tick to jump to it.
- **The file name is in the toolbar only** - the record, the frame and the
  position (`video-002-… · 001.jpg · 1/1184`); the right panel carries what is
  about the image's annotation, never its name again, and the banner says only
  `ready` or `unsaved changes`.
- **↶ undo** (`⌘Z`) steps back through the box edits the browser cannot undo: a
  window drawn, moved, turned, nudged or deleted, boxes copied from the previous
  frame, auto-annotate, a pad, a negative added or removed. Text typed in a card
  keeps the browser's own undo. A burst of arrow-key nudges is one step; the
  stack belongs to the open image and is cleared when another opens.
- **⟲ reload** re-reads the still or record from the database and drops unsaved
  edits (it asks first) - the way out of a half-made change.
- **Anchors**: on any video frame the quads can be dragged (corners and body);
  the frame is pinned as an anchor by itself (`videos.json` and the tracked
  file) and nothing else moves. **↻ re-track all** / **↻ from here** (toolbar) re-register every other frame,
  or this one and the following, to its nearest anchors and take the best - a pinned frame is written back
  verbatim and never re-registered - so one corrected frame fixes the stretch
  around it when you ask for it, and a single bad frame costs a single pin.
- **✦ auto** (`A`, shift+a): auto-annotate a still - the live path locates
  the rows, and every row the reader assigned a field to becomes a window whose
  text is the CSV's truth - the display's own padding and comma still need typing - (never the reader's read, so a misread cannot be
  frozen in); a board row becomes a `board` window with an empty text to type. Windows already drawn are kept; the first new one is selected so
  the box can be tightened. Nothing is saved until Save.
- **det** (toolbar): the row detector `⇧R`'s live path runs - the model in the
  app bundle (marked `★`), the dev copy the Swift tests read, and every
  candidate under `ml/pump-reader/.out/det/`, each shown with the date it was
  written so two rounds of the same name are distinguishable. Remembered per
  browser; the read's status line names the detector it used. This is how a
  candidate is judged by looking (shipped vs candidate on the same still)
  rather than only by its committed count.
- **▶ read** (`r`): runs the app's own reader on what is on
  screen and fills the fields as a prefill - the annotated windows (or a video
  frame's carried quads) are sliced, classified and judged by the law, and the
  still's or the frame's empty texts take what came back (yellow = unsaved
  prefill; `Save` / `⇧⏎` accepts it, or correct it first) and draws the slicer's cells
  inside each window - green boxes per glyph, dashed where the slicer saw a blank, a green
  dot under a cell where it saw a decimal mark - so a miscount or a missed mark is visible
  at the pixel. Shift-`R` runs the
  **live path** instead - detector, verifier, row assignment, law, with no
  windows at all, the way the phone reads a photo - and draws the rows it
  located as dashed boxes (white = the detector's, grey = Vision/classical)
  with their assigned role and cell count. The read is `ios/.build/debug/pump-read`
  (`swift build --product pump-read` in `ios/`, built on first use) with the
  models from `ios/App/Resources`; the per-cell digits and margins print under
  the buttons. Nothing is written until you save.
- **Text conventions**: beside each window's text input a `cells N` badge
  compares the last `▶ read`'s slicer cell count for that field against
  `glyphCount(text)` (digits plus leading blanks) - green when equal, red when
  they differ, grey before a read - and a ⚠ appears when the typed separator's
  cell index differs from the cell the slicer marked `dp`. `Z` pads the three
  transaction texts to the still's make convention, derived from the same make's
  reviewed entries (`corpus_db.convention`, never a table): leading zeros to the
  modal digit count and the modal separator, and `#msg` says what it did.
- **Provenance**: every window carries `placedBy` (`hand` / `auto` / `reader` /
  `tracker` / `template`) and `zoom` - the canvas zoom at the last quad edit -
  written by the page, stored by `clean_entry` and the `windows` table, and
  shown on the card as `hand @1.4x`. A `▶ read` pre-fill that only changes text
  leaves them alone; the reader's auto-placed pump-244..pump-281 batch is `auto`.
- `Save` (`⌘S`) writes the entry as rows in `fixtures/corpus.sqlite`
  (`scripts/corpus_db.py`) through the database, dumped; the database is
  committed with the files. `Check` runs
  `scripts/pump-windows-check.py --check` and shows the verdict, which now also
  fails when a file no longer matches the database.

- **The corrections ledger** - `pump-live/corrections.jsonl`, appended by every save: one line
  per field the operator changed against a tool's proposal (the tracker's quad with its IoU
  against the hand-placed one, the reader's pre-fill or arithmetic label against the typed
  text, a tracking verdict), stamped with the build the proposal came from. Nothing is written
  for a field left as proposed. `scripts/corrections-report.py` turns it into the tracker's IoU
  histogram per record and make, the reader's pre-fill accuracy per build split into slicer
  misses (mark or leading zero only) and classifier misses, and the list of hard frames the
  next training export should weight. How each round uses it: `ml/pump-reader/CORRECTIONS.md`.

Loopback only. Nothing is committed - stage the JSON by path when the batch
is done.
