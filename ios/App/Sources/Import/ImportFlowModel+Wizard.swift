import Foundation
import TankbookCore

// The wizard's gates and its one write (P5.5b) - the parts of `ImportFlowModel`
// that decide, review and confirm. Split from the model's declaration file so
// the class stays under the repo's lint floors; the state lives in the
// declaration, these extensions only read and mutate it through its methods.

extension ImportFlowModel {
    // MARK: - The date-format question (PJ.10)

    /// The `dateFormat` ambiguity the server reported, if any (F6: ambiguity is
    /// returned, never guessed - the parser's M/D reading must not stand silent).
    var dateFormatAmbiguity: ImportAmbiguity? {
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

    /// Answers the `dateFormat` question, once per export (RV.93: the whole
    /// batch shares one exporter, so one answer governs it; a file that PROVED
    /// its dates never flips - the per-file flip happens inside the merge).
    /// Choosing the flip reading re-dates the ambiguous candidates (month and
    /// day swap); the M/D reading is already what the wire carries. Either way
    /// the merged parse, the preview and the review list rebuild, so the number
    /// the user approves is the number that lands (F6a).
    func answerDateFormat(_ option: String) {
        guard let ambiguity = dateFormatAmbiguity,
              ambiguity.options.contains(option) else { return }
        dateFormatAnswer = option
        syncMergedParse()
        rebuildClassification()
    }

    /// Answers the currency question (RV.113), once per file. The pick applies
    /// to every money-carrying candidate, and the classification rebuilds so the
    /// preview, the review list and the commit all read the answered currency -
    /// the number the user approves is the number that lands (F6a).
    func answerCurrency(_ code: CurrencyCode) {
        guard hasCurrencyQuestion else { return }
        currencyAnswer = code
        rebuildClassification()
    }

    /// The candidates with the chosen date reading applied. The merged parse is
    /// ALREADY the answer applied - `ImportBatchMerge` re-dates per file that
    /// needs it, and re-dating the merged list again would double-flip an
    /// ambiguous file and corrupt a file that proved its dates (RV.85). So this
    /// is simply the merged candidates; the pristine per-file parses are never
    /// mutated, so re-answering stays correct. A file with no currency column
    /// (RV.113) has the user's currency answer (or the car's home currency)
    /// applied here, so the conversion and the commit read the answered money.
    var effectiveCandidates: [ImportCandidate] {
        guard let parse else { return [] }
        guard hasCurrencyQuestion, let currency = effectiveCurrency else {
            return parse.candidates
        }
        return parse.candidates.map { $0.applyingCurrency(currency) }
    }

    /// The currency question's answer: the user's pick, or the destination car's
    /// home currency when they have not overridden it (the default the wizard
    /// offers - hard rule 13, never a fact).
    var effectiveCurrency: CurrencyCode? {
        guard hasCurrencyQuestion else { return parse?.declaredCurrency }
        return currencyAnswer ?? defaultCurrency
    }

    var hasCurrencyQuestion: Bool { parse?.hasCurrencyQuestion ?? false }

    /// The destination car's home currency - the default the currency question
    /// offers. A brand-new car is EUR; an existing car is its own home currency.
    var defaultCurrency: CurrencyCode {
        targetCar?.vehicleValue.homeCurrency ?? liveVehicles.first?.homeCurrency ?? .eur
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
            declaredCurrency: effectiveCurrency)
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

    /// The review list's exit: back to the gate that asks the questions. The
    /// `.preview` for a single-car file (today's flow, byte-for-byte); the
    /// `.cars` mapping screen for a multi-car one (RV.86: the mapping step IS
    /// that file's gate - it carries the figures and the commit).
    func reviewReturn() {
        rebuildClassification()
        step = carPlan.isEmpty ? .preview : .cars
    }

    // MARK: - Cancel (F6a: nothing is written, and the stored parse is deleted)

    /// Cancel deletes every stored parse of the pick (`DELETE /v1/import/{id}`
    /// per file - a batch stored N parses, RV.93) and writes nothing. The
    /// garage is untouched.
    func cancelImport() async {
        await deleteStoredParses()
        resetFlow()
    }

    /// Drops the server-side parse storage for every successfully-parsed file
    /// (each file was its own `POST /v1/import/parse` - hard rule 9's per-file
    /// pure function - so each has its own stored parse to delete). Best effort:
    /// `DELETE` is idempotent and a failure here is server storage, not user
    /// data on the device.
    func deleteStoredParses() async {
        for file in parseFiles {
            try? await client.deleteParse(importId: file.parse.importId)
        }
    }

    func resetFlow() {
        parseFiles = []
        fileFailures = []
        parse = nil
        mergedRawLines = [:]
        pickedFileName = nil
        uploadedFileData = nil
        reviewRows = []
        readyFills = []
        skippedSourceRows = []
        odometerEdits = [:]
        totalEdits = [:]
        dateFormatAnswer = nil
        currencyAnswer = nil
        carPlan = []
        targetCar = nil
        step = .source
    }

    // MARK: - Confirm (the ONE write)

    /// Writes the kept records and drops the stored parses. Returns whether the
    /// repository write succeeded. This is the only mutation the whole flow
    /// performs - hard rule 8 has nothing to lose because nothing was staged.
    /// The commit is refused until every F6 question is answered (PJ.10): a
    /// `dateFormat` question unanswered would write the export under the
    /// parser's M/D guess. RV.86: a multi-car file's records already carry each
    /// lane's destination vehicle (the per-lane classification stamped them), so
    /// this one write lands every car in its own place; the only extra step is
    /// creating the NEW cars the mapping chose, exactly as the single-car flow
    /// creates its one new target. RV.93: a whole-export pick is still ONE write
    /// - `commitImport` receives every file's records at once, so a half-imported
    /// export can never become a state nothing can undo (F6a).
    @discardableResult
    func confirmImport() async -> Bool {
        guard parse != nil else { return false }
        guard canConfirm else { return false }
        let records = importRecords
        guard !records.isEmpty else {
            await deleteStoredParses()
            didConfirm = true
            return true
        }
        do {
            // RV.93: the write order is vehicles first, entries second. Creating
            // the NEW cars before `commitImport` is what lets one transaction
            // land every file's entries on the cars the mapping chose; entries
            // written before their vehicle existed could not reference it.
            if carPlan.isEmpty {
                if let targetCar {
                    if case .new(let newCar) = targetCar {
                        try repository.upsertVehicle(newCar)
                    }
                }
            } else {
                // RV.86: create each NEW destination the mapping chose - but
                // only when that lane actually contributes a record, so a lane
                // whose rows the user left out never mints an empty car.
                let destinationIDs = Set(records.compactMap(\.importVehicleID))
                for row in carPlan {
                    if case .new(let newCar) = row.destination,
                       destinationIDs.contains(newCar.id) {
                        try repository.upsertVehicle(newCar)
                    }
                }
            }
            try repository.commitImport(records + materializedStationRecords(for: records),
                                        source: source)
            await deleteStoredParses()
            // RV.88: the rows land rate-pending (a foreign-currency file into a
            // different-currency car), and nothing else on this path resolves
            // them - drain them now, each at its OWN entry date. Re-planted
            // here when RV.86 split this method out of ImportFlowModel: the
            // merge would otherwise have deleted it silently, since RV.88's
            // own tests are L1 and never run this app-layer commit.
            AppRates.scheduleDrainAfterImport(records)
            didConfirm = true
            return true
        } catch {
            confirmFailed = true
            return false
        }
    }

    /// The Station rows this commit must create (RV.142), as `ArchiveImportRecord`
    /// entries appended to the SAME `commitImport` call - one transaction, so a
    /// fill never references a station that did not land. A kept fill's station
    /// name was resolved to a deterministic id at classification; rows the user
    /// skipped mint no station, and a station the device already has (matched by
    /// name at classification) is not written again. Records that are not fills
    /// (service/expense) have no station and contribute nothing.
    private func materializedStationRecords(for records: [ArchiveImportRecord]) -> [ArchiveImportRecord] {
        let keptStationIDs = Set(records.compactMap { record -> UUID? in
            if case .fillUp(let fill) = record { return fill.stationId } else { return nil }
        })
        guard !keptStationIDs.isEmpty else { return [] }
        let existing = (try? repository.liveStations()) ?? []
        var nameByID: [UUID: String] = [:]
        for candidate in effectiveCandidates {
            guard let name = candidate.trimmedStation else { continue }
            nameByID[ImportStationResolver.station(for: name, existing: existing).id] = name
        }
        return ImportStationResolver.missingStations(keptStationIDs: keptStationIDs,
                                                     nameByID: nameByID,
                                                     existing: existing)
            .map(ArchiveImportRecord.station)
    }

    // MARK: - Classification

    /// Splits the parse into ready fills and review rows, keeping the user's
    /// skip/odometer/total decisions by source row. Reads the candidates through
    /// the date-format answer (PJ.10) AND the user's review-list edits, so
    /// answering the question or fixing a value re-derives every figure and
    /// review row. PJ.11: the timeline is validated against the destination
    /// car's existing entries here, so a `.timelineConflict` row appears in the
    /// review list before anything is written.
    ///
    /// RV.86: a single-name file classifies as one partition against the target
    /// car (byte-for-byte today's flow). A multi-car file classifies LANE BY
    /// LANE (`partitionByLanes`) - each source group against ITS destination
    /// vehicle and that car's own entries - so two cars can never corrupt each
    /// other's odometers. RV.93: the candidates and raw lines are the MERGED
    /// view (`parse`/`mergedRawLines`, re-keyed into one global source-row
    /// space), so a whole-export pick validates per lane exactly as one file
    /// does - a service from costs.csv and the fills from fuel.csv that bracket
    /// it are ONE timeline, never two validations that cannot see each other.
    func rebuildClassification() {
        guard let parse else { return }
        let lines = mergedRawLines
        let existingStations = (try? repository.liveStations()) ?? []
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
        if carPlan.isEmpty {
            guard let targetCar else { return }
            let vehicle = targetCar.vehicleValue
            let (ready, review) = ImportReviewClassifier.partition(
                candidates: candidates,
                unparsed: parse.unparsed,
                rawLinesByRow: lines,
                vehicle: vehicle,
                source: source,
                existingEntries: existingEntries,
                existingStations: existingStations)
            self.readyFills = ready
            self.reviewRows = review
        } else {
            // Multi-car: one lane per source group the user decided to bring in,
            // each validated against its own destination's existing entries.
            var existingByVehicle: [UUID: [any Entry]] = [:]
            for row in carPlan {
                guard let vehicle = row.destinationVehicle,
                      existingByVehicle[vehicle.id] == nil else { continue }
                existingByVehicle[vehicle.id] = (try? repository.liveEntries(forVehicle: vehicle.id)) ?? []
            }
            let lanes = carPlan.compactMap { row -> ImportLane? in
                guard let vehicle = row.destinationVehicle else { return nil }
                return ImportLane(sourceRows: row.group.sourceRows, vehicle: vehicle)
            }
            let (ready, review) = ImportReviewClassifier.partitionByLanes(
                candidates: candidates,
                lanes: lanes,
                existingEntriesByVehicle: existingByVehicle,
                existingStations: existingStations,
                unparsed: parse.unparsed,
                rawLinesByRow: lines,
                source: source)
            self.readyFills = ready
            self.reviewRows = review
        }
    }

    /// The target car's existing entries, against which the incoming fills'
    /// timeline is validated (PJ.11): a merge must flag an odometer that breaks
    /// the CAR's order, not just the file's own. A new car has none. Used by
    /// the single-car partition; multi-car reads each lane's car separately.
    var existingEntries: [any Entry] {
        guard case .existing(let vehicle) = targetCar else { return [] }
        return (try? repository.liveEntries(forVehicle: vehicle.id)) ?? []
    }
}


// MARK: - Parse (PR.6)

extension ImportFlowModel {
    /// RV.73: the pick's staged copy failed - the stager logged the type/code;
    /// this sets the read-failure state so the wizard shows the honest card.
    func reportPickedFileCouldNotBeRead() {
        parseFailure = .couldNotRead
    }

