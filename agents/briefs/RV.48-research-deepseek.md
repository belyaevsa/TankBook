# RV.48 research: raise LOCAL receipt extraction accuracy, and decide what is worth keeping

You are doing **research and design only**. You write exactly one file. You change no code.

## Where you may write

Only this one path, inside the worktree you are started in:

    diagnostics/RV.48-proposal-deepseek.md

**This brief is deliberately NARROW, and here is why.** Three earlier agents on the wider version
of it reasoned all the way to the end of their run budget and saved almost nothing to disk - two
of them produced 100 KB of excellent transcript and an empty or skeleton file. So: **answer only
questions 1 and 3** (the
cleaning stage, and the volume/price pair - the two hardest, and the two another agent is least
likely to get right). Skip questions 2, 4 and 5 entirely; other agents cover them. Budget your
reading: the two dump files plus `FuelExtractor.swift`, `NumberScanner.swift` and
`HIGH-WATER.md` are enough - do not sweep the app, the schemas or the test suite.

**Rewrite the file after EACH sub-answer, not once at the end.** Treat every save as if the run
ends immediately afterwards.

**Write that file within your first three tool calls**, as a skeleton with the five question
headings and whatever you already believe, then keep rewriting it as you learn. A previous run of
this exact brief did the whole analysis, reached the end of its budget while still reasoning, and
**exited having written nothing** - the entire run was lost. The file on disk is the deliverable;
your reasoning in the transcript is not. Update it after each question you settle, so that whenever
the run ends, the best answer you had is already saved.

Nothing else. Do not create, edit, move or delete any other file. **Do not run any `git` command**
(no `add`, `commit`, `checkout`, `stash`, `status` is fine but pointless). Do not run
`swift build`, `swift test`, `xcodebuild` or `swiftlint` - another process owns those and you would
fight it for the machine. Do not touch `docs/TASKS.md`.

Reading anything in the repo is encouraged.

## Never `pgrep -f`

Your brief is your command line, so `pgrep -f "swift test"` matches YOU and any other agent whose
brief mentions it. If you ever need to check a process, match the name: `pgrep -x opencode`. Never
`pkill -f` anything.

## The problem, measured

The app reads a fuel receipt photo on-device with Apple Vision OCR and a deterministic parser
(`ios/Sources/TankbookCore/Extraction/`). Against the committed corpus of **46 real receipts**
(`Spike/ReceiptSpike/fixtures/receipts/`, ground truth in `expected.csv`), the parser scores

    receipts 101/210 cells
    misses by field: unitPrice=34  liters=30  currency=28  fuelKind=10  total=7

The product owner's framing of the task (RV.48 in `docs/TASKS.md`, read the row):

> "there are all the data, but for a user and for the app important is only entry data. The data
> must be stripped, filtered and left only meaningful. That's the goal of the local OCR."

So there are two halves and this brief is about both: **clean the OCR text first, then extract**,
and **keep only what the parse concluded** rather than a line dump.

Two of the current misses are the sharpest possible illustration of the missing cleaning stage -
the parser returned a **merchant registration number as a volume in litres**:

    receipt-023-rn-tver-fuelcard-95-ru.png     liters: want 20.000     got 32986034.000
    receipt-046-circlek-sikupilli-...-ee.jpg   liters: want 55.800     got 10180925.000

`10180925` is `Reg.kood 10180925` on the Estonian receipt. A confident wrong number is worse than
an abstention (hard rule 13), and it is also data the app has no use for storing at all.

## Your evidence, already gathered for you

Two files in the worktree, generated from the live parser this morning. **Use them; they are the
point of this brief.** Do not regenerate them.

- `diagnostics/receipt-field-report.txt` - per fixture, per field: HIT/MISS with the expected and
  the actually-extracted value, plus the cross-check outcome and the parsed date.
- `diagnostics/receipt-ocr-lines.txt` - the **raw Vision OCR lines for all 46 receipts** with each
  line's normalised bounding box (`y`, `x`, `w`) and confidence. This is exactly what the parser
  sees. Every claim you make must be traceable to lines in here.

## What already exists - do not redesign it from scratch

In `ios/Sources/TankbookCore/Extraction/`:

