import Foundation
import Testing
@testable import TankbookCore

/// P2.1 - the capture mode row contract (design/screens/Capture.dc.html):
/// exactly four modes, Fill-up first (the default) and the only one promising
/// automatic surface detection. The UI row, the P2.3 forward exits and the
/// P2.7 pump-mode feature flag all switch on this enum, so pinning the contract
/// here catches a reorder or an accidental addition at the source instead of in
/// an accessibility tree.
struct CaptureModeTests {

    @Test
    func exactlyFourModesInArtboardOrder() {
        #expect(CaptureMode.allCases == [.fillUpAuto, .charge, .service, .expense])
    }

    @Test
    func fillUpIsFirstSoItIsTheDefault() {
        #expect(CaptureMode.allCases.first == .fillUpAuto,
                "the artboard's default chip must be the first case")
    }

    @Test
    func onlyFillUpPromisesAutomaticDetection() {
        for mode in CaptureMode.allCases {
            if mode == .fillUpAuto {
                #expect(mode.isSurfaceAutoDetected,
                        "Fill-up must carry the · auto promise")
            } else {
                #expect(!mode.isSurfaceAutoDetected,
                        "\(mode.rawValue) must not promise auto-detection")
            }
        }
    }

    @Test
    func modeIdentifiersAreStableAndUnique() {
        let identifiers = CaptureMode.allCases.map(\.rawValue)
        #expect(Set(identifiers).count == identifiers.count,
                "mode identifiers must be unique")
        #expect(identifiers.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Powertrain filtering

    /// A car is only offered the modes it can actually log. The chip is not
    /// merely unused otherwise - it invites an entry the vehicle cannot have.
    /// PJ.12: with EV charging deferred to v1.x, an EV's offered modes are
    /// Service + Expense (no Charge, no Fill-up).
    @Test("a petrol car is never offered Charge, an EV is never offered Fill-up")
    func modesFollowThePowertrain() {
        #expect(CaptureMode.modes(for: .ice) == [.fillUpAuto, .service, .expense])
        #expect(CaptureMode.modes(for: .ev) == [.service, .expense])
        #expect(!CaptureMode.modes(for: .ice).contains(.charge))
        #expect(!CaptureMode.modes(for: .ev).contains(.fillUpAuto))
    }

    /// The distinction that is easy to get backwards: a plain hybrid has no
    /// plug - its battery is charged by the engine and by regeneration - so it
    /// must not be offered a charging session. A plug-in hybrid does have a
    /// plug, and keeps the Fill-up door, but loses `.charge` like everyone
    /// else until EV charging is v1.x (PJ.12).
    @Test("a plain hybrid gets no Charge; a plug-in hybrid keeps Fill-up, Charge deferred")
    func hybridHasNoPlugButPhevKeepsFillUp() {
        #expect(!CaptureMode.modes(for: .hybrid).contains(.charge))
        #expect(CaptureMode.modes(for: .hybrid) == CaptureMode.modes(for: .ice))

        let phev = CaptureMode.modes(for: .phev)
        #expect(phev.contains(.fillUpAuto))
        #expect(!phev.contains(.charge), "PJ.12: the Charge chip is deferred for PHEV too")
        #expect(phev == [.fillUpAuto, .service, .expense])
    }

    // MARK: - PJ.12: the Charge chip is deferred, not offered dead

    /// The whole PJ.12 contract in one sweep: no powertrain is offered
    /// `.charge` while no charge entry form exists (J6 is `[v1.x]`,
    /// docs/JOURNEYS.md). Looping `Powertrain.allCases` is what makes the
    /// PHEV half real - a fix aimed at "the EV bug" drops exactly that case.
    @Test("PJ.12: no powertrain is offered Charge while EV charging is v1.x")
    func chargeIsDeferredForEveryPowertrain() {
        for powertrain in Powertrain.allCases {
            #expect(!CaptureMode.modes(for: powertrain).contains(.charge),
                    "PJ.12: \(powertrain) must not be offered the dead Charge chip")
        }
    }

    /// The EV's default must be a mode that actually works - Service (whose
    /// shutter is the document camera and whose "Type it" opens ServiceEntry),
    /// never a mode it lacks or a dead chip.
    @Test("PJ.12: an EV opens on Service - a mode that works - not on a dead chip")
    func evDefaultsToAWorkingMode() {
        let evModes = CaptureMode.modes(for: .ev)
        #expect(evModes == [.service, .expense])
        let evDefault = CaptureMode.defaultMode(for: .ev)
        #expect(evDefault == .service,
                "an EV must open on Service, the first mode that actually works")
        #expect(evModes.contains(evDefault))
    }

    /// The starting mode has to be one the car is actually offered - an EV must
    /// not open on Fill-up.
    @Test("the default mode is always one of the offered modes")
    func defaultModeIsAlwaysOffered() {
        for powertrain in Powertrain.allCases {
            let offered = CaptureMode.modes(for: powertrain)
            #expect(offered.contains(CaptureMode.defaultMode(for: powertrain)),
                    "\(powertrain) defaults outside its own mode list")
            #expect(!offered.isEmpty)
            #expect(offered.contains(.service) && offered.contains(.expense),
                    "service and expense apply to every powertrain")
        }
    }

    // MARK: - PJ.6: the manual-entry form per mode

    /// Every mode pins an entry form, so "Type it" opens the form for the mode
    /// the user selected (hard rule 15). `.charge` deliberately shares the
    /// fill-up form - no charge form exists yet and PJ.12 owns the dead Charge
    /// chip - and the pin makes that a decision, not a silent fallthrough: a
    /// switch that looks complete over an enum whose cases are not all handled
    /// is the P6.20 shape. Dropping any case fails to compile; this test pins
    /// the intent.
    @Test("every mode pins a manual entry form, charge deliberately sharing fill-up")
    func manualEntryFormIsPinnedForEveryMode() {
        #expect(CaptureMode.fillUpAuto.manualEntryForm == .fillUp)
        #expect(CaptureMode.service.manualEntryForm == .service)
        #expect(CaptureMode.expense.manualEntryForm == .expense)
        #expect(CaptureMode.charge.manualEntryForm == .fillUp,
                "no charge form exists - charge shares the fill-up form until PJ.12")
    }

    // MARK: - RV.61: every entry form has a manual door

    /// RV.61: the Home "Type it" door lists every non-fill-up form as a menu
    /// item, with fill-up as the primary (one-tap) action. This pins the enum's
    /// shape so the door cannot drift: `CaptureEntryForm.allCases` IS the door
    /// menu's source (the app derives it, never hardcodes "Service"/"Expense"),
    /// fill-up leads so it stays the zero-tap primary, and a fourth case added
    /// here both fails this ordering pin and refuses to compile in
    /// `CaptureEntryForm.sheetRoute` (an exhaustive switch) until it maps to a
    /// sheet. The set-equals half pins that no form is an orphan: every case is
    /// a real form some capture mode routes to (hard rule 15 - every entry type
    /// has a typed door).
    @Test("RV.61: every entry form is a distinct manual door, fill-up the primary")
    func everyEntryFormHasAManualDoor() {
        #expect(CaptureEntryForm.allCases == [.fillUp, .service, .expense],
                "fill-up must lead so it stays the door's one-tap primary")
        let reachable = Set(CaptureMode.allCases.map(\.manualEntryForm))
        #expect(reachable == Set(CaptureEntryForm.allCases),
                "every form must be reachable from a capture mode - no orphan form")
    }
}
