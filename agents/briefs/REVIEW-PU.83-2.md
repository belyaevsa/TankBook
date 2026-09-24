# REVIEW-PU.83-2 - re-check review 1's two items

Read-only except `agents/reviews/PU.83-REVIEW-2.md`. Review 1: `agents/reviews/PU.83-REVIEW.md`
(INCOMPLETE on two items). Verify with file:line only: (1) PU.41's round 11b plan in `docs/TASKS.md`
no longer uses the removed `--dp-crop none`; (2) `ml/pump-reader/tests/test_dp_crop.py`'s module
docstring describes the current flags. Also confirm the PU.83 row's shipped text matches the code.
Run `cd ml/pump-reader && .venv/bin/python -m pytest -q`; report count and exit code.
End with **COMPLETE** or **INCOMPLETE**.
