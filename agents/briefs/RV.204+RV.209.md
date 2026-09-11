# RV.204 + RV.209 - two decisions on the receipt-persistence seam

**Scenarios: J3 · the scanned receipt, J7 · the invoice, J7b · the expense scan.** One brief because
both are the receipt-persistence seam `RV.171`'s guard now watches, and both are "two paths that
should be one, or a documented reason they are two". **Neither is a feature build.**

## RV.204 - one screen, two contracts for the same failure

When a photo write fails on Edit entry, the **fill-up** path BLOCKS and warns in place
(`attachFailedWarn`, entry unchanged - `PJ.48`'s contract); the **non-fill** path `RV.202` added
DEGRADES and toasts (the entry saves without the photo - `RV.149`'s contract). Both report, so hard
rule 8 holds - but same screen, same gesture, same failure, two behaviours by entry kind.
`docs/ERRORS.md` -> Edit entry documents BOTH rows, which is the tell that this is undecided.

**DECIDED by the product owner, 2026-09-11: DEGRADE everywhere.** The save the user asked for lands;
the photo failure is reported after it (`RV.149`'s message); re-attach is the next step (`RV.202`
gives every kind that door). Make the fill-up edit path obey it - it blocks today - and make both
paths call the same handler. Write the reason in `ERRORS.md` as ONE row and delete the other. **L1 from both entry kinds asserting the SAME outcome**, whichever it
is. **L4** in both, EN + RU, of the failure state.

## RV.209 - two `Attachment` builders disagree about what a scan concluded

`writeReceiptPhoto` (`ManualFillUpReceiptSave.swift:208`, the Confirm fill-up) and
`ReceiptAttachmentWriter.write` (`ReceiptAttachSupport.swift:18`, typed attach, non-fill attach,
expense scan) both call `VehiclePhotoStore.save` and both build the row - but build
`extractionMeta` **differently**: `extraction?.assignmentOnly` against
`ScannedSavePlanner.assignment(from:)`. The same photograph through two doors may record two
accounts of what was read - the shape `RV.184` fixed once already.

**Establish whether the two shapes are meant to differ.** Trace what each caller passes and what
each reader of `extractionMeta` expects (grep the readers - the viewer, the Inbox, F9a). If they
should agree, extract ONE builder and make both call it; if they genuinely differ, **say why in the
code** at both sites and **extend `RV.171`'s `ReceiptBindingScanner` to cover row construction as
well as binding** so a third builder cannot appear silently. **L1**: the same extraction through
both doors yields the same `extractionMeta`, or a test pins the documented difference.

## Mutations - named

**RV.204**: make one path diverge from the chosen contract; the cross-kind L1 goes red.
**RV.209**: if unified, reintroduce a divergent `extractionMeta` on one door; the equality L1 goes
red. If documented-different, the extended guard must go red on a third builder - add one in a
scratch file, show red, delete it. Verbatim, byte-identical restores.

## Vacuous traps

- Documenting the `RV.204` difference as intentional without a reason a user would recognise.
- Unifying `RV.209`'s builders without checking what each caller actually passes.
- A guard extension that passes on the current tree without having been shown to fail.
