import Foundation

/// RV.171 - the source-scan guard over the receipt-persistence seam.
///
/// The family this guards is the most expensive shape in the project: a scanned
/// save threw its photograph away on one surface while another kept it, because
/// the binding of an entry to its **attachment**, its **provenance** and its
/// **`purchaseGroupId`** was a convention rather than a checked one. `PJ.28` fixed
/// the expense scan, its fence stopped there, `RV.149` had to be filed for the
/// fill-up, and `RV.149` fenced out the grouped case, so `RV.173` had to be filed
/// for the expense siblings. Each fix was correct and each left the next copy
/// unprotected.
///
/// **The canonical seam, decided by the investigation this row demanded, is
/// `ScannedSavePlan.binding(_:)` composed with `ScannedSavePlan.expenses(from:)`.**
/// `binding(_:)` rebinds the plan to the id the photo write ACTUALLY produced
/// (`ReceiptWriteOutcome.sharedID`); `expenses(from:)` is the one place that
/// stamps attachment + provenance + `purchaseGroupId` onto the accepted expense
/// rows of one mixed receipt. `ScannedSavePlanner.plan(...)` mints the intended
/// plan; the write outcome reports what the disk got. A production save must call
/// `.expenses(from:)` only on a plan that went through `.binding(_:)`, and must
/// not hand-roll a second binding.
///
/// The investigation found exactly **one** production `.expenses(from:)` call
/// site, and it is bound. The single-expense scan path
/// (`ExpenseEntryView.save` -> `ExpenseReceiptWrite.write`) is a distinct shape,
/// not a second canonical seam: one row, one write, and the id comes from the
/// write's return value - never from a shared plan - so the dangling-id defect
/// RV.173 fixed cannot arise there. The typed-attach paths carry `.manual`
/// provenance and are not scanned saves.
///
/// The scanner is a pure function over source text: comments, strings and
/// `#if DEBUG` regions are masked first, and seeds, tests, sync and the
/// persistence surface are not hosts. It reports two shapes:
///   - `.unboundRowBuilder` - a `.expenses(from:)` call whose enclosing function
///     never binds a plan to a `ReceiptWriteOutcome.sharedID`. This is RV.173's
///     pre-fix wiring exactly.
///   - `.secondBindingSite` - a `ScannedSavePlan(...)` construction with a scan
///     provenance outside the factory/rebind, or a read of the plan's
///     `sharedAttachmentIDs` outside the seam. A hand-rolled copy of the binding.
///   - `.thirdReceiptBuilder` - a receipt `Attachment` row construction (an
///     `Attachment(...)` that passes `extractionMeta:`) outside the two
///     canonical builders RV.209 settled. RV.209 found the save builder
///     (`writeReceiptPhoto`) and the out-of-save builder
///     (`ReceiptAttachmentWriter.write`) building `extractionMeta` differently
///     and decided the difference is deliberate (the save has a plan, the
///     out-of-save path has only a `FuelExtraction`); this shape is what stops a
///     third receipt-persistence path appearing silently. The discriminator is
///     `extractionMeta:` - vehicle photos and invoice pages build `Attachment`
///     rows without it, so they are not receipt rows.
enum ReceiptBindingScanner {

    typealias SourceFile = EntityWriterScanner.SourceFile

    /// The shape a finding reports.
    enum Kind: String, Equatable {
        case unboundRowBuilder
        case secondBindingSite
        case thirdReceiptBuilder
    }

    /// One binding site that bypasses the canonical seam, named by file, 1-based
    /// line, enclosing function and shape.
    struct Finding: Equatable {
        let path: String
        let line: Int
        let function: String
        let kind: Kind
    }

    /// A site allowed to bind outside the seam, with the reason a human wrote.
    /// Empty today - the seam is allowed structurally - but a future deliberate
    /// site is a recorded decision rather than a silent drop. A bare entry fails
    /// the self-check and a stale one fails the walk.
    struct DocumentedException {
        let path: String
        let function: String
        let reason: String
    }

    /// The one canonical seam.
    static let seamPath = "Sources/TankbookCore/Domain/ScannedSavePlan.swift"
    static let rowBuilderFunction = "expenses"
    static let rebindFunction = "binding"
    static let factoryFunction = "plan"
    static let bindingAccessor = "sharedAttachmentIDs"
    /// The only accessor that yields the id a photo write actually produced.
    static let effectiveIDAccessor = "sharedID"
    /// RV.209: the two canonical receipt `Attachment` row builders. Both pass
    /// `extractionMeta:` - the argument that distinguishes a receipt row from a
    /// vehicle photo or an invoice page - so a third construction carrying it is
    /// a second receipt-persistence path.
    static let receiptRowType = "Attachment"
    static let receiptMetaArgument = "extractionMeta"
    static let canonicalReceiptRowBuilders: [(path: String, function: String)] = [
        ("App/Sources/ConfirmManual/ManualFillUpReceiptSave.swift", "writeReceiptPhoto"),
        ("App/Sources/ConfirmManual/ReceiptAttachSupport.swift", "write")
    ]

