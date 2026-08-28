+++
title = "Privacy policy"
description = "What Tankbook collects, what it never logs, and the one deliberate exception – written from how the app actually behaves, not from a template."
+++

Tankbook is a car cost log that works with your data on your phone. This policy is written from
how the app actually behaves – every statement below is true of Tankbook today.

## The short version

- Tankbook is fully usable **with no account**. The database on your phone is the authoritative copy of your data.
- **Sign-in is optional.** It enables sync across your devices, restore on a new phone, and the cloud extraction gateway for scans the on-device reader cannot crack.
- **We never log your domain values** – amounts, stations, notes, coordinates, payloads, tokens, images – at any level, in any build.
- Images sent to the extraction gateway are **processed transiently and never retained**.
- **One deliberate exception:** third-party import parsing. An uploaded file and its parse result **are stored for 30 days**, then purged. No sign-in is required.
- Deleting your account is a **tombstone**: your other devices learn on their next sync, and **the log on your phone stays on your phone**.
- Export is **always free**, in CSV or JSON. There are **no ads** and **no server-side analytics**.
- **This website sets no cookies and runs no third-party analytics.**

## No account needed

Tankbook is local-first. Capture, manual entry, the consumption maths, reminders, multi-currency
entries and export all work with no account at all, and no screen waits for a server. The log is a
database on your phone, and that database – not our server – is the authoritative copy of your data.
If our servers disappeared tomorrow, the app would keep working.

## If you sign in

Sign-in (Sign in with Apple or Google) is optional and turns on three things: sync across your own
devices, restore on a new phone, and the cloud extraction gateway used as a fallback when the
on-device reader cannot help with a scan.

When you sign in, we store:

- your account identifier,
- your email address, used as a neutral recovery identity,
- the synced record stream – your entries and the attachments they reference.

The connection is always TLS-encrypted in transit, and what we store is encrypted at rest.
We do **not** use end-to-end encryption: in v1 our server can technically read the synced data it
stores. We say that plainly rather than implying more. What bounds our ability to care about your
data is not cryptography but minimal collection – no analytics on content, no profiling, nothing
computed over your entries except serving them back to your own devices.

## What we never log

Our logs never contain your domain values. Amounts, stations, notes, coordinates, payloads, tokens
and images never appear in a log line – not in development, not in production, at any level, in any
build. What logs do carry is ids, counts, codes, durations and field names: enough to debug a
failure, nothing that describes your driving or your spending.

## Scanning

Reading a receipt, a pump display or a charging screenshot happens on your phone first – the
on-device reader is the primary path, and it works offline. When a scan is too hard for it, the app
can ask our cloud extraction gateway. The image travels over TLS, is downscaled and compressed on
your device before upload, is processed transiently on our server, and is **never retained** – never
written to disk or to storage of any kind. The gateway returns field values with confidence scores;
it makes no judgements about your data.

## The one exception: third-party import parsing

Importing a file from another app – for example a My Fuel Manager CSV – is the one place a file
leaves your device without an account. The file is uploaded to our server, which parses it and
returns candidate rows **for you to review**; the server commits nothing, and the entries land in
your log only after you review and confirm them.

Unlike everything else we receive, the uploaded file and its parse result **are stored, deliberately,
for 30 days** – the same window as the app's tombstones and undo – so an interrupted review can be
resumed and a bad parse can be re-examined. After 30 days they are purged. No sign-in is required,
and nothing about the content is logged: only the shape – format name, row counts, error counts.

## Deleting your account

You delete your account from the app. Deletion is a **tombstone**: the account is marked deleted,
your other devices learn about it on their next sync (the server answers them with HTTP 410 and
they stop syncing), and after a grace period – 30 days by default, the same window as the app's
undo – our copy of your records and attachments is purged.

**The log on your phone is not touched.** Deleting the account removes our server's copy; it does
not delete the data on your device. If you also want the local copy gone, delete the app – and
export first (Settings → export, always free) if you want to keep it.

## Export

Export is always free. CSV or JSON, every field, as many times as you like. Your own data has no
paywall – and never will.

## No ads, no analytics

The app carries no advertising and no analytics SDKs. We run no server-side analytics and no
content analytics: nothing computes over your entries except serving them back to you.

## This website

This website sets no cookies and runs no third-party analytics. If that ever changes, this page
will change with it.

## Contact

Questions about this policy: [to@belyaev.live](mailto:to@belyaev.live).