    /// Maps a parse error to the parse-failure surface (RV.68: a transport
    /// failure that is not a connectivity signal and a decode break never mean
    /// "you need a connection"; `.cancelled` is handled in `performParse`
    /// before this switch).
    static func failure(for error: ImportClientError, format: ImportFormat) -> ParseFailure {
        switch error {
        case .transportUnreachable: return .transportUnreachable
        case .oversize: return .oversize
        case .unrecognisedFormat: return .unrecognisedFormat
        case .doesNotMatchDeclared: return .doesNotMatchDeclared(displayName: format.displayName)
        case .inconsistentDates: return .inconsistentDates
        case .server(let status): return .server(status: status)
        case .invalidResponse, .missingIdentity, .client, .transportFailure, .cancelled:
            return .unknown
        }
    }

    /// The in-flight single-file parse's body: reads the server response and
    /// advances the wizard. Cancellation-aware - a user Cancel leaves
    /// `parseFailure` nil and the wizard on the source step, with nothing
    /// written (F6a). RV.86: a file holding several source cars lands on the
    /// `.cars` mapping step, a single-car file on today's `.preview`. RV.93: the
    /// result joins the pick as a parsed file and the merged view re-derives,
    /// so single-file and whole-export picks share one downstream path.
    func performParse(data: Data, fileName: String, format: ImportFormat,
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
            parseFiles = []
            fileFailures = []
            adoptSingleFile(fileName: fileName, rawData: data, parse: result)
            routeAfterParse(preferredVehicleID: preferredVehicleID)
            step = carPlan.isEmpty ? .preview : .cars
        } catch let error as ImportClientError {
            guard !Task.isCancelled else { return }
            // RV.68: a cancelled parse is not a failure - the user's Cancel (or a
            // torn-down task) stops the upload and nothing surfaces. Identical
            // to the `Task.isCancelled` path above, reached when the cancellation
            // arrived through the transport rather than the task flag.
            if case .cancelled = error { return }
            parseFailure = Self.failure(for: error, format: format)
            step = .source
        } catch {
            guard !Task.isCancelled else { return }
            parseFailure = .unknown
            step = .source
        }
    }

