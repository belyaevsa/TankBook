import Foundation
import CoreGraphics

/// ID of an `Attachment`. `UUID` under the hood; named to match docs/SCHEMA.md
/// (`[AttachmentID]`, `photo: AttachmentID?`).
public typealias AttachmentID = UUID

/// Every persisted entity shares this envelope (docs/SCHEMA.md, Identifiers &
/// sync envelope).
public protocol Entity {
    var id: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

/// Common envelope of `FillUp`, `ChargeSession`, `ServiceRecord` and `Expense`
/// (docs/SCHEMA.md, Entry). The Log renders their union ordered by `date`.
public protocol Entry: Entity {
    var vehicleId: UUID { get set }
    var date: Date { get set }
    var odometer: Int? { get set }
    var money: Money? { get set }
    var note: String? { get set }
    var attachments: [AttachmentID] { get set }
    var provenance: Provenance { get set }
    var conflict: ConflictState { get set }
    var purchaseGroupId: UUID? { get set }
}

/// A vehicle (docs/SCHEMA.md, Vehicle).
public struct Vehicle: Entity, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var name: String
    public var make: String?
    public var model: String?
    public var year: Int?
    public var plate: String?
    public var powertrain: Powertrain
    public var fuelKinds: [FuelKind]
    public var tankCapacityL: Double?
    public var batteryCapacityKWh: Double?
    public var homeCurrency: CurrencyCode
    public var units: Units
    public var photo: AttachmentID?
    public var archived: Bool = false
    public var paceLimitKmPerDay: Double = 1500

    /// Units of measure for a vehicle (docs/SCHEMA.md, Vehicle.units).
    public struct Units: Codable, Sendable, Equatable {
        public var distance: DistanceUnit
        public var volume: VolumeUnit
        public var consumption: ConsumptionUnit
        public var energy: EnergyUnit

        public init(distance: DistanceUnit, volume: VolumeUnit,
                    consumption: ConsumptionUnit, energy: EnergyUnit) {
            self.distance = distance
            self.volume = volume
            self.consumption = consumption
            self.energy = energy
        }
    }
}

/// A fuel fill-up (docs/SCHEMA.md, FillUp).
public struct FillUp: Entry, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var date: Date
    public var odometer: Int?
    public var money: Money?
    public var note: String?
    public var attachments: [AttachmentID]
    public var provenance: Provenance
    public var conflict: ConflictState
    public var purchaseGroupId: UUID?
    public var volumeL: Double
    public var unitPrice: Decimal?
    public var fuelKind: FuelKind
    public var fuelGrade: String?
    public var isFull: Bool
    public var tankLevelAfterPct: Double?
    public var stationId: UUID?
    public var crossCheck: CrossCheckState
    public var extraction: ExtractionMeta?
}

/// A charging session (docs/SCHEMA.md, ChargeSession).
public struct ChargeSession: Entry, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var date: Date
    public var odometer: Int?
    public var money: Money?
    public var note: String?
    public var attachments: [AttachmentID]
    public var provenance: Provenance
    public var conflict: ConflictState
    public var purchaseGroupId: UUID?
    public var energyKWh: Double
    public var unitPrice: Decimal?
    public var chargeType: ChargeType
    public var provider: String?
    public var tariffId: UUID?
    public var durationMin: Int?
    public var socStartPct: Double?
    public var socEndPct: Double?
    public var extraction: ExtractionMeta?
}

/// Work DONE to the car (docs/SCHEMA.md, ServiceRecord).
public struct ServiceRecord: Entry, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var date: Date
    public var odometer: Int?
    public var money: Money?
    public var note: String?
    public var attachments: [AttachmentID]
    public var provenance: Provenance
    public var conflict: ConflictState
    public var purchaseGroupId: UUID?
    public var vendor: String?
    public var items: [ServiceItem]
    public var usedParts: [UUID]
    public var tireSetId: UUID?
    public var proposedReminderId: UUID?
}

/// An invoice line item (docs/SCHEMA.md, ServiceItem).
public struct ServiceItem: Codable, Sendable, Equatable {
    public var title: String
    public var category: ServiceCategory
    public var cost: Money?
    public var partNumber: String?
    public var lifetime: Lifetime?

    /// Optional service life that drives the next-reminder suggestion.
    public struct Lifetime: Codable, Sendable, Equatable {
        public var km: Int?
        public var months: Int?

        public init(km: Int?, months: Int?) {
            self.km = km
            self.months = months
        }
    }
}

/// Money NOT tied to work done on the car (docs/SCHEMA.md, Expense).
public struct Expense: Entry, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var date: Date
    public var odometer: Int?
    public var money: Money?
    public var note: String?
    public var attachments: [AttachmentID]
    public var provenance: Provenance
    public var conflict: ConflictState
    public var purchaseGroupId: UUID?
    public var category: ExpenseCategory
    public var title: String
    public var recurrence: RecurrenceRule?
    public var installedInServiceId: UUID?
}

/// Recurrence for recurring expenses (e.g. yearly insurance). Judgement call:
/// SCHEMA.md names the type (`recurrence: RecurrenceRule?`) but leaves its
/// fields open - `everyMonths` plus the anchor date is the minimal shape that
/// covers the documented yearly-insurance example.
public struct RecurrenceRule: Codable, Sendable, Equatable {
    public var everyMonths: Int
    public var anchorDate: Date?

    public init(everyMonths: Int, anchorDate: Date?) {
        self.everyMonths = everyMonths
        self.anchorDate = anchorDate
    }
}

/// A seasonal tire set (docs/SCHEMA.md, TireSet).
public struct TireSet: Entity, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var name: String
    public var purchaseExpenseId: UUID?
}

