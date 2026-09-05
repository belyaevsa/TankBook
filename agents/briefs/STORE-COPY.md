# Write the final App Store texts, English and Russian

You are a copywriter. You write **one file**. You change no code.

## Where you may write

Only this path, inside the repository you are started in:

    docs/STORE-COPY.md

Nothing else. **Run no `git` command.** Do not run builds or tests. Do not touch `docs/STORE.md`,
`docs/SITE.md`, `agents/briefs/` or anything under `ios/`, `backend/` or `design/`.

**Never `pgrep -f`** - your brief is your command line, so it matches you.

## What to write

The finished, submittable App Store copy for an iOS app called **Tankbook**, in **English** and
**Russian**, as two complete sets:

| Field | Limit |
|---|---|
| App name | 30 characters |
| Subtitle | 30 characters |
| Promotional text | 170 characters |
| Description | 4000 characters, plain text, no markdown |
| What's New (first release) | 4000, but keep it to 3-5 lines |
| Keyword field | 100 characters, comma-separated, no spaces |

Give **two candidates for the name and subtitle** in each language and mark which you recommend
and why in one sentence. Everything else, one final version.

## Read first - the research is done, do not redo it

- `docs/STORE.md` - **the authority for this task.** Section "The copy rule" says what may never
  be claimed; section 1 is dated competitor-review research telling you exactly what each audience
  is angry about; sections 3 and 4 are a first DRAFT of the copy. **Your job is to write the final
  version, not to copy that draft** - it was written to capture the argument, not to sell.
- `docs/SITE.md` - the never-say / say-instead table. It binds you.
- `docs/VISION.md` §1-2 - what the product is and what is genuinely unowned.

## The rules that will get your copy rejected if you break them

1. **Never promise what the product cannot do.** No "zero typing", no "just snap and you're done",
   no "AI reads any receipt perfectly", no "automatic" as the headline verb. Measured: receipts
   resolve 85% of fields but only 69% of receipts come out entirely right, so about a third still
   need a correction. Say so, in both languages, in the description.
2. **Never name the fiscal QR** as a feature. Never mention pump-display scanning - it ships off.
3. **No em-dashes anywhere.** En-dashes only.
4. **The Russian is not a translation of the English, and the English is not a translation of the
   Russian.** They lead on different things because the audiences complain about different things
   (`STORE.md` section 1). Write each one natively. A Russian sentence that reads like a translated
   English sentence is a failure of this task.
5. **No emoji, no ALL-CAPS shouting, no exclamation marks.**

## What each audience is angry about - lead with it

**English.** The strongest 1-star trigger in 2025-2026 is losing years of history to a phone
change, a forced login or a sync that overwrites instead of merging, plus exports that leave the
receipt photos behind and subscriptions that jump in price. Notably, OCR accuracy is NOT a common
complaint - so do not sell reading quality. Sell: no account ever, works offline, export is free
and complete INCLUDING the receipt images, no subscription, no ads.

**Russian.** The complaints are different: the app stops being usable through no fault of the
user. Servers go off and the local log will not even open; a paid subscription does not activate
or cannot be paid for at all from Russia; the free tier "ничего не считает"; and - the sharpest
one - a driver recomputes the consumption by hand, gets a different number than the app, and
deletes it. Sell: работает офлайн и открывается без серверов, подписки нет вообще, арифметика
показана и её можно проверить, фото чека хранится в приложении, ТО и напоминания, импорт из
других приложений.

## What is true, and may be claimed

No account required, ever. Every screen works offline. No subscription and no paid tier in this
version. No ads. Export is free and the archive contains the receipt image files, not only the
rows. Litres x price per litre = total is checked on screen and a disagreement is stated plainly.
Multi-currency with the rate snapshotted on the entry's own date. Several cars, free. Petrol,
diesel, hybrid and electric in one history. Service, repairs, parts, tyres, insurance and taxes
with photos. Reminders by date and mileage. Back-dated entries. Importers for Fuelio, Drivvo,
Fuelly/aCar, Spritmonitor, CarScope and My Fuel Manager. English and Russian throughout.

## Keywords

Propose the 100-character field for each language. Do not repeat words that already appear in that
language's name or subtitle - Apple indexes those already. Do not include `ai`, `нейросеть` or
`автоматически`. Explain each language's field in two sentences.

## Format of your file

`docs/STORE-COPY.md`, with an `## English` and an `## Russian` section, each field under its own
heading, the copy in a fenced block so it can be pasted into App Store Connect verbatim, and the
character count in brackets after each heading. End with a short "What I would not say" section
naming any phrase you were tempted by and rejected, and why.

## Report back

The file path, your recommended name and subtitle in each language, and the character counts.
