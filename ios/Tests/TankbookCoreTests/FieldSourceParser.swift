import Foundation

/// RV.196's low-level source readers: the Swift field declarations of a domain
/// type, and the repository write functions' assigned columns. Split from
/// `FieldWriterScanner` so each type body stays readable and under the lint
/// ceiling; it holds no policy - the scanner owns which fields matter, which
/// hosts may write them, and what an unwritten one means.
enum FieldSourceParser {

    typealias SourceFile = EntityWriterScanner.SourceFile

    // MARK: - Field extraction

    /// Every leaf field of `typeName`, including the fields of a nested value
    /// type (one level: `Preferences.notifications.anomalies`). A container
    /// whose type is a nested struct is not itself reported. Masks first; the
    /// scanner passes already-masked sources to `inMasked`.
    static func fields(forType typeName: String, in sources: [SourceFile]) -> [FieldWriterScanner.Field] {
        fields(forType: typeName, inMasked: sources.map {
            SourceFile(path: $0.path, contents: EntityWriterScanner.masked($0.contents))
        })
    }

    static func fields(forType typeName: String,
                       inMasked sources: [SourceFile]) -> [FieldWriterScanner.Field] {
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
                               path: [String]) -> [FieldWriterScanner.Field] {
        var result: [FieldWriterScanner.Field] = []
        for property in topLevelProperties(in: body) {
            let fieldPath = path + [property.name]
            if let nested = declarationBody(ofType: baseTypeName(property.type), in: body) {
                result.append(contentsOf: fields(in: nested, typeName: typeName,
                                                 ownerTypeName: baseTypeName(property.type),
                                                 path: fieldPath))
            } else {
                result.append(FieldWriterScanner.Field(typeName: typeName,
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
                    || !FieldWriterScanner.isIdentifier(source[source.index(before: range.lowerBound)])
                let afterIndex = range.upperBound
                let afterOK = afterIndex >= source.endIndex
                    || !FieldWriterScanner.isIdentifier(source[afterIndex])
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

    // MARK: - The repository write surface

    /// A field name mapped to the repository write functions whose bodies assign
    /// it. The function is the write API; a production CALL to it is the writer
    /// (RV.163's rule, applied to a single field). Reading the definition's body
    /// is what makes `setStationFavorite` mean `favorite` without a hand-kept
    /// field-to-symbol table.
    static func repositoryFieldWriters(sources: [SourceFile]) -> [String: Set<String>] {
        var writers: [String: Set<String>] = [:]
        for source in sources where FieldWriterScanner.isRepositoryDefinition(path: source.path) {
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
                || !FieldWriterScanner.isIdentifier(source[source.index(before: range.lowerBound)])
            if beforeOK {
                let after = source[range.upperBound...]
                let name = after.prefix { FieldWriterScanner.isIdentifier($0) }
                if !name.isEmpty { names.append(String(name)) }
            }
            searchStart = range.upperBound
        }
        return names
    }

    private static func functionBodyRange(named name: String,
                                          in source: String) -> Range<String.Index>? {
        let needle = "func \(name)"
        var searchStart = source.startIndex
        while let range = source.range(of: needle, range: searchStart..<source.endIndex) {
            let afterIndex = range.upperBound
            let afterOK = afterIndex >= source.endIndex
                || !FieldWriterScanner.isIdentifier(source[afterIndex])
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
                while cursor < characters.count, FieldWriterScanner.isIdentifier(characters[cursor]) {
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
            while cursor < characters.count, FieldWriterScanner.isIdentifier(characters[cursor]) {
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
}
