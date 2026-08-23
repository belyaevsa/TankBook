import Foundation

/// A small, lossless JSON tree used as the payload representation in the
/// payload contract (docs/SYNC.md -> Payload contract and versioning).
///
/// Numbers keep their *raw token* (`number("289.50")`), so a value read from a
/// wire payload re-encodes byte-identically - the forward-compatibility
/// invariant is about bytes, not values.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// A raw JSON number token (e.g. "42.3", "-7", "1e5").
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Accessors

    public var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Numeric value of a `.number` token, or nil for a non-number.
    public var numericValue: Double? {
        if case .number(let token) = self { return Double(token) }
        return nil
    }

    /// True when the token is an integer (no fraction/exponent).
    public var isInteger: Bool {
        if case .number(let token) = self {
            return !token.contains(".") && !token.contains("e") && !token.contains("E")
        }
        return false
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: Parsing

    /// Parses a complete JSON document.
    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: [UInt8](data))
        let value = try parser.parseDocument()
        return value
    }

    /// Parses a complete JSON document from a UTF-8 string.
    public static func parse(_ string: String) throws -> JSONValue {
        try parse(Data(string.utf8))
    }

    // MARK: Serialization

    /// Serializes compactly. Object keys are sorted so output is canonical.
    public func jsonData() throws -> Data {
        var bytes: [UInt8] = []
        append(to: &bytes)
        return Data(bytes)
    }

    /// Serializes compactly as a UTF-8 string.
    public func jsonString() throws -> String {
        let data = try jsonData()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func append(to bytes: inout [UInt8]) {
        switch self {
        case .null: bytes.append(contentsOf: Array("null".utf8))
        case .bool(let value): bytes.append(contentsOf: Array((value ? "true" : "false").utf8))
        case .number(let token): bytes.append(contentsOf: Array(token.utf8))
        case .string(let value): Self.appendString(value, to: &bytes)
        case .array(let items):
            bytes.append(0x5B) // [
            for (index, item) in items.enumerated() {
                if index > 0 { bytes.append(0x2C) } // ,
                item.append(to: &bytes)
            }
            bytes.append(0x5D) // ]
        case .object(let entries):
            bytes.append(0x7B) // {
            let sorted = entries.sorted { $0.key < $1.key }
            for (index, entry) in sorted.enumerated() {
                if index > 0 { bytes.append(0x2C) } // ,
                Self.appendString(entry.key, to: &bytes)
                bytes.append(0x3A) // :
                entry.value.append(to: &bytes)
            }
            bytes.append(0x7D) // }
        }
    }

    private static func appendString(_ string: String, to bytes: inout [UInt8]) {
        bytes.append(0x22) // "
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: bytes.append(contentsOf: Array("\\\"".utf8))
            case 0x5C: bytes.append(contentsOf: Array("\\\\".utf8))
            case 0x08: bytes.append(contentsOf: Array("\\b".utf8))
            case 0x0C: bytes.append(contentsOf: Array("\\f".utf8))
            case 0x0A: bytes.append(contentsOf: Array("\\n".utf8))
            case 0x0D: bytes.append(contentsOf: Array("\\r".utf8))
            case 0x09: bytes.append(contentsOf: Array("\\t".utf8))
            case 0 ... 0x1F:
                bytes.append(contentsOf: Array(String(format: "\\u%04x", scalar.value).utf8))
            default:
                bytes.append(contentsOf: String(scalar).utf8)
            }
        }
        bytes.append(0x22) // "
    }
}

