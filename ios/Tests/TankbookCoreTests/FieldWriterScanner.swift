import Foundation

/// RV.196 - the field-level extension of RV.163's entity-writer guard. RV.163
/// proves an entity has a production writer; `PJ.55` was the instance it could
/// not see, because `Station` had a writer while `Station.favorite` had none -
/// a column, a decoder, ten seeds, a reader in the ranking ladder, and nothing
/// that could set it. This scanner asks the same question one level down: for
/// each persisted field, is there a production path that gives it a value a
/// human can reach?
///
/// **The unit of truth is the Swift domain type, not the doc's prose.** RV.163
/// binds the doc's `###` headings (which are stable) to write calls; this
/// scanner binds those same headings to the Swift types that carry the fields,
/// then reads each field from its compiled declaration. SCHEMA.md names fields
/// in prose, inline structs and tables (`notifications: { reminders, anomalies,
/// monthlySummary }`, `id, createdAt, updatedAt, deletedAt` on one line), and a
/// parser over that shape would silently miss a field the next doc edit
/// reflows. The Swift declaration is the shape the memberwise init and the
/// decoder actually agree on, so the init-argument half of the rule is exact.
/// **The trade this makes, stated:** a field the docs promise but the Swift type
/// lacks is invisible here - the compiled type is the writer's own contract, and
/// a field no type declares cannot be written or read. The entity-level guard
/// still fails on a heading whose type is gone.
///
/// A field is written when, **in a production host** (not a seed, the import
/// path, sync, `#if DEBUG`, or the repository's own write/decoder surface):
///   - it is assigned outside its own declaration (`.field =`), or
///   - it is passed to its owner's init as an argument that is not a literal
///     default (`nil`, `false`, `[]`, `0`, or the value the declaration carries), or
///   - a production call reaches a repository write function whose body assigns
///     it (`setStationFavorite` writes `favorite`; `selectVehicle` writes
///     `defaultVehicleId`). The repository definition is the write API, not a
///     caller - exactly RV.163's rule - so the call is what counts, never the
///     definition.
///
/// The persistence decoder is deliberately **not** a writer: it restores what
/// was stored, and treating `Station(favorite: row["favorite"])` as a write is
/// the one mistake that would have hidden `PJ.55` all over again. It lives in
/// the repository/decoder surface, which is not a host.
enum FieldWriterScanner {

    typealias SourceFile = EntityWriterScanner.SourceFile

    /// One field of a persisted entity. `path` is one element for a plain
    /// field, two for a field of a nested value type (the container itself is
    /// not reported - the doc names `notifications.anomalies`, not the
    /// `notifications` blob).
    struct Field {
        let typeName: String
        let ownerTypeName: String
        let path: [String]
        let declaredType: String
        let declaredDefault: String?

        var qualifiedName: String { ([typeName] + path).joined(separator: ".") }
        var leafName: String { path.last ?? typeName }
    }

    /// A field allowed to have no production writer, with its reason.
    struct DocumentedException {
        let field: String
        let reason: String
    }

    /// The doc binding: one SCHEMA `###` heading to the Swift type(s) whose
    /// fields it names. The `note` is required and checked, exactly as RV.163's
    /// spec notes are - a bare binding is a skip list.
    struct EntityFields {
        let heading: String
        let typeNames: [String]
        let note: String
    }

