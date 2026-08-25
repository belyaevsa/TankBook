import Foundation
import TankbookCore

/// The composed display strings of a Reminder row (design/screens/
/// Reminders.dc.html). Every phrase here is a full localised catalogue phrase
/// per language - never concatenation (the RU pass on P1.4 proved composed
/// strings need their own phrase): "Due Sep 4 · in 12 days" is one key with
/// two placeholders, the count-bearing sub-phrases carry real Russian plural
/// rules, and the due moment resolves from whichever of date/odometer comes
/// first (docs/SCHEMA.md -> Reminder).
enum ReminderRowFormat {

    /// The due line: "Due Sep 4 · in 12 days", "In 8 400 km or Feb 2027",
    /// "Overdue by 3 days". Empty when the reminder has neither due field
    /// (which cannot happen for a saved reminder - ReminderDraft refuses it).
    static func dueLine(for reminder: Reminder,
                        currentOdometer: Int?,
                        now: Date = Date()) -> String {
        switch ReminderLifecycle.due(reminder) {
        case .date(let date):
            return dateLine(date: date, now: now)
        case .odometer(let odometer):
            let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer)
            return odometerLine(odometer: odometer, km: km, now: now)
        case .both(let date, let odometer):
            return bothLine(date: date, odometer: odometer,
                            km: ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer),
                            now: now)
        case nil:
            return ""
        }
    }

    /// The trailing chip on a "Needs attention" row: "12 days", "420 km".
    /// The count is the whichever-comes-first metric that put the row in the
    /// attention group.
    static func chip(for reminder: Reminder,
                     currentOdometer: Int?,
                     now: Date = Date()) -> String? {
        switch ReminderLifecycle.due(reminder) {
        case .date(let date):
            let days = ReminderLifecycle.daysRemaining(until: date, from: now)
            return String(localized: "\(abs(days)) days")
        case .odometer(let odometer):
            guard let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer) else {
                return OdometerFormat.grouped(odometer)
            }
            return String(format: L10n.localize("%lld km"), abs(km))
        case .both(let date, let odometer):
            let days = ReminderLifecycle.daysRemaining(until: date, from: now)
            let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer)
            // The date half is the attention driver when it is within its
            // window (or already past) - show days then; the km half drives
            // when the date is far out. The two units cannot be compared
            // directly, so each half answers in its own metric.
            if let km, days > ReminderLifecycle.attentionWindowDays {
                return String(format: L10n.localize("%lld km"), abs(km))
            }
            return String(localized: "\(abs(days)) days")
        case nil:
            return nil
        }
    }

    /// The recurrence caption: "every 15 000 km / 12 mo", or nil when the
    /// reminder does not repeat.
    static func recurrenceLine(for reminder: Reminder) -> String? {
        guard let recurrence = reminder.recurrence else { return nil }
        let km = recurrence.everyKm
            .map { String(format: L10n.localize("every %1$@ km"), OdometerFormat.grouped($0)) }
        let months = recurrence.everyMonths
            .map { String(format: L10n.localize("every %1$lld mo"), $0) }
        switch (km, months) {
        case (let km?, let months?): return "\(km) / \(months)"
        case (let km?, nil): return km
        case (nil, let months?): return months
        case (nil, nil): return nil
        }
    }

    /// The full row caption: the due line plus the recurrence caption, joined
    /// with the separator the artboard draws ("In 8 400 km or Feb 2027 ·
    /// every 15 000 km / 12 mo").
    static func caption(for reminder: Reminder,
                        currentOdometer: Int?,
                        now: Date = Date()) -> String {
        var parts = [dueLine(for: reminder, currentOdometer: currentOdometer, now: now)]
        if let recurrence = recurrenceLine(for: reminder) {
            parts.append(recurrence)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Pieces

    /// "Sep 4" in the current year, "Feb 2027" outside it - the artboard's own
    /// distinction (this year's due date gets a day, next year's gets a year).
    static func dateString(_ date: Date, now: Date = Date()) -> String {
        let isThisYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        if isThisYear {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    /// The count phrase with the artboard's unit switch: days while there are
    /// fewer than ~30 left, months beyond that ("in 12 days", "in 7 months").
    static func daysPhrase(_ days: Int) -> String {
        guard days >= 30 else {
            return String(localized: "in \(days) days")
        }
        let months = Int((Double(days) / 30.0).rounded())
        return String(localized: "in \(months) months")
    }

    private static func dateLine(date: Date, now: Date) -> String {
        let days = ReminderLifecycle.daysRemaining(until: date, from: now)
        if days < 0 {
            return String(format: L10n.localize("Overdue by %1$@"),
                          String(localized: "\(-days) days"))
        }
        return String(format: L10n.localize("Due %1$@ · %2$@"),
                      dateString(date, now: now), daysPhrase(days))
    }

    private static func odometerLine(odometer: Int, km: Int?, now: Date) -> String {
        guard let km else {
            return String(format: L10n.localize("Due at %1$@ km"),
                          OdometerFormat.grouped(odometer))
        }
        if km < 0 {
            return String(format: L10n.localize("Overdue by %1$@ km"),
                          OdometerFormat.grouped(-km))
        }
        return String(format: L10n.localize("In %1$@ km"), OdometerFormat.grouped(km))
    }

    private static func bothLine(date: Date, odometer: Int, km: Int?, now: Date) -> String {
        let dateString = self.dateString(date, now: now)
        guard let km else {
            return String(format: L10n.localize("Due at %1$@ km or %2$@"),
                          OdometerFormat.grouped(odometer), dateString)
        }
        if km < 0 {
            return String(format: L10n.localize("Overdue by %1$@ km or %2$@"),
                          OdometerFormat.grouped(-km), dateString)
        }
        return String(format: L10n.localize("In %1$@ km or %2$@"),
                      OdometerFormat.grouped(km), dateString)
    }
}
