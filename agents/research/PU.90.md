# RESEARCH-PU.90 - dark LCDs with light ink, and TFT screens

*Research note for PU.90. Product owner, 2026-09-26: "make a research how to deal with dark LCD
with a light ink and TFT displays. What approach to apply?" Research: kimi k3, 2026-09-26.
Read-only except this file; the only builds run were `pump-read` into `ios/.build/opt` (allowed)
and a throwaway Vision probe script outside the repo.*

## Verdict up front

**Both families fail first at the same stage: the row locator (RowSeg).** Not at polarity, not at
the segment classifier, not at the law. When the windows are handed to the pipeline by hand, the
black LCD reads mostly right (pump-340 perfect; the idle Alexela heads perfect) and the TFT commits
its full correct triple after the law's arithmetic repair (85.00 -> 35.00). Nothing wrong is
committed anywhere in either family at HEAD - the law holds - but nothing right is either, because
the rows are never found. The fix order is therefore: locator data first, a family route second,
read-stage work last (and maybe never).

## 1. The measured failure table (question 1)

Commands run from the repo root, `pump-read` built 2026-09-26 at HEAD with
`swift build --product pump-read -Xswiftc -O --scratch-path .build/opt` (exit 0):

```
echo '{"rotationCW":0,"currency":"EUR"}' | ios/.build/opt/debug/pump-read <image>            # live path
ios/.build/opt/debug/pump-read <image> < <request-with-hand-quads.json>                    # oracle path
```

The oracle requests carry the hand quads from `windows.json` (via `corpus.sqlite`, `windows`
table), with and without the `board` windows. IoU below is bounding-box IoU between the best
located row (`rows[].quad` in the reply) and each hand quad.

### 1.1 Dark LCD, light ink (stills)

| Still | Fill | Classified? | Rows found (kept) | Best IoU vs hand quads | Row texts | Law outcome | Oracle (hand quads) |
|---|---|---|---|---|---|---|---|
| pump-332 (train) | idle 0.00/0.00 | **NO** (slow, rows=1, widest 0.075 < 0.18) | 1 | 0.00 on all 5 hand windows | `liters 2.06` (a board artefact) | not routed; `noTotalWindow` | `0.00`/`0.00` **correct**; law `litersAllZero` (right: idle) |
| pump-334 (train) | idle | YES (fast, rows=2) | 1 kept | liters 0.79; total 0.13; boards 0.00 | `liters 0.00` correct | `litersAllZero` (right: idle) | `0.00`/`0.00` correct |
| pump-335 (**heldout2**) | idle | YES (fast, rows=2) | 1 kept | liters 0.75; total 0.08; boards 0.00 | `liters 0.00` correct | `litersAllZero` (right: idle) | `0.00`/`0.00` correct |
| pump-339 (train) | 29.99/15.31, no shown price | **NO** (slow, rows=1) | 3, all mis-framed | transaction rows 0.00; board 2.399 framed at IoU 0.36 as an 8-cell row | `total 2.39920`, `liters 0009`, `board 2.069` - board taken for total, grade label for litres | not routed; `cellUnknown` | with boards: commits total **29.99 right**, litres **15.21 wrong** (truth 15.31, `3`->`2`), caution `priceDisagrees` |
| pump-340 (train) | 19.61/10.01, no shown price | **NO** (slow, rows=2, widest 0.170 < 0.18) | 2 kept, clipped | liters 0.56, total 0.53 (total clipped to 3 cells, read `19.6`) | `total 19.6` | not routed; `noLitersWindow` | with boards: commits **10.01 / 19.61 both correct**, caution `priceDisagrees` (board 1.959 misread `1.954`) |
| pump-117 (train, control) | 113.99/52.65/2.165 | YES (slow) | 3 | - | all correct | **commits all three, correct** | - |
| pump-144 (train, control) | same fill, wider | YES (slow) | 3 | - | all correct | **commits all three, correct** | - |

pump-117/144 answer the brief's "check whether they are the same family": behaviourally they are
**not** - the pipeline reads them end to end at margins 6-13 with no defect. Inference from the
make (Wayne heads, `wayne-alexela-...-third-party`): they are the emissive look (lit segments on a
dark surround) the corpus already holds in quantity, not the reflective pale-on-black glass of
pump-332/334/335/339/340. I cannot see the images; the behavioural difference is what is measured.

