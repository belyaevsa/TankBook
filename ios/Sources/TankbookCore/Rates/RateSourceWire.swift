import Foundation

/// The single wire→`RateSource` mapping, shared by the bundled seed decoder and
/// the `/rates/pack` decoder (docs/API.md -> Exchange rates). The backend
/// writes a carried-forward row (a weekend/holiday with no publish) as
/// `"<source>:carried-forward"`, so the label before the `:` decides the source
/// - a `"cis:carried-forward"` row is still CIS data, never ECB.
extension RateSource {
    /// Maps a wire `source` string to a `RateSource`. `"cis"` and
    /// `"cis:carried-forward"` map to `.cis`; everything else - `"ecb"`,
    /// `"ecb:carried-forward"`, and any unknown label - maps to `.ecb`.
    public static func wire(_ source: String) -> RateSource {
        let label = source.split(separator: ":", maxSplits: 1).first.map(String.init) ?? source
        return label == RateSource.cis.rawValue ? .cis : .ecb
    }
}
