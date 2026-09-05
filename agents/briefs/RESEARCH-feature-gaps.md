# What is missing from Tankbook, who would pay for it, and where

You are a product analyst. **You write ONE file and change nothing else.**

## Write this file FIRST, within your first three tool calls, and rewrite it after every section

    diagnostics/RESEARCH-feature-gaps-qwen.md

Start it as a skeleton with the four headings below and fill them in as you go. **An agent that
reasons for an hour and saves nothing has produced nothing.** Run no `git` command, no build, no
tests. Touch no other file. **Never `pgrep -f`** - your brief is your command line, so it matches you.

## What this app is, before you judge what it lacks

Read these first. They are the product, not background:

- `docs/VISION.md` - scope, what is deliberately cut, and the monetization principles. **Read the
  cuts before proposing a feature: several obvious ones were rejected on purpose, and re-proposing
  them without engaging the reason is the failure mode of this brief.**
- `docs/COMPETITORS.md` - the incumbents and what they do and lack. **The authority for competitor
  claims.** Where you go beyond it, say you are doing so and how confident you are.
- `docs/STORE.md` section 1 - dated App Store and Google Play review research, English and Russian,
  on what users of competing apps are angry about. This is the closest thing to real user voice in
  the repo. Section 2 covers findability and what each audience searches for.
- `docs/JOURNEYS.md` - the journeys that exist (J1-J17), including the ones marked [v1.1] and [v2].
- `docs/TASKS.md` - the launch triage and the backlog. **Something already in the backlog is not
  "missing"** - it is scheduled, and saying so is more useful than listing it as a gap.
- `docs/AGENT.md` - the v2 Car Agent, which is what the Pro tier is meant to pay for.
- `docs/SCHEMA.md` - what the data model already carries. A feature the schema already supports is
  cheap; one that needs new entities is not, and your answer should say which.

The build itself: `ios/App/Sources/` (the screens that exist), `ios/Sources/TankbookCore/` (the
engines). `ls` these before claiming something is absent.

## Answer these four, in this order

**1. What is missing, and why does it matter?**
Not a wish list. For each gap: what a user cannot do today, the evidence it matters (a review
pattern in `STORE.md` section 1, a journey that dead-ends, a competitor whose users cite it), and
whether the schema already supports it. **Rank by user pain, not by ease.** Ten items maximum; five
sharp ones beat ten vague ones. Mark anything already in `TASKS.md` as scheduled, not missing.

**2. Which region's problem does each one solve?**
This product has two distinct audiences and they are NOT the same market: an English-speaking one
whose complaints are about losing history, exports and subscriptions, and a Russian-speaking one
whose complaints are about apps that stop working, subscriptions that cannot be paid, and numbers
that cannot be checked (`STORE.md` section 1 has both, dated). Some gaps are one-market only -
fiscal receipts and ОСАГО in Russia, VIN decoding and inspection reminders in the EU, gallons and
trip logging in the US. Say which, and say when a gap is genuinely universal.

**3. Why would a user PAY for it?**
v1 is free with no in-app purchase; v2's Pro tier is the Car Agent (`docs/AGENT.md`). For each
proposed feature: is it a free-tier obligation, a Pro feature, or neither? A feature people want but
will not pay for is still worth building - say so plainly rather than inventing a monetization
story. Where you claim willingness to pay, name what the competitor charges for the same thing.

**4. UX gaps in what already ships, and how to resolve them.**
Read the screens, not just the docs. Where does the built app make something harder than it needs to
be? Be concrete: name the screen, the file, and what you would change. Do not redesign the app;
find the seams. Reminders are being worked on right now (RV.74-RV.79) - **skip them, they are
covered.**

## Rules

- **Ground every claim.** A file, a documented review pattern, or a named competitor. "Users expect
  X" with nothing behind it is the answer this brief exists to prevent.
- **Engage the cuts.** `VISION.md` records what was rejected and why. If you propose one of those,
  argue against the recorded reason - do not pretend it was never decided.
- **No em-dashes.** En-dashes only. House rule, and it is checked.
- Honesty over completeness: "I could not tell from the repo" is a useful sentence.
- Aim for 1200-1800 words.

## Report back

The file path, your top three gaps in one sentence each, and the single thing you would build first
if you had one engineer for one month.