### 1.2 Dark LCD, light ink (video and Live frames; 7 + 9 sampled)

`video-050` (948 frames, reference quads **unreviewed** - so recall numbers are against the
pipeline only, not against truth quads): frames 001/100/250/480/600/750/900. **0 of 7 classified.**
RowSeg finds 0-3 rows; even when it finds them the slow verdict's floors reject the frame
(widestRow 0.086-0.160 < 0.18, or fewer than 2 rows). Notable: frame 250 located both transaction
rows and read `total 32.93 / liters 15.84` - implied price 2.0789 against the video's asserted
2.079, i.e. a **correct running-display read**, refused as `priceUnvalidated` because no price row
was located. When rows are found on this family, the read is already close.

Live frames (`live-6402`, `live-6404` idle; `live-6424` = pump-339's fill; 3 frames each): 3 of 9
classified. Idle frames read `0.00` correctly. The 6424 frames show the read-stage weakness that
remains after location: `total 2999` / `total 1.959` (a board), `liters 299`/`129` - decimal marks
dropped and boards framed as rows. Nothing committed anywhere.

### 1.3 TFT (stills, video, Live)

| Item | Classified? | Rows | What happened | Law |
|---|---|---|---|---|
| pump-337 (train) | YES (fast, rows=3) | 4 kept | RowSeg framed the advert's words (`LOJAALSUS`, `TASUB ÄRA`) as rows; hand total IoU 0.53 but roled `unitPrice`, litres IoU 0.80 roled `None`, price window not found. Read `70.80` for the total `72.80` | `noTotalWindow` - refused |
| pump-337 oracle | - | hand quads | `total 72.80` right, `liters 85.00` for `35.00` (rendered `3` -> `8`), `unitPrice 2.080` right | **commits the full correct triple 72.8 / 35 / 2.08** - the exact close repaired the misread digit |
| video-051 frames 001/030/066/100/133 | 3 of 7 | 1-3 | frame 001: `liters 35.00` + `total 72.80` **both right** (abstained `priceUnvalidated` - no price row); 030/100: `85.00`; 066: litres right, total `01.2219`; 133: `851.00`, `7212` | nothing committed |
| live-6420 frames 001/030/055 | 3 of 3 | 2-4 | `22.80`/`85.00`; `31999.9`/`86.00`/`0.009`; `2.80`/`3.99`/`199` | refused (`priceOutOfBand`, `cellCountImpossible`) |

### 1.4 The general-OCR probe (Vision, macOS, `VNRecognizeTextRequest` accurate, no language correction)

A 20-line script outside the repo, run once per still:

- **pump-337 (TFT): Vision reads everything, exactly.** `72,80` and `35,00` on the white fields,
  `2,080` under the `€/L` label, plus the labels `SUMMA`, `LIITRIT`, `€/L` - each label sitting one
  row above/beside its number (label x ~0.44-0.47, number x ~0.64-0.66, same y-band; the price label
  and number share x ~0.06-0.25). `35,00 × 2,080 = 72,80` closes exactly. The advert
  (`LOJAALSUS TASUB ÄRA!`) is read as words - no digits.
- **pump-339 (black LCD): Vision is the wrong tool.** It reads the total as `2999` - the decimal
  point dropped, the documented seven-segment failure (`docs/EXTRACTION.md` -> "The pump reader" -
  Vision "drops the decimal point the display renders as a separate dot"). Board cells read
  (`1959`, `2399`, `20 19`) but the transaction litres not at all.
- **pump-332 (black LCD, idle, reflection):** Vision reads only stickers and the reflected
  forecourt - no display digits at all.

### 1.5 First failing stage, per family

| Family | Classify | Locate | Roles | Read | Law |
|---|---|---|---|---|---|
| Dark LCD, light ink | **fails** (3 of 5 stills not a display, 0/7 video frames) - but *because* the locator starves it | **fails first**: 0-1 transaction rows, IoU 0-0.56, boards framed as rows | untested upstream of locate | adequate when fed (oracle: 340 perfect, idles perfect, 339 one digit + one dp off) | holds: nothing wrong committed |
| TFT | passes (fast path fires on advert+number rows) | partial: fields found but advert framed too; price window missed | **fails**: total roled as price, litres unassigned | weak on proportional font (`3`->`8`, `851.00`) but the exact close repairs it | holds: `noTotalWindow`, `priceOutOfBand` |

**The locator is the first failing stage for both families.** It is also the newest component and
the one whose training set provably contains neither family (§2.3).

## 2. The population, counted

### 2.1 The two families

Counted from `split.csv` + `corpus.sqlite` (2026-09-26), matching the brief's table exactly:

- **Dark LCD, light ink:** pump-332, 334, 339, 340 = `train`; pump-335 = `heldout2`. video-050:
  831 tracked frames, **1 verified**, 830 with unreviewed tracked windows. live-6402/6403/6404/
  6405/6424/6425: 89+76+60+86+57+65 = 433 tracked frames, **0 verified**. (live-6403 pairs with
  pump-333, a CNG head, not this family.)
- **TFT:** pump-337 = `train`. video-051: 134 frames, 1 verified. live-6420: 63 frames, 0 verified.
- 341 pump stills total.

### 2.2 Other light-on-dark in the corpus (the brief asked for a count)

Light-on-dark is **not new to the corpus** - every emissive head is light-on-dark in pixels:
- 25 stills with `night` in the name (lit panels against a dark forecourt: Wayne Neste, Gilbarco
  Circle K/UK, Tatsuno amber LED `pump-186/187`, Tokheim Lukoil `pump-195/196/201/202`, Scheidt
  `pump-107`, Wayne Gazpromneft `pump-235/236`);
- the Wayne/Dresser/Tatsuno LED and Tokheim VFD heads generally (the renderer's `led`/`vfd`
  profiles exist precisely because the corpus is full of them - `profiles.py:120-131`);
- pump-341 (Voltera, yellow backlit LCD, idle): located 3/3 rows, read `0.00/0.00/1.219` all
  correct, law correctly refuses `litersAllZero`.

What **is** new about the Alexela/Neste black LCDs is not polarity but the *reflective* look:
pale segments on black glass, low contrast, mirroring the forecourt. So "polarity data" exists in
quantity; "pale-on-black-glass behind reflections in daylight" is exactly 5 stills + 2 videos'
worth of frames + 433 Live frames, and only the 5 stills carry owner-reviewed quads.

### 2.3 Neither shipped model has seen either family

- RowSeg (`rowseg-seg-r1`, shipped PU.87, commit 4f836a6a, 2026-09-25): trained on 256 train
  stills + 275 owner-verified frames + 116 negatives (`models.json`; `.out/seg/train/index.json`
  contains none of pump-332/334/335/337/339/340, no video-050/051 frame, no live-64xx frame).
- RowRead (`rowread-pu89`, shipped PU.89, commit c9e04a39, 2026-09-25): 50 287 real strips from an
  export dated 2026-09-22 (`.out/real-current/manifest.json`), i.e. before corpus batch 11
  (pump-329..335, 2026-09-24) and batch 12 (pump-336..341, 2026-09-25).
- The new stills are all `train` (except pump-335, `heldout2`), so **a retrain on a fresh export
  is already legal under decision 9** - no new capture is required to try it.

## 3. Dark LCD, light ink - options, ranked (question 2)

### Option L1 - retrain RowSeg on data the corpus already holds (FIRST)

- **Method:** fresh `segdata` export (it picks up the four train stills' hand quads
  automatically, `segdata.py:50-69`), plus owner-verification of a sample of video-050 and
  live-6402..6425 frames - `segdata.py:71-83` takes only `verified` frames ("a tracker's box
  carries its drift", PU.66). Adjacent frames are near-copies (decision 9's video rule), so
  diversity, not count: ~30-60 verified frames per record, spread across the fill, plausibly
  suffices. PixelLink's own claim is exactly this regime: "better or comparable performance ...
  while requiring many fewer training iterations and less training data" (Deng et al., AAAI 2018,
  arXiv:1801.01315, abstract - fetched and confirmed).
- **Changes:** no code. `segdata` -> `segtrain` -> `segexport`, then PU.57's rotated gate
  (median IoU + recall@0.7 hold or rise, false rows/photo +0.05) and the live floor.
- **Data:** exists today; needs owner annotation time, not captures. 4 stills + ~150-300 verified
  frames against RowSeg's current 256 stills + 275 frames is a real change in mix (~2x the frames,
  all of the new family).
