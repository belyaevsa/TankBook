import Foundation

/// The RV.165 scanner: a pure function over the cold-launch journey suite's own
/// source text, so a test can feed it the real file or a hand-written fixture
/// and see which launch arguments are navigation seeds in disguise.
///
/// The journey suite exists to walk the view graph by tapping, because the rest
/// of the UI suite teleports into screens with `-presentScreen` and friends and
/// therefore cannot discover an unreachable screen. Without a guard, the first
/// journey that is awkward to walk will reach for the same shortcut and the
/// suite will quietly regress to the shape it replaced - which is the whole
/// defect this row is about.
///
/// Two rules shape it:
///   1. A NAVIGATION seed is never allowed, however it is spelled:
///      `-presentScreen`, any other `-present*` except the fresh-install
///      precondition `-presentWelcome`, `-openFirst*`, and `-select*Tab`.
///   2. Every other `-`-prefixed argument must be on the reasoned allowlist,
///      which records WHY it is data or environment rather than navigation.
///      The brief permits seeds for data VOLUME, never for navigation; a seed
///      for a value the journey exists to create is the defect wearing the
///      row's own name. The allowlist is small and each entry carries a
///      required reason - a bare entry fails the guard's own self-check, the
///      same discipline RV.163's exception list uses.
///
/// Comments are masked before the scan so prose that names a forbidden flag is
/// never mistaken for a call site. String literals are deliberately NOT masked
/// (they are the subject); the scanner extracts them and looks at their text.
enum JourneyLaunchArgumentScanner {

    struct SourceFile {
        let path: String
        let contents: String
    }

    /// One launch argument the journey suite may pass, with the reason it is
    /// data or environment and not navigation. `isDataVolume` records whether
    /// the brief's "data VOLUME" allowance covers it.
    struct AllowedFlag {
        let flag: String
        let reason: String
        let isDataVolume: Bool
    }

    struct Violation {
        let path: String
        let line: Int
        let argument: String
        let reason: String
    }

    /// The reasoned allowlist. Every entry is used by the real suite; the
    /// stale check below fails when one is not, so the list cannot grow into a
    /// dumping ground. `-presentWelcome` is the one `-present*` flag that is
    /// not navigation: it runs the real onboarding gate and seeds nothing.
    static let allowedFlags: [AllowedFlag] = [
        AllowedFlag(flag: "-homeResetDatabase",
                    reason: "the database reset; a journey starts from an empty database",
                    isDataVolume: false),
        AllowedFlag(flag: "-presentWelcome",
                    reason: "the fresh-install precondition: runs the REAL onboarding gate even "
                        + "under the seed harness, seeds no data and navigates nowhere",
                    isDataVolume: false),
        AllowedFlag(flag: "-cameraStatus",
                    reason: "environment: the simulator has no camera, so the permission status "
                        + "is forced to reach the capture surface",
                    isDataVolume: false),
        AllowedFlag(flag: "-captureFixtureImage",
                    reason: "data: substitutes the untestable camera frame with a corpus image; "
                        + "the real OCR pipeline still runs over it",
                    isDataVolume: true),
        AllowedFlag(flag: "-seedFillUpScan",
                    reason: "data: a deterministic local parse so the save is not gated on OCR "
                        + "accuracy; it substitutes only the parse, never a value the user did not see",
                    isDataVolume: true),
        AllowedFlag(flag: "-feedbackQueueReset",
                    reason: "data: empties the persisted feedback queue file, which outlives the "
                        + "database reset",
                    isDataVolume: true),
        AllowedFlag(flag: "-feedbackTransportSuccess",
                    reason: "environment: the app's stub transport gives the Send tap a "
                        + "deterministic terminal outcome; it navigates nowhere and seeds no data",
                    isDataVolume: false),
        AllowedFlag(flag: "-AppleLanguages",
                    reason: "environment: the RU pass",
                    isDataVolume: false),
        AllowedFlag(flag: "-AppleLocale",
                    reason: "environment: the RU pass",
                    isDataVolume: false)
    ]

    // MARK: - The reachability question

    /// The forbidden flags in `sources`, each naming its file, line and reason.
    static func violations(in sources: [SourceFile],
                           allowed: [AllowedFlag] = allowedFlags) -> [Violation] {
        let allowedNames = Set(allowed.map(\.flag))
        var found: [Violation] = []
        for file in sources {
            for (value, line) in stringLiterals(in: maskComments(file.contents)) {
                guard isFlag(value) else { continue }
                guard let reason = violationReason(for: value, allowed: allowedNames) else { continue }
                found.append(Violation(path: file.path, line: line, argument: value, reason: reason))
            }
        }
        return found
    }

