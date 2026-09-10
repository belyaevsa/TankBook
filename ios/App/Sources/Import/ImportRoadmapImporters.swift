import Foundation
import TankbookCore

extension ImportSourceView {
    /// Every importer the product has committed to, shipped or not
    /// (`docs/VISION.md` -> the importers, `docs/JOURNEYS.md` -> J2). A name
    /// leaves the "Not yet" row by appearing in the server's format list, never
    /// by being deleted from here - that is what keeps the two in step.
    static var roadmapImporters: [String] {
        ["Fuelio", "Drivvo", "Fuelly", "Spritmonitor", "CarScope", "My Fuel Manager"]
    }

    /// The roadmap names, minus whatever the server already parses. Matched on
    /// the display name the format list renders, case- and space-insensitively,
    /// so a rename on either side cannot resurrect a shipped importer here.
    var notYetNames: [String] {
        let shipped = Set(model.formats.map(Self.normalizedFormatName))
        return Self.roadmapImporters.filter { !shipped.contains(Self.normalizedFormatName($0)) }
    }

    static func normalizedFormatName(_ format: ImportFormat) -> String {
        normalizedFormatName(format.displayName)
    }

    static func normalizedFormatName(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace }
    }
}
