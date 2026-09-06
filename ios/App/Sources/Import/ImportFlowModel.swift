import Foundation
import TankbookCore

// The import wizard's state (P5.5b) - docs/ERRORS.md -> Import wizard,
// docs/JOURNEYS.md F6. The model owns the wizard's steps - source picker, the
// `.cars` mapping gate a multi-car file earns (RV.86), the preview gate and the
// review list - the one `ImportClient`, and the ONE write the flow performs:
// `confirmImport` calls `repository.commitImport`. Building the preview,
// computing the figures, cancelling and reviewing all touch the repository NOT
// AT ALL - F6a: nothing is written until the user confirms. The step logic
// lives in `ImportFlowModel+Wizard.swift` (gates, review, the write) and
// `ImportFlowModel+Cars.swift` (the multi-car plan).

@MainActor
@Observable
final class ImportFlowModel {

    enum Step: Equatable {
        case source
        case cars
        case preview
        case review
    }

    /// The format list's state (docs/ERRORS.md -> Import wizard). Offline is
    /// said plainly before the tap, never discovered as a failure after it.
    /// RV.68: `.offline` is reserved for a genuine connectivity failure - a
    /// server error (`.serverError`), a client/server contract break
    /// (`.contractError`) and anything else (`.failed`) each get their own
    /// honest card, never the "needs a connection" one.
    enum FormatsState: Equatable {
        case idle
        case loading
        case loaded
        case offline
        case contractError
        case serverError
        case failed
    }

    /// The parse's failure, each mapped to a specific message (F7) - never a
    /// generic "something went wrong".
    enum ParseFailure: Equatable {
        /// The file could not be READ locally (RV.73) - no parse was attempted.
        /// Distinct from the parse-failure cases below, whose next step differs.
        case couldNotRead
        case doesNotMatchDeclared(displayName: String)
        /// RV.85: the file is an MFM export whose dates mix two orders. Not the
        /// `dateFormat` question - no single answer exists - so it is its own
        /// message, never a question the user cannot answer correctly.
        case inconsistentDates
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

    var step: Step = .source
    var formats: [ImportFormat] = []
    var formatsState: FormatsState = .idle

    var pickedFormat: ImportFormat?
    var pickedFileName: String?
    var uploadedFileData: Data?
    /// RV.93: the successfully-parsed files of the current pick. ONE for a
    /// single-file pick (the flow stays byte-for-byte); several for a
    /// whole-export pick, which is N separate `POST /v1/import/parse` calls -
    /// the server stays a per-file pure function (hard rule 9) and the grouping
    /// happens here, in `syncMergedParse`.
    var parseFiles: [ImportParseFile] = []
    /// RV.93: the picked files that failed to parse, each with its own failure.
    /// A failed file names its next step and the run survives the rest (hard
    /// rule 7) - the successful files above are committed together.
    var fileFailures: [ImportFileFailure] = []
    /// The merged parse (`parse`'s value) plus its raw lines under the SAME
    /// global source rows, re-derived from `parseFiles` + `dateFormatAnswer` by
    /// `syncMergedParse`. `parse` stays a stored var so the many readers of
    /// today's single-file model read the merged view unchanged.
    var mergedRawLines: [Int: String] = [:]
    var parse: ImportParseResponse?
    var isParsing = false
    var parseFailure: ParseFailure?
    /// True while the source step holds a batch result that PARTLY failed:
    /// successful files are waiting behind the per-file failure cards, and the
    /// bar offers "Continue with N files" (the run survives - hard rule 7).
    var batchHasFailures: Bool { !fileFailures.isEmpty && !parseFiles.isEmpty }
    /// The in-flight parse, so the user's Cancel can stop the upload (a wait the
    /// user cannot escape is the bug hard rule 7 exists to remove - PR.6).
    var parseTask: Task<Void, Never>?

    var liveVehicles: [Vehicle] = []
    var targetCar: TargetCar?
    /// RV.86: one row per distinct source car in a multi-car file, holding the
    /// user's decision about where each lands. Empty for a file with one
    /// distinct name, which keeps the single `targetCar` flow untouched.
    var carPlan: [ImportCarRow] = []

    /// The unit every odometer in the review list renders in. Taken from the
    /// target car when there is one; a brand-new car has not chosen yet, so it
    /// falls back to the app default. Never a hardcoded "km" - hard rule 10, and
    /// the `Text(_: String)` blind spot that let one ship (see L10n.swift).
    var distanceUnit: DistanceUnit {
        if case .existing(let vehicle) = targetCar { return vehicle.units.distance }
        return liveVehicles.first?.units.distance ?? .km
    }

    /// A review row's odometer renders in ITS car's unit (RV.86: a multi-car
    /// file's rows can land in cars with different units). Resolves the row's
    /// fill/non-fuel vehicle through the mapping; a single-name file's rows all
    /// carry the target car's id, so this equals `distanceUnit` there.
    func distanceUnit(for row: ImportReviewRow) -> DistanceUnit {
        let vehicleID = row.fill?.vehicleId ?? row.nonFuelVehicleID
        if let vehicleID, let unit = vehicleDistanceUnit(for: vehicleID) {
            return unit
        }
        return distanceUnit
    }

