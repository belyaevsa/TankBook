import Foundation
import Testing
@testable import TankbookCore

// P6.3 - the late-answer rule (docs/API.md rule 3): fill only fields that are
// still blank and untouched, render as a suggestion, and nothing arrives after
// save. The "cannot overwrite a touched one" half is the point - a test that
// never touches a field first proves nothing.

@Suite("LLM gateway suggestion policy (P6.3)")
struct GatewaySuggestionPolicyTests {

    private static func answer() -> GatewayExtraction {
        GatewayExtraction(
            total: .init(value: Decimal(string: "71.02")!, confidence: 0.9),
            volume: .init(value: 42.30, confidence: 0.9),
            unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.9),
            date: .init(value: "17.08.2026", confidence: 0.8),
            fuelKind: .init(value: .petrol95, confidence: 0.7),
            currency: .init(value: .rub, confidence: 0.6),
            pipeline: "test"
        )
    }

    // MARK: - The rule itself

    @Test("a late answer fills fields that are blank and untouched")
    func fillsBlankAndUntouchedFields() {
        // The on-device pipeline resolved volume only; the user touched
        // nothing. The gateway may fill everything the on-device left blank.
        let snapshot = GatewaySuggestionSnapshot(
            touched: [],
            onDeviceResolved: [.volume],
            saved: false)
        #expect(GatewaySuggestionPolicy.fillableFields(answer: Self.answer(), snapshot: snapshot)
            == [.total, .unitPrice, .date, .fuelKind, .currency])
    }

    @Test("a field the on-device pipeline resolved is not blank and never refilled")
    func onDeviceResolvedFieldIsNeverRefilled() {
        // The gateway says volume 42.30 too - but the on-device parser already
        // put 42.30 on screen, and the gateway never fights the parser for a
        // field the parser already holds.
        let snapshot = GatewaySuggestionSnapshot(touched: [], onDeviceResolved: [.volume], saved: false)
        #expect(!GatewaySuggestionPolicy.fillableFields(answer: Self.answer(), snapshot: snapshot)
            .contains(.volume))
    }

    @Test("a touched field can never be overwritten - the core of hard rule 13")
    func touchedFieldIsNeverOverwritten() {
        // The user typed the total while the request was in flight. The late
        // answer must leave it alone while still filling the untouched blanks.
        let snapshot = GatewaySuggestionSnapshot(
            touched: [.total],
            onDeviceResolved: [.volume],
            saved: false)
        let fillable = GatewaySuggestionPolicy.fillableFields(answer: Self.answer(), snapshot: snapshot)
        #expect(!fillable.contains(.total),
                "a touched field is the user's own - no late answer may overwrite it")
        #expect(fillable.contains(.unitPrice))
        #expect(fillable.contains(.date))
    }

    @Test("engagement on every gateway-fillable field empties the fill set")
    func touchingEverythingEmptiesTheFillSet() {
        let snapshot = GatewaySuggestionSnapshot(
            touched: [.total, .unitPrice, .date, .fuelKind, .currency],
            onDeviceResolved: [.volume],
            saved: false)
        #expect(GatewaySuggestionPolicy.fillableFields(answer: Self.answer(), snapshot: snapshot).isEmpty)
    }

    // MARK: - F4: nothing after save

    @Test("once the entry is saved, nothing arrives at all - even into blank untouched fields")
    func nothingArrivesAfterSave() {
        // The hard F4 stop: even a field that would be fillable before save
        // (blank, untouched) is refused once the entry is saved.
        let snapshot = GatewaySuggestionSnapshot(
            touched: [],
            onDeviceResolved: [.volume],
            saved: true)
        #expect(GatewaySuggestionPolicy.fillableFields(answer: Self.answer(), snapshot: snapshot).isEmpty)
    }

    @Test("the per-field boolean form agrees with the set form")
    func perFieldFormAgrees() {
        #expect(GatewaySuggestionPolicy.mayFill(
            ref: .total, onDeviceResolved: false, touched: false, saved: false))
        #expect(!GatewaySuggestionPolicy.mayFill(
            ref: .total, onDeviceResolved: true, touched: false, saved: false))
        #expect(!GatewaySuggestionPolicy.mayFill(
            ref: .total, onDeviceResolved: false, touched: true, saved: false))
        #expect(!GatewaySuggestionPolicy.mayFill(
            ref: .total, onDeviceResolved: false, touched: false, saved: true))
    }

    @Test("an answer with no fields offers nothing")
    func emptyAnswerOffersNothing() {
        let snapshot = GatewaySuggestionSnapshot(touched: [], onDeviceResolved: [], saved: false)
        #expect(
            GatewaySuggestionPolicy.fillableFields(
                answer: GatewayExtraction(pipeline: "p"), snapshot: snapshot).isEmpty)
    }
}
