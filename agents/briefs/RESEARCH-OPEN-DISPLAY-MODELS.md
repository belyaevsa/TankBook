# RESEARCH-OPEN-DISPLAY-MODELS – are there published models that already read pump / meter displays?

*Product owner, 2026-09-27: "Is there hugging face models published that allow recognize data from
ink/tft/lcd screens already? Likely, our case is not unique and there are open trained models
published already." Research only - a ranked survey with evidence, not an integration.*

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:
`agents/research/OPEN-DISPLAY-MODELS.md`**, and scratch files under `/tmp/open-display-models/`.
No code changes, no commits. You MAY download a small candidate model into the scratch folder and
run it on a handful of corpus photos if that is quick (see "Optional: a smoke test").

## Write first, explore second

Create the note's skeleton in the first minutes and fill it as you go.

## What we have, so you can compare (read, do not change)

`docs/EXTRACTION.md` -> "The pump reader" and its amendments; code in
`ios/Sources/TankbookCore/Extraction/PumpReader/`; training code in `ml/pump-reader/`. A device-side
pipeline on iPhone (Core ML, iPhone 12 floor): a PixelLink-style row locator (RowSeg), a CRNN+CTC
row reader (RowRead), an 8-sigmoid seven-segment cell classifier, and an arithmetic law
(`volume x price = total`) that commits only what closes. Our own research notes, for context and
to avoid repeating them: `agents/research/PU.90.md` (dark LCDs and TFT), `PU.68.md`, and the
others in `agents/research/`. The corpus: `Spike/ReceiptSpike/fixtures/pump/` (~356 stills,
`expected.csv` truth, `windows.json` hand quads, `split.csv`), Live records and videos under
`pump-live/`. Display families we meet: dark-on-light seven-segment LCD (Gilbarco, Wayne,
Tokheim), light-on-dark LCD behind glass (Alexela, Neste), backlit LED/amber (Tatsuno), and TFT
screens with rendered proportional digits beside adverts (Tokheim at Olerex/Terminal).

## Questions the note must answer

1. **What is published?** Search Hugging Face (models and datasets), GitHub, Papers with Code,
   Roboflow Universe and arXiv for: seven-segment display recognition/OCR, digital meter reading
   (electricity/gas/water meters, weighing scales, fuel dispensers, calculators, thermometers,
   blood-pressure monitors), LCD/LED digit detection and recognition, and scene-text OCR that is
   evaluated on screens. For each candidate: name and link, task (detection / recognition /
   end-to-end), architecture and size, input, licence (**commercial use in an app?**), training
   data and its size, reported accuracy and on what, last update, and whether it can run on
   iPhone (Core ML conversion, size, speed).
2. **Which are genuinely relevant to OUR photos?** A hand-held phone photo of a whole pump head:
   several rows of digits, board price cells, glare, reflections, tilt, 3-8 digit windows, a
   decimal mark that decides the value. Separate models trained on cropped single-meter images
   from those that handle a full scene.
3. **Datasets** we could train or evaluate on (licence first): e.g. UFPR-AMR / Copel-AMR (meter
   reading, Laroca et al.), seven-segment datasets on HF/Roboflow/Kaggle, fuel-dispenser photos.
   Size, labels (boxes? strings? decimal marks?), licence.
4. **General VLM/OCR models** as a baseline for the hard families (TFT, light-on-dark): e.g.
   PaddleOCR / PP-OCR, TrOCR, Donut, Florence-2, PaliGemma, Qwen2-VL / Qwen2.5-VL small sizes,
   MiniCPM-V, GOT-OCR2, Apple's on-device Vision. Which can run on-device on an iPhone 12, and which
   only on a server (our LLM gateway already exists server-side - `docs/API.md`, hard rule 9's
   gateway)?
5. **A recommendation**: adopt / evaluate / ignore, per candidate, and the single most promising
   experiment - which model, on which corpus photos (name them: e.g. the dark-LCD stills
   `pump-332`, `339`, `340`, `344`; the TFT `pump-337`, `354`-`356`; a few Gilbarco controls), and
   what result would justify integrating it. Say plainly if the honest answer is "nothing
   published beats a domain pipeline on this; here is why".

## Optional: a smoke test

If a candidate is small, permissively licensed and runnable on this Mac in minutes (Python, CPU/MPS),
run it on 5-10 of the named corpus photos and report what it read against `expected.csv`. Use a
venv under `/tmp/open-display-models/`. Do not install anything system-wide. Skip it if it would
take more than about 30 minutes.

## Evidence rules

Every claim about a model cites its page (fetch it; if you cannot, say so and do not describe it
from memory), and licences are quoted from the page. Label inference as inference. Numbers you
measure carry the command that produced them.

## Report back

The note's path, the top three candidates in one line each (link, licence, on-device or server),
the most promising experiment, and the honest bottom line.
