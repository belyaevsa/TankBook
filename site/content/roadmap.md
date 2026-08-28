+++
title = "Roadmap"
description = "What is shipped in Tankbook, what is next, and what was deliberately cut – one honest page, updated as the app ships."
+++

Three lists, kept honest: what ships today, what comes next, and what was deliberately cut. Nothing
on this page is a promise; the shipped list is the record.

## Shipped

- **Capture and manual entry as peers.** Snap the receipt, or type it in – both doors take seconds,
  and a scan is a head start you correct, never an answer you accept blindly.
- **On-device reading** of receipts and charging screenshots, with the arithmetic cross-check shown
  on every entry: litres × price has to equal the total.
- **One history for every powertrain** – petrol, diesel, hybrid, EV – with consumption maths that
  knows litres from kilowatt-hours.
- **True multi-currency with historical rates:** a fill-up abroad keeps both amounts, converted at
  the rate on the day of the fill-up, and the snapshots never rewrite your history.
- **Service entries, parts and reminders**, alongside the fuel log.
- **Recently deleted with a 30-day undo**, and sync-overwritten edits kept the same way – nothing is
  lost silently.
- **Sync and restore** across your own devices, attachments included, on an optional account.
- **Account and device management:** sign in with Apple or Google, revoke a device, delete the
  account – a tombstone that leaves the log on your phone untouched.
- **The cloud extraction gateway** as a fallback for scans the on-device reader cannot crack –
  images processed transiently, never retained.
- **Import from My Fuel Manager (CSV)**, review-first: the file is parsed into candidates, you
  review every row, and only you commit.
- **Export always free:** CSV, JSON, or the versioned archive format.

## Next

- **Pump-display capture** – point the camera at the pump itself, before the receipt prints. It is
  built to ship, and switched off today: the reading quality is not yet honest enough to turn on.
- **Importers for the apps you are leaving** beyond My Fuel Manager – Drivvo, Fuelio, Spritmonitor
  and the rest – same review-first shape.
- **The Garage tab and the Account & devices screens** as full surfaces in the app.
- **TestFlight, then the App Store** – the ring opens soon; feedback during it shapes the release.
- **CarPlay** – your costs and reminders on the dash.
- **Android** – possible later: the sync protocol was designed for it from the start. Nothing
  promised, nothing dated.

## Deliberately cut

- **On-device AI normalisation** (the system language model): cut because it reports itself
  unavailable for Russian and the other languages where the rules parser is weakest – it would have
  been missing exactly where it was needed. The cloud gateway does this job instead.
- **End-to-end encryption in v1:** a signed-off trade – real E2E with multi-device sync needs
  user-held recovery keys, the exact UX that loses non-technical users their data. It may return as
  an opt-in once recovery is solved.
- **CloudKit:** replaced by our own sync backend before launch – one sync system, not two.
- **A paid tier:** deferred, not cancelled. Nothing is for sale today, so the app has no paywall and
  this site quotes no price beyond free.