    static let entityFieldSpecs: [EntityFields] = [
        EntityFields(heading: "Vehicle", typeNames: ["Vehicle"],
                     note: "Vehicle's fields are its struct's stored properties, including the "
                         + "nested Units value type."),
        EntityFields(heading: "Entry (common envelope)", typeNames: [],
                     note: "Entry is the shared envelope, not a row: its fields are declared and "
                         + "checked on each of the four concrete entry types below."),
        EntityFields(heading: "FillUp", typeNames: ["FillUp"],
                     note: "FillUp's own fields plus the envelope it redeclares."),
        EntityFields(heading: "ChargeSession", typeNames: ["ChargeSession"],
                     note: "ChargeSession's fields are inherited by the EV entry path [v1.x]; the "
                         + "heading is recorded as an entity-level exception rather than re-reported."),
        EntityFields(heading: "ServiceRecord & Expense", typeNames: ["ServiceRecord", "Expense"],
                     note: "One heading, two persisted rows; each type's fields are checked."),
        EntityFields(heading: "Reminder", typeNames: ["Reminder"],
                     note: "Reminder's fields; Recurrence is a nested value type."),
        EntityFields(heading: "Attachment & extraction provenance", typeNames: ["Attachment"],
                     note: "Attachment is the persisted row; extraction provenance is embedded in "
                         + "it and in the entry, not a table of its own."),
        EntityFields(heading: "Preferences (app-level settings)", typeNames: ["Preferences"],
                     note: "Preferences' fields, including the nested Notifications value type."),
        EntityFields(heading: "Station", typeNames: ["Station"],
                     note: "Station's fields, including the nested Defaults value type."),
        EntityFields(heading: "ExchangeRate (local cache, deliberately NOT synced)",
                     typeNames: ["ExchangeRate"],
                     note: "ExchangeRate is a local cache; its writer is the /rates fetch -> "
                         + "persist path, never sync and never a user typing a rate.")
    ]

