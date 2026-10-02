import Foundation
import SwiftUI
import TankbookCore

/// The device's half of the home-city question: the per-car state in
/// UserDefaults (device-local, like the other one-time hints) and the hook the
/// scanned-save paths call.
enum HomeCityAsk {
    static func key(_ vehicleId: UUID) -> String { "homeCity.question.\(vehicleId.uuidString)" }

    static func state(for vehicleId: UUID) -> HomeCityQuestion.State? {
        guard let data = UserDefaults.standard.data(forKey: key(vehicleId)) else { return nil }
        return try? JSONDecoder().decode(HomeCityQuestion.State.self, from: data)
    }

    static func set(_ state: HomeCityQuestion.State, for vehicleId: UUID) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key(vehicleId))
    }

    /// Called after a scanned receipt is saved for `vehicle`.
    static func noteScannedSave(vehicle: Vehicle, prefill: ConfirmPrefill?) {
        guard let prefill, !prefill.ocrLines.isEmpty else { return }
        guard let next = HomeCityQuestion.afterScannedSave(
            vehicle: vehicle, current: state(for: vehicle.id), receiptLines: prefill.ocrLines,
            currency: prefill.extraction?.currency, deviceRegion: Locale.current.region?.identifier,
            dictionary: AppCities.dictionary) else { return }
        set(next, for: vehicle.id)
        if case .pending(let suggested) = next {
            AppLog.shared.emit(HomeCityAsked(action: "raised", suggested: suggested != nil))
        }
    }
}
