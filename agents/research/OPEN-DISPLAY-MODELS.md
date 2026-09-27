# RESEARCH-OPEN-DISPLAY-MODELS - published models that read pump / meter displays

*Research note for the product owner's question, 2026-09-27: "Is there hugging face models
published that allow recognize data from ink/tft/lcd screens already? Likely, our case is not
unique and there are open trained models published already." Research only - a ranked survey with
evidence, not an integration. Researcher: k3, 2026-09-27. Read-only except this file and
`/tmp/open-display-models/`. Evidence rule: every claim cites a page fetched in this run
(fetch log in the appendix); licences are quoted from the page; inference is labelled; measured
numbers carry their command. All fetches 2026-09-27.*

## Verdict up front

**Nothing published beats the domain pipeline on our photos, and the honest answer is mostly "here
is why"** - but the survey was worth running, and two findings are worth keeping:

1. **There is no published fuel-dispenser display model or dataset at all.** arXiv carries zero
   papers for fuel-dispenser display recognition (query `all:"fuel dispenser" AND all:recognition`:
   0 entries, 2026-09-27); Hugging Face has no model for it; Roboflow Universe's only fuel-pump
   datasets are 244 and 50 images classifying pump *makes*, not readings. Our case is close to
   unique in public: the neighbouring literatures are utility meters (water/gas/electricity) and
   medical-device displays, and both solve an easier problem - one window, one value, known device.
2. **The strongest permissively-licensed general OCR (PaddleOCR PP-OCRv5 mobile, Apache-2.0),
   measured today on our own photos, fails exactly where our pipeline fails and only matches it
   where we already succeed.** It reads 0 of the 4 dark-LCD stills' transaction values (the family
   our locator cannot find), reads the TFT triples exactly (the family on-device Vision already
   reads exactly, PU.90), and on the Gilbarco dark-on-light control it beats Vision by keeping the
   decimal points (`02038.00`, `00040.00`) - a family our RowRead already reads at the gate's
   0.992 precision. A published model that loses on our hard family and ties on our solved
   families is not an integration candidate; it is a cross-check at most.

The single experiment worth running is not an adoption test but a **capacity probe**: a big
server-side VLM (Qwen2.5-VL-7B, Apache-2.0, through the existing LLM gateway) on the dark-LCD
stills `pump-332`, `339`, `340`, `344`. If a 7B VLM cannot read pale-on-black-glass either, the
locator-retrain path (PU.90 option L1) is confirmed as the right spend; if it can, that family
becomes a gateway candidate. Everything else in this note is adopt-nothing.

## 0. What we compare against (the in-house baseline, as shipped)

Device-side pipeline (`docs/EXTRACTION.md` -> "The pump reader", code in
`ios/Sources/TankbookCore/Extraction/PumpReader/`): a PixelLink-style row locator (RowSeg,
1.8 MB), a CRNN+CTC row reader (RowRead, 1.01 M parameters), an 8-sigmoid seven-segment cell
classifier, and `PumpReadingLaw` (`volume x price = total`, commits only what closes). Gate:
precision >= 0.99 on committed cells, coverage >= 0.60; current marks 122/121 committed/correct of
183 heldout cells (precision 0.992, coverage 0.667). The measured gaps (PU.90,
`agents/research/PU.90.md`): the **dark-LCD light-ink** family (pump-332/334/335/339/340/344)
fails at the *locator*, and **TFT** heads (pump-337/354/355/356) fail at role assignment and
proportional-font digits - while on-device Apple Vision reads the TFT triple exactly (PU.90 §1.4).
So the two questions a published model could answer are: (a) does anything locate + read
pale-on-black-glass LCDs, (b) is there a better full-scene reader for TFT than the Vision route
already measured.

## 1. Published models: seven-segment / meter / display reading

### 1.1 What Hugging Face actually holds

HF API searches 2026-09-27 (`/api/models?search=` for `seven segment`, `7-segment`,
`meter reading`, `meter-reading`, `digital meter`): the entire dedicated population is:

