import CoreGraphics
import Foundation

/// The trace of one `PumpDisplayCapture.classify` run as JSON - the shape the
/// annotator's pipeline view (tools/pump-annotate, `pipeline.js`) renders, so a
/// run traced on a phone opens there exactly like one traced by
/// `pump-read --trace-serve`. Every quad is normalised over the photo as it was
/// taken. Strips are written only when a `stripWriter` is given (the tool
/// writes PNGs); without one the reply names none, and the photo re-derives
/// them.
enum PumpTraceJSON {
    typealias StripWriter = (PumpRGBImage?, String) -> Any

    static func reply(trace: PumpTrace, result: (detection: PumpDisplayCapture.Detection,
                                                 reading: PumpDisplayCapture.Reading?),
                      photoWidth: Int, photoHeight: Int, budget: TimeInterval, currency: CurrencyCode?,
                      extra: [String: Any] = [:], stripWriter: StripWriter? = nil) -> [String: Any] {
        var reply: [String: Any] = ["photo": ["w": photoWidth, "h": photoHeight], "budget": budget,
                                    "currency": currency?.rawValue ?? NSNull(),
                                    "chosen": trace.chosen ?? NSNull()]
        reply.merge(extra) { _, new in new }
        reply["orientationScores"] = trace.orientationScores.map {
            ["rotationCW": $0.rotationCW, "keptRows": $0.keptRows, "inkBandArea": $0.inkBandArea]
        }
        reply["attempts"] = trace.attempts.enumerated().map { index, attempt in
            attemptJSON(attempt, index: index, stripWriter: stripWriter)
        }
        reply["final"] = ["detection": detectionJSON(result.detection), "routedAsPump": result.reading != nil,
                          "law": result.reading.map { lawJSON($0.law) } ?? NSNull()]
        return reply
    }

    private static func attemptJSON(_ attempt: PumpTrace.Attempt, index: Int,
                                    stripWriter: StripWriter?) -> [String: Any] {
        func quad(_ points: [CGPoint], normalised: Bool) -> [[Double]] {
            quadJSON(points, normalised: normalised, attempt)
        }
        var out: [String: Any] = ["kind": attempt.kind, "rotationCW": attempt.rotationCW,
                                  "w": attempt.width, "h": attempt.height,
                                  "textLines": attempt.textLines ?? NSNull(),
                                  "fastVerdict": attempt.fastVerdict ?? NSNull(), "budgetHit": attempt.budgetHit,
                                  "detection": attempt.detection.map(detectionJSON) ?? NSNull(),
                                  "law": attempt.law.map(lawJSON) ?? NSNull()]
        out["detectedRows"] = attempt.detectedRows.map { row -> [String: Any] in
            ["quad": quad(row.quad, normalised: true), "confidence": row.confidence,
             "passesSize": PumpDisplayCapture.passesSize(row)]
        }
        out["candidates"] = attempt.candidates.map { ["quad": quad($0.quad, normalised: true), "detected": $0.detected] }
        out["verdicts"] = attempt.verdicts.enumerated().map { number, record -> [String: Any] in
            let verdict = record.verdict
            return ["quad": quad(verdict.quad, normalised: false), "kept": verdict.kept, "detected": verdict.detected,
                    "reasons": verdict.dropReasons, "cells": verdict.cells, "heightFraction": verdict.heightFraction,
                    "meanMargin": verdict.meanMargin, "cellRects": cellsJSON(record.cells),
                    "strip": stripWriter?(record.strip, "a\(index)-v\(number).png") ?? NSNull()]
        }
        out["verified"] = attempt.verified.enumerated().map { number, window -> [String: Any] in
            let role = number < attempt.roles.count ? attempt.roles[number]?.rawValue : nil
            return ["quad": quad(window.quad, normalised: false), "cells": window.glyphCount, "detected": window.detected,
                    "meanMargin": window.meanMargin, "role": role ?? NSNull()]
        }
        out["reads"] = attempt.reads.enumerated().map { number, record -> [String: Any] in
            ["field": record.field.rawValue, "quad": quad(record.quad, normalised: false),
             "skipped": record.skipped ?? NSNull(), "cellRects": cellsJSON(record.cells),
             // A row read has digits and no slicer cells: the strip was read whole.
             "reader": record.cells.isEmpty && !record.readings.isEmpty ? "row" : "cells",
             "readings": record.readings.map(readingJSON),
             "strip": stripWriter?(record.strip, "a\(index)-r\(number).png") ?? NSNull()]
        }
        return out
    }

    /// A point of the attempt's upright image, normalised over the photo as taken.
    private static func unturned(_ point: CGPoint, rotationCW: Int) -> [Double] {
        var turned = point
        for _ in 0..<((4 - ((rotationCW % 360) + 360) % 360 / 90) % 4) {
            turned = CGPoint(x: 1 - turned.y, y: turned.x)
        }
        return [turned.x, turned.y]
    }

    private static func quadJSON(_ quad: [CGPoint], normalised: Bool, _ attempt: PumpTrace.Attempt) -> [[Double]] {
        quad.map { point in
            let unit = normalised ? point
                : CGPoint(x: point.x / Double(attempt.width), y: point.y / Double(attempt.height))
            return unturned(unit, rotationCW: attempt.rotationCW)
        }
    }

