import Foundation

// RV.93 - one export is several files, and the wizard takes them in one pass.
// The server stays a per-file pure function (hard rule 9's narrowest possible
// exception - N files mean N `POST /v1/import/parse` calls); THIS file is the
// device-side grouping that reassembles the export. It is pure: given the
// picked files' parses (each with its local raw lines) and the user's one
// date-format answer, it returns the merged view - candidates, vehicle groups
// and unparsed rows all re-keyed into ONE global source-row space, plus the
// raw lines under the same keys.
//
// Why a global re-key: the review list, the skip set and the odometer/total
// edits are keyed by `sourceRow`, and every file numbers its own rows from 1.
// Two files' row 5 must not collide, so each file's rows move into its own
// global band before anything downstream reads them. The bands come from the
// files' own row extents, so the mapping is deterministic for a given pick.
//
// Why union groups: the `Vehicle name` column is identical across the export's
// files (verified in RV.86), so one mapping answers for all of them. A source
// car's group therefore carries every file's rows that carry that name, and the
// wizard asks once per DISTINCT name, never once per file.
//
// Why per-file date handling: the `dateFormat` question is a once-per-export
// question, but the D/M flip must re-date ONLY the files whose parse reported
// the ambiguity. A file whose own rows proved M/D (RV.85 - the server resolved
// every date) must not be re-dated by another file's ambiguity; the merged
// candidates are therefore produced by applying the answer to each file that
// needs it, never to the merged list as a whole.

/// One successfully-parsed picked file: the wire response plus the file's OWN
/// raw lines, keyed by the file's own 1-based data-row numbers (the "Original
/// row" renderer reads them - P6.15c).
public struct ImportParsedFile: Sendable {
    public let parse: ImportParseResponse
    public let rawLines: [Int: String]

    public init(parse: ImportParseResponse, rawLines: [Int: String]) {
        self.parse = parse
        self.rawLines = rawLines
    }
}

/// The merged view of a whole-export pick (RV.93). Candidates, groups, unparsed
/// rows and raw lines share ONE global `sourceRow` space, so every downstream
/// consumer - the lane partition, the review list, the skip/odometer/total
/// edits - treats a multi-file export exactly as it treats a single file.
public struct ImportBatchView: Sendable {
    /// The merged parse: candidates in pick order under global source rows, the
    /// vehicle groups unioned by name, the unparsed rows re-keyed, and the
    /// F6 ambiguities summed across the files that carry them.
    public let parse: ImportParseResponse
    /// The raw source lines under the same global keys as the merged candidates.
    public let rawLinesByRow: [Int: String]

    public init(parse: ImportParseResponse, rawLinesByRow: [Int: String]) {
        self.parse = parse
        self.rawLinesByRow = rawLinesByRow
    }
}

/// The device-side grouping that turns N parsed files into one importable
/// whole (docs/JOURNEYS.md F6, hard rule 9: the server is not asked to do
/// this - it stays a per-file pure function).
public enum ImportBatchMerge {

