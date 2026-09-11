# RV.214 - what names a service well enough to save on

**Scenarios: J7 · the invoice in your hand, J7b · the shop receipt.** `RV.206`'s decision one entry
kind over, made separately because the service gate is NOT the same code and its reason is
different. **Closes `PJ.50` too** - see the end.

## The gate

`ServiceEntryView.saveEnabled` requires `form.hasTitledItem` (`ServiceEntryView.swift:210`; the
disabled-save hint at `:478`). `RV.206`'s agent found it, judged it a different decision, and filed
it rather than changing it - correctly, because **a service has no amount requirement**, so
`hasTitledItem` is the only thing between a wholly blank `ServiceRecord` and the database.

But: `EntryTitle`'s service chain (`RV.187`) names a service from its **vendor**, else its first
named item, else that item's **category**; and `InvoiceSplitter`'s lump-sum item is titled
`vendor ?? ""`. So a vendor-less scan with a categorised lump sum is nameable and still blocked;
and a typed service with a vendor and an amount and no line item at all - the lump-sum record J7's
Fallbacks call *"a perfectly good record"* - **cannot be saved on the create screen**, while
`RV.198` made the empty item list legal on the edit screen. Two doors again.

## Decide, then build

What is the minimum that names a service and makes it a record? Candidates: **a vendor, or a titled
item, or a categorised item** - plus **either an amount or at least one line** so the record is not
wholly blank. Find the gate's original commit (`git log -S hasTitledItem`) and its reason; state it.
Then ONE rule, in `ServiceEntryFormState`, that the create gate and the edit gate both call, so the
two doors cannot disagree (`RV.212`'s brief is settling the odometer half of the same problem on the
same screens - if it has landed, use its shape).

The disabled-save hint (`:478`) must name **what is missing** under the new rule (hard rule 7).
Its copy changes -> `docs/ERRORS.md` -> Service entry, EN + RU.

## PJ.50 - close it against RV.206, keep only what is still true

`PJ.50` says *"the expense scan door always ends at the keyboard"* because `canSave` needed a
title - `RV.206` removed that. Its remaining half is a **merchant-line title suggestion** for the
expense form, dimmed until touched. **Do not build it here.** In your report, state that `PJ.50`'s
complaint is resolved by `RV.206` and whether the suggestion is worth its own row; the orchestrator
closes `PJ.50`.

## Tests

- **L1, FAILS TODAY**: a service with a vendor and an amount and NO items is saveable, and its
  Log row reads the vendor.
- **L1**: a scanned lump sum with a category and no vendor is saveable, and the Log row reads the
  category.
- **L1**: a service with no vendor, no items and no amount is refused, and the hint names what is
  missing.
- **L1**: create and edit apply the SAME rule - asserted from both.
- **L4 `ServiceEntryUITests` EN + RU**: the lump-sum save; the hint's copy.

## Mutation - named

Restore `hasTitledItem` as the sole gate; the vendor-only L1 goes red. Byte-identical; verbatim.

## Vacuous traps

- Deleting the gate so a blank record saves.
- Asserting Save is enabled rather than that the record persisted and the Log names it.
- Two rules, one per door.
