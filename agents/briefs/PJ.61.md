# PJ.61 - `partNumber` gets its writer: a field on the service item editor

**Scenario: J7b · parts, tires, consumables.** Decided by the product owner 2026-09-11: option 2 -
the field ships in v1 on the item editor. **After `RV.207`** (the guard must be able to see the
field before this row can delete its exception).

`ServiceItem.partNumber` is written `nil` at `ServiceEntryDraft.swift:12` and
`ImportConversion.swift:147`, read nowhere, and not editable even after `PJ.23`'s item editor.
`SCHEMA.md:228` promises it.

## Build

One more row on the item card - both doors: `ServiceItemLifetimeFields`' sibling on the EDIT card
(`EditEntryNonFillView`) and on the CREATE card (`ServiceEntryItemCard`, once `RV.213` lands; if it
has not, put it on both cards yourself, one view). Free text, optional, keyed to the row it was
loaded from so a delete never shifts it (the `PJ.23` rule). The Log row does not show it; the item
row on Edit entry does, dimmed, when present.

**Then close the guard loop**: run `SchemaFieldWriterGuardTests`; `ServiceItem.partNumber` must now
be reported as WRITTEN, and the reasoned exception `RV.207` added naming this row is deleted - the
stale check fails until it is.

## Tests

- **L1, FAILS TODAY**: an item edited with a part number round-trips it through save and reload.
- **L1**: the guard reports `partNumber` written and its exception is gone.
- **L4 `EditEntryUITests` EN + RU**: the field on the item card; frames, capture lines. RU is where
  *Номер детали* on the narrow card runs longest.

## Mutation - named

Drop the field's write in the draft -> item conversion; the round-trip L1 goes red AND the guard
goes red. Byte-identical restore; both verbatim.
