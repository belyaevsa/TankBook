# RESEARCH-PU.90 – dark LCDs with light ink, and TFT screens: what approach to apply

*A research note for PU.90 (`docs/TASKS.md`). Product owner, 2026-09-26: "make a research how to
deal with dark LCD with a light ink and TFT displays. What approach to apply? Run research with
kimi k3." TFT screens are in scope (owner, 2026-09-25: "we should also consider them in addition to
the ink-based").*

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:
`agents/research/PU.90.md`.** No code, no tests, no builds of the app, no commits. Building
`pump-read` into `ios/.build/opt` and running it on corpus images is allowed (build output only):

```
cd ios && swift build --product pump-read -Xswiftc -O --scratch-path .build/opt
echo '{"rotationCW":0,"currency":"EUR"}' | ios/.build/opt/debug/pump-read <image>
```
(from the repo root; the reply is JSON: `rows` with quads and roles, `rowTexts`, `appCommitted`,
`abstainReason`, `appDecision`). Another agent or the orchestrator may be working in this checkout.

## Write first, explore second

Start the note's skeleton within the first minutes and fill it as you go. The pipeline is already
described for you below and in `docs/EXTRACTION.md` -> "The pump reader" - do not re-derive it.

## The problem, measured (2026-09-25/26)

Two display families the reader does not read today. In both, **nothing wrong is committed** - the
law refuses - but nothing right is either:

1. **Dark LCD, light segments** (white or pale segments on a black/dark-blue panel, behind glossy
   glass that mirrors the forecourt and the photographer). Alexela and Neste heads in Estonia.
   - `pump-332` (idle 0.00, board 2.079/1.979/1.919): **not classified as a pump** - RowSeg found one
     row (`liters 2.06`), the slow path found no second row -> receipt path.
   - `pump-339`, `pump-340` (Neste, 29.99/15.31, 19.61/10.01): rows found, but RowSeg took a board
     cell (`2.399`) for the total and a grade label (`Futura D`) for the litres; on 340 the total box
     clipped its last digit.
   - Capture Lab Run 3 (`docs/experiments/CAPTURE-LAB.md`, the same fill as `pump-339`, 7 presets):
     HEAD commits nothing on all 7; an older build committed "1 L" on four of them.
2. **TFT screen** (Tokheim at Terminal): the transaction numbers are **rendered text in a
   proportional font** on white fields, beside a full-colour cycling advert - not segments at all.
   - `pump-337` (72,80 / 35,00 at 2,080): classified as a pump, but RowSeg framed the advert's words
     ("LOJAALSUS", "TASUB ÄRA") as rows and the total `72,80` as the price; the law refused
     (`noTotalWindow`).
   - Capture Lab Run 2 (7 presets, same fill): HEAD commits nothing; an older build committed litres
     and price **swapped** (2.08 L at 35 EUR/L - closes 72.80, so the arithmetic could not catch it).

## The population - counted, use exactly these

From `Spike/ReceiptSpike/fixtures/pump/split.csv` + `windows.json` + `pump-live/videos.json`
(2026-09-26), every entry reviewed by the owner:

| Family | Stills (split) | Video / Live records |
|---|---|---|
| Dark LCD, light ink | `pump-332` (train), `pump-334` (train), `pump-335` (**heldout2**), `pump-339` (train), `pump-340` (train); third-party Alexela `pump-117`, `pump-144` (train - check whether they are the same family) | `video-050-unknown-alexela-black-lcd-running-display-2079-ee` (948 frames, reference quads unreviewed), Live records `live-6402`..`6405`, `live-6424`, `live-6425` (tracked frames under `pump-live/frames/`) |
| TFT screen | `pump-337` (train) | `video-051-tokheim-terminal-tft-static-display-2080-ee` (133 frames), `live-6420` |
| For contrast | 341 pump stills in total, almost all dark-on-light LCD / LED segments | |

Count and report any other light-on-dark display you find in the corpus (search the stills; e.g.
night-lit LED heads) - that changes how much "polarity" data exists already. The corpus database is
`Spike/ReceiptSpike/fixtures/corpus.sqlite` (`python3 scripts/corpus_db.py sql "..."`).

## What exists (read, do not change)

- Pipeline: `docs/EXTRACTION.md` -> "The pump reader" and its decision-10 amendments (RowSeg PU.87,
  row reader PU.89). Code: `ios/Sources/TankbookCore/Extraction/PumpReader/`.
