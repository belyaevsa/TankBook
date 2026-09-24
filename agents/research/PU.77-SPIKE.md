# PU.77 spike report - a row-level sequence reader (CRNN + CTC), offline

*Built and measured by the orchestrator, 2026-09-25 (product owner: "build by yourself PU.77"),
from `agents/research/PU.77.md` §4's recipe, in the worktree `wt/pu77`. Offline only: nothing on the
app path changes, and by the row's own rule no Swift reader is built until the bars pass.*

## Verdict

**A measured no-go for this run, by the row's own rule (B3): B1 passes on every seed, B2 fails.**
The row reader reads far better than the current slicer + classifier (exact string 0.887-0.903
against 0.564 on the 195 heldout strips; 0.59-0.65 against 0.06 on heldout2). The law over its
posteriors commits 152-163 correct cells against the tier's 126, but at precision 0.987-0.993 -
under the 0.99 bar on five of six arms. No Swift reader is built.

Separately, and as its own decision: the binding miss is one fixture, pump-041, wrong in every run,
and it is a law decision rather than a misread - the reader reads the price right and the law's
repair tier overrides it to close a glare-obscured total. A law guard for that is proposed at the
end as a new row; it is not part of this verdict.

## What was built

| Piece | File |
|---|---|
| CRNN per the note's §4.1 table - 1 010 668 parameters; CTC; prefix search and best path; per-position substitution marginals for the law (A4); the hand-rolled Graves forward recursion | `ml/pump-reader/src/pump_reader/rowreader.py` |
| Training: synthetic strips from `row.render_row_of_labels` with strings drawn from the measured conventions table (per currency, field and cell count), the real re-export capped at 2 % per source and mixed at 30 % of every batch, AdaDelta rho 0.95 + clip 5, He init, selection on a fixture-grouped 10 % of the real train strips | `rowtrain.py` |
| Scoring: B1 for both arms on the same heldout pixels, T fitted by CTC NLL on the train-side validation strips, posteriors raw and T-scaled | `roweval.py` |
| The Swift harness (test target, opt-in): heldout strips warped as the reader warps them plus the current arm's string for each; the law over the row reader's posteriors scored as `gateMirror` scores | `ios/Tests/TankbookCoreTests/PumpRowReaderSpikeTests.swift` |
| F1 tests | `ml/pump-reader/tests/test_rowreader.py` |

**Data.** Step 0 re-export: stills + tracked frames from the main checkout's export (32 260 windows,
corpus sha256 `cf836e56...`, the owner's in-progress working tree) and the video frames from the
worktree's export (18 303 windows); 50 287 real strips from 295 source groups, 36 478 after the 2 %
cap, 4 872 held aside for validation. (The worktree's own tracked-frame export came back empty:
`FileManager.contentsOfDirectory` does not list through the `frames` symlink the worktree needed.)

