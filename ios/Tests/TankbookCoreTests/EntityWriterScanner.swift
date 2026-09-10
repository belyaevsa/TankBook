import Foundation

/// The RV.163 scanner: a pure function over source text and the SCHEMA doc, so
/// a test can feed it any string - the tree, one file, a hand-written fixture -
/// and see exactly which entities lack a production writer. It masks comments,
/// strings and `#if DEBUG` regions before looking for a call, so prose and
/// seed-only calls can never satisfy it.
enum EntityWriterScanner {

    struct SourceFile {
        let path: String
        let contents: String
    }

    /// One SCHEMA entity heading and the repository write functions that can
    /// create a row of it. The `note` records why those symbols (and not
    /// others) are the writer - it is required and checked.
    struct Spec {
        let heading: String
        let writerSymbols: [String]
        let note: String
    }

    /// An entity allowed to have no production writer, with its reason.
    struct DocumentedException {
        let entity: String
        let reason: String
    }

    /// The exact-heading bindings. Headings that do not map mechanically to a
    /// row type (Entry is an envelope; ServiceRecord & Expense is two rows;
    /// Attachment's heading carries extraction provenance; Preferences and
    /// ExchangeRate carry annotations) are resolved here. A heading with no
    /// spec falls back to a mechanical symbol derivation, so a NEW entity must
    /// bring its own writer or fail.
    static let specs: [Spec] = [
        Spec(heading: "Vehicle",
             writerSymbols: ["upsertVehicle"],
             note: "Add car and the vehicle-detail edit both write through upsertVehicle."),
        Spec(heading: "Entry (common envelope)",
             writerSymbols: ["upsertFillUp", "upsertChargeSession",
                             "upsertServiceRecord", "upsertExpense"],
             note: "Entry is the shared envelope, not a table: an entry is written as one of its "
                 + "four concrete types, each a heading of its own with a writer."),
        Spec(heading: "FillUp",
             writerSymbols: ["upsertFillUp"],
             note: "A fill-up is written by the Confirm/Manual save path and by the rate backfill."),
        Spec(heading: "ChargeSession",
             writerSymbols: ["upsertChargeSession"],
             note: "A charge session is written by the Edit-entry save path and by the rate backfill."),
        Spec(heading: "ServiceRecord & Expense",
             writerSymbols: ["upsertServiceRecord", "upsertExpense"],
             note: "One heading, two persisted rows; each is written by its own save path."),
        Spec(heading: "Reminder",
             writerSymbols: ["upsertReminder"],
             note: "A reminder is written by the reminder form and by completion/recurrence."),
        Spec(heading: "Attachment & extraction provenance",
             writerSymbols: ["upsertAttachment"],
             note: "Attachment is the persisted row; extraction provenance is embedded in it and "
                 + "in the entry, not a table of its own."),
        Spec(heading: "Preferences (app-level settings)",
             writerSymbols: ["upsertPreferences"],
             note: "Preferences is a fixed-id singleton written by the settings/notification paths."),
        Spec(heading: "Station",
             writerSymbols: ["upsertStation", "createStation"],
             note: "createStation is the typed name-to-station door RV.156 added; upsertStation is "
                 + "the repository write it routes through."),
        Spec(heading: "ExchangeRate (local cache, deliberately NOT synced)",
             writerSymbols: ["upsertExchangeRate", "upsertExchangeRates"],
             note: "A local cache, deliberately NOT synced: its writer is the /rates fetch -> "
                 + "persist path (AppRates.persist), never sync and never a user typing a rate.")
    ]

