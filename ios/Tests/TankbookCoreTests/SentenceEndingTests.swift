import Testing
@testable import TankbookCore

/// RV.77 - the doubled period an RU screenshot showed and no test could:
/// "Counted from this record ... 3 сент.." A Russian abbreviated month brings
/// its own period, so a sentence phrase that ends in one doubles it.
@Suite("Composed sentence endings (RV.77)")
struct SentenceEndingTests {
    @Test func aValueEndingInAPeriodDoesNotDoubleIt() {
        #expect(SentenceEnding.normalized("Отсчёт от этой записи – 3 сент..") ==
                "Отсчёт от этой записи – 3 сент.",
                "a doubled trailing period collapses to one")
    }

    @Test func anOrdinarySentenceKeepsItsPeriod() {
        #expect(SentenceEnding.normalized("Counted from this record – Sep 3.") ==
                "Counted from this record – Sep 3.",
                "a single period is left alone")
    }

    @Test func anEllipsisSurvives() {
        #expect(SentenceEnding.normalized("Loading...") == "Loading...",
                "three dots are an ellipsis, never a doubled period")
    }
}
