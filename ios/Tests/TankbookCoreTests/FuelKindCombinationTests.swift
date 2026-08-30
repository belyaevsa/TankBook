import Foundation
import Testing
@testable import TankbookCore

// P2.3b: a car accepts a set of fuel kinds, and the set has to be one a real
// car can hold. The distinctions that matter are NOT symmetric
// (docs/DESIGN.md, the fuel-kind rule): petrol grades share a tank and are a
// real driver's choice; LPG/CNG/E85 alongside petrol are real bi-fuel and
// flex-fuel cars; diesel with petrol is not. The rule guards INPUT exactly as
// DESIGN.md guards display - the combination the Confirm fuel row may offer is
// the one AddVehicle may save.
@Suite("Fuel kind combinations are realistic (P2.3b)")
struct FuelKindCombinationTests {

    // The forbidden direction: diesel + any petrol grade.
    @Test func dieselWithAnyPetrolGradeIsImpossible() {
        for grade in [FuelKind.petrol92, .petrol95, .petrol98, .petrol100] {
            #expect(!FuelKind.isRealisticCombination([.diesel, grade]),
                    "diesel with \(grade) is not a car")
        }
    }

    // The converse: a petrol car is never offered diesel, which is the trap
    // that passes a filter inverted the wrong way.
    @Test func petrolWithDieselIsImpossible() {
        #expect(!FuelKind.isRealisticCombination([.petrol95, .diesel]))
        #expect(!FuelKind.isRealisticCombination([.petrol92, .petrol98, .diesel]))
    }

    // Petrol grades share a tank: any mix is a real choice.
    @Test func petrolGradesShareATank() {
        #expect(FuelKind.isRealisticCombination([.petrol92, .petrol95]))
        #expect(FuelKind.isRealisticCombination([.petrol95, .petrol98, .petrol100]))
        #expect(FuelKind.isRealisticCombination([.petrol92, .petrol95, .petrol98, .petrol100]))
    }

    // LPG/CNG/E85 beside petrol: real bi-fuel and flex-fuel cars.
    @Test func petrolWithGasKindsIsReal() {
        #expect(FuelKind.isRealisticCombination([.petrol95, .lpg]))
        #expect(FuelKind.isRealisticCombination([.petrol92, .petrol95, .lpg]))
        #expect(FuelKind.isRealisticCombination([.petrol95, .cng]))
        #expect(FuelKind.isRealisticCombination([.petrol95, .e85]))
    }

    // A single kind, whatever it is, is always a real car.
    @Test func singleKindIsAlwaysReal() {
        for kind in FuelKind.allCases {
            #expect(FuelKind.isRealisticCombination([kind]),
                    "a \(kind)-only car is a real car")
        }
    }

    // The plural cases that exist: a PHEV takes petrol + electricity; a
    // diesel-only car is a car; electricity alone is an EV.
    @Test func powertrainShapedCombinationsAreReal() {
        #expect(FuelKind.isRealisticCombination([.petrol95, .electricity]))
        #expect(FuelKind.isRealisticCombination([.diesel, .electricity]))
        #expect(FuelKind.isRealisticCombination([.diesel]))
        #expect(FuelKind.isRealisticCombination([.electricity]))
        #expect(FuelKind.isRealisticCombination([.petrol95, .lpg, .electricity]))
    }

    // The empty set is vacuously fine (the form starts from it).
    @Test func emptySetIsAllowed() {
        #expect(FuelKind.isRealisticCombination([]))
    }

    // The rule is about diesel vs petrol, not about diesel itself: LPG/CNG
    // beside diesel are conversions that exist.
    @Test func dieselWithGasKindsIsReal() {
        #expect(FuelKind.isRealisticCombination([.diesel, .lpg]))
        #expect(FuelKind.isRealisticCombination([.diesel, .cng]))
    }
}
