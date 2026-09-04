import Foundation
import Testing
@testable import TankbookCore

// RV.48 the stored assignment: the Attachment persists what the parse CONCLUDED
// (per-field value + confidence), so the recognised page shows meaning instead
// of raw OCR line soup. These tests pin the two invariants from the RV.48 row:
//   - a field the parse did not assign is ABSENT, never an empty string/zero;
//   - a parse that assigned nothing stores no container at all.
// The L1 values come from a real corpus fixture's OCR lines, never a hand-typed
// string (Spike/ReceiptSpike/fixtures is the point of having them).

@Suite("RV.48 the stored assignment (Attachment.extractionMeta)")
struct AttachmentExtractionTests {

    // MARK: - The real corpus fixture

    /// receipt-001's committed OCR lines (Circle K Järvevana, Tallinn - the same
    /// merchant the RV.48 report shows, Reg.kood/KMKR noise included). Decoded
    /// from the vision-ab artefact so the test never hand-types the values.
    private static func receipt001Lines() -> [String] {
        let url = PaddleOCRCorpus.abRoot.appendingPathComponent("paddleocr-a-lines-receipt-001.json")
        let data = try! Data(contentsOf: url)
        let fixture = try! JSONDecoder().decode(PaddleOCRCalibrationFixture.self, from: data)
        return fixture.lines.map(\.text)
    }

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    private func extraction(from lines: [String]) -> FuelExtraction {
        FuelExtractor().extract(textLines: lines)
    }

    // MARK: - The assigned fields carry the extractor's values

    @Test("a real receipt's assigned fields carry exactly the values the extractor produced")
    func assignedFieldsCarryTheExtractorsValues() {
        let result = extraction(from: Self.receipt001Lines())
        // The fixture's own evidence: the Circle K receipt resolves a total
        // (125.22), a unit price (1.869) and a currency (EUR). Its volume is NOT
        // read (the OCR merges the value with its /L label), which makes it the
        // "unassigned field is absent" half of the invariant on the same fixture.
        #expect(result.total != nil)
        #expect(result.unitPrice != nil)
        #expect(result.currency != nil)

        let assignment = ScannedSavePlanner.assignment(from: result)
        guard let assignment else {
            Issue.record("a parse that resolved fields must produce an assignment")
            return
        }

        // Every field the parse assigned carries the value it assigned - the
        // whole point of RV.48. The comparison is against the extractor's own
        // typed value, so a wrong copy cannot pass.
        #expect(assignment.fields[.total]?.value == .money(result.total!))
        #expect(assignment.fields[.unitPrice]?.value == .money(result.unitPrice!))
        #expect(assignment.fields[.currency]?.value == .currency(result.currency!))

        // An unassigned field is ABSENT, never an empty string or a zero: the
        // volume and fuel kind were not read, so they carry no entry at all.
        #expect(result.liters == nil)
        #expect(assignment.fields[.volume] == nil, "an unread volume is ABSENT, never a zero")
        #expect(assignment.fields[.fuelKind] == nil)

        // A specific, known value pins the fixture - not vacuous.
        #expect(result.total == decimal("125.22"), "receipt-001 total is the Circle K receipt's 125.22 EUR")
        #expect(result.unitPrice == decimal("1.869"))
        #expect(result.currency == .eur)

        // The save path carries the same values (plus userCorrected), and its
        // attachment shape is the value-bearing subset only.
        let saved = ScannedSaveValues(total: result.total, volumeL: result.liters,
                                      unitPrice: result.unitPrice, currency: result.currency,
                                      fuelKind: result.fuelKind,
                                      date: result.date.flatMap { ConfirmDate.parse($0) })
        let plan = ScannedSavePlanner.plan(extraction: result, hasPhoto: true, saved: saved)
        let meta = plan.extraction
        #expect(meta != nil)
        #expect(meta?.fields[.total]?.value == .money(result.total!))
        #expect(meta?.fields[.unitPrice]?.value == .money(result.unitPrice!))
        #expect(meta?.fields[.currency]?.value == .currency(result.currency!))
        #expect(meta?.assignmentOnly?.fields.values.allSatisfy { $0.value != nil } == true)
    }

    // MARK: - An unassigned field is ABSENT, never blank

    @Test("a field the parse did not assign is absent, never an empty string or zero")
    func unassignedFieldIsAbsent() {
        // A parse that read only a volume - no total, no price, no date, no
        // currency, no fuel kind. The fields map must carry ONLY `.volume`.
        let result = FuelExtraction(liters: 26.94)
        let assignment = ScannedSavePlanner.assignment(from: result)
        guard let assignment else {
            Issue.record("a parse that resolved a volume must produce an assignment")
            return
        }
        #expect(Array(assignment.fields.keys) == [.volume], "only the assigned field may be present")
        #expect(assignment.fields[.total] == nil, "an unassigned total is ABSENT, not a blank entry")
        #expect(assignment.fields[.unitPrice] == nil)
        #expect(assignment.fields[.date] == nil)
        #expect(assignment.fields[.currency] == nil)
        #expect(assignment.fields[.fuelKind] == nil)
        #expect(assignment.fields[.volume]?.value == .number(26.94))
    }

