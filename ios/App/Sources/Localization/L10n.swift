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
///
/// P5.3 made the provable half of this a gate: `LocalizationGate` now flags a
/// literal sitting inside a `String`-typed argument (`x ?? "…"`, a mixed
/// ternary, a concatenation), and it found two live instances (the Provider /
/// Vendor placeholders on Edit entry, both fixed). An interpolated literal
/// (`Text("\(value) literal")`) is NOT the trap - the compiler routes it through
/// `Text(_: LocalizedStringKey)` with a `%@` key (the `String` init is
/// `@_disfavoredOverload`). `Text(someVariable)` with no literal at all needs
/// value-flow analysis, so only a human reading the rendered Russian can judge
/// it. Full audit and reasoning: `docs/LOCALIZATION.md`.
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

    /// "3 entries pending rates" - the F9 footnote count for entries still
    /// waiting on a rate (docs/JOURNEYS.md F9, the text verbatim). Real plural
    /// rules per language (Russian has three forms - 1 запись ждёт курс /
    /// 2 записи ждут курс / 5 записей ждут курс) via the String Catalog's
    /// "%lld entries pending rates" plural variations, exactly like
    /// `entriesExcluded`. It is a hint, never a warning: nothing is wrong, the
    /// number is simply not known yet.
    static func pendingRates(_ count: Int) -> String {
        String(localized: "\(count) entries pending rates")
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

    // MARK: - Sign in & restore (P4.4)

    static func providerName(_ provider: AuthProvider) -> String {
        switch provider {
        case .apple: localize("Apple")
        case .google: localize("Google")
        }
    }

    /// The account's name for a provider ("Apple ID" / "Google") - the J11a
    /// wrong-provider question names both the account that is empty and the one
    /// to try instead, and the two word differently.
    static func providerAccountName(_ provider: AuthProvider) -> String {
        switch provider {
        case .apple: localize("Apple ID")
        case .google: localize("Google")
        }
    }

    /// "driver@icloud.com · signed in with Apple" - the Restoring screen's
    /// identity line. A hidden (private-relay) identity renders the bare
    /// "signed in with Apple". One full localised phrase per language.
    static func signedInSubtitle(email: String?, provider: AuthProvider) -> String {
        let name = providerName(provider)
        if let email {
            return String(format: localize("%1$@ · signed in with %2$@"), email, name)
        }
        return String(format: localize("signed in with %@"), name)
    }

    /// The J11a wrong-provider question (docs/JOURNEYS.md J11a): names the
    /// account that turned out empty and the provider to try instead.
    static func wrongProviderQuestion(signedInWith current: AuthProvider,
                                      switchTo other: AuthProvider) -> String {
        String(format: localize("Nothing is stored under this %1$@. Last time, did you sign in with %2$@?"),
               providerAccountName(current), providerName(other))
    }

    /// "Use Google instead" - the one-tap provider switch.
    static func switchProvider(_ provider: AuthProvider) -> String {
        String(format: localize("Use %@ instead"), providerName(provider))
    }

    /// "2 cars" - pluralised (Russian has three forms).
    static func carCount(_ count: Int) -> String {
        String(localized: "\(count) cars")
    }

    /// "428 entries" - pluralised.
    static func entryCount(_ count: Int) -> String {
        String(localized: "\(count) entries")
    }

    /// "from your Android phone, yesterday" - the last-odometer provenance. One
    /// full localised phrase: the device name and the relative day are runtime
    /// data sharing the sentence, never concatenated. RU reads "%1$@, %2$@" -
    /// the device name in the nominative head, then the day - because a
    /// server-supplied device name cannot be declined (the P4.7 lesson: no
    /// translation of "с вашего %1$@" is correct, only a different shape).
    static func lastOdometerSource(deviceName: String, daysAgo: Int) -> String {
        String(format: localize("from your %1$@, %2$@"), deviceName, relativeDay(daysAgo))
    }

    /// "today" / "yesterday" / "3 days ago" (plural).
    static func relativeDay(_ daysAgo: Int) -> String {
        switch daysAgo {
        case 0: localize("today")
        case 1: localize("yesterday")
        default: String(localized: "\(daysAgo) days ago")
        }
    }

    /// "downloading · 38%" - the Restoring screen's photo progress line.
    static func downloading(percent: Int) -> String {
        String(format: localize("downloading · %@"), "\(percent)%")
    }

    // MARK: - Restore states (P4.7)

    /// "428 entries · Sep 2019 – Aug 2026" - the Restoring screen's entries line.
    /// One full localised phrase per language, never concatenation: the count
    /// (real RU plural rules) and the two month-year strings are runtime data
    /// sharing one sentence (the trap at the top of this file).
    static func restoreEntriesLine(entryCount: Int, startMonthYear: String, endMonthYear: String) -> String {
        String(localized: "\(entryCount) entries · \(startMonthYear) – \(endMonthYear)")
    }

    /// "2 cars – Volvo V60, ID.4" - the Restoring screen's cars line. One full
    /// localised phrase (RU plural rules); the names are user data sharing the
    /// sentence, never concatenated copy.
    static func restoreCarsLine(carCount: Int, names: String) -> String {
        String(localized: "\(carCount) cars – \(names)")
    }

    // MARK: - Settings sync surface (P4.9b)

    /// The account card's identity line: the display email when the provider
    /// handed one ("driver@icloud.com"), else the provider account name
    /// ("Apple ID" / "Google") for a hidden private-relay identity.
    static func accountTitle(email: String?, provider: AuthProvider) -> String {
        if let email { return email }
        return providerAccountName(provider)
    }

    /// The status line's reassurance text (docs/ERRORS.md -> Settings): "Synced
    /// just now", "Synced 3 hours ago" or "Synced 5 days ago". A full localised
    /// phrase per language with real plural rules (RU час/часа/часов,
    /// день/дня/дней) - never concatenation. A nil `lastSyncDate` (signed in,
    /// nothing has synced yet) reads as "just now": nothing is pending, so it is
    /// reassurance, never a warning.
    static func syncedAgo(lastSyncDate: Date?, now: Date = Date()) -> String {
        guard let lastSyncDate else { return localize("Synced just now") }
        let interval = now.timeIntervalSince(lastSyncDate)
        if interval < 3600 { return localize("Synced just now") }
        let hours = Int(interval / 3600)
        if hours < 24 { return syncedHoursAgo(hours) }
        return syncedDaysAgo(Int(interval / 86_400))
    }

    /// "Synced %lld hours ago" - plural (RU час / часа / часов).
    static func syncedHoursAgo(_ hours: Int) -> String {
        String(localized: "Synced \(hours) hours ago")
    }

    /// "Synced %lld days ago" - plural (RU день / дня / дней).
    static func syncedDaysAgo(_ days: Int) -> String {
        String(localized: "Synced \(days) days ago")
    }

    /// "Waiting to sync · %lld changes" - plural (RU изменение / изменения /
    /// изменений). The status is reassurance, never a warning: a long queue is
    /// not an error state (docs/SYNC.md S7).
    static func waitingToSync(_ count: Int) -> String {
        String(localized: "Waiting to sync · \(count) changes")
    }

    /// "N entries need a look" - the flagged-entries count and link only, plural
    /// (RU запись требует / записи требуют / записей требуют). Settings resolves
    /// nothing; the count is derived and the link goes to where the data lives.
    static func flaggedEntries(_ count: Int) -> String {
        String(localized: "\(count) entries need a look")
    }

    /// "Photo storage 95% full – older photos stay on this phone only."
    /// (docs/ERRORS.md -> Settings). One full localised phrase; the percent is
    /// runtime data.
    static func quotaFull(percent: Int) -> String {
        String(format: localize("Photo storage %lld%% full – older photos stay on this phone only."), percent)
    }

    /// "This device was signed out – sign in to reconnect. Your data on this
    /// phone is untouched." (docs/ERRORS.md -> Settings, the 410 card).
    static var deviceRevokedMessage: String {
        localize("This device was signed out – sign in to reconnect. Your data on this phone is untouched.")
    }

    /// "Sync service unreachable – your data is safe on this phone. It will go
    /// up automatically when the service is back." (docs/ERRORS.md -> Settings,
    /// the server-5xx card). Reassurance, never amber.
    static var syncServiceUnreachableMessage: String {
        let key = "Sync service unreachable – your data is safe on this phone. "
            + "It will go up automatically when the service is back."
        return localize(key)
    }

    // MARK: - Import wizard (P5.5b)

    /// "from MyFuelManager_2026-08.csv · nothing is saved yet" - the preview's
    /// source line. One full localised phrase per language (RU word order
    /// differs); the file name is runtime data sharing the sentence.
    static func fromFileNothingSaved(fileName: String) -> String {
        String(format: localize("from %1$@ · nothing is saved yet"), fileName)
    }

    /// "3 look like fill-ups you already have. They'll be flagged, not merged –
    /// you decide after." - the S2 duplicate count when merging (hard rule 8),
    /// real plural rules per language.
    static func lookLikeDuplicates(_ count: Int) -> String {
        String(localized: "\(count) look like fill-ups you already have. They'll be flagged, not merged – you decide after.")
    }

    /// "6 rows need a look" - the review-list count (F6), plural.
    static func rowsNeedALook(_ count: Int) -> String {
        String(localized: "\(count) rows need a look")
    }

    /// "The other 214 are ready" - the preview's partial-parse footnote.
    static func otherRowsReady(_ review: Int, total: Int) -> String {
        String(localized: "The other \(total - review) are ready")
    }

    /// "Import 214 fill-ups" - the preview's confirm button, plural.
    static func importFillUps(_ count: Int) -> String {
        String(localized: "Import \(count) fill-ups")
    }

    /// "Imported 214 fill-ups" - the confirmation toast after the commit.
    static func importedFillUps(_ count: Int) -> String {
        String(localized: "Imported \(count) fill-ups")
    }

    /// "214 rows are ready. These six are missing something – fix one, or leave
    /// it out." - the review screen's intro, two runtime counts sharing one
    /// sentence (never concatenated).
    static func rowsReadyIntro(ready: Int, review: Int) -> String {
        String(localized: "\(ready) rows are ready. These \(review) are missing something – fix one, or leave it out.")
    }

    /// "38.00 × 1.812 is 68.86, but the file says 64.66. A discount, or a
    /// typo." - the cross-check mismatch's evidence line. The four numbers are
    /// runtime data sharing one sentence.
    static func crossCheckDetail(volume: String, price: String,
                                 computed: String, fileTotal: String) -> String {
        String(format: localize("%1$@ × %2$@ is %3$@, but the file says %4$@. A discount, or a typo."),
               volume, price, computed, fileTotal)
    }

    /// "This doesn't look like a My Fuel Manager export." - the 422 message,
    /// naming the DECLARED source specifically (F7, docs/ERRORS.md).
    static func doesNotLookLike(displayName: String) -> String {
        String(format: localize("This doesn't look like a %@ export."), displayName)
    }

    /// "We read: My Fuel Manager. Send us the file and we'll add it." - the
    /// not-supported sheet names what IS supported rather than dead-ending.
    static func weReadThese(supportedNames: String) -> String {
        String(format: localize("We read: %@. Send us the file and we'll add it."), supportedNames)
    }

    /// The "send us the file" share-sheet body - a consent affordance, not a
    /// silent upload.
    static var sendUsTheFileMessage: String {
        localize("I'd like Tankbook to import from my fuel app – here's my export file.")
    }

    /// "Off by 4.20 €" - a cross-check-mismatch row's badge (F6b). The amount
    /// is already formatted with its symbol.
    static func offBy(amount: String) -> String {
        String(format: localize("Off by %@"), amount)
    }

    /// "Row 6" - an unparsed review row's label (the 1-based data-row number).
    static func rowLabel(sourceRow: Int) -> String {
        String(format: localize("Row %@"), "\(sourceRow)")
    }

    /// "Imported car" - the fallback name when a file names no vehicle.
    static var importedCarName: String {
        localize("Imported car")
    }

    /// A format row's file kinds ("CSV or backup file"), localized per kind.
    static func fileKindsLabel(_ kinds: [String]) -> String {
        let normalized = kinds.map { $0.lowercased() }
        if normalized.contains("csv") && normalized.contains("backup") {
            return localize("CSV or backup file")
        }
        let mapped = kinds.map { kind -> String in
            switch kind.lowercased() {
            case "csv": return localize("CSV")
            case "backup": return localize("backup file")
            default: return kind.capitalized
            }
        }
        return mapped.joined(separator: localize(" or "))
    }
}