/// A service reminder (docs/SCHEMA.md, Reminder).
public struct Reminder: Entity, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var title: String
    public var category: ReminderCategory
    public var dueDate: Date?
    public var dueOdometer: Int?
    public var recurrence: Recurrence?
    public var sourceEntryId: UUID?
    public var status: ReminderStatus

    /// Self-scheduling recurrence: on completion the next occurrence is created
    /// anchored at the COMPLETION date/odometer (docs/SCHEMA.md, Reminder).
    public struct Recurrence: Codable, Sendable, Equatable {
        public var everyKm: Int?
        public var everyMonths: Int?

        public init(everyKm: Int?, everyMonths: Int?) {
            self.everyKm = everyKm
            self.everyMonths = everyMonths
        }
    }
}

/// A gas station / charger location (docs/SCHEMA.md, Station).
public struct Station: Entity, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var name: String
    public var brand: String?
    public var location: GeoCoordinate?
    public var favorite: Bool
    public var defaults: Defaults
    public var lastUsedAt: Date?

    /// Pre-fill smart defaults for the next visit (docs/SCHEMA.md, Station.defaults).
    public struct Defaults: Codable, Sendable, Equatable {
        public var fuelKind: FuelKind?
        public var fuelGrade: String?

        public init(fuelKind: FuelKind?, fuelGrade: String?) {
            self.fuelKind = fuelKind
            self.fuelGrade = fuelGrade
        }
    }
}

/// A geographic point. Stands in for `CLLocationCoordinate2D` so the domain
/// stays pure and Codable (docs/SCHEMA.md spells `location: CLLocationCoordinate2D?`).
public struct GeoCoordinate: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A home/public charging tariff (docs/SCHEMA.md, Tariff).
public struct Tariff: Entity, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID?
    public var name: String
    public var pricePerKWh: Decimal
    public var currency: CurrencyCode
    public var validFrom: Date
}

/// A captured receipt/PDF (docs/SCHEMA.md, Attachment).
public struct Attachment: Entity, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var kind: AttachmentKind
    public var file: LocalFileRef
    public var extractedTimestamp: Date?
    public var ocrText: String?
}

/// A local file reference, synced/backed up as a content-addressed blob
/// (sha256 - docs/SCHEMA.md, Attachment.file). Judgement call: SCHEMA.md names
/// `LocalFileRef` but leaves its fields open - the blob hash plus the local
/// relative path is the minimal shape implied by the blob pipeline.
public struct LocalFileRef: Codable, Sendable, Equatable {
    public var sha256: String
    public var relativePath: String

    public init(sha256: String, relativePath: String) {
        self.sha256 = sha256
        self.relativePath = relativePath
    }
}

/// OCR extraction provenance embedded in FillUp/ChargeSession
/// (docs/SCHEMA.md, ExtractionMeta).
public struct ExtractionMeta: Codable, Sendable, Equatable {
    public var fields: [FieldRef: FieldExtraction]
    public var pipeline: String

    public init(fields: [FieldRef: FieldExtraction], pipeline: String) {
        self.fields = fields
        self.pipeline = pipeline
    }
}

/// Per-field OCR extraction record (docs/SCHEMA.md, FieldExtraction).
public struct FieldExtraction: Codable, Sendable, Equatable {
    public var cropRect: CGRect?
    public var confidence: Double
    public var userCorrected: Bool

    public init(cropRect: CGRect?, confidence: Double, userCorrected: Bool) {
        self.cropRect = cropRect
        self.confidence = confidence
        self.userCorrected = userCorrected
    }
}

/// Synced, app-level settings - one singleton record per account
/// (docs/SCHEMA.md, Preferences).
public struct Preferences: Entity, Codable, Sendable, Equatable {
    /// Well-known fixed id for the single synced preferences record
    /// (docs/SCHEMA.md: well-known id "preferences"). A v7-shaped constant so it
    /// stays consistent with device-generated ids.
    public static let fixedID = UUID(uuidString: "00000000-0000-7000-8000-000000000001")!

    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var notifications: Notifications
    public var eagerMediaOnWiFi: Bool
    public var defaultVehicleId: UUID?
    public var proFeedbackDiagnostics: Bool

    public init(createdAt: Date, updatedAt: Date, deletedAt: Date? = nil,
                notifications: Notifications = Notifications(),
                eagerMediaOnWiFi: Bool = false,
                defaultVehicleId: UUID? = nil,
                proFeedbackDiagnostics: Bool = false) {
        self.id = Preferences.fixedID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.notifications = notifications
        self.eagerMediaOnWiFi = eagerMediaOnWiFi
        self.defaultVehicleId = defaultVehicleId
        self.proFeedbackDiagnostics = proFeedbackDiagnostics
    }

    /// Notification content categories - what may notify at all
    /// (docs/SCHEMA.md, Preferences.notifications).
    public struct Notifications: Codable, Sendable, Equatable {
        public var reminders: Bool
        public var anomalies: Bool
        public var monthlySummary: Bool

        public init(reminders: Bool = true, anomalies: Bool = true, monthlySummary: Bool = false) {
            self.reminders = reminders
            self.anomalies = anomalies
            self.monthlySummary = monthlySummary
        }
    }
}

/// Local rate-cache row - deliberately NOT synced (docs/SCHEMA.md, ExchangeRate).
/// No envelope: it has no id/createdAt and never leaves the device.
public struct ExchangeRate: Codable, Sendable, Equatable {
    public var base: CurrencyCode
    public var quote: CurrencyCode
    public var date: Date
    public var rate: Decimal
    public var source: RateSource

    public init(base: CurrencyCode, quote: CurrencyCode, date: Date,
                rate: Decimal, source: RateSource) {
        self.base = base
        self.quote = quote
        self.date = date
        self.rate = rate
        self.source = source
    }
}
