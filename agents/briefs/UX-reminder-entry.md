# Where does "add a reminder" belong? A UX review, grounded in this app

You are a mobile UX reviewer. **You write ONE file and change nothing else.**

## Write this file FIRST, within your first three tool calls, and rewrite it after every
## sub-answer

    diagnostics/RESEARCH-reminder-entry-<yourmodel>.md

where `<yourmodel>` is `pro` if you are deepseek-v4-pro, `qwen` if you are qwen3.8-max. Start it as a
skeleton with your headings and fill it in as you go. **An agent that reasons for an hour and saves
nothing at the end has produced nothing.** Do not run `git`, do not build, do not run tests, do not
touch any other file. **Never `pgrep -f`** - your brief is your command line, so it matches you.

## The question

A driver wants to be reminded of something - insurance in March, oil in 15 000 km, the winter tyre
swap. **Where in this app should that begin?** Answer for the app as it is, not for an ideal app.

Today there is exactly ONE trigger: a dashed "New reminder" card at the BOTTOM of the per-car
Reminders list (`ios/App/Sources/Reminders/RemindersView.swift`, `newReminderCard`). Reaching it is
Garage -> the car -> Reminders -> scroll. The Home banner that would shortcut it only renders while
something is already in the attention window (`ios/Sources/TankbookCore/Service/ReminderBanner.swift`
filters to `.attention`), so **a user with no reminders yet has no path from Home at all** - they
must already know the screen exists to find it.

## Read these - they are the app, not background

- `docs/JOURNEYS.md` - the user journeys. **J7c is the reminder lifecycle** and it covers complete /
  reschedule / delete. Notice what it does NOT cover: how a reminder is CREATED in the first place.
- `docs/SCREENMAP.md` - the navigation graph, the per-screen index, and the section "Reminders across
  cars [v1.1]" with the planned screens.
- `docs/TASKS.md` - rows **RV.74 to RV.79**: the registered gaps, with their causes at file:line.
- `docs/DESIGN.md` - the layout and IA rules, including what the tab bar is allowed to hold.
- `CLAUDE.md` - the hard rules. **13** (the app suggests, the user decides) and **15** (two doors:
  type it or scan it) both bear on this.
- The MOCKS, which are plain HTML you can read as source:
  `design/screens/RemindersAll.dc.html` (the merged all-cars list, with the dashed New reminder card),
  `design/screens/ReminderForm.dc.html` (the creation form: car is the first field),
  `design/screens/RemindersEntry.dc.html` (Home with a permanent "Reminders - 2 due" row),
  `design/screens/GarageReminderCounts.dc.html` (per-car attention counts),
  `design/screens/ServiceReminderOffer.dc.html` (after saving a service record: "Remind you next
  time?"), `design/screens/Reminders.dc.html` (today's per-car list), `design/screens/HomeA.dc.html`
  and `design/screens/CarSwitcher.dc.html` (the surfaces a trigger might live on).
- The code, for what actually exists: `ios/App/Sources/Reminders/`, `ios/App/Sources/Home/HomeBanners.swift`,
  `ios/App/Sources/VehicleDetail/VehicleDetailView.swift`, `ios/App/Sources/ServiceEntry/`.

## Answer exactly these three, in this order

**1. Where should the trigger live, and where should it NOT?**
Name the surfaces and rank them. For each: what a user is doing when they are there, and whether
creating a reminder is a plausible next move from that state. Say plainly which candidates you
REJECT and why - a review that likes every option is useless. Consider at least: the merged
Reminders list, the per-car list, the Vehicle detail row, the Home "Reminders" row, the Garage car
row, the tab bar's centre button and its "Type it" menu, the empty state, and the moment just after
a service or fill-up is saved. The tab bar has five slots and they are decided (`DESIGN.md`); saying
"put it in the tab bar" needs an argument for what it displaces.

**2. Write the missing journey.** `JOURNEYS.md` has J7c for the reminder LIFECYCLE but nothing for
its BIRTH. Draft that journey in the file's own house style - trigger, a table of Action / What
happens / Notes, the warning line, and a success metric that could actually be measured. Cover the
three real openings: the driver who decides to add one, the driver who just logged the work and
should be offered the next one, and the driver who has none at all and must discover the feature.

**3. What makes this feel native on iOS, specifically?**
Not general advice - this app. Where does a "+" belong in a pushed screen's header versus a card at
the end of a list? Does an empty state's primary action being a dashed outline read as a
placeholder? Is a per-car reminder created from a merged list a confusing act, and if so what makes
it unconfusing? Cite the mock or the file you are talking about.

## Rules

- **Ground every claim in a file you read.** "Users expect X" with no reference is the kind of
  answer this brief exists to avoid. If you are inferring from convention, say so and name the
  convention (an iOS platform pattern, a named app).
- **Do not redesign the reminder feature.** The merged list, the counts and the offer sheet are
  decided (RV.75-RV.79). You are placing the create action inside that world.
- **No em-dashes.** En-dashes only. This is a house rule and it is checked.
- **Disagreeing with the current plan is welcome** if you argue it from the files. Say so plainly
  rather than hedging.
- Aim for 700-1200 words. Fewer, sharper points beat a survey.

## Report back

The file path, your ranked answer to (1) in one sentence, and the one thing you would change about
the mocks.
