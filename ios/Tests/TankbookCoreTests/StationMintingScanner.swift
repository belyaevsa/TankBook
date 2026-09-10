import Foundation

/// RV.170 - the source-scan guard for `Station` minting, the other side of
/// `RV.156`. `RV.156` gave the typed path a creation door and `RV.150` made a
/// save stamp `lastUsedAt` and `defaults` on the row; a second `Station(...)`
/// construction outside the one seam would mint a station the suggestion
/// ranking (`docs/JOURNEYS.md` -> J4) cannot rank - the same silent hole
/// `RV.156` was, freshly dug.
///
/// **The canonical seam is `ImportStationResolver.station(for:existing:now:)`
/// in `ImportStation.swift`.** The investigation the row demanded found exactly
/// one production construction site outside the decoder, and it is inside that
/// function. `TankbookRepository.createStation`
/// (`Repository+StationCreate.swift`) is a caller that routes through the
/// resolver, and `ImportStationResolver.missingStations` (the import commit)
/// calls it too; neither constructs a `Station`. The persistence decoder
/// (`Records+Extras.swift`) restores a stored row and is not a creation path -
/// the same discrimination `RV.196`'s field guard had to make.
///
/// The scanner is a pure function over source text: comments, strings and
/// `#if DEBUG` regions are masked first, and the persistence/repository surface
/// (the decoder and the write API) is not a minting host. A `Station(...)`
/// construction anywhere else is reported with its `file:line`.
enum StationMintingScanner {

    typealias SourceFile = EntityWriterScanner.SourceFile

    /// A `Station(...)` construction site, named by file and 1-based line.
    struct Construction: Equatable {
        let path: String
        let line: Int
    }

    /// A path allowed to construct a `Station`, with the reason a human wrote.
    /// The seam itself is allowed structurally (only its own function), so this
    /// list is empty today; a bare entry fails the self-check and an entry that
    /// no longer matches a construction fails the walk.
    struct DocumentedException {
        let path: String
        let reason: String
    }

    /// The one canonical minting seam: the function that constructs the row.
    static let seamPath = "Sources/TankbookCore/Import/ImportStation.swift"
    static let seamFunction = "station"

    // MARK: - The scan

    /// Every `Station(...)` construction in a production host that is not the
    /// canonical seam, sorted by file and line. `exceptions` suppresses a whole
    /// path; the seam is always allowed, so the list stays empty unless a second
    /// legitimate site appears.
    static func unmintedStations(in sources: [SourceFile],
                                 exceptions: [DocumentedException] = []) -> [Construction] {
        let excepted = Set(exceptions.map(\.path))
        var found: [Construction] = []
        for file in sources where isMintingHost(path: file.path) {
            if excepted.contains(file.path) { continue }
            let chars = Array(EntityWriterScanner.masked(file.contents))
            let original = Array(file.contents)
            for hit in stationConstructions(in: chars) {
                let isSeam = file.path == seamPath
                    && enclosingFunctionName(before: hit, in: chars) == seamFunction
                if !isSeam {
                    found.append(Construction(path: file.path,
                                              line: lineNumber(at: hit, in: original)))
                }
            }
        }
        return found.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }

    /// The offsets of `Station(` tokens in `chars` where `Station` is a whole
    /// identifier - so `createStation(`, `upsertStation(` and `StationRow(` are
    /// not constructions.
    static func stationConstructions(in chars: [Character]) -> [Int] {
        let needle = Array("Station(")
        var hits: [Int] = []
        var index = 0
        while index <= chars.count - needle.count {
            if Array(chars[index..<(index + needle.count)]) == needle,
               index == 0 || !isIdentifier(chars[index - 1]) {
                hits.append(index)
            }
            index += 1
        }
        return hits
    }

    /// Whether a path may mint a station. The decoder, the repository write API
    /// and schema DDL are not hosts - they restore or define, never originate.
    /// Test seeds are not hosts: a seed that constructs a `Station` is exactly
    /// the fixture this guard must not be tuned to allowlist.
    static func isMintingHost(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("TestSeed") || path.contains("TestSupport") { return false }
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
        return "documented exception for \(exception.path) carries no reason - "
            + "a bare path is a skip list, not a deliberate exception"
    }

    /// Exception paths that no longer match a construction - the site was
    /// removed or moved back into the seam. A stale entry hides the next hole.
    static func staleExceptions(in sources: [SourceFile],
                                exceptions: [DocumentedException]) -> [String] {
        let flagged = Set(unmintedStations(in: sources).map(\.path))
        return exceptions.map(\.path).filter { !flagged.contains($0) }.sorted()
    }

    // MARK: - Lexing

    /// The name of the nearest `func` declared before `offset`, or nil when the
    /// construction sits outside any function. The seam is a function, not a
    /// file: a second `Station(...)` in `ImportStation.swift` is still flagged.
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

    static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