- **Locator** `PumpRowSegmenter` (RowSeg.mlpackage, PixelLink pixel+link maps, trained by
  `ml/pump-reader/src/pump_reader/segtrain.py` / `segdata.py` on the train split's hand quads).
- **Decision** `PumpDisplayCapture` (fast path: >= 2 sized rows sharing a column; slow path with a
  Vision text-line ceiling and the geometry verifier).
- **Geometry verifier** `PumpRowGeometry` + the slicer `PumpGlyphSlicer` (it already detects
  polarity from percentiles - check whether that is the weak point for light ink behind glare).
- **Row reader** `PumpRowReader` (RowRead.mlpackage, CRNN + CTC, alphabet blank/0-9/separator;
  trained by PU.77's code under `ml/pump-reader/` - find its training data source and whether it
  includes inverted polarity or rendered fonts).
- **Cell classifier** `PumpSegmentsModel` (8 segment sigmoids) and the synthetic renderer
  (`ml/pump-reader` - check its LCD palettes: is light-on-dark rendered at all?).
- **Law** `PumpReadingLaw` - unchanged by this research; it already refuses safely.
- The receipt path's Vision OCR (`VNRecognizeTextRequest`) - relevant for TFT: rendered
  proportional digits are exactly what a general OCR reads well.

## Questions the note must answer

1. **Where does each family fail first?** Measure, don't guess: for every still in the table (and a
   sample of frames from the two videos), run `pump-read` and report per stage - classified? rows
   found (how many, IoU vs the hand quads in `windows.json`)? roles right? row text right? law
   outcome? The first failing stage per family is the one to fix first.
2. **Dark LCD, light ink - options, ranked.** At least:
   - **Polarity as augmentation**: train RowSeg / RowRead / the classifier with inverted strips and
     synthetic light-on-dark renders + synthetic glass reflections (is the renderer able to?);
   - **Polarity normalisation at inference**: detect light-on-dark per window (the slicer's
     percentile rule, or a learned bit) and invert before reading;
   - **More real data**: the Live records and video-050 give ~1 000+ frames of this family - enough
     for RowSeg? (the train split's quads and tracked frames are how RowSeg was trained);
   - **Reflection handling**: multi-frame fusion from the Live record (glare moves, digits do not -
     decision 2 in EXTRACTION.md), polarising-free tricks, exposure bias (the Capture Lab has a
     metered -0.5 EV preset - did it help on Run 3?).
3. **TFT screens - options, ranked.** At least:
   - **Route to general OCR**: classify the display family (segment vs rendered font), and for TFT
     read the located fields with Vision OCR (on-device, already in the app) then apply the same law;
   - **Train RowRead on rendered fonts** (synthetic: render numbers in common UI fonts on light
     fields) so one reader serves both;
   - **Label-anchored layout**: TFT heads print labels next to the numbers ("SUMMA", "LIITRIT",
     "€/L", "KOGUS/L", "HIND €/L") - using Vision's text to assign roles by label instead of by
     column geometry; is this general beyond one make?
   - **Ignoring the advert**: how to keep the locator off full-colour imagery (colour saturation,
     texture, the white field behind the numbers).
4. **One family-detection step or two separate fixes?** Would a small "display family" classifier
   (segment-dark-on-light / segment-light-on-dark / TFT / not a display) before the reader pay for
   itself? What does it cost on the phone (iPhone 12 floor, Core ML, bundle size)?
5. **What the published work says.** Cite and check (fetch the source; if you cannot, say so and do
   not describe it from memory): PixelLink (Deng et al., AAAI 2018, arXiv:1801.01315); CRNN (Shi,
   Bai, Yao, TPAMI 2017, arXiv:1507.05717); meter/display reading papers (e.g. Laroca et al.'s
   meter-reading work; Salomon, Laroca, Menotti 2020, arXiv:2005.03106); anything on inverse-polarity
   text / scene text on screens (e.g. text detection robustness to polarity, screen-content OCR).
   Also two Russian Habr articles found by the orchestrator, for their framing only:
   https://habr.com/ru/articles/792376/ (seven-segment reading without AI) and
   https://habr.com/ru/companies/sberbank/articles/670568/ (Sber's meter OCR - sequence model,
   separator handling, orientation check).

## What the note must contain

1. **The measured failure table** (question 1), with the commands you ran.
2. **Ranked options per family**, each with: the method (and its source), what it changes in our
   code (`file:line`), the data it needs (from the counted population - say if it is enough), the
   expected effect, the cost on the phone, and **the cheapest experiment that would falsify it**.
3. **A recommendation**: which to do first for each family and why, and what must NOT be done (e.g.
   anything that would let the TFT's advert text commit a number - hard rule: a wrong number is worse
   than none).
4. **What stays unknown** and what data would settle it (how many more captures of which kind).

Evidence rules: every claim cites a paper section, a `file:line`, or a number you measured; label
inference as inference. Precision is reported with its interval (`PumpPrecisionBounds`,
`agents/research/PU.68.md`) where you give one. Never quote a pump score produced any other way than
the corpus scorer (tolerance 0.005) as a corpus number.

## Report back

The path of the note, the first-failing-stage table, your recommendation per family in two lines
each, and anything you found and could not settle.
