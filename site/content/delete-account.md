+++
title = "How to delete your account"
description = "What account deletion does in Tankbook: a tombstone on the server, your other devices informed, and the log on your phone untouched."
+++

You do not need an account to use Tankbook, and you can delete one whenever you like. Here is
exactly what happens, with nothing softened.

## How to delete

In the app, sign in and open account settings, then choose **Delete account**. The app asks you to
confirm – destructive confirmations are the only place the app shows you red.

If you cannot reach the app – a lost phone, a lost password – write to
[to@belyaev.live](mailto:to@belyaev.live) from the email your account uses, and we will delete it.

## What happens next

Deletion is a **tombstone**, in two stages:

1. **Immediately.** The account is marked deleted. Your other devices learn about it on their next
   sync: the server answers them with HTTP 410, they stop syncing, and each shows what happened and
   how to go on. Nothing arrives at them or leaves them silently.
2. **After the grace period.** Our copy of your records and attachments is purged from the server.
   The grace period is 30 days by default – the same window as the app's undo – and it is never
   shorter than that undo window, so a deletion stays fully recoverable while the app's own undo
   would still work.

## What stays yours

**The log on your phone is not touched.** Deleting the account removes our server's copy of your
data; the local database on each device keeps everything it had, and the app keeps working with it
– capture, consumption maths, reminders, export. Deleting the app itself is what removes the local
copy, so if you want out completely: export first (always free, CSV or JSON), then delete the
account, then delete the app.

## Deleting one device instead

To take one device out of sync without touching the account, revoke that device in account
settings: it stops syncing (same HTTP 410) and its local data stays on it. The other devices are
unaffected.