    // MARK: - Whole-export pick (RV.93)

    /// A fresh pick replaces the previous batch state: whatever the source step
    /// was showing (a prior batch's per-file failures, an undecided preview) is
    /// dropped before the new files stage. Nothing is written - this is the
    /// same nothing-was-staged promise as `cancelParse`.
    func preparePick() {
        parseFiles = []
        fileFailures = []
        parse = nil
        mergedRawLines = [:]
        reviewRows = []
        readyFills = []
        skippedSourceRows = []
        odometerEdits = [:]
        totalEdits = [:]
        carPlan = []
        targetCar = nil
        dateFormatAnswer = nil
        currencyAnswer = nil
        parseFailure = nil
        step = .source
    }

    /// Parses a whole-export pick of N files, one `POST /v1/import/parse` call
    /// per file (the server stays a per-file pure function - hard rule 9). Each
    /// upload is parsed independently; a file that fails is recorded per-file
    /// (`fileFailures`) and the rest continue - one bad file never kills the
    /// batch (hard rule 7: every failure names its file, and the successful
    /// files survive it). When every file has been tried, the successful parses
    /// become the merged whole-export view. A read failure (the bytes never got
    /// into the container) is reported before this, via `reportBatchReadFailure`.
    func beginBatchParse(uploads: [ImportFileUpload], preferredVehicleID: UUID?) {
        guard let format = pickedFormat else { return }
        guard !serverBackedPaused else { return }
        guard !uploads.isEmpty else { return }
        isParsing = true
        parseFailure = nil
        parseFiles = []
        fileFailures = []
        parse = nil
        mergedRawLines = [:]
        parseTask?.cancel()
        parseTask = Task { [weak self] in
            await self?.performBatchParse(uploads: uploads, format: format,
                                          preferredVehicleID: preferredVehicleID)
        }
    }

