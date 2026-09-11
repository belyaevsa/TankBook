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
/// A field is written when, **in a production host** (not a seed, sync,
/// `#if DEBUG`, or the repository's own write/decoder surface; the import path
/// IS a host - see `isProductionHost`):
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
                     note: "ChargeSession's fields belong to the EV entry path [v1.x]; the heading "
                         + "is recorded as an entity-level field exception rather than re-reported."),
        EntityFields(heading: "ServiceRecord & Expense",
                     typeNames: ["ServiceRecord", "Expense", "ServiceItem"],
                     note: "One heading, two persisted rows; each type's fields are checked. "
                         + "ServiceItem is the line-item child row a ServiceRecord carries - it is "
                         + "persisted only with its parent, so it rides this heading rather than "
                         + "owning an entity heading the entity guard would demand a writer for."),
        EntityFields(heading: "TireSet", typeNames: ["TireSet"],
                     note: "TireSet is its own persisted row with its own create/rename path; its "
                         + "fields are checked here, not as fields of ServiceRecord."),
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
        let repoWriters = FieldSourceParser.repositoryFieldWriters(sources: sources)
        var unwritten: [String] = []
        for heading in EntityWriterScanner.entityHeadings(in: schemaText) {
            if entityExceptions[heading] != nil { continue }
            for typeName in typeNames(forHeading: heading) {
                for field in FieldSourceParser.fields(forType: typeName, inMasked: masked) {
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
                let fields = FieldSourceParser.fields(forType: typeName, inMasked: masked)
                names.append(contentsOf: fields.map(\.qualifiedName))
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

    /// Whether a path may host a production field write. Two deliberate
    /// differences from RV.163's entity host rule:
    ///
    /// - **The import path IS a field host.** RV.163 excluded it because an
    ///   entity only an import can create is still uncreatable by a hand-typing
    ///   user; a field an import fills, however, is genuinely set by a
    ///   production flow the user triggers, and `Station.name`/`createdAt` are
    ///   constructed exactly there (`ImportStationResolver.station(for:)`). The
    ///   import still cannot fake `Station.brand` or `Station.favorite`, because
    ///   it passes them their nil/false defaults.
    /// - **The decoder and the repository write API are not hosts.** The whole
    ///   core `Persistence/` directory defines the write surface and restores
    ///   stored rows; it never originates a value. The app-layer
    ///   `App/Sources/Persistence/` wrappers ARE hosts - they call the
    ///   repository functions a user reaches. Sync stays excluded: a field only
    ///   another device set is not settable here.
    static func isProductionHost(path: String) -> Bool {
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

    /// A file that DEFINES the repository write surface or decodes a stored row.
    static func isRepositoryDefinition(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.contains("TankbookCore/Persistence/") { return true }
        if name.hasPrefix("Repository") { return true }
        if name.hasPrefix("Records") { return true }
        if name == "Migrations.swift" { return true }
        return false
    }

    /// The fields of one Swift domain type. The parser owns the reading; this
    /// wrapper keeps the scanner's public surface for tests.
    static func fields(forType typeName: String, in sources: [SourceFile]) -> [Field] {
        FieldSourceParser.fields(forType: typeName, in: sources)
    }

    static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
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
        // Advance only past the dot: the member name itself must still be seen
        // by the main loop so `repository.setStationFavorite(` registers as a
        // call and `Station.Defaults(` as a construction.
        return dot + 1
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
            switch character {
            case "(":
                depth += 1
                if depth > 1 { current.append(character) }
            case ")" where depth > 1:
                depth -= 1
                current.append(character)
            case ")":
                record(label, current, into: &pairs)
                return (pairs, index + 1)
            case "," where depth == 1:
                record(label, current, into: &pairs)
                label = nil
                current = ""
            case ":" where depth == 1 && label == nil:
                if let candidate = labelCandidate(current) {
                    label = candidate
                    current = ""
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
            index += 1
        }
        return nil
    }

    private static func record(_ label: String?, _ value: String, into pairs: inout [String: String]) {
        guard let label else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { pairs[label] = trimmed }
    }

    private static func labelCandidate(_ text: String) -> String? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return candidate
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

    private static func isNonDefault(_ value: String, field: Field) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let declared = field.declaredDefault { return trimmed != declared }
        return !(trimmed == "nil" || trimmed == "false" || trimmed == "[]" || trimmed == "0")
    }
}
