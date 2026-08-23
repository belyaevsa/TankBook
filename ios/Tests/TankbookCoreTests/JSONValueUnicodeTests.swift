import Foundation
import Testing
@testable import TankbookCore

// Regression suite for JSONValue's string decoding (docs/SYNC.md -> payload
// contract). Added after the parser was found to reject EVERY non-ASCII string:
// a payload carrying a Cyrillic station name - the common case for an app that
// ships RU from day one - failed to decode at all.
//
// The existing payload fixtures are all ASCII, which is exactly why the defect
// survived a green suite. These tests exist so that can never be true again.
//
// CONVENTION: this file stays pure ASCII. Non-ASCII characters are constructed
// with `UnicodeScalar`, never typed literally, and JSON escape sequences are
// written as literal backslash text.

private func scalar(_ value: UInt32) -> String {
    String(UnicodeScalar(value)!)
}

private func roundTrip(_ text: String) throws -> String? {
    let json = "{\"k\":\"\(text)\"}"
    return try JSONValue.parse(json).objectValue?["k"]?.stringValue
}

// MARK: - The regression

/// Every UTF-8 sequence width must survive a parse. Before the fix, all four of
/// these threw `invalidUTF8`, because the decoder demanded one continuation byte
/// more than the encoding has.
@Test func stringsOfEveryUTF8WidthRoundTrip() throws {
    let cases: [(String, String)] = [
        ("1-byte ASCII", "plain"),
        ("2-byte Cyrillic", scalar(0x0416)),
        ("2-byte e-acute", scalar(0x00E9)),
        ("3-byte CJK", scalar(0x4E2D)),
        ("4-byte emoji", scalar(0x1F600))
    ]

    for (label, text) in cases {
        #expect(try roundTrip(text) == text, "\(label) did not round-trip")
    }
}

/// The concrete case from the field: a Russian fuel station name.
@Test func cyrillicStationNameRoundTrips() throws {
    let gazprom = "\(scalar(0x0413))\(scalar(0x0430))\(scalar(0x0437))"
        + "\(scalar(0x043F))\(scalar(0x0440))\(scalar(0x043E))\(scalar(0x043C))"

    #expect(try roundTrip(gazprom) == gazprom)
}

/// Mixed-width text in one string: the decoder must advance by the right amount
/// for each character, not a fixed stride. A wrong stride corrupts everything
/// after the first multi-byte character rather than throwing.
@Test func mixedWidthTextRoundTripsIntact() throws {
    let mixed = "a\(scalar(0x0416))b\(scalar(0x4E2D))c\(scalar(0x1F600))d"

    let parsed = try roundTrip(mixed)

    #expect(parsed == mixed)
    #expect(parsed?.count == mixed.count)
}

/// Decode -> encode must preserve the bytes, which is the payload contract's
/// forward-compatibility invariant (docs/SYNC.md). A parser that mangles
/// multi-byte text breaks this silently.
@Test func nonASCIISurvivesDecodeThenEncode() throws {
    let text = "\(scalar(0x0416))\(scalar(0x4E2D))\(scalar(0x1F600))"
    let json = "{\"k\":\"\(text)\"}"

    let encoded = try JSONValue.parse(json).jsonString()

    #expect(encoded == json)
}

/// Non-ASCII inside object KEYS, not just values - keys go through the same
/// string decoder.
@Test func nonASCIIObjectKeysRoundTrip() throws {
    let key = "\(scalar(0x0441))\(scalar(0x0442))" // Cyrillic "st"
    let parsed = try JSONValue.parse("{\"\(key)\":1}")

    #expect(parsed.objectValue?[key] != nil, "the key was mangled during decoding")
}

// MARK: - Escaped form

/// `\uXXXX` escapes and the raw characters they denote must decode identically.
@Test func escapedAndRawFormsDecodeToTheSameString() throws {
    let raw = "\(scalar(0x0416))\(scalar(0x4E2D))"

    let fromEscape = try JSONValue.parse("{\"k\":\"\\u0416\\u4E2D\"}").objectValue?["k"]?.stringValue

    #expect(fromEscape == raw)
}

