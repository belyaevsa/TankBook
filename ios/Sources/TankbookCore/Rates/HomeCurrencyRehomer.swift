import Foundation

/// The pass a home-currency change runs over a car's rate-pending entries
/// (docs/SCHEMA.md -> Money).
///
/// Two triggers call it and must stay one implementation: RV.140's
/// Vehicle-detail save (the currency is typed) and RV.143's sync apply (the
/// currency arrives through S9's field-level merge). `MoneyBackfillService` is
/// the production conformer; the protocol is the seam a test uses to assert the
/// sync trigger invokes the same pass rather than a second copy of it.
public protocol HomeCurrencyRehomer: Sendable {
    @discardableResult
    func rehome(_ repository: TankbookRepository, vehicleID: UUID,
                to newHome: CurrencyCode) throws -> MoneyBackfillService.Result
}
