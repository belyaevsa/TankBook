# PJ.60 - drop `Expense.recurrence`

**Scenarios: J7b · purchase, J7d · a reminder is born.** Owner decision 2026-09-12: **drop it.**
The recurring-expense promise's reminder half is met by `ReminderOffer`; the next-entry half was
never built, so the column, the `RecurrenceRule` type and its `Codable` exist with zero function.

## Build

Delete `Expense.recurrence`: the field, `RecurrenceRule` if nothing else uses it (check
`Reminder.Recurrence` is a different type - `Records+Extras.swift:35` - and stays), the
`Records.swift:534,545` encode/decode, the `Migrations.swift:282` column (a forward migration
that drops it, or a documented no-op if GRDB's migration story makes a drop costlier than a
dead column - say which and why), `expense.schema.json` in the registry per `SCHEMA.md`'s schema
evolution rules (a data change, rule 9 - version and transform as the doc prescribes), and the
`SCHEMA.md:237` sentence. `RV.196`'s field guard and `PJ.63`'s heading note: the guard must now
SEE `Expense` - fix the shared-heading blind spot if it is one line, otherwise say so.

## Tests

- **L1**: `recurrence` is gone from the type, the migration, the schema registry and the decoder;
  a grep in the report shows no `recurrence:` on `Expense` anywhere.
- The reminder recurrence tests stay green (different type).
- `swift test` in full; backend untouched (the server never reads the field - confirm with a grep
  of `backend/`).

## Mutation - named

None - a deletion. Show the grep and the schema-registry check passing. No UI.
