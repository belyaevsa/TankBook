# RV.207 - the field guard counts a pass-through as a write

**no-scenario: guard completeness.** Cross-cutting; gates `PJ.61`. `[!]`

## The blind spot

`FieldWriterScanner` (`RV.196`) counts a non-literal init argument as a write.
`ServiceEntryItemDraft.serviceItem(homeCurrency:)` passes `partNumber: partNumber ?? original?.partNumber`
- non-literal, accepted - and **nothing can ever put a value in `partNumber`**: the draft's own field
is never set, so the expression forwards whatever the decoder restored, `nil` forever. A false
negative in the guard built to find dead fields; `PJ.61` therefore has no exception to remove and
the loop `PJ.63` relies on is broken. Found by the `PJ.63` agent, reported rather than papered over.

## Build

Teach the scanner that an argument which can only forward an existing value is not a write. The
shapes: `x ?? original?.x`, `original?.x`, a bare re-read of the same field from a source object.
**Do not simply exclude `??`** - `count ?? 0` with a real left operand IS a write; the rule is
about the left operand being itself unwritten. Reuse the scanner's existing "is this identifier
assigned anywhere outside its declaration" pass on the left operand; if it is not, the whole
expression is a pass-through.

Then run the guard: it should now report `ServiceItem.partNumber` (and, per `PJ.60`, check
`Expense.recurrence` the same way). **Add the reasoned exception naming `PJ.61` as the row that
will write it** - that is the loop closing correctly: guard reports, row is filed, exception names
the row, row deletes the exception.

## Tests

- **L1, FAILS TODAY** (i.e. the guard is green today and must go red): `ServiceItem.partNumber` is
  reported unwritten before the exception is added.
- **L1**: `count ?? 0`-shaped arguments with a written left operand are still counted as writes -
  the calibration pair, from a real field in the tree.
- **L1**: the self-check still fails a blank-reason exception and a stale one.

## Mutation - named

Revert the pass-through rule; the `partNumber` L1 goes green-when-it-should-be-red (report it as
the guard's own failure to fail). Restore; verbatim.
