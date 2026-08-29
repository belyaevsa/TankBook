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
    /// P6.18b: the config service behind the import gate. Import's server read
    /// (parse) is the one named exception to local-first (hard rule 9), and it
    /// is the one part withheld under `.required` - the review list, the edits
    /// and the commit stay fully local (docs/CONFIG.md -> "The exception").
    let configService: AppConfigService

    private(set) var step: Step = .source
    private(set) var formats: [ImportFormat] = []
    private(set) var formatsState: FormatsState = .idle

    private(set) var pickedFormat: ImportFormat?
    private(set) var pickedFileName: String?
    private(set) var uploadedFileData: Data?
    private(set) var parse: ImportParseResponse?
    private(set) var isParsing = false
    private(set) var parseFailure: ParseFailure?
    /// The in-flight parse, so the user's Cancel can stop the upload (a wait the
    /// user cannot escape is the bug hard rule 7 exists to remove - PR.6).
    private var parseTask: Task<Void, Never>?

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
    /// Totals the user fixed in the review list, keyed by `sourceRow` (PJ.11).
    /// Applied to the candidates before the partition, so a corrected total
    /// re-derives exactly like an untouched row (F6a: the number approved lands).
    private(set) var totalEdits: [Int: Decimal] = [:]

    /// The `dateFormat` question's answer - the chosen option ("M/D/YYYY" or
    /// "D/M/YYYY"), nil until the user answers. Asked ONCE per file, at the
    /// preview gate (docs/JOURNEYS.md F6, docs/API.md): the wire carries the
    /// M/D reading, so choosing D/M re-dates the ambiguous candidates before
    /// anything is committed. nil when the parse reported no ambiguity.
    private(set) var dateFormatAnswer: String?

    private(set) var didConfirm = false
    private(set) var confirmFailed = false

    /// The parse's source id (`mfm`, ...) - the provenance every committed row
    /// carries (P5.4: `provenance = { tag: "import", source: <format> }`).
    private var source: String { pickedFormat?.id ?? parse?.format ?? "unknown" }

    init(client: ImportClient, repository: TankbookRepository, configService: AppConfigService) {
        self.client = client
        self.repository = repository
        self.configService = configService
        self.liveVehicles = (try? repository.liveVehicles()) ?? []
    }

    /// True when the update requirement is `.required` (P6.18b): the server
    /// has stopped supporting this build, so the parse is withheld client-side
    /// and the source screen renders the non-dismissible update notice in place
    /// of the picker. Everything else about import - the review list, the
    /// edits, the commit - stays local and reachable.
    var serverBackedPaused: Bool { !configService.allowsServerBacked }

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
        dateFormatAnswer = nil
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// Installs a stub parse whose candidates mix fill-ups and a `serviceRecord`
    /// row (PJ.9), so the UI tests and screenshots drive the non-fuel action and
    /// the mixed commit against a known fixture without a server. The uploaded
    /// file data is a real-looking MFM costs fragment so "Original row" renders
    /// a source line.
    func installSeededServiceParse() {
        let money = ImportMoney(amount: "125.50", currency: "USD")
        let item = ImportServiceItem(title: "Oil change", category: ImportCategoryTag(tag: "oil"),
                                     cost: money)
        let serviceCandidate = ImportCandidate(
            entityType: "serviceRecord",
            date: Date(timeIntervalSince1970: 1_752_307_200),  // 2026-07-20
            odometer: 119_486, volumeL: nil, unitPrice: nil, money: money,
            fuelKind: nil, isFull: nil, tankLevelAfterPct: nil, note: "Oil change",
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 1, items: [item])
        let fillCandidate = ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_752_393_600),  // 2026-07-21
            odometer: 119_486, volumeL: 55, unitPrice: "1.85", money: ImportMoney(amount: "101.75", currency: "USD"),
            fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: "Neste",
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 2)
        parse = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000303", format: "mfm",
            scope: "vehicle", candidates: [serviceCandidate, fillCandidate],
            unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        pickedFileName = "MyFuelManager_costs_2026.csv"
        uploadedFileData = Data("""
        My Fuel Manager - Costs
        Date;Category;Odometer;Total price;Currency;Note;Vehicle name
        7/20/2026;Oil;119486;125.50;USD;Oil change;"Volvo"
        """.utf8)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// Installs a stub parse whose fills break the odometer order (PJ.11): row
    /// 2's `9` mirrors the real MFM defect (`Spike/ImportFixtures/mfm/README.md`)
    /// and must appear in the review list badged "Breaks the timeline".
    func installSeededTimelineParse() {
        func fill(_ row: Int, _ date: Date, _ odo: Int, _ note: String) -> ImportCandidate {
            ImportCandidate(
                entityType: "fillUp", date: date, odometer: odo, volumeL: 55,
                unitPrice: "1.85", money: ImportMoney(amount: "101.75", currency: "USD"),
                fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: note,
                vehicleName: "Volvo",
                provenance: ImportProvenance(tag: "import", source: "mfm"),
                sourceRow: row)
        }
        let fillCandidates = [
            fill(1, Date(timeIntervalSince1970: 1_787_529_600), 121_727, "Neste"),
            fill(2, Date(timeIntervalSince1970: 1_786_320_000), 9, "Shell"),
            fill(3, Date(timeIntervalSince1970: 1_784_332_800), 120_559, "Circle K")
        ]
        parse = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000304", format: "mfm",
            scope: "vehicle", candidates: fillCandidates,
            unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        pickedFileName = "MyFuelManager_2026-08.csv"
        uploadedFileData = Data("""
        My Fuel Manager - Fuel
        Date;Odometer;Fillup volume;Total price;Currency;Note;Vehicle name
        8/24/2026;121727;55;101.75;USD;Neste;"Volvo"
        8/10/2026;9;55;101.75;USD;Shell;"Volvo"
        7/18/2026;120559;55;101.75;USD;Circle K;"Volvo"
        """.utf8)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    // MARK: - Source step

    /// Loads `GET /import/formats` - the picker renders this response and
    /// nothing else. Offline is a distinct, named state. Withheld under
    /// `.required` (P6.18b) - the source screen shows the update notice instead.
    func loadFormats() async {
        guard !serverBackedPaused else { return }
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
    /// neither does this. The parse runs in a tracked task so `cancelParse`
    /// can stop it (PR.6 - a half-connected radio must not freeze the wizard
    /// for the full upload budget with no escape).
    func parse(fileURL: URL, preferredVehicleID: UUID? = nil) {
        guard let format = pickedFormat else { return }
        // P6.18b: withheld under `.required` - the server has stopped
        // supporting this build.
        guard !serverBackedPaused else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            parseFailure = .unknown
            return
        }
        isParsing = true
        parseFailure = nil
        parseTask?.cancel()
        parseTask = Task { [weak self] in
            await self?.performParse(data: data,
                                     fileName: fileURL.lastPathComponent,
                                     format: format,
                                     preferredVehicleID: preferredVehicleID)
        }
    }

    /// Stops the in-flight parse and returns the wizard to the source step. The
    /// garage is untouched: nothing is written until `confirmImport`, so cancel
    /// has nothing to unwind.
    func cancelParse() {
        parseTask?.cancel()
        parseTask = nil
        isParsing = false
        parseFailure = nil
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

    // MARK: - The date-format question (PJ.10)

    /// The `dateFormat` ambiguity the server reported, if any (F6: ambiguity is
    /// returned, never guessed - the parser's M/D reading must not stand silent).
    private var dateFormatAmbiguity: ImportAmbiguity? {
        parse?.ambiguities.first(where: { $0.kind == "dateFormat" })
    }

    /// The two readings the server named ("M/D/YYYY" and "D/M/YYYY").
    var dateFormatOptions: [String]? { dateFormatAmbiguity?.options }

    /// How many rows genuinely read either way (their day is also ≤ 12).
    var dateFormatRowCount: Int { dateFormatAmbiguity?.rowCount ?? 0 }

    var hasDateFormatQuestion: Bool { dateFormatAmbiguity != nil }

    var dateFormatAnswered: Bool { dateFormatAnswer != nil }

    /// Whether the commit may proceed: every F6 question is answered. A
    /// `dateFormat` question unanswered would commit the file under the
    /// parser's guess (docs/JOURNEYS.md J2's stats-poisoning misread), so the
    /// preview disables confirm and the model refuses the write until it is
    /// answered (PJ.10).
    var canConfirm: Bool { parse?.canCommit(dateFormatAnswer: dateFormatAnswer) ?? false }

    /// Answers the `dateFormat` question, once per file. Choosing the flip
    /// reading re-dates the ambiguous candidates (month and day swap); the
    /// M/D reading is already what the wire carries. Either way the preview and
    /// the review list rebuild against the corrected dates, so the number the
    /// user approves is the number that lands (F6a).
    func answerDateFormat(_ option: String) {
        guard let ambiguity = dateFormatAmbiguity,
              ambiguity.options.contains(option) else { return }
        dateFormatAnswer = option
        rebuildClassification()
    }

    /// The candidates with the chosen date reading applied: the wire's M/D set
    /// as-is, or the D/M flip when the user answered with `options[1]`. The
    /// pristine parse is never mutated, so re-answering stays correct.
    private var effectiveCandidates: [ImportCandidate] {
        guard let parse else { return [] }
        return ImportDateFormat.candidates(for: parse, answer: dateFormatAnswer)
    }

    /// The `outOfScope` message the preview surfaces, if the server reported
    /// one (a recognised file whose rows are deliberately unmapped - income,
    /// reminders - docs/API.md). The message names the scope and the count so
    /// "we read the file but show nothing" never reads as a silent drop.
    var outOfScopeMessage: String? {
        guard let ambiguity = parse?.ambiguities.first(where: { $0.kind == "outOfScope" }),
              let option = ambiguity.options.first else { return nil }
        switch option {
        case "income": return L10n.outOfScopeIncome(ambiguity.rowCount)
        case "reminder": return L10n.outOfScopeReminder(ambiguity.rowCount)
        default: return nil
        }
    }

    // MARK: - Review list

    /// "Leave out" / "Import" toggle for a review row. A row with no record to
    /// commit (an unparsed row, a non-fill row that could not be mapped) is
    /// always left out; a `.noFuel` row toggles its "Import as service /
    /// expense" choice (PJ.9).
    func toggleSkipped(sourceRow: Int) {
        if skippedSourceRows.contains(sourceRow) {
            skippedSourceRows.remove(sourceRow)
        } else {
            skippedSourceRows.insert(sourceRow)
        }
    }

    func isSkipped(sourceRow: Int) -> Bool {
        if let row = reviewRows.first(where: { $0.sourceRow == sourceRow }) {
            // A row with nothing to commit is always left out: an unparsed row
            // has no record at all, and a `.noFuel` row stays out until the
            // user chooses to import it as a service/expense (PJ.9) - the
            // non-fuel action, never a silent commit.
            if row.fill == nil && row.nonFuel == nil { return true }
        }
        return skippedSourceRows.contains(sourceRow)
    }

    /// "Add odometer" - sets the review row's fill odometer from a typed value.
    /// The edit is applied at the CANDIDATE level and the whole classification
    /// rebuilds (PJ.11): a corrected odometer can resolve a `.timelineConflict`
    /// row exactly as it resolves a `.missingOdometer` one, and a value that
    /// resolves the row promotes it to the ready set; clearing it keeps the gap
    /// a gap (never `0`).
    func setOdometer(_ value: Int?, for sourceRow: Int) {
        if let value {
            odometerEdits[sourceRow] = value
            skippedSourceRows.remove(sourceRow)
        } else {
            odometerEdits[sourceRow] = nil
        }
        rebuildClassification()
    }

    /// "Fix" - corrects the total on a cross-check-mismatch row. Recorded and
    /// rebuilt like an odometer edit, so the corrected arithmetic is what the
    /// conversion re-derives (and the cross-check recomputes against it).
    func setTotal(_ amount: Decimal, for sourceRow: Int) {
        totalEdits[sourceRow] = amount
        skippedSourceRows.remove(sourceRow)
        rebuildClassification()
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

    /// Every record the commit will write: the ready fills plus the review rows
    /// the user kept - a kept fill writes a `FillUp`, a kept `.noFuel` row
    /// writes its `ServiceRecord` or `Expense` (PJ.9: a non-fuel row commits as
    /// what it is, `provenance = .import`, never silently dropped - hard rule
    /// 8). The preview's figures are computed over the fills in this set.
    var importRecords: [ArchiveImportRecord] {
        var records: [ArchiveImportRecord] = readyFills.map { ArchiveImportRecord.fillUp($0) }
        let keptReview = reviewRows.filter { row in
            !isSkipped(sourceRow: row.sourceRow)
                && (row.fill != nil || row.nonFuel != nil)
        }
        for row in keptReview {
            if let fill = row.fill {
                records.append(.fillUp(fill))
            } else if let nonFuel = row.nonFuel {
                switch nonFuel {
                case .service(let service): records.append(.serviceRecord(service))
                case .expense(let expense): records.append(.expense(expense))
                }
            }
        }
        return records
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
        totalEdits = [:]
        dateFormatAnswer = nil
        step = .source
    }

    // MARK: - Confirm (the ONE write)

    /// Writes the kept records and drops the stored parse. Returns whether the
    /// repository write succeeded. This is the only mutation the whole flow
    /// performs - hard rule 8 has nothing to lose because nothing was staged.
    /// The commit is refused until every F6 question is answered (PJ.10): a
    /// `dateFormat` question unanswered would write the file under the parser's
    /// M/D guess.
    @discardableResult
    func confirmImport() async -> Bool {
        guard let parse else { return false }
        guard canConfirm else { return false }
        let records = importRecords
        guard !records.isEmpty else {
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
            try repository.commitImport(records, source: source)
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
    /// target car, keeping the user's skip/odometer/total decisions by source
    /// row. Reads the candidates through the date-format answer (PJ.10) AND the
    /// user's review-list edits, so answering the question or fixing a value
    /// re-derives every figure and review row. PJ.11: the timeline is validated
    /// against the target car's existing entries here, so a `.timelineConflict`
    /// row appears in the review list before anything is written.
    private func rebuildClassification() {
        guard let parse, let targetCar else { return }
        let vehicle = targetCar.vehicleValue
        let lines = ImportRawLines.dataLines(from: uploadedFileData)
        var candidates = effectiveCandidates
        // Fold the user's review-list edits in at the CANDIDATE level: the
        // partition then applies the SAME conversion and timeline validation to
        // an edited row as to an untouched one, so a fixed odometer can resolve
        // a `.timelineConflict` row and a fixed total a `.crossCheckMismatch`
        // one - each in the same pass.
        if !odometerEdits.isEmpty || !totalEdits.isEmpty {
            candidates = candidates.map { candidate in
                var edited = candidate
                if let odometer = odometerEdits[candidate.sourceRow] {
                    edited = edited.applyingOdometer(odometer)
                }
                if let total = totalEdits[candidate.sourceRow] { edited = edited.applyingTotal(total) }
                return edited
            }
        }
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: candidates,
            unparsed: parse.unparsed,
            rawLinesByRow: lines,
            vehicle: vehicle,
            source: source,
            existingEntries: existingEntries)

        self.readyFills = ready
        self.reviewRows = review
    }

    /// The target car's existing entries, against which the incoming fills'
    /// timeline is validated (PJ.11): a merge must flag an odometer that breaks
    /// the CAR's order, not just the file's own. A new car has none.
    private var existingEntries: [any Entry] {
        guard case .existing(let vehicle) = targetCar else { return [] }
        return (try? repository.liveEntries(forVehicle: vehicle.id)) ?? []
    }
}

// MARK: - Parse (PR.6)

extension ImportFlowModel {
    /// The in-flight parse's body: reads the server response and advances the
    /// wizard. Cancellation-aware - a user Cancel leaves `parseFailure` nil and
    /// the wizard on the source step, with nothing written (F6a).
    private func performParse(data: Data, fileName: String, format: ImportFormat,
                              preferredVehicleID: UUID?) async {
        defer {
            isParsing = false
            parseTask = nil
        }
        do {
            let result = try await client.parseFile(data: data,
                                                    fileName: fileName,
                                                    format: format)
            guard !Task.isCancelled else { return }
            pickedFileName = fileName
            uploadedFileData = data
            parse = result
            ensureTargetCar(preferredVehicleID: preferredVehicleID)
            rebuildClassification()
            step = .preview
        } catch let error as ImportClientError {
            guard !Task.isCancelled else { return }
            parseFailure = Self.failure(for: error, format: format)
            step = .source
        } catch {
            guard !Task.isCancelled else { return }
            parseFailure = .unknown
            step = .source
        }
    }
}
