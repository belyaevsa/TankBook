# SH.17 - "How Tankbook reads a pump display": a site article in English and Russian

You are a technical writer and editor. You write one long-form article for the public site
`tankbook.live` (Hugo, `site/`), in **English and Russian**, about how the app reads the numbers off
a fuel pump's display from a photo. The source is an internal explainer the product owner liked;
you turn it into a public article, **check every fact against the current code**, and add one
section it does not have: how the first generation of the reader differed from the second.

## The source

    agents/briefs/SH.17-source.md

It is the Russian text of the explainer (written 2026-09-26 from the code of that day), with
`[DIAGRAM name]` and `[PHOTO name: alt]` placeholders where its figures stood. Its structure is a
good skeleton: the one rule (a wrong digit costs more than an empty field), the pipeline, then each
step with its input, output and algorithm, then examples, then how it is measured.

## The style you apply

Read both files in full before writing a word:

    /Users/sbelyaev/repos/edu-platform/docs/brand/lesson-guides/writing-style.md
    /Users/sbelyaev/repos/edu-platform/docs/brand/lesson-guides/voice-samples.md

The guide is in Russian and is the owner's single style source; apply its rules to both languages
(for English, the same rules in their English form). The ones that bite hardest:

- en-dash (–) only, never an em-dash (—), spaced on both sides except in ranges;
- no "not X, but Y" / "it's not X – it's Y" constructions;
- no bold lead-in sentence opening every paragraph or bullet; no bullets cloned from one template;
- no absolute claims; concrete over abstract; plain words over marketing;
- the numbers rules (section 6) wherever a number appears.

Ignore the guide's parts about the school, lessons or courses.

## The facts: check each one against the tree, today

The source was accurate for 2026-09-26. The reader changed since. **Before you keep a claim, a
threshold or a number, find it in the code or in `docs/EXTRACTION.md`; if you cannot confirm it,
drop the number or the claim.** The code:

    ios/Sources/TankbookCore/Extraction/PumpReader/          (the reader, the law, the locator)
    ios/Sources/TankbookCore/Extraction/                     (the capture pipeline around it)
    ios/App/Sources/Capture/                                 (what the Confirm/verify screen shows)
    docs/EXTRACTION.md                                       (decisions; read "Currency supports the read and never blocks it")
    docs/TASKS-DONE.md                                       (PU.33, PU.76, PU.77, PU.87, PU.88, PU.89, PU.100 - what shipped and why)

Known to have changed since the source (confirm how it works now and write that):

1. **Currency (PU.100).** The source says the currency comes from the phone's settings and that an
   unmeasured currency makes the law refuse. Now currency is a set of signals that supports the read
   and never blocks it (the car's home currency, a currency printed on the display, the region); a
   triple that closes under any measured convention is offered.
2. **A read that does not close (PU.100).** The source's step 10 says a field the law refused stays
   empty. Now, when nothing closes, the top read of each field reaches the verify screen under a
   warning (the "don't multiply up" caution). Say what the user sees.
3. **The alpha label and the remote switch.** Check what the verify screen shows today and whether
   the pump-photo mode is on in the 1.1 build (`docs/RELEASE-NOTES-1.1.md`, `docs/CONFIG.md`,
   `site/content/releases.md`). Write only what a 1.1 user will meet. The site's releases page calls
   1.1 "in preparation": if the article says when the feature arrives, it says "in 1.1".

Leave out anything internal: task ids, file paths, remote-config flag names, the law's refusal
reason codes as identifiers (describe the reasons in words), the source's "where the code and the
docs disagree" section (already removed from the source). Model names (RowSeg, RowRead) and the
papers they come from (PixelLink, CRNN, CTC) may stay - they are what a technical reader searches for.

## The new section: two generations of the reader

Put it after the step-by-step part and before "how we measure". Facts, from `docs/TASKS-DONE.md`
(confirm them there):

- **First generation (2026-09-20, PU.33).** A Create ML object detector found the digit rows:
  31 MB, and it could draw only upright rectangles. A "slicer" then cut each row into character
  cells, and a small classifier (about 64 KB) read each seven-segment cell alone: eight outputs, the
  segments a–g and the decimal point, the digit being the nearest of ten allowed patterns. The law
  of reading on top.
- **What held it back.** Upright boxes on a tilted display: the same hand-drawn rows read 89 cells
  as upright rectangles and 111 as tilted quadrilaterals - the box's orientation was the largest
  single variable measured. It was trained mostly on level displays (90 % of its boxes under 4°).
  Loose or clipped boxes cut digits. It never saw some displays (night, amber LEDs, screens).
  Slicing a row into cells was where most cells were lost. And 31 MB in the app bundle.
- **Second generation (2026-09-25), in two steps.** RowSeg (PU.87): a pixel-and-link segmenter in
  the PixelLink manner, 1.8 MB, which returns rotated quadrilaterals fitted to the row's own pixels.
  RowRead (PU.89): a CRNN trained with CTC that reads a whole straightened row at once, 3.9 MB; the
  slicer and the cell classifier stay only to check a row's geometry and to decide which side is up.
- **The measured difference**, on the 68 held-out photos no model trained on (183 cells): the old
  locator committed 47 cells, all correct; the new locator 62 (61 correct); with the whole-row reader
  117 (116 correct), and the photos read entirely right went from 21 to 40 of 68. Box fit against
  hand-drawn rows (median rotated IoU) 0.771 -> 0.861; false rows per photo 0.647 -> 0.088.

## Numbers and the copy rule

`docs/SITE.md` -> "The copy rule" and `docs/STORE.md` bind every page: a pump photo is a **head
start the user checks, never "automatic"**; typing a fill-up is an **equal** way in, never the
fallback; never a promise of accuracy. This article is an engineering explanation, so measured
numbers appear, under these limits:

- a number is always a **measurement with its conditions** (which photos, how many, when) - never a
  promise ("reads 99 %") and never in the lede;
- the measurements live in the two-generations section and in "how we measure", nowhere else;
- keep the source's four headline stat cards out.

## What you write (the only files you may create)

    site/content/pump-reading.md
    site/content/pump-reading.ru.md

Hugo front matter in TOML (`+++ ... +++`), exactly `title` and `description` (the description is
the search snippet: one sentence, 120-160 characters, per language). Look at
`site/content/import-guide.md` for the shape. The body is Markdown **with no raw HTML** (the site
renders none). Figures go in only through these two shortcodes, which the orchestrator builds:

    {{< diagram name="pipeline" caption="..." >}}     names: pipeline rowseg decision warp roles ctc law
    {{< photo name="night-tilt" caption="..." >}}     names: board-lit night-tilt night-circlek tokheim-tft alexela-black-lcd

Use each at most once, in the language of the page; drop a figure the text no longer needs. The
three row strips (`strip-*`) are not available - describe them in words if you need them. Tables are
Markdown tables. Headings: `##` for sections, `###` below; no `#` (the layout prints the title).

The two pages say the same things in the same order; the Russian one is written in Russian, not
translated word by word. Russian runs longer - keep sentences short on both.

## Fences

- **Git is read-only for you** (`git log`, `git show`, `git diff`); never `commit`, `add`,
  `checkout`, `stash`, `reset`, `restore`. Other sessions have uncommitted work in this checkout -
  touch no file you were not given. Never `pgrep -f`. Run no builds and no tests.
- Write nothing outside the two files above.

## Report

When done, your final message lists: every claim from the source you changed or dropped because the
code says otherwise (source line -> what the code does, with the file and line you read), every
number you kept with where you confirmed it, and anything you could not confirm.
