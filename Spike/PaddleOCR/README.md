# PaddleOCR – ARCHIVED, measured and rejected (P4.13, 2026-08-26)

**Nothing here is part of any build.** No Swift target compiles it, no CI step runs it, and no
PaddleOCR code exists in `ios/Sources`, `ios/App` or `backend/`. It is kept as the reproducible
evidence behind a decision, not as a dependency.

## The verdict

PaddleOCR was measured as a third extraction arm against the rules parser (Apple Vision) and the
DeepSeek cloud model, over the whole corpus, with the **same scorer at the same tolerance**:

| class | rules (Vision) | Arm A (PaddleOCR) | DeepSeek cloud |
|---|---|---|---|
| receipts | 46/96 | **29/96** | 84/96 |
| pump | 1/46 | 2/46 | 31/46 |
| screenshots | 7/24 | 7/24 | 22/24 |
| fiscal | 1/3 | 1/3 | 2/3 |

**It does not earn the gateway's fallback slot.** It is worse than on-device Vision on receipts,
its latency is above the 3 s device budget in **every** class (median 4.5-8.4 s on CPU, so
self-hosting buys no latency back without a GPU), and Arm B (`PaddleOCR-VL-0.9B`) could not run at
all on this machine - `paddlex` calls `paddle.amp.is_bfloat16_supported()` with no place argument
on aarch64, and forcing float32 OOM-kills a 7.6 GB Docker VM. It needs a GPU or 12+ GB RAM.

## What the measurement found that outlives the verdict

**The parser is coupled to Vision's line segmentation - it is not reader-agnostic.** PaddleOCR's
detector merges `1,869 EUR/L` into one line where Vision emits `1,869` and `EUR/L` separately, and
`FuelExtractor.loneMarkers` resolves a price by finding it *directly below its `/L` label*. So a
different reader cannot simply be dropped in. This is why `docs/EXTRACTION.md`'s
"interpretation, not recognition" split holds **only under Vision-quality recognition** - a
qualification that section now carries.

The tests in `ios/Tests/TankbookCoreTests/PaddleOCR*.swift` pin that finding, and pin the
**coordinate trap**: `OCRLine` uses Vision's normalised space with a **bottom-left** origin, while
PaddleOCR returns pixel coordinates with a **top-left** origin. An unflipped conversion inverts
the page and breaks the parser's geometric rules silently - which would look like evidence
*confirming* the interpretation claim. `naiveFlipInvertsThePage` keeps that trap from being
rediscovered the hard way.

## Reviving it (only worth doing on a GPU box)

```
docker build -t tankbook-paddleocr:0.1.0 Spike/PaddleOCR
docker run -d --name tankbook-paddleocr -p 8000:8000 \
  -v tankbook-paddleocr-models:/root/.paddlex tankbook-paddleocr:0.1.0
python3 scripts/sweep-paddleocr.py            # writes Spike/ReceiptSpike/fixtures/vision-ab/
```

Pinned: base `python:3.12-slim-bookworm`, `paddlepaddle==3.2.2` (3.3.x ships no Linux aarch64
wheel), `paddleocr==3.7.0`, `paddlex[ocr]==3.7.2`; models `PP-OCRv5_server_det` +
`cyrillic_PP-OCRv5_mobile_rec`.

The image and its model volume were deleted after the measurement (~4 GB). The committed result
files under `Spike/ReceiptSpike/fixtures/vision-ab/paddleocr-a-*.json` mean the **scores can be
re-derived without re-running the sweep** - the tests score them offline and need no container.
