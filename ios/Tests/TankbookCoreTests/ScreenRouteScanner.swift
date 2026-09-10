import Foundation

/// The RV.162 scanner: a pure function over the SCREENMAP doc and the app's
/// source text, so a test can feed it any string - the real tree, a fixture, a
/// deliberately-broken doc - and see which screens have no non-DEBUG production
/// door. It exists because `PJ.4` shipped a screen whose only route was gated
/// on a DEBUG flag: the route existed, compiled, and every UI suite navigated
/// to it through `-presentScreen`, so a green suite proved nothing about a
/// Release build.
///
/// Two rules shape it:
///   1. A route inside `#if DEBUG` (or in `DebugLaunch.swift`, or a test seed)
///      is not a door. `maskCommentsAndStrings` + `maskDebugRegions` blank those
///      regions before a witness is looked for, and the plumbing files
///      (`Routes.swift`, `Destinations.swift`, `DebugLaunch.swift`) are not door
///      hosts - a destination map or an enum case is not a way in.
///   2. A screen's witness is a literal source fragment naming its door (a
///      `NavigationLink(value:)`, a `presentSheet(...)`, a modal assignment).
///      The binding table (`ScreenRouteBindings`) is deliberately reasoned and
///      annotated, the same discipline RV.163/RV.167 use: a binding with no
///      note is a skip list.
///
/// What it does NOT check is graph reachability: it proves a non-DEBUG door
/// exists, not that the view containing it is itself reachable from a tab root,
/// and not that a runtime condition guarding the door can ever be true. That
/// limit is stated in the guard test and in `docs/TESTING.md`.
enum ScreenRouteScanner {

    struct SourceFile {
        let path: String
        let contents: String
    }

    /// One SCREENMAP screen and the source fragments that prove a production
    /// door exists. The `note` records which door the witnesses are and why -
    /// it is required and checked, so the table cannot degrade into a skip list.
    struct Binding {
        let screen: String
        let witnesses: [String]
        let note: String
    }

    /// A screen the doc records as legitimately having no production route,
    /// with the reason. Paywall is the only one today.
    struct MarkedScreen {
        let screen: String
        let reason: String
    }

    static let inventoryHeading = "## Per-screen index"
    static let markerHeading = "### Screens with no production route"

    // MARK: - Doc parsing

    /// The per-screen index's first column, normalised: markdown bold and
    /// bracketed version markers stripped, the parenthetical qualifier dropped,
    /// whitespace collapsed. The section ends at the next heading, so the
    /// later `###` prose and its tables are never mistaken for the index.
    static func screenNames(in doc: String) -> [String] {
        tableRows(after: inventoryHeading, in: doc).compactMap { cells in
            guard let first = cells.first else { return nil }
            let name = normalise(first)
            guard !name.isEmpty, name.lowercased() != "screen" else { return nil }
            return name
        }
    }

    /// The marker table's rows: screen and reason.
    static func markedScreens(in doc: String) -> [MarkedScreen] {
        tableRows(after: markerHeading, in: doc).compactMap { cells in
            guard cells.count >= 2 else { return nil }
            let screen = normalise(cells[0])
            guard !screen.isEmpty, screen.lowercased() != "screen" else { return nil }
            return MarkedScreen(screen: screen, reason: cells[1])
        }
    }