- `OCRLine.swift` - `text`, `confidence`, `boundingBox` (Vision normalised space, origin
  bottom-left), plus `midY` / `midX`.
- `FuelExtractor.swift` (500 lines) - the entry point. `extract(lines:source:)` runs: currency ->
  date -> fuelKind -> `resolveVolumeAndPrice` -> total -> cross-check -> (pump-only) digit repair.
  `resolveVolumeAndPrice` is a **ladder**: (1) labelled column via header x-positions, (2) the
  operand pair on the line carrying the unit marker, (3) the first operand pair anywhere,
  (4) `loneMarkers`, (5) give up and return `(nil, nil)`.
- `NumberScanner.swift`, `CurrencyDetection.swift`, `FuelKindNormalizer.swift`, `CrossCheck.swift`,
  `DigitRepair.swift`, `FuelPriceBand.swift` (a `FuelPriceBandProvider` protocol that is declared
  and **not yet fed by anything**), `ExtractionAssembler.swift`, `ConfirmPrefill.swift`.
- `FuelExtraction.swift` - the result type: `liters`, `unitPrice`, `total`, `fuelKind`, `currency`,
  `date`, `crossCheck`, `digitRepair`, and per-field confidence.

Storage side: `Attachment` in `ios/Sources/TankbookCore/…/Entities.swift` carries **only**
`ocrText: String?` and `extractedTimestamp: Date?` - the raw lines and a clock. The assignment the
parser computed is used as a Confirm-screen pre-fill and then thrown away.

## Read before you write - these are the authorities

1. `CLAUDE.md` - the hard rules. **13** (the app suggests, the user decides - an uncertain field is
   `nil`, never a guess), **12** (never log domain values), **15** (typing is a peer path), **9**
   (the server never reads domain meaning - so every improvement you propose is on-device).
2. `docs/EXTRACTION.md` - the pipeline's own authority: role assignment, the four cross-check
   outcomes, the named failure modes and which fixture each is pinned to.
3. `Spike/ReceiptSpike/fixtures/receipts/README.md` - what each fixture is and what it proved.
   Long, and worth it: several of the misses in the report are **deliberate** and re-"fixing" them
   would be a regression.
4. `Spike/ReceiptSpike/fixtures/HIGH-WATER.md` - **read this before proposing any tie-break.** It
   records that a decimal-digit-count tie-break was removed on purpose: it scored 3/3 by luck on
   one fixture while returning `99.400 L at 43.610` on `receipt-007` where the truth is
   `43.61 L at 99.40`, and the arithmetic cross-check said PASS because `a x b == b x a`. Any
   proposal that resolves an unmarked operand pair by "which number looks more like a price" must
   explain why it is not that heuristic wearing a new hat.
