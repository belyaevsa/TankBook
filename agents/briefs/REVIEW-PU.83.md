# REVIEW-PU.83 - one dp vocabulary across realglyphs.py and train.py

Read-only except `agents/reviews/PU.83-REVIEW.md`. The change: `git diff -- ml/pump-reader/src
ml/pump-reader/tests` in `/Users/sbelyaev/repos/fuel-counter-ios` (ignore every other modified file -
other sessions' work). The row: `docs/TASKS.md`, PU.83 (read its Checks cell).
What was built: `realglyphs.py` `--dp-crop {off,gap}` (framing, default `off`, the shipped framing) and
`--dp-bits {keep,clear}` (default `keep`), both in the pool manifest; `train.py` drops its `--dp-crop`
for `--dp-bits {7,8}` defaulting to the `--real` pool's manifest (`pool_framing`, `resolve_dp_bits`),
refusing 8 on a cleared pool, and records `dp_bits`, `pool_dp_crop`, `pool_dp_bits` in metrics.json; a
legacy `dp_crop: none` manifest reads as off + clear. Tests in `tests/test_dp_crop.py`; mutations red:
`/tmp/agentlogs/pu83-mutation-{default-gap,ignore-pool,no-refusal}.log`.
Check with file:line: (1) every Checks-cell sentence MET/PARTIAL/MISSING; (2) is `keep` + `off` truly
what the shipped model trained with - read `ml/pump-reader/REPORT.md` and `docs/TASKS.md` PU.73's row
for the shipped round's pool command; (3) any caller left using the removed `train.py --dp-crop` or
`realglyphs --dp-crop none` (scripts, run folders' README commands that are meant to be re-run, docs
that present them as current); (4) `cd ml/pump-reader && .venv/bin/python -m pytest -q` - count and
exit code. End with **COMPLETE** or **INCOMPLETE** and what must change.