- **Expected effect:** high (inference). Every measured failure on this family is a locate/classify
  failure on a look the model never saw; the read stage behind it is already adequate (oracle arm,
  §1.1). The idle heads (332/334/335) show the locator *almost* works - it finds the litres row at
  IoU 0.75-0.79 - so this looks like a small distribution gap, not a new task.
- **Phone cost:** none (same model size class; RowSeg is 1.8 MB, 26.5-29.8 ms Mac Release).
- **Cheapest falsifier:** run the retrain, then `pump-read` on pump-339/340/332 and 10 video-050
  frames. If classification still fails on most, the gap is not data volume - stop and go to L2/L4.
  Cost: one training run (~hours) plus annotation.

### Option L2 - polarity-inversion augmentation in `segtrain`

- **Method:** augment the segmenter with inverted images. The classifier already does exactly this
  per batch (15 % random invert, `train.py:68-76`, comment: "dark-on-light and light-on-dark LCDs
  both exist"), and the glyph dataset renders light-on-dark at ~6 % (`dataset.py:56`,
  `DARK_ON_LIGHT_PROB = 0.94`, measured on 40 755 real cells). `segtrain.py:63-83` has photometric
  jitter but **no inversion**.
- **Changes:** `ml/pump-reader/src/pump_reader/segtrain.py:63-83` (a few lines: `x = 255 - x` on a
  fraction of samples; quads unchanged).