    // MARK: - The scan

    /// Every production binding that bypasses the canonical seam, sorted by file
    /// and line. `exceptions` suppress one `path` + `function` pair; the real
    /// list is empty.
    static func findings(in sources: [SourceFile],
                         exceptions: [DocumentedException] = []) -> [Finding] {
        var found: [Finding] = []
        for file in sources where isReceiptHost(path: file.path) {
            found.append(contentsOf: findings(in: file, exceptions: exceptions))
        }
        return found.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }

    /// Every bypass in one file, in source order.
    static func findings(in file: SourceFile,
                         exceptions: [DocumentedException]) -> [Finding] {
        let chars = Array(EntityWriterScanner.masked(file.contents))
        let bound = functionsBindingEffectivePlan(in: chars)
        return unboundRowBuilders(in: file, chars: chars, boundFunctions: bound,
                                  exceptions: exceptions)
            + scanProvenanceConstructions(in: file, chars: chars, exceptions: exceptions)
            + handRolledAccessorReads(in: file, chars: chars, exceptions: exceptions)
            + thirdReceiptBuilders(in: file, chars: chars)
    }

    /// RV.209: an `Attachment(...)` row construction that carries
    /// `extractionMeta:` outside the two canonical builders. The check is over
    /// source text, so a new receipt-persistence path cannot appear without
    /// either routing through one of the canonical builders or extending the
    /// canonical list here with a reason.
    private static func thirdReceiptBuilders(in file: SourceFile,
                                             chars: [Character]) -> [Finding] {
        typeConstructions(named: receiptRowType, in: chars).compactMap { paren in
            guard argumentValues(in: chars, openParen: paren)[receiptMetaArgument] != nil else {
                return nil
            }
            let function = enclosingFunctionName(before: paren, in: chars) ?? "?"
            if canonicalReceiptRowBuilders.contains(where: {
                $0.path == file.path && $0.function == function
            }) {
                return nil
            }
            return Finding(path: file.path, line: lineNumber(at: paren, in: chars),
                           function: function, kind: .thirdReceiptBuilder)
        }
    }

    private static func unboundRowBuilders(in file: SourceFile, chars: [Character],
                                           boundFunctions: Set<String>,
                                           exceptions: [DocumentedException]) -> [Finding] {
        memberCallOpenParens(named: rowBuilderFunction, in: chars).compactMap { paren in
            guard firstArgumentLabel(openParen: paren, in: chars) == "from" else { return nil }
            let function = enclosingFunctionName(before: paren, in: chars) ?? "?"
            if file.path == seamPath, function == rowBuilderFunction { return nil }
            if isExcepted(path: file.path, function: function, in: exceptions) { return nil }
            if boundFunctions.contains(function) { return nil }
            return Finding(path: file.path, line: lineNumber(at: paren, in: chars),
                           function: function, kind: .unboundRowBuilder)
        }
    }

    private static func scanProvenanceConstructions(in file: SourceFile, chars: [Character],
                                                    exceptions: [DocumentedException]) -> [Finding] {
        typeConstructions(named: "ScannedSavePlan", in: chars).compactMap { paren in
            let function = enclosingFunctionName(before: paren, in: chars) ?? "?"
            if file.path == seamPath, function == factoryFunction || function == rebindFunction {
                return nil
            }
            if isExcepted(path: file.path, function: function, in: exceptions) { return nil }
            guard let provenance = argumentValues(in: chars, openParen: paren)["provenance"],
                  isScanProvenance(provenance) else { return nil }
            return Finding(path: file.path, line: lineNumber(at: paren, in: chars),
                           function: function, kind: .secondBindingSite)
        }
    }

    private static func handRolledAccessorReads(in file: SourceFile, chars: [Character],
                                                exceptions: [DocumentedException]) -> [Finding] {
        guard file.path != seamPath else { return [] }
        return identifierOffsets(bindingAccessor, in: chars).compactMap { offset in
            let function = enclosingFunctionName(before: offset, in: chars) ?? "?"
            if isExcepted(path: file.path, function: function, in: exceptions) { return nil }
            return Finding(path: file.path, line: lineNumber(at: offset, in: chars),
                           function: function, kind: .secondBindingSite)
        }
    }

    /// Whether a path may host a receipt binding. Seeds, tests, sync and the
    /// persistence surface restore or reproduce rows; they never originate the
    /// binding a user's scanned save writes.
    static func isReceiptHost(path: String) -> Bool {
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
        return "documented exception for \(exception.path):\(exception.function) carries no reason - "
            + "a bare entry is a skip list, not a deliberate exception"
    }

    static func isExcepted(path: String, function: String,
                           in exceptions: [DocumentedException]) -> Bool {
        exceptions.contains { $0.path == path && $0.function == function }
    }

    /// Exceptions whose path + function no longer bypasses the seam - the site
    /// was routed through `binding(_:)`, or it is gone. A stale entry hides the
    /// next copy.
    static func staleExceptions(in sources: [SourceFile],
                                exceptions: [DocumentedException]) -> [String] {
        let flagged = findings(in: sources)
        return exceptions.filter { exception in
            !flagged.contains {
                $0.path == exception.path && $0.function == exception.function
            }
        }.map { "\($0.path):\($0.function)" }.sorted()
    }

