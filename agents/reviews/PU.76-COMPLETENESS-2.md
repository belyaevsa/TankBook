# PU.76 completeness review - re-check of review 1's four items

Run 2026-09-24, read-only except this file. Re-checks only the four items review 1
(`agents/reviews/PU.76-COMPLETENESS.md`) flagged INCOMPLETE, plus the post-review-1
production-seam change. Everything review 1 passed (fidelity, gate numbers, F1-F5,
verdict, pytest 73) is not re-reviewed.

## 1. F6 reported not-measured; B5 re-pinning stated not-done and why — FIXED

`PU.76-SPIKE.md:51-53` now states both, matching the note's definitions (F6 at
`PU.76.md:662-665`, B5 at `PU.76.md:383-387`): "**Label re-pinning (B5 / F6) was not
done.** The row asks for labels "re-pinned under one rule" first; the rule is the
owner's to pick (note §5.4), so this spike trained on the labels as they are.
**F6 is not measured** - the hand-vs-hand agreement stays the note's 0.745 median."
The "why" (the rule is the owner's to pick, §5.4) is present.

## 2. Departures B10 / B11 / B9 named — FIXED

`PU.76-SPIKE.md:33-49` heads the section "Departures beyond the note's B1-B8, named
here" and lists:
- **B9 - a quadrilateral fit** in place of the rectangle (`segnet.fit_quad`,
  `segeval --shape quad`), measured below, not adopted. Code: `segnet.py:161-162`
  (`if shape == "quad": quad = fit_quad(...)`), `segnet.py:167-217` (`fit_quad`,
  docstring names "adaptation B9"), `segeval.py:74` (`--shape` choices rect/quad).
- **B10 - the optimiser**, covering both review-1 items (Adam+OneCycle in place of
  SGD/xavier AND no xavier init): `segtrain.py:109-110`
  (`torch.optim.Adam` + `OneCycleLR`), no `nn.init`/xavier call anywhere in the file,
  so PyTorch's default Kaiming-uniform applies. The report names both the optimizer
  and "PyTorch's default (Kaiming-uniform) init" plus a why.
- **B11 - augmentation beyond B4's rotations**: `segtrain.py:62-77` (random scale
  0.7-1.25, +-20 % placement, brightness/contrast 0.7-1.3/+−25, greyscale p 0.2,
  Gaussian blur p 0.2) - beyond the note's B4 rotations-only (`PU.76.md:377-382`).

The note's fence (`PU.76.md:321-322`) requires departures not listed in the note to be
named or owner-approved; the report names all three for the owner.

## 3. B7 percentile reconciled (1st vs note's "99th") — FIXED

`PU.76-SPIKE.md:46-49` "B7, the percentile, stated plainly": read literally a 99th
percentile floor would drop 99 % of real rows; the implemented rule is the paper's
intent, the **1st** percentile (short side 4.94, area 57.0). Code confirms the 1st
percentile: `segeval.py:53` (docstring "1st percentiles"), `segeval.py:66`
(`np.percentile(shorts, 1)`, `np.percentile(areas, 1)`), echoed in
`segnet.py:19-20` and `PumpRowSegmenter.swift:17-18`.

## 4. Apportionment labels committed-vs-correct; parity cites the log — FIXED

`PU.76-SPIKE.md:86` now labels the table: "Counts are CORRECT cells except where a row
says "committed"; the apportionment prints both." Verified against the named logs:
- "detected windows, hand quads (committed = correct)" 106 / 114 — `pu76-apportion-shipped.log:13`
  (committed 106, correct 106), `pu76-apportion-seg.log:12` (committed 114, correct 114).
- "kept windows, hand quads" 85 / 100 — CORRECT counts (`-shipped.log:14` committed 86/correct 85;
  `-seg.log:13` committed 101/correct 100).
- "detector boxes, hand roles" 49 (49 committed) / 59 (62 committed) — `-shipped.log:15`, `-seg.log:14`.
- "framing loss" 36 / 41 correct-consistent (85-49, 100-59).
- "app" 47/47 and "61 committed / 58 correct" — `-shipped.log:20`, `-seg.log:19`.

Parity claim now cites the log: `PU.76-SPIKE.md:79` (`/tmp/agentlogs/pu76-parity.log`),
which exists and reads "PU.76 parity: 247/252 python rows within 0.01 of a swift row;
worst corner 0.20496152298626993; count mismatches 1: ["pump-008-...: swift 1 python 3"]".

## 5. Production seam since review 1 — the app never loads the segmenter

The Swift decode now lives in `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowSegmenter.swift`
(package, not the test target). `PumpRowDetector` grows an **internal**
`static func load(contentsOf:)` (`PumpRowDetector.swift:55-59`) that routes an
`.mlpackage` to a `PumpRowSegmenter` and everything else to the object detector, and an
**internal** `init(rows:)` (`:64-66`) plus the `.rows` branch in `detect(in:)` (`:68-71`).

- `grep -rn "load(contentsOf:)\|PumpRowSegmenter\|PumpRowSegmenterSpike\|PUMP_SEGMENTER" ios/App`
  -> **exit 1, no matches** (556 Swift files under `ios/App/Sources`). The app target
  never calls `load(contentsOf:)` and never constructs a `PumpRowSegmenter`.
- The only callers of `PumpRowDetector.load(contentsOf:)` are `PumpReadTool/main.swift:207`,
  `PumpReadTool/TraceServe.swift:40`, and `PumpReaderTestSupport.swift:42` (test target);
  `PumpRowSegmenterParityTests.swift:18` constructs `PumpRowSegmenter` directly (test target).
- `tools/pump-annotate/server.py` lists the segmenters in its detector picker:
  `SEGMENTER_ROOT.glob("seg-*")` (`:132`), `"kind": "segmenter" if path.suffix == ".mlpackage"
  else "detector"` (`:185`).
- The report's "What was built" table says so: `PU.76-SPIKE.md:29` ("internal and unused by
  the app"), `:30` ("used by the tests (`PUMP_SEGMENTER`), `pump-read` and its trace server -
  not by the app"), and `:119-125` ("the app does not load it").

The public API for the shipped `.vision` backend (`init(contentsOf:)`, `detect(in:)`,
`detect(in pixelBuffer:)`) is unchanged, so the app path is unaffected.

## Code comments

The new production comments (`PumpRowSegmenter.swift:5-13,54-55,83,99-100,148,162-163,176,180`;
`PumpRowDetector.swift:53-54,61-63`) follow CLAUDE.md: present tense, no task ids/dates/history,
no mutable facts copied into comments (the threshold values 4.94/57.0 are default-arg data, not
comments), and they explain non-obvious invariants (pixel-cell growth, black-canvas memset,
CGContext bottom-left origin, the union-find min-area-rect decode). `PumpRowSegmenter.swift:13`
("the app does not load it") is a statement of current wiring, not a planned feature.

## Verdict

**COMPLETE.** All four review-1 items are fixed and verified against the code and logs with
file:line, and the post-review-1 production-seam claim (app never loads the segmenter) holds.
