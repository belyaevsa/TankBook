import Foundation
import Testing
@testable import TankbookCore

// PJ.3: the RU locale defaults a new car to 92 + 95 alongside the RUB guess
// (docs/JOURNEYS.md J1 -> "RU locale defaults to ₽ + RU fuel grades"). A
// locale guess is a default input, never a fact (hard rule 13) - the Add-car
// form offers it and the user edits it - but the RU default must be pinned:
// it is the one CIS-specific value a new install ships with.
@Suite("Vehicle defaults by locale (PJ.3)")
struct VehicleDefaultsTests {

    @Test func ruLocaleDefaultsTo92And95() {
        let ru = Locale(identifier: "ru_RU")
        #expect(VehicleDefaults.defaultFuelKinds(for: ru) == [.petrol92, .petrol95])
    }

    @Test func nonRuLocalesDefaultTo95Alone() {
        let us = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        let kz = Locale(identifier: "ru_KZ")
        #expect(VehicleDefaults.defaultFuelKinds(for: us) == [.petrol95])
        #expect(VehicleDefaults.defaultFuelKinds(for: de) == [.petrol95])
        #expect(VehicleDefaults.defaultFuelKinds(for: kz) == [.petrol95])
    }

    /// The two defaults are the same decision: the RU locale guesses RUB AND
    /// the two common grades - one locale, one consistent suggestion.
    @Test func ruLocaleGuessesRubAlongsideTheGrades() {
        let ru = Locale(identifier: "ru_RU")
        #expect(LocaleCurrency.defaultCurrency(for: ru).rawValue == "RUB")
    }
}
