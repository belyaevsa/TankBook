# RV.48 – local receipt extraction: cleaning stage & persistence (run 2, narrowed)

Status: skeleton. Sub-answers are written incrementally; each section is complete only when its
marker says COMPLETE.

Carried forward from run 1 (confirmed as working assumptions, re-verified against the dump):
- **Bare value lines are load-bearing.** A bare 4–6 digit decimal line IS the total or the line
  extension; any id-stripping rule keyed on digit count must never touch short decimals.
- **The `Справочная информация` / `Цена за ед.` reference block is data** (only source of
  `receipt-023`'s and `receipt-044`'s unit price); the `1 ед.=1 литр для нефтепродуктов/СУГ`
  convention line is noise that fabricates BOTH a volume and an `lpg` fuel kind.

## Change 1 – (pending) Q1: the cleaning stage

COMPLETE marker: no.

## Change 2 – OUT OF SCOPE (Q2: RUB currency evidence gate)

Another agent covers questions 2, 3, 4 in this narrowed run. Heading kept for merge.

## Change 3 – OUT OF SCOPE (Q3: the volume/price pair)

Another agent covers questions 2, 3, 4 in this narrowed run. Heading kept for merge.

## Change 4 – OUT OF SCOPE (Q4: fuel kind)

Another agent covers questions 2, 3, 4 in this narrowed run. Heading kept for merge.

## Change 5 – (pending) Q5: what to persist

COMPLETE marker: no.

## What I would NOT do

(pending)

## Evidence statement

(pending – will state which parts of the dump were actually read)
