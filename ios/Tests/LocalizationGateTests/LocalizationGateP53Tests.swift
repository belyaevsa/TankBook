import Foundation
import Testing
@testable import LocalizationGate

/// P5.3 - the RU localization pass (docs/TASKS.md P5.3). Two suites cover it:
/// this one owns the NEW gate passes (the `Text(_: String)` blind spot) and
/// the Russian plural selection at 11/21; `LocalizationGateTests` keeps the
/// P0.3 gate. Split so no test type trips the type_body_length lint rule.
@Suite("Localization gate (P5.3)")
struct LocalizationGateP53Tests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-p53-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - P5.3 the Text(_: String) blind spot

    /// `Text(x ?? "literal")` is a `String`, so the literal renders English
    /// whatever the catalogue holds - the recorded blind spot. The pass must
    /// flag it, and the recorded fix (split the expression so the literal
    /// reaches `Text(_: LocalizedStringKey)`) must clear it.
    @Test("a coalesced fallback literal is flagged and the split fix clears it")
    func coalescedFallbackIsFlagged() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("CoalescedView.swift")

        try """
        import SwiftUI
        struct CoalescedView: View {
            let quote: String?
            var body: some View { Text(quote ?? "Odometer breaks the timeline – check it.") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1, "got \(violations)")
        #expect(violations.first?.kind == .stringExpressionLiteral)
        #expect(violations.first?.keyTemplate == "Odometer breaks the timeline – check it.")

        // The recorded fix: split so the literal is its own LocalizedStringKey.
        try """
        import SwiftUI
        struct CoalescedView: View {
            let quote: String?
            var body: some View {
                if let quote { Text(quote) } else { Text("Odometer breaks the timeline – check it.") }
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let clean = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(clean.isEmpty, "split fix must clear the violation; got \(clean)")
    }

    /// `Text(cond ? variable : "literal")` is pinned to String by the
    /// non-literal branch, so the literal branch renders English.
    @Test("a mixed ternary's literal branch is flagged")
    func mixedTernaryLiteralIsFlagged() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("TernaryView.swift")

        try """
        import SwiftUI
        struct TernaryView: View {
            let name: String
            var body: some View { Text(name.isEmpty ? name : "Nearby suggestion") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1, "got \(violations)")
        #expect(violations.first?.kind == .stringExpressionLiteral)
    }

    /// `"a" + "b"` and `variable + "km"` are always `String`, so their literals
    /// can never reach the catalogue. A variable-led concatenation is the
    /// compound-pass shape (the trailing literal is a direct `+` operand); an
    /// all-literal concatenation already fails the normal pass, because the
    /// leading literal is recorded as the key `"Save "` - trailing space and
    /// all - which no catalogue entry can match.
    @Test("a concatenated literal is flagged")
    func concatenatedLiteralIsFlagged() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("ConcatView.swift")

        try """
        import SwiftUI
        struct ConcatView: View {
            let amount: String
            var body: some View { Text(amount + " km") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1, "got \(violations)")
        #expect(violations.first?.kind == .stringExpressionLiteral)
        #expect(violations.first?.keyTemplate == " km")

        try """
        import SwiftUI
        struct ConcatView: View {
            var body: some View { Text("Save " + "fill-up") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let allLiteral = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(!allLiteral.isEmpty, "all-literal concatenation must fail the gate")
    }

    /// `Text(cond ? "A" : "B")` with both branches literal is a
    /// `LocalizedStringKey` (a runtime key), so the branches need catalogue
    /// membership - and a branch missing from the catalogue must fail the gate.
    /// The same shape already ships in the app (VehicleFormControls, SignInView,
    /// ServiceEntryView) and was previously invisible to key scanning.
    @Test("an all-literal ternary's branches are checked for catalogue membership")
    func allLiteralTernaryBranchesAreKeys() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("TernaryKeysView.swift")

        // Both branches are real catalogue keys - clean.
        try """
        import SwiftUI
        struct TernaryKeysView: View {
            let hasPhoto: Bool
            var body: some View { Text(hasPhoto ? "Replace photo" : "Add a photo") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        #expect(try LocalizationGate.violations(sources: dir, catalogue: catalogue).isEmpty)

        // A branch that is not a catalogue key is a key-membership failure.
        let marker = "N0T_A_KEY_\(UInt64.random(in: UInt64.min ... UInt64.max))"
        try """
        import SwiftUI
        struct TernaryBadView: View {
            let on: Bool
            var body: some View { Text(on ? "Replace photo" : "\(marker)") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.count == 1, "got \(violations)")
        #expect(violations.first?.kind == .noEntry)
        #expect(violations.first?.keyTemplate == marker)
    }

    /// An interpolated literal passed straight to `Text` is NOT the blind
    /// spot: the compiler routes it through `Text(_: LocalizedStringKey)` with
    /// a `%@` key (verified against the SwiftUI interface - the `String` init
    /// is `@_disfavoredOverload`), so it localises exactly like a bare literal
    /// and must not be flagged. The blind spot is a `String`-typed *value*
    /// sharing an expression with copy, never an interpolated literal.
    @Test("an interpolated literal is not the blind spot and is not flagged")
    func interpolatedLiteralIsNotFlagged() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("InterpolatedView.swift")

        try """
        import SwiftUI
        struct InterpolatedView: View {
            let name: String
            var body: some View { Text("\\(name) came back with 1 new entry – stays archived.") }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let violations = try LocalizationGate.violations(sources: dir, catalogue: catalogue)
        #expect(violations.isEmpty, "interpolated literals localise via LocalizedStringKey; got \(violations)")
    }

    // MARK: - P5.3 Russian plural selection at 11 and 21

    /// The expected RENDERED RU strings at 1/2/5/11/21, keyed by catalogue
    /// key. A data table rather than a shape check: the assertion that matters
    /// is the exact string, so a future regression cannot hide behind "the
    /// number appears". 11 must take `many`, 21 `one`.
    private static let pluralCases: [(String, [Int: String])] = [
            ("%lld cars", [1: "1 автомобиль", 2: "2 автомобиля", 5: "5 автомобилей",
                           11: "11 автомобилей", 21: "21 автомобиль"]),
            ("%lld days", [1: "1 день", 2: "2 дня", 5: "5 дней",
                           11: "11 дней", 21: "21 день"]),
            ("%lld days ago", [1: "1 день назад", 2: "2 дня назад", 5: "5 дней назад",
                               11: "11 дней назад", 21: "21 день назад"]),
            ("%lld days left", [1: "Остался 1 день", 2: "Осталось 2 дня", 5: "Осталось 5 дней",
                                11: "Осталось 11 дней", 21: "Остался 21 день"]),
            ("%lld entries", [1: "1 запись", 2: "2 записи", 5: "5 записей",
                              11: "11 записей", 21: "21 запись"]),
            ("%lld entries excluded", [1: "1 запись исключена", 2: "2 записи исключены",
                                       5: "5 записей исключено", 11: "11 записей исключено",
                                       21: "21 запись исключена"]),
            ("%lld entries need a look", [1: "1 запись требует внимания", 2: "2 записи требуют внимания",
                                          5: "5 записей требуют внимания", 11: "11 записей требуют внимания",
                                          21: "21 запись требует внимания"]),
            // PR.14: the post-batch toast (docs/SYNC.md -> "Synced. N entries
            // need a look"). The `Synced.` prefix does not change the plural -
            // 11 takes `many` (записей), 21 takes `one` (запись).
            ("Synced. %lld entries need a look", [1: "Синхронизировано. 1 запись требует внимания",
                                                   2: "Синхронизировано. 2 записи требуют внимания",
                                                   5: "Синхронизировано. 5 записей требуют внимания",
                                                   11: "Синхронизировано. 11 записей требуют внимания",
                                                   21: "Синхронизировано. 21 запись требует внимания"]),
            ("%lld entries pending rates", [1: "1 запись ждёт курс", 2: "2 записи ждут курс",
                                            5: "5 записей ждут курс", 11: "11 записей ждут курс",
                                            21: "21 запись ждёт курс"]),
            ("%lld items on this receipt", [1: "1 позиция в этом чеке", 2: "2 позиции в этом чеке",
                                            5: "5 позиций в этом чеке", 11: "11 позиций в этом чеке",
                                            21: "21 позиция в этом чеке"]),
            ("Save fill-up + %lld expenses", [1: "Сохранить заправку + 1 расход",
                                              2: "Сохранить заправку + 2 расхода",
                                              5: "Сохранить заправку + 5 расходов",
                                              11: "Сохранить заправку + 11 расходов",
                                              21: "Сохранить заправку + 21 расход"]),
            ("Synced %lld days ago", [1: "Синхронизировано 1 день назад", 2: "Синхронизировано 2 дня назад",
                                      5: "Синхронизировано 5 дней назад", 11: "Синхронизировано 11 дней назад",
                                      21: "Синхронизировано 21 день назад"]),
            ("Synced %lld hours ago", [1: "Синхронизировано 1 час назад", 2: "Синхронизировано 2 часа назад",
                                       5: "Синхронизировано 5 часов назад", 11: "Синхронизировано 11 часов назад",
                                       21: "Синхронизировано 21 час назад"]),
            // RV.22: the RU form deliberately carries NO agreement - the count
            // sits after a colon, so every form is identical. That is not
            // laziness, it is what makes the string fit: this key is rendered
            // by the sync state CHIP as well as the Settings row, and the
            // agreeing form ("Ожидает синхронизации · 5 изменений") overflowed
            // the chip and truncated to "Ожидает синхронизации…", dropping the
            // count entirely - caught by opening the RU screenshot, never by a
            // test, because an accessibility label is not truncated. The edges
            // are still asserted so a future edit cannot reintroduce agreement
            // without seeing this note.
            ("Waiting to sync · %lld changes", [1: "Ожидают отправки: 1",
                                                2: "Ожидают отправки: 2",
                                                5: "Ожидают отправки: 5",
                                                11: "Ожидают отправки: 11",
                                                21: "Ожидают отправки: 21"]),
            ("first estimate · %lld fill cycles", [1: "предварительная оценка · 1 цикл заправки",
                                                   2: "предварительная оценка · 2 цикла заправки",
                                                   5: "предварительная оценка · 5 циклов заправки",
                                                   11: "предварительная оценка · 11 циклов заправки",
                                                   21: "предварительная оценка · 21 цикл заправки"]),
            ("in %lld days", [1: "через 1 день", 2: "через 2 дня", 5: "через 5 дней",
                              11: "через 11 дней", 21: "через 21 день"]),
            ("in %lld months", [1: "через 1 месяц", 2: "через 2 месяца", 5: "через 5 месяцев",
                                11: "через 11 месяцев", 21: "через 21 месяц"]),
            ("last %lld months", [1: "за 1 месяц", 2: "за 2 месяца", 5: "за 5 месяцев",
                                  11: "за 11 месяцев", 21: "за 21 месяц"]),
            ("%lld cars – %@", [1: "1 автомобиль – Volvo V60", 2: "2 автомобиля – Volvo V60",
                                5: "5 автомобилей – Volvo V60", 11: "11 автомобилей – Volvo V60",
                                21: "21 автомобиль – Volvo V60"]),
            // P5.5b import wizard plurals - the same 11/21 edge (11 takes
            // `many`, 21 takes `one`).
            ("%lld look like fill-ups you already have. They'll be flagged, not merged – you decide after.",
             [1: "1 похоже на заправку, которая у вас уже есть. Она будет помечена, а не объединена – вы решите после.",
              2: "2 похожи на заправки, которые у вас уже есть. Они будут помечены, а не объединены – вы решите после.",
              5: "5 похожи на заправки, которые у вас уже есть. Они будут помечены, а не объединены – вы решите после.",
              11: "11 похожи на заправки, которые у вас уже есть. Они будут помечены, а не объединены – вы решите после.",
              21: "21 похоже на заправку, которая у вас уже есть. Она будет помечена, а не объединена – вы решите после."]),
            ("%lld rows need a look",
             [1: "1 строка требует внимания", 2: "2 строки требуют внимания",
              5: "5 строк требуют внимания", 11: "11 строк требуют внимания",
              21: "21 строка требует внимания"]),
            ("The other %lld are ready",
             [1: "Остальная 1 готова", 2: "Остальные 2 готовы",
              5: "Остальные 5 готовы", 11: "Остальные 11 готовы",
              21: "Остальная 21 готова"]),
            ("Import %lld fill-ups",
             [1: "Импортировать 1 заправку", 2: "Импортировать 2 заправки",
              5: "Импортировать 5 заправок", 11: "Импортировать 11 заправок",
              21: "Импортировать 21 заправку"]),
            ("Imported %lld fill-ups",
             [1: "Импортирована 1 заправка", 2: "Импортированы 2 заправки",
              5: "Импортировано 5 заправок", 11: "Импортировано 11 заправок",
              21: "Импортирована 21 заправка"]),
            ("%lld rows are ready. These %lld are missing something – fix one, or leave it out.",
             [1: "1 строка готова. Эта 1 неполная – исправьте или пропустите.",
              2: "2 строки готовы. Эти 2 неполные – исправьте или пропустите.",
              5: "5 строк готовы. Эти 5 неполные – исправьте или пропустите.",
              11: "11 строк готовы. Эти 11 неполные – исправьте или пропустите.",
              21: "21 строка готова. Эта 21 неполная – исправьте или пропустите."]),
            // PJ.13: "Synced just now · 1 device" - the account card's
            // device-count suffix (docs/JOURNEYS.md J11a -> First push). The
            // `%@` slot is the app-composed ago text and never governs a case.
            ("%@ · %lld devices",
             [1: "Volvo V60 · 1 устройство", 2: "Volvo V60 · 2 устройства",
              5: "Volvo V60 · 5 устройств", 11: "Volvo V60 · 11 устройств",
              21: "Volvo V60 · 21 устройство"]),
            // PJ.10: the date-format question's subtitle - 11 and 21 both end
            // in 1, but 11 takes `many` (дат) and 21 takes `one` (дата).
            ("Date format matters – %lld dates read either way.",
             [1: "Формат дат важен – 1 дата читается двояко.",
              2: "Формат дат важен – 2 даты читаются двояко.",
              5: "Формат дат важен – 5 дат читаются двояко.",
              11: "Формат дат важен – 11 дат читаются двояко.",
              21: "Формат дат важен – 21 дата читается двояко."]),
            ("This file has %lld income rows; income isn't imported in v1.",
             [1: "В этом файле 1 строка доходов; доходы не импортируются в v1.",
              2: "В этом файле 2 строки доходов; доходы не импортируются в v1.",
              5: "В этом файле 5 строк доходов; доходы не импортируются в v1.",
              11: "В этом файле 11 строк доходов; доходы не импортируются в v1.",
              21: "В этом файле 21 строка доходов; доходы не импортируются в v1."]),
            ("This file has %lld reminders; reminders aren't imported in v1.",
             [1: "В этом файле 1 напоминание; напоминания не импортируются в v1.",
              2: "В этом файле 2 напоминания; напоминания не импортируются в v1.",
              5: "В этом файле 5 напоминаний; напоминания не импортируются в v1.",
              11: "В этом файле 11 напоминаний; напоминания не импортируются в v1.",
              21: "В этом файле 21 напоминание; напоминания не импортируются в v1."]),
            // PJ.4: the Home banner's due-in-N-days sentence - the title sits in
            // the nominative head, `через` reaches only the %lld count, so the
            // 11/21 edge applies to the number (11 дней takes `many`, 21 день
            // takes `one`). The `%@` slot is rendered as "Volvo V60" here, the
            // same user-text slot the banner feeds the reminder title into.
            ("%@ in %lld days",
             [1: "Volvo V60 через 1 день", 2: "Volvo V60 через 2 дня",
              5: "Volvo V60 через 5 дней", 11: "Volvo V60 через 11 дней",
              21: "Volvo V60 через 21 день"]),
            // PJ.14: the live odometer-delta caption (docs/DESIGN.md -> the
            // Pump Card). RU spells out the unit so the count governs a real
            // three-form plural (километр / километра / километров) - the 11/21
            // edge is the same trap as every other count key: 11 takes `many`,
            // 21 takes `one`.
            ("+%lld km since last",
             [1: "+1 километр с прошлой заправки", 2: "+2 километра с прошлой заправки",
              5: "+5 километров с прошлой заправки", 11: "+11 километров с прошлой заправки",
              21: "+21 километр с прошлой заправки"])
        ]

    /// Russian plural selection is not 1/2/5: 11 ends in 1 but takes `many`,
    /// 21 ends in 1 and takes `one`. Every plural key the app renders is
    /// asserted on its RENDERED string - each expected string is written out
    /// in full in `pluralCases`.
    @Test("RU plural strings render the right form at 1, 2, 5, 11 and 21")
    func russianPluralsSelectTheRightFormAtTheEdges() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let category: [Int: String] = [1: "one", 2: "few", 5: "many", 11: "many", 21: "one"]

        func render(_ key: String, _ count: Int) -> String {
            let ruForms = catalogue.pluralForms(for: key, language: "ru")
            guard let form = category[count], let template = ruForms[form] else {
                return "MISSING-\(String(describing: category[count]))"
            }
            return template
                .replacingOccurrences(of: "%lld", with: "\(count)")
                .replacingOccurrences(of: "%@", with: "Volvo V60")
        }

        for (key, expected) in Self.pluralCases {
            for count in [1, 2, 5, 11, 21] {
                #expect(render(key, count) == expected[count],
                        "\(key) at \(count): rendered '\(render(key, count))', expected '\(expected[count])'")
            }
        }
    }

    /// The P1.4 lesson made load-bearing: "Synced 3 hours ago" must not lose
    /// the verb in Russian. The status line renders reassurance, and a bare
    /// "3 часа назад" reads as a fact, not a sync state.
    @Test("Synced hours/days ago keep the verb in Russian")
    func syncedAgoKeepsItsVerb() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        for key in ["Synced %lld hours ago", "Synced %lld days ago"] {
            let ruForms = catalogue.pluralForms(for: key, language: "ru")
            #expect(ruForms.values.allSatisfy { $0.contains("Синхронизировано") },
                    "\(key) RU forms must keep the verb: \(ruForms)")
            #expect(!ruForms.values.contains { $0.hasPrefix("%lld") },
                    "\(key) must not start with the bare count: \(ruForms)")
        }
    }

    /// The P5.3 shape changes, pinned. Each key's RU puts the runtime slot in
    /// a position no preposition reaches: a quoted nominative, an apposition,
    /// or a slot after a separator. The assertion is the sharper rule itself:
    /// no governing preposition may sit IMMEDIATELY before the slot, because
    /// the slot receives text (a car name, a part title, an account name, a
    /// device name) that cannot be declined - the P4.7 lesson is that no
    /// translation fixes a wrong sentence shape.
    @Test("reshaped RU keys do not place a governing preposition before the runtime slot")
    func reshapedKeysDoNotGovernTheSlot() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        // A struct, not a tuple - the gate's own lint rule (large_tuple)
        // must not be tripped by the tests that guard the gate.
        struct ReshapedKey {
            let key: String
            let slot: String
            let expectedRU: String
        }
        let reshaped: [ReshapedKey] = [
            ReshapedKey(key: "%@ came back with 1 new entry – stays archived.",
                        slot: "%@", expectedRU: "«%@» вернулся с 1 новой записью – остаётся в архиве."),
            ReshapedKey(key: "Install %1$@ from %2$@?",
                        slot: "%1$@", expectedRU: "Установить «%1$@» от %2$@?"),
            ReshapedKey(key: "Nothing is stored under this %1$@. Last time, did you sign in with %2$@?",
                        slot: "%1$@",
                        expectedRU: "Под этой учётной записью «%1$@» ничего не сохранено. "
                            + "В прошлый раз вы входили через %2$@?"),
            ReshapedKey(key: "removed on %@",
                        slot: "%@", expectedRU: "устройство: %@")
        ]

        // с, на, в, от, до, у, под, за, для, про, о - the prepositions that
        // govern a following noun. Any of them directly before the slot means
        // the sentence shape is wrong.
        let prepositionPattern = #"\b(?:с|на|в|от|до|у|под|за|для|про|о)\s+"#

        for item in reshaped {
            guard let russian = catalogue.value(for: item.key, language: "ru") else {
                Issue.record("\(item.key) has no RU value")
                continue
            }
            #expect(russian == item.expectedRU, "\(item.key) RU drifted: '\(russian)'")
            let slotPattern = NSRegularExpression.escapedPattern(for: item.slot)
            let full = try NSRegularExpression(pattern: prepositionPattern + slotPattern)
            let range = NSRange(russian.startIndex..., in: russian)
            #expect(full.firstMatch(in: russian, options: [], range: range) == nil,
                    "\(item.key) RU '\(russian)' governs \(item.slot) with a preposition")
        }
    }

    // MARK: - P6.3 the gateway timeout message (hard rule 7: it names its next
    // step, EN and RU; docs/API.md rule 2)

    /// The 3 s budget message is pinned verbatim in both languages. It must
    /// name the next step - carry on with what was read on-device - and the RU
    /// must obey docs/LOCALIZATION.md: no past-tense verb aimed at the user
    /// (Russian has no genderless past), no `%@` slot at all (nothing to
    /// decline), and no upsell (the Pro tier is deferred).
    @Test("the gateway timeout message names its next step in EN and RU")
    func gatewayTimeoutMessageNamesItsNextStep() throws {
        let key = "Cloud reading continues in the background – keep going with what was read here."
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        #expect(catalogue.value(for: key, language: "en") == key)

        let expectedRU = "Облачное распознавание продолжается в фоне – продолжайте с тем, что распознано здесь."
        let russian = try #require(catalogue.value(for: key, language: "ru"), "\(key) has no RU value")
        #expect(russian == expectedRU, "RU drifted: '\(russian)'")

        // No runtime slot: there is nothing for a phrase to decline, and the
        // P4.7/P5.3 slot-governance rules have nothing to trip over.
        #expect(!russian.contains("%"))

        // The user is addressed in the imperative, never a past-tense verb
        // (docs/LOCALIZATION.md: Russian has no genderless past tense). The
        // one past participle - "распознано" - describes the reading, not the
        // user, so it is legal.
        #expect(russian.contains("продолжайте"))

        // No monetization: hard rule 7 forbids an upsell in this surface and
        // API.md forbids one mid-capture, which is exactly where this runs.
        #expect(!russian.lowercased().contains("pro"))
        #expect(!russian.lowercased().contains("подписк"))
        #expect(!key.lowercased().contains("pro"))
    }

    // MARK: - P1.13b the F9a conflict quote renders the grouped odometer

    /// The F9a quote's odometer slot changed `%d` -> `%@` so the caller formats
    /// the figure with `OdometerFormat.grouped` (the P1.13 class: the shared
    /// formatter is correct and a call site bypasses it). This pins the
    /// CATALOGUE half: the new key carries the exact EN/RU shapes, the RU slot
    /// receives a grouped NUMBER (which does not decline - docs/LOCALIZATION.md),
    /// no governing preposition sits before the slot, and the old `%d` key is
    /// gone (it and the new key normalise to the same template, so leaving it
    /// beside the new one would trip the collision guard
    /// `catalogueKeysDoNotCollideAfterNormalisation` - the guard's job, not a
    /// problem to route around). The RENDERED half is the three UI suites (L4):
    /// the composed quote is drawn there, and only pixels prove the group
    /// separator is visible.
    @Test("the F9a conflict quote composes the grouped figure in EN and RU")
    func f9aConflictQuoteComposesTheGroupedFigure() throws {
        let key = "%@ already recorded %@ km."
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        // EN: the key's value is itself; composing 119486 must render the
        // grouped figure, never the raw digits.
        let english = try #require(catalogue.value(for: key, language: "en"),
                                   "\(key) has no EN value")
        var composedEN = english
        if let range = composedEN.range(of: "%@") { composedEN.replaceSubrange(range, with: "Aug 17") }
        if let range = composedEN.range(of: "%@") { composedEN.replaceSubrange(range, with: "119\u{00A0}486") }
        #expect(composedEN == "Aug 17 already recorded 119\u{00A0}486 km.",
                "EN composed: '\(composedEN)'")

        // RU: the day is quoted, the subject is `пробег`, and the second slot
        // receives the grouped figure - a number, which does not decline.
        let expectedRU = "«%@» уже зафиксирован пробег %@ км."
        let russian = try #require(catalogue.value(for: key, language: "ru"),
                                   "\(key) has no RU value")
        #expect(russian == expectedRU, "RU drifted: '\(russian)'")
        var composedRU = russian
        if let range = composedRU.range(of: "%@") { composedRU.replaceSubrange(range, with: "17 авг.") }
        if let range = composedRU.range(of: "%@") { composedRU.replaceSubrange(range, with: "119\u{00A0}486") }
        #expect(composedRU == "«17 авг.» уже зафиксирован пробег 119\u{00A0}486 км.",
                "RU composed: '\(composedRU)'")

        // No governing preposition may sit immediately before a runtime slot
        // (docs/LOCALIZATION.md - the P4.7 lesson). The odometer slot follows
        // `пробег`; the quoted day is preceded by nothing but the quote mark.
        let prepositionPattern = #"\b(?:с|на|в|от|до|у|под|за|для|про|о)\s+"#
        let full = try NSRegularExpression(pattern: prepositionPattern
            + NSRegularExpression.escapedPattern(for: "%@"))
        let range = NSRange(russian.startIndex..., in: russian)
        #expect(full.firstMatch(in: russian, options: [], range: range) == nil,
                "\(key) RU governs a slot with a preposition: '\(russian)'")

        // The old `%d` key is gone from the RAW catalogue, not just shadowed by
        // normalisation. Re-adding it next to the new key fails the collision
        // guard; removing it here documents that the guard is respected.
        let data = try Data(contentsOf: Self.catalogueURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = (root?["strings"] as? [String: Any]) ?? [:]
        #expect(strings["%@ already recorded %d km."] == nil,
                "the old %d key must be gone - it collides with the %@ key after normalisation")
        #expect(strings[key] != nil, "the new key must be present in the raw catalogue")
    }
}

