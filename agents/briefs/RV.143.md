# RV.143 - a home-currency change that arrives by sync re-homes nothing

**Scenario: J10 · cross-border trip.** The only v1 row holding J10 open.

`RV.140` re-homes a car's pending entries at the point the currency changes - the Vehicle-detail
save. A device that learns the new `homeCurrency` through S9's field-level merge runs no such pass,
so the same account shows resolved entries on the editing device and still-pending rows on every
other one. The re-home write is `.dirty`, so the re-homed ROWS travel; the **trigger** does not.
`RV.136`'s shape: two devices disagreeing because a rule runs on one of them.

**Decide the `RV.152` prompt first** - it is the same territory (what to do with the existing log
when the currency changes) - then this row is what is left: **run the same pass when the currency
ARRIVES, not only when it is typed.** `docs/SYNC.md` S9 is the authority; this is its mirror. One
pass, one function, two triggers - never a second re-home.

## Tests

- **L1, FAILS TODAY**: a pulled Vehicle whose `homeCurrency` differs from the stored one triggers
  the re-home pass over that car's pending entries.
- **L1**: the pass is the same function `RV.140` calls - assert the call, not a copy.
- **L1**: a pulled Vehicle with an unchanged currency triggers nothing.
- Money is a pair (hard rule 3): `rateDate` stays the entry date; snapshots are not rewritten.

## Mutation - named

Skip the pass on the sync trigger; the first L1 goes red while `RV.140`'s own tests stay green.