    /// Merges the picked files' parses into one view. nil when the batch is
    /// empty. `dateFormatAnswer` is the once-per-export answer to the F6
    /// `dateFormat` question (nil until asked): files whose parse reported the
    /// ambiguity are re-dated when the answer flips to D/M; files that proved
    /// their dates are never touched.
    public static func merge(files: [ImportParsedFile],
                             dateFormatAnswer: String?) -> ImportBatchView? {
        guard !files.isEmpty else { return nil }

        // The global band each file's rows move into. offset[0] = 0 and each
        // later file starts one past the previous file's highest local row, so
        // no two files can ever collide on a global source row.
        let offsets = globalOffsets(files: files)

        var candidates: [ImportCandidate] = []
        var groupsByTrimmedName: [String: (first: Int, sourceRows: [Int])] = [:]
        var groupOrder: [String] = []
        var unparsed: [ImportUnparsedRow] = []
        var rawLines: [Int: String] = [:]
        var ambiguityByKey: [String: ImportAmbiguity] = [:]
        // RV.116: unsupported-column counts sum across the files of a whole-
        // export pick, exactly as the ambiguities' row counts do - the notice is
        // once per export, so the number must cover every file the user picked.
        var unsupportedByColumn: [String: Int] = [:]

        for (index, file) in files.enumerated() {
            let offset = offsets[index]
            let needsRedating = Self.needsDMYRedating(parse: file.parse,
                                                      answer: dateFormatAnswer)
            let datedCandidates = needsRedating ? file.parse.reDatingAsDMY().candidates
                                                : file.parse.candidates

            for candidate in datedCandidates {
                candidates.append(candidate.remappingSourceRow(by: offset))
            }

            // Union the file's own groups into the export's groups by NAME. A
            // name that appears in several files is ONE mapping question whose
            // lane carries every file's rows (RV.93 - the same-car rows from
            // fuel.csv and costs.csv must validate as one timeline).
            for group in file.parse.resolvedVehicleGroups {
                let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.isEmpty ? Self.blankGroupKey(group.name) : name
                let remapped = group.sourceRows.map { $0 + offset }
                if let existing = groupsByTrimmedName[key] {
                    groupsByTrimmedName[key] = (existing.first, existing.sourceRows + remapped)
                } else {
                    groupsByTrimmedName[key] = (groupOrder.count, remapped)
                    groupOrder.append(key)
                }
            }

            for row in file.parse.unparsed {
                unparsed.append(ImportUnparsedRow(row: row.row + offset, reason: row.reason))
            }

            for (localRow, line) in file.rawLines {
                rawLines[localRow + offset] = line
            }

            // F6 ambiguities summed across the files that carry them. Options
            // come from the first occurrence; rowCounts add, because the once
            // question (date format, out-of-scope income/reminders) counts the
            // whole export's rows, not one file's.
            for ambiguity in file.parse.ambiguities {
                let key = ambiguity.kind + "\u{0}" + ambiguity.options.joined(separator: "\u{0}")
                if let existing = ambiguityByKey[key] {
                    ambiguityByKey[key] = ImportAmbiguity(kind: existing.kind,
                                                          options: existing.options,
                                                          rowCount: existing.rowCount + ambiguity.rowCount)
                } else {
                    ambiguityByKey[key] = ambiguity
                }
            }

            for (column, count) in file.parse.unsupported ?? [:] {
                unsupportedByColumn[column, default: 0] += count
            }
        }

        let groups = groupOrder.compactMap { key -> ImportVehicleGroup? in
            guard let entry = groupsByTrimmedName[key] else { return nil }
            // A blank group keeps the empty name on the merged group too
            // (nothing is silently re-named); the union key is just the merge
            // identity.
            return ImportVehicleGroup(name: key.isEmpty ? "" : key,
                                      sourceRows: entry.sourceRows)
        }

        let mergedParse = ImportParseResponse(
            importId: files.first?.parse.importId ?? "batch",
            format: files.first?.parse.format ?? "unknown",
            scope: files.first?.parse.scope ?? "vehicle",
            candidates: candidates,
            unparsed: unparsed,
            ambiguities: Array(ambiguityByKey.values),
            vehicleGroups: groups,
            unsupported: unsupportedByColumn.isEmpty ? nil : unsupportedByColumn)

        return ImportBatchView(parse: mergedParse, rawLinesByRow: rawLines)
    }

    // MARK: - Offsets

    /// The global-band start for each file, in pick order. File 0 owns rows
    /// 1...max0; file i owns max(prev)+1 ... max(prev)+maxi, so every file's
    /// rows land in a disjoint, ascending range. The extent includes raw-line
    /// keys so a file whose raw lines outrun its candidates (unparsed tails)
    /// still cannot collide with the next file.
    static func globalOffsets(files: [ImportParsedFile]) -> [Int] {
        let extents = files.map(Self.localRowExtent(_:))
        var offsets: [Int] = []
        var cursor = 0
        for extent in extents {
            offsets.append(cursor)
            cursor += extent
        }
        return offsets
    }

    /// The file's highest local row across candidates, unparsed rows and raw
    /// lines; at least 1 so a following file always gets a non-zero offset.
    private static func localRowExtent(_ file: ImportParsedFile) -> Int {
        let candidateMax = file.parse.candidates.map(\.sourceRow).max() ?? 0
        let unparsedMax = file.parse.unparsed.map(\.row).max() ?? 0
        let rawMax = file.rawLines.keys.max() ?? 0
        return max(1, candidateMax, unparsedMax, rawMax)
    }

    /// Whether a file's dates need the D/M flip under the user's answer: the
    /// file must itself have reported the `dateFormat` ambiguity, and the
    /// answer must be its second option. A file that PROVED its dates (RV.85)
    /// never flips, no matter what another file's ambiguity says.
    private static func needsDMYRedating(parse: ImportParseResponse,
                                         answer: String?) -> Bool {
        guard let answer else { return false }
        guard let ambiguity = parse.ambiguities.first(where: { $0.kind == "dateFormat" }) else {
            return false
        }
        return ambiguity.options.count == 2 && answer == ambiguity.options[1]
    }

    /// The identity for a group whose name is blank after trimming: the raw
    /// name (which may differ from another file's blank by nothing - blank
    /// names union under one key, exactly as the parser groups them within a
    /// file). Distinct blank-looking names cannot arise (the name is trimmed to
    /// emptiness or not), so a fixed sentinel is the honest union key.
    private static func blankGroupKey(_ name: String) -> String {
        name.isEmpty ? "\u{0}blank" : name
    }
}

extension ImportCandidate {
    /// A copy whose `sourceRow` has moved into a merged batch's global band.
    fileprivate func remappingSourceRow(by offset: Int) -> ImportCandidate {
        ImportCandidate(entityType: entityType, date: date, odometer: odometer,
                        volumeL: volumeL, unitPrice: unitPrice, money: money,
                        fuelKind: fuelKind, isFull: isFull,
                        tankLevelAfterPct: tankLevelAfterPct, note: note,
                        vehicleName: vehicleName, provenance: provenance,
                        sourceRow: sourceRow + offset, items: items,
                        category: category, title: title)
    }
}
