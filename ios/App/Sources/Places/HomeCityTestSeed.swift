#if DEBUG
import Foundation
import TankbookCore

/// The home-city question posed for UI tests and screenshots: a car (the AdBlue
/// seed's diesel Passat) whose first scanned receipt named Tallinn - or named no
/// city at all.
enum HomeCityTestSeed {
    static var actions: [(argument: String, seed: (TankbookRepository) -> Void)] { [
        ("-seedHomeCityQuestion", { seed($0, suggestion: "Tallinn") }),
        ("-seedHomeCityQuestionNoCity", { seed($0, suggestion: nil) }),
    ] }

    private static func seed(_ repository: TankbookRepository, suggestion: String?) {
        P114HomeTestSeed.seedOne(repository)
        guard let vehicle = try? repository.liveVehicles().first else { return }
        let city = suggestion.flatMap { CityDictionary(pack: .bundled).cities(named: $0).first }
        HomeCityAsk.set(.pending(suggestedCityId: city?.id), for: vehicle.id)
    }
}
#endif
