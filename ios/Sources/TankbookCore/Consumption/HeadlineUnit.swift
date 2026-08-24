import Foundation

/// How a vehicle's consumption headline is presented
/// (design/screens/CarSwitcher.dc.html): an EV reports `kWh/100`, a fuel
/// vehicle the configured consumption unit (`L/100`, `MPG`, ...). The choice is
/// **per-vehicle**, never a global setting - the switcher artboard shows the
/// contrast on one screen (Volvo V60 "6.8 L/100" beside ID.4 "17.8 kWh/100").
public enum HeadlineUnit: Equatable, Sendable {
    /// Electric range consumption (`Vehicle.units.energy` - kWh/100km).
    case energyPer100
    /// Fuel consumption (`Vehicle.units.consumption` - L/100, MPG, km/L).
    case consumption(ConsumptionUnit)
}

extension Vehicle {
    /// The unit the consumption headline is reported in, derived from the
    /// powertrain so an EV and a petrol car sharing one code path can never
    /// disagree about their units (P1.11).
    public var headlineUnit: HeadlineUnit {
        powertrain == .ev ? .energyPer100 : .consumption(units.consumption)
    }
}
