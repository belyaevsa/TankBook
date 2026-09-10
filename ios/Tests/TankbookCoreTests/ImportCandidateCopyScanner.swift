import Foundation

/// RV.170 (Half B) - the source-scan guard for `ImportCandidate` copy helpers.
/// `RV.189` was a value dropped between the wire and the conversion: the parser
/// read the station column, the wire carried it, the conversion stamped it and
/// the commit materialised the row - but `ImportBatchMerge.remappingSourceRow`
/// rebuilt the `ImportCandidate` without `station`. Nothing failed, because
/// `ImportCandidate.init` defaults `station` to nil, so omitting it compiles.
///
/// In production an `ImportCandidate` is never built from raw values - the wire
/// path decodes it with `Codable` - so every `ImportCandidate(...)` construction
/// in a production host is a copy helper, and a copy helper must round-trip
/// **every** field of the memberwise init. The scanner parses the init's
/// parameter list from `ImportModels.swift` and reports any construction that
/// omits one, naming the missing field(s). It is deliberately not keyed on
/// `station`: the next field a helper drops is caught the same way.
///
/// The persistence decoder is not a copy host - it restores what was stored -
/// and test seeds are not hosts, so a fixture that builds a candidate from
/// scratch is never mistaken for a production copy.
enum ImportCandidateCopyScanner {

    typealias SourceFile = EntityWriterScanner.SourceFile

    /// One construction that omits at least one init field, named by file,
    /// 1-based line and enclosing function.
    struct Finding: Equatable {
        let path: String
        let line: Int
        let helper: String
        let missing: [String]
    }

    /// A helper allowed to omit a field, with the reason a human wrote. Empty
    /// today - every production copy helper passes every field - but the
    /// mechanism keeps a future deliberate omission a recorded decision rather
    /// than a silent drop.
    struct DocumentedException {
        let helper: String
        let field: String
        let reason: String
    }

    static let typeName = "ImportCandidate"

    // MARK: - The scan

    /// Every production copy that omits an init field, sorted by file and line.
    /// `exceptions` suppress one `helper.field` pair; the real list is empty.
    static func findings(in sources: [SourceFile],
                         initFields: [String],
                         exceptions: [DocumentedException] = []) -> [Finding] {
        guard !initFields.isEmpty else { return [] }
        var found: [Finding] = []
        for file in sources where isCopyHost(path: file.path) {
            let chars = Array(EntityWriterScanner.masked(file.contents))
            for site in constructionSites(in: chars) {
                let labels = Set(argumentLabels(in: chars, openParen: site.paren))
                let helper = enclosingFunctionName(before: site.token, in: chars) ?? "?"
                let missing = initFields.filter { field in
                    !labels.contains(field)
                        && !isExcepted(helper: helper, field: field, in: exceptions)
                }
                if !missing.isEmpty {
                    found.append(Finding(path: file.path,
                                         line: lineNumber(at: site.token, in: chars),
                                         helper: helper, missing: missing))
                }
            }
        }
        return found.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }

    /// The `init` parameter labels of `ImportCandidate`, read from its compiled
    /// declaration in `ImportModels.swift`. The compiled init is the contract
    /// the copy helpers and the decoder agree on, so the comparison is exact.
    static func initFields(in source: String) -> [String] {
        let chars = Array(EntityWriterScanner.masked(source))
        guard let structRange = firstRange(of: Array("struct \(typeName)"), in: chars, from: 0),
              let initRange = firstRange(of: Array("init("), in: chars,
                                         from: structRange.upperBound) else {
            return []
        }
        let open = initRange.upperBound - 1  // the `(` of `init(`
        return argumentLabels(in: chars, openParen: open)
    }

