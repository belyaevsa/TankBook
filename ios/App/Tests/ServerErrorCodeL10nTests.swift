import XCTest

/// PR.9/OB.1 - L1: every user-visible phrase that a server error `code` can now
/// drive exists in the String Catalog in BOTH languages, and the Russian entry
/// is a real translation - never a copy of the English key (the RV.58 trap).
///
/// The codes themselves are classified in core (`ServerErrorCode` +
/// per-owner mappings, tested there, including the unknown-code -> status
/// fallback). What only this bundle can check is the L10n half: the catalog is
/// compiled into the app, and the source `.xcstrings` is read from the repo so
/// the test stays meaningful in CI (the ReleaseSeedGateTests pattern). The
/// localization gate enforces that a literal used in app source has a catalog
/// entry; this test additionally pins that the entry is present in EN **and**
/// RU and that RU differs from EN.
final class ServerErrorCodeL10nTests: XCTestCase {

    /// The catalog keys the coded envelope added or sharpened (PR.9): each is
    /// reachable only because a code told the client something the status alone
    /// could not (docs/ERRORS.md -> Sign in). If a key is dropped the test fails
    /// - a mapping to copy that no longer exists is exactly the silent drift a
    /// code contract cannot afford.
    private static let codedCopyKeys = [
        "%@ couldn't sign you in – try again.",
        "Your device's date looks off (%1$@) – sign-in needs it correct. Open Settings > Date & Time.",
    ]

    func testCodedCopyKeysExistInEnglishAndRussianAndAreDistinct() throws {
        let catalog = try Self.readCatalog()

        for key in Self.codedCopyKeys {
            let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
            let entry = try XCTUnwrap(
                strings[key] as? [String: Any],
                "code-driven key is missing from Localizable.xcstrings: \(key)")

            let en = Self.value(entry, language: "en")
            let ru = Self.value(entry, language: "ru")

            XCTAssertNotNil(en, "missing English translation for \(key)")
            XCTAssertNotNil(ru, "missing Russian translation for \(key)")

            if let en, let ru {
                XCTAssertNotEqual(ru, en,
                                  "Russian entry for \(key) is a byte-copy of the English one")
                XCTAssertNotEqual(ru, key,
                                  "Russian entry for \(key) is the untranslated key itself")
                XCTAssertFalse(en.isEmpty && ru.isEmpty)
            }
        }
    }

    // MARK: - Catalog reading

    /// Reads the committed String Catalog from the repo (this test file lives at
    /// `ios/App/Tests/...`, four levels below the repo root).
    private static func readCatalog() throws -> [String: Any] {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let catalogURL = candidate.appendingPathComponent("ios/App/Sources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "cannot parse Localizable.xcstrings at \(catalogURL.path)")
        return object
    }

    private static func value(_ entry: [String: Any], language: String) -> String? {
        let localizations = entry["localizations"] as? [String: Any]
        let languageEntry = localizations?[language] as? [String: Any]
        let stringUnit = languageEntry?["stringUnit"] as? [String: Any]
        return stringUnit?["value"] as? String
    }
}
