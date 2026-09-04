# RV.48 stage three: the four remaining deterministic gaps in receipt extraction

Design and implement. Code first, exploration second.

## Where you work

The worktree you are started in:

    /Users/sbelyaev/repos/fuel-counter-ios/.claude/worktrees/rv48   (branch rv48-local-extraction)

Write only inside it. **Never `cd` to the main checkout** at `/Users/sbelyaev/repos/fuel-counter-ios` -
another session is live there.

**Run no `git` command at all.** The orchestrator verifies and commits; an agent that commits
destroys the verification record. Leave the work uncommitted.

**Do not touch**: `docs/TASKS.md`, `agents/briefs/`, any `expected.csv`, any fixture image, and
anything under `ios/Sources/TankbookCore/Extraction/FuelPriceBand*` (stage two landed an hour ago
and is verified - do not re-open it).

**Never `pgrep -f`** - your brief is your command line, so it matches you. Use `pgrep -x opencode`,
`pgrep -x xcodebuild`. Never `pkill -f`.

## Where the corpus stands

Receipts score **158/210** (75.2%). Stage one cleaned the OCR and added a RUB evidence gate; stage
two made the price band real. Read `Spike/ReceiptSpike/fixtures/high-water.json` `_note` for both,
and `docs/EXTRACTION.md` for the pipeline.

Regenerate the evidence any time with:

    cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=/tmp/rv48c \
      swift test --filter ReceiptFieldDiagnostics

`/tmp/rv48c/receipt-field-report.txt` is per fixture and per field; `receipt-ocr-lines.txt` is the
raw Vision output with bounding boxes and a `[FILTERED …]` marker on lines the noise filter removed.

**52 cells still miss. This brief is about 22 of them.** The rest are deliberate abstentions
(`receipt-007`, `-008`, `-012`, `-029`, `-040`, `-041` need the user's own history or are honestly
undecidable) or belong to a later task.

## The four gaps, with their evidence

### Gap 1: the Estonian unit price is on the SAME line as its label (+5, maybe +6)

Five fixtures miss `unitPrice` and print it plainly:

    receipt-038   [y=0.627] 1,754 EUR/L
    receipt-039   [y=…]     1,744 EUR/L
    receipt-042   [y=0.648] 1,839 EUR/L
    receipt-045   [y=…]     1,919 EUR/L
    receipt-046   [y=…]     1,799 EUR/L

`FuelExtractor.loneMarkers` has a price path, but it looks for a value on a line **below** a bare
`/L` label. Here the label and the value are one line. Handle the self-describing form. Mind that
`Pump 5 Hind 1,799 EUR/L` also carries a pump NUMBER - `5` must not become the price.

### Gap 2: a product name split across lines (+1)

`receipt-042` misses `fuelKind`. Its product string is broken by the OCR into
`[y=0.675] miles` on one line, with the grade on another. The Circle K vocabulary added in stage one
(`FuelKindNormalizer.circleKLoyaltyGrade`) requires `MILES` and the grade on the SAME line, which is
right for the other four Estonian fixtures and wrong for this one. Decide whether joining adjacent
lines on a shared baseline is safe, and if it is not, say so and leave the cell missing - an honest
abstention beats a rule that fires on the wrong pair of lines.

### Gap 3: the fuel kind is unreadable, and that BLOCKS THE BAND (+4 kinds, and up to +6 more)

This is the highest-value item and the reason it is not just a vocabulary chore. Stage two's band is
keyed by fuel kind, and it correctly refuses to apply a petrol band to an unknown kind (that is the
swap `receipt-012` proves the key prevents). So on these fixtures the undetected kind **also costs
the volume and the price**:

| fixture | the product line, as Vision read it | misses |
|---|---|---|
| receipt-032 | `AM-95-K5 PuLsar-95 N 5:00000` and `95PuLsar AM-95-K5` | fuelKind, liters, unitPrice |
| receipt-043 | (see the dump) | fuelKind, liters, unitPrice |
| receipt-044 | `AM-95` | fuelKind, liters, unitPrice (also gap 4) |
| receipt-018 | (see the dump) | fuelKind |

The octane pattern is `A[ИH][\s\-–]*(\d{2,3})` over the homoglyph-canonical key
(`FuelKindNormalizer`, and note `М -> M` is ALREADY in `latinTwin`). `АИ` is being read as `AM`, and
`И -> M` is not a homoglyph pair - it is a smear in thermal print.

