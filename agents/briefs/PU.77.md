# PU.77 - a row-level sequence reader (CRNN + CTC), spike, offline first

## Where you work - read this first
You work ONLY in the git worktree `/Users/sbelyaev/repos/fuel-counter-ios-wt-pu77` (branch `wt/pu77`).
Another agent is training in the main checkout at the same time; never touch
`/Users/sbelyaev/repos/fuel-counter-ios` except to RUN its Python interpreter:
- Python: `/Users/sbelyaev/repos/fuel-counter-ios/ml/pump-reader/.venv/bin/python`, ALWAYS with
  `PYTHONPATH=/Users/sbelyaev/repos/fuel-counter-ios-wt-pu77/ml/pump-reader/src` (the venv's editable
  install points at the MAIN checkout's `src`; `PYTHONPATH` must win). Prove it once:
  `python -c "import pump_reader; print(pump_reader.__file__)"` must print a path under `-wt-pu77`.
- Swift: `cd /Users/sbelyaev/repos/fuel-counter-ios-wt-pu77/ios && swift test ...` (this worktree's
  own `.build`). Never two Swift runs at once.
Do not commit. Write code, run, report.

## The method is fixed - `agents/research/PU.77.md` is the recipe
Read §0, §4 (4.1-4.6), §5 (the adaptations A1-A12 - the fence: a departure not on that list is
not yours to make), §6.2 (the bars B1-B3), §6.4 (falsifiers F1-F6). Build exactly that:
- Step 0 re-export: `PUMP_TRAIN_EXPORT=1 PUMP_TRAIN_EXPORT_VIDEOS=1 swift test --filter
  PumpTrainSliceExportTests` in this worktree (§4.5).
- The strip dataset, the corpus-calibrated synthetic string sampler (§4.3, using
  `PumpDisplayConventions` as committed - it now ties placements to cell counts, PU.85), the
  dedup/cap at 2 % per source (§4.5), real-frac 0.3, height 32, aspect-preserved right padding
  (§4.2), the 12-token alphabet.
- The CRNN of §4.1's table (~1.01M params), CTC loss, AdaDelta 0.95 / clip 5 / He init (A8; the
  AdamW fallback only if AdaDelta diverges - log it).
- Validation fixture-grouped on TRAIN only (§4.5, F3). 3 seeds. Budget: the note's 20-40k steps;
  if a run's wall time exceeds 3 h, report the loss curve and stop that arm rather than extend it.
- F1 first, before any training: the hand-rolled forward-backward vs `nn.CTCLoss` to 1e-5, the
  eq.-6 skip-rule mutation red, and the substitution-marginal sanity check (§6.4-F1).
- Decode by prefix search with best path as the control; per-position substitution marginals
  (§4.4, A4); T fitted on train strips; the JSON per window of §4.4 step 4.
- The Swift harness (test target only): a loader that builds `PumpCellReading(probabilities: [],
  ranked:, decimalPoint:)` from that JSON and runs `PumpReadingLaw.resolve` exactly as
  `PumpReaderPipelineTests.gateMirror` scores - same windows, currency, bands, tolerance.

## The bars (the note's §6.2, at today's counts)
- **B1**: on ALL 195 heldout transaction strips, exact-string accuracy and normalised-Levenshtein
  digit accuracy must beat the CURRENT arm (the shipped slicer + classifier on the same strips) -
  measure the current arm with the same instrument; 3-seed mean, Wilson intervals.
- **B2**: the law over the posteriors commits **>= 126** (the annotated tier at HEAD, after PU.85)
  at precision **>= 0.99** over the 183 cells, in raw AND T-scaled nats (F5), and the oracle
  ratchet (`swift test --filter PumpReadingLawTests`) stays green.
- **B3**: fail B1 or B2 -> stop, no further Swift; the report is the result.
- heldout2 once, at the end. Heldout is scored once per finalist; every scored candidate logged
  with its config (F3).

## Report back
The F1 outputs verbatim; per seed: val string accuracy, heldout B1 (a)(b)(c), length accuracy,
sep/placement accuracy per style (and the F4 masking ablation if it triggers), B2 committed /
correct in raw and T-scaled nats; the current arm's B1 on the same strips; wall time per run;
the go / no-go against B1-B3; anything found and not fixed.