| Model | Task / shape | Licence (as published) | Size, recency | Verdict |
|---|---|---|---|---|
| `sgenzer/seven-segment-led` ([card](https://huggingface.co/sgenzer/seven-segment-led)) | Swin **image classifier**, single cropped digit per image; AutoTrain; val accuracy 0.868 | **None stated** on the card (no license tag) - unusable in a shipping app until clarified | 27.6 M params, Sep 2023, 56 downloads | **Ignore**: no licence, single-crop only, no detection, 0.868 val |
| `Beni4/rwanda-water-meter-reading-yolov8n` | YOLOv8n digit detector, Rwanda water meters | **AGPL-3.0** (card tag) - copyleft, incompatible with a closed app bundle | Jul 2026, 28 downloads | **Ignore**: licence |
| `alreaper/Rwanda_Water_Meter_Reading` | YOLO digit detector | Apache-2.0 (card tag) | May 2026 | **Ignore**: one utility's meters, cropped-counter shape |
| `Omar-Elnaggar/meter-reading-models` | raw `.pt` checkpoints (`best_numbers_digital2.pt`, `best_reading_area4.pt`, ...) | **None stated**, no README | Sep 2025 | **Ignore**: no licence, no card, no evaluation |
| `Seeed-Studio/digital_meter_water` | object detection, tag MIT | MIT tag, but the repo holds **only a README** - no weights (siblings listing) | Aug 2023 | **Ignore**: nothing to run |
| `s2021sss/Meter-reading-recognition`, `TaLuksss/Meter_Readings` | no pipeline tag, no card info | none stated | 2024/2025 | **Ignore** |

That is the whole HF shelf for the exact ask. Nothing in it handles a full pump-head scene.

### 1.2 The meter-reading systems that actually work (and why they do not transfer)

- **jomjol/AI-on-the-edge-device** ([repo](https://github.com/jomjol/AI-on-the-edge-device),
  8.8k stars, fetched 2026-09-27): ESP32-CAM + TFLite CNN digit classifiers for water/gas/power
  meters. The architecture assumes a **fixed camera on one known meter with hand-configured ROIs**
  ("Inline image processing (feature detection, alignment, ROI extraction)" - README). That is the
  opposite of our input (hand-held phone, unknown head, several rows plus a price board). Licence:
  **"Dual Use License... freely for private, non-commercial purposes. Any commercial use requires a
  separate licensing agreement"** (`Licence.md`, fetched). **Ignore** on both axes.
- **Laroca et al., AMR in unconstrained scenarios** (arXiv:2009.10181, abstract fetched): three
  cascaded networks with a corner-detection/counter-classification stage that rectifies and
  **rejects illegible meters**, >99 % recognition only with confidence-based rejection. Weights are
  not published as a deployable model; the datasets are non-commercial (§3). The *ideas* (a
  type/route classifier before reading; refusal as a first-class outcome) are already in our
  pipeline and were already absorbed by PU.90. **Already adopted as method; nothing to adopt as
  artifact.**
- **Medical-display work** (the closest academic neighbours with smartphones in the loop):
  arXiv:1807.04888 *"Utilizing Smartphone-Based ML in Medical Monitor Data Collection: Seven
  Segment Digit Recognition"* (blood-pressure gauges, glucose monitors, scales) and
  arXiv:2210.01325 *"Automated Medical Device Display Reading Using Deep Learning Object
  Detection"* (EfficientDet detection + recognition; abstracts fetched). Both are **one device,
  one window, one reading**; no public weights surfaced in this run (not checked beyond the
  abstract - labelled). Useful as evidence the single-window problem is solved; irrelevant to a
  multi-row pump head.

### 1.3 Roboflow Universe and Kaggle

Roboflow search `seven segment display` (2026-09-27): **300 datasets**, almost all 100-3,000-image
**digit-detection** sets (classes `0-9`, `dot`), many with a trained YOLO attached. They answer
"crop to digit" - a stage we synthesize at scale with the glyph renderer (`ml/pump-reader`).
Licences are per-dataset on Roboflow (not checked individually; labelled as unverified). Search
`fuel dispenser`: two pump-specific datasets - "Dispenser" (244 images, digit classes) and
"dispenser spbu" (50 images, classes are Gilbarco/Tatsuno **makes**, Indonesian SPBU stations) -
neither carries display *readings*. Kaggle: not fetched (JS-walled); the Roboflow/HF coverage makes
a larger fuel-display corpus there unlikely - labelled inference.

## 2. Relevance to OUR photos

The separating question the brief asks: cropped single-meter image vs full pump-head scene. Every
dedicated model above is the former. Our photo is the latter: several digit rows, a grade-price
board, glare, tilt, 3-8 digit windows, a decimal mark that decides the value, and (dark-LCD
family) forecourt reflections on black glass. The measured consequence: the failure stage on our
hard family is **location**, and no published artifact addresses location on that look - the
general OCR detectors below find the rows and still misread or miss the values (§4, measured).

## 3. Datasets we could train or evaluate on (licence first)

| Dataset | Size / labels | Licence (quoted from the fetched page) | Usable? |
|---|---|---|---|
| **UFPR-AMR** ([repo](https://github.com/raysonlaroca/ufpr-amr-dataset), README fetched) | 2,000 warehouse images, 3 phones, 5-digit counters, counter box + **per-digit boxes** + reading | "released for academic research only and is free to researchers from educational or research institutes for **non-commercial purposes**" | **No** - a shipping app is commercial use |
| **Copel-AMR** ([repo](https://github.com/raysonlaroca/copel-amr-dataset), README fetched) | 12,500 field images (2,500 illegible), counter corners + digit boxes + reading | "released **only** to academic researchers ... for **non-commercial purposes**"; signed agreement by an institution head | **No** |
| `goodcoffee/Meter_Reading` ([HF](https://huggingface.co/datasets/goodcoffee/Meter_Reading)) | 1K-10K rendered-looking frames (`v_0001_f_0000_rgba.png/json` naming), JSON labels | `apache-2.0` (card) | Technically yes; small and synthetic-looking - our renderer already covers this need. **Skip** |
| `tomasko1987/seven-segment-digits` ([HF](https://huggingface.co/datasets/tomasko1987/seven-segment-digits)) | card says 100K<n<1M but modality tag is `text` - content unverified | `mit` (tag) | Unverified; **skip** |
| Roboflow seven-segment sets (~300) | digit boxes, 60-20k images each | per-dataset, unverified | Digit crops only; we synthesize those. **Skip** |
| Fuel-dispenser readings | **does not exist publicly** (§1.3, arXiv 0 hits) | - | Our own corpus is the only one we know of |

## 4. General VLM/OCR baselines (the realistic candidates)

Licences as tagged/quoted on the fetched pages; "on-device" is judged against the iPhone 12 floor
(A14, 4 GB) - architecture/size judgements are **inference** unless a measurement is named.

| Model | Licence | Size | Evidence on displays | On iPhone 12? | Verdict |
|---|---|---|---|---|---|
| **Apple Vision** (`VNRecognizeTextRequest`) | platform | built-in | **Measured today** (below) and in PU.90: TFT exact; Gilbarco digits right, decimal point dropped; dark LCD nothing | Already shipped (receipt path) | **Adopted already** for the TFT route (PU.90 T1) |
| **PaddleOCR PP-OCRv5 mobile** ([repo](https://github.com/PaddlePaddle/PaddleOCR), LICENSE fetched) | **Apache-2.0** ("Copyright (c) 2016 PaddlePaddle Authors") | det+rec models 21 MB total (measured: `~/.paddlex` after download); rec model 16 MB per the [model list](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/module_usage/text_recognition.en.md) | **Measured today** (§6): TFT triples exact on 337/354; keeps decimal points Vision drops (pump-009); 0/4 on dark LCD | Yes in principle (mobile-targeted; Core ML conversion via ONNX is an inference, untested here) | **Evaluate** as a second-opinion reader only (§5) |
| Surya ([repo](https://github.com/datalab-to/surya), LICENSE fetched) | **Apache-2.0** | line detection + recognition, hundreds of MB | not measured; document/scene OCR | No (too heavy) | Ignore for v1; a server-side option if the gateway ever wants OCR without an LLM |
| TrOCR `microsoft/trocr-base-printed` ([card](https://huggingface.co/microsoft/trocr-base-printed)) | **no licence field on the card** (observed) | 333 M params | line recognizer trained on printed text (SROIE crops on the card); not measured here | Possible but pointless: our RowRead is 1.01 M params doing the same stage | **Ignore** unless a read-stage question reopens |
| Donut `naver-clova-ix/donut-base` ([card](https://huggingface.co/naver-clova-ix/donut-base)) | `mit` (tag) | document transformer | document parsing, needs task fine-tune | No | **Ignore** |
| Florence-2 `microsoft/Florence-2-large` ([card](https://huggingface.co/microsoft/Florence-2-large)) | `mit` (tag) | 0.77 B (large) / 0.23 B (base) | general caption/region OCR; not measured | Base, maybe (custom code conversion; inference) | **Ignore**: generalist; Vision+Paddle already cover its role cheaper |
| GOT-OCR2.0 `stepfun-ai/GOT-OCR-2.0-hf` ([card](https://huggingface.co/stepfun-ai/GOT-OCR-2.0-hf)) | `apache-2.0` (tag) | 560 M params BF16 | document OCR VLM; not measured | No (A14 unrealistic; inference) | Server-class; **ignore** while Qwen-VL exists |
| Qwen2.5-VL **7B** ([card](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct)) | `apache-2.0` (tag) | 8.3 B BF16 | strongest open VLM OCR line; not measured on our photos | No - **server via the existing LLM gateway** (hard rule 9's gateway) | **Evaluate** as the capacity probe (§5) |
| Qwen2.5-VL **3B** ([card](https://huggingface.co/Qwen/Qwen2.5-VL-3B-Instruct)) | **`qwen-research`** (cardData) - research-only, **not commercial** | 3.75 B | - | - | **Ignore on licence**; the licence split by size is the trap here |
| MiniCPM-V 4.6 / MiniCPM-o 4.5 ([README](https://github.com/OpenBMB/MiniCPM-V) fetched) | **"The MiniCPM-o/V model weights and code are open-sourced under the Apache-2.0 license"** (README, quoted) | 1.3 B (V 4.6) / 9 B (o 4.5) | README claims OCRBench 876 (o 4.5), ships an iOS app + deployment guide for V 4.6 | V 4.6 is the one published VLM family explicitly targeting phones (vendor iOS guide) | **Watch**, do not evaluate yet: a 1.3 B VLM on-device is a product-size decision, not a pump-reader fix |
| PaliGemma `google/paligemma-3b-mix-224` ([card](https://huggingface.co/google/paligemma-3b-mix-224)) | `gemma` (tag), gated | 2.9 B | generalist VQA; OCR not its strength | No | **Ignore** |
| EasyOCR ([LICENSE](https://raw.githubusercontent.com/JaidedAI/EasyOCR/master/LICENSE) fetched), docTR ([LICENSE](https://raw.githubusercontent.com/mindee/doctr/main/LICENSE) fetched) | Apache-2.0 both | CRNN-CTC stacks | same architecture family as our RowRead; Paddle measured stronger in practice (inference from the PP-OCRv5 result, not a head-to-head here) | possible, heavyweight Python stacks | **Ignore**: nothing over PaddleOCR |

## 5. Recommendation

**Adopt: nothing. Evaluate: one probe. Ignore: the rest.**

- **The single most promising experiment (capacity probe, not adoption):** Qwen2.5-VL-7B-Instruct
  (Apache-2.0) **server-side through the existing LLM gateway**, prompted for the three values with
  their positions, on the dark-LCD stills **`pump-332`, `pump-339`, `pump-340`, `pump-344`** plus
  TFT `pump-337`, `pump-354`-`356` and Gilbarco `pump-009`, `pump-026` as controls (truth:
  `expected.csv` - e.g. 339 = 15.31 L / 29.99, 340 = 10.01 / 19.61, 344 = 0.00 / 0.00,
  337 = 35.00 / 2.080 / 72.80). **Success bar that would justify anything further:** the VLM reads
  the transaction rows on at least 3 of the 4 dark-LCD stills *with decimal marks* (Vision and
  PaddleOCR both scored 0/4 there today). If it fails too, that is strong evidence the family is a
  data problem, not a capacity problem, and PU.90's L1 (retrain RowSeg on the corpus's own
  dark-LCD material) is confirmed as the right spend. Cost: one gateway prompt template and ~10
  images; no client change.
- **Cheap but low marginal value (only if the TFT route stalls):** PP-OCRv5 mobile as a second
  reader on the TFT/Gilbarco families behind the unchanged law. Measured today it matches Vision
  on TFT and beats it on decimal points for pump-009 - but RowRead already reads that family at
  gate precision, so the measured delta over the shipped pipeline is zero on the gate families and
  zero on the hard family. Run it across the heldout split only if PU.90's T1 (Vision TFT route)
  underperforms on new TFT photos.
- **Everything in §1 (dedicated seven-segment/meter models): ignore.** Licences (none, AGPL,
  dual-use non-commercial, dataset non-commercial) or problem shape (single cropped window, fixed
  camera) disqualify every one.
- **Datasets: none usable.** UFPR-AMR/Copel-AMR are non-commercial; the HF/Roboflow seven-segment
  sets are digit crops our renderer already makes. Our corpus remains the only fuel-dispenser
  display corpus we can find - which is also the answer to "our case is not unique": **the case is
  close to unique; the families are not** (meters and medical displays are the same segments,
  one window at a time).

**Honest bottom line:** nothing published beats the domain pipeline on this task. The measured
evidence is that a strong, permissively-licensed, mobile-targeted general OCR (PP-OCRv5 mobile)
reproduces our pipeline's failures on the hard family and its successes on the easy ones, and the
only published systems that truly work on seven-segment hardware (jomjol, Laroca's AMR) solve a
geometrically fixed or licence-locked problem. The published world can still help in two places:
the **7B-VLM capacity probe** above (it tells us whether dark-LCD is learnable at all before we
spend annotation time), and **MiniCPM-V 4.6** as the model to watch if a future task wants a
general on-device scene reader.

## 6. Smoke test (run, 2026-09-27, this Mac: Apple M5 Pro)

Setup (all inside `/tmp/open-display-models/`, nothing system-wide; the 21 MB of Paddle models
landed in `~/.paddlex` by paddleocr's default and were deleted after the run):

```
python3.12 -m venv /tmp/open-display-models/venv && pip install paddlepaddle paddleocr   # paddleocr 3.7.0, paddlepaddle 3.3.1, exit 0
swiftc -O /tmp/open-display-models/visionprobe.swift -o /tmp/open-display-models/visionprobe   # VNRecognizeTextRequest, accurate, no language correction
/tmp/open-display-models/venv/bin/python /tmp/open-display-models/paddleprobe.py <10 photos>   # PP-OCRv5_mobile_det + PP-OCRv5_mobile_rec, CPU
```

Timing (PaddleOCR, CPU, 12 MP stills, one warm run each): pump-337 **6.3 s**, pump-009 **3.2 s**
(command: `/usr/bin/time ... python -c ...`, printed `photo1 6.3s photo2 3.2s`). Vision: seconds
for all 10 photos total (not individually timed; PU.90 measured 6-36 ms/photo on 12 MP).

Readings vs `expected.csv` (raw logs: `/tmp/open-display-models/{vision-out,paddle-out}.txt`):

| Photo (family) | Truth (litres/price/total) | Apple Vision | PaddleOCR PP-OCRv5 mobile |
|---|---|---|---|
| pump-009 (Gilbarco, dark-on-light) | 40.00 / 50.95 / 2038.00 | `0004000`, `05095`, `0203800` - digits right, **all decimal points dropped** | `00040.00`, `02038.00` **exact with dps**, price `05095` (dp dropped) |
| pump-026 (Gilbarco, comma) | 53.81 / 1.924 / 103.53 | `0353`, `1053,8 1` garbled, `1924` (dp dropped) | display values **not found** (label noise dominates) |
| pump-332 (dark LCD, idle) | 0.00 / - / 0.00 | stickers only, no display digits | stickers only, no display digits |
| pump-339 (dark LCD) | 15.31 / - / 29.99 | `2999` (**dp dropped**), litres not read; boards read | transaction rows **not found at all**; one board `1959` |
| pump-340 (dark LCD) | 10.01 / - / 19.61 | `104 1 2` garbled litres; total not read | transaction rows **not found**; boards partial |
| pump-344 (dark LCD, idle, rain) | 0.00 / - / 0.00 | `000` (digits, dp dropped); board `2059` | display zeros **not found**; board `889` |
| pump-337 (TFT) | 35.00 / 2.080 / 72.80 | **`35,00`, `2,080`, `72,80` exact** + labels SUMMA/LIITRIT/€/L | **`35,00`, `2,080`, `72,80` exact** + labels |
| pump-354 (TFT) | 20.20 / 2.039 / 41.19 | **`20,20`, `2,039`, `41,19` exact** | **`20,20`, `2,039`, `41,19` exact** |
| pump-355 (TFT) | 10.90 / 2.039 / 22.23 | `10,90`, `22,23` exact; price label only (`EUR/L`) | `10,90`, `2,039`; total split as adjacent tokens `22`+`23` |
| pump-356 (TFT, second angle) | 10.90 / 2.039 / 22.23 | `10,90`, `22,23`, `2,039` all exact | `2,039`; total/litres split as `22`+`10`+`90` |

Read of the table: on TFT both general OCRs are already at ceiling (matching PU.90's T1 premise);
on Gilbarco, PaddleOCR keeps the decimal points Vision loses - the one place a general model
measured *better* than our shipped fallback reader, on a family RowRead already reads; on the
dark-LCD family **both general readers score 0/4 on transaction values**, exactly the stage and
family where RowSeg fails. No published model we ran sees through pale-on-black-glass reflections
either.

Not run (over the 30-minute budget): TrOCR on row crops (1.3 GB download for a stage that is not
the bottleneck), MiniCPM-V 4.6 on-device (a product-size evaluation, not a probe), Surya.

## Appendix - fetch log (all 2026-09-27)

| Source | What it established |
|---|---|
| HF `/api/models?search=seven segment` / `7-segment` / `meter reading` / `meter-reading` / `digital meter` | the full dedicated-model population (§1.1) |
| HF card `sgenzer/seven-segment-led` | Swin classifier, 27.6 M, val acc 0.868, **no licence tag** |
| HF API `Qwen/Qwen2.5-VL-3B-Instruct` | cardData `license_name: qwen-research`; 3.75 B BF16 |
| HF API `Qwen/Qwen2.5-VL-7B-Instruct` | tag `license:apache-2.0`; 8.3 B BF16 |
| HF API `microsoft/Florence-2-large` | tag `license:mit`; 0.77 B F16 |
| HF API `microsoft/trocr-base-printed` | 333 M F32; **card carries no licence field** |
| HF API `naver-clova-ix/donut-base` | tag `license:mit` |
| HF API `stepfun-ai/GOT-OCR-2.0-hf` | tag `license:apache-2.0`; 560 M BF16 |
| HF API `google/paligemma-3b-mix-224` | tag `license:gemma`, gated manual |
| HF API `openbmb/MiniCPM-V-2_6` | 8.1 B BF16, gated auto; raw README 401 (gated) |
| GitHub `OpenBMB/MiniCPM-V` README (raw) | "The MiniCPM-o/V model weights and code are open-sourced under the Apache-2.0 license"; MiniCPM-V 4.6 = 1.3 B, iOS/Android/HarmonyOS deployment guide |
| GitHub `jomjol/AI-on-the-edge-device` README + `Licence.md` | fixed-camera ROI pipeline; "freely for private, non-commercial purposes... commercial use requires a separate licensing agreement" |
| GitHub search API `meter reading digits` | long tail of 2-23-star student projects; nothing else of weight |
| arXiv API `all:"fuel dispenser" AND all:recognition` | **0 entries** |
| arXiv API `all:"seven-segment"` | 1807.04888, 2210.01325 (medical displays; abstracts fetched) |
| arXiv:2009.10181 abstract | Copel-AMR 12,500 images; reject-illegible stage; >99 % only with rejection |
| GitHub `raysonlaroca/ufpr-amr-dataset` README | 2,000 images, per-digit boxes; "academic research only ... non-commercial purposes" |
| GitHub `raysonlaroca/copel-amr-dataset` README | 12,500 images, corners+digit boxes; "only to academic researchers ... non-commercial purposes" |
| HF datasets search `meter reading`, card `goodcoffee/Meter_Reading` | Apache-2.0, rendered-looking frames |
| Roboflow Universe search `seven segment display` / `fuel dispenser` | 300 seven-seg digit sets; 2 tiny fuel-pump sets, no readings |
| PaddleOCR `LICENSE` (raw) + PP-OCRv5 model-list doc | Apache-2.0; PP-OCRv5_mobile_rec 16 MB |
| EasyOCR / docTR / surya `LICENSE` (raw) | Apache-2.0 all three |
| Local: `Spike/ReceiptSpike/fixtures/pump/expected.csv` | truth values quoted in §6 |

Failed/not fetched (and therefore not described beyond what is stated): MiniCPM-V HF card licence
text (401, gated - the GitHub README quote above stands instead); Kaggle (JS-walled); individual
Roboflow dataset licences (per-dataset, unverified); TrOCR's licence (no field on the card -
the code repo is MIT but the weights' page does not say so, so the card silence is what is
reported).
