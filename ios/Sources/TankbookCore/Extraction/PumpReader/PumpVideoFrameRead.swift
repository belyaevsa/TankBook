import Foundation

/// One running-display frame read the way the corpus labels video frames: the
/// total and liters windows sliced and classified - the price is the clip's
/// constant and is never read - the cells joined as strings with no law, and a
/// label only where `total == liters x price` closes at the cent, or at the
/// tenth for a head that shows one decimal. `PumpVideoReadTests` and the
/// annotator's resident reader (`pump-read --read-serve`) both read through
/// this, so the two cannot label a frame differently.
struct PumpVideoFrameRead: Equatable {
    let total: String
    let liters: String
    let closes: Bool
    /// The lowest classifier margin over the total and liters cells, nil when
    /// neither window produced a cell.
    let margin: Double?

    /// One window as the tracked file stores it: a field and its quad
    /// normalised over the EXIF-oriented frame.
    struct Window {
        let field: String
        let quad: [[Double]]
    }

    /// Nil when nothing could be read (no window survived, or the reader threw).
    static func read(reader: PumpReader, image: PumpRGBImage, windows: [Window],
                     priceText: String) -> PumpVideoFrameRead? {
        guard let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let located: [PumpReader.Window] = windows.compactMap { window in
            guard window.field != PumpField.unitPrice.rawValue,
                  let role = PumpField(rawValue: window.field) else { return nil }
            let pixels = window.quad.map { CGPoint(x: $0[0] * Double(image.width), y: $0[1] * Double(image.height)) }
            return PumpReader.Window(field: role, quad: pixels)
        }
        guard let reads = try? reader.read(image: image, windows: located) else { return nil }
        let comma = priceText.contains(",")
        var strings: [PumpField: String] = [:]
        var margins: [Double] = []
        for windowRead in reads {
            strings[windowRead.field] = windowRead.cells.map { cell -> String in
                guard let best = cell.ranked.first else { return "?" }
                return String(best.digit) + (cell.decimalPoint ? (comma ? "," : ".") : "")
            }.joined()
            if windowRead.field == .total || windowRead.field == .liters {
                margins.append(contentsOf: windowRead.cells.map(\.margin))
            }
        }
        let totalText = strings[.total] ?? "", litersText = strings[.liters] ?? ""
        let total = Double(totalText.replacingOccurrences(of: ",", with: "."))
        let liters = Double(litersText.replacingOccurrences(of: ",", with: "."))
        var closes = false
        if !totalText.contains("?"), !litersText.contains("?"), let total, let liters, liters > 0 {
            closes = abs(total - (liters * price * 100).rounded() / 100) < 0.011
                || abs(total - (liters * price * 10).rounded() / 10) < 0.06
        }
        return PumpVideoFrameRead(total: totalText, liters: litersText, closes: closes, margin: margins.min())
    }

    /// The per-frame reading the annotator pre-fills from - kept for every frame read.
    var reading: [String: Any] {
        var out: [String: Any] = ["total": total, "liters": liters, "closes": closes]
        if let margin { out["margin"] = margin }
        return out
    }

    /// The arithmetic label - only for a frame that closes.
    func label(priceText: String) -> [String: Any]? {
        closes ? ["total": total, "liters": liters, "unitPrice": priceText, "source": "arithmetic"] : nil
    }
}
