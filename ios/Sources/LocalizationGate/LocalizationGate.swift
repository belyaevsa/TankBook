import Foundation

/// The localization gate (docs/TASKS.md P0.3): makes a hardcoded or
/// untranslated user-facing string a build failure instead of a silent RU
/// regression.
///
/// SwiftUI's `Text("literal")` initialiser takes a `LocalizedStringKey`, so a
/// bare literal IS looked up in the String Catalog - the defect is a key the
/// code references that has no catalogue entry, or an entry without a Russian
/// value. This gate therefore drives off the catalogue, not off style rules:
/// it extracts the keys the app code references from its user-facing call
/// sites and fails on any key that cannot resolve. That is the difference
/// between a gate and a heuristic - a key that resolves is fine even when its
/// wording is unusual; a key that does not resolve is English-in-RU no matter
/// how conventional it looks. Extraction lives in `SourceScanner`.
///
/// WHAT IT CATCHES
///   - `Text("Save fill-up")` where "Save fill-up" is not a catalogue key.
///   - `Text("\(count) days left")` whose template (`%@ days left`) matches no
///     catalogue entry (the catalogue stores the real specifier, `%lld days
///     left`, which normalises to the same template).
///   - A referenced key whose entry has no Russian value (or only an empty
///     one).
///   - Literals on `LocalizedStringKey`-typed stored properties and computed
///     bodies (`var caption: LocalizedStringKey? = "…"`, `var title:
///     LocalizedStringKey { … }`), which are keys by construction.
///   - `L10n.localize("…")`, the app's own catalogue lookup for composed rows.
///     These are the dangerous half: they route through `Text(_: String)`,
///     which does not localise, so a missing key renders English in Russian
///     while reading as correct code. Adding this call site to the scan found
///     two live defects (`%d items on this receipt` on Home, and a product
///     name being sent through the catalogue as if it were copy).
///   - A literal inside a call's non-literal first argument (`Text(x ??
///     "literal")`, `Text(cond ? someString : "literal")`, `"a" + "b"`) - the
///     P5.3 pass. The expression is `String`-typed, so `Text(_: String)`
///     renders the literal in English even when the catalogue holds a
///     translation: the key IS present, so key membership cannot catch it.
///     A pure-literal ternary branch (`cond ? "A" : "B"`) is the exception -
///     SwiftUI builds a `LocalizedStringKey` from it and the branch literal is
///     a runtime key, so it gets a membership check like any other key.
///
/// WHAT IT DOES NOT CATCH (deliberately - documented so the gate's blind spots
/// are known rather than guessed at):
///   - `Text(someVariable)` / `Text(computedKey)` with NO literal inside - a
///     dynamic value cannot be checked without type information or value-flow
///     analysis. The variable may hold user data (correct - it must not be
///     localised) or an unlocalised key (a bug). Only a human reading the
///     rendered Russian can tell; the rule lives at the top of `L10n.swift`.
///   - Literals passed to custom wrappers whose parameter type is `String`
///     (`Text(_: StringProtocol)` does not localise at all). Such wrappers are
///     a real defect class but are invisible to a key-membership check - the
///     string may be a perfect catalogue key and still render English because
///     it was routed through the wrong `Text` overload. Hunt these by making
///     the wrapper take `LocalizedStringKey`; the gate will not spot them.
///   - Escaped interpolation nesting deeper than balanced parentheses, and
///     multi-line `"""` strings (none in the app target today).
///   - Strings in `ios/Tests` and `ios/App/UITests`: the gate is invoked with
///     the app target's sources directory only.
public enum LocalizationGate {

    // MARK: - Check

