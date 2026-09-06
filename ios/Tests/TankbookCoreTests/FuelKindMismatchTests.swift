import Foundation
import Testing
@testable import TankbookCore

// RV.71 (2026-09-05, product owner): a scanned receipt whose fuel kind is not
// among the car's declared kinds must warn on the confirm screen at scan
// moment - a diesel receipt logged against a petrol car otherwise saves without
// a word, and fuel kind feeds the consumption maths (hard rule 2: stats are
// derived, so a bad kind propagates on every recompute). The comparison is
// decided: warn when the scanned kind is not in `offeredKinds(for:)` - the same
// offer set the confirm chips render - with two carve-outs: an empty
// `vehicleFuelKinds` never warns, and `electricity` never warns in either
// direction. The must-NOT-warn rows are as load-bearing as the must-warn ones:
// a rule that fires on everything is not a rule (docs/ERRORS.md -> Confirm).
@Suite("RV.71: a scanned receipt's fuel kind warns only when the car does not offer it")
struct FuelKindMismatchTests {

    // MARK: - The worked cases (must warn)

    // diesel receipt against a petrol-only car.
    @Test func dieselReceiptAgainstPetrolCarWarns() {
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .diesel,
                                                 vehicleFuelKinds: [.petrol95]))
    }

    // petrol receipt against a diesel-only car.
    @Test func petrolReceiptAgainstDieselCarWarns() {
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .petrol95,
                                                 vehicleFuelKinds: [.diesel]))
    }

    // LPG against a car declaring neither LPG nor CNG.
    @Test func lpgReceiptAgainstPetrolCarWarns() {
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .lpg,
                                                 vehicleFuelKinds: [.petrol95]))
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .cng,
                                                 vehicleFuelKinds: [.petrol95]))
    }

    // A scanned kind the car simply does not take: petrol on an LPG-only car.
    @Test func liquidAgainstUnrelatedDeclaredKindsWarns() {
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .petrol95,
                                                 vehicleFuelKinds: [.lpg]))
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .diesel,
                                                 vehicleFuelKinds: [.lpg, .cng]))
    }

    // MARK: - The worked cases (must NOT warn)

    // 95 receipt on a 92+95 car: the grade case, asserted positive.
    @Test func gradeOnCarThatDeclaresItDoesNotWarn() {
        #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: .petrol95,
                                                  vehicleFuelKinds: [.petrol92, .petrol95]))
    }

    // 92 receipt on a 95-only car: `offeredKinds` opens ALL petrol grades to a
    // petrol car, because they share a tank - a 92/95/98/100 choice is a
    // driver's choice, never a fuel switch. This is the case that would annoy
    // every user daily if the comparison used `vehicleFuelKinds` directly.
    @Test func gradeOnCarThatSharesTheTankDoesNotWarn() {
        for receipt in [FuelKind.petrol92, .petrol95, .petrol98, .petrol100] {
            #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: receipt,
                                                      vehicleFuelKinds: [.petrol95]),
                    "a \(receipt) receipt on a 95 car is a grade choice, never a warn")
            #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: receipt,
                                                      vehicleFuelKinds: [.petrol92, .petrol95, .petrol98]))
        }
    }

    // The petrol-car offer set never changes when the car also declares a gas
    // kind: 98 on a 95+LPG car stays a grade choice.
    @Test func gradeOnBiFuelPetrolCarDoesNotWarn() {
        #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: .petrol98,
                                                  vehicleFuelKinds: [.petrol95, .lpg]))
    }

    // Empty `vehicleFuelKinds` never warns, whatever the receipt says - a car
    // that has declared nothing cannot disagree with anything, and most cars
    // start in that state.
    @Test func emptyFuelKindsNeverWarn() {
        for receipt in FuelKind.allCases {
            #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: receipt, vehicleFuelKinds: []),
                    "an undeclared car must not warn on a \(receipt) receipt")
        }
    }

    // A nil scanned kind (the extractor resolved none) never warns.
    @Test func unresolvedReceiptKindNeverWarns() {
        #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: nil,
                                                  vehicleFuelKinds: [.petrol95]))
        #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: nil, vehicleFuelKinds: []))
    }

    // MARK: - Carve-out 2: electricity never warns, in either direction

    // A receipt that reads electricity never warns, whatever the car declares -
    // a charge session is a different entry path.
    @Test func electricityReceiptNeverWarns() {
        let cars: [[FuelKind]] = [[.petrol95], [.diesel], [.petrol95, .electricity], [.lpg], []]
        for car in cars {
            #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: .electricity,
                                                      vehicleFuelKinds: Set(car)),
                    "an electricity receipt must not warn against \(car)")
        }
    }

    // A car whose only declared kind is electricity (an EV) never warns on a
    // liquid scan - the same carve-out in the other direction.
    @Test func evCarNeverWarnsOnALiquidReceipt() {
        #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: .diesel,
                                                  vehicleFuelKinds: [.electricity]))
        #expect(!FuelKind.shouldWarnFuelMismatch(scannedKind: .petrol95,
                                                  vehicleFuelKinds: [.electricity]))
    }

    // A hybrid's electricity declaration does not silence a REAL liquid
    // mismatch: diesel against a petrol+electricity PHEV still warns.
    @Test func hybridElectricitySideDoesNotSilenceALiquidMismatch() {
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .diesel,
                                                 vehicleFuelKinds: [.petrol95, .electricity]))
        #expect(FuelKind.shouldWarnFuelMismatch(scannedKind: .lpg,
                                                 vehicleFuelKinds: [.petrol95, .electricity]))
    }
}