    /// The cells of each `|` row between `heading` and the next heading.
    private static func tableRows(after heading: String, in doc: String) -> [[String]] {
        guard let start = doc.range(of: heading) else { return [] }
        var rows: [[String]] = []
        for rawLine in doc[start.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { break }
            guard line.hasPrefix("|") else { continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            // Drop the empty leading/trailing cells a `| a | b |` row produces.
            let trimmed = cells.dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
            guard !trimmed.isEmpty else { continue }
            if trimmed.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
            rows.append(trimmed)
        }
        return rows
    }

    static func normalise(_ cell: String) -> String {
        var value = cell.replacingOccurrences(of: "**", with: "")
        value = value.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "",
                                           options: .regularExpression)
        if let qualifier = value.range(of: " (") {
            value = String(value[..<qualifier.lowerBound])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.split(separator: " ").joined(separator: " ")
    }

    // MARK: - The reachability question

    /// Screens in the index with neither a live production door nor a reasoned
    /// marker. A screen the index does not bind and does not mark is reported -
    /// that is how a newly written screen with no route fails.
    static func unreachableScreens(doc: String, sources: [SourceFile]) -> [String] {
        let markedNames = Set(markedScreens(in: doc).map(\.screen))
        return screenNames(in: doc).filter { screen in
            if markedNames.contains(screen) { return false }
            guard let binding = bindings.first(where: { $0.screen == screen }) else { return true }
            return !hasProductionDoor(for: binding, in: sources)
        }
    }

    static func hasProductionDoor(for binding: Binding, in sources: [SourceFile]) -> Bool {
        hasProductionDoor(forWitnesses: binding.witnesses, in: sources)
    }

    static func hasProductionDoor(forWitnesses witnesses: [String], in sources: [SourceFile]) -> Bool {
        let hosts = sources.filter { isDoorHost(path: $0.path) }
        return hosts.contains { file in
            let masked = maskDebugRegions(maskCommentsAndStrings(file.contents))
            return witnesses.contains { maskedContains($0, in: masked) }
        }
    }

    /// Whether a path may host a production door: not a test seed/support, not
    /// a test file, and not the navigation plumbing. `Routes.swift` defines the
    /// cases, `Destinations.swift` maps a case to a view, and `DebugLaunch.swift`
    /// is DEBUG-only - none of the three is a way a user gets in.
    static func isDoorHost(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("TestSeed") || path.contains("TestSupport") { return false }
        if path.contains("/Tests/") || path.contains("/UITests/") { return false }
        if name == "DebugLaunch.swift" || name == "Routes.swift" || name == "Destinations.swift" {
            return false
        }
        return true
    }

    // MARK: - Self-checks

    static func noteProblem(in binding: Binding) -> String? {
        guard binding.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "binding for \(binding.screen) carries no note - a bare binding is a skip list"
    }

    static func reasonProblem(in marker: MarkedScreen) -> String? {
        guard marker.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "marker for \(marker.screen) carries no reason - a bare entry is a skip list, "
            + "not a recorded decision"
    }

    /// Bindings whose screen has left the per-screen index.
    static func staleBindings(in doc: String) -> [String] {
        let names = Set(screenNames(in: doc))
        return bindings.map(\.screen).filter { !names.contains($0) }
    }

    /// Markers whose screen is not named anywhere else in the doc - a marker
    /// for a screen the map no longer carries is stale.
    static func staleMarkers(in doc: String) -> [String] {
        let body = docRemovingMarkerSection(doc)
        return markedScreens(in: doc).map(\.screen).filter { screen in
            body.range(of: screen, options: .caseInsensitive) == nil
        }
    }

    private static func docRemovingMarkerSection(_ doc: String) -> String {
        guard let start = doc.range(of: markerHeading) else { return doc }
        let remainder = doc[start.upperBound...]
        let end = remainder.range(of: "\n#").map { remainder.index($0.lowerBound, offsetBy: 1) }
            ?? doc.endIndex
        var body = doc
        body.replaceSubrange(start.lowerBound..<end, with: "")
        return body
    }

    // MARK: - Matching

    /// Whether `witness` occurs in `masked` and is not the prefix of a longer
    /// identifier (`Route.reminders` must not match `Route.remindersAll`).
    static func maskedContains(_ witness: String, in masked: String) -> Bool {
        let haystack = Array(masked)
        let needle = Array(witness)
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        var index = 0
        while index <= haystack.count - needle.count {
            if Array(haystack[index..<(index + needle.count)]) == needle {
                let after = index + needle.count
                // A witness ending in an identifier character must not be the
                // prefix of a longer identifier (`Route.reminders` vs
                // `Route.remindersAll`); one ending in `(`/`)`/space is already
                // delimited.
                if !isIdentifierCharacter(needle[needle.count - 1])
                    || after >= haystack.count
                    || !isIdentifierCharacter(haystack[after]) {
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

    // MARK: - Masking

    /// Blank comments and string literals, preserving length and newlines, so a
    /// door named in prose can never satisfy the scan.
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