- **Data:** none new.
- **Expected effect:** uncertain (inference). A whole-image inversion is unrealistic - sky, skin
  and the forecourt invert too - and PixelLink keys on texture, not only polarity; the corpus
  already contains abundant emissive light-on-dark (§2.2), so raw polarity is unlikely to be what
  the model is missing. The distinctive look is *reflection on black glass*, which inversion does
  not synthesise.
- **Phone cost:** none.
- **Cheapest falsifier:** it is itself cheap - but only worth a run after L1, and only if L1
  under-delivers.

### Option L3 - polarity normalisation at inference (RANKED LOW - measured unnecessary)

- **Method:** detect light-on-dark per window and invert before reading.
- **Why low:** this already exists where it matters. The slicer decides polarity per strip before
  any normalisation (`PumpGlyphSlicer.swift:153-154`, `darkOnLight = (p50 - p05) > (p95 - p50)`;
  `realglyphs.py:205-210` documents the same rule for exports), and the oracle arm reads this
  family correctly through it. RowRead sees no normalisation (`PumpReader.swift:207-214` warps and
  feeds RGB straight to the CRNN) yet still reads pump-340's strips perfectly - 4 of 5 renderer
  profiles it trained on are emissive light-on-dark (`profiles.py`: wayne/dresser/scheidt LED,
  tokheim VFD). The percentile rule could in principle be fooled by a large glare patch flipping
  the p95 side; measured, it was not (0.00/0.00 on 332/334/335 behind reflections, 10.01/19.61 on
  340). Do not build this unless the locator is fixed and misreads remain.

### Option L4 - reflection handling / multi-frame fusion (SECOND, after L1)

- **Method:** fuse across the Live record's frames at the *locator* level: align frames, median the
  pixel maps, decode once - glare moves between frames, digits do not (decision 2,
  `docs/EXTRACTION.md`).
- **What exists:** `PumpFrameFusion.swift:5-11` fuses the cell classifier's probabilities across
  frames **after** the still is located and sliced - it cannot help a family whose rows are never
  located. L4 is a new fusion point, not a reuse.
- **Changes:** new code - frame alignment (the tracker in `ml/pump-reader/src/pump_reader/track.py`
  already aligns frames to a still for annotation; the same homographies would be needed on-device
  or the fusion done on the decoded maps of each frame without alignment, taking a per-pixel
  median over maps from `PumpRowSegmenter.rows` on each frame).
- **Data:** the Live records (6 records, 433 frames of this family) are exactly the input shape.
- **Expected effect:** moderate-high on the reflective heads specifically (inference) - this is the
  one option aimed at *glare*, the family's second distinctive property.
- **Phone cost:** N locator passes per capture instead of 1 (~27 ms Mac each; the Capture Lab owns
  the phone number) - real but bounded; can run on the 2-3 sharpest frames only.
- **Cheapest falsifier:** offline script - run RowSeg on 10-15 frames of one Live record, median
  the pixel maps, decode, count rows vs the still's hand quads. No training.

