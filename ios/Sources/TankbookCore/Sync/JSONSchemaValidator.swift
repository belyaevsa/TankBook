import Foundation

/// A schema validation failure, named by its JSON pointer (docs/SYNC.md, the
/// server's `422 payload_schema_violation` names the offending pointer too).
public struct SchemaValidationError: Equatable, Sendable {
    public var pointer: String
    public var message: String
}

/// A deliberately lightweight JSON Schema validator for the subset the payload
/// contract uses (docs/SYNC.md -> "Payload contract and versioning"):
/// `$defs`/`$ref`, `type`, `enum`, `const`, `required`, `properties`,
/// `additionalProperties`, `items`, `propertyNames`, `anyOf`, `oneOf`,
/// `format` (uuid, date-time), `pattern` and boolean schemas.
///
/// Chosen over a dependency: the contract intentionally restricts itself to
/// this subset (draft 2020-12, `additionalProperties: true` everywhere, no
/// remote refs), so a full validator - and its transitive dependencies,
/// update pressure and license surface - is not worth it. Both consumers (the
/// iOS client and the C# server) implement exactly this same small surface.
public enum JSONSchemaValidator {
    public static func validate(instance: JSONValue, schema: JSONValue) -> [SchemaValidationError] {
        var errors: [SchemaValidationError] = []
        validate(instance, against: schema, root: schema, pointer: "", errors: &errors)
        return errors
    }

    private static func validate(_ instance: JSONValue, against schema: JSONValue,
                                 root: JSONValue, pointer: String,
                                 errors: inout [SchemaValidationError]) {
        if let reference = schema.objectValue?["$ref"]?.stringValue {
            guard let resolved = resolve(reference, in: root) else {
                errors.append(SchemaValidationError(pointer: pointer, message: "Unresolvable $ref '\(reference)'"))
                return
            }
            validate(instance, against: resolved, root: root, pointer: pointer, errors: &errors)
            return
        }

        if schema.isNull { return } // any value
        if let allowed = schema.boolValue {
            if !allowed {
                errors.append(SchemaValidationError(pointer: pointer, message: "Value not permitted"))
            }
            return
        }

        guard let object = schema.objectValue else { return }

        // Split by keyword family purely for readability - the order of these
        // four calls is the order errors are reported in, so it is part of the
        // observable behaviour and must not be shuffled.
        validateAssertions(instance, object: object, pointer: pointer, errors: &errors)
        validateCombinators(instance, object: object, root: root, pointer: pointer, errors: &errors)
        validateObjectKeywords(instance, object: object, root: root, pointer: pointer, errors: &errors)
        validateArrayKeywords(instance, object: object, root: root, pointer: pointer, errors: &errors)
    }

    /// `type`, `enum`, `const`, `format`, `pattern` - the keywords that judge a
    /// value on its own, with no recursion.
    private static func validateAssertions(_ instance: JSONValue, object: [String: JSONValue],
                                           pointer: String, errors: inout [SchemaValidationError]) {
        if let type = object["type"] {
            if case .string(let typeName) = type, !matches(instance, type: typeName) {
                errors.append(SchemaValidationError(pointer: pointer,
                                                    message: "Expected type '\(typeName)'"))
            }
        }

        if let enumValues = object["enum"]?.arrayValue, !enumValues.contains(instance) {
            errors.append(SchemaValidationError(pointer: pointer,
                                                message: "Value not in the allowed enum"))
        }

        if let const = object["const"], instance != const {
            errors.append(SchemaValidationError(pointer: pointer,
                                                message: "Value does not match const"))
        }

        if let format = object["format"]?.stringValue, !validFormat(instance, format) {
            errors.append(SchemaValidationError(pointer: pointer,
                                                message: "Value does not match format '\(format)'"))
        }

        if let pattern = object["pattern"]?.stringValue, let string = instance.stringValue,
           !regexMatch(pattern, string) {
            errors.append(SchemaValidationError(pointer: pointer,
                                                message: "Value does not match pattern '\(pattern)'"))
        }
    }

