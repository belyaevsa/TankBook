# RV.48 stage two: make the resolution ladder's steps 3 and 4 real

You are designing **and implementing** this one. Code first, exploration second.

## Where you work

The git worktree you are started in:

    /Users/sbelyaev/repos/fuel-counter-ios/.claude/worktrees/rv48   (branch rv48-local-extraction)

Write only inside it. **Never `cd` to the main checkout** at `/Users/sbelyaev/repos/fuel-counter-ios`
- another session is working there and your edits would collide with it.

**Do not run any `git` command.** No `add`, no `commit`, no `stash`, no `checkout`. The
orchestrator commits after verifying; an agent that commits destroys the verification record.
Leave your work uncommitted in the tree.

**Do not touch**: `docs/TASKS.md`, anything under `agents/briefs/`, any `expected.csv` (the corpus
ground truth is not yours to edit - if you believe a cell is wrong, say so in your report), and any
fixture image.

**Never `pgrep -f`.** Your brief is your command line, so `pgrep -f "swift test"` matches YOU. Match
process names instead: `pgrep -x opencode`, `pgrep -x xcodebuild`. Never `pkill -f` anything.

## The problem, measured this morning

The receipt corpus scores **138/210 cells** after stage one (`Spike/ReceiptSpike/fixtures/high-water.json`
holds the full breakdown; read its `_note` first). The single largest remaining block:

**26 of the remaining volume misses are ABSTENTIONS, and they all die on the same line.**

`FuelExtractor.resolveUnmarked` (`ios/Sources/TankbookCore/Extraction/FuelExtractor.swift`) begins:

    guard let provider = bandProvider else { return (nil, nil) }

