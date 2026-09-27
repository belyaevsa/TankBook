import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// A per-unit label - `EUR/1L`, `HIND/1L`, `€/L`, `Цена/л` - names what a price
/// is per, never how much was bought. The OCR lines below are what iOS 27's
/// Vision reads on the Neste and Alexela black-LCD heads (`pump-339`,
/// `live-6404`), where the reader refuses and the photo falls to the receipt
/// path (PU.93).
@Suite("A per-unit label is not a volume")
struct FuelExtractorPerUnitLabelTests {
    private let extractor = FuelExtractor(
        bandProvider: DefaultFuelPriceBandProvider(pack: try! FuelPriceBandStore.bundledPack()))

    private func extract(_ texts: [String], source: ExtractionSource = .receipt) -> FuelExtraction {
        extractor.extract(lines: texts.map { OCRLine(text: $0) }, source: source, qrAnchor: nil)
    }

    @Test("pump-339 (Neste black LCD): HIND/1L commits no litre")
    func nesteHindPerLitre() {
        let result = extract(["Futura 95", "1959", "Futura 98", "EUR", "2.0 19", "HIND/1L", "nESTEMY D", "2399",
                              "LIITRIT", "Futura DE", "CNCHE MTRO", "STOP", "ÄRA UNUSTA", "PÜSTOLIT PAAKI!", "3", "3"])
        #expect(result.liters == nil)
    }

    @Test("live-6404 (Alexela black LCD): EUR/1L commits no litre")
    func alexelaEurPerLitre() {
        let result = extract(["EUR", "LIITRIT", "19", "EUR/1L", "NB!", "ARA UNUSTA"])
        #expect(result.liters == nil)
    }

    @Test("a price per litre label is not the volume")
    func pricePerLitreLabel() {
        #expect(extract(["Цена/л 52.10"]).liters == nil)
        #expect(extract(["€/L 2,080"]).liters == nil)
    }

    @Test("a printed volume beside its total still reads")
    func printedVolumeStillReads() {
        #expect(extract(["Diesel", "45.20 L x 2.000 EUR/L", "TOTAL 90.40 EUR"]).liters == 45.2)
    }

    @Test("a lone volume with no total to check it against commits nothing")
    func loneVolumeWithoutTotal() {
        #expect(extract(["6L02"]).liters == nil)
        #expect(extract(["EUR", "2079 L", "4573", "LIITRIT", "EUR/IL"]).liters == nil)
    }

    /// `live-6424` frame 37: the board cell `2.019` (Futura 98) sits directly
    /// below `HIND/L`, where the label rule looks for a receipt's price. The fill
    /// was Futura 95 at 1.959, and no total or volume was read to check it.
    @Test("a lone board price under HIND/1L commits nothing")
    func lonePriceUnderPerUnitLabel() {
        let lines = [OCRLine(text: "HIND/L", boundingBox: CGRect(x: 0.60, y: 0.500, width: 0.08, height: 0.010)),
                     OCRLine(text: "2.019", boundingBox: CGRect(x: 0.60, y: 0.488, width: 0.06, height: 0.010)),
                     OCRLine(text: "Futura 98", boundingBox: CGRect(x: 0.40, y: 0.488, width: 0.10, height: 0.010)),
                     OCRLine(text: "LIITRIT", boundingBox: CGRect(x: 0.20, y: 0.300, width: 0.08, height: 0.010))]
        #expect(extractor.extract(lines: lines, source: .receipt, qrAnchor: nil).unitPrice == nil)
    }
}