    /// A staged pick whose bytes could not be read (RV.73) joins the per-file
    /// failures so a whole-export pick reports it by name and survives the rest
    /// (hard rule 7) - the same honest card the single-file path shows, per file.
    func reportBatchReadFailure(fileName: String) {
        fileFailures.append(ImportFileFailure(fileName: fileName, failure: .couldNotRead))
    }

    /// The batch's body. Uploads each file in turn, appending the successful
    /// parses and recording per-file failures.
    func performBatchParse(uploads: [ImportFileUpload], format: ImportFormat,
                           preferredVehicleID: UUID?) async {
        defer {
            isParsing = false
            parseTask = nil
        }
        for upload in uploads {
            if Task.isCancelled { return }
            do {
                let result = try await client.parseFile(data: upload.data,
                                                        fileName: upload.fileName,
                                                        format: format)
                guard !Task.isCancelled else { return }
                parseFiles.append(ImportParseFile(fileName: upload.fileName,
                                                  rawData: upload.data,
                                                  parse: result))
            } catch let error as ImportClientError {
                guard !Task.isCancelled else { return }
                if case .cancelled = error { return }
                fileFailures.append(ImportFileFailure(
                    fileName: upload.fileName,
                    failure: Self.failure(for: error, format: format)))
            } catch {
                guard !Task.isCancelled else { return }
                fileFailures.append(ImportFileFailure(fileName: upload.fileName,
                                                      failure: .unknown))
            }
        }
        guard !Task.isCancelled else { return }
        finishBatch(preferredVehicleID: preferredVehicleID)
    }

    /// Routes the wizard after a whole-export pick has been parsed. With no
    /// failures the batch advances straight to the mapping/preview gate; with
    /// per-file failures it stops at the source step, where every failure names
    /// its file and its next step, and the bar offers to continue with the
    /// files that did parse (hard rule 7 - the run survives).
    func finishBatch(preferredVehicleID: UUID?) {
        if parseFiles.isEmpty {
            step = .source
            return
        }
        syncMergedParse()
        routeAfterParse(preferredVehicleID: preferredVehicleID)
        step = fileFailures.isEmpty ? (carPlan.isEmpty ? .preview : .cars) : .source
    }

    /// "Continue with N files" - the source step's bar when part of the pick
    /// failed: the successful files advance to the mapping/preview gate, and
    /// the failed ones stay behind as the cards the user already saw.
    func continueAfterBatchFailures() {
        step = carPlan.isEmpty ? .preview : .cars
    }
}
