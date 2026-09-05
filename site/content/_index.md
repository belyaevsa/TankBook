+++
title = "Tankbook – fuel & cost log for iPhone"
description = "A car cost log with no account, offline, export always free. Snap the receipt or type it in – both doors take seconds, and the arithmetic is checked where you can see it."

hero_eyebrow = "Fuel & cost log for iPhone"
hero_title_1 = "Log the fill-up your way:"
hero_title_2 = "snap the receipt,"
hero_title_3 = "or type it in."
hero_sub = "Tankbook is a car cost log. Fuel, charging, service and the rest – kept on your phone, added in seconds through either door, checked by arithmetic you can watch."
hero_facts = ["Free", "No account needed", "Export always free"]
hero_cta_primary = "Join the TestFlight ring"
hero_cta_secondary = "See what's shipped"
hero_cta_secondary_url = "/roadmap/"
hero_note = "In testing now – no badge, no fake ratings. The mail reaches a human."
hero_shot = "P1.4-home.png"
hero_shot_alt = '''Tankbook's Log screen: a Volvo V60 at 123 600 km, average consumption 5.3 L/100km set large, September spend 147 €, and a stream of real entries'''
hero_shot_caption = '''The real app, not a render – note "Type it" sits beside the camera.'''

doors_eyebrow = "The two doors"
doors_title = "Snap it or type it – both take seconds."
doors_note = "Neither door is a fallback – a poor photo means correcting two fields, never starting over."

check_eyebrow = "Checks as you type"
check_title = "The maths runs where you can see it."
check_text = '''Litres × price has to equal the total. When it does, the line locks with a tick – trust you can look at, not magic you're asked to believe.'''
check_lhs_value = "42.30"
check_lhs_unit = "L"
check_rhs_value = "1.679"
check_rhs_unit = "€/L"
check_total = "71.02"
check_total_unit = "€"
check_warn_before = "And when it doesn't add up, the odd field gets an"
check_warn_styled = "amber underline"
check_warn_after = "and a tap-to-fix – never a silent guess."
check_shot = "P2.3-confirm.png"
check_shot_alt = "The fill-up card mid-entry: total 71.02, litres 42.30, price 1.679, with the cross-check line reading 'checks as you type'"
check_shot_crop = -230
check_shot_caption = "Live in the entry card, on every fill-up."

data_eyebrow = "Your data, yours"
data_title = "On your phone. Not on a login wall."
data_link = "The privacy policy is generated from how the app actually behaves – read it →"
data_link_url = "/privacy/"

power_eyebrow = "One history"
power_title = "Every powertrain, every currency."
power_text = "Litres and kilowatt-hours live in one stream, each with its own consumption maths – fuel burns taillight red, electricity glows headlight cyan, the same code everywhere in the app."
power_border_before = "Fill up across a border and the entry keeps"
power_border_strong_1 = "both amounts"
power_border_mid = "– what you paid and what it was worth at home, at the rate"
power_border_strong_2 = "on the day of the fill-up"
power_border_after = ", never today's. Rate snapshots are immutable: they never rewrite your history."
power_shot = "P2.5-confirm-foreign.png"
power_shot_alt = "A fill-up in Poland: currency chips with PLN selected, total 289.50 zloty, 47.30 litres at 6.120 per litre, the cross-check locked with its tick"
power_shot_crop = -330
power_shot_caption = "289.50 zł, kept with its euro value at the Aug 21 rate – the day it happened."

road_eyebrow = "Next"
road_title = "Pump-display capture – point the camera at the pump itself, before the receipt prints."
road_text = "Also on the bench: importers from the app you're leaving, and CarPlay. What's shipped, what's next and what we deliberately cut – all on one honest page."
road_cta = "See the roadmap →"
road_cta_url = "/roadmap/"

faq_eyebrow = "FAQ"
faq_title = "Questions, answered straight."

[[doors]]
title = "Snap it"
icon = "camera"
text = "Point the camera at the receipt. The scan fills in what it can read – you check the numbers, correct the rest, and it remembers your corrections. A head start, not an answer."
shot = "RV.5-capture-review.png"
shot_alt = "After a capture: the photographed receipt filling the screen under \"Check the photo - can you read the total on it?\", with Use this, Re-take and Type it side by side"

[[doors]]
title = "Type it"
icon = "keyboard"
text = "Date, odometer, litres, total – a form built for thumbs, and price per litre fills in from total ÷ litres. Typing is a front door of its own, never the failure branch."
shot = "P1.3-confirm-manual.png"
shot_alt = "The manual fill-up form: date, odometer with its live sanity check, station suggestion, fuel choice and the three-number card"

[[data_cards]]
icon = "user-x"
title = "No account, ever needed"
text = "Everything works signed out. Sign-in exists only for sync and restore – the app never asks first."

[[data_cards]]
icon = "cloud-off"
title = "Offline is normal"
text = "The log is a database on your phone. No screen waits for a server, at a pump or in a garage with no bars."

[[data_cards]]
icon = "download"
title = "Export always free"
text = "CSV or JSON, every field, whenever you like. Your own data has no paywall – and never will."

[[data_cards]]
icon = "lock"
title = "Nothing of yours is logged"
text = "Amounts, stations, notes, coordinates: never in our logs – at any level, in any build."

[[power_chips]]
label = "Petrol"
fuel = true
electric = false

[[power_chips]]
label = "Diesel"
fuel = true
electric = false

[[power_chips]]
label = "Hybrid"
fuel = true
electric = true

[[power_chips]]
label = "EV"
fuel = false
electric = true

[[faq]]
q = "Do I need an account?"
a = "No, and the app never asks first. Everything works signed out; signing in exists only to sync and restore across devices."

[[faq]]
q = "Does it work offline?"
a = "Yes. The log lives on your phone and no screen is gated on a server. The network is only for the optional things: a cloud assist on a hard scan, sync, restore."

[[faq]]
q = "What does a scan actually do?"
a = '''It gives you a head start, not an answer. The scan fills in what it can read and shows what it's unsure about; you correct the rest, and it remembers. A poor photo means fixing two fields, never starting over.'''

[[faq]]
q = "What does it cost?"
a = "Nothing right now – Tankbook is free while we finish. Three things stay true after launch: multiple cars in the free tier, export always free, and limits never change retroactively."

[[faq]]
q = "I have years of data in another app."
a = "Import works review-first: your file is parsed into candidate rows, you review and edit every one, and only you commit them. My Fuel Manager CSV is supported today; more formats are on the roadmap."

[[faq]]
q = "I drive a petrol car and an EV."
a = "One history for both. Fill-ups in litres, charges in kilowatt-hours, and consumption maths that knows the difference – colour-coded apart at a glance."
+++
