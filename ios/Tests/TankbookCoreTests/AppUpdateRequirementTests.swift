import Foundation
import Testing
@testable import TankbookCore

// P6.18a: the update requirement, core only (docs/CONFIG.md -> "App version and
// the update notice"). The server states two facts - the two thresholds - and
// the client derives one sign: `.none` / `.recommended` / `.required`.
//
// The four invariants, each with a named mutation that must break it:
// 1. Numeric per-component comparison, never lexicographic - `1.10.0` vs
//    `1.9.0` is the one pair that separates the two implementations.
// 2. Fail OPEN, never closed - absent key, malformed threshold, malformed
//    running version: all `.none`.
// 3. Two thresholds, one derived value, boundaries inclusive on the low side.
// 4. An unknown sibling key never blocks `appUpdate` (forward compatibility).
//
// Document-shape choice, made deliberately: `AppVersion` parses exactly three
// dotted numeric components. Two components (`"1.2"`) do NOT parse - a missing
// component is a guess, not a fact (hard rule 13) - and the tests below pin
// the rejected cases, including the two-component one.

// MARK: - Document builder

/// A schema-valid document carrying an `appUpdate` key (or none), so the
/// decode path - not a hand-built `AppUpdateNotice` - is what produces the
/// value under test. `minSupportedVersion`/`latestVersion` are raw JSON
/// strings; passing garbage here is exactly how the fail-open tests work.
private func updateDocument(
    appUpdate: String? = nil,
    tier3: Bool = true,
    extraUnknown: String? = nil
) throws -> ConfigDocument {
    var fields: [String] = [
        "\"version\": 7",
        "\"issuedAt\": \"2026-01-01T00:00:00Z\"",
        "\"notAfter\": \"2099-01-01T00:00:00Z\"",
        "\"apiBaseUrl\": \"https://api.tankbook.live\"",
        "\"tier2OnDeviceLLM\": true",
        "\"tier3CloudFallback\": \(tier3)",
        "\"llmQuota\": {\"onDeviceLLM\": 200, \"cloudFallback\": 50}",
        "\"ocrConfidenceThreshold\": 0.75",
        "\"minSchemaVersion\": 1",
        "\"referencePacks\": {\"rates\": 1, \"catalog\": 1}",
        "\"rolloutSalt\": \"update-test-salt\""
    ]
    if let appUpdate { fields.append("\"appUpdate\": \(appUpdate)") }
    if let extraUnknown { fields.append("\"\(extraUnknown)\": {\"nested\": 1}") }
    let data = Data(("{ " + fields.joined(separator: ", ") + " }").utf8)
    return try ConfigDocument.parse(data)
}

private func resolve(_ document: ConfigDocument) -> AppConfig {
    AppConfig(document: document, apiBaseURL: document.apiBaseURL!)
}

private func validAppUpdateJSON(min: String, latest: String) -> String {
    "{\"minSupportedVersion\": \"\(min)\", \"latestVersion\": \"\(latest)\"}"
}

/// The canonical thresholds for boundary tests: min 1.2.0, latest 1.4.0
/// (docs/CONFIG.md's own example values).
private func canonicalConfig() throws -> AppConfig {
    resolve(try updateDocument(appUpdate: validAppUpdateJSON(min: "1.2.0", latest: "1.4.0")))
}

// MARK: - 1. Numeric comparison, not lexicographic

@Test func versionsCompareNumericallyPerComponentNotLexicographically() {
    // THE load-bearing pair: 1.10.0 is newer than 1.9.0 numerically; a string
    // compare says the opposite. A test set without this pair is vacuous.
    let oneTen = AppVersion("1.10.0")!
    let oneNine = AppVersion("1.9.0")!
    #expect(oneTen > oneNine)
    #expect(oneNine < oneTen)
    #expect(oneTen != oneNine)

    // The same separation one level down.
    #expect(AppVersion("1.2.10")! > AppVersion("1.2.9")!)
    // And across components: minor 10 beats minor 9 even with a smaller patch.
    #expect(AppVersion("2.10.0")! > AppVersion("2.9.9")!)
}

