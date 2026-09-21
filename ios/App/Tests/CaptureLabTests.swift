import XCTest
@testable import Tankbook

/// PU.39 - the Capture Lab's value layer. The screen itself is a UI test; here
/// the run log's JSON round-trips whole, the preset list is well-formed and the
/// control applies nothing, and an unsupported capability is recorded rather
/// than thrown.
@MainActor
final class CaptureLabTests: XCTestCase {

    // MARK: - The run log's JSON shape

    /// One result with every field populated encodes and decodes back byte for
    /// byte in meaning: the round-trip is the shape pin, and the raw JSON is
    /// checked for each key name so a silently-dropped field cannot pass.
    func testRunLogJSONRoundTripsEveryField() throws {
        let applied = CaptureLabApplied(sessionPreset: "photo",
                                        qualityPrioritization: "quality",
                                        exposureBias: -0.5,
                                        focusMode: "continuousAutoFocus",
                                        exposureMode: "continuousAutoExposure",
                                        zoomFactor: 2.0,
                                        flashOff: true,
                                        locked: false,
                                        unsupported: ["flash"])
        let result = CaptureLabResult(
            preset: "quality",
            applied: applied,
            captureMs: 123,
            bytes: 456_789,
            width: 4032,
            height: 3024,
            exif: CaptureLabExif(exposureTime: 0.008, iso: 100, focalLength: 4.2),
            classifyPath: "fast",
            isDisplay: true,
            rows: 2,
            textLines: 5,
            committed: CaptureLabCommitted(liters: 60.25,
                                           unitPrice: Decimal(string: "76.24"),
                                           total: Decimal(string: "4593.46")),
            pipelineMs: 210,
            resolvedFields: 3,
            crossCheck: "lock")
        let log = CaptureLabRunLog(startedAt: "2026-09-21-101530",
                                   source: "pump",
                                   device: "iPhone14,5",
                                   results: [result])

        let data = try CaptureLabLogStore.encode(log)
        let decoded = try CaptureLabLogStore.decode(data)
        XCTAssertEqual(decoded, log, "the run log must survive its own round trip")

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["startedAt", "source", "device", "results"] {
            XCTAssertNotNil(object[key], "top-level key \(key) must be present")
        }
        let first = try XCTUnwrap((object["results"] as? [[String: Any]])?.first)
        for key in ["preset", "applied", "captureMs", "bytes", "width", "height", "exif",
                    "classifyPath", "isDisplay", "rows", "textLines", "committed",
                    "pipelineMs", "resolvedFields", "crossCheck"] {
            XCTAssertNotNil(first[key], "result key \(key) must be present")
        }
        let appliedJSON = try XCTUnwrap(first["applied"] as? [String: Any])
        for key in ["sessionPreset", "qualityPrioritization", "exposureBias", "focusMode",
                    "exposureMode", "zoomFactor", "flashOff", "locked", "unsupported"] {
            XCTAssertNotNil(appliedJSON[key], "applied key \(key) must be present")
        }
        let committedJSON = try XCTUnwrap(first["committed"] as? [String: Any])
        for key in ["liters", "unitPrice", "total"] {
            XCTAssertNotNil(committedJSON[key], "committed key \(key) must be present")
        }
        let exifJSON = try XCTUnwrap(first["exif"] as? [String: Any])
        for key in ["exposureTime", "iso", "focalLength"] {
            XCTAssertNotNil(exifJSON[key], "exif key \(key) must be present")
        }
    }

    /// The `applied` field carries what the preset actually did, not the
    /// control - the run log half of the mutation named by the brief.
    func testRunLogAppliedReflectsThePreset() throws {
        let plan = CaptureLabPreset.zoom2x.plan(capabilities: .all)
        XCTAssertEqual(plan.applied.zoomFactor, 2.0)
        XCTAssertEqual(plan.applied.sessionPreset, "photo")

        let result = CaptureLabResult(preset: CaptureLabPreset.zoom2x.id, applied: plan.applied,
                                      captureMs: 1, bytes: 1, width: 1, height: 1, exif: nil,
                                      classifyPath: nil, isDisplay: false, rows: 0, textLines: 0,
                                      committed: CaptureLabCommitted(), pipelineMs: 0,
                                      resolvedFields: nil, crossCheck: nil)
        let data = try CaptureLabLogStore.encode(
            CaptureLabRunLog(startedAt: "x", source: "pump", device: "d", results: [result]))
        let decoded = try CaptureLabLogStore.decode(data)
        XCTAssertEqual(decoded.results.first?.applied.zoomFactor, 2.0,
                       "the log's applied field must carry the preset's zoom, not the control's")
    }