    /// Scans every `.swift` file under `sources` and reports every referenced
    /// key that the catalogue cannot resolve in Russian.
    public static func violations(sources: URL,
                                  catalogue: LocalizationCatalogue) throws -> [LocalizationViolation] {
        guard let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw LocalizationGateError.sourcesUnreadable(sources.path)
        }
        var violations: [LocalizationViolation] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for reference in SourceScanner.references(inFile: url.path, text: text) {
                // Normalise the code side too: a literal written with a real
                // specifier (`String(format: L10n.localize("%lld days"), n)`)
                // must compare equal to the catalogue key it names.
                let template = normalizeKey(reference.keyTemplate)
                guard let realKey = catalogue.keyTemplates[template] else {
                    violations.append(LocalizationViolation(file: reference.file,
                                                            line: reference.line,
                                                            keyTemplate: template,
                                                            kind: .noEntry))
                    continue
                }
                if !catalogue.hasNonEmptyRu(template) {
                    violations.append(LocalizationViolation(file: reference.file,
                                                            line: reference.line,
                                                            keyTemplate: realKey,
                                                            kind: .ruMissing))
                }
            }
            for literal in SourceScanner.compoundStringLiterals(inFile: url.path, text: text) {
                if literal.localizes {
                    // A pure-literal ternary branch is a runtime key: check it
                    // against the catalogue like any other key.
                    let template = normalizeKey(literal.literal)
                    if catalogue.keyTemplates[template] == nil {
                        violations.append(LocalizationViolation(file: literal.file,
                                                                line: literal.line,
                                                                keyTemplate: template,
                                                                kind: .noEntry))
                    }
                } else {
                    // A literal inside a String-typed expression renders
                    // English through `Text(_: String)` whatever the catalogue
                    // holds (P5.3 - the shape behind the P1.4/P4.7 defects).
                    violations.append(LocalizationViolation(file: literal.file,
                                                            line: literal.line,
                                                            keyTemplate: literal.literal,
                                                            kind: .stringExpressionLiteral))
                }
            }
        }
        return violations.sorted { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }
    }

    /// Normalises a catalogue key: every format specifier (`%lld`, `%@`,
    /// `%1$@`, `%2$lld`, `%d%%`, ...) becomes a single `%@` token, so keys sort
    /// and compare independently of the concrete integer/string placeholder.
    /// Falls back to the unmodified key if the specifier pattern ever fails to
    /// compile - a key that then cannot resolve is reported rather than
    /// silently accepted.
    static func normalizeKey(_ key: String) -> String {
        let pattern = "%(?:[0-9]+\\$)?(?:[-+#0 ]|\\.?[0-9]+)*(?:hh|h|ll|l|L|z|j|t)?[diouxXfFeEgGaAcsp@%]"
        guard let specifier = try? NSRegularExpression(pattern: pattern) else { return key }
        let range = NSRange(key.startIndex..., in: key)
        return specifier.stringByReplacingMatches(in: key, range: range, withTemplate: "%@")
    }
}

/// A string literal the app presents to the user.
public struct LocalizedKeyReference: Equatable, Sendable {
    /// The literal with every interpolation replaced by a `%@` token, so
    /// code-side `Text("\(count) days left")` matches the catalogue-side
    /// `%lld days left` entry after the same normalisation.
    public let keyTemplate: String
    public let file: String
    public let line: Int
}

public enum LocalizationViolationKind: Equatable, Sendable, CustomStringConvertible {
    /// The referenced key has no catalogue entry at all.
    case noEntry
    /// The entry exists but carries no non-empty Russian value.
    case ruMissing
    /// A literal inside a `String`-typed expression (`Text(x ?? "…")`). The
    /// `String` overload does not localise, so it renders English in Russian
    /// even though its key may exist in the catalogue (P5.3).
    case stringExpressionLiteral

    public var description: String {
        switch self {
        case .noEntry: return "no catalogue entry"
        case .ruMissing: return "entry has no Russian value"
        case .stringExpressionLiteral:
            return "literal inside a String-typed expression - Text(_: String) will not localise it"
        }
    }
}

public struct LocalizationViolation: Equatable, Sendable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let keyTemplate: String
    public let kind: LocalizationViolationKind

    public var description: String {
        "\(file):\(line): \(keyTemplate) -> \(kind)"
    }
}

