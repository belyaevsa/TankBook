import Foundation

// RV.86: the lane routing for a multi-car import. The parser exposes the
// source file's distinct vehicles (`ImportVehicleGroup`); the wizard asks which
// car each group lands in and resolves that into one `ImportLane` per group the
// user decided to bring in. Everything below is pure - it commits nothing, and
// the ONE write stays the commit the flow performs afterwards (hard rule 9).

/// One decided lane of a multi-car import (RV.86): the source file's rows that
/// belong to one source car (`sourceRows`, the wire's 1-based data-row numbers
/// of the group's candidates) and the destination vehicle the user chose for
/// them. A group the user left out has no lane. Two lanes may share a
/// destination vehicle - the user decides; the wizard never forbids a merge.
public struct ImportLane: Equatable, Sendable {
    public let sourceRows: [Int]
    public let vehicle: Vehicle

    public init(sourceRows: [Int], vehicle: Vehicle) {
        self.sourceRows = sourceRows
        self.vehicle = vehicle
    }
}

extension ImportReviewClassifier {
    /// RV.86: partition a multi-car file's candidates lane by lane. Each lane's
    /// candidates convert and validate against THAT lane's destination vehicle
    /// and the destination car's OWN existing entries
    /// (`existingEntriesByVehicle`), so two cars' odometers can never be
    /// validated against each other: a merge flags an odometer that breaks the
    /// DESTINATION car's order, never the other car's. The ready/review rows'
    /// fills carry each lane's vehicle id, so the single commit (`commitImport`,
    /// which groups by vehicle) writes every lane to its own car.
    ///
    /// Unparsed rows cannot be attributed to a car (the parser could not read
    /// their row, so it could not read their vehicle name) and are appended
    /// once, outside any lane - nothing is silently dropped (hard rule 8).
    public static func partitionByLanes(candidates: [ImportCandidate],
                                        lanes: [ImportLane],
                                        existingEntriesByVehicle: [UUID: [any Entry]] = [:],
                                        existingStations: [Station] = [],
                                        unparsed: [ImportUnparsedRow],
                                        rawLinesByRow: [Int: String],
                                        source: String) -> (ready: [FillUp], review: [ImportReviewRow]) {
        var ready: [FillUp] = []
        var review: [ImportReviewRow] = []
        for lane in lanes {
            let wanted = Set(lane.sourceRows)
            let laneCandidates = candidates.filter { wanted.contains($0.sourceRow) }
            let existing = existingEntriesByVehicle[lane.vehicle.id] ?? []
            let (laneReady, laneReview) = partition(candidates: laneCandidates,
                                                    unparsed: [],
                                                    rawLinesByRow: rawLinesByRow,
                                                    vehicle: lane.vehicle,
                                                    source: source,
                                                    existingEntries: existing,
                                                    existingStations: existingStations)
            ready += laneReady
            review += laneReview
        }
        for row in unparsed {
            review.append(ImportReviewRow(sourceRow: row.row,
                                          kind: .unparsed(reason: row.reason),
                                          fill: nil,
                                          rawLine: rawLinesByRow[row.row]))
        }
        review.sort { $0.sourceRow < $1.sourceRow }
        return (ready, review)
    }
}
