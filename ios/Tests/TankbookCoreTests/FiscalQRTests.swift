import Foundation
import Testing
@testable import TankbookCore

// P2.6 (parser half): the fiscal QR payload parser, anchor, cross-check and
// duplicate identity. Ground truth is the real decoded QR payloads committed
// under Spike/ReceiptSpike/fixtures - read from disk, never pasted as literals.

private let utc = TimeZone(identifier: "UTC")!
private let moscow = TimeZone(identifier: "Europe/Moscow")!

// MARK: - Fixture plumbing

private func repoRoot() -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0 ..< 8 {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("CLAUDE.md").path) {
            return directory
        }
        directory = directory.deletingLastPathComponent()
    }
    fatalError("repo root (CLAUDE.md) not found above the test file")
}

private let receiptsDir = repoRoot().appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")
private let fiscalDir = repoRoot().appendingPathComponent("Spike/ReceiptSpike/fixtures/fiscal")

private func qrFixtureBases() throws -> [String] {
    var bases: [String] = []
    for dir in [receiptsDir, fiscalDir] {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        for name in files where name.hasSuffix(".qr.txt") {
            bases.append(String(name.dropLast(".qr.txt".count)))
        }
    }
    return bases.sorted()
}

private func qrPayload(_ base: String) throws -> String {
    for dir in [receiptsDir, fiscalDir] {
        let url = dir.appendingPathComponent("\(base).qr.txt")
        if FileManager.default.fileExists(atPath: url.path) {
            return try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    throw CocoaError(.fileNoSuchFile)
}

/// The `total` column of every `expected.csv`, keyed by fixture base name.
private func expectedTotals() throws -> [String: Decimal] {
    let locale = Locale(identifier: "en_US_POSIX")
    var result: [String: Decimal] = [:]
    for dir in [receiptsDir, fiscalDir] {
        let content = try String(contentsOf: dir.appendingPathComponent("expected.csv"), encoding: .utf8)
        for line in content.split(separator: "\n") {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count == 4 else { continue }
            let filename = String(cols[0])
            guard !filename.isEmpty, filename != "filename" else { continue }
            let base = (filename as NSString).deletingPathExtension
            result[base] = Decimal(string: String(cols[3]), locale: locale)
        }
    }
    return result
}

private func localDate(components: DateComponents, in timeZone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: components)!
}

// MARK: - 1. Every committed fixture parses and reconciles with the expected total

@Test func allCommittedFixturesParseAndMatchExpectedTotals() throws {
    let expected = try expectedTotals()
    let bases = try qrFixtureBases()
    // A FLOOR, not a frozen count. Pinning the exact number means every corpus
    // contribution breaks this test, which is how a fixture suite stops growing.
    // What matters is that every committed payload parses, not that there are
    // exactly N of them.
    #expect(bases.count >= 11, "expected at least 11 committed QR fixtures, found \(bases.count)")
    var mixedCount = 0
    for base in bases {
        let raw = try qrPayload(base)
        let payload = try FiscalQRParser.parse(raw, timeZone: utc)
        let expectedTotal = try #require(expected[base], "no expected total for \(base)")
        // expected.csv records the FILL-UP amount (the fuel line, hard rule 4), so
        // on a non-mixed receipt it equals the QR grand total and on a mixed receipt
        // the QR grand total exceeds it. The cross-check tells the two apart.
        let result = FiscalQRCrossCheck.classify(qrTotal: payload.total, candidateTotal: expectedTotal)
        switch result {
        case .agrees:
            #expect(payload.total == expectedTotal,
                    "\(base): total \(payload.total) != expected \(expectedTotal)")
        case .suggestsMixedReceipt:
            // receipt-009: the QR grand total exceeds the fuel line by the non-fuel items.
            #expect(payload.total > expectedTotal,
                    "\(base): QR grand total \(payload.total) should exceed the fuel line \(expectedTotal)")
            mixedCount += 1
        case .disagrees:
            Issue.record("\(base): QR total \(payload.total) disagrees with expected total \(expectedTotal)")
        }
    }
    #expect(mixedCount == 1, "exactly one mixed fixture expected, found \(mixedCount)")
}