    /// The Swift type(s) whose fields a heading names. A spec wins; an unknown
    /// heading falls back to the mechanical first-capitalized-token rule so a
    /// NEW entity must bring a readable type or fail.
    static func typeNames(forHeading heading: String) -> [String] {
        if let spec = entityFieldSpecs.first(where: { $0.heading == heading }) { return spec.typeNames }
        let base = heading.split(separator: "(", maxSplits: 1).first.map(String.init) ?? heading
        var names: [String] = []
        for part in base.split(separator: "&") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.split(separator: " ").first.map(String.init),
                  first.first?.isUppercase == true else { continue }
            names.append(first)
        }
        return names
    }

    /// Specs whose heading has left the doc while the binding remains.
    static func staleSpecHeadings(schemaText: String) -> [String] {
        let headings = Set(EntityWriterScanner.entityHeadings(in: schemaText))
        return entityFieldSpecs.map(\.heading).filter { !headings.contains($0) }
    }

    static func noteProblem(in spec: EntityFields) -> String? {
        guard spec.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "field spec for \(spec.heading) carries no note - a bare binding is a skip list"
    }

    static func reasonProblem(in exception: DocumentedException) -> String? {
        guard exception.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "documented exception for \(exception.field) carries no reason - "
            + "a bare entry is a skip list, not a deliberate exception"
    }

    // MARK: - The scan

    /// The fields with no production writer. `entityExceptions` suppresses every
    /// field of a heading (used for `ChargeSession`, whose EV path is [v1.x]);
    /// `exceptions` suppresses one qualified field.
    static func unwrittenFields(schemaText: String,
                                sources: [SourceFile],
                                exceptions: [DocumentedException] = [],
                                entityExceptions: [String: String] = [:]) -> [String] {
        let exceptionNames = Set(exceptions.map(\.field))
        let masked = sources.map {
            SourceFile(path: $0.path, contents: EntityWriterScanner.masked($0.contents))
        }
        let hosts = masked.filter { isProductionHost(path: $0.path) }
            .map { witness(in: $0.contents) }
        let repoWriters = repositoryFieldWriters(sources: sources)
        var unwritten: [String] = []
        for heading in EntityWriterScanner.entityHeadings(in: schemaText) {
            if entityExceptions[heading] != nil { continue }
            for typeName in typeNames(forHeading: heading) {
                for field in fields(forType: typeName, inMasked: masked) {
                    if exceptionNames.contains(field.qualifiedName) { continue }
                    if !isWritten(field, in: hosts, repoWriters: repoWriters) {
                        unwritten.append(field.qualifiedName)
                    }
                }
            }
        }
        return unwritten.sorted()
    }

    /// Every qualified field name the doc's entities resolve to, whether or not
    /// it is written. Used to tell a stale exception (no such field) from a
    /// resolved one.
    static func allFieldNames(schemaText: String, sources: [SourceFile]) -> [String] {
        let masked = sources.map {
            SourceFile(path: $0.path, contents: EntityWriterScanner.masked($0.contents))
        }
        var names: [String] = []
        for heading in EntityWriterScanner.entityHeadings(in: schemaText) {
            for typeName in typeNames(forHeading: heading) {
                names.append(contentsOf: fields(forType: typeName, inMasked: masked).map(\.qualifiedName))
            }
        }
        return names
    }

    /// Exceptions whose field no longer exists, or now has a production writer.
    /// The list cannot rot into a permanent skip list: a field that gains a
    /// writer must lose its exception in the same change.
    static func staleExceptions(schemaText: String,
                                sources: [SourceFile],
                                exceptions: [DocumentedException],
                                entityExceptions: [String: String] = [:]) -> [String] {
        let allFields = Set(allFieldNames(schemaText: schemaText, sources: sources))
        // The raw report, WITHOUT this exception list: a field is only a valid
        // exception while it is genuinely unwritten.
        let unwritten = Set(unwrittenFields(schemaText: schemaText, sources: sources,
                                            entityExceptions: entityExceptions))
        return exceptions.map(\.field).filter { field in
            !allFields.contains(field) || !unwritten.contains(field)
        }.sorted()
    }

    /// Entity exceptions whose heading has left the doc.
    static func staleEntityExceptions(schemaText: String,
                                      entityExceptions: [String: String]) -> [String] {
        let headings = Set(EntityWriterScanner.entityHeadings(in: schemaText))
        return entityExceptions.keys.filter { !headings.contains($0) }.sorted()
    }

    /// Whether a path may host a production field write. This is RV.163's host
    /// rule, tightened at the repository boundary: the whole core
    /// `Persistence/` directory is the write API and the decoder, so it defines
    /// fields and restores them but never originates a value. The app-layer
    /// `App/Sources/Persistence/` wrappers are hosts - they call the repository
    /// write functions a user reaches.
    static func isProductionHost(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("TestSeed") || path.contains("TestSupport") { return false }
        if path.contains("/Tests/") || path.contains("/UITests/") { return false }
        if path.contains("/Import/") || name.hasPrefix("Import") { return false }
        if path.contains("/Sync/") || name.contains("Sync") { return false }
        if path.contains("TankbookCore/Persistence/") { return false }
        if name.hasPrefix("Repository") { return false }
        if name == "Migrations.swift" { return false }
        if name.hasPrefix("Records") { return false }
        return true
    }

    /// A file that DEFINES the repository write surface or decodes a stored row.
    static func isRepositoryDefinition(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("TankbookCore/Persistence/") { return true }
        if name.hasPrefix("Repository") { return true }
        if name.hasPrefix("Records") { return true }
        if name == "Migrations.swift" { return true }
        return false
    }

    // MARK: - Field extraction

    /// Every leaf field of `typeName`, including the fields of a nested value
    /// type (one level: `Preferences.notifications.anomalies`). A container
    /// whose type is a nested struct is not itself reported. Masks the sources
    /// first; the scanner's own scan uses `fields(forType:inMasked:)` so a whole
    /// tree is masked once.
    static func fields(forType typeName: String, in sources: [SourceFile]) -> [Field] {
        fields(forType: typeName, inMasked: sources.map {
            SourceFile(path: $0.path, contents: EntityWriterScanner.masked($0.contents))
        })
    }

    static func fields(forType typeName: String, inMasked sources: [SourceFile]) -> [Field] {
        for source in sources {
            if let body = declarationBody(ofType: typeName, in: source.contents) {
                return fields(in: body, typeName: typeName, ownerTypeName: typeName, path: [])
            }
        }
        return []
    }

    private static func fields(in body: String,
                               typeName: String,
                               ownerTypeName: String,
                               path: [String]) -> [Field] {
        var result: [Field] = []
        for property in topLevelProperties(in: body) {
            let fieldPath = path + [property.name]
            if let nested = declarationBody(ofType: baseTypeName(property.type), in: body) {
                result.append(contentsOf: fields(in: nested, typeName: typeName,
                                                 ownerTypeName: baseTypeName(property.type),
                                                 path: fieldPath))
            } else {
                result.append(Field(typeName: typeName,
                                    ownerTypeName: ownerTypeName,
                                    path: fieldPath,
                                    declaredType: property.type,
                                    declaredDefault: property.defaultValue))
            }
        }
        return result
    }

    private struct Property {
        let name: String
        let type: String
        let defaultValue: String?
    }

    /// Stored properties declared at the top level of a type body. Nested
    /// declarations sit at brace depth > 0 and are skipped (their fields are
    /// reached through the property that names them).
    private static func topLevelProperties(in body: String) -> [Property] {
        var result: [Property] = []
        var depth = 0
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if depth == 0, let property = parseProperty(line.trimmingCharacters(in: .whitespaces)) {
                result.append(property)
            }
            depth += braceDelta(line)
        }
        return result
    }

    private static func parseProperty(_ line: String) -> Property? {
        guard let keyword = firstKeywordRange(in: line) else { return nil }
        let afterKeyword = line[keyword.upperBound...]
        guard let colon = afterKeyword.firstIndex(of: ":") else { return nil }
        let name = afterKeyword[..<colon].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        var rest = String(afterKeyword[afterKeyword.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
        if let brace = rest.firstIndex(of: "{") {  // `var x: T { get set }`
            rest = String(rest[..<brace]).trimmingCharacters(in: .whitespaces)
        }
        var defaultValue: String?
        if let equals = rest.firstIndex(of: "=") {
            defaultValue = String(rest[rest.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            rest = String(rest[..<equals]).trimmingCharacters(in: .whitespaces)
        }
        return Property(name: name, type: rest, defaultValue: defaultValue)
    }

    private static func firstKeywordRange(in line: String) -> Range<String.Index>? {
        for keyword in ["var ", "let "] {
            if let range = line.range(of: keyword) {
                if range.lowerBound == line.startIndex { return range }
                let before = line[line.index(before: range.lowerBound)]
                if before == " " { return range }
            }
        }
        return nil
    }

    private static func braceDelta(_ line: String) -> Int {
        line.reduce(0) { count, character in
            if character == "{" { return count + 1 }
            if character == "}" { return count - 1 }
            return count
        }
    }

    /// The inner body of `struct`/`protocol`/`enum`/`class <typeName>`.
    private static func declarationBody(ofType typeName: String, in source: String) -> String? {
        guard let range = declarationBodyRange(ofType: typeName, in: source) else { return nil }
        return String(source[range])
    }

    private static func declarationBodyRange(ofType typeName: String,
                                             in source: String) -> Range<String.Index>? {
        for keyword in ["struct", "protocol", "enum", "class"] {
            let needle = "\(keyword) \(typeName)"
            var searchStart = source.startIndex
            while let range = source.range(of: needle, range: searchStart..<source.endIndex) {
                let beforeOK = range.lowerBound == source.startIndex
                    || !isIdentifier(source[source.index(before: range.lowerBound)])
                let afterIndex = range.upperBound
                let afterOK = afterIndex >= source.endIndex || !isIdentifier(source[afterIndex])
                if beforeOK, afterOK, let brace = source[afterIndex...].firstIndex(of: "{"),
                   let close = matchingBrace(in: source, from: brace) {
                    return source.index(after: brace)..<close
                }
                searchStart = range.upperBound
            }
        }
        return nil
    }

    private static func matchingBrace(in source: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func baseTypeName(_ type: String) -> String {
        var value = type.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix("?") { value.removeLast() }
        if value.hasPrefix("["), value.hasSuffix("]") {
            value.removeFirst()
            value.removeLast()
        }
        if let angle = value.firstIndex(of: "<") { value = String(value[..<angle]) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Writer detection

    /// What one production host can write, extracted once so the scan is
    /// O(sources) rather than O(fields x sources). `contents` must be masked.
    struct HostWitness {
        /// Member-assignment chains, e.g. `favorite` from `live.favorite = x`,
        /// `notifications.anomalies` from `p.notifications.anomalies = x`. A
        /// `self.` receiver is the type's own init and is not a production write.
        var assignmentChains: Set<String> = []
        /// Construction arguments by type name: `Station(favorite: true)` ->
        /// `["Station": ["favorite": "true"]]`.
        var initArguments: [String: [String: String]] = [:]
        /// Every function/member name called in the host.
        var calledFunctions: Set<String> = []
    }

    static func witness(in masked: String) -> HostWitness {
        var result = HostWitness()
        let characters = Array(masked)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "." {
                index = recordAssignmentChain(characters, at: index, into: &result)
                continue
            }
            if isIdentifier(character), !character.isNumber {
                var end = index
                var name = ""
                while end < characters.count, isIdentifier(characters[end]) {
                    name.append(characters[end])
                    end += 1
                }
                var cursor = end
                while cursor < characters.count, characters[cursor] == " " { cursor += 1 }
                if cursor < characters.count, characters[cursor] == "(" {
                    result.calledFunctions.insert(name)
                    if let (pairs, next) = argumentPairs(characters, openParen: cursor) {
                        result.initArguments[name, default: [:]].merge(pairs) { _, new in new }
                        index = next
                        continue
                    }
                }
                index = end
                continue
            }
            index += 1
        }
        return result
    }

    private static func recordAssignmentChain(_ characters: [Character],
                                              at dot: Int,
                                              into result: inout HostWitness) -> Int {
        var receiverStart = dot
        while receiverStart > 0, isIdentifier(characters[receiverStart - 1]) { receiverStart -= 1 }
        let receiver = String(characters[receiverStart..<dot])
        var cursor = dot + 1
        var chain: [String] = []
        while cursor < characters.count, isIdentifier(characters[cursor]) {
            var name = ""
            while cursor < characters.count, isIdentifier(characters[cursor]) {
                name.append(characters[cursor])
                cursor += 1
            }
            chain.append(name)
            if cursor < characters.count, characters[cursor] == "." {
                cursor += 1
                continue
            }
            break
        }
        var after = cursor
        while after < characters.count, characters[after] == " " { after += 1 }
        if !chain.isEmpty, receiver != "self", after < characters.count, characters[after] == "=",
           after + 1 >= characters.count || characters[after + 1] != "=" {
            result.assignmentChains.insert(chain.joined(separator: "."))
        }
        return max(cursor, dot + 1)
    }

    /// The labelled arguments of a call starting at `openParen`, as
    /// `[label: value]`, and the index just past the closing `)`.
    private static func argumentPairs(_ characters: [Character],
                                      openParen: Int) -> ([String: String], Int)? {
        var depth = 0
        var index = openParen
        var current = ""
        var label: String?
        var pairs: [String: String] = [:]
        while index < characters.count {
            let character = characters[index]
            if character == "(" {
                depth += 1
                if depth == 1 {
                    index += 1
                    continue
                }
            }
            if character == ")" {
                depth -= 1
                if depth == 0 {
                    if let label, !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pairs[label] = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return (pairs, index + 1)
                }
            }
            if depth == 1, character == "," {
                if let label { pairs[label] = current.trimmingCharacters(in: .whitespacesAndNewlines) }
                label = nil
                current = ""
                index += 1
                continue
            }
            if depth == 1, character == ":", label == nil {
                let candidate = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty,
                   candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    label = candidate
                    current = ""
                    index += 1
                    continue
                }
            }
            if depth >= 1 { current.append(character) }
            index += 1
        }
        return nil
    }

    static func isWritten(_ field: Field,
                          in hosts: [HostWitness],
                          repoWriters: [String: Set<String>]) -> Bool {
        for host in hosts {
            if host.assignmentChains.contains(field.path.joined(separator: ".")) { return true }
            if let args = host.initArguments[field.ownerTypeName],
               let value = args[field.leafName], isNonDefault(value, field: field) {
                return true
            }
            if let functions = repoWriters[field.leafName],
               !functions.isDisjoint(with: host.calledFunctions) {
                return true
            }
        }
        return false
    }

    /// A field name mapped to the repository write functions whose bodies assign
    /// it. The function is the write API; a production CALL to it is the writer
    /// (RV.163's rule, applied to a single field). Reading the definition's body
    /// is what makes `setStationFavorite` mean `favorite` without a hand-kept
    /// field-to-symbol table.
    static func repositoryFieldWriters(sources: [SourceFile]) -> [String: Set<String>] {
        var writers: [String: Set<String>] = [:]
        for source in sources where isRepositoryDefinition(path: source.path) {
            let masked = EntityWriterScanner.masked(source.contents)
            for function in functionNames(in: masked) {
                guard let range = functionBodyRange(named: function, in: masked) else { continue }
                // Masking preserves length, so the range maps onto the raw text:
                // Swift member writes are read from the masked body (strings and
                // comments blanked), SQL `SET` columns from the raw body (they
                // live inside a string literal the masker would hide).
                let memberWrites = memberAssignedFieldNames(in: String(masked[range]))
                let sqlWrites = sqlSetFieldNames(in: String(source.contents[range]))
                for assignment in memberWrites + sqlWrites {
                    writers[assignment, default: []].insert(function)
                }
            }
        }
        return writers
    }

    private static func functionNames(in source: String) -> [String] {
        var names: [String] = []
        var searchStart = source.startIndex
        while let range = source.range(of: "func ", range: searchStart..<source.endIndex) {
            let beforeOK = range.lowerBound == source.startIndex
                || !isIdentifier(source[source.index(before: range.lowerBound)])
            if beforeOK {
                let after = source[range.upperBound...]
                let name = after.prefix { isIdentifier($0) }
                if !name.isEmpty { names.append(String(name)) }
            }
            searchStart = range.upperBound
        }
        return names
    }

    private static func functionBodyRange(named name: String, in source: String) -> Range<String.Index>? {
        let needle = "func \(name)"
        var searchStart = source.startIndex
        while let range = source.range(of: needle, range: searchStart..<source.endIndex) {
            let afterIndex = range.upperBound
            let afterOK = afterIndex >= source.endIndex || !isIdentifier(source[afterIndex])
            if afterOK, let brace = source[afterIndex...].firstIndex(of: "{"),
               let close = matchingBrace(in: source, from: brace) {
                return source.index(after: brace)..<close
            }
            searchStart = range.upperBound
        }
        return nil
    }

    /// SQL `SET col = ...` columns in a raw body: `archiveVehicle` writes
    /// `archived` and `archivedAt` through `db.execute(sql:)`, not through a
    /// Swift member assignment.
    private static func sqlSetFieldNames(in body: String) -> [String] {
        var names: [String] = []
        var searchStart = body.startIndex
        while let setRange = body.range(of: "SET ", range: searchStart..<body.endIndex) {
            let afterSet = body[setRange.upperBound...]
            let lineEnd = afterSet.firstIndex(of: "\n") ?? afterSet.endIndex
            let whereRange = afterSet.range(of: "WHERE")
            let clauseEnd = [lineEnd, whereRange?.lowerBound ?? afterSet.endIndex].min() ?? lineEnd
            let clause = afterSet[..<clauseEnd]
            let characters = Array(clause)
            var index = 0
            while index < characters.count {
                guard characters[index].isLetter else {
                    index += 1
                    continue
                }
                var cursor = index
                var name = ""
                while cursor < characters.count, isIdentifier(characters[cursor]) {
                    name.append(characters[cursor])
                    cursor += 1
                }
                while cursor < characters.count, characters[cursor] == " " { cursor += 1 }
                if cursor < characters.count, characters[cursor] == "=" { names.append(name) }
                index = max(cursor, index + 1)
            }
            searchStart = setRange.upperBound
        }
        return names
    }

    private static func memberAssignedFieldNames(in body: String) -> [String] {
        var names: [String] = []
        let characters = Array(body)
        var index = 0
        while index < characters.count {
            guard characters[index] == "." else {
                index += 1
                continue
            }
            if index + 1 < characters.count, characters[index + 1] == "." {
                index += 1
                continue
            }
            var cursor = index + 1
            var name = ""
            while cursor < characters.count, isIdentifier(characters[cursor]) {
                name.append(characters[cursor])
                cursor += 1
            }
            while cursor < characters.count, characters[cursor] == " " { cursor += 1 }
            if let first = name.first, first.isLetter,
               cursor < characters.count, characters[cursor] == "=",
               cursor + 1 >= characters.count || characters[cursor + 1] != "=" {
                names.append(name)
            }
            index = max(cursor, index + 1)
        }
        return names
    }

    private static func isNonDefault(_ value: String, field: Field) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let declared = field.declaredDefault { return trimmed != declared }
        return !(trimmed == "nil" || trimmed == "false" || trimmed == "[]" || trimmed == "0")
    }
}
