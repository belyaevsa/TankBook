# PU.82 - train the classifier on the owner-verified hand-box pool

## Where you may write
`ml/pump-reader/src/pump_reader/realglyphs.py`, `ml/pump-reader/tests/`, and anything under
`ml/pump-reader/.out/` (runs, pools, logs). Nothing under `ios/` or `docs/` - the orchestrator scores,
decides and records. Never touch `Spike/ReceiptSpike/fixtures/` (the owner is annotating: the corpus
files are modified and uncommitted - read them, never write, stash or check them out). Do not commit.

## Read first
`docs/TASKS.md` rows PU.82 and PU.73 (its protocol and outcome), `agents/research/PU.73.md` §3.3
(the hand-box pool, adaptation A11) and §5.3 (the round protocol), `ml/pump-reader/REPORT.md`
(r10/r11 round precedent). Row PU.83 (committed) renamed the dp flags: `realglyphs --dp-crop off|gap`
is framing (default `off`, the shipped one), `--dp-bits keep|clear` the labels (default `keep`);
`train.py --dp-bits 7|8` follows the pool's manifest.

## What to build (small)
`realglyphs.py` gains `--hand-only`: frame windows only from frames with `frames.verified = 1`
(stills unchanged), mirroring `detdata.py`'s `--hand-only`. The manifest records `hand_only`. Test it
the way `tests/test_dp_crop.py` builds a synthetic corpus: a verified and an unverified frame, and
`--hand-only` keeps only the verified one's cells. The mutation that must go red: ignore the flag.

## The round (the PU.73 protocol; every command pins its flags)
0. **Re-export**: `cd ios && PUMP_TRAIN_EXPORT=1 swift test --filter PumpTrainSliceExportTests`.
   Record the corpus.sqlite sha256 you exported from (`shasum -a 256 Spike/ReceiptSpike/fixtures/corpus.sqlite`).
1. **Two pools** from that export, identical flags except `--hand-only`, both `--dp-crop off
   --dp-bits keep`, and the shipped pool's other flags (read them from REPORT.md's r6/r11 pool
   command and state which you used): `.out/real-r12-full` and `.out/real-r12-hand`. Report each
   pool's cell count, fixture count, verified-frame count and dp rate.
2. **Arms, 3 seeds each (0, 1, 2)**, the shipped recipe otherwise (`train.py` defaults;
   `--steps 15000 --contrast-prob 0.15 --real-frac 0.3`, the PU.73 controls - confirm against
   `.out/pu73-control-s0/metrics.json`): (a) control on the FULL pool, (b) control on the HAND pool,
   (c) `--head flatten` on the HAND pool. Nine runs; each exported with `python -m pump_reader.export`
   to `<run>/PumpSegments.mlpackage`, and `python -m pump_reader.temperature` on it (reporting only).
3. **Score every candidate on both tiers**, one at a time (never two Swift runs at once), with the
   orchestrator's scorer - never your own script:
   `cd ios && PUMP_MODEL=<abs path to .mlpackage> swift test --filter "PumpReaderPipelineTests/(gateMirror|livePath)"`
   Read the `PU.22 reader on real cells:` (annotated) and `PU.63 live path` lines and every `WRONG`
   line. The test's own assertions will fail for a candidate that differs from the shipped constants -
   that is expected; the printed numbers are the result.
4. **With the new locator**: for the best candidate of each arm by annotated correct (ties: live
   correct), also run the live tier with
   `PUMP_SEGMENTER=<abs>/ml/pump-reader/.out/seg-r1/RowSeg.mlpackage` added. Baselines to compare:
   shipped classifier annotated 126/126, live 47/47; shipped classifier + segmenter live 62/61 (one
   wrong: pump-063).

## Report back (a table, nothing omitted)
Per run: arm, seed, annotated committed/correct, live committed/correct, every WRONG, final val loss,
T. Per arm: mean and range over seeds. The pool effect = (b) - (a); the head effect = (c) - (b).
The segmenter lines from step 4. Exit codes of the ML suite (`cd ml/pump-reader && .venv/bin/python
-m pytest -q`) and the mutation's red output. Wall time. Anything found and not fixed.