    // MARK: - Witnesses

    /// The enclosing functions that bind a plan to the effective id the write
    /// produced - a `.binding(` call whose first argument reads
    /// `ReceiptWriteOutcome.sharedID`. This is the contract, not the spelling:
    /// binding to the plan's own intended id does not count.
    static func functionsBindingEffectivePlan(in chars: [Character]) -> Set<String> {
        var names: Set<String> = []
        for paren in memberCallOpenParens(named: rebindFunction, in: chars) {
            let arguments = ImportCandidateCopyScanner.topLevelArguments(in: chars, openParen: paren)
            guard let first = arguments.first, first.contains(".\(effectiveIDAccessor)") else {
                continue
            }
            if let function = enclosingFunctionName(before: paren, in: chars) {
                names.insert(function)
            }
        }
        return names
    }

    /// The offsets of `.<name>(` member calls, at the opening parenthesis. A
    /// whole-identifier match means a longer name never reads as a call.
    static func memberCallOpenParens(named name: String, in chars: [Character]) -> [Int] {
        let needle = Array(name)
        guard needle.count <= chars.count else { return [] }
        var result: [Int] = []
        var index = 1
        while index <= chars.count - needle.count {
            if chars[index - 1] == ".",
               Array(chars[index..<(index + needle.count)]) == needle {
                let after = index + needle.count
                if after >= chars.count || !isIdentifier(chars[after]) {
                    var cursor = after
                    while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" {
                        cursor += 1
                    }
                    if cursor < chars.count, chars[cursor] == "(" {
                        result.append(cursor)
                    }
                }
            }
            index += 1
        }
        return result
    }

    /// The offsets of `TypeName(` constructions, at the opening parenthesis. A
    /// whole-identifier match means `[TypeName]` or a longer name never reads as
    /// a construction.
    static func typeConstructions(named name: String, in chars: [Character]) -> [Int] {
        let needle = Array(name)
        guard needle.count <= chars.count else { return [] }
        var result: [Int] = []
        var index = 0
        while index <= chars.count - needle.count {
            if Array(chars[index..<(index + needle.count)]) == needle,
               index == 0 || !isIdentifier(chars[index - 1]) {
                let after = index + needle.count
                if after >= chars.count || !isIdentifier(chars[after]) {
                    var cursor = after
                    while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" {
                        cursor += 1
                    }
                    if cursor < chars.count, chars[cursor] == "(" {
                        result.append(cursor)
                    }
                }
                index = after
                continue
            }
            index += 1
        }
        return result
    }

    /// The offsets of a whole-identifier token in `chars`.
    static func identifierOffsets(_ name: String, in chars: [Character]) -> [Int] {
        let needle = Array(name)
        guard needle.count <= chars.count else { return [] }
        var result: [Int] = []
        var index = 0
        while index <= chars.count - needle.count {
            if Array(chars[index..<(index + needle.count)]) == needle,
               index == 0 || !isIdentifier(chars[index - 1]) {
                let after = index + needle.count
                if after >= chars.count || !isIdentifier(chars[after]) {
                    result.append(index)
                }
            }
            index += 1
        }
        return result
    }

    /// The label of the first argument of a call whose `(` is at `openParen`.
    static func firstArgumentLabel(openParen: Int, in chars: [Character]) -> String? {
        var cursor = openParen + 1
        while cursor < chars.count,
              chars[cursor] == " " || chars[cursor] == "\t" || chars[cursor] == "\n" {
            cursor += 1
        }
        var name = ""
        while cursor < chars.count, isIdentifier(chars[cursor]) {
            name.append(chars[cursor])
            cursor += 1
        }
        while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" { cursor += 1 }
        guard cursor < chars.count, chars[cursor] == ":" else { return nil }
        return name.isEmpty ? nil : name
    }

    /// The top-level `label: value` pairs of a call whose `(` is at `openParen`.
    static func argumentValues(in chars: [Character], openParen: Int) -> [String: String] {
        let arguments = ImportCandidateCopyScanner.topLevelArguments(in: chars, openParen: openParen)
        var pairs: [String: String] = [:]
        for argument in arguments {
            guard let colon = ImportCandidateCopyScanner.firstTopLevelColon(in: argument) else {
                continue
            }
            let label = argument[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.allSatisfy(isIdentifier) else { continue }
            pairs[label] = String(argument[argument.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pairs
    }

    /// Whether a `provenance:` value names a capture the scan door produced.
    /// `.manual` is the typed door (hard rule 15) and is not a scanned save.
    static func isScanProvenance(_ value: String) -> Bool {
        [".receiptScan", ".pumpPhoto", ".fiscalQR", ".screenshot"].contains {
            value.contains($0)
        }
    }

    // MARK: - Lexing

    /// The name of the nearest `func` declared before `offset`, or nil when the
    /// site sits outside any function.
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
