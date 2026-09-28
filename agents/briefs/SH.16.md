# SH.16 - Rewrite the 1.1 release notes and App Store copy in the owner's writing style

You are an editor. You rewrite existing texts for the next App Store release of **Tankbook** (an
iOS car cost log) in the product owner's writing style, in **English and Russian**. The facts do
not change - only how they are written.

## The style you apply

Read both files in full before writing a word:

    /Users/sbelyaev/repos/edu-platform/docs/brand/lesson-guides/writing-style.md
    /Users/sbelyaev/repos/edu-platform/docs/brand/lesson-guides/voice-samples.md

The guide is written in Russian and is the owner's single style source; **apply its rules to both
languages** (for English, apply the same rules in their English form: the same bans, the same
rhythm, the same attitude to numbers and claims). The rules that bite hardest on this kind of text:

- dashes: en-dash (–) only, never an em-dash (—), spaced on both sides except in ranges;
- no "not X, but Y" / "it's not X – it's Y" constructions;
- no bold lead-in sentence at the start of every paragraph or bullet (the AI pattern the guide bans);
- no paragraphs or bullets cloned from one template;
- no absolute claims; concrete over abstract; plain words over marketing;
- the numbers rules (section 6) where a number appears.

Ignore the guide's parts that are about the school, lessons or courses (the school name, lesson
structure); they do not apply to an app listing.

## What you rewrite (and the only files you may write)

1. `docs/RELEASE-NOTES-1.1.md` - the owner-facing list of user-visible changes since `v1.0`. Keep
   its structure (New / Better / Fixed, the task ids in parentheses, the owner-check list at the end);
   rewrite each line in the style.
2. `docs/STORE-COPY.md` - **only the section `## Update 1.1 (2026-09-28)`**: What's New, Description,
   Promotional text and Keywords, English and Russian. Leave every other section of the file
   byte-identical. Keep the section's field headings and put the **character count** after each
   field, counted by a script (python on a temp file you delete afterwards) - never estimated. The
   limits: What's New 4000 (keep it to 4-6 short lines), Description 4000, Promotional text 170,
   Keywords 100 (comma-separated, no spaces; change a keyword only with a reason you state).
3. `site/content/releases.md` and `site/content/releases.ru.md` - the site's releases page. Keep the
   Hugo front matter (`+++ ... +++`) and the headings (`## 1.1 – in preparation`,
   `## 1.0 – 22 September 2026` and the Russian ones, `### New / Better / Fixed` and theirs) and the
   two links (`/roadmap/`, `/ru/roadmap/`); rewrite the prose and the bullets in the style.

Nothing else. **Git is read-only for you** (`git log`, `git show`, `git diff`); never `commit`,
`add`, `checkout`, `stash`, `reset`, `restore`. Other sessions have uncommitted work in this
checkout - touch no file you were not given. **Never `pgrep -f`** - your brief is your command line.
Run no builds or tests.

## The facts, and the claims you may not make

Every fact stays as it is in the current text - you may merge, reorder or drop a line only if it
repeats another; never add a feature. Read `docs/STORE.md` (the copy rule, what each audience is
angry about) and `docs/SITE.md` -> "The copy rule". The binding ones:

- capture is a **head start, not an answer**: a scan or a pump photo pre-fills numbers the user
  checks; never "automatic", "zero typing", "reads any receipt", and never an accuracy number;
- typing is an **equal** way in, never the fallback;
- no account needed, works offline, export free and complete - true, keep them;
- 1.1 is **not released yet**: the site page calls it "in preparation"; the App Store What's New is
  written for the day it ships.

Russian is written for a Russian-speaking driver, in the guide's voice - not translated from the
English line by line (docs/STORE.md 4b: two audiences, two texts).

## Report

End with: the files you changed; each App Store field's character count, before and after; the
style rules you applied that changed the most lines; anything you dropped as a repeat.
