import Foundation

/// The process-wide vocabulary the station resolver reads (the one creation
/// seam, `ImportStationResolver.station(for:)`). The app installs its
/// `StationBrandStore` at launch; with none installed the bundled seed serves,
/// so the package's own tests and a headless resolver still match. Never
/// consulted for a station that already exists.
public enum StationBrandRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var store: StationBrandStore?

    public static func install(_ store: StationBrandStore) {
        lock.withLock { Self.store = store }
    }

    public static var brands: [StationBrand] {
        if let store = lock.withLock({ store }) { return store.brands }
        return bundled
    }

    /// The seed decoded once: an import resolves hundreds of names through
    /// this accessor, and decoding the pack per name is the cost to avoid.
    private static let bundled: [StationBrand] = (try? StationBrandSeed.bundledPack().brands) ?? []

    nonisolated(unsafe) private static var hint: String?

    /// The most recent `detectedCountry` a per-request response carried
    /// (docs/API.md). In memory only - computed, used for ordering, forgotten
    /// at the next launch; never written anywhere.
    public static var detectedCountry: String? {
        get { lock.withLock { hint } }
        set { lock.withLock { hint = newValue } }
    }
}
