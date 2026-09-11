# RV.212 + RV.213 + RV.224 - the service CREATE door catches up with the edit door

**Scenario: J7 · service visit** (and J7d, which the lifetime offer feeds). One brief because all
three are `ServiceEntryView` / `ServiceEntryItemCard` - the create screen - and each is a behaviour
the edit screen got from `PJ.22`/`PJ.23` that the create screen did not. Hard rule 15's shape: type
and scan are peers, and so are create and edit.

## RV.213 - a lifetime can only be stated AFTER the first save

`PJ.22` put the km / months editor on the Edit-entry line item and extracted
`ServiceItemLifetimeFields.swift` for exactly this reuse. `ServiceEntryItemCard` on the create
screen has none, so the user types the service, saves, reopens, states the interval, and the
*"Remind you next time?"* offer arrives one visit late.

**Build**: the SAME `ServiceItemLifetimeFields` view on the create card - one editor, two doors -
and the offer fires at the first save when a lifetime was stated. **Keep `PJ.22`'s gate**: the
offer fires because a lifetime was stated, not on every service save
(`EditEntryNonFillForm.serviceLifetimeChanged` is the edit-side rule; the create side's rule is
"any item has a lifetime", say so).

## RV.212 - the km-lifetime odometer rule is enforced on one door and not the other

A km-only lifetime needs an odometer or the reminder it proposes has neither due field. The create
path enforces it (`ServiceEntryView.saveEnabled`); `EditEntryView.saveEnabled` returns `true` for
every non-fill entry. Nothing is silently minted - `ReminderOffer.acceptance` returns `noDueField`
and the offer does not appear - but the two doors disagree, and the edit door says nothing about
why nothing happened (hard rule 7).

**Decide which door is right, and make both say it.** The likely answer: **neither should refuse
the save** - a km lifetime with no odometer is a fact the user knows and the app cannot use YET;
the honest behaviour is to save it and say *the reminder needs an odometer* at the offer point.
If you keep a gate, it is one rule in one place both doors call. **Say which and why**, and put
the rule in `docs/ERRORS.md` -> Service entry.

## RV.224 - the "· invoice" date caption survives a manual edit

`dateFromInvoice` keeps its provenance caption after the user changes the date, claiming the date
came from the invoice when it no longer did. Hard rule 13: once changed, it is theirs. Clear the
caption when the date field changes after a scan. **Check the fill-up's Confirm screen for the same
caption behaviour** - if it has the same bug, it is the same line one entry kind over; fix it here.

## Tests

- **L1, FAILS TODAY**: a service created WITH a lifetime raises the offer at first save; one
  created without does not.
- **L1**: the two screens render the SAME lifetime view - assert the type, from both.
- **L1**: the (lifetime, odometer) pair is accepted or refused **identically** by both doors -
  asserted from both, whichever rule you chose.
- **L1**: editing the scanned date clears the invoice caption.
- **L4 `ServiceEntryUITests` EN + RU**: create with a lifetime -> the offer sheet; capture lines
  and frames for the create card with the lifetime fields (RU is where `СРОК СЛУЖБЫ · км · мес`
  runs longest on the narrower create card).

## Mutations - named

**RV.213**: remove the lifetime fields from the create card; the first-save offer L1 goes red.
**RV.212**: make the edit door diverge from the rule; the cross-door L1 goes red.
**RV.224**: restore the caption after edit; its L1 goes red. All byte-identical restores, verbatim.

## Vacuous traps

- A second lifetime editor.
- Firing the offer on every service save.
- Copying the create gate into the edit screen without deciding whether the gate is right.