public enum LocalizationGateError: Error, LocalizedError {
    case malformedCatalogue(String)
    case sourcesUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .malformedCatalogue(let name):
            return "\(name) is not a parseable String Catalog"
        case .sourcesUnreadable(let path):
            return "cannot read sources directory at \(path)"
        }
    }
}

/// One catalogue entry: the plain value per language, and the plural forms per
/// language (Russian plural rules have one/few/many/other; English one/other).
public struct LocalizationCatalogueEntry: Sendable {
    /// language -> plain value (stringUnit). Absent for plural entries.
    public let values: [String: String]
    /// language -> plural form name -> value.
    public let pluralForms: [String: [String: String]]
}

/// The parsed `Localizable.xcstrings` String Catalog.
public struct LocalizationCatalogue: Sendable {
    public let sourceLanguage: String
    /// Normalised key template -> the real key as written in the file.
    public let keyTemplates: [String: String]
    private let entries: [String: LocalizationCatalogueEntry]

    public var keyCount: Int { keyTemplates.count }
    public var keysMissingRu: [String] {
        keyTemplates.keys
            .filter { !hasNonEmptyRu($0) }
            .sorted()
            .compactMap { keyTemplates[$0] }
    }
    public var ruCoveragePercent: Int {
        guard !keyTemplates.isEmpty else { return 0 }
        let covered = keyTemplates.keys.filter { hasNonEmptyRu($0) }.count
        return Int((Double(covered) / Double(keyTemplates.count) * 100).rounded())
    }

    /// The value for a real catalogue key (non-plural entries), or nil.
    public func value(for key: String, language: String) -> String? {
        let template = LocalizationGate.normalizeKey(key)
        return entries[template]?.values[language]
    }

    /// The plural forms for a real catalogue key, form name -> value.
    public func pluralForms(for key: String, language: String) -> [String: String] {
        let template = LocalizationGate.normalizeKey(key)
        return entries[template]?.pluralForms[language] ?? [:]
    }

    func hasNonEmptyRu(_ template: String) -> Bool {
        guard let entry = entries[template] else { return false }
        if let value = entry.values["ru"], !value.isEmpty { return true }
        if let forms = entry.pluralForms["ru"] {
            return forms.values.contains { !$0.isEmpty }
        }
        return false
    }

    public static func load(at url: URL) throws -> LocalizationCatalogue {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let strings = object?["strings"] as? [String: Any] else {
            throw LocalizationGateError.malformedCatalogue(url.lastPathComponent)
        }
        let sourceLanguage = object?["sourceLanguage"] as? String ?? "en"
        var templates: [String: String] = [:]
        var entries: [String: LocalizationCatalogueEntry] = [:]
        for (key, raw) in strings {
            guard let entry = raw as? [String: Any] else { continue }
            let template = LocalizationGate.normalizeKey(key)
            templates[template] = key
            entries[template] = Self.parse(entry)
        }
        return LocalizationCatalogue(sourceLanguage: sourceLanguage,
                                     keyTemplates: templates,
                                     entries: entries)
    }

    private static func parse(_ entry: [String: Any]) -> LocalizationCatalogueEntry {
        guard let localizations = entry["localizations"] as? [String: Any] else {
            return LocalizationCatalogueEntry(values: [:], pluralForms: [:])
        }
        var values: [String: String] = [:]
        var pluralForms: [String: [String: String]] = [:]
        for (language, raw) in localizations {
            guard let localization = raw as? [String: Any] else { continue }
            if let stringUnit = localization["stringUnit"] as? [String: Any],
               let value = stringUnit["value"] as? String {
                values[language] = value
            }
            if let variations = localization["variations"] as? [String: Any],
               let plural = variations["plural"] as? [String: Any] {
                var forms: [String: String] = [:]
                for (formName, rawForm) in plural {
                    if let unit = rawForm as? [String: Any],
                       let stringUnit = unit["stringUnit"] as? [String: Any],
                       let value = stringUnit["value"] as? String {
                        forms[formName] = value
                    }
                }
                pluralForms[language] = forms
            }
        }
        return LocalizationCatalogueEntry(values: values, pluralForms: pluralForms)
    }
}
