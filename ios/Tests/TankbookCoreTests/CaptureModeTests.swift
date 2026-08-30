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
    @Test("a petrol car is never offered Charge, an EV is never offered Fill-up")
    func modesFollowThePowertrain() {
        #expect(CaptureMode.modes(for: .ice) == [.fillUpAuto, .service, .expense])
        #expect(CaptureMode.modes(for: .ev) == [.charge, .service, .expense])
        #expect(!CaptureMode.modes(for: .ice).contains(.charge))
        #expect(!CaptureMode.modes(for: .ev).contains(.fillUpAuto))
    }

    /// The distinction that is easy to get backwards: a plain hybrid has no
    /// plug - its battery is charged by the engine and by regeneration - so it
    /// must not be offered a charging session. Only a plug-in does both.
    @Test("a plain hybrid gets no Charge; only a plug-in hybrid gets both")
    func hybridHasNoPlugButPhevDoes() {
        #expect(!CaptureMode.modes(for: .hybrid).contains(.charge))
        #expect(CaptureMode.modes(for: .hybrid) == CaptureMode.modes(for: .ice))

        let phev = CaptureMode.modes(for: .phev)
        #expect(phev.contains(.fillUpAuto))
        #expect(phev.contains(.charge))
        #expect(phev.count == 4, "phev is the only four-chip case")
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
}