// MARK: - 2. Both timestamp forms parse to the correct instant

@Test func timestampParsesWithoutSeconds() throws {
    // receipt-002 carries t=20260711T1512 (no seconds) - the common ФНС form.
    let raw = try qrPayload("receipt-002-krymoil-yalta-100-ru")
    let payload = try FiscalQRParser.parse(raw, timeZone: moscow)
    #expect(payload.timestamp == localDate(components: DateComponents(year: 2026, month: 7, day: 11,
                                                                      hour: 15, minute: 12), in: moscow))
}

@Test func timestampParsesWithSeconds() throws {
    // fiscal-002 carries t=20260818T193700 (with seconds).
    let raw = try qrPayload("fiscal-002-lukoil-ru")
    let payload = try FiscalQRParser.parse(raw, timeZone: moscow)
    #expect(payload.timestamp == localDate(components: DateComponents(year: 2026, month: 8, day: 18,
                                                                      hour: 19, minute: 37), in: moscow))
}

// MARK: - 3. Variable-length fp / i all parse

@Test func fiscalSignAndDocumentNumberAreVariableLength() throws {
    // Across the corpus fp is 8, 9 and 10 digits; i is variable too. The parser
    // must accept numbers, never a fixed-format code.
    let fpLengths: [String: Int] = [
        "receipt-010-gazpromneft-diesel-bonus-ru": 8,   // fp=91817583
        "receipt-014-orion-penza-95-ru": 9,             // fp=577695261
        "fiscal-001-gpn-ru": 10                         // fp=4235874914
    ]
    for (base, expectedLength) in fpLengths {
        let raw = try qrPayload(base)
        let payload = try FiscalQRParser.parse(raw, timeZone: utc)
        #expect(payload.fiscalSign.count == expectedLength,
                "\(base): fp length \(payload.fiscalSign.count) != \(expectedLength)")
        #expect(payload.fiscalSign.allSatisfy { $0.isNumber })
        #expect(!payload.documentNumber.isEmpty && payload.documentNumber.allSatisfy { $0.isNumber })
        #expect(!payload.fiscalDriveNumber.isEmpty && payload.fiscalDriveNumber.allSatisfy { $0.isNumber })
    }
}

// MARK: - 4. `total` is an exact Decimal, never a Double

@Test func totalParsesAsExactDecimal() throws {
    // Money values, including ones a binary float cannot represent (0.1, 0.3).
    for value in ["4201.68", "0.1", "0.2", "0.3", "1680.38", "2385.83"] {
        let raw = "t=20260711T1512&s=\(value)&fn=1&i=2&fp=3&n=1"
        let payload = try FiscalQRParser.parse(raw, timeZone: utc)
        #expect(payload.total == Decimal(string: value)!, "\(value) must round-trip exactly as a Decimal")
    }
}

@Test func totalDoesNotRouteThroughBinaryFloat() throws {
    // 1680.38 has no exact binary representation: through a Double it becomes
    // 1680.3800000000004096, so the parser must stay in Decimal.
    let payload = try FiscalQRParser.parse("t=20260711T1512&s=1680.38&fn=1&i=2&fp=3&n=1", timeZone: utc)
    #expect(payload.total == Decimal(string: "1680.38")!)
    #expect(payload.total != Decimal(Double("1680.38")!))
}

// MARK: - 5. Malformed input is rejected cleanly, never crashes

@Test func emptyInputIsRejected() {
    #expect(throws: FiscalQRParseError.emptyInput) {
        _ = try FiscalQRParser.parse("", timeZone: utc)
    }
}