    // MARK: - Presets

    func testPresetIDsAreUniqueAndTheControlAppliesNothing() {
        let ids = CaptureLabPreset.allCases.map(\.id)
        XCTAssertEqual(ids.count, 7, "the lab shoots seven presets")
        XCTAssertEqual(Set(ids).count, ids.count, "preset ids must be unique")

        let plan = CaptureLabPreset.default.plan(capabilities: .all)
        XCTAssertNil(plan.qualityPrioritization, "the control must not prioritise quality")
        XCTAssertNil(plan.exposureBias)
        XCTAssertNil(plan.focusPoint)
        XCTAssertNil(plan.exposurePoint)
        XCTAssertNil(plan.focusMode)
        XCTAssertNil(plan.exposureMode)
        XCTAssertNil(plan.zoomFactor)
        XCTAssertFalse(plan.sessionPresetHigh)
        XCTAssertFalse(plan.flashOff)
        XCTAssertFalse(plan.waitForConvergence)
        XCTAssertTrue(plan.unsupported.isEmpty, "the control needs no capability")
        XCTAssertEqual(plan.applied.sessionPreset, "photo")
        XCTAssertFalse(plan.applied.locked)
    }

    /// A device that cannot do a thing records it in `unsupported` and omits
    /// the setting - never a crash and never a silent no-op.
    func testUnsupportedCapabilityIsRecordedNotThrown() {
        var capabilities = CaptureLabCapabilities.all
        capabilities.focusPointOfInterest = false
        capabilities.zoom = false
        capabilities.lockedFocus = false
        capabilities.flash = false

        let metered = CaptureLabPreset.metered.plan(capabilities: capabilities)
        XCTAssertTrue(metered.unsupported.contains("focusPointOfInterest"))
        XCTAssertNil(metered.focusPoint, "an unsupported point must not be applied")
        XCTAssertNotNil(metered.focusMode, "the rest of the metered core still applies")

        let zoom = CaptureLabPreset.zoom2x.plan(capabilities: capabilities)
        XCTAssertTrue(zoom.unsupported.contains("zoom"))
        XCTAssertNil(zoom.zoomFactor)

        let locked = CaptureLabPreset.locked.plan(capabilities: capabilities)
        XCTAssertTrue(locked.unsupported.contains("focusLock"))
        XCTAssertTrue(locked.unsupported.contains("flash"))
        XCTAssertEqual(locked.exposureMode, .locked, "exposure lock is still supported")

        // The same preset against a fully capable device records nothing.
        let full = CaptureLabPreset.locked.plan(capabilities: .all)
        XCTAssertTrue(full.unsupported.isEmpty, "a capable device records no gap")
        XCTAssertEqual(full.focusMode, .locked)
        XCTAssertEqual(full.exposureMode, .locked)
        XCTAssertTrue(full.flashOff)
        XCTAssertTrue(full.waitForConvergence)
    }

    func testHigh1080UsesTheHighPresetAtSpeed() {
        let plan = CaptureLabPreset.high1080.plan(capabilities: .all)
        XCTAssertTrue(plan.sessionPresetHigh)
        XCTAssertEqual(plan.qualityPrioritization, .speed)
        XCTAssertEqual(plan.applied.sessionPreset, "high")

        var noHigh = CaptureLabCapabilities.all
        noHigh.highSessionPreset = false
        let unsupported = CaptureLabPreset.high1080.plan(capabilities: noHigh)
        XCTAssertTrue(unsupported.unsupported.contains("sessionPreset.high"))
        XCTAssertFalse(unsupported.sessionPresetHigh)
    }

    /// The pump source classifies (nil), the receipt source forces the receipt
    /// path - the scoring contract `CapturePipeline.process` reads.
    func testSourceMapsToExtractionSource() {
        XCTAssertNil(CaptureLabSource.pump.extractionSource)
        XCTAssertEqual(CaptureLabSource.receipt.extractionSource, .receipt)
    }
}
