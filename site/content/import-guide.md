+++
title = "Import from My Fuel Manager"
description = "Where the My Fuel Manager CSV export lives and what Tankbook does with it: one format, parsed on our server, reviewed by you before anything is written."
+++

## The short version

My Fuel Manager exports its data as CSV files, one per category. In Tankbook, open **Settings →
Import from another app**, choose **My Fuel Manager**, pick the file, review what we read, and
confirm. Nothing is written until you confirm.

## Where the export lives

Look for the export or backup option in My Fuel Manager's menu. The export saves a separate CSV
file for each category, so the file you want is the one whose first line names it, like
`My Fuel Manager - Fuel` or `My Fuel Manager - Costs`. Each file is imported separately.

Get the file onto your iPhone however you like: AirDrop, the Files app, or a copy emailed to
yourself all work. Tankbook reads the file through the system file picker, so anything that puts
the file on your phone works.

## What Tankbook does with the file

- **Parsed on our server.** One parser serves every Tankbook user, so a mapping fix reaches you
  without an app update. This is the only step that needs a connection.
- **Reviewed by you before anything is written.** The parse returns candidate rows. You see a
  preview – how many fill-ups, the date range, the last odometer – then review and edit the rows
  that need a look. Only the rows you confirm are written.
- **Nothing of yours is stored or logged.** No amount, station or note from the file is ever
  logged. The file and its parse result are kept for 30 days and then deleted. You do not need an
  account.

## What can go wrong

- **"This doesn't look like a My Fuel Manager export."** The file did not match the format we
  know. Make sure you exported from My Fuel Manager and picked the right file.
- **A row that needs a look.** Rows the parser cannot place are marked, not dropped. You can fix
  the field, leave the row out, or import it as-is.
- **Ambiguous dates.** Dates that read either way are checked once, before anything is committed –
  the app never guesses silently.

## One more thing

Only My Fuel Manager is supported today; other apps are on the roadmap. A file that is not a My
Fuel Manager export is turned away rather than mis-read. If your app is missing, the import screen
offers to take the file so the format can be added.