    /// `anyOf` / `oneOf`. Sub-schema failures are collected into a throwaway
    /// buffer: a branch that does not match is not itself an error.
    private static func validateCombinators(_ instance: JSONValue, object: [String: JSONValue],
                                            root: JSONValue, pointer: String,
                                            errors: inout [SchemaValidationError]) {
        func branchMatches(_ subSchema: JSONValue) -> Bool {
            var subErrors: [SchemaValidationError] = []
            validate(instance, against: subSchema, root: root, pointer: pointer, errors: &subErrors)
            return subErrors.isEmpty
        }

        if let anyOf = object["anyOf"]?.arrayValue, !anyOf.contains(where: branchMatches) {
            errors.append(SchemaValidationError(pointer: pointer,
                                                message: "Value does not match anyOf"))
        }

        if let oneOf = object["oneOf"]?.arrayValue {
            let count = oneOf.filter(branchMatches).count
            if count != 1 {
                errors.append(SchemaValidationError(
                    pointer: pointer,
                    message: "Value must match exactly one oneOf branch (matched \(count))"
                ))
            }
        }
    }

    /// `required`, `properties`, `additionalProperties`, `propertyNames`. All of
    /// these are no-ops unless the instance is an object.
    private static func validateObjectKeywords(_ instance: JSONValue, object: [String: JSONValue],
                                               root: JSONValue, pointer: String,
                                               errors: inout [SchemaValidationError]) {
        guard let instanceObject = instance.objectValue else { return }

        if let required = object["required"]?.arrayValue {
            for key in required.compactMap(\.stringValue) where instanceObject[key] == nil {
                errors.append(SchemaValidationError(pointer: pointer,
                                                    message: "Missing required property '\(key)'"))
            }
        }

        if let properties = object["properties"]?.objectValue {
            for (key, subSchema) in properties {
                if let value = instanceObject[key] {
                    validate(value, against: subSchema, root: root,
                             pointer: pointer + "/" + key, errors: &errors)
                }
            }
        }

        if let additional = object["additionalProperties"] {
            let known = Set(object["properties"]?.objectValue?.keys ?? [:].keys)
            for (key, value) in instanceObject where !known.contains(key) {
                switch additional {
                case .bool(false):
                    errors.append(SchemaValidationError(pointer: pointer + "/" + key,
                                                        message: "Additional property '\(key)' not permitted"))
                case .object:
                    validate(value, against: additional, root: root,
                             pointer: pointer + "/" + key, errors: &errors)
                default:
                    break
                }
            }
        }

        if let propertyNames = object["propertyNames"] {
            for key in instanceObject.keys {
                validate(.string(key), against: propertyNames, root: root,
                         pointer: pointer, errors: &errors)
            }
        }
    }

    /// `items`.
    private static func validateArrayKeywords(_ instance: JSONValue, object: [String: JSONValue],
                                              root: JSONValue, pointer: String,
                                              errors: inout [SchemaValidationError]) {
        guard let items = object["items"], let instanceArray = instance.arrayValue else { return }
        for (index, item) in instanceArray.enumerated() {
            validate(item, against: items, root: root,
                     pointer: pointer + "/\(index)", errors: &errors)
        }
    }

    private static func matches(_ instance: JSONValue, type: String) -> Bool {
        switch type {
        case "string": return instance.stringValue != nil
        case "number": return instance.numericValue != nil
        case "integer": return instance.numericValue != nil && instance.isInteger
        case "boolean": return instance.boolValue != nil
        case "array": return instance.arrayValue != nil
        case "object": return instance.objectValue != nil
        case "null": return instance.isNull
        default: return true
        }
    }

    private static func validFormat(_ instance: JSONValue, _ format: String) -> Bool {
        guard let string = instance.stringValue else { return true }
        switch format {
        case "uuid":
            return UUID(uuidString: string) != nil
        case "date-time":
            return PayloadFormat.date(from: string) != nil
        default:
            return true
        }
    }

    private static func regexMatch(_ pattern: String, _ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// Resolves `#/$defs/NAME` references against the schema document root.
    private static func resolve(_ reference: String, in root: JSONValue) -> JSONValue? {
        guard reference.hasPrefix("#/") else { return nil }
        var node = root
        for component in reference.dropFirst(2).split(separator: "/") {
            guard let dict = node.objectValue,
                  let next = dict[String(component)] else { return nil }
            node = next
        }
        return node
    }
}
