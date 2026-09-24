# REVIEW-COMPLETE-PU.85 - read placements tied to the window's cell count

Read-only except `agents/reviews/PU.85-COMPLETENESS.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
The row: `docs/TASKS.md` PU.85 (read its Built and Checks cells). The diff: `git diff HEAD --
ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingTypes.swift PumpReadingLaw.swift
ios/Tests/TankbookCoreTests/PumpReadingLawExactTests.swift PumpReadingLawTests.swift
PumpDisplayConventionsCorpusTests.swift PumpReaderPipelineTests.swift docs/EXTRACTION.md` (ignore
corpus files under `Spike/` - the owner's in-progress annotations).
Check with file:line, each MET / PARTIAL / MISSING:
1. The joint table in code equals the corpus: re-count (reviewed windows, `csvDisagrees` fields and
   zero values out, placements that reproduce the asserted value) per (currency, field, cell count)
   for EUR, RUB, KZT, GBP, AUD, BYN, and compare to `placementsByCells` and the field sets.
2. Every TRANSACTION window read in `PumpReadingLaw` uses `conventions.decimals(_:cells:)`; boards
   keep `priceDecimals` - judge whether that split is justified.
3. Tests would fail: the RUB price-tie mutation log `/tmp/agentlogs/pu85-mutation-rub-price.log`;
   the corpus test's new equality check; the moved repair test (RUB -> NOK) still tests the repair tier.
4. Measurements: `/tmp/agentlogs/pu85-tiers-shipped.log` (annotated 126/126, live 47/47),
   `/tmp/agentlogs/pu85-live-seg.log` (segmenter 62/61), `/tmp/agentlogs/pu85-train.log` (train
   in-sample, when present), oracle 790/789 and fragility 0.036 from
   `cd ios && swift test --filter "PumpReadingLaw|PumpDisplayConventions"`. Zero new wrong readings on
   the shipped path.
5. Docs: the PU.85 paragraph in `docs/EXTRACTION.md` matches the code; comments follow `CLAUDE.md`.
End with **COMPLETE** or **INCOMPLETE** and what must change.