    private static func cellsJSON(_ cells: [GlyphCell]) -> [[String: Any]] {
        cells.map { ["x": $0.rect.minX, "y": $0.rect.minY, "w": $0.rect.width, "h": $0.rect.height,
                     "blank": $0.isBlank, "dp": $0.hasDecimalPoint] }
    }

    private static func readingJSON(_ reading: PumpCellReading) -> [String: Any] {
        ["top": reading.ranked.prefix(3).map { ["d": $0.digit, "lp": $0.logPosterior] },
         "margin": reading.margin, "dp": reading.decimalPoint,
         "dpProb": reading.probabilities.count > 7 ? reading.probabilities[7] : 0]
    }

    private static func fieldJSON(_ field: PumpFieldReading) -> [String: Any] {
        var provenance: Any = NSNull()
        switch field.provenance {
        case .read: provenance = "read"
        case .derived: provenance = "derived"
        case let .repaired(cellIndex, fromDigit, toDigit):
            provenance = ["repaired": ["cell": cellIndex, "from": fromDigit, "to": toDigit]]
        case nil: break
        }
        return ["value": field.value.map { "\($0)" } ?? NSNull(), "reason": field.reason?.rawValue ?? NSNull(),
                "provenance": provenance, "logPosterior": field.logPosterior]
    }

    private static func lawJSON(_ law: PumpDisplayReading) -> [String: Any] {
        ["total": fieldJSON(law.total), "liters": fieldJSON(law.liters), "unitPrice": fieldJSON(law.unitPrice),
         "reason": law.reason?.rawValue ?? NSNull(), "caution": law.caution.map { "\($0)" } ?? NSNull(),
         "committed": law.committedCount]
    }

    private static func detectionJSON(_ detection: PumpDisplayCapture.Detection) -> [String: Any] {
        ["display": detection.isPumpDisplay, "rows": detection.displayRows, "textLines": detection.textLines,
         "widestRow": detection.widestRow, "tallestRow": detection.tallestRow, "path": detection.path.rawValue]
    }
}

/// One pump read's stages as counts and codes (the `capture.pumpRead` line):
/// how far the read got and where it stopped, never a digit or a pixel (hard
/// rule 12). Taken from the attempt `classify` chose, else its last attempt.
public struct PumpReadSummary: Sendable, Equatable {
    public var attempts = 0
    public var chosen: Int?
    public var rotationCW: Int?
    public var detectedRows = 0
    public var candidates = 0
    public var kept = 0
    public var dropReasons: [String] = []
    public var verified = 0
    public var roles: [String] = []
    public var skippedReads: [String] = []
    public var lawReason: String?
    public var committed = 0
    public var budgetHit = false

    public init() {}

    init(trace: PumpTrace) {
        attempts = trace.attempts.count
        chosen = trace.chosen
        guard let attempt = trace.chosen.map({ trace.attempts[$0] }) ?? trace.attempts.last else { return }
        rotationCW = attempt.rotationCW
        detectedRows = attempt.detectedRows.count
        candidates = attempt.candidates.count
        kept = attempt.verdicts.filter(\.verdict.kept).count
        var reasons: [String] = []
        for record in attempt.verdicts where !record.verdict.kept {
            for reason in record.verdict.dropReasons where !reasons.contains(reason) { reasons.append(reason) }
        }
        dropReasons = reasons
        verified = attempt.verified.count
        roles = attempt.roles.compactMap { $0?.rawValue }
        skippedReads = attempt.reads.compactMap(\.skipped)
        lawReason = attempt.law?.reason?.rawValue
        committed = attempt.law?.committedCount ?? 0
        budgetHit = attempt.budgetHit
    }
}

extension PumpDisplayCapture {
    /// A classify run observed by a trace: the result, its stage summary, and
    /// - when asked for - the run's pipeline JSON (`PumpTraceJSON`).
    public struct TracedRun: Sendable {
        public let detection: Detection
        public let reading: Reading?
        public let summary: PumpReadSummary
        public let traceJSON: Data?
    }

    /// `classify` as the app runs it, observed by a trace. The trace only
    /// records: the result equals the untraced run's (`PumpTraceParityTests`).
    /// `includeJSON` serialises the whole trace for a debug case; the summary
    /// is always there.
    public static func classifyTraced(image: CGImage, reader: PumpReaderHandle, currency: CurrencyCode?,
                                      priceBand: FuelPriceBand?, rotationCW: Int? = nil,
                                      includeJSON: Bool) -> TracedRun {
        let trace = PumpTrace()
        let result = classify(image: image, reader: reader, currency: currency, priceBand: priceBand,
                              budget: slowPathBudget, rotationCW: rotationCW, trace: trace)
        let summary = PumpReadSummary(trace: trace)
        guard includeJSON else { return TracedRun(detection: result.detection, reading: result.reading,
                                                  summary: summary, traceJSON: nil) }
        let reply = PumpTraceJSON.reply(trace: trace, result: result, photoWidth: image.width,
                                        photoHeight: image.height, budget: slowPathBudget, currency: currency)
        // A non-finite number (a log posterior can be -inf) makes
        // `JSONSerialization` raise rather than throw, so validity is checked
        // first and an unserialisable trace is dropped, never the capture.
        let data = JSONSerialization.isValidJSONObject(reply)
            ? try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) : nil
        return TracedRun(detection: result.detection, reading: result.reading, summary: summary, traceJSON: data)
    }
}