### Option L5 - exposure bias / capture preset (REJECTED, measured)

Capture Lab Run 3 (`docs/experiments/CAPTURE-LAB.md`, 7 presets incl. metered -0.5 EV): **HEAD
commits nothing on all 7**, the older phone build committed a wrong "1 L" on four. "The preset is
not the lever here: every preset fails alike at HEAD." Measured, closed.

### The renderer question the brief asked

Can the synthetic renderer produce this family? Partially: `grey_lcd_palette` (`dataset.py:83-102`)
draws light-on-dark at 6 % with corpus-contrast quantiles, `apply_reflection`/`apply_glare` exist
(`augment.py:125-180`), and LED/VFD profiles are light-on-dark with bloom. What no palette renders
is *pale grey-blue segments on true-black glass with a mirror reflection of a forecourt* - the six
named LCD palettes (`dataset.py:62-79`) are all dark-ink-on-light-ground, and reflection blobs are
soft gaussians, not mirrored scenery. A dedicated `alexela`-style profile is a moderate renderer
change (palette + stronger reflection model) and would feed the classifier/RowRead; but RowSeg's
training is real-only (`segdata` renders nothing), so synthetic light-on-dark does not reach the
stage that fails. **Renderer work serves the read stage, which is not the bottleneck - do not start
here.**

## 4. TFT screens - options, ranked (question 3)

### Option T1 - route TFT frames to general OCR, then the same law (FIRST)

- **Method:** detect the TFT look; read the located fields with `VNRecognizeTextRequest` (on
  device, already shipped in the receipt path); feed (value, quad) candidates into
  `PumpReadingLaw.resolve` unchanged. Measured basis: the §1.4 probe - Vision reads pump-337's
  `72,80 / 35,00 / 2,080` exactly, with labels, and the exact close `35,00 × 2,080 = 72,80` holds.
  Precedent for a type-routing first stage: Sber's meter OCR runs a lightweight MobileNetV3 to
  classify meter *type* before anything else, accuracy 0.99 (Habr 670568, fetched).
- **Changes:** a branch in `PumpDisplayCapture.classify` /
  `PumpReader.readPhoto` (`PumpReader.swift:319-324`): when the frame is TFT-like, skip the
  segment reader, run Vision, collect numeric observations, and hand them to the law as candidate
  windows. The law is untouched.
- **Data:** none for a heuristic route (white fields + rendered digits + high Vision line yield).
  A learned family bit would want a few dozen TFT photos - the corpus has **one** TFT still.
- **Expected effect:** high on pump-337 itself (the numbers are already read exactly); unknown
  beyond one make/station (population = 1 still + 1 video + 1 Live record, all Terminal Tokheim).
- **Phone cost:** Vision OCR already runs in the app; the text-line pass costs 6-36 ms Mac on 12 MP
  stills. No new model.
- **Cheapest falsifier:** the §1.4 probe on the next TFT photo of a *different* make - if Vision
  stops reading the numbers exactly, T1's "general OCR is enough" premise is false. Also: run the
  receipt rules parser over pump-337 and confirm/deny that its own cross-check would have committed
  the right triple (see §8).

### Option T2 - label-anchored roles (with T1, not instead of it)

- **Method:** assign roles by the printed label next to each number (`SUMMA`->total,
  `LIITRIT`->litres, `€/L`->price on this head) instead of column geometry
  (`PumpRowAssignment.swift` assigns by stacking/x-span today). On pump-337 the labels sit in the
  same y-band as their number (measured, §1.4).
- **Generality:** labels are per-locale, per-make strings (Estonian here; a Russian head prints
  `СУММА`/`ЛИТРЫ`). It generalises as a *small per-locale vocabulary*, the same shape as the
  receipt parser's keyword lists - but with one TFT still in the corpus there is no evidence of
  what other TFT heads print. Treat labels as a **cross-check on geometry** (agree -> confidence,
  disagree -> caution), never as the only role source, mirroring decision 11's shown-price ruling.
- **Changes:** role assignment for the TFT branch only; vocabularies live with the receipt parser's
  keyword tables.
- **Phone cost:** none (string matching).
- **Cheapest falsifier:** the next two TFT photos from other chains.

### Option T3 - train RowRead on rendered fonts (THIRD)

