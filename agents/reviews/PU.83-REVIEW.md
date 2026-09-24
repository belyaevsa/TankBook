# PU.83 review — INCOMPLETE

Reviewed only `git diff -- ml/pump-reader/src ml/pump-reader/tests` against the Checks cell at `docs/TASKS.md:1087`. No implementation files were changed in this review.

## Checks-cell verdict

1. **MET — one vocabulary.** `realglyphs.py:293-297` uses `--dp-crop off|gap` for framing and `--dp-bits keep|clear` for labels; `train.py:192-197` uses `--dp-bits 7|8` for the corresponding loss/output choice. `train.py:130-147` reads both pool attributes, maps legacy `dp_crop: none` to off + clear, defaults to 7 for a cleared pool, and refuses an explicit 8. `realglyphs.py:332,338` applies the choices independently. The `train.py` flag no longer claims to control a crop it does not make.
2. **MET — shipped default.** `realglyphs.py:293-297` defaults to off + keep and `train.py:229-231` resolves that pool to 8 bits. `REPORT.md:416-425` identifies round 6's shipped `.out/real` pool and 30% real training; `docs/TASKS.md:1081` explicitly says that round's pool was off-framed and training used 8 bits. The existing `.out/real/manifest.json` predates these keys, has 25,085 cells and 5,551 dp-positive `cell_meta` entries, which corroborates kept dp labels. Thus the new defaults match the shipped *framing and dp-label choice*; this is not a claim that all current synthetic-data defaults reproduce the old model.
3. **MET — records.** `realglyphs.py:364-384` writes `dp_crop` and `dp_bits` into the pool manifest. `train.py:312-319` writes the resolved numeric `dp_bits` and the pool's `pool_dp_crop` / `pool_dp_bits` into `metrics.json`.
4. **MET — agreement test.** `tests/test_dp_crop.py:90-115` builds a default off + keep pool, checks a positive dp label survives, runs `train --smoke --real` with the train default, and checks metrics for 8 / off / keep. `:118-138` also covers a cleared pool's 7-bit default, refusal of 8, and legacy `none` interpretation. The supplied mutations were red, and the full suite is green below.

## Caller and documentation review

**Finding — stale executable plan:** `docs/TASKS.md:1045`, PU.41's still-open **Round 11b** plan, instructs a future pool build with `--dp-crop none`. `realglyphs.py:293` now rejects that argument. Change that plan to `--dp-crop off --dp-bits clear` (or just `--dp-bits clear`, since off is the default) before considering the vocabulary migration complete. PU.41 owns the round; PU.83 owns making the renamed CLI usable by that caller.

**Finding — stale local description:** `tests/test_dp_crop.py:1-7` still describes `none` as a `--dp-crop` mode even though the tests now use `--dp-bits clear`. Update that docstring to the new two-flag vocabulary in the same file.

No active script or run-folder README command was found using the removed `train.py --dp-crop` or `realglyphs --dp-crop none`. `ml/pump-reader/README.md:60-62` runs `realglyphs` without either flag and remains valid. `REPORT.md:1229,1265-1266` and `agents/briefs/PU.41.md:56-67` document the historical round-11 experiment; `REPORT.md:1229` includes the old train syntax as a description of that round, not a current rerun command. The PU.73 research/review records likewise describe past commands.

## Verification

`cd ml/pump-reader && .venv/bin/python -m pytest -q`: exit **0**, **68 passed** in 17.83s. Output:

```
....................................................................     [100%]
68 passed in 17.83s
PYTEST_EXIT=0
```

Named mutation red output, verbatim from `/tmp/agentlogs/pu83-mutation-*.log`:

```
== pool default framing gap
FAILED tests/test_dp_crop.py::test_dp_bits_clear_clears_every_dp_bit - Assert...
FAILED tests/test_dp_crop.py::test_pool_defaults_are_the_shipped_framing - As...
FAILED tests/test_dp_crop.py::test_train_default_agrees_with_the_pool - Asser...
FAILED tests/test_dp_crop.py::test_train_follows_a_cleared_pool_and_refuses_eight_bits
4 failed, 3 passed in 5.05s
```

```
== train ignores the pool
FAILED tests/test_dp_crop.py::test_train_follows_a_cleared_pool_and_refuses_eight_bits
1 failed, 6 passed in 5.08s
```

```
== no refusal
FAILED tests/test_dp_crop.py::test_train_follows_a_cleared_pool_and_refuses_eight_bits
1 failed, 6 passed in 5.05s
```

The baseline iOS gate, UI suites, localization gate, screenshot-manifest check and screenshots were **not run/captured** in this read-only Python review; no exit code or count is claimed for them. The review's requested full Python suite is the green run above.

**INCOMPLETE.** Update PU.41's still-live `--dp-crop none` plan to the new flags and correct the test module's stale flag description. No other actionable caller was found.