    // MARK: - A nothing-assigned parse stores no container

    @Test("a parse that assigned nothing stores no assignment at all")
    func nothingAssignedStoresNoContainer() {
        let empty = FuelExtraction()
        #expect(empty.resolvedAnyField == false)
        #expect(ScannedSavePlanner.assignment(from: empty) == nil,
                "a nothing-assigned parse must store nil, never an empty container")
        // The save path still records provenance for the entry, but the
        // ATTACHMENT's assignment is nil.
        let plan = ScannedSavePlanner.plan(extraction: empty, hasPhoto: true,
                                           saved: ScannedSaveValues())
        #expect(plan.extraction?.assignmentOnly == nil)
    }

    // MARK: - Round-trip through the payload codec

    @Test("an attachment with an assignment round-trips through the payload codec exactly")
    func roundTripsThroughPayloadCodec() throws {
        let meta = ExtractionMeta(fields: [
            .total: FieldExtraction(cropRect: nil, confidence: 0.98, userCorrected: false,
                                    value: .money(decimal("125.22"))),
            .volume: FieldExtraction(cropRect: nil, confidence: 0.97, userCorrected: false,
                                     value: .number(67.0)),
            .currency: FieldExtraction(cropRect: nil, confidence: 0.99, userCorrected: false,
                                       value: .currency(.eur)),
        ], pipeline: "vision+rules v3")
        let attachment = Attachment(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            kind: .photo,
            file: LocalFileRef(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                               relativePath: "photos/2026/08/9f86d081.jpg"),
            extractedTimestamp: Date(), ocrText: "125,22 EUR\n67,00", thumbnailBase64: nil,
            extractionMeta: meta)

        let envelope = try PayloadCodec.encode(attachment)
        let decoded = try PayloadCodec.decode(envelope, as: type(of: attachment))
        #expect(decoded.entity.extractionMeta == meta)
        // The value is a Decimal, serialized as a string - never a JSON number.
        let totalNode = envelope.payload.objectValue?["extractionMeta"]?
            .objectValue?["fields"]?.objectValue?["total"]?
            .objectValue?["value"]
        #expect(totalNode?.objectValue?["tag"] == .string("money"))
        #expect(totalNode?.objectValue?["value"]?.numericValue == nil,
                "money values must serialize as strings, never JSON numbers")
    }

    @Test("an older attachment payload without extractionMeta still decodes")
    func olderPayloadWithoutExtractionMetaStillDecodes() throws {
        let url = PaddleOCRCorpus.repoRoot()
            .appendingPathComponent("docs/fixtures/payloads/v1/attachment.json")
        let data = try Data(contentsOf: url)
        let tree = try JSONValue.parse(data)
        let envelope = PayloadEnvelope(entityType: "attachment",
                                       schemaVersion: PayloadCodec.currentSchemaVersion,
                                       payload: tree)
        let sample = Attachment(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            kind: .photo,
            file: LocalFileRef(sha256: "abc", relativePath: "p.jpg"))
        let decoded = try PayloadCodec.decode(envelope, as: type(of: sample))
        #expect(decoded.entity.extractionMeta == nil,
                "a pre-RV.48 payload has no extractionMeta and must decode to nil")
    }

    // MARK: - Persistence

    @Test("an attachment's assignment survives the persistence layer")
    func assignmentSurvivesPersistence() throws {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let meta = ExtractionMeta(fields: [
            .total: FieldExtraction(cropRect: nil, confidence: 0.98, userCorrected: false,
                                    value: .money(decimal("125.22"))),
            .fuelKind: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false,
                                       value: .fuelKind(.diesel)),
        ], pipeline: "vision+rules v3")
        let attachment = Attachment(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            kind: .photo,
            file: LocalFileRef(sha256: "abc", relativePath: "p.jpg"),
            extractedTimestamp: nil, ocrText: nil, thumbnailBase64: nil,
            extractionMeta: meta)
        try repository.upsertAttachment(attachment)

        let live = try #require(try repository.liveAttachments().first)
        #expect(live.extractionMeta == meta)
        #expect(live.extractionMeta?.fields[.total]?.value == .money(decimal("125.22")))
        #expect(live.extractionMeta?.fields[.fuelKind]?.value == .fuelKind(.diesel))
    }
}