/// A surrogate PAIR denotes one scalar. The old code appended two scalars - a
/// wrong character followed by a stray one - so an escaped emoji silently became
/// two characters, neither of them the emoji.
@Test func escapedSurrogatePairDecodesToOneScalar() throws {
    let emoji = scalar(0x1F600)

    let parsed = try JSONValue.parse("{\"k\":\"\\uD83D\\uDE00\"}").objectValue?["k"]?.stringValue

    #expect(parsed == emoji)
    #expect(parsed?.unicodeScalars.count == 1, "a surrogate pair is ONE scalar, not two")
    #expect(parsed?.unicodeScalars.first?.value == 0x1F600)
}

@Test func lowercaseAndUppercaseHexEscapesAgree() throws {
    let lower = try JSONValue.parse("{\"k\":\"\\ud83d\\ude00\"}").objectValue?["k"]?.stringValue
    let upper = try JSONValue.parse("{\"k\":\"\\uD83D\\uDE00\"}").objectValue?["k"]?.stringValue

    #expect(lower == upper)
    #expect(lower == scalar(0x1F600))
}

// MARK: - Ill-formed input is rejected, not silently repaired

/// Each of these is ill-formed UTF-8 and must throw. Several are classic
/// smuggling tricks: an overlong encoding can hide an ASCII character (a quote,
/// a slash) from a naive scanner that looks at bytes before decoding.
@Test func illFormedUTF8IsRejected() {
    let prefix = Array("{\"k\":\"".utf8)
    let suffix = Array("\"}".utf8)

    let cases: [(String, [UInt8])] = [
        ("truncated 2-byte", [0xC3]),
        ("2-byte with non-continuation", [0xC3, 0x28]),
        ("truncated 3-byte", [0xE4, 0xB8]),
        ("3-byte with non-continuation", [0xE4, 0x28, 0xAD]),
        ("truncated 4-byte", [0xF0, 0x9F, 0x98]),
        ("stray continuation byte", [0x80]),
        ("overlong 2-byte NUL", [0xC0, 0x80]),
        ("overlong 2-byte slash", [0xC0, 0xAF]),
        ("overlong 3-byte", [0xE0, 0x80, 0xAF]),
        ("surrogate encoded as UTF-8", [0xED, 0xA0, 0x80]),
        ("out of range F5", [0xF5, 0x80, 0x80, 0x80])
    ]

    for (label, payload) in cases {
        let bytes = Data(prefix + payload + suffix)
        #expect(throws: (any Error).self, "should reject: \(label)") {
            _ = try JSONValue.parse(bytes)
        }
    }
}

/// Unpaired surrogates in escaped form are not legal scalars. The old code
/// accepted a lone high surrogate and emitted a wrong character.
@Test func unpairedEscapedSurrogatesAreRejected() {
    let cases = [
        "{\"k\":\"\\uD83D\"}",          // lone high surrogate
        "{\"k\":\"\\uDE00\"}",          // lone low surrogate
        "{\"k\":\"\\uD83D\\u0041\"}",   // high surrogate followed by a normal escape
        "{\"k\":\"\\uD83D\\uD83D\"}"    // two high surrogates
    ]

    for json in cases {
        #expect(throws: (any Error).self, "should reject: \(json)") {
            _ = try JSONValue.parse(json)
        }
    }
}

// MARK: - Guard against the fixture blind spot

/// The defect survived because every payload fixture was ASCII. This asserts the
/// corpus now exercises non-ASCII somewhere, so an ASCII-only corpus cannot
/// quietly return.
@Test func payloadFixtureCorpusContainsNonASCII() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let corpus = repoRoot.appendingPathComponent("docs/fixtures/payloads/v1")

    let names = try FileManager.default.contentsOfDirectory(atPath: corpus.path)
        .filter { $0.hasSuffix(".json") }
    #expect(!names.isEmpty, "no fixtures found at \(corpus.path)")

    var sawNonASCII = false
    for name in names {
        let data = try Data(contentsOf: corpus.appendingPathComponent(name))
        // Every fixture must still parse, whatever it contains.
        _ = try JSONValue.parse(data)
        if data.contains(where: { $0 > 0x7F }) { sawNonASCII = true }
    }

    #expect(sawNonASCII, "the payload fixture corpus is entirely ASCII - the blind spot that hid the defect")
}