- **Method:** synthetic strips of numbers in common UI fonts (PIL + truetype) on white fields,
  mixed into `rowtrain.py`'s `Synthetic` (rowtrain.py:63-76 renders only segment glyphs today).
- **Effect:** fixes digit misreads on TFT (`3`->`8`, `851.00` in §1.3) - but the oracle arm shows
  the *law already repairs* the one misread digit on pump-337, and T3 does nothing for locating the
  right fields or keeping the advert out, which are the actual failures. Useful hardening after T1;
  not the first move.
- **Cheapest falsifier:** n/a (it answers a question T1 may make moot).

### Option T4 - keep RowSeg off the advert (required by whichever route)

- **Method:** the advert is full-colour cycling imagery; the numbers sit on white fields. Either
  (a) add advert-like synthetic negatives to `segdata`'s negative set (today's negatives are
  receipts/screenshots/fiscal/expenses, `detdata.py:42` - screenshots carry some colourful UI but
  nothing like a forecourt advert), or (b) mask high-saturation regions before the locator
  (a saturation threshold in `PumpRowSegmenter.letterbox`'s input prep), or (c) both.
- **Measured basis:** on pump-337 two of the four kept rows are advert words (§1.3); on the
  Capture Lab's 7 Run-2 shots both locators framed advert text (CAPTURE-LAB.md Runs 2-3).
- **Hard rule framing:** the danger is not a wrong commit - the law refused everything on all 14
  lab shots - but *wasted* rows that crowd out the real ones and mislead roles. Any option that
  lets advert text reach the law as a candidate is acceptable **only** because the law's exact
  close is the backstop; an advert number that happens to close (a `2x` bonus beside a real pair)
  is the scenario to design against: prefer candidates on white fields, prefer rows that stack with
  a label, and never let a number with no label-neighbour or column-mate validate a pair alone.
- **Cheapest falsifier for (b):** one-off script - threshold saturation on pump-337, count how many
  of the four kept rows survive (inference: the advert rows die, the white-field rows live).

## 5. One family-detection step or two separate fixes? (question 4)

**One small step, and it pays for itself** - because the two families want different readers
(Vision vs RowRead) and the wrong route is asymmetric: RowRead on TFT abstains safely (measured:
nothing committed anywhere), while Vision on a black LCD drops decimal points (measured: `2999`
for `29.99`, §1.4) - exactly the factor-of-ten failure the reader exists to prevent. So the router
must be confident before sending anything to the Vision branch, and may default to the segment
reader on doubt.

Form, cheapest first:
1. **Statistics** (free, no model): TFT = high near-white pixel fraction around the text lines +
   high colour saturation elsewhere + Vision line count in the receipt range + located rows whose
   strips lack segment pitch (the slicer's autocorrelation pitch fails on proportional fonts -
   `PumpGlyphSlicer.swift:205-215`). Each signal exists in the pipeline today.
2. **A learned bit** if statistics do not separate: MobileNetV3-small-class classifier
   (Sber's precedent: type classification at 0.99 accuracy before any reading, Habr 670568).
   Cost on the iPhone 12 floor (inference from the shipped models' numbers): a 1-3 MB Core ML
   model at single-digit ms on the Neural Engine - the same envelope as RowSeg (1.8 MB, ~27 ms
   Mac). Bundle and latency budgets can carry exactly one such model.

But note the ordering: the classifier is only worth training when there are enough TFT photos to
train and measure it (today: 1 still). Statistics first.

## 6. What the published work says (question 5)

Fetched and checked; nothing here contradicts the ranking above.

- **PixelLink** (Deng, Liu, Li, Cai, AAAI 2018, arXiv:1801.01315 - abstract fetched): instance
  segmentation by linking pixels; "better or comparable performance ... with many fewer training
  iterations and less training data" - the property L1 relies on. It says nothing about polarity;
  the corpus's emissive heads already prove the architecture tolerates light-on-dark when trained
  on it.
- **CRNN** (Shi, Bai, Yao, TPAMI 2017, arXiv:1507.05717 - abstract fetched): sequence recognition
  without character segmentation, lexicon-free. This is RowRead's architecture; its TFT misreads
  are a training-fonts question (T3), not an architecture limit.
- **Laroca et al., AMR in unconstrained scenarios** (arXiv:2009.10181, IEEE Access 2021 - abstract
  fetched): a *counter classification* stage that rectifies and **rejects illegible meters before
  recognition**, and >99 % recognition only with confidence-based rejection - the same two ideas as
  §5's router and this app's law/abstain design. Independent precedent that a type/route stage plus
  refusal is the shape that survives the field.
- **Salomon, Laroca, Menotti** (arXiv:2005.03106, IJCNN 2020 - abstract fetched): dial meters;
  detection at 100 % F1, recognition the hard part (93.6 % per dial, 75.25 % per meter) with a
  detailed error analysis. Relevant as meter-reading context only (analogue dials, not displays).
- **Habr 792376** (fetched): seven-segment reading *without* ML by comparing each segment zone
  against the digit's own background and thresholding the difference into a segment bitmask ->
  digit signature. Its framing is polarity-free by construction (difference from background, not
  absolute brightness) - the same property the slicer's percentile rule has. Useful as a
  cross-check idea, not as a replacement: it needs a fixed per-display segment layout, which an
  unconstrained phone photo does not have.
- **Habr 670568 (Sber)** (fetched): the full industrial meter-OCR pipeline. The transferable
  decisions: (1) a cheap type classifier first (MobileNetV3, 0.99); (2) a *separate* orientation
  classifier beat rotation augmentation (0.99); (3) a sequence model (LSTM/CTC family) for the
  digits, with the decimal separator as a sequence token and a second loss on its position
  (+8.85 % accuracy) - RowRead's separator class is the same idea, already shipped; (4) digit-mixing
  augmentation as the accuracy lever; (5) ≥1000 photos per new task as their rule of thumb. Their
  glare note also matches this family: "on digital meters the separator is hard to find even for
  the human eye" under reflections.
- **Inverse-polarity / screen-content text:** no specific paper was fetched for this sub-question;
  I do not describe one from memory. What the corpus itself says is stronger anyway: light-on-dark
  emissive displays are already read at the shipped floor, so polarity robustness is demonstrated
  in-tree, and the black-LCD gap is measured above to be locate-stage, not read-stage.

## 7. Recommendation (question 3 of "what the note must contain")

**Dark LCD, light ink - do L1 first (retrain RowSeg on the stills and a verified frame sample the
corpus already holds), then L4 (locator-level Live-frame fusion) only if glare still defeats the
retrained locator.** Skip L3 (measured unnecessary), defer L2 (whole-image inversion is the wrong
synthesis), reject L5 (measured). Do not touch the renderer for this family until the locator moves
- synthetic light-on-dark does not reach RowSeg's real-only training data.

**TFT - do T1 first (family route to on-device Vision OCR + the unchanged law), with T4 (advert
suppression) as part of the same change and T2 (labels) as a cross-check, not a gate.** Defer T3
(rendered-font RowRead) until T1's limits are measured on more than one head. Route by statistics
first; a learned family bit waits for a TFT population worth training on (today: one still).

**Must NOT be done (hard rule: a wrong number is worse than none):**
- No path where Vision's raw tokens pre-fill a field without passing `PumpReadingLaw`'s exact
  close - the advert's digits and the dp-dropped `2999` are both real outputs measured above.
- No loosening of the classification floors (`minimumRows`, `minimumWidestRowFraction`,
  `PumpDisplayCapture.swift:71-95`) to let these frames through: on pump-339/340 the floor is the
  only thing between the user and a board-cell "total".
- No committing from the cautioned pair tier on this family without looking at the caution:
  pump-339's oracle arm commits litres `15.21` for `15.31` under `priceDisagrees` - a misread
  digit inside a legitimate-looking discount band. That tier's precision on new families is
  unmeasured (§8).
- No training or tuning against pump-335 (heldout2) - it is the only member of either family in a
  measurement set, and it stays untouched until a change is judged.

## 8. What stays unknown, and what would settle it

1. **Whether L1's data is enough.** 4 train stills + a verified sample of ~1 264 unreviewed frames
   (video-050: 831; live-6402/04/05/24/25: 433) of exactly two stations (one Alexela, one Neste
   head). Settles: the retrain itself, judged on the rotated gate + these stills + the video
   frames. If it fails, the ask is captures of more black-LCD stations - 10-20 fills across 3+
   chains, each with its Live record, would move this from "two heads" to "a family".
2. **Whether PU.62's rules arm already fills pump-337 in the app** (CapturePipeline fills
   reader-abstained fields from the receipt parser). The §1.4 probe says Vision sees a perfect
   closing triple on this still, so the arm may already commit it - right here, but by a path with
   no family gate, and on another TFT it could commit advert numbers that happen to close. One
   ReceiptSpike run on pump-337 settles it (not run: the brief's build allowance covers
   `pump-read` only).
3. **TFT generality.** One make, one station, one language of labels. Settles with 5-10 TFT photos
   from other chains/countries; until then T1 ships behind statistics tuned to be conservative.
4. **The cautioned pair tier on new families.** pump-339's oracle committed a wrong litres value
   under caution; the tier carries no precision floor by design (decision 11). Whether that is
   acceptable on families the reader barely knows is a product call, not a measurement.
5. **heldout2 has exactly one family member (pump-335, an idle display).** Any future change for
   these families is judgeable on heldout2 at n=1, and on an idle display at that. The next black
   LCD or TFT *fill* capture should join heldout2 as a whole fill, per the intake rule.
6. **Capture-time help for glare.** L4 (multi-frame) is unbuilt; polarising-free tricks (asking the
   user to move, exposure bias) are unmeasured beyond Run 3's negative. If L1 lands and glare still
   caps recall, the Capture Lab's night/glare runs are the settling instrument.

---

### Appendix - raw per-frame results (the numbers behind §1)

Live path, `pump-read`, currency EUR, HEAD of 2026-09-26. `display`/`rows`/`widest`/`path` from
`appDecision`; texts from `rowTexts`; law from `abstainReason` / `appCommitted`.

Stills:

| still | display | rows | widest | path | texts | law |
|---|---|---|---|---|---|---|
| pump-117 | yes | 3 | 0.29 | slow | `113.99`, `52.65`, `2.165` | commits, all correct |
| pump-144 | yes | 3 | 0.30 | slow | `113.99`, `52.65`, `2.165` | commits, all correct |
| pump-332 | no | 1 | 0.075 | slow | `liters 2.06` | not routed |
| pump-334 | yes | 2 | 0.27 | fast | `liters 0.00` | `litersAllZero` (idle, correct) |
| pump-335 | yes | 2 | 0.30 | fast | `liters 0.00` | `litersAllZero` (idle, correct) |
| pump-337 | yes | 3 | 0.34 | fast | `liters 3190.00`, `unitPrice 70.80` | `noTotalWindow` |
| pump-339 | no | 1 | 0.22 | slow | `total 2.39920`, `liters 0009`, `board 2.069` | not routed |
| pump-340 | no | 2 | 0.170 | slow | `total 19.6` | not routed |
| pump-341 | yes | 3 | - | fast | `0.00`, `0.00`, `1.219` all correct | `litersAllZero` (idle, correct) |

video-050 frames (7 sampled): display=no on all; rows 0-3; widest 0-0.160; frame 250 read
`32.93 / 15.84` (implied 2.0789 vs asserted 2.079 - correct running read), refused
`priceUnvalidated`; others `noTotalWindow` / `cellCountImpossible` / `noLitersWindow`.

video-051 frames (5 sampled): display=yes on 3; frame 001 read `35.00` + `72.80` (both correct,
refused `priceUnvalidated`); 030/100 `85.00`; 066 `35.00` + `01.2219`; 133 `851.00` + `7212`.

Live frames (12 sampled): live-6402 0/3 classified; live-6404 (idle) 2/3, `0.00` correct;
live-6424 1/3, dp-dropped reads (`2999`, `299`); live-6420 3/3 classified, digit misreads
(`22.80`, `85.00`, `31999.9`), all refused by the law.

Oracle arm (hand quads, incl. boards where annotated): pump-332/334/335 `0.00`/`0.00` correct;
pump-337 commits `72.8 / 35 / 2.08` fully correct (law repaired the `85.00` misread); pump-339
commits `29.99` correct + `15.21` wrong (caution); pump-340 commits `10.01 / 19.61` both correct
(caution from a board misread `1.954`).

Vision probe (macOS, accurate, no language correction): pump-337 -> `72,80`, `35,00`, `2,080`,
labels `SUMMA`/`LIITRIT`/`€/L`, advert words read as words; pump-339 -> `2999` (dp dropped),
boards `1959`/`2399`/`20 19`, no litres; pump-332 -> stickers only, no display digits.
