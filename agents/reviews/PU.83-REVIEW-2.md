# PU.83 review 2 — COMPLETE

Re-check of the two incomplete items in review 1 (`agents/reviews/PU.83-REVIEW.md:14`, `agents/reviews/PU.83-REVIEW.md:16`). Evidence below is from the current files; no implementation file was changed in this review.

1. **PU.41 round 11b plan: resolved.** `docs/TASKS.md:1045` gives the active pool command as `--dp-bits clear` and says `train.py` follows the pool manifest to 7 bits. Its `--dp-crop none` mention identifies the old flag that PU.83 renamed; it is not an instruction to run it. `ml/pump-reader/src/pump_reader/realglyphs.py:293` accepts only `off|gap` for `--dp-crop`, and `ml/pump-reader/src/pump_reader/realglyphs.py:296` accepts `keep|clear` for `--dp-bits`.
2. **Test module docstring: resolved.** `ml/pump-reader/tests/test_dp_crop.py:1` identifies `--dp-crop` as framing and `--dp-bits` as labels; `ml/pump-reader/tests/test_dp_crop.py:2` through `ml/pump-reader/tests/test_dp_crop.py:6` explain `gap`, shipped `off`, `clear`, and default `keep`. These agree with the parser at `ml/pump-reader/src/pump_reader/realglyphs.py:293` and `ml/pump-reader/src/pump_reader/realglyphs.py:296`.
3. **PU.83 shipped row: matches code.** The shipped text at `docs/TASKS.md:1087` describes the current parser choices and defaults (`ml/pump-reader/src/pump_reader/realglyphs.py:293`, `ml/pump-reader/src/pump_reader/realglyphs.py:296`, `ml/pump-reader/src/pump_reader/train.py:197`), independent crop and bit handling (`ml/pump-reader/src/pump_reader/realglyphs.py:332`, `ml/pump-reader/src/pump_reader/realglyphs.py:338`), pool manifest keys (`ml/pump-reader/src/pump_reader/realglyphs.py:373`, `ml/pump-reader/src/pump_reader/realglyphs.py:374`), legacy `none` translation and cleared-pool refusal/default (`ml/pump-reader/src/pump_reader/train.py:135` through `ml/pump-reader/src/pump_reader/train.py:147`), and metrics keys (`ml/pump-reader/src/pump_reader/train.py:314`, `ml/pump-reader/src/pump_reader/train.py:315`). The default-pool and cleared-pool assertions are at `ml/pump-reader/tests/test_dp_crop.py:92` through `ml/pump-reader/tests/test_dp_crop.py:140`.

Verification: `cd ml/pump-reader && .venv/bin/python -m pytest -q` — exit **0**, **68 passed** in 18.37s. Output:

```
....................................................................     [100%]
68 passed in 18.37s
```

No mutation was made for this read-only re-check, so there is no new red-then-green output. The baseline iOS gate, UI suites, localization gate, screenshot-manifest check, and screenshots were not run or captured; no counts or exit codes are claimed for them. No additional finding was left unfixed.

**COMPLETE**
