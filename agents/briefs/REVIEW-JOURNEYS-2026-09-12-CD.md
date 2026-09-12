# REVIEW-JOURNEYS run, 2026-09-12 - Group C + Group D

**Read `agents/briefs/REVIEW-JOURNEYS.md` first and follow it in full** - method, the two passes (reachability AND sequence), the shared instructions, and the group sections named below. This file narrows that brief to this run; where they differ, the recurring brief wins on method and this file wins on scope.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY: no edits, no builds, no tests, no commits.** A build agent (`RV.226`) and other read-only reviews are working in this checkout right now. Your entire output is your report at **`diagnostics/REVIEW-JOURNEYS-2026-09-12-CD.md`** - the ONE file you write.

## Why this run

The cadence in `CLAUDE.md` is every 10 shipped rows. Since the last walk of these groups (2026-09-10) these rows shipped (60 of them): PJ.22, PJ.23, PJ.26 + PJ.27, PJ.34, PJ.51, PJ.58, PJ.59, PJ.61, PJ.63, RV.108, RV.134, RV.143, RV.155, RV.158 + RV.138, RV.164 + RV.211, RV.165, RV.170, RV.171, RV.173, RV.174, RV.181, RV.182, RV.183 + RV.184, RV.185 + RV.187, RV.186 + RV.188, RV.188, RV.189, RV.190, RV.192 + PJ.45, RV.195 + RV.193, RV.196, RV.197, RV.198, RV.199, RV.200, RV.201, RV.202, RV.204 + RV.209, RV.206, RV.207, RV.208, RV.214, RV.215, RV.216 + RV.217, RV.218, RV.219, RV.222 + RV.223, RV.230, RV.231, RV.239, RV.243, RV.244, RV.247, RV.249, RV.250, RV.253, RV.255, RV.259, RV.260, RV.261. Today alone the scenario reviews walked J10, F9, J2, F10, J11a, J11, F7 to code and found three real gaps the ticked rows had not (RV.255, RV.259, RV.260) - the argument that the tree moved faster than the walks. **Scope: Group C + Group D**, both passes. Read the previous report for these groups (`diagnostics/REVIEW-JOURNEYS-2026-09-10.md`) first and do not re-file what it filed; re-check what it gated on.

## What is different today

- Every open row must name its scenario (`scripts/scenario-index.py --check`); a row you propose says its journey id in the first cell, `no-scenario: <reason>` if it genuinely has none.
- Scenarios carrying `**Status: implemented <date>**` were reviewed by `REVIEW-SCENARIO`; a finding there is a finding against a REVIEWED story - say so explicitly, it is the higher-value kind.
- Propose rows in the `PJ` numbering the recurring brief assigns to your groups; do not tick, do not edit `docs/`.
