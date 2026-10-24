# Tankbook 1.2.1 – changes since 1.2

Range: `v1.2..v1.2.1`. Between the tags, everything outside the app (the corpus batches, the
move of object storage to Azure, the site) changed nothing a user runs; the app changes are the
three rows below.

## App Store – What's New (EN)

• Long trips are no longer flagged. Fills a few hours apart across midnight – a motorway leg, a night shift – count as real, and the check now learns how you drive after your first dozen fills.
• Entries the old check wrongly set aside are re-checked when the app opens and count in your consumption again.
• Sharing a receipt now sends what it says with the photo: date, station, fuel, litres, price, amount, the extras bought on the same receipt and the total.
• Clearer wording when a reading looks too far for the time between fills.

## App Store – What's New (RU)

• Дальние поездки больше не помечаются как ошибка. Заправки с разницей в несколько часов через полночь – трасса, ночная смена – считаются настоящими, а проверка после первого десятка заправок подстраивается под то, как вы ездите.
• Записи, которые старая проверка ошибочно исключила, перепроверяются при запуске и снова учитываются в расходе.
• Поделиться чеком теперь можно вместе с данными: дата, заправка, топливо, литры, цена, сумма, покупки из того же чека и итог.
• Понятнее подсказка, когда пробег кажется слишком большим для времени между заправками.

## App Store – Promotional text

Unchanged from 1.2 (`docs/RELEASE-NOTES-1.2.md`): it describes the product, not the release, and
can be edited in App Store Connect without a build.

## Detail, with task ids

### Fixed

- CHECK 2 (pace) divided the distance by the fractional days between two fills on different
  dates, so the 1 500 km/day limit became 62.5 km/h across midnight and real fills were flagged
  and excluded from consumption. A pair on different dates now counts at least one day; the
  limit is learned from the car's own fills after 12 of them (4 × the 75th percentile, 800 to
  1 500 km/day), and a limit the user set applies as set. Every car's stored flags are re-derived
  on each foreground pass, which clears the flags older builds wrote. (RV.341)
- A pace flag says "Daily pace over the limit – check it." instead of "Odometer breaks the
  timeline"; a valid-date window inside one day names the day; a Russian date ending a sentence
  keeps one full stop ("21 окт.", not "21 окт.."). (RV.341)

### New

- A shared receipt photo carries a caption from the stored entries: date, station, fuel kind,
  volume, price per unit, amount, each expense in the same purchase group, the expenses' sum and
  the receipt total, in the receipt's currency; sums are per currency. (RV.339)

### Closed

- Shares reach out-of-process destinations: the owner's receipt share to Telegram arrived on a
  device. (RV.181)

## Owner check

- Share a mixed receipt to Telegram and Messages: the photo and the caption both arrive. A
  destination that keeps only the text is the failure to look for (RV.339).
- Open the app on the car from the 21-23 Oct report: the four fills show no badge and count in
  October's consumption (RV.341).
- A car with fewer than 12 fills is no longer pace-checked at all; a misread order (a reading
  lower than the previous one) is still flagged from the first fill.
