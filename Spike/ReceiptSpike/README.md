# ReceiptSpike

Validation spike for the Tankbook OCR pipeline (see `../../docs/VISION.md`, section 3 and 8): measure how well **on-device Vision OCR + deterministic rules** extract liters, unit price, and total from real fuel receipts and pump-display photos – before building any app UI. Decision gate: the pump-photo path ships only if it clears ~95% on a real test set.

No LLM in this spike on purpose. Whatever fails here is exactly the workload for the Foundation Models normalization step and the cloud fallback.

## Usage

1. Drop photos (jpg/png/heic) into a folder, e.g. `fixtures/`:
   - target: ~50 real receipts (different chains, countries, crumpled ones too) and ~20 pump displays.
2. Run:

   ```sh
   swift run ReceiptSpike fixtures
   ```

3. Flags:
   - `--dump-text` – print raw OCR lines per image (to debug parser misses)
   - `--json` – machine-readable output

## Scoring against ground truth

Add `fixtures/expected.csv`:

```csv
filename,liters,unitPrice,total
receipt-01.jpg,42.30,1.679,71.02
pump-01.heic,38.00,6.12,232.56
```

The run then reports field-level accuracy. Leave a field empty to skip it for that file.

## How the parser works

1. Vision framework OCR (`.accurate`, language correction off, EN/DE/PL/CZ/RU).
2. Keyword-anchored extraction (TOTAL/GESAMT/RAZEM…, LITER/MENGE…, /L price markers), currency and fuel-type vocabularies.
3. Arithmetic fallback: among all numbers in the image, find the triple where `liters × price ≈ total`. This alone handles label-free pump displays and doubles as the confidence signal.

## Tests

```sh
swift test
```

Parser unit tests run on synthetic receipt text (German, Polish, bare pump display, thousands grouping).
