# PU.82 completeness re-review — 2026-09-25

1. **Export provenance — MET.** `agents/research/PU.82-REPORT.md:20-28` gives both export commands, the full corpus SHA-256 `cf836e5651c924de538ee19891f62475811cb002eaa7004d36a27e95528fb767`, and the logs `/tmp/agentlogs/PU.82.log` and `/tmp/agentlogs/pu77-export.log`. The named logs exist; `PU.82.log:4940` records the same hash.
2. **Verdict — MET.** `agents/research/PU.82-REPORT.md:11-16` compares each arm's *mean* with shipped and explicitly identifies flatten s2 as 48 correct live cells versus 47 shipped, with 4 wrong. The result row at `agents/research/PU.82-REPORT.md:54` agrees. It no longer claims every individual arm or seed is below shipped on both tiers.
3. **PU.41 claim — MET.** `agents/research/PU.82-REPORT.md:76-80` expressly says PU.41 round 11b is not answered and remains open, naming the recipe differences.

This was a read-only re-review of the three requested points. No builds, tests, UI suites, localization gate, screenshot gate, or captures were run; no mutation was performed. No additional findings were evaluated.

**COMPLETE**
