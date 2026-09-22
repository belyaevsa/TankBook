# PU.51 - The law says why it abstained

Row: `docs/TASKS.md` -> PU.51. The measurement that motivates it: 2026-09-22, the live path over the
68 heldout stills under the shipped detector - **53 find rows, assign fields and commit nothing**,
9 are fully right, 4 partial, 2 wrong. The largest failure class in the corpus has no diagnosis.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingTypes.swift`,
`PumpReadingLaw.swift`, `PumpReader.swift` (only to carry the reason through `resolve`),
`ios/Sources/PumpReadTool/main.swift` (print it), `ios/Tests/TankbookCoreTests/PumpReadingLawTests.swift`,
`ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` (the histogram print only),
`ml/pump-reader/REPORT.md` (a dated PU.51 section). Nothing under `Spike/` - the corpus is another
session's live work; read it, never write it. **`tools/pump-annotate/` is PU.50's write set, not
yours.** Scratch: `ios/.build/pump-reader-out/pu51/`.

## What exists (read first, in order)

1. `PumpReadingLaw.swift` - `resolve(windows:currency:priceBand:)` and its tiers (exact, preset,
   truncated, board-as-price, repair). Count the `return .abstained` sites; there are about eight,
   and each is a different reason.
2. `PumpReadingTypes.swift` - `PumpFieldReading` and `PumpDisplayReading`, both `Equatable` and
   `Sendable`; `.abstained` is a static. Whatever you add must keep both conformances and must not
   change equality for a committed reading (tests compare readings).
3. `PumpReader.swift` `resolve(image:windows:currency:priceBand:)` - the one call site the app uses.
4. `ios/Sources/PumpReadTool/main.swift` - `committed(_:)` builds the JSON; the live branch also
   prints `rowTexts` and `cellsPerRow`.
5. `PumpReadingLawTests.swift` - the existing fixtures and their oracles; `PumpReaderPipelineTests`
   for the heldout live sweep.
6. `docs/EXTRACTION.md` -> "The pump reader" (the law's conventions) and hard rule 13 (the app
   suggests, the user decides - a reason is diagnosis, never a licence to commit).

This brief's premise is a hypothesis: confirm the abstention sites before changing anything. If a
branch turns out to be reachable only through another, say so rather than inventing a reason for it.

## What to build

A `PumpAbstentionReason` enum (public, `Sendable`, `Equatable`) naming the branch that refused, one
case per genuinely distinct refusal - at least: no liters window, liters all zero, no total window,
nothing closed the arithmetic, more than one candidate closed (ambiguous), the board tier found no
price, a cell read as unknown, the value fell outside the price band. Carry it on
`PumpDisplayReading` (`reason: PumpAbstentionReason?`, nil when anything committed) and, where a
single field abstains while others commit, on `PumpFieldReading`. `PumpReader.resolve` passes it
through unchanged; `pump-read` prints it as `"abstainReason"` beside `committed`.

**It is a pure addition**: no branch changes its verdict, no reason is read to decide anything, and
the committed counts on both paths are identical before and after - that is the headline claim and
the test below is what proves it.

Out of scope: changing any law verdict, the verifier (PU.47 landed), the annotator (PU.50), any
attempt to FIX an abstention - this row explains, it does not repair.

## Tests you must add

`PumpReadingLawTests`:
- one test per reason with a fixture that takes that branch, its oracle named in the test's comment
  (e.g. `pump-016`/`pump-017` are the idle heads: liters all zero; `pump-031` carries
  `csvDisagrees` and its total does not close; build a synthetic two-candidate window for the
  ambiguous case if no fixture is ambiguous - say which you used);
- a committed reading carries `reason == nil`.
**Named mutation**: make the "nothing closed" and "ambiguous" branches return the SAME case - the
test that separates them must go red. Paste red-then-green.

`PumpReaderPipelineTests`: the live sweep prints a reason histogram over the heldout stills (the 53
that commit nothing), and **asserts the committed count and precision are unchanged** (43 / 1.000
with the shipped detector today) - the pure-addition claim, measured.

## Checks

`scripts/gate.sh` (you change core code; if lint exits 132 note that `build/` is now excluded in
`.swiftlint.yml` and re-run), `swift test --filter "PumpReadingLawTests|PumpReaderPipelineTests|PumpRowGeometryTests"`
with counts, `swiftlint lint` from the repo ROOT exit 0. Verify by exit code.

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green verbatim, **the reason
histogram over the 53** (this is the row's real output - which refusal dominates), and anything
found and not fixed.
