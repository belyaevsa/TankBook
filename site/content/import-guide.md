+++
title = "Import from My Fuel Manager or Drivvo"
description = "Where the My Fuel Manager and Drivvo CSV exports live and what Tankbook does with them: parsed on our server, reviewed by you before anything is written."
+++

## The short version

Tankbook imports CSV exports from two apps: My Fuel Manager and Drivvo. In Tankbook, open
**Settings → Import from another app**, choose the app the file came from, pick the file, review
what was read and confirm. Nothing is written until you confirm.

## My Fuel Manager

Look for the export or backup option in My Fuel Manager's menu. The export saves a separate CSV
file for each category, and the first line of each file names it – `My Fuel Manager - Fuel`,
`My Fuel Manager - Costs` and so on. Each file is imported on its own.

## Drivvo

Export your data from Drivvo as CSV. Drivvo can also produce a PDF report, but a report is a
printout, not data, and Tankbook cannot read it. The CSV comes as one file with three sections –
refuelling, expenses and service – and Tankbook reads all three in one pass.

A few things work differently from My Fuel Manager:

- One file holds one car. If the import creates a new car, it is named from the file, and you can
  rename it in the same step or later in the Garage.
- Drivvo's file has no currency column, so the import asks once which currency the amounts are in,
  with the car's own currency offered first.
- Station names become stations you can pick later. The second and third fuel, the EV charging
  columns, the driver, the payment method and the discount are not imported; the preview lists the
  columns it leaves out.

## Getting the file onto your iPhone

AirDrop, the Files app or a copy emailed to yourself all work. Tankbook reads the file through the
system file picker, and you can also share a CSV from another app straight into the import.

## What Tankbook does with the file

- The file is parsed on our server. One parser serves every Tankbook user, so a mapping fix reaches
  you without an app update. This is the only step that needs a connection.
- The parse returns candidate rows. You see a preview – how many fill-ups, the date range, the last
  odometer – and review and edit the rows that need a look. Only the rows you confirm are written.
- No amount, station or note from the file is ever logged. The file and its parse result are kept
  for 30 days and then deleted. You do not need an account.

## What can go wrong

- "This doesn't look like a … export." The file did not match the format of the app you chose.
  Check that you picked the right app and the CSV export, not a report or a backup of another kind.
- A row that needs a look. Rows the parser cannot place are marked, not dropped. You can fix the
  field, leave the row out, or import it as it is.
- Ambiguous dates. Dates that read either way are checked once, before anything is committed; the
  app does not guess silently.

## Other apps

Today Tankbook reads My Fuel Manager and Drivvo; other apps may follow. A file from an app it does
not know is turned away rather than mis-read. If your app is missing, the import screen offers to
take the file so the format can be added.
