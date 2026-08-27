import Foundation
import TankbookCore

// The import wizard's state (P5.5b) - docs/ERRORS.md -> Import wizard,
// docs/JOURNEYS.md F6. The model owns the three steps (source picker, preview
// gate, review list), the one `ImportClient`, and the ONE write the flow
// performs: `confirmImport` calls `repository.commitImportFills`. Building the
// preview, computing the figures, cancelling and reviewing all touch the
// repository NOT AT ALL - F6a: nothing is written until the user confirms.

@MainActor
@Observable
final class ImportFlowModel {

    enum Step: Equatable {
        case source
        case preview
        case review
    }

    /// The format list's state (docs/ERRORS.md -> Import wizard): offline is
    /// said plainly before the tap, never discovered as a failure after it.
    enum FormatsState: Equatable {
        case idle
        case loading
        case loaded
        case offline
        case failed
    }

    /// The parse's failure, each mapped to a specific message (F7) - never a
    /// generic "something went wrong".
    enum ParseFailure: Equatable {
        case doesNotMatchDeclared(displayName: String)
        case transportUnreachable
        case oversize
        case unrecognisedFormat
        case server(status: Int)
        case unknown
    }

    let client: ImportClient
    let repository: TankbookRepository

    private(set) var step: Step = .source
    private(set) var formats: [ImportFormat] = []
    private(set) var formatsState: FormatsState = .idle

    private(set) var pickedFormat: ImportFormat?
    private(set) var pickedFileName: String?
    private(set) var uploadedFileData: Data?
    private(set) var parse: ImportParseResponse?
    private(set) var isParsing = false
    private(set) var parseFailure: ParseFailure?

    private(set) var liveVehicles: [Vehicle] = []
    private(set) var targetCar: TargetCar?

    /// The unit every odometer in the review list renders in. Taken from the
    /// target car when there is one; a brand-new car has not chosen yet, so it
    /// falls back to the app default. Never a hardcoded "km" - hard rule 10, and
    /// the `Text(_: String)` blind spot that let one ship (see L10n.swift).
    var distanceUnit: DistanceUnit {
        if case .existing(let vehicle) = targetCar { return vehicle.units.distance }
        return liveVehicles.first?.units.distance ?? .km
    }

    private(set) var readyFills: [FillUp] = []
    private(set) var reviewRows: [ImportReviewRow] = []
    /// Review rows the user left out, keyed by `sourceRow` (stable across
    /// reclassification - the fills and row ids are minted fresh per rebuild).
    private(set) var skippedSourceRows: Set<Int> = []
    /// Odometer values the user typed in the review list, keyed by `sourceRow`.
    private(set) var odometerEdits: [Int: Int] = [:]

    private(set) var didConfirm = false
    private(set) var confirmFailed = false

    /// The parse's source id (`mfm`, ...) - the provenance every committed row
    /// carries (P5.4: `provenance = { tag: "import", source: <format> }`).
    private var source: String { pickedFormat?.id ?? parse?.format ?? "unknown" }

    init(client: ImportClient, repository: TankbookRepository) {
        self.client = client
        self.repository = repository
        self.liveVehicles = (try? repository.liveVehicles()) ?? []
    }

    /// Re-reads the garage (a test seed may have added a car after init).
    func reloadVehicles() {
        liveVehicles = (try? repository.liveVehicles()) ?? []
    }

    // MARK: - DEBUG/test seam

    /// Installs a stub parse response directly (no file picker) so the UI tests
    /// and screenshots drive the preview/review against a known fixture. The
    /// parse bytes come from the same bundle resources the stub transport
    /// serves; `rawFileResource` is the ORIGINAL file (the real CSV export) the
    /// parse claims to have read, so the review list's "Original row" renders a
    /// real source line instead of the wire envelope (P6.15c).
    func installSeededParse(resourceName: String, fileName: String,
                            rawFileResource: String? = nil) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(ImportParseResponse.self, from: data) else { return }
        pickedFileName = fileName
        if let rawFileResource,
           let rawURL = Bundle.main.url(forResource: rawFileResource, withExtension: "csv"),
           let rawData = try? Data(contentsOf: rawURL) {
            uploadedFileData = rawData
        } else {
            uploadedFileData = data
        }
        parse = result
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    // MARK: - Source step

    /// Loads `GET /import/formats` - the picker renders this response and
    /// nothing else. Offline is a distinct, named state.
    func loadFormats() async {
        guard formatsState == .idle || formatsState == .failed
            || formatsState == .offline else { return }
        formatsState = .loading
        do {
            formats = try await client.fetchFormats()
            formatsState = .loaded
        } catch ImportClientError.transportUnreachable {
            formatsState = .offline
        } catch {
            formatsState = .failed
        }
    }

    func selectFormat(_ format: ImportFormat) {
        pickedFormat = format
        parseFailure = nil
    }