@Test func truncatedInputIsRejected() {
    // The task's truncated example: the payload is cut off mid-way, so the total
    // has no value and the remaining keys are absent. Rejected, never crashes.
    #expect(throws: FiscalQRParseError.self) {
        _ = try FiscalQRParser.parse("t=20260711T1512&s=", timeZone: utc)
    }
    // And when only the total's value is empty (every key present), it is a
    // non-numeric total.
    #expect(throws: FiscalQRParseError.nonNumericTotal) {
        _ = try FiscalQRParser.parse("t=20260711T1512&s=&fn=1&i=2&fp=3&n=1", timeZone: utc)
    }
}

@Test func missingRequiredKeyIsRejected() {
    #expect(throws: FiscalQRParseError.missingField(.total)) {
        _ = try FiscalQRParser.parse("t=20260711T1512&fn=1&i=2&fp=3&n=1", timeZone: utc)
    }
}

@Test func nonNumericTotalIsRejected() {
    #expect(throws: FiscalQRParseError.nonNumericTotal) {
        _ = try FiscalQRParser.parse("t=20260711T1512&s=abc&fn=1&i=2&fp=3&n=1", timeZone: utc)
    }
}

@Test func duplicatedKeyIsRejected() {
    #expect(throws: FiscalQRParseError.duplicatedField(.total)) {
        _ = try FiscalQRParser.parse("t=20260711T1512&s=1&s=2&fn=1&i=2&fp=3&n=1", timeZone: utc)
    }
}

@Test func absurdlyLongInputIsRejected() {
    let long = String(repeating: "x", count: 10_000)
    #expect(throws: FiscalQRParseError.inputTooLong) {
        _ = try FiscalQRParser.parse(long, timeZone: utc)
    }
}

@Test func junkInputIsRejected() {
    #expect(throws: FiscalQRParseError.malformedPair) {
        _ = try FiscalQRParser.parse("\u{FFFD}garbage\u{0}\u{1}\u{2}", timeZone: utc)
    }
}

@Test func unknownExtraKeysAreTolerated() throws {
    // The format may grow: unknown keys (and even an unknown key with an empty
    // value) must be ignored, not rejected.
    let raw = "t=20260711T1512&s=4201.68&fn=1&i=2&fp=3&n=1&foo=bar&EXTRA=42&x="
    let payload = try FiscalQRParser.parse(raw, timeZone: utc)
    #expect(payload.total == Decimal(string: "4201.68")!)
    #expect(payload.operationType == 1)
}

// MARK: - 6. The anchor leaves litres, price and fuel kind empty

@Test func anchorLeavesUncarriedFieldsNil() throws {
    let payload = try FiscalQRParser.parse("t=20260711T1512&s=4201.68&fn=1&i=2&fp=3&n=1", timeZone: utc)
    let anchor = payload.anchor
    #expect(anchor.total == Decimal(string: "4201.68")!)
    #expect(anchor.date == payload.timestamp)
    // nil, not zero: a zero litre count is a wrong fact, nil is an honest absence.
    #expect(anchor.liters == nil)
    #expect(anchor.unitPrice == nil)
    #expect(anchor.fuelKind == nil)
}

// MARK: - 6b. The cross-check, one test per outcome

@Test func crossCheckAgrees() {
    let result = FiscalQRCrossCheck.classify(qrTotal: Decimal(string: "4201.68")!,
                                             candidateTotal: Decimal(string: "4201.68")!)
    #expect(result == .agrees)
}

@Test func crossCheckDisagreesOnVATLine() {
    // receipt-011: the parser's actual wrong total was the VAT line, 700.28.
    let result = FiscalQRCrossCheck.classify(qrTotal: Decimal(string: "4201.68")!,
                                             candidateTotal: Decimal(string: "700.28")!)
    #expect(result == .disagrees)
}

@Test func crossCheckDisagreesOnRoundingLine() {
    // receipt-012: the parser's actual wrong total was the rounding line, 0.08.
    let result = FiscalQRCrossCheck.classify(qrTotal: Decimal(string: "1251.00")!,
                                             candidateTotal: Decimal(string: "0.08")!)
    #expect(result == .disagrees)
}

