import Foundation

/// What a car accepts / what a fill-up holds (docs/SCHEMA.md, Vehicle.fuelKinds).
public enum FuelKind: String, Codable, Sendable, CaseIterable {
    case diesel
    case petrol92
    case petrol95
    case petrol98
    case petrol100
    case lpg
    case cng
    case e85
    case electricity
}

extension FuelKind {
    /// The petrol grades. They share one tank and are a real driver's choice -
    /// a 92/95 car can burn either, so a driver logging against it is choosing
    /// between grades, not switching fuels (docs/DESIGN.md).
    public var isPetrolGrade: Bool {
        switch self {
        case .petrol92, .petrol95, .petrol98, .petrol100: return true
        case .diesel, .lpg, .cng, .e85, .electricity: return false
        }
    }

    /// Whether this set of kinds is a TYPICAL car. Diesel and a petrol grade
    /// are an unusual fit - a driver who selects both is almost certainly
    /// misconfigured - while petrol grades share a tank and LPG/CNG/E85 beside
    /// petrol are real bi-fuel and flex-fuel fits (docs/DESIGN.md).
    /// P2.3c (2026-08-30): this is a DISCOURAGEMENT signal, never a blocker.
    /// The pills still let diesel + petrol be saved, because a wrong car
    /// configuration is correctable and nothing the user records may be refused
    /// (hard rule 13).
    public static func isRealisticCombination(_ kinds: Set<FuelKind>) -> Bool {
        let hasDiesel = kinds.contains(.diesel)
        let hasPetrol = kinds.contains { $0.isPetrolGrade }
        return !(hasDiesel && hasPetrol)
    }

    /// The LIKELY offer set for the Confirm fuel row (P2.3c, 2026-08-30).
    /// `Vehicle.fuelKinds` is a suggestion, not a limit (hard rule 13): petrol
    /// grades share a tank, so a car configured for 95 is routinely filled with
    /// 92 or 100. A car whose kinds include any petrol grade is therefore
    /// offered ALL petrol grades plus its other kinds; a car without a petrol
    /// grade (diesel, EV, gas-only) is offered its own kinds. This is what the
    /// row shows as chips - every other kind stays reachable through the
    /// correction affordance, so nothing is ever blocked.
    public static func offeredKinds(for kinds: Set<FuelKind>) -> [FuelKind] {
        var result = kinds
        if kinds.contains(where: { $0.isPetrolGrade }) {
            result.formUnion([.petrol92, .petrol95, .petrol98, .petrol100])
        }
        return allCases.filter { result.contains($0) }
    }
}

/// Vehicle drivetrain (docs/SCHEMA.md, Vehicle.powertrain).
public enum Powertrain: String, Codable, Sendable, CaseIterable {
    case ice
    case ev
    case hybrid
    case phev
}

/// Charging session type (docs/SCHEMA.md, ChargeSession.chargeType).
public enum ChargeType: String, Codable, Sendable, CaseIterable {
    case acHome
    case acPublic
    case dcPublic
}

/// Service invoice line-item category (docs/SCHEMA.md, ServiceItem.category).
public enum ServiceCategory: Codable, Sendable, Equatable, Hashable {
    case oil
    case brakes
    case tires
    case battery
    case filters
    case inspection
    case repair
    case parts
    case wash
    case other(String)
}

/// Expense category for money NOT tied to work done on the car
/// (docs/SCHEMA.md, Expense.category).
public enum ExpenseCategory: Codable, Sendable, Equatable, Hashable {
    case insurance
    case tax
    case parking
    case toll
    case fine
    case accessory
    case parts
    case other(String)
}

/// How an entry was created (docs/SCHEMA.md, EntryCommon.provenance).
public enum Provenance: Codable, Sendable, Equatable, Hashable {
    case receiptScan
    case pumpPhoto
    case fiscalQR
    case screenshot
    case manual
    case `import`(source: String)
}

/// Timeline-validation state of an entry (docs/SCHEMA.md, Validation).
public enum ConflictState: Codable, Sendable, Equatable, Hashable {
    case none
    case flagged(kind: ConflictKind, detectedAt: Date)

    /// The kind of timeline violation that flagged an entry.
    public enum ConflictKind: String, Codable, Sendable, CaseIterable {
        case order
        case pace
    }
}

/// Result of the pump-card cross-check `volumeL x unitPrice ~= money.amount`
/// (docs/SCHEMA.md, FillUp.crossCheck).
public enum CrossCheckState: Codable, Sendable, Equatable, Hashable {
    case verified
    case mismatch(field: FieldRef)
    case notApplicable
}

/// A field that can be OCR-extracted and verified (docs/SCHEMA.md, FieldRef).
public enum FieldRef: Codable, Sendable, Equatable, Hashable {
    case total
    case volume
    case unitPrice
    case date
    case station
    case fuelKind
    case energy
    case currency
    case vendor
    case lineItem(Int)
}

/// Reminder category: service work, insurance, or custom
/// (docs/SCHEMA.md, Reminder.category).
public enum ReminderCategory: Codable, Sendable, Equatable, Hashable {
    case oil
    case brakes
    case tires
    case battery
    case filters
    case inspection
    case repair
    case parts
    case wash
    case insurance
    case custom
    case other(String)
}

/// Reminder lifecycle state (docs/SCHEMA.md, Reminder.status).
public enum ReminderStatus: Codable, Sendable, Equatable, Hashable {
    case scheduled
    case attention
    case done(entryId: UUID?)
    case dismissed(reason: String?)
}

/// Attachment content kind (docs/SCHEMA.md, Attachment.kind).
public enum AttachmentKind: String, Codable, Sendable, CaseIterable {
    case photo
    case pdf
}

// Vehicle units (docs/SCHEMA.md, Vehicle.units).

public enum DistanceUnit: String, Codable, Sendable, CaseIterable {
    case km
    case mi
}

public enum VolumeUnit: String, Codable, Sendable, CaseIterable {
    case l
    case galUS
    case galUK
}

public enum ConsumptionUnit: String, Codable, Sendable, CaseIterable {
    case lPer100
    case mpgUS
    case mpgUK
    case kmPerL
}

public enum EnergyUnit: String, Codable, Sendable, CaseIterable {
    case kWhPer100
    case miPerKWh
}
