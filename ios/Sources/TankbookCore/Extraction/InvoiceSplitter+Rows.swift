import CoreGraphics
import Foundation

// MARK: - Table rows, the tax line and the issuer's domain

extension InvoiceSplitter {
    /// One page's lines rebuilt into printed rows. Vision reads a table cell as
    /// its own line, so an invoice row's code, title, quantity and amounts
    /// arrive as separate lines, and a label and its value (`ARVE SUMMA:` ...
    /// `134.00 EUR`) as two. Lines whose vertical centres lie within half a
    /// typical line height are one row, joined left to right; rows run top to
    /// bottom. Lines without geometry (`.zero` boxes, the text-only entry
    /// point) are returned unchanged, in their order.
    public static func rows(_ lines: [OCRLine]) -> [OCRLine] {
        guard lines.contains(where: { $0.boundingBox != .zero }) else { return lines }
        let heights = lines.map(\.boundingBox.height).filter { $0 > 0 }.sorted()
        guard !heights.isEmpty else { return lines }
        let tolerance = heights[heights.count / 2] * rowToleranceInLineHeights
        var rows: [[OCRLine]] = []
        for line in lines.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last, let anchor = last.first, abs(anchor.midY - line.midY) <= tolerance {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { cells in
            let ordered = cells.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let box = ordered.dropFirst().reduce(ordered[0].boundingBox) { $0.union($1.boundingBox) }
            return OCRLine(text: ordered.map(\.text).joined(separator: "  "),
                           confidence: ordered.map(\.confidence).min() ?? 1,
                           boundingBox: box)
        }
    }

    /// Half a line height: cells of one printed row share a baseline to within
    /// a few percent of a line's height, while the next row sits a full line
    /// away, so half a height separates the two with room for a slight tilt.
    static let rowToleranceInLineHeights: CGFloat = 0.5

    /// Labels that name the tax an invoice adds on top of its net lines. A line
    /// carrying one of these, and not a "without tax" label, prints the tax
    /// amount.
    static let taxLabels = ["KÄIBEMAKS", "KAIBEMAKS", "НДС", "VAT", "MWST", "MOMS", "PVM", "ALV"]
    /// "Without tax" and "net" labels, which carry a net subtotal, not the tax.
    static let untaxedLabels = [
        "KÄIBEMAKSUTA", "KAIBEMAKSUTA", "KM-TA", "KMTA", "ILMA KM", "БЕЗ НДС", "NETTO", "EXCL",
        "OHNE MWST", "ZWISCHENSUMME", "SUBTOTAL"
    ]

    /// The tax amount the invoice prints, as a line item titled by its label
    /// (`Käibemaks 24%`), when exactly one tax line carries an amount.
    func detectTaxItem(_ lines: [OCRLine]) -> InvoiceLineItem? {
        var found: [InvoiceLineItem] = []
        for line in lines {
            let upper = line.text.uppercased()
            guard Self.taxLabels.contains(where: upper.contains),
                  !Self.untaxedLabels.contains(where: upper.contains),
                  let (title, amount) = Self.splitTitleAmount(line.text), amount > 0 else { continue }
            found.append(InvoiceLineItem(title: Self.taxTitle(title), amount: amount,
                                         category: .other(""), confidence: Double(line.confidence)))
        }
        return found.count == 1 ? found[0] : nil
    }

    /// The tax line's own label, without whatever the row put before it.
    private static func taxTitle(_ title: String) -> String {
        let upper = title.uppercased()
        for label in taxLabels {
            if let range = upper.range(of: label) {
                let start = title.index(title.startIndex,
                                        offsetBy: upper.distance(from: upper.startIndex, to: range.lowerBound))
                return String(title[start...]).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            }
        }
        return title
    }

    /// The net lines plus the printed tax equal the total: the lines are net of
    /// tax and the total is gross, so the tax is the missing line.
    static func sumsToTotalWithTax(_ items: [InvoiceLineItem], tax: InvoiceLineItem, total: Decimal) -> Bool {
        sumsToTotal(items + [tax], total: total)
    }

    // MARK: - Vendor evidence

    /// Legal forms that mark a line as the issuing company's registered name.
    static let legalForms = ["AS", "OÜ", "OU", "ООО", "ИП", "АО", "ПАО", "GMBH", "SIA", "UAB", "OY", "AB",
                             "LTD", "LLC", "SA", "SRL", "BV"]

    /// The first company-shaped line that carries a legal form as its own word.
    func legalNameLine(_ lines: [OCRLine]) -> String? {
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isVendorCandidate(text) else { continue }
            let words = text.uppercased().split(whereSeparator: { !$0.isLetter })
            if words.contains(where: { Self.legalForms.contains(String($0)) }) { return text }
        }
        return nil
    }

    /// Mail and web hosts that name a provider, not the issuer.
    static let genericDomains = ["gmail", "mail", "yandex", "outlook", "hotmail", "icloud", "yahoo",
                                 "inbox", "rambler", "bk", "list", "live", "me", "proton", "protonmail"]

    /// The issuer named by its own e-mail or web domain (`…@tireman.ee`,
    /// `www.tireman.ee` -> `Tireman`), skipping mail providers.
    func domainVendor(_ lines: [OCRLine]) -> String? {
        let pattern = #/(?:@|www\.)([A-Za-z0-9-]+)\.[A-Za-z]{2,}/#
        for line in lines {
            for match in line.text.matches(of: pattern) {
                let name = String(match.1).lowercased()
                guard name.count >= 3, !Self.genericDomains.contains(name) else { continue }
                return name.prefix(1).uppercased() + name.dropFirst()
            }
        }
        return nil
    }

    /// A line that could name the vendor: company-shaped, not a total or tax
    /// line, and not a `Label: value` field (`Kommentaar: 004TXK`,
    /// `Email: …`) - a field's value is data about the job, not its issuer.
    static func isVendorCandidate(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(":") else { return false }
        guard totalLabelKind(text) == nil,
              !excludedLabels.contains(where: text.uppercased().contains) else { return false }
        return CompanyNameLine.isCompanyName(text)
    }
}
