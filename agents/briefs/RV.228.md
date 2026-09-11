# RV.228 - the `units` import ambiguity is documented twice and exists nowhere

**Scenario: F6 · import file won't parse.** Small. F6's first walk found it; F6 cannot be marked
implemented while its journey text promises a units question the code cannot ask.

`ImportAmbiguity` names `units` as a kind (`ImportModels.swift:254`); `docs/API.md` documents it
(`:444`, `:502`); no parser emits it, no client reads it, and `canCommit` blocks only `dateFormat`
(`ImportModels.swift:376-379`). Both shipped importers are metric, so nothing is reachable today.

## Decide, then do the small thing

**Take option (b) unless you find a reason not to**: the units question is `P5.4b`'s (the first
imperial importer) and not v1's. So: in `docs/JOURNEYS.md` F6, mark the units half of *"never
import with guessed units/currency"* as **N/A for v1 - both importers are metric; the question
ships with the first imperial importer (P5.4b)**; make the `ImportModels.swift:254` comment and
both `API.md` lines say `units` is **reserved and not emitted by any v1 parser** - do not delete
it from the wire contract (that is a breaking-change review for nothing). If you instead find an
importer that CAN be ambiguous today, stop and report - that is option (a) and a bigger row.

## Also F6a's text and the preview hint (from F6a's walk)

F6a's bullets 1 and 4 promise *detected units* and *units adjustable here*; mark both **N/A for v1**
the same way, and fix the preview hint *"check the units below"* (`ImportPreviewView.swift:99`),
which points at a units row that is not adjustable - reword it to what the preview actually lets
the user change (date format, currency when asked). Same change, same test binding the texts.

## Tests

- **L1**: the three texts agree - a test that reads the `ImportModels` doc comment, the `API.md`
  lines and F6's sentence and asserts each carries the word *reserved* (or the N/A marker), so
  one cannot be edited without the others. Cheap, and it is the `RV.210`-shaped guard for this
  exact drift.
- **L1**: `canCommit` with a `units` ambiguity present still returns `true` **and this is now
  documented as intended** in the test name, not left as an accident.

## Mutation - named

Remove *reserved* from one of the three; the agreement L1 goes red.