**This is exactly where the corpus's own rule applies**: `Spike/ReceiptSpike/fixtures/HIGH-WATER.md`
forbids resolution by resemblance, and `receipt-027`'s `АИ-96` is deliberately NOT snapped to 95 for
that reason. So do not simply widen the letter class. **Require corroboration on the same line**,
and `-К5`/`-K5` is the obvious candidate: it is the Euro-5 grade suffix, it is itself a fuel token,
and it appears on `receipt-032` and on most Russian product lines. `PuLsar-95` repeating the octane
is a second corroborator. Write down the rule you chose, why it is corroboration rather than
resemblance, and what it would take for it to fire on a non-fuel line.

Then confirm the band actually unlocks for 032/043/044 - the report will show it.

### Gap 4: the Russian labelled column and the reference-block price (+6)

`receipt-023`, `-030` and `-044` state the roles and the parser does not read them:

- The quantity header vocabulary is `["КОЛ", "QTY", "КОЛИЧЕСТВО", "KOGUS"]`. `receipt-023` prints
  `товар | единиц | сУмма`; **`ЕДИНИЦ` is missing.**
- The price label vocabulary (`isPricePerUnitLabel`) has `/L`, `/Л`, `ЦЕНА/ЛИТР`, `ЦЕНА ЗА 1 ЛИТР`,
  `HIND/1L`. These three print **`Цена за ед.`**, in a `Справочная информация` reference block, and
  it is the ONLY source of the unit price on the paper. The value sits on the SAME baseline to the
  right on `receipt-023` and `receipt-030`, and slightly below-right on `receipt-044`.
- Structurally, `labelledColumn` returns nil unless it finds BOTH a price header and a quantity
  header. `receipt-023` has a quantity column and states its price elsewhere, so the whole path
  returns nothing and both fields are lost. **Let step 1 contribute PARTIALLY** and let the later
  steps fill what it could not.

## What must not change

- **Hard rule 13.** Every new path either resolves for a stated reason or returns nil. A confident
  wrong value is the one outcome that is worse than a miss.
- **No decimal-count or operand-position tie-break** (`HIGH-WATER.md`), no currency from magnitude,
  no OCR-confidence threshold used to accept a value.
- Do not weaken `ReceiptNoiseFilter`: if a fix needs a line the filter removes, that is a filter bug
  and you must say so rather than deleting a rule. `Цена за ед.` and its value are NOT filtered
  today - check before assuming.
- The three remaining confident-wrong values in the class are all in `total` (receipts 017, 018,
  025). **Do not touch the total finder** - it is a separate task. If your work changes a total,
  that is a regression to explain, not a bonus.

## Tests

- `cd ios && swift test` is **1293 tests in 121 suites, all passing** today. It must still pass and
  the count must rise.
- A test per gap, driven by `extract(textLines:)` with the lines quoted exactly as the dump shows
  them - misreads included. Name the fixture in the test name.
- **Mutation-check every load-bearing change and report each one**: the mutation, the test that
  failed, and confirmation you restored the file byte-identical. Vacuous traps to avoid: asserting
  a field is non-nil when it already was, asserting a vocabulary array "contains" a string rather
  than asserting the parse OUTCOME, and a corroboration test whose line would also pass without the
  corroborator.
- Re-measure the corpus and update `Spike/ReceiptSpike/fixtures/high-water.json` (numbers AND a
  `_note` entry in the existing style), `CorpusCompressionTests.recordedReceipts`, and
  `PumpPhotoGate` if the pump class moves.

## The baseline gate - judged by exit code, not by reading output

    cd ios && swift build      # exit 0
    swiftlint lint             # from the REPO ROOT, exit 0
    cd ios && swift test       # exit 0, count above 1293

Run `echo $?` after each and report the three numbers.

## Out of scope

The total finder, the pump class, the RV.48 storage half, the band pack, the server endpoint, any
fixture or ground-truth change, and `receipt-027`'s `АИ-96` (settled: it stays unresolved).

## If you run short of budget

Land the smallest complete slice, in this order: gap 1, gap 4, gap 3, gap 2. Save as you go.

## Report back

The three exit codes and the test count; the corpus before/after per class; which fixtures moved and
which did not; your corroboration rule for gap 3 in full, with the argument that it is not
resolution by resemblance; every mutation check; and anything you chose not to do.