    /// The offsets of `ImportCandidate` tokens followed by a call, with the
    /// offset of the opening parenthesis. A whole-identifier match means
    /// `[ImportCandidate]` or a longer name never reads as a construction.
    static func constructionSites(in chars: [Character]) -> [(token: Int, paren: Int)] {
        let needle = Array(typeName)
        var sites: [(token: Int, paren: Int)] = []
        var index = 0
        while index <= chars.count - needle.count {
            if Array(chars[index..<(index + needle.count)]) == needle,
               index == 0 || !isIdentifier(chars[index - 1]) {
                let after = index + needle.count
                var cursor = after
                while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" {
                    cursor += 1
                }
                if after >= chars.count || !isIdentifier(chars[after]),
                   cursor < chars.count, chars[cursor] == "(" {
                    sites.append((index, cursor))
                }
                index = after
                continue
            }
            index += 1
        }
        return sites
    }

    /// Whether a path may host a copy helper. The decoder/repository surface is
    /// not a host, and neither are test seeds or sync - a copy that exists only
    /// in a fixture or restores a stored row is not a production round-trip.
    static func isCopyHost(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("Seed") || path.contains("TestSupport") { return false }
        if path.contains("/Tests/") || path.contains("/UITests/") { return false }
        if path.contains("/Sync/") || name.contains("Sync") { return false }
        if path.contains("TankbookCore/Persistence/") { return false }
        if name.hasPrefix("Repository") { return false }
        if name == "Migrations.swift" { return false }
        if name.hasPrefix("Records") { return false }
        return true
    }

    // MARK: - Self-checks

    static func reasonProblem(in exception: DocumentedException) -> String? {
        guard exception.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "documented exception for \(exception.helper).\(exception.field) carries no reason - "
            + "a bare entry is a skip list, not a deliberate exception"
    }

    static func isExcepted(helper: String, field: String,
                           in exceptions: [DocumentedException]) -> Bool {
        exceptions.contains { $0.helper == helper && $0.field == field }
    }

    /// Exceptions whose helper.field is no longer reported - the field is passed
    /// again, or the helper is gone. A stale entry hides the next drop.
    static func staleExceptions(findings: [Finding],
                                exceptions: [DocumentedException]) -> [String] {
        exceptions.filter { exception in
            !findings.contains {
                $0.helper == exception.helper && $0.missing.contains(exception.field)
            }
        }.map { "\($0.helper).\($0.field)" }.sorted()
    }

    // MARK: - Lexing

    /// The labels of the top-level arguments of a call whose `(` is at
    /// `openParen`. Nested calls, arrays and closures are stepped over, so a
    /// `:` inside a value (`ImportMoney(amount:)`) is never read as a label.
    static func argumentLabels(in chars: [Character], openParen: Int) -> [String] {
        topLevelArguments(in: chars, openParen: openParen).compactMap(label(of:))
    }

    /// The raw text of each top-level argument between `openParen` and its
    /// matching `)`, in order. Delimiters inside nested containers are kept in
    /// the argument text so `label(of:)` can find the outer colon.
    static func topLevelArguments(in chars: [Character], openParen: Int) -> [String] {
        var arguments: [String] = []
        var current = ""
        var depth = 0
        var index = openParen
        while index < chars.count {
            let character = chars[index]
            if "([{".contains(character) {
                depth += 1
                if depth > 1 { current.append(character) }
            } else if ")]}".contains(character) {
                depth -= 1
                if depth == 0 {
                    arguments.append(current)
                    return arguments
                }
                current.append(character)
            } else if character == ",", depth == 1 {
                arguments.append(current)
                current = ""
            } else if depth >= 1 {
                current.append(character)
            }
            index += 1
        }
        return arguments
    }

    /// The label of one argument segment: the identifier before its first
    /// top-level colon, or nil when the argument is unlabelled.
    static func label(of segment: String) -> String? {
        guard let colon = firstTopLevelColon(in: segment) else { return nil }
        let candidate = segment[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.allSatisfy(isIdentifier) else { return nil }
        return candidate
    }

    /// The index of the first colon in `segment` not nested inside a container.
    static func firstTopLevelColon(in segment: String) -> String.Index? {
        var depth = 0
        var index = segment.startIndex
        while index < segment.endIndex {
            let character = segment[index]
            if "([{".contains(character) {
                depth += 1
            } else if ")]}".contains(character) {
                depth -= 1
            } else if character == ":", depth == 0 {
                return index
            }
            index = segment.index(after: index)
        }
        return nil
    }

    /// The name of the nearest `func` declared before `offset`, or nil when the
    /// construction sits outside any function.
    static func enclosingFunctionName(before offset: Int, in chars: [Character]) -> String? {
        guard offset > 0 else { return nil }
        var cursor = offset - 1
        while cursor >= 0 {
            if chars[cursor] == "c", cursor >= 3,
               chars[cursor - 3] == "f", chars[cursor - 2] == "u", chars[cursor - 1] == "n",
               cursor == 3 || !isIdentifier(chars[cursor - 4]) {
                var index = cursor + 1
                while index < chars.count, chars[index] == " " || chars[index] == "\t" {
                    index += 1
                }
                var name = ""
                while index < chars.count, isIdentifier(chars[index]) {
                    name.append(chars[index])
                    index += 1
                }
                return name.isEmpty ? nil : name
            }
            cursor -= 1
        }
        return nil
    }

    static func lineNumber(at offset: Int, in chars: [Character]) -> Int {
        var line = 1
        var index = 0
        while index < offset, index < chars.count {
            if chars[index] == "\n" { line += 1 }
            index += 1
        }
        return line
    }

    static func firstRange(of needle: [Character], in chars: [Character],
                           from: Int) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= chars.count else { return nil }
        var index = max(0, from)
        while index <= chars.count - needle.count {
            if Array(chars[index..<(index + needle.count)]) == needle {
                return index..<(index + needle.count)
            }
            index += 1
        }
        return nil
    }

    static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