    /// Why `argument` is forbidden, or nil when it is allowed. A navigation
    /// seed is rejected even if it somehow reached the allowlist; every other
    /// unknown flag is rejected by default.
    static func violationReason(for argument: String, allowed: Set<String>) -> String? {
        if argument == "-presentScreen" {
            return "`-presentScreen` teleports into a screen and can never prove it is reachable"
        }
        if argument.hasPrefix("-present") && argument != "-presentWelcome" {
            return "a `-present*` flag teleports into a screen; only the fresh-install "
                + "precondition `-presentWelcome` is allowed"
        }
        if argument.hasPrefix("-openFirst") {
            return "`-openFirst*` opens a screen's own content, bypassing the walk to it"
        }
        if argument.hasPrefix("-select") && argument.hasSuffix("Tab") {
            return "`-select*Tab` pre-selects a tab, bypassing the tab tap"
        }
        if argument.hasPrefix("-seed") && !allowed.contains(argument) {
            return "a `-seed*` flag is not on the data allowlist"
        }
        if !allowed.contains(argument) {
            return "a launch argument not on the reasoned allowlist"
        }
        return nil
    }

    // MARK: - Self-checks

    static func reasonProblem(in allowed: AllowedFlag) -> String? {
        guard allowed.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "allowlist entry \(allowed.flag) carries no reason - a bare entry is a skip list, "
            + "not a recorded decision"
    }

    /// Allowlist entries the suite no longer uses. A stale entry is a hole
    /// waiting for the next journey to lean on.
    static func staleAllowlistEntries(in allowed: [AllowedFlag],
                                      usedArguments: Set<String>) -> [String] {
        allowed.map(\.flag).filter { !usedArguments.contains($0) }
    }

    /// Every flag-like literal in `sources` - the set the stale check compares
    /// against.
    static func usedArguments(in sources: [SourceFile]) -> Set<String> {
        var used: Set<String> = []
        for file in sources {
            for (value, _) in stringLiterals(in: maskComments(file.contents)) where isFlag(value) {
                used.insert(value)
            }
        }
        return used
    }

    // MARK: - Lexing

    /// A launch argument starts with `-` followed by a letter, so a negative
    /// number or a lone dash is not mistaken for a flag.
    static func isFlag(_ value: String) -> Bool {
        guard value.hasPrefix("-"), value.count > 1 else { return false }
        guard let second = value.dropFirst().first else { return false }
        return second.isLetter
    }

    /// Every string literal and its 1-based line number, with escapes handled.
    static func stringLiterals(in source: String) -> [(value: String, line: Int)] {
        let characters = Array(source)
        var results: [(String, Int)] = []
        var line = 1
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\n" {
                line += 1
                index += 1
                continue
            }
            guard character == "\"" else {
                index += 1
                continue
            }
            let startLine = line
            var value = ""
            index += 1
            while index < characters.count {
                let current = characters[index]
                if current == "\\", index + 1 < characters.count {
                    value.append(characters[index + 1])
                    if characters[index + 1] == "\n" { line += 1 }
                    index += 2
                    continue
                }
                if current == "\"" {
                    index += 1
                    break
                }
                if current == "\n" { line += 1 }
                value.append(current)
                index += 1
            }
            results.append((value, startLine))
        }
        return results
    }

    /// Blank comments (`//` and `/* */`) while preserving length and newlines,
    /// so prose naming a forbidden flag is never read as code. String literals
    /// are left intact - the scanner's subject is the text inside them.
    static func maskComments(_ source: String) -> String {
        let characters = Array(source)
        var output = characters
        var index = 0
        var inString = false
        while index < characters.count {
            if inString {
                index = skipStringBody(characters, index: index, inString: &inString)
                continue
            }
            if characters[index] == "\"" {
                inString = true
                index += 1
                continue
            }
            if characters[index] == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    index = maskLineComment(characters, output: &output, index: index)
                    continue
                }
                if characters[index + 1] == "*" {
                    index = maskBlockComment(characters, output: &output, index: index)
                    continue
                }
            }
            index += 1
        }
        return String(output)
    }

    /// Advance past a string body (including escapes), flipping `inString` off
    /// at the closing quote.
    private static func skipStringBody(_ characters: [Character], index start: Int,
                                       inString: inout Bool) -> Int {
        var index = start
        if characters[index] == "\\", index + 1 < characters.count { return index + 2 }
        if characters[index] == "\"" { inString = false }
        return index + 1
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
            if characters[index] != "\n" { output[index] = " " }
            index += 1
        }
        return index
    }
}