@Test func numericComparisonDrivesTheRequirementNotStringOrder() throws {
    // min 1.9.0, latest 1.11.0, running 1.10.0: numerically the running build
    // is above min (recommended). A lexicographic compare ranks "1.10.0" below
    // "1.9.0" and would derive .required - the mutation this test exists to
    // catch at the decision level, not just in AppVersion.
    let config = resolve(try updateDocument(appUpdate: validAppUpdateJSON(min: "1.9.0", latest: "1.11.0")))
    #expect(config.updateRequirement(runningVersion: "1.10.0") == .recommended)
    #expect(config.updateRequirement(runningVersion: "1.9.10") == .recommended)
}

// MARK: - 2. Fail open, never closed

@Test func absentAppUpdateKeyIsNilAndNeverRequired() throws {
    let config = resolve(try updateDocument())
    #expect(config.appUpdate == nil)
    // Even an ancient build is told nothing: a device that has never reached
    // the network is never told it is out of date.
    #expect(config.updateRequirement(runningVersion: "0.1.0") == .none)
}

@Test func malformedMinSupportedVersionFailsOpen() throws {
    // Two components: a deliberate non-parse (see the file header), not an
    // accidental "still valid dotted numerics" fixture.
    let twoComponents = resolve(try updateDocument(
        appUpdate: validAppUpdateJSON(min: "1.2", latest: "1.4.0")))
    #expect(twoComponents.appUpdate == nil, "a malformed threshold must degrade the key to nil")
    #expect(twoComponents.updateRequirement(runningVersion: "0.1.0") == .none)

    let garbage = resolve(try updateDocument(
        appUpdate: validAppUpdateJSON(min: "one-point-two", latest: "1.4.0")))
    #expect(garbage.appUpdate == nil)
    #expect(garbage.updateRequirement(runningVersion: "0.1.0") == .none)
}

@Test func malformedLatestVersionFailsOpen() throws {
    let config = resolve(try updateDocument(
        appUpdate: validAppUpdateJSON(min: "1.2.0", latest: "1.4.0-beta")))
    #expect(config.appUpdate == nil)
    #expect(config.updateRequirement(runningVersion: "0.1.0") == .none)
}

@Test func appUpdateObjectMissingAThresholdFailsOpen() throws {
    // Only minSupportedVersion present: latestVersion is absent, so the whole
    // key degrades to nil rather than guessing a latest.
    let config = resolve(try updateDocument(appUpdate: "{\"minSupportedVersion\": \"1.2.0\"}"))
    #expect(config.appUpdate == nil)
    #expect(config.updateRequirement(runningVersion: "0.1.0") == .none)
}

@Test func unparseableRunningVersionFailsOpen() throws {
    let config = try canonicalConfig()
    // A CFBundleShortVersionString that will not parse yields .none, logged at
    // WARN by the surface (P6.18b) - never .required, which would withhold
    // sync from every install with one bad string.
    #expect(config.updateRequirement(runningVersion: "soon") == .none)
    #expect(config.updateRequirement(runningVersion: "1.2") == .none)
    #expect(config.updateRequirement(runningVersion: "") == .none)
}

// MARK: - 3. Two thresholds, one derived value, boundaries

@Test func runningAtOrAboveLatestIsNone() throws {
    let config = try canonicalConfig()
    // Equality with latestVersion is .none - an off-by-one here (strict >)
    // would nag every current build.
    #expect(config.updateRequirement(runningVersion: "1.4.0") == .none)
    #expect(config.updateRequirement(runningVersion: "1.5.0") == .none)
    #expect(config.updateRequirement(runningVersion: "1.4.1") == .none)
}

@Test func runningBetweenThresholdsIsRecommended() throws {
    let config = try canonicalConfig()
    #expect(config.updateRequirement(runningVersion: "1.3.9") == .recommended)
    #expect(config.updateRequirement(runningVersion: "1.2.1") == .recommended)
}