@Test func crossCheckSuggestsMixedReceipt() {
    // receipt-009: QR grand total 6264.00, fuel line 6135.24. The 128.76 gap is
    // a 129.00 bottle of water less the 0.24 the receipt rounds off its own grand
    // total (ОКРУГЛЕНИЕ). This is mixed, NOT a disagreement, and the fuel line stands.
    let qr = Decimal(string: "6264.00")!
    let fuelLine = Decimal(string: "6135.24")!
    let result = FiscalQRCrossCheck.classify(qrTotal: qr, candidateTotal: fuelLine)
    #expect(result == .suggestsMixedReceipt)
    #expect(result != .disagrees)
}

@Test func crossCheckToleratesWholeRoubleRounding() {
    // ЛУКОЙЛ rounds the fiscal total down to the whole rouble (fiscal-002:
    // 1680.38 -> 1680.00), so a rouble-or-less gap still agrees.
    #expect(FiscalQRCrossCheck.classify(qrTotal: Decimal(string: "1680.00")!,
                                        candidateTotal: Decimal(string: "1680.38")!) == .agrees)
    #expect(FiscalQRCrossCheck.classify(qrTotal: Decimal(string: "4334.00")!,
                                        candidateTotal: Decimal(string: "4334.83")!) == .agrees)
    // Exactly one rouble off still agrees.
    #expect(FiscalQRCrossCheck.classify(qrTotal: Decimal(string: "1251.00")!,
                                        candidateTotal: Decimal(string: "1250.00")!) == .agrees)
}

// MARK: - 7. Duplicate identity

@Test func identitySharedAcrossRescans() throws {
    // Same fn/i/fp, different date and total: one fiscal document, one purchase.
    let first = try FiscalQRParser.parse("t=20260711T1512&s=1.00&fn=111&i=222&fp=333&n=1", timeZone: utc)
    let rescan = try FiscalQRParser.parse("t=20260811T1512&s=2.00&fn=111&i=222&fp=333&n=1", timeZone: utc)
    #expect(first.fiscalDocumentIdentity == rescan.fiscalDocumentIdentity)
    #expect(first.fiscalDocumentIdentity.key == rescan.fiscalDocumentIdentity.key)
}

@Test func identityChangesWithAnyComponent() throws {
    let base = try FiscalQRParser.parse("t=20260711T1512&s=1.00&fn=111&i=222&fp=333&n=1", timeZone: utc)
    let changedFn = try FiscalQRParser.parse("t=20260711T1512&s=1.00&fn=999&i=222&fp=333&n=1", timeZone: utc)
    let changedI = try FiscalQRParser.parse("t=20260711T1512&s=1.00&fn=111&i=999&fp=333&n=1", timeZone: utc)
    let changedFp = try FiscalQRParser.parse("t=20260711T1512&s=1.00&fn=111&i=222&fp=999&n=1", timeZone: utc)
    #expect(base.fiscalDocumentIdentity != changedFn.fiscalDocumentIdentity)
    #expect(base.fiscalDocumentIdentity != changedI.fiscalDocumentIdentity)
    #expect(base.fiscalDocumentIdentity != changedFp.fiscalDocumentIdentity)
}

// MARK: - 8. Timezone is injected, not ambient

@Test func timezoneIsInjectedNotAmbient() throws {
    let raw = "t=20260711T1512&s=4201.68&fn=1&i=2&fp=3&n=1"
    let inMoscow = try FiscalQRParser.parse(raw, timeZone: moscow)
    let inUTC = try FiscalQRParser.parse(raw, timeZone: utc)
    #expect(inMoscow.timestamp != inUTC.timestamp)
    // Moscow is UTC+3: the same wall-clock time is three hours later in UTC.
    #expect(inMoscow.timestamp.addingTimeInterval(3 * 3600) == inUTC.timestamp)
}
