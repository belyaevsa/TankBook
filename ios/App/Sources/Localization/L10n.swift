import Foundation
import TankbookCore

/// String Catalog access for composed display strings. Standalone phrases go
/// through `Text(LocalizedStringKey)`; composed rows (units, suggestion subtitles)
/// read the same catalog through the bundle. Every key here has an EN + RU
/// entry in Localizable.xcstrings.
/// **The trap this file cannot save you from.** `Text(_: LocalizedStringKey)`
/// localises; `Text(_: String)` does not. Any expression that produces a
/// `String` therefore renders its English key in Russian even when the catalogue
/// holds a translation, and the P0.3 localization gate cannot see it - the key IS
/// present, so nothing is missing to report.
///
/// Four have been found this way, each by looking at a Russian screenshot:
///   let text = locked ? "✓" : "checks as you type"     // inferred String
///   Text(conflict.quote ?? "Odometer breaks the...")   // coalesced String?
///   Text(selection?.name ?? "Nearby suggestion")       // coalesced String?
///   hintText("Which currency is this?")                // String parameter
///
/// The shape is always the same: **runtime data and copy sharing one expression**.
/// Split them - `if let x { Text(x) } else { Text("literal") }` - so the literal
/// reaches the `LocalizedStringKey` overload. When a wrapper must take text, type
/// its parameter `LocalizedStringKey`, not `String`.
enum L10n {
    static func localize(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func distanceUnit(_ unit: DistanceUnit) -> String {
        switch unit {
        case .km: localize("km")
        case .mi: localize("mi")
        }
    }

    static func volumeUnit(_ unit: VolumeUnit) -> String {
        switch unit {
        case .l: localize("L")
        case .galUS, .galUK: localize("gal")
        }
    }

    /// The units editor's volume labels - "gal (US)" / "gal (UK)" distinguish
    /// the two gallons, which the compact `volumeUnit` cannot (both are "gal").
    static func volumeLabel(_ unit: VolumeUnit) -> String {
        switch unit {
        case .l: localize("L")
        case .galUS: localize("gal (US)")
        case .galUK: localize("gal (UK)")
        }
    }

    static func consumptionLabel(_ unit: ConsumptionUnit) -> String {
        switch unit {
        case .lPer100: localize("L/100km")
        case .mpgUS: localize("MPG (US)")
        case .mpgUK: localize("MPG (UK)")
        case .kmPerL: localize("km/L")
        }
    }

    static func energyLabel(_ unit: EnergyUnit) -> String {
        switch unit {
        case .kWhPer100: localize("kWh/100")
        case .miPerKWh: localize("mi/kWh")
        }
    }

    static func consumptionUnit(_ unit: ConsumptionUnit) -> String {
        switch unit {
        case .lPer100: localize("L/100km")
        case .mpgUS, .mpgUK: localize("MPG")
        case .kmPerL: localize("km/L")
        }
    }

    static var kWh: String { localize("kWh") }

    /// "Page 1 of 3" - the invoice page strip's counter. A full localised phrase
    /// per language, never concatenation (RU word order differs: "Страница 1 из
    /// 3"). The numbers are runtime data, the phrase is one catalogue key.
    static func pageOf(current: Int, total: Int) -> String {
        String(format: localize("Page %1$@ of %2$@"), "\(current)", "\(total)")
    }

    /// The archived-car row subtitle (J13): "Archived · sold Mar 2026 · history
    /// kept" from `archivedAt`, or the bare "Archived · history kept" when the
    /// car was archived without a date. The month-year string is produced by a
    /// locale-aware DateFormatter (nominative in every language), and the
    /// surrounding phrase is one full localised string per language - never
    /// concatenation (the RU pass on P1.4 proved composed strings need a full
    /// localised phrase).
    static func archivedSubtitle(archivedAt: Date?) -> String {
        guard let archivedAt else { return localize("Archived · history kept") }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMM yyyy",
                                                        options: 0, locale: Locale.current)
        let month = formatter.string(from: archivedAt)
        return String(format: localize("Archived · %1$@ · history kept"), month)
    }

    /// The headline unit a vehicle's consumption figure is reported in
    /// (docs/SCHEMA.md -> Vehicle.units; P1.11): an EV always reports
    /// kWh/100, a fuel car its configured consumption unit - per-vehicle,
    /// never a global setting. Home's headline renders through this so the
    /// switcher and Home can never disagree about a number's unit.
    static func headlineUnit(_ unit: HeadlineUnit) -> String {
        switch unit {
        case .energyPer100: localize("kWh/100")
        case .consumption(let consumption): consumptionUnit(consumption)
        }
    }

    /// The compact headline unit for tight vitals (the Car switcher rows and
    /// the Trends tiles): "L/100", "kWh/100", "MPG", "km/L" - the forms the
    /// CarSwitcher artboard shows, not the long "L/100km".
    static func consumptionUnitShort(_ unit: HeadlineUnit) -> String {
        switch unit {
        case .energyPer100: localize("kWh/100")
        case .consumption(.lPer100): localize("L/100")
        case .consumption(.mpgUS), .consumption(.mpgUK): localize("MPG")
        case .consumption(.kmPerL): localize("km/L")
        }
    }

    /// "1 entry excluded" / "2 entries excluded" - the Home footnote for
    /// entries excluded from a figure. Real plural rules per language
    /// (Russian has three forms) via the String Catalog's "%lld entries
    /// excluded" plural variations - never concatenation (the RU pass on P1.4
    /// proved composed strings need a full localised phrase per language).
    static func entriesExcluded(_ count: Int) -> String {
        String(localized: "\(count) entries excluded")
    }

    /// The honest consumption-span label, localized (docs/SCHEMA.md ->
    /// HEADLINE; docs/ERRORS.md -> Trends). Shared by Home and Trends so they
    /// render the identical wording from one place. `Headline.Label.honestText()`
    /// is the same rule in the default language; this is the catalog-backed
    /// rendering with real plural rules per language ("last 5 months", never
    /// "last 3 months" for an extended window; "first estimate · 1 fill cycle").
    static func honestSpanLabel(_ label: Headline.Label) -> String {
        switch label {
        case .window(let months):
            return String(localized: "last \(months) months")
        case .firstEstimate(let cycles):
            return String(localized: "first estimate · \(cycles) fill cycles")
        }
    }

    /// The display label for an Expense category (docs/SCHEMA.md,
    /// Expense.category). The `.other` payloads the mixed-receipt detector
    /// (P2.4) emits are machine tokens, not user copy: "wash" maps to a
    /// localised car-wash label, anything else to the generic "Other".
    static func expenseCategoryLabel(_ category: ExpenseCategory) -> String {
        switch category {
        case .insurance: localize("Insurance")
        case .tax: localize("Tax")
        case .parking: localize("Parking")
        case .toll: localize("Toll")
        case .fine: localize("Fine")
        case .accessory: localize("Accessory")
        case .parts: localize("Parts")
        case .other(let value):
            switch value {
            case "wash": localize("Wash")
            default: localize("Other")
            }
        }
    }

    /// "Install oil filter from Mar 3?" - the ServiceEntry Link row's offer. One
    /// full localised phrase per language, never concatenation: the part title
    /// and the purchase day are runtime data sharing the sentence.
    static func installPart(title: String, day: String) -> String {
        String(format: localize("Install %1$@ from %2$@?"), title, day)
    }

    /// "bought Mar 3, 12.40 €" - a shelf part's purchase provenance. One full
    /// localised phrase per language.
    static func partBought(date: String, amount: String) -> String {
        String(format: localize("bought %1$@, %2$@"), date, amount)
    }
}
