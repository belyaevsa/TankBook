# PU.82 report - the classifier on the owner-verified hand-box pool

*Built and measured by the orchestrator, 2026-09-25 (the DeepSeek build was stopped when the owner
dropped DeepSeek; its `realglyphs --hand-only` change and test were kept and verified). PU.73's
protocol: a fresh export, one control per pool, the flatten arm, 3 seeds each, both tiers, T per
candidate, and the best of each arm measured with PU.76's segmenter as the locator (owner: "run
after PU.76 - measured together with the better detector").*

## Verdict

**No candidate ships; the hand-box pool does not help the classifier.** Cutting the pool to the
owner's hand-placed boxes loses 4 cells on each tier and adds a wrong live reading on every seed; the
flatten head adds annotated cells and wrong live readings (PU.73's signature again). With the
shipped detector every arm's mean is below the shipped classifier on both tiers; the one seed above
it on a tier - flatten s2, 48 correct live cells against 47 - commits 4 wrong live cells doing so,
which alone rules it out.

## Data

Step 0 re-export, two runs (provenance):
- stills + tracked frames: `cd ios && PUMP_TRAIN_EXPORT=1 swift test --filter PumpTrainSliceExportTests`
  in the main checkout, started by the PU.82 agent before it was stopped (`/tmp/agentlogs/PU.82.log`
  records the command and the corpus it exported from, sha256
  `cf836e5651c924de538ee19891f62475811cb002eaa7004d36a27e95528fb767` - the owner's in-progress working
  tree), finished 2026-09-25 01:01: 32 260 windows;
- video frames: `PUMP_TRAIN_EXPORT=1 PUMP_TRAIN_EXPORT_VIDEOS=1 swift test --filter
  PumpTrainSliceExportTests` in the PU.77 worktree (`/tmp/agentlogs/pu77-export.log`): 18 303 windows
  (the main checkout's video manifest was the stale 2026-09-21 one).
Both manifests and their strips are combined in `.out/pu82-export` so the two pools read the same
sources. Pools (`realglyphs --dp-crop off --dp-bits keep`, the shipped r6 pool's defaults otherwise):

| pool | cells | windows used | dp rate |
|---|---|---|---|
| full (`.out/real-r12-full`) | 172 318 | 39 078 of 50 563 | 0.225 |
| hand-only (`--hand-only`, `.out/real-r12-hand`) | 6 236 | 1 412 of 50 563 | 0.225 |

The hand-only pool is 28x smaller - the "data cut" the row warned of (it estimated 13x).

## Results (`train.py --steps 15000 --contrast-prob 0.15 --real-frac 0.3`, seeds 0-2)

Scored with `PUMP_MODEL=` through `PumpReaderPipelineTests` (`.out/pu82-*-score.log`); the shipped
classifier reads annotated **126 / 126** and live **47 / 47**.

| arm | annotated committed / correct | live committed / correct | live wrong | val loss | T |
|---|---|---|---|---|---|
| full s0 | 119 / 117 | 47 / 47 | 0 | 0.155 | 0.79 |
| full s1 | 117 / 116 | 47 / 47 | 0 | 0.155 | 0.80 |
| full s2 | 117 / 116 | 41 / 41 | 0 | 0.156 | 0.80 |
| hand s0 | 114 / 114 | 43 / 42 | 1 (pump-062) | 0.154 | 0.80 |
| hand s1 | 109 / 109 | 40 / 39 | 1 (pump-062) | 0.157 | 0.80 |
| hand s2 | 116 / 114 | 43 / 42 | 1 (pump-062) | 0.154 | 0.79 |
| flatten s0 (hand pool) | 116 / 116 | 43 / 42 | 1 (pump-091) | 0.125 | 0.68 |
| flatten s1 | 113 / 113 | 35 / 34 | 1 (pump-091) | 0.124 | 0.68 |
| flatten s2 | 124 / 123 | 52 / 48 | 4 (pump-091, pump-092 x2, pump-120) | 0.126 | 0.68 |

Means (correct): full 116.3 annotated / 45.0 live; hand 112.3 / 41.0; flatten 117.3 / 41.3.
**Pool effect** (hand - full): -4.0 annotated, -4.0 live, and a wrong live reading on every seed.
**Head effect** (flatten - hand): +5.0 annotated, +0.3 live, and more wrong live readings.
The annotated WRONG lines include pump-041's price in three runs - the law's repair tier (PU.86).

**With PU.76's segmenter as the locator** (live, the best seed of each arm by annotated correct;
`.out/pu82-*-seg.log`); the shipped classifier + segmenter reads **62 / 61** (pump-063 wrong):

| classifier | live committed / correct | wrong |
|---|---|---|
| full s0 | 60 / 58 | pump-035 total, pump-091 price |
| hand s0 | 59 / 58 | pump-062 total |
| flatten s2 | 66 / 65 | pump-275 total |

Tests: `tests/test_hand_only.py` (a verified and an unverified frame; `--hand-only` keeps the verified
one and the still); the mutation - ignore the flag - red (`/tmp/agentlogs/pu82-mutation-hand-only.log`).
ML suite 78 / 78.

## What it says

The classifier's limit is not the tracker's box noise: the full pool (tracker boxes included)
beats the hand pool on both tiers, so for the CELL classifier more data outweighs cleaner boxes -
the opposite of the detector's PU.66 finding. PU.41's round 11b is NOT answered here: it specifies
the phase-aware centred filter, `--dp-bits clear`, the grey profile, the cap and the hard weight,
none of which this run used - it stays open. What this run does say is that the current recipe on a
fresh pool reads below the shipped r6 model, and that the reader's larger lever is PU.77's row
reader, not a retrained cell classifier.
