# vision-ab/ - the P4.12 corpus A/B artefact (NOT the accuracy ratchet)

`rules-*.json` and `llm-*.json` are the committed per-image extraction results
for the **P4.12 corpus A/B**: the cloud vision model
(`deepseek/deepseek-v4-flash-vision-exp`) against the shipped rules parser, scored
field-by-field with the one shared scorer in
`ios/Tests/TankbookCoreTests/CorpusABScorer.swift`.

**These files do NOT touch `../high-water.json` and must never be merged into it.**
`high-water.json` is the floor the *rules parser* is ratcheted against; writing a
different engine's numbers into it would break the gate for everyone.

## Schema

One file per class, one per engine:

```json
{
  "engine": "rules" | "llm",
  "className": "receipts" | "pump" | "fiscal" | "screenshots",
  "generated": "2026-08-26",
  "entries": [
    {"filename": "pump-001.heic", "liters": 67.0, "unitPrice": 1.869,
     "total": 125.22, "latencySeconds": 24.1, "error": null}
  ]
}
```

- A `null` field is "the engine abstained or the field is not legible" - scored as
  a miss when ground truth has a value, skipped when ground truth is blank.
- `error` carries the failure text when the whole image failed; `latencySeconds`
  is the wall-clock round trip (LLM arm only).
- Ground truth stays in each class's `expected.csv`; the scorer re-reads it and
  never trusts a number stored here.

## Regenerating

- Rules arm: `cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 swift test --filter CorpusABRulesDump`.
- LLM arm: `scripts/sweep-vision-ab.py` (sequential; budget ~10-20 min; resumes
  over already-recorded images). The model is stochastic, so a re-sweep will not
  reproduce these exact values - which is itself a finding, see the P4.12 section
  of `docs/EXTRACTION.md`.

## Recorded sweep, 2026-08-26 (61 images, 0 errors)

| class | rules | LLM | latency median / max |
|---|---|---|---|
| receipts | 46/96 | **84/96** | 7.4 s / 21.8 s |
| pump | 1/46 | **31/46** | 8.3 s / 40.1 s |
| fiscal | 1/3 | **2/3** | 5.6 s / 5.6 s |
| screenshots | 7/24 | **22/24** | 6.5 s / 9.8 s |

The two failure modes are committed, not averaged away: `receipt-035` is the
volume/price swap (70.44 read as litres), and `pump-009` is the decimal-separator
shift (40.00 read as 400.0) - both pass the arithmetic cross-check. The probe's
shift on `pump-005` did not reproduce: that fixture read correctly three runs in
a row, and `pump-009` itself flipped between correct and shifted across runs.