    /// Parse the `###` entity headings between `## Entities` and the next `## `.
    static func entityHeadings(in schemaText: String) -> [String] {
        var headings: [String] = []
        var inEntities = false
        for rawLine in schemaText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                inEntities = (line == "## Entities")
                continue
            }
            if inEntities, line.hasPrefix("### ") {
                headings.append(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            }
        }
        return headings
    }

    /// The writer symbols a heading requires. A spec wins; an unknown heading
    /// (a new entity) falls back to mechanical derivation.
    static func writerSymbols(forHeading heading: String) -> [String] {
        if let spec = specs.first(where: { $0.heading == heading }) { return spec.writerSymbols }
        return genericWriterSymbols(forHeading: heading)
    }

    /// `<Type>` -> `upsert<Type>`/`create<Type>`. Strips a trailing
    /// parenthetical, splits on `&`, and keeps the first capitalized token of
    /// each part (so `Attachment & extraction provenance` -> `Attachment`).
    static func genericWriterSymbols(forHeading heading: String) -> [String] {
        let base = heading.split(separator: "(", maxSplits: 1).first.map(String.init) ?? heading
        var types: [String] = []
        for part in base.split(separator: "&") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.split(separator: " ").first.map(String.init),
                  first.first?.isUppercase == true else { continue }
            types.append(first)
        }
        return types.flatMap { ["upsert\($0)", "create\($0)"] }
    }

    /// Entities whose heading has left the doc while its spec remains.
    static func staleSpecHeadings(schemaText: String) -> [String] {
        let headings = Set(entityHeadings(in: schemaText))
        return specs.map(\.heading).filter { !headings.contains($0) }
    }

    static func noteProblem(in spec: Spec) -> String? {
        guard spec.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "spec for \(spec.heading) carries no note - a bare binding is a skip list"
    }

    static func reasonProblem(in exception: DocumentedException) -> String? {
        guard exception.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "documented exception for \(exception.entity) carries no reason - "
            + "a bare entry is a skip list, not a deliberate exception"
    }

    /// The entities with no production writer. `sources` is the whole corpus;
    /// only files that may host a production writer are consulted.
    static func unwrittenEntities(schemaText: String,
                                  sources: [SourceFile],
                                  exceptions: [DocumentedException] = []) -> [String] {
        let exceptionNames = Set(exceptions.map(\.entity))
        let hosts = sources.filter { isWriterHost(path: $0.path) }
        return entityHeadings(in: schemaText).filter { heading in
            if exceptionNames.contains(heading) { return false }
            let symbols = writerSymbols(forHeading: heading)
            return !hosts.contains { file in
                symbols.contains { containsCall(to: $0, in: file.contents) }
            }
        }
    }

    /// Whether a path may host a production writer: not a test seed/support,
    /// not the import path, not sync, and not the repository write surface or
    /// schema DDL.
    static func isWriterHost(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("TestSeed") || path.contains("TestSupport") { return false }
        if path.contains("/Tests/") || path.contains("/UITests/") { return false }
        if path.contains("/Import/") || name.hasPrefix("Import") { return false }
        if path.contains("/Sync/") || name.contains("Sync") { return false }
        if path.contains("/Persistence/") { return false }
        if name.hasPrefix("Repository") { return false }
        if name == "Migrations.swift" { return false }
        return true
    }

    /// Whether `source` contains a CALL to `symbol` (not a definition, not a
    /// mention). Comments, strings and `#if DEBUG` regions are masked first.
    static func containsCall(to symbol: String, in source: String) -> Bool {
        let masked = maskDebugRegions(maskCommentsAndStrings(source))
        let chars = Array(masked)
        let needle = Array(symbol)
        guard needle.count <= chars.count else { return false }
        var index = 0
        while index <= chars.count - needle.count {
            if Array(chars[index..<(index + needle.count)]) == needle {
                let beforeOK = index == 0 || !isIdentifierCharacter(chars[index - 1])
                let after = index + needle.count
                let afterOK = after < chars.count && chars[after] == "("
                if beforeOK, afterOK, !isFunctionDefinition(before: index, in: chars) {
                    return true
                }
            }
            index += 1
        }
        return false
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// True when the token immediately before `index` (skipping whitespace) is
    /// `func`, so `public func upsertStation(` is a declaration, not a call.
    private static func isFunctionDefinition(before index: Int, in chars: [Character]) -> Bool {
        var cursor = index - 1
        while cursor >= 0, chars[cursor] == " " || chars[cursor] == "\t" { cursor -= 1 }
        let end = cursor + 1
        while cursor >= 0, isIdentifierCharacter(chars[cursor]) { cursor -= 1 }
        return String(chars[(cursor + 1)..<end]) == "func"
    }

    // MARK: - Masking

    /// Blank comments and string literals, preserving length and newlines, so a
    /// writer name in prose can never be mistaken for a call.
    private static func maskCommentsAndStrings(_ source: String) -> String {
        let characters = Array(source)
        var output = characters
        var index = 0
        while index < characters.count {
            if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                while index < characters.count, characters[index] != "\n" {
                    output[index] = " "
                    index += 1
                }
                continue
            }
            if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                output[index] = " "
                output[index + 1] = " "
                index += 2
                var closed = false
                while index < characters.count {
                    if characters[index] == "*", index + 1 < characters.count,
                       characters[index + 1] == "/" {
                        output[index] = " "
                        output[index + 1] = " "
                        index += 2
                        closed = true
                        break
                    }
                    output[index] = " "
                    index += 1
                }
                if !closed { break }
                continue
            }
            if characters[index] == "\"" {
                index = maskString(in: characters, output: &output, index: index)
                continue
            }
            index += 1
        }
        return String(output)
    }

    private static func maskString(in characters: [Character], output: inout [Character],
                                   index start: Int) -> Int {
        var index = start
        if index + 2 < characters.count,
           characters[index + 1] == "\"", characters[index + 2] == "\"" {
            for offset in 0..<3 { output[index + offset] = " " }
            index += 3
            while index < characters.count {
                if index + 2 < characters.count,
                   characters[index] == "\"", characters[index + 1] == "\"",
                   characters[index + 2] == "\"" {
                    for offset in 0..<3 { output[index + offset] = " " }
                    return index + 3
                }
                output[index] = " "
                index += 1
            }
            return index
        }
        output[index] = " "
        index += 1
        while index < characters.count {
            if characters[index] == "\\" {
                output[index] = " "
                if index + 1 < characters.count {
                    output[index + 1] = " "
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if characters[index] == "\"" {
                output[index] = " "
                return index + 1
            }
            output[index] = " "
            index += 1
        }
        return index
    }

    private enum Branch { case debugTrue, debugFalse, neutral }

    /// Blank regions compiled only in DEBUG builds. `#if DEBUG`'s true branch
    /// and `#if !DEBUG`'s else branch are masked; `#else` of `#if DEBUG` is
    /// release code and stays.
    private static func maskDebugRegions(_ source: String) -> String {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var stack: [Branch] = []
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if applyDirective(trimmed, to: &stack) { continue }
            if stack.contains(.debugTrue) {
                lines[index] = String(repeating: " ", count: lines[index].count)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Updates the conditional stack for one directive line. Returns true when
    /// the line was a directive and must not be scanned as code.
    private static func applyDirective(_ trimmed: String, to stack: inout [Branch]) -> Bool {
        if trimmed.hasPrefix("#if") {
            stack.append(branch(forCondition: trimmed))
            return true
        }
        if trimmed.hasPrefix("#else") {
            flipTop(of: &stack)
            return true
        }
        if trimmed.hasPrefix("#endif") {
            if !stack.isEmpty { stack.removeLast() }
            return true
        }
        return false
    }

    private static func branch(forCondition condition: String) -> Branch {
        if condition.contains("!DEBUG") { return .debugFalse }
        if condition.contains("DEBUG") { return .debugTrue }
        return .neutral
    }

    private static func flipTop(of stack: inout [Branch]) {
        guard let top = stack.indices.last else { return }
        switch stack[top] {
        case .debugTrue: stack[top] = .debugFalse
        case .debugFalse: stack[top] = .debugTrue
        case .neutral: break
        }
    }
}
