# PU.77 completeness re-check 3 — 2026-09-25

**COMPLETE.** Re-check limited to review 2's seed 2 raw/scaled reversal against the two named logs.

1. **B2 table:** The seed 2 row reports raw 153 committed / 152 correct / 0.993, 54/68 photos, and scaled 158 / 156 / 0.987, 55/68 photos (`/Users/sbelyaev/repos/fuel-counter-ios-wt-pu77/agents/research/PU.77-SPIKE.md:80-84`). These match `/tmp/agentlogs/pu77-s2-law-raw.log:8-9` and `/tmp/agentlogs/pu77-s2-law-scaled.log:8-9`.
2. **“Differ on seed 2” sentence:** It assigns 153 / 152 to raw and 158 / 156 to scaled (`PU.77-SPIKE.md:44-47`), matching both logs' line 8.
3. **pump-023 attribution:** It assigns the pump-023 total error to seed 2 scaled (`PU.77-SPIKE.md:92-95`). The scaled log lists pump-023 (`pu77-s2-law-scaled.log:10`); the raw log lists only pump-041 (`pu77-s2-law-raw.log:10`).
4. **“Without pump-041” sentence:** It assigns 1.000 to seed 2 raw and about 0.994 to seed 2 scaled (`PU.77-SPIKE.md:97-98`). The raw log's sole error is pump-041, so removing it leaves 152/152 = 1.000 (`pu77-s2-law-raw.log:8-10`). The scaled log has pump-023 as its other error, so removing pump-041 leaves 156/157 = 0.994 rounded (`pu77-s2-law-scaled.log:8-11`).

No builds, tests, UI suites, localization or screenshot checks were run for this read-only artifact review; no screenshots were captured. No other findings were reviewed.

**COMPLETE**
