import Foundation
import Testing
@testable import TankbookCore

// PR.8: AppVersion reads Info.plist. The bundle's marketing version in this
// product is `1.0.0` (project.yml MARKETING_VERSION), which is why a test can
// assert the exact three-component parse against a crafted plist.

@Suite("AppVersion from Info.plist (PR.8)")
struct AppVersionBundleTests {

    private static func makeBundle(shortVersion: String?, build: String) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppVersionBundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": "test.bundle",
            "CFBundleVersion": build
        ]
        if let shortVersion {
            plist["CFBundleShortVersionString"] = shortVersion
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Info.plist"))
        let bundle = Bundle(path: directory.path)
        #expect(bundle != nil)
        return try #require(bundle)
    }

    @Test func parsesTheMarketingVersionFromAnInfoPlist() async throws {
        let bundle = try Self.makeBundle(shortVersion: "1.0.0", build: "1")
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }

        #expect(AppVersion(bundle: bundle) == AppVersion("1.0.0"))
        #expect(AppVersion(bundle: bundle)?.description == "1.0.0")
    }

    @Test func anAbsentOrUnparseablePlistValueIsNilNeverAGuess() async throws {
        let missing = try Self.makeBundle(shortVersion: nil, build: "1")
        defer { try? FileManager.default.removeItem(at: missing.bundleURL) }
        #expect(AppVersion(bundle: missing) == nil, "no plist value must be nil, never a guessed version")

        let unparseable = try Self.makeBundle(shortVersion: "beta", build: "1")
        defer { try? FileManager.default.removeItem(at: unparseable.bundleURL) }
        #expect(AppVersion(bundle: unparseable) == nil, "a non dotted-numeric value must fail to parse")
    }

    @Test func currentBuildsTheWireHeadersFromTheBundle() async throws {
        let bundle = try Self.makeBundle(shortVersion: "1.0.0", build: "1")
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }

        let info = TankbookAppInfo.current(bundle: bundle)
        #expect(info?.appHeader == "1.0.0+1", "X-Tankbook-App is <version>+<build>")
        #expect(info?.platform == "ios")
        #expect(info?.schemaVersion == PayloadCodec.currentSchemaVersion)
    }
}
