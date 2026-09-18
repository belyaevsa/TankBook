import Testing
import Foundation
@testable import TankbookCore

/// Pairing the cloud's invoice lines onto the local split (PJ.302). The
/// property the fixtures are built to catch: the pairing is by amount, then
/// title, NEVER by position - every fixture below is reordered, so a matcher
/// that paired by index fails it.
struct LineMatcherTests {

    private static func money(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    private static func local(_ title: String, _ amount: String?,
                              _ category: ServiceCategory = .other("")) -> ServiceItem {
        ServiceItem(title: title, category: category, cost: amount.map(money))
    }

    private static func cloud(_ title: String, _ amount: String?,
                              _ category: ServiceCategory = .other("")) -> ServiceRecognition.LineItem {
        ServiceRecognition.LineItem(title: title, category: category, cost: amount.map(money))
    }

    @Test("lines with the same amount pair, whatever their order")
    func sameAmountPairsAcrossOrder() {
        let local = [Self.local("Oil filter", "24.90"), Self.local("Labour", "120.00"), Self.local("Oil 5W30", "48.50")]
        // The cloud reads them in a different order and with OCR'd titles.
        let cloud = [Self.cloud("LABOUR 2H", "120.00"), Self.cloud("Motor oil", "48.50"), Self.cloud("Filter", "24.90")]

        let matches = LineMatcher.match(cloud: cloud, local: local)

        #expect(matches.map(\.localIndex) == [1, 2, 0])
        #expect(matches.allSatisfy { $0.basis == .sameAmount })
    }

    @Test("without an amount match the closest title pairs, above the threshold")
    func titleFallback() {
        let local = [Self.local("Brake pads front", "89.00"), Self.local("Wheel alignment", "45.00")]
        let cloud = [Self.cloud("Wheel alignment check", "49.00"), Self.cloud("Front brake pads", "95.00")]

        let matches = LineMatcher.match(cloud: cloud, local: local)

        #expect(matches[0] == LineMatch(cloudIndex: 0, localIndex: 1, basis: .title))
        #expect(matches[1] == LineMatch(cloudIndex: 1, localIndex: 0, basis: .title))
    }

    @Test("a cloud line nothing pairs with is new; a local line nothing pairs with is left alone")
    func unmatchedLines() {
        let local = [Self.local("Oil change", "80.00"), Self.local("Cabin filter", "19.00")]
        let cloud = [Self.cloud("Oil change", "80.00"), Self.cloud("Environmental fee", "3.50")]

        let matches = LineMatcher.match(cloud: cloud, local: local)

        #expect(matches[0].localIndex == 0)
        #expect(matches[1] == LineMatch(cloudIndex: 1, localIndex: nil, basis: .new))
        // No match names local index 1: the cabin filter is nobody's partner and
        // is never offered for replacement or deletion.
        #expect(!matches.contains { $0.localIndex == 1 })
    }

    @Test("no local line is paired twice")
    func oneToOne() {
        let local = [Self.local("Labour", "60.00")]
        let cloud = [Self.cloud("Labour hour 1", "60.00"), Self.cloud("Labour hour 2", "60.00")]

        let matches = LineMatcher.match(cloud: cloud, local: local)

        #expect(matches[0].localIndex == 0)
        #expect(matches[1].basis == .new)
    }

    @Test("Russian titles pair by token overlap, case-insensitively")
    func russianTitles() {
        let local = [Self.local("Замена масла", nil), Self.local("Тормозные колодки", nil)]
        let cloud = [Self.cloud("ТОРМОЗНЫЕ КОЛОДКИ передние", nil), Self.cloud("замена масла и фильтра", nil)]

        let matches = LineMatcher.match(cloud: cloud, local: local)

        #expect(matches.map(\.localIndex) == [1, 0])
        #expect(matches.allSatisfy { $0.basis == .title })
    }

    @Test("a title below the threshold does not pair")
    func weakTitleIsNew() {
        let local = [Self.local("Oil change", nil)]
        let cloud = [Self.cloud("Coolant top-up", nil)]
        #expect(LineMatcher.match(cloud: cloud, local: local)
            == [LineMatch(cloudIndex: 0, localIndex: nil, basis: .new)])
    }
}