/// Recursive-descent JSON parser. Numbers keep their raw token so they can be
/// re-emitted byte-identically.
private struct Parser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        if index != bytes.count {
            throw JSONParseError.trailingCharacters(at: index)
        }
        return value
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    private mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard index < bytes.count else { throw JSONParseError.unexpectedEnd }
        switch bytes[index] {
        case 0x7B: return try parseObject()   // {
        case 0x5B: return try parseArray()    // [
        case 0x22: return .string(try parseString())  // "
        case 0x74: return try parseLiteral("true", .bool(true))
        case 0x66: return try parseLiteral("false", .bool(false))
        case 0x6E: return try parseLiteral("null", .null)
        case 0x2D, 0x30 ... 0x39: return try parseNumber()  // - or digit
        default: throw JSONParseError.unexpectedCharacter(at: index)
        }
    }

    private mutating func parseLiteral(_ literal: String, _ value: JSONValue) throws -> JSONValue {
        let literalBytes = Array(literal.utf8)
        guard index + literalBytes.count <= bytes.count else { throw JSONParseError.unexpectedEnd }
        for (offset, byte) in literalBytes.enumerated() where bytes[index + offset] != byte {
            throw JSONParseError.unexpectedCharacter(at: index)
        }
        index += literalBytes.count
        return value
    }

    private mutating func parseObject() throws -> JSONValue {
        index += 1 // {
        var entries: [String: JSONValue] = [:]
        skipWhitespace()
        if index < bytes.count, bytes[index] == 0x7D { index += 1; return .object(entries) } // }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw JSONParseError.unexpectedCharacter(at: index)
            }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x3A else { throw JSONParseError.expectColon(at: index) } // :
            index += 1
            let value = try parseValue()
            entries[key] = value
            skipWhitespace()
            guard index < bytes.count else { throw JSONParseError.unexpectedEnd }
            switch bytes[index] {
            case 0x2C: index += 1 // ,
            case 0x7D: index += 1; return .object(entries) // }
            default: throw JSONParseError.unexpectedCharacter(at: index)
            }
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        index += 1 // [
        var items: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == 0x5D { index += 1; return .array(items) } // ]
        while true {
            items.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw JSONParseError.unexpectedEnd }
            switch bytes[index] {
            case 0x2C: index += 1 // ,
            case 0x5D: index += 1; return .array(items) // ]
            default: throw JSONParseError.unexpectedCharacter(at: index)
            }
        }
    }

    private mutating func parseString() throws -> String {
        index += 1 // "
        var scalars: [UInt32] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x22 { // "
                return String(String.UnicodeScalarView(scalars.compactMap(Unicode.Scalar.init)))
            }
            if byte == 0x5C { // backslash
                guard index < bytes.count else { throw JSONParseError.unexpectedEnd }
                let escape = bytes[index]
                index += 1
                switch escape {
                case 0x22: scalars.append(0x22)
                case 0x5C: scalars.append(0x5C)
                case 0x2F: scalars.append(0x2F)
                case 0x62: scalars.append(0x08)
                case 0x66: scalars.append(0x0C)
                case 0x6E: scalars.append(0x0A)
                case 0x72: scalars.append(0x0D)
                case 0x74: scalars.append(0x09)
                case 0x75:
                    guard let scalar = try parseHexScalar() else { throw JSONParseError.invalidUnicode(at: index) }
                    if scalar.isHighSurrogate, index + 6 <= bytes.count,
                       bytes[index] == 0x5C, bytes[index + 1] == 0x75 {
                        index += 2
                        guard let low = try parseHexScalar(), low.isLowSurrogate else {
                            throw JSONParseError.invalidUnicode(at: index)
                        }
                        scalars.append(scalar.decomposedHighSurrogate)
                        scalars.append(low.decomposedLowSurrogate)
                    } else {
                        scalars.append(scalar)
                    }
                default: throw JSONParseError.invalidEscape(at: index)
                }
            } else if byte < 0x20 {
                throw JSONParseError.controlCharacterInString(at: index)
            } else if byte < 0x80 {
                scalars.append(UInt32(byte))
            } else if byte < 0xC0 {
                throw JSONParseError.invalidUTF8(at: index)
            } else if byte < 0xE0 {
                guard index + 1 < bytes.count,
                      (bytes[index] & 0xC0) == 0x80, (bytes[index + 1] & 0xC0) == 0x80 else {
                    throw JSONParseError.invalidUTF8(at: index)
                }
                scalars.append(UInt32(byte & 0x1F) << 6 | UInt32(bytes[index] & 0x3F))
                index += 2
            } else if byte < 0xF0 {
                guard index + 2 < bytes.count,
                      (bytes[index] & 0xC0) == 0x80, (bytes[index + 1] & 0xC0) == 0x80,
                      (bytes[index + 2] & 0xC0) == 0x80 else {
                    throw JSONParseError.invalidUTF8(at: index)
                }
                scalars.append(UInt32(byte & 0x0F) << 12 | UInt32(bytes[index] & 0x3F) << 6 | UInt32(bytes[index + 2] & 0x3F))
                index += 3
            } else {
                guard index + 3 < bytes.count,
                      (bytes[index] & 0xC0) == 0x80, (bytes[index + 1] & 0xC0) == 0x80,
                      (bytes[index + 2] & 0xC0) == 0x80, (bytes[index + 3] & 0xC0) == 0x80 else {
                    throw JSONParseError.invalidUTF8(at: index)
                }
                scalars.append(UInt32(byte & 0x07) << 18 | UInt32(bytes[index] & 0x3F) << 12
                    | UInt32(bytes[index + 2] & 0x3F) << 6 | UInt32(bytes[index + 3] & 0x3F))
                index += 4
            }
        }
        throw JSONParseError.unexpectedEnd
    }

    private mutating func parseHexScalar() throws -> UInt32? {
        guard index + 4 <= bytes.count,
              let digits = String(bytes: bytes[index ..< index + 4], encoding: .utf8),
              let scalar = UInt32(digits, radix: 16) else {
            return nil
        }
        index += 4
        return scalar
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        if index < bytes.count, bytes[index] == 0x2D { index += 1 } // -
        var seenDigit = false
        while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
            index += 1
            seenDigit = true
        }
        guard seenDigit else { throw JSONParseError.invalidNumber(at: index) }
        if index < bytes.count, bytes[index] == 0x2E { // .
            index += 1
            var fractionDigits = false
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                index += 1
                fractionDigits = true
            }
            guard fractionDigits else { throw JSONParseError.invalidNumber(at: index) }
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 { // e E
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            let expStart = index
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
            guard index > expStart else { throw JSONParseError.invalidNumber(at: index) }
        }
        let token = String(bytes: bytes[start ..< index], encoding: .utf8) ?? ""
        return .number(token)
    }
}

private enum JSONParseError: Error, Equatable {
    case trailingCharacters(at: Int)
    case unexpectedEnd
    case unexpectedCharacter(at: Int)
    case expectColon(at: Int)
    case invalidUnicode(at: Int)
    case invalidEscape(at: Int)
    case controlCharacterInString(at: Int)
    case invalidUTF8(at: Int)
    case invalidNumber(at: Int)
}

extension UInt32 {
    var isHighSurrogate: Bool { self >= 0xD800 && self <= 0xDBFF }
    var isLowSurrogate: Bool { self >= 0xDC00 && self <= 0xDFFF }
    var decomposedHighSurrogate: UInt32 { 0x10000 + (self - 0xD800) << 10 }
    var decomposedLowSurrogate: UInt32 { self - 0xDC00 }
}
