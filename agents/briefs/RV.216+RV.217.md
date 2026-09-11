# RV.216 + RV.217 - the Inbox card's row number and its RU label column

**Scenarios: J3 · the receipt catches up with you, and J7.** Both found by the orchestrator opening
`RV.201`'s screenshots; no test saw either. One brief: same card, same `FieldLabel`, same column.

## RV.216 - the row is numbered from zero

EN *"Row 0"*, RU *"Строка 0"*. `FieldLabel` renders `.lineItem(n)` with the array index verbatim
(`ios/App/Sources/Shared/FieldLabel.swift:28`). Users count from one. `RV.201`'s agent fixed the
neighbouring bug on that line (`Row %@ 0`, an un-interpolated format string) and did not notice
the number.

**Build**: render `n + 1` **in the label**, never in `FieldRef` - the ref is an index into `items`
and the merge depends on it. Check `AttachmentRecognisedView` uses the same `FieldLabel` (it should
since `RV.201`); if any other surface prints a line index, it moves too.

## RV.217 - the RU label column hyphenates

*Мастерская* breaks as **Мастер-ская** across two lines in the three-column "yours vs the receipt"
comparison, whose left column is fixed-width. **This is the shape the product owner already rejected
once** - on 2026-09-10 a hint inlined into a narrow column hyphenated into a five-line RU stack and
the instruction was that such labels *"should be at the bottom and take the whole width of the
box"*. Same mistake, different screen.

**Build**: give the label the width it needs, or stack the label above its comparison row. **Measure
against the longest RU label, not the English**: `Мастерская`, `Стоимость`, `Категория`, `Строка N`.
A fix that fits the EN is the bug again in RU. `tabular-nums` on the value columns stays.

## Tests

- **L1**: `.lineItem(0)` renders *Row 1* / *Строка 1*; the ref still addresses `items[0]` -
  **both asserted**, or the fix moves the bug into the merge.
- **L4 `InboxUITests` EN + RU**: the service offer's first line reads *Row 1* / *Строка 1*.
- **Screenshots EN + RU** re-shot on the `RV.201-inbox-service` pose - **the orchestrator opens
  them and no RU label may hyphenate**. That is the check for `RV.217`; XCUITest cannot see it.

## Mutation - named

Restore the raw index in `FieldLabel`; the *Row 1* L1 goes red. Byte-identical restore; verbatim.

## Vacuous traps

- Offsetting `FieldRef` itself.
- Shrinking the label font below the `DESIGN.md` scale to fit.
- Testing the tick identifier `inboxTick_lineItem_0` and calling `RV.216` proven.