/// PJ.13 (docs/JOURNEYS.md J11a -> First push): the account card's
/// "Synced just now · 1 device" line. Owned by its own suite so no test type
/// trips the type_body_length lint rule - the same split rationale the file's
/// header names for the two gate suites.
@Suite("Device-count plural (PJ.13)")
struct DeviceCountPluralTests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    /// The RU plural is the same 11/21 trap the whole gate exists for - 11 and
    /// 21 both end in 1 but take `many` and `one` respectively (устройство /
    /// устройства / устройств) - and a swap of the `many`/`few` forms is
    /// invisible at every number except the edges. Asserted at L1 on the
    /// RENDERED string in BOTH languages: EN is one/other ("1 device" vs "N
    /// devices"), RU is one/few/many.
    @Test("the device-count plural renders at 1, 2, 5, 11 and 21 in EN and RU")
    func deviceCountPluralRendersInBothLanguages() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let key = "%@ · %lld devices"
        let counts = [1, 2, 5, 11, 21]

        let expectedEN: [Int: String] = [
            1: "· 1 device", 2: "· 2 devices", 5: "· 5 devices",
            11: "· 11 devices", 21: "· 21 devices"
        ]
        let expectedRU: [Int: String] = [
            1: "· 1 устройство", 2: "· 2 устройства", 5: "· 5 устройств",
            11: "· 11 устройств", 21: "· 21 устройство"
        ]

        func render(language: String, _ count: Int) -> String {
            // EN selects on "one"; RU on "one"/"few"/"many". `other` is the
            // fallback neither branch reaches at these counts, so it is
            // asserted separately as a non-empty form.
            let form: String
            switch language {
            case "ru":
                form = count == 1 || count == 21 ? "one"
                    : (count == 2 ? "few" : "many")
            default:
                form = count == 1 ? "one" : "other"
            }
            guard let template = catalogue.pluralForms(for: key, language: language)[form] else {
                return "MISSING-\(form)"
            }
            return template
                .replacingOccurrences(of: "%@", with: "")
                .replacingOccurrences(of: "%lld", with: "\(count)")
                .trimmingCharacters(in: .whitespaces)
        }

        for count in counts {
            let en = render(language: "en", count)
            #expect(en == expectedEN[count],
                    "EN device count at \(count): rendered '\(en)', expected '\(expectedEN[count]!)'")
            let ru = render(language: "ru", count)
            #expect(ru == expectedRU[count],
                    "RU device count at \(count): rendered '\(ru)', expected '\(expectedRU[count]!)'")
        }

        // The `other` fallback must exist (English uses it for every count but
        // 1) and must not be empty.
        for language in ["en", "ru"] {
            let forms = catalogue.pluralForms(for: key, language: language)
            #expect(!(forms["other"]?.isEmpty ?? true),
                    "\(language) must carry a non-empty `other` form for \(key)")
        }
    }
}
