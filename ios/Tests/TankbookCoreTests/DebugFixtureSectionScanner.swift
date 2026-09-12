import Foundation

/// The PJ.59 scanner: a pure function over production view source that reports a
/// **section whose only data is a DEBUG launch-argument fixture**.
///
/// The defect it exists for: `RecentlyDeletedView` rendered its "Overwritten by
/// sync" section from `RecentlyDeletedFixtures.fromLaunchArguments()`, so the
/// section existed in every UI test (which passes `-forceSyncOverwritten`) and
/// in no Release build. `ScreenRouteScanner` (RV.162) binds screens to doors and
/// cannot see a section inside a live screen; this is that stated blind spot,
/// mechanised for the one shape that can be read from source text.
///
/// The mechanisable slice is deliberately narrow, and the narrowness is the
/// point:
///   1. A **fixture binding** is a variable assigned from a
///      `…fromLaunchArguments()` call. Only those bind to launch arguments.
///   2. A **section** is a *collection* the view renders from that fixture:
///      `ForEach(<fixture>.<member>)` or an `if … <fixture>.<member>.isEmpty`
///      gate. A fixture boolean that hides a card of static copy is NOT this
///      shape (the S5 archived-returned banner is PJ.40's separate decision).
///
/// Comments and string literals are masked before the scan, so prose naming a
/// fixture is never mistaken for a call site.
///
/// WHAT IT DOES NOT CHECK, stated so it is not overclaimed: it does not parse
/// SwiftUI. A fixture collection rendered through a helper the scanner cannot
/// see (`let rows = fixtures.rows; ForEach(rows)`) is missed, and a fixture
/// boolean gating a whole screen is out of scope. It catches the one shape the
/// row shipped for and fails a regression to it.
enum DebugFixtureSectionScanner {

    struct SourceFile {
        let path: String
        let contents: String
    }

    /// One fixture-backed section: the file, the line the collection is used,
    /// and the fixture member (`fixtures.syncOverwritten`).
    struct GatedSection: Equatable {
        let path: String
        let line: Int
        let member: String
    }

    /// Every fixture-backed section in `sources`, in file/line order. This is
    /// the failing set.
    static func gatedSections(in sources: [SourceFile]) -> [GatedSection] {
        var found: [GatedSection] = []
        for file in sources {
            let masked = maskCommentsAndStrings(file.contents)
            let names = fixtureBindings(in: masked)
            guard !names.isEmpty else { continue }
            var seen = Set<String>()
            for (offset, rawLine) in masked.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(rawLine)
                for name in names {
                    guard let member = collectionMember(of: name, in: line) else { continue }
                    let qualified = "\(name).\(member)"
                    guard seen.insert(qualified).inserted else { continue }
                    found.append(GatedSection(path: file.path, line: offset + 1, member: qualified))
                }
            }
        }
        return found
    }

    // MARK: - Fixture bindings

    /// The variable names assigned from a `…fromLaunchArguments()` call in this
    /// source text, in declaration order.
    static func fixtureBindings(in masked: String) -> [String] {
        var names: [String] = []
        for rawLine in masked.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let call = line.range(of: ".fromLaunchArguments(") else { continue }
            let before = line[..<call.lowerBound]
            guard let equals = before.lastIndex(of: "=") else { continue }
            let lhs = before[..<equals]
            let name = lhs.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
                .last.map(String.init) ?? ""
            guard !name.isEmpty, !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    // MARK: - The section signal

    /// The fixture member rendered as a collection on this line, or nil. A
    /// `ForEach(<fixture>.<member>)` render or an `<fixture>.<member>.isEmpty`
    /// gate is the shape; a plain `<fixture>.<member>` read is not.
    static func collectionMember(of name: String, in line: String) -> String? {
        var searchStart = line.startIndex
        while let range = line.range(of: name + ".", range: searchStart..<line.endIndex) {
            searchStart = range.upperBound
            let rest = line[range.upperBound...]
            let member = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            guard !member.isEmpty else { continue }
            let after = rest.dropFirst(member.count)
            let before = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if before.hasSuffix("ForEach(") || after.hasPrefix(".isEmpty") {
                return String(member)
            }
        }
        return nil
    }

    // MARK: - Masking

    /// Blank comments and string literals, preserving length and newlines, so a
    /// fixture named in prose or in a launch-argument string is not a call site.
    static func maskCommentsAndStrings(_ source: String) -> String {
        let characters = Array(source)
        var output = characters
        var index = 0
        while index < characters.count {
            if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                index = maskLineComment(characters, output: &output, index: index)
                continue
            }
            if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                index = maskBlockComment(characters, output: &output, index: index)
                continue
            }
            if characters[index] == "\"" {
                index = maskString(characters, output: &output, index: index)
                continue
            }
            index += 1
        }
        return String(output)
    }

    private static func maskLineComment(_ characters: [Character], output: inout [Character],
                                        index start: Int) -> Int {
        var index = start
        while index < characters.count, characters[index] != "\n" {
            output[index] = " "
            index += 1
        }
        return index
    }

    private static func maskBlockComment(_ characters: [Character], output: inout [Character],
                                         index start: Int) -> Int {
        var index = start
        output[index] = " "
        output[index + 1] = " "
        index += 2
        while index < characters.count {
            if characters[index] == "*", index + 1 < characters.count,
               characters[index + 1] == "/" {
                output[index] = " "
                output[index + 1] = " "
                return index + 2
            }
            output[index] = " "
            index += 1
        }
        return index
    }

    private static func maskString(_ characters: [Character], output: inout [Character],
                                   index start: Int) -> Int {
        var index = start
        output[index] = " "
        index += 1
        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count {
                output[index] = " "
                output[index + 1] = " "
                index += 2
                continue
            }
            if characters[index] == "\"" {
                output[index] = " "
                return index + 1
            }
            if characters[index] != "\n" { output[index] = " " }
            index += 1
        }
        return index
    }
}