@Test func runningAtMinSupportedIsRecommendedNotRequired() throws {
    let config = try canonicalConfig()
    // Equality with minSupportedVersion is .recommended, NOT .required - the
    // likeliest real off-by-one, and it withholds sync when wrong.
    #expect(config.updateRequirement(runningVersion: "1.2.0") == .recommended)
}

@Test func runningBelowMinSupportedIsRequired() throws {
    let config = try canonicalConfig()
    #expect(config.updateRequirement(runningVersion: "1.1.9") == .required)
    #expect(config.updateRequirement(runningVersion: "1.0.0") == .required)
    #expect(config.updateRequirement(runningVersion: "0.9.9") == .required)
}

// MARK: - 4. Unknown sibling key does not block appUpdate

@Test func unknownSiblingKeyStillAppliesAppUpdateAndTheRest() throws {
    let config = resolve(try updateDocument(
        appUpdate: validAppUpdateJSON(min: "1.2.0", latest: "1.4.0"),
        tier3: false,
        extraUnknown: "unknownFutureKey"))
    // The unknown key is ignored; appUpdate and the known keys still apply
    // (docs/CONFIG.md -> "One unknown key in an otherwise valid document").
    #expect(config.appUpdate != nil)
    #expect(config.updateRequirement(runningVersion: "1.1.0") == .required)
    #expect(config.tier3CloudFallback == false)
}

@Test func rawBytesAreRetainedVerbatimWithAppUpdate() throws {
    let document = try updateDocument(appUpdate: validAppUpdateJSON(min: "1.2.0", latest: "1.4.0"))
    #expect(document.rawBytes.range(of: Data("appUpdate".utf8)) != nil,
            "the key must survive verbatim in rawBytes")
}

// MARK: - Bundled default and sparse override

@Test func bundledDefaultCarriesNoAppUpdate() throws {
    let bundled = try ConfigDefaults.bundledAppConfig()
    #expect(bundled.appUpdate == nil, "Config.default.json must never carry an appUpdate")
    #expect(bundled.updateRequirement(runningVersion: "0.1.0") == .none)
}

@Test func sparseOverrideAppliesAppUpdateWhenPresentAndKeepsItWhenAbsent() throws {
    let noticeDoc = try updateDocument(appUpdate: validAppUpdateJSON(min: "1.2.0", latest: "1.4.0"))
    let bareDoc = try updateDocument()
    let withNotice = resolve(noticeDoc)
    let bare = resolve(bareDoc)

    // A remote document carrying the key overrides...
    #expect(bare.applying(remote: noticeDoc).appUpdate == withNotice.appUpdate)
    // ...and one omitting the key leaves the current value standing - an
    // update notice is not blanked by a document that says nothing about it.
    #expect(withNotice.applying(remote: bareDoc).appUpdate == withNotice.appUpdate)
}

// MARK: - AppVersion parsing (documented rejections)

@Test func parsesThreeDottedNumericsIntoComponents() {
    let version = AppVersion("1.10.3")!
    #expect(version.major == 1)
    #expect(version.minor == 10)
    #expect(version.patch == 3)
    #expect(AppVersion("0.0.1") != nil)
}

@Test func rejectsEverythingThatIsNotThreeDottedNumerics() {
    // The cases NOT allowed, pinned: two components (deliberate), four
    // components, pre-release suffixes, prefixes, signs, whitespace, empty.
    let rejected = [
        "1.2",           // two components - the deliberate choice
        "1",             // one component
        "1.2.0.4",       // four components
        "1.2.0-beta",    // pre-release suffix
        "v1.2.0",        // prefix
        "+1.2.0",        // sign
        "1.2.0 ",        // trailing whitespace
        " 1.2.0",        // leading whitespace
        "1..0",          // empty component
        "1.x.0",         // non-numeric component
        "",              // empty string
        "1.2.0\n"        // newline
    ]
    for string in rejected {
        #expect(AppVersion(string) == nil, "must not parse: \"\(string)\"")
    }
}