**Departures named here** (beyond the note's A1-A12): the prefix search is a beam of 32 over the
note's whole-strip search (A11's exact search is intractable to write for the spike; best path, the
published control, scores within 0.01 of it); the synthetic sampler's currency and field mix is
fixed (EUR 0.55, RUB 0.35, KZT and GBP 0.05; total 0.3, liters 0.3, price 0.25, board 0.15), not
fitted; 20 000 steps at batch 64 (the note's 20-40k).

**Not done, and a departure from the note (needs the owner's OK before any rerun counts):** §4.4
step 3 re-derives the law's nat windows (`readWindow`, `ambiguityWindow`, the repair window) on the
TRAIN split under T-scaled posteriors. This spike ran the law with its shipped windows, on raw and
on T-scaled posteriors (T fitted train-side). The two scales give the same commits on seeds 0 and 1
and differ on seed 2 (153 / 152 raw, 158 / 156 scaled), so the windows are not scale-free for this
model family - exactly why the note requires the re-derivation. The B2 numbers below are therefore
the shipped windows' numbers, not the note's protocol.

**Scored candidates and their configuration** (F3's audit): three, one per seed, each scored once on
heldout and once on heldout2 after training finished - `seed` 0 / 1 / 2, 20 000 steps, batch 64,
real-frac 0.3, cap 0.02, AdaDelta 1.0 / rho 0.95 / clip 5, checkpoint = best train-side validation
string accuracy (step and pool sizes in each run's `metrics.json`); T fitted on the 4 872 train-side
validation strips.

## Measured

**F1** (`tests/test_rowreader.py`): the hand-rolled forward recursion matches `nn.CTCLoss` to
1.4e-14 over 30 random sequences; dropping eq. 6's skip term turns it red
(`/tmp/agentlogs/pu77-mutation-skip.log`); on a peaked strip the substitution marginal ranks every
true digit first and puts the separator where it is.

**B1** - the 195 heldout transaction strips, the same pixels for both arms:

| arm | exact string (Wilson 95 %) | normalised Levenshtein | per-glyph, count-matched | length | separator placement |
|---|---|---|---|---|---|
| current (slicer + classifier) | 0.564 [0.494, 0.632] | 0.910 | 0.948 | - | 0.646 |
| row reader seed 0 | **0.887** [0.835, 0.924] | **0.976** | 0.978 | 0.995 | 0.954 |
| row reader seed 1 | **0.897** | **0.966** | 0.977 | 0.980 | 0.969 |
| row reader seed 2 | **0.903** | **0.965** | 0.987 | 0.954 | 0.949 |

B1 passes on all three seeds, by a margin the intervals do not bridge. The separator - the dp bit
PU.73 bounded near 0.75 AUC for any cell crop - is placed right 95-97 % of the time: the note's §4.6
claim that a strip reader sees the mark holds. Neither leak tripwire fires (heldout exact < 0.99,
F3; separator < 0.99, F4). Best path scores with prefix search (0.892 on seed 0).

**B2** - the law over the posteriors on the annotated tier (183 cells; the tier's floor is 126 at
HEAD, all correct), raw and T-scaled nats (F5):

| seed | T | raw: committed / correct / precision (photos all right) | scaled: committed / correct / precision (photos all right) |
|---|---|---|---|
| 0 | 1.48 | 165 / 163 / 0.988 (57 / 68) | 165 / 163 / 0.988 (57 / 68) |
| 1 | 1.62 | 156 / 154 / 0.987 (54 / 68) | 156 / 154 / 0.987 (54 / 68) |
| 2 | 1.46 | 153 / 152 / **0.993** (54 / 68) | 158 / 156 / 0.987 (55 / 68) |

The wrong cells, every one of them:
- **pump-041 unit price 1.794 for 1.784 - every run.** The total window is annotated `partial`
  (read through glare): the owner's text 54.93 does not close (30.62 x 1.784 = 54.63). The row reader
  reads the glare exactly as the owner did and reads the PRICE right (the 8 at -0.01 nats); the law's
  repair tier then substitutes the price's 8 with its seven-segment partner 9, because 30.62 x 1.794
  closes to the glare-read 54.93. A confidently read cell repaired to fit an obscured one.
- pump-035 total 82.07 for 82.01 (seed 0), pump-055 108.66 for 108.68 (seed 1), pump-023 51.77 for
  51.71 (seed 2, scaled): a last digit the reader was unsure of (pump-035: 7 at -0.65 against 1 at -1.01),
  committed by the PAIR tier - no transaction price is shown, and decision 11's 5 % shown-price band
  validates the pair with the `shownPriceDiffers` caution.

Without pump-041: seeds 0 and 1 and seed 2 scaled sit at 0.993-0.994; seed 2 raw, whose only wrong
cell it is, at 1.000.

**heldout2** - the second frozen draw, scored once at this go/no-go (`PUMP_ROWREADER_SPLIT=heldout2`;
7 stills, 17 transaction strips, 25 windows):

| arm | exact string | normalised Levenshtein | separator placement | law: committed / correct |
|---|---|---|---|---|
| current | 0.059 | 0.691 | - | - |
| row reader seed 0 | 0.647 | 0.824 | 0.765 | 7 / 7 (3 / 7 photos all right) |
| row reader seed 1 | 0.647 | 0.838 | 0.824 | 7 / 7 |
| row reader seed 2 | 0.588 | 0.809 | 0.765 | 7 / 7 |

## What the numbers say

1. **Reading a row as a sequence beats slicing it into cells**, by 33 points of exact-string
   accuracy, and it carries the decimal mark the cell crop cannot see.
2. **The law is now the limiter, not the reader.** More committed cells means the law's two loose
   paths - the repair tier and the pair tier's band - fire more often. Both are law questions.
3. The count bar is cleared with room: 152-163 correct against 126 (+26 to +37 cells).

## For the owner

**This run is a no-go (B3).** What would change that is a new decision, not a continuation:

- **A law row**: *the repair tier never overrides a cell the reader was
  confident in* - a substitution only where the read cell's own margin is small. It removes
  pump-041 in every seed; pump-035/055/023 remain the pair tier's decision 11 territory, committed
  with the caution.
- **A rerun of B2 under the note's full protocol** once that lands: the law windows re-derived on
  train under T (§4.4 step 3, not done here), the same three seeds. Only a pass there opens the Swift
  integration row (the note's §3-6: the CRNN in Core ML, the decode and marginals in Swift, the
  verifier's use of the decoded length).
