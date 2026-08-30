import Foundation
import Testing
@testable import TankbookCore

// P2.3b + P2.3c: a car accepts a set of fuel kinds, and `Vehicle.fuelKinds` is
// a suggestion, not a limit (hard rule 13). The distinctions that matter are
// NOT symmetric (docs/DESIGN.md, the fuel-kind rule): petrol grades share a
// tank and are a real driver's choice; LPG/CNG/E85 alongside petrol are real
// bi-fuel and flex-fuel cars; diesel with petrol is unusual - almost certainly
// a misconfigured car, but P2.3c downgraded it from "rejected" to "discouraged
// but savable", so `isRealisticCombination` is now a DISCOURAGEMENT signal and
// `offeredKinds(for:)` widens the Confirm fuel row to every petrol grade for a
// petrol car. Nothing the user records may be refused.
@Suite("Fuel kind combinations are realistic (P2.3b) and offered, never limited (P2.3c)")
struct FuelKindCombinationTests {

    // The discouraged direction: diesel + any petrol grade is unusual.
    @Test func dieselWithAnyPetrolGradeIsUnusual() {
        for grade in [FuelKind.petrol92, .petrol95, .petrol98, .petrol100] {
            #expect(!FuelKind.isRealisticCombination([.diesel, grade]),
                    "diesel with \(grade) is an unusual car")
        }
    }

    // The converse, so a signal inverted the wrong way cannot pass: the pair
    // stays unusual whichever order the set is built in.
    @Test func petrolWithDieselIsUnusual() {
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

    // MARK: - The offer set is likely, never a limit (P2.3c)

    // A petrol car is offered ALL petrol grades, whatever single grade it is
    // configured for - a 95 car is routinely filled with 92 or 100 (the
    // product-owner correction: "one car can fillup 95, 92 and 100").
    @Test func petrolCarIsOfferedEveryPetrolGrade() {
        #expect(FuelKind.offeredKinds(for: [.petrol95]) == [.petrol92, .petrol95, .petrol98, .petrol100])
        #expect(FuelKind.offeredKinds(for: [.petrol92]) == [.petrol92, .petrol95, .petrol98, .petrol100])
        #expect(FuelKind.offeredKinds(for: [.petrol98, .petrol100]) == [.petrol92, .petrol95, .petrol98, .petrol100])
    }

    // A petrol car keeps its non-petrol kinds beside the widened petrol set -
    // a 95 + LPG car is offered 92/95/98/100 plus LPG, and NOT diesel.
    @Test func petrolCarKeepsItsOtherKinds() {
        #expect(FuelKind.offeredKinds(for: [.petrol95, .lpg]) == [.petrol92, .petrol95, .petrol98, .petrol100, .lpg])
        #expect(FuelKind.offeredKinds(for: [.petrol92, .cng]) == [.petrol92, .petrol95, .petrol98, .petrol100, .cng])
    }

    // A car with no petrol grade is offered its own kinds and nothing petrol -
    // a diesel car is never offered a petrol chip (but remains correctable).
    @Test func nonPetrolCarIsOfferedItsOwnKindsOnly() {
        #expect(FuelKind.offeredKinds(for: [.diesel]) == [.diesel])
        #expect(FuelKind.offeredKinds(for: [.diesel, .lpg]) == [.diesel, .lpg])
        #expect(FuelKind.offeredKinds(for: [.electricity]) == [.electricity])
        #expect(FuelKind.offeredKinds(for: [.lpg]) == [.lpg])
    }

    // The offer set always preserves the canonical case order, so the row's
    // chips read diesel < petrol grades < gas kinds < electricity.
    @Test func offerSetPreservesCanonicalOrder() {
        let offered = FuelKind.offeredKinds(for: [.lpg, .petrol98])
        let expected = FuelKind.allCases.filter {
            [.petrol92, .petrol95, .petrol98, .petrol100, .lpg].contains($0)
        }
        #expect(offered == expected)
        #expect(offered.firstIndex(of: .petrol92)! < offered.firstIndex(of: .petrol98)!)
        #expect(offered.firstIndex(of: .petrol98)! < offered.firstIndex(of: .lpg)!)
    }
}