and **nothing in the app or in the corpus scorer ever injects a provider.** `FuelPriceBandProvider`
(`Extraction/FuelPriceBand.swift`) is a declared seam with no implementation, so ladder steps 3
(the user's own price history) and 4 (the curated band) have been dead code since they were written.

Every one of those 26 fixtures has a printed operand pair. The parser finds it, cannot tell which
operand is the price, and correctly abstains rather than guess. Your job is to give it the one input
that lets it decide honestly.

## Read these before writing code, in this order

1. **`docs/SCHEMA.md` -> "Fuel price bands (the extraction disambiguator)"** - this is the
   AUTHORITY and it already specifies the design. It gives you the table shape, the five-step
   ladder, why all four key columns are load-bearing, and the "wide and soft, rank never veto"
   rule. Implement what it says; do not redesign it. If you must deviate, say so in your report
   and update the doc in the same change.
2. `Spike/ReceiptSpike/fixtures/high-water.json` `_note` - what stage one changed and why.
3. `diagnostics/RV.48-proposal-qwen.md` section C9 - a per-fixture verdict on which pairs a band
   resolves, which stay ambiguous, and which are band-width dependent. Check its claims against
   the dump rather than trusting them.
4. `diagnostics/RV.48-analysis-orchestrator.md` - the same question worked independently, including
   the simulation showing a currency-only band gets `receipt-012` WRONG.
5. `Spike/ReceiptSpike/fixtures/HIGH-WATER.md` - the tie-break that was removed on purpose. Your
   band must not become that heuristic wearing a new hat.
6. `CLAUDE.md` hard rules **13** (the app suggests, the user decides), **1** (local-first - the
   band must work with no network, ever) and **9** (no server-side domain meaning).
7. `docs/PRACTICES.md` -> the constants-placement policy (compiled / remote / user / frozen). A band
   pack is reference data; place it where that policy says, and say which bucket you chose and why.

## What to build

### 1. The bundled seed pack

Follow the pattern the repo already has for exactly this shape of data:
`ios/Package.swift` declares `.copy("Catalog/VehicleCatalog.seed.json")` and
`.copy("Rates/Rates.seed.json")`; read both loaders and mirror the one that fits best.

The pack is keyed as `docs/SCHEMA.md` specifies: **country, currency, fuel kind, period start,
low, high**. Ship the currencies the corpus actually exercises (RUB, EUR, KZT) and leave the file
obviously extensible.

**THE ANTI-GOAL, and the thing that will make me reject this work: do not fit the bands to the
corpus.** A band derived from the min and max of the fixtures is not a band, it is a lookup table of
the answers wearing a band's clothes, and it will score beautifully here and fail on the first real
receipt. Bands must be **round numbers with a stated rationale** ("RUB petrol, 2024 onward: 40-500,
because retail petrol has not been under 40 since 2019 and the corpus's own regional outlier is
450"), wide enough that a genuine outlier still saves, and coarse enough that quarterly curation
would be plenty. Write the rationale into the JSON as a `source`/`note` field or alongside it.

### 2. The user's price history (ladder step 3, which OUTRANKS the pack)

`docs/SCHEMA.md` is explicit that history is preferred over the pack, because it needs no network,
tracks inflation, and follows the user's own grade and stations. Implement it over the vehicle's
recent fill-ups - the median unit price of roughly the last ten for that vehicle in that currency,
with the +/-60% acceptance the existing `resolveUnmarked` code already applies.

Find the real call sites (`ExtractionAssembler`, and whatever builds it in `ios/App`) and inject
there. The persistence layer is GRDB under `ios/Sources/TankbookCore`; find the existing store or
repository type rather than adding a new one.

### 3. Thread the date through

`FuelExtractor.extract` computes `result.date` and then calls
`resolveVolumeAndPrice(..., date: nil)`. A period-keyed band cannot work until that is fixed. The
corpus spans 2018 to 2026 and RUB prices in it run from 43.38 to 450.00 per litre, so the era is
not a detail.

### 4. Inject in the corpus scorer too

`ios/Tests/TankbookCoreTests/AccuracyRatchetTests.swift` builds a bare `FuelExtractor()`. If the app
injects a provider and the scorer does not, the recorded number measures a parser the app never
runs - the same argument the existing `source: .pump` comment in that file makes. Inject the
**bundled pack** (a corpus fixture has no user history, and say so in a comment).

## The semantics you must preserve

- **Exactly one candidate in band decides. Both in, or neither in, returns nil.** That is what
  makes this a ranking input rather than a guess, and it is already how `resolveUnmarked` is
  written - keep it.
- **Bands rank, never veto.** A value outside every band is still saved if the user types or
  confirms it. No band ever rejects a fill-up, blocks a save, or raises an error.
- **Hard rule 13**: whatever the ladder decides is a pre-fill the user edits, and once edited it is
  theirs forever.

## The traps, by fixture. Your tests must cover these by name

| fixture | pair | what MUST happen |
|---|---|---|
| receipt-012 | `52.15 Х 23.99` | LPG at 23.99 RUB/L sits BELOW any petrol band. With a petrol band it resolves backwards - 52.15 called the price. A fuel-kind-keyed LPG band contains both operands, so the honest answer is **nil**. This is the fixture that proves the fuel-kind key is load-bearing. |
| receipt-007 | `43.61 Х 99.40` | The corpus's swap fixture. Truth is 43.61 L at 99.40. If your band cannot separate them, **nil** - never the swap. |
| receipt-008 | `48.89 Х 48.80` | Genuinely undecidable. Must stay **nil** forever; a band that "resolves" this one is overfitted. |
| receipt-025, -029, -040, -041 | both operands plausible | **nil** from the pack alone; these are what step 3 (history) exists for. |
| receipt-003, -004, -005, -014, -015, -024, -026, -032 | volume under 43 L, price well above | should resolve, and are the bulk of the gain. |
| receipt-043 | `40 Х 120.00` | width-dependent. Say which way yours falls and why - both answers are defensible, a wrong one is not. |

## Tests, and the counts they must beat

- `cd ios && swift test` is **1258 tests in 118 suites, all passing, today**. It must still pass and
  the count must rise.
- Unit tests for the pack loader, the history provider, and the ladder's decision table - including
  every named fixture above, as `[String]` line arrays (the `extract(textLines:)` overload), not as
  images.
- **Mutation-check every load-bearing assertion and report the result.** For each: state the
  mutation, the test that failed, and confirm you restored the file. A test that passes when you
  break the code it covers is worse than no test. Name the vacuous traps you avoided: `#expect(x
  != nil)` on a field that was already non-nil, asserting a band merely "exists", or a decision
  test whose two candidates are so far apart that any rule would separate them.
- Re-measure the corpus with the diagnostics harness and put the numbers in your report:

      cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=/tmp/rv48b \
        swift test --filter ReceiptFieldDiagnostics

  then read `/tmp/rv48b/receipt-field-report.txt` - it is per fixture and per field.
- **If a recorded mark moves, update it**: `Spike/ReceiptSpike/fixtures/high-water.json` (numbers
  AND a `_note` entry in the existing style), `CorpusCompressionTests.recordedReceipts`, and - if
  the PUMP class moves, which it can, because pumps run the same ladder -
  `PumpPhotoGate.measuredHits`/`measuredTotal`. The gate test asserts them against the live score,
  so it will tell you.

## The baseline gate (CLAUDE.md rule 14) - judged by exit code, not by reading output

    cd ios && swift build            # must exit 0
    swiftlint lint                   # from the REPO ROOT, must exit 0 errors
    cd ios && swift test             # must exit 0, count must rise above 1258

Run `echo $?` after each and put the three numbers in your report.

## Out of scope - do not build these

- The server endpoint `GET /reference/fuel-price-bands` and any backend change. Bundled seed only;
  the pack-download path is a later task.
- The pump class and its flag.
- The RV.48 storage half (persisting the assignment on `Attachment`) - a separate task.
- Any change to fixture ground truth, and any new fixture.

## If you run short of budget

Land the **smallest working slice** rather than a half-written large one, in this order: the pack
plus the loader, then the date threading, then the scorer injection, then the history provider. Each
of those is independently useful and independently testable. Save your files as you go; three
earlier agents on this task reasoned to the end of their budget and left nothing on disk.

## Report back

1. The three exit codes (build, lint, test) and the test count.
2. The corpus numbers before and after, per class, and the per-fixture list of what moved.
3. Your band table, with the rationale for each row's width - and an honest statement of which rows
   are curated judgement and which are the corpus talking.
4. The mutation checks, each with its mutation and the test that failed.
5. Anything you chose not to do, and why.
