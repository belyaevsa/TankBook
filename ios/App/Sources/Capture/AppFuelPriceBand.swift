import Foundation
import TankbookCore

// MARK: - The band provider the capture pipeline injects

// Builds the provider for the resolution ladder's steps 3 and 4
// (docs/SCHEMA.md -> Fuel price bands). The curated pack always applies; the
// user's own price history applies when a vehicle is known, so a capture
// against an existing car prefers the user's own grade and stations (step 3)
// over the national band (step 4). A nil pack (bundle missing) degrades to no
// provider, and the ladder then abstains rather than guesses - the honest
// fallback (hard rule 13). Local-only, no network (hard rule 1).
@MainActor
enum AppFuelPriceBand {
    static func provider(vehicleId: UUID?) -> (any FuelPriceBandProvider)? {
        guard let pack = try? FuelPriceBandStore.bundledPack() else { return nil }
        let history = vehicleId.flatMap { id -> FillUpHistory? in
            guard let repository = try? AppStore.repository(),
                  let fillUps = try? repository.liveFillUps(forVehicle: id) else { return nil }
            return FillUpHistory(fillUps: fillUps)
        }
        return DefaultFuelPriceBandProvider(pack: pack, history: history)
    }
}