    /// The distance unit of the car a review row belongs to, when that car is
    /// known through the current mapping or the single target car.
    private func vehicleDistanceUnit(for vehicleID: UUID) -> DistanceUnit? {
        if case .existing(let vehicle) = targetCar, vehicle.id == vehicleID {
            return vehicle.units.distance
        }
        for row in carPlan {
            if row.destinationVehicleID == vehicleID {
                return row.destinationVehicle?.units.distance
            }
        }
        return liveVehicles.first(where: { $0.id == vehicleID })?.units.distance
    }

    var readyFills: [FillUp] = []
    var reviewRows: [ImportReviewRow] = []
    /// Review rows the user left out, keyed by `sourceRow` (stable across
    /// reclassification - the fills and row ids are minted fresh per rebuild).
    var skippedSourceRows: Set<Int> = []
    /// Odometer values the user typed in the review list, keyed by `sourceRow`.
    var odometerEdits: [Int: Int] = [:]
    /// Totals the user fixed in the review list, keyed by `sourceRow` (PJ.11).
    /// Applied to the candidates before the partition, so a corrected total
    /// re-derives exactly like an untouched row (F6a: the number approved lands).
    var totalEdits: [Int: Decimal] = [:]

    /// The `dateFormat` question's answer - the chosen option ("M/D/YYYY" or
    /// "D/M/YYYY"), nil until the user answers. Asked ONCE per file, at the
    /// preview gate (docs/JOURNEYS.md F6, docs/API.md): the wire carries the
    /// M/D reading, so choosing D/M re-dates the ambiguous candidates before
    /// anything is committed. nil when the parse reported no ambiguity.
    var dateFormatAnswer: String?

    var didConfirm = false
    var confirmFailed = false

    /// The parse's source id (`mfm`, ...) - the provenance every committed row
    /// carries (P5.4: `provenance = { tag: "import", source: <format> }`). All
    /// of a batch's files share the format (they come from one exporter).
    var source: String {
        parseFiles.first?.parse.format ?? pickedFormat?.id ?? parse?.format ?? "unknown"
    }

    /// The one source line the wizard shows ("from fuel.csv · nothing is saved
    /// yet", or its whole-export form). Single file = the file's name, exactly
    /// as before; a batch names its size (hard rule 10: full localised phrases).
    var pickedFileSummary: String {
        if let pickedFileName, parseFiles.count <= 1 {
            return L10n.fromFileNothingSaved(fileName: pickedFileName)
        }
        return L10n.fromFilesNothingSaved(count: parseFiles.count)
    }

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

    // MARK: - Source step

    /// Loads `GET /v1/import/formats` - the picker renders this response and
    /// nothing else. Offline is a distinct, named state, reachable ONLY from a
    /// genuine connectivity failure (RV.68): a cancellation is not an error at
    /// all, a decode failure is a contract bug, and a 5xx is a server problem -
    /// none of them may render as "Importing needs a connection". Withheld
    /// under `.required` (P6.18b) - the source screen shows the update notice
    /// instead.
    func loadFormats() async {
        guard !serverBackedPaused else { return }
        guard formatsState != .loading && formatsState != .loaded else { return }
        formatsState = .loading
        do {
            formats = try await client.fetchFormats()
            formatsState = .loaded
        } catch let error as ImportClientError {
            // RV.68: the outcome is decided in core (ImportFormatsOutcome) so
            // the L1 tests assert the mapping over the wire's error classes.
            // `.offline` is reachable only from `.transportUnreachable`; a
            // `.noError` (cancellation) reverts to idle rather than leaving
            // `.loading`, so a `.task` SwiftUI re-fires after a view update
            // reloads instead of spinning forever.
            switch error.formatsOutcome {
            case .offline: formatsState = .offline
            case .contractError: formatsState = .contractError
            case .serverError: formatsState = .serverError
            case .failed: formatsState = .failed
            case .noError:
                if formatsState == .loading { formatsState = .idle }
            }
        } catch {
            formatsState = .failed
        }
    }

    func selectFormat(_ format: ImportFormat) {
        pickedFormat = format
        parseFailure = nil
    }

    /// Uploads the picked file to `POST /v1/import/parse` and classifies the
    /// response into ready fills and review rows. The server commits nothing;
    /// neither does this. The parse runs in a tracked task so `cancelParse`
    /// can stop it (PR.6 - a half-connected radio must not freeze the wizard
    /// for the full upload budget with no escape). RV.93: this is the
    /// SINGLE-file path, byte-for-byte today's flow - a whole-export pick of
    /// several files goes through `beginBatchParse` instead.
    func parse(fileURL: URL, preferredVehicleID: UUID? = nil) {
        guard let format = pickedFormat else { return }
        guard !serverBackedPaused else { return } // P6.18b: parse is withheld under `.required`.
        // RV.73: never read silently - log the error's type/code and set the READ-failure state, not a parse one.
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            AppLog.shared.emit(ImportReadFailure(error: error))
            parseFailure = .couldNotRead
            return
        }
        isParsing = true
        parseFailure = nil
        parseFiles = []
        fileFailures = []
        parse = nil
        mergedRawLines = [:]
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
    func ensureTargetCar(preferredVehicleID: UUID?) {
        guard targetCar == nil else { return }
        if let preferred = liveVehicles.first(where: { $0.id == preferredVehicleID })
            ?? liveVehicles.first {
            targetCar = .existing(preferred)
        } else {
            targetCar = .newCar(named: newCarName)
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

}
