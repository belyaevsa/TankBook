import Foundation

/// The car's home-city question: asked, and how it was answered. Shape only -
/// never the city, the country or a coordinate (hard rule 12).
public struct HomeCityAsked: LogEvent {
    public let eventName = "homeCity.ask"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    /// `action` is `raised`, `confirmed`, `chosen` or `dismissed`; `suggested`
    /// says whether the receipt named a city.
    public init(action: String, suggested: Bool) {
        fields = [.safe("action", action), .safe("suggested", suggested)]
    }
}

/// A home city typed under "Other": whether the geocoder found it. The count of
/// misses is what says which cities the dictionary lacks; the name never leaves
/// the device.
public struct HomeCityTyped: LogEvent {
    public let eventName = "homeCity.typed"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(found: Bool) {
        fields = [.safe("found", found)]
    }
}
