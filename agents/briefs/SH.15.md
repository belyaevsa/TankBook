# SH.15 - Prepare the App Store update after 1.0: what changed, the copy, and a pump panel

You prepare the store listing for the next App Store release of **Tankbook** (an iOS car cost log,
fuel receipts and pump displays captured by the camera, typed entries as a peer path). The last
store release is the git tag **`v1.0`**. You change **no code**.

## Where you may write

Only these paths, inside the repository you are started in:

    docs/STORE-COPY.md                      (add a new section; keep every existing section)
    docs/RELEASE-NOTES-1.1.md               (new)
    design/store/panel-06-en.yaml           (new)
    design/store/panel-06-ru.yaml           (new)
    design/store/final/store-06-en.png      (built by the script, never drawn by hand)
    design/store/final/store-06-ru.png      (same)
    design/store/.cache/                    (whatever build.py writes there)

Nothing else. No file under `ios/`, `backend/`, `scripts/`, `Spike/`, `agents/` or `docs/` other
than the two named above.

**Git is read-only for you:** `git log`, `git show`, `git diff`, `git tag` only. Never `commit`,
`add`, `checkout`, `stash`, `reset`, `restore`, `merge`, `rebase` or `push`. Other sessions have
uncommitted work in this checkout; leave every file you did not create untouched.
**Never `pgrep -f`** - your brief is your command line, so it matches you.
Run no builds or tests. The one program you run besides git and file reads is
`design/store/build.py` (step 4).

## Step 1 - what changed since 1.0 (docs/RELEASE-NOTES-1.1.md)

`git log --oneline v1.0..HEAD` (about 480 commits). The commit subjects name task ids
(`PU.93`, `RV.318`, `SH.14` ...); the rows behind them are in `docs/TASKS-DONE.md` (search the
id). Write `docs/RELEASE-NOTES-1.1.md`:

- **User-visible changes only**, grouped: *New*, *Better*, *Fixed*. One line each, in the
  user's words (what they can now do or no longer suffer), with the task ids in parentheses.
- Leave out: tests, docs, corpus batches, tooling, the annotator, research notes, anything
  behind `#if EXPERIMENTS` / beta-only (docs/CONFIG.md -> "Build channels and experiments" lists
  them: `captureLab`, `sendDiagnostics`, `scanOutcome`, `scanShadow` ...) - the store build does
  not have them.
- Verify a claim against the row before writing it; if a row says it was cut, reverted or is
  beta-only, it is not in the release.
- At the end, a short list of anything you were unsure about, so the owner can check it.

The headline feature of this release is **reading the pump display**: the user photographs the
pump's display and the app reads total, litres and price from it (on the device, a trained
segment reader - the PU.* rows; the `pumpPhoto` flag is on in
`ios/Sources/TankbookCore/Config/Config.default.json`). Describe it truthfully: the numbers are
**pre-filled for the user to check**, never saved without them, and typing stays a peer door
(CLAUDE.md hard rules 13 and 15). A read that does not add up is shown with a warning to check it.
Do not claim accuracy numbers.

## Step 2 - the copy (docs/STORE-COPY.md)

Read `docs/STORE.md` first (sections 0-4b: the copy rule, what each audience is angry about,
the two listings) and all of `docs/STORE-COPY.md`, including "What I would not say". Then add a
new section at the end of `docs/STORE-COPY.md`:

    ## Update 1.1 (2026-09-28)

containing, for **English** and **Russian** each:

| Field | Limit | Note |
|---|---|---|
| What's New | 4000, keep to 4-6 short lines | lead with the pump display; then the other *New*/*Better* items that matter to a user |
| Description | 4000 | the full, submittable description: the current one with the pump capture woven in where capture is described (not a paragraph bolted on at the end); keep what it says about local-first, export and no account |
| Promotional text | 170 | a new one if the pump capture earns it, else say "unchanged" |
| Keywords | 100, comma-separated, no spaces | only if a pump word earns a slot; show what it replaces |

Give the **character count** after each field, counted by a script (e.g. python on a temp file you
delete afterwards) - never estimated. Russian is written for a Russian-speaking driver, not
translated from the English (docs/STORE.md 4b: two audiences, two sets). Use **en-dashes (–) only,
never em-dashes (—)**, in both languages.

## Step 3 - the pump panel (design/store/panel-06-*.yaml)

The listing's screenshots are panels built by `design/store/build.py` from YAML specs
(`design/store/panel-0N-{en,ru}.yaml`). Read `build.py` and panels 01-05 in both languages to
learn the format and how a panel takes its device screenshot (a `source: image` layer whose
`path` points into `design/store/.cache/`, prepared by the script from a screenshot in
`design/screenshots/`).

The device screenshots for this panel already exist (captured by the orchestrator):

    design/screenshots/SH.15-pump-capture.png      (English)
    design/screenshots/SH.15-pump-capture-ru.png   (Russian)

They show the capture's check step on a real pump photo: the photo of a Gilbarco display and the
three numbers read from it (total, litres, price) ready to check.

Write `panel-06-en.yaml` and `panel-06-ru.yaml` in the **same family** as panels 01-05: the same
canvas, background, wash, typography roles and device frame treatment - copy panel 03's structure
(the capture panel) and change only the kicker, headline, sub-line and the device image. Headline
ideas (yours to improve, within the panels' length): EN "Point at the pump. It reads the numbers.",
RU something a Russian driver would say about photographing the pump display (табло колонки). The
sub-line says the user checks the numbers before saving.

## Step 4 - build and check

Run `python3 design/store/build.py` with whatever arguments it takes to build panel 06 in both
languages (read its `main()`/argparse; build only panel 06 if it can, otherwise all - but then the
other ten outputs must come out byte-identical to the committed ones; if they do not, restore
nothing yourself and report it). Then check with PIL that both files are 1284 x 2778.

Add a "Screenshots for 1.1" table inside your new section of `docs/STORE-COPY.md` with row 6, and
propose where panel 6 goes in the upload order (the first three are what search results show),
with one sentence of reasoning.

## Report

End with: the files you wrote; each copy field's character count; the proposed upload order;
the unsure list from step 1. You cannot see images - say so, and do not describe what the panel
looks like beyond what the YAML says; the orchestrator checks the pixels.