5. `docs/SCHEMA.md` - field names (canonical across Swift/C#/SQL), the fuel-price-band section, and
   the validation invariants. `docs/SECURITY.md` for the storage question.

## The questions, in order. Answer all five.

**1. The cleaning stage.** Design a deterministic line/token classifier that runs *before* field
extraction and marks lines that can carry no entry data: fiscal and registration ids (`ИНН`, `ФН`,
`ФД`, `ФП`, `ЗН ККТ`, `РН ККТ`, `Reg.kood`, `KMKR nr.`, `STAATUS`, `KAUPMEES`, `Terminal`,
`Kood T07`, `ATC`, `AID`, masked PANs), addresses, phone numbers, cashier names, loyalty ids.
Give the **exact** match patterns you propose and the fixtures each is evidenced by. Then the harder
half: **say what the classifier must never drop** - name the lines in the dump that look like noise
and are load-bearing (the product line, the operand line, the `ИТОГ`/`KOKKU`/`SUMMA` line, the
date). Quantify: how many of the 30 litres misses and 34 price misses does cleaning alone fix, by
fixture name?

**2. Currency - 28 misses, all RUB.** Today `CurrencyDetection` needs a currency *word* in the OCR
text, and most Russian receipts do not print one Vision reads. A document-evidence gate already
exists for **KZT** (P2.10 - the tenge marker `тг` OCRs as `гг`, so the KZ receipt is resolved from
`КГД`, `kofd.kz`, `ККС`, `ЖИЫНЫ` instead). Propose the equivalent **RUB** evidence gate: enumerate
the evidence tokens from the dump, state the precedence against an explicit marker (there is an
existing test "an explicit RUB marker outranks the KZ evidence gate" - keep that shape), and name
every fixture in the corpus that would be at risk of a **false** RUB (`receipt-033` is a Kazakh
receipt in Russian; the Crimean ones; the Estonian ones). Expected +hits, by fixture.

**3. The volume/price pair - 30 + 34 misses, and 26 of the litres misses are ABSTENTIONS**
(`got nil`, the ladder reaching step 5). This is the biggest single block and the most dangerous to
touch. Work through the dump and classify **why each one abstains**, then propose fixes ranked by
safety. Things worth checking in the raw lines: the multiplication separator actually printed
(`269.00*20` on `receipt-015` uses `*`; others use `X`, `х`, `×`, `·`), whether the unit marker
(`л`, `L`, `LTR`, `литр`) is on the operand's own line or stranded on another (`receipt-015` prints
`л =5380.00` on the line *above* the operands), operand ORDER (the corpus has both price-first and
volume-first and `receipt-043`/`receipt-037` falsify decimal-count as a rule), and the labelled
column header vocabulary (`КОЛ-ВО`, `КОЛИЧЕСТВО`, `Kogus`, `Kirjeldus`).
Separate your answers into **(a) deterministic gains** - the receipt itself states the roles and the
parser simply fails to read it - and **(b) cases that genuinely need the price-band step**
(`FuelPriceBandProvider`, currently unfed). For (b), sketch what a shipped band pack would have to
contain to resolve them (per currency, per era - the corpus spans 2018 to 2026 and RUB prices in it
run from 43.38 to 450.00 per litre) and say honestly which fixtures it still cannot resolve
(`receipt-008` is `48.89 L x 48.80` - both operands plausible as either role).

**4. Fuel kind - 10 misses, one of them WRONG** (a petrol-95 read as `lpg`). Find it in the dump,
diagnose it, and propose the vocabulary/normalisation fix. Distinguish "the grade is on the paper
and we failed to read it" from "the paper does not state it".

**5. What to persist (the RV.48 storage half).** Propose the shape of the assignment stored on
`Attachment`: which fields, with what confidence, and how an "assigned nothing" parse is
represented (absent, never an empty string). Then answer the decision the row explicitly leaves
open: **is the raw OCR text trimmed or kept whole?** It is the evidence that lets a bad parse be
re-examined and `docs/EXTRACTION.md`'s failure modes depend on it; it also carries merchant
registration and VAT numbers into on-device storage and through sync. Argue one way, name the cost
of your choice, and say what the schema evolution needs (`docs/SCHEMA.md` + `docs/SYNC.md`; hard
rule 9 makes this a data change with a declarative transform, never a backend deploy).

## The shape of your report

Write `diagnostics/RV.48-proposal-deepseek.md` as a **ranked list of concrete changes**, most valuable
first. For each one, all five of:

    (a) what changes, precisely enough to implement without you
    (b) the evidence - fixture names and the actual OCR lines from the dump
    (c) expected delta in corpus hits, counted per fixture, not estimated in the abstract
    (d) the regression risk: which currently-passing fixtures could this break, and why not
    (e) the test that would prove it, including the mutation that must make it fail

End with a short **"what I would NOT do"** section: the tempting changes you rejected, and why.
That section is worth as much as the proposals - a heuristic that scores well on 46 fixtures and is
wrong in principle is exactly what this corpus exists to catch.

## Explicitly out of scope

Pump displays (the pump class ships behind a failing gate and is a separate problem), the cloud LLM
gateway and anything about its latency, the Confirm screen's UI, sync mechanics, and any change to
`expected.csv` ground truth - if you believe a ground-truth cell is wrong, say so in the report
with the evidence rather than editing it.

## Report back

In your final message: the path you wrote, your top three changes with their expected hit deltas,
and your answer to question 5's trim-or-keep decision in one sentence each. State plainly which
parts of the dump you actually read - a proposal built on the fixture names alone is worth less
than one built on the lines, and saying so is not a failure.