    /// Uploads the picked file to `POST /import/parse` and classifies the
    /// response into ready fills and review rows. The server commits nothing;
    /// neither does this.
    func parse(fileURL: URL, preferredVehicleID: UUID? = nil) async {
        guard let format = pickedFormat else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            parseFailure = .unknown
            return
        }
        isParsing = true
        parseFailure = nil
        defer { isParsing = false }
        do {
            let result = try await client.parseFile(data: data,
                                                    fileName: fileURL.lastPathComponent,
                                                    format: format)
            pickedFileName = fileURL.lastPathComponent
            uploadedFileData = data
            parse = result
            ensureTargetCar(preferredVehicleID: preferredVehicleID)
            rebuildClassification()
            step = .preview
        } catch let error as ImportClientError {
            parseFailure = Self.failure(for: error, format: format)
            step = .source
        } catch {
            parseFailure = .unknown
            step = .source
        }
    }

    /// The import lands in the selected car when one exists (a merge, whose
    /// duplicates the preview surfaces), else in a new car.
    private func ensureTargetCar(preferredVehicleID: UUID?) {
        guard targetCar == nil else { return }
        if let preferred = liveVehicles.first(where: { $0.id == preferredVehicleID })
            ?? liveVehicles.first {
            targetCar = .existing(preferred)
        } else {
            targetCar = .newCar(named: newCarName)
        }
    }

    private static func failure(for error: ImportClientError, format: ImportFormat) -> ParseFailure {
        switch error {
        case .transportUnreachable: return .transportUnreachable
        case .oversize: return .oversize
        case .unrecognisedFormat: return .unrecognisedFormat
        case .doesNotMatchDeclared: return .doesNotMatchDeclared(displayName: format.displayName)
        case .server(let status): return .server(status: status)
        case .invalidResponse, .missingIdentity, .client: return .unknown
        }
    }

    // MARK: - Target car

    /// Re-derives the preview against the chosen target car. Choosing a
    /// different car changes home currency, tank capacity and the S2 duplicate
    /// count, so the conversion and every figure must be recomputed.
    func selectTarget(_ car: TargetCar) {
        targetCar = car
        rebuildClassification()
    }

    func selectExistingVehicle(_ vehicle: Vehicle) {
        selectTarget(.existing(vehicle))
    }

    func selectNewCar() {
        selectTarget(.newCar(named: newCarName))
    }

    var newCarName: String {
        parse?.candidates.first(where: { $0.vehicleName != nil })?.vehicleName
            ?? pickedFormat?.displayName
            ?? L10n.importedCarName
    }

    // MARK: - Review list

    /// "Leave out" / "Import" toggle for a review row. A row with no mapped
    /// fill (an unparsed row, a non-fill row) cannot be committed and is
    /// always left out.
    func toggleSkipped(sourceRow: Int) {
        if skippedSourceRows.contains(sourceRow) {
            skippedSourceRows.remove(sourceRow)
        } else {
            skippedSourceRows.insert(sourceRow)
        }
    }

    func isSkipped(sourceRow: Int) -> Bool {
        if let row = reviewRows.first(where: { $0.sourceRow == sourceRow }), row.fill == nil {
            return true
        }
        return skippedSourceRows.contains(sourceRow)
    }

    /// "Add odometer" - sets the review row's fill odometer from a typed value.
    /// A value that resolves the row promotes it to the ready set; clearing it
    /// keeps the gap a gap (never `0`).
    func setOdometer(_ value: Int?, for sourceRow: Int) {
        guard let index = reviewRows.firstIndex(where: { $0.sourceRow == sourceRow }) else { return }
        reviewRows[index].fill?.odometer = value
        if let value {
            odometerEdits[sourceRow] = value
            skippedSourceRows.remove(sourceRow)
            promoteIfResolved(sourceRow: sourceRow)
        } else {
            reviewRows[index].fill?.odometer = nil
            odometerEdits[sourceRow] = nil
        }
    }

    /// "Fix" - corrects the total on a cross-check-mismatch row. If the new
    /// total reconciles the arithmetic the row becomes ready.
    func setTotal(_ amount: Decimal, for sourceRow: Int) {
        guard let index = reviewRows.firstIndex(where: { $0.sourceRow == sourceRow }),
              var fill = reviewRows[index].fill,
              let money = fill.money else { return }
        fill.money = money.replacingAmount(amount)
        fill.crossCheck = TimelineValidator.crossCheck(volumeL: fill.volumeL,
                                                       unitPrice: fill.unitPrice,
                                                       amount: amount)
        reviewRows[index].fill = fill
        skippedSourceRows.remove(sourceRow)
        promoteIfResolved(sourceRow: sourceRow)
    }

    /// Moves a review row to the ready set once its issue is resolved (the same
    /// predicate the classifier used - the row stays honest, never silently
    /// dropped).
    private func promoteIfResolved(sourceRow: Int) {
        guard let index = reviewRows.firstIndex(where: { $0.sourceRow == sourceRow }),
              let fill = reviewRows[index].fill,
              ImportReviewClassifier.stillNeedsLook(fill) == nil else { return }
        readyFills.append(fill)
        reviewRows.remove(at: index)
    }

    // MARK: - Derived

    /// Every fill the commit will write: the ready rows plus the review rows the
    /// user kept. The preview's figures are computed over EXACTLY this set, so
    /// the number the user approves is the number that lands.
    var importFills: [FillUp] {
        let keptReview = reviewRows.filter { row in
            !isSkipped(sourceRow: row.sourceRow) && row.fill != nil
        }.compactMap(\.fill)
        return readyFills + keptReview
    }

    var commitCount: Int { importFills.count }

    /// The preview gate's figures, derived on demand over the target car and
    /// the fills that will actually be written.
    var summary: ImportSummary? {
        guard let parse, let targetCar else { return nil }
        let vehicle = targetCar.vehicleValue
        let existingFills: [FillUp]
        if case .existing(let existing) = targetCar {
            existingFills = (try? repository.liveFillUps(forVehicle: existing.id)) ?? []
        } else {
            existingFills = []
        }
        return ImportSummary.compute(
            importFills: importFills,
            existingFills: existingFills,
            tankCapacityL: vehicle.tankCapacityL,
            declaredCurrency: parse.declaredCurrency)
    }

    var duplicateCount: Int { summary?.duplicateCount ?? 0 }

    /// The S2 duplicate warning shows only when merging into a car that already
    /// has entries - a new car cannot collide with anything.
    var isMerging: Bool {
        if case .existing(let vehicle) = targetCar {
            return ((try? repository.liveFillUps(forVehicle: vehicle.id))?.isEmpty == false)
        }
        return false
    }

    // MARK: - Navigation

    func showReview() { step = .review }
    func showPreview() {
        rebuildClassification()
        step = .preview
    }
    func backToSource() { step = .source }

    // MARK: - Cancel (F6a: nothing is written, and the stored parse is deleted)

    /// Cancel deletes the stored parse (`DELETE /import/{id}`) and writes
    /// nothing. The garage is untouched.
    func cancelImport() async {
        if let importId = parse?.importId {
            try? await client.deleteParse(importId: importId)
        }
        resetFlow()
    }

    func resetFlow() {
        parse = nil
        pickedFileName = nil
        uploadedFileData = nil
        reviewRows = []
        readyFills = []
        skippedSourceRows = []
        odometerEdits = [:]
        step = .source
    }

    // MARK: - Confirm (the ONE write)

    /// Writes the kept fills and drops the stored parse. Returns whether the
    /// repository write succeeded. This is the only mutation the whole flow
    /// performs - hard rule 8 has nothing to lose because nothing was staged.
    @discardableResult
    func confirmImport() async -> Bool {
        guard let parse else { return false }
        let fills = importFills
        guard !fills.isEmpty else {
            try? await client.deleteParse(importId: parse.importId)
            didConfirm = true
            return true
        }
        do {
            if let targetCar {
                if case .new(let newCar) = targetCar {
                    try repository.upsertVehicle(newCar)
                }
            }
            try repository.commitImportFills(fills, source: source)
            try? await client.deleteParse(importId: parse.importId)
            didConfirm = true
            return true
        } catch {
            confirmFailed = true
            return false
        }
    }

    // MARK: - Classification

    /// Splits the parse into ready fills and review rows against the current
    /// target car, keeping the user's skip/odometer decisions by source row.
    private func rebuildClassification() {
        guard let parse, let targetCar else { return }
        let vehicle = targetCar.vehicleValue
        let lines = ImportRawLines.dataLines(from: uploadedFileData)
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: parse.candidates,
            unparsed: parse.unparsed,
            rawLinesByRow: lines,
            vehicle: vehicle,
            source: source)

        self.readyFills = ready
        self.reviewRows = review
        // The user's decisions survive a target-car change: they are keyed by
        // sourceRow, which is stable across rebuilds.
        var resolvedRows: [Int] = []
        for index in reviewRows.indices {
            let row = reviewRows[index]
            if !skippedSourceRows.contains(row.sourceRow), row.fill != nil {
                if let edited = odometerEdits[row.sourceRow] {
                    reviewRows[index].fill?.odometer = edited
                }
                if let fill = reviewRows[index].fill,
                   ImportReviewClassifier.stillNeedsLook(fill) == nil {
                    resolvedRows.append(row.sourceRow)
                }
            }
        }
        // Promote rows the user's edits resolved (an odometer typed earlier
        // must not come back as "missing" after a car change).
        for sourceRow in resolvedRows {
            promoteIfResolved(sourceRow: sourceRow)
        }
    }
}
