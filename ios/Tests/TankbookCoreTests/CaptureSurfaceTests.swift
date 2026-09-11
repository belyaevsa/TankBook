import Testing
@testable import TankbookCore

/// RV.222 + RV.223 L1 - the pure decisions behind the capture surface's two
/// recovery paths. The denied fallback and the transient camera fault are
/// separate states: permission can be `.authorized` while the hardware refuses,
/// so a fault must not become a fourth `CaptureCameraStatus` case. The mapping
/// is pinned here so a view-only change cannot silently flip the precedence.
struct CaptureSurfaceTests {

    // MARK: - RV.222: the surface state

    @Test("a denied permission presents the denied fallback")
    func deniedPresentsTheFallback() {
        #expect(CaptureSurfaceState.resolve(status: .denied, cameraFault: false) == .denied)
    }

    /// Denied wins over a fault: a permission the user revoked is not something
    /// the fault card can fix, and its Settings next step is still the right one.
    @Test("denied outranks a transient fault")
    func deniedOutranksFault() {
        #expect(CaptureSurfaceState.resolve(status: .denied, cameraFault: true) == .denied)
    }

    /// The RV.223 decision: an authorised camera that returned nothing is the
    /// fault state, never a silent live surface.
    @Test("an authorised camera with a fault presents the fault state")
    func authorisedFaultPresentsFault() {
        #expect(CaptureSurfaceState.resolve(status: .authorized, cameraFault: true) == .fault)
    }

    @Test("an authorised camera with no fault is live")
    func authorisedWithoutFaultIsLive() {
        #expect(CaptureSurfaceState.resolve(status: .authorized, cameraFault: false) == .live)
    }

    @Test("an undetermined permission with no fault is live (the resolve runs first)")
    func undeterminedWithoutFaultIsLive() {
        #expect(CaptureSurfaceState.resolve(status: .notDetermined, cameraFault: false) == .live)
    }

    // MARK: - RV.223: the shutter outcome

    /// The fixture path substitutes the camera entirely and is always usable,
    /// so it can never report a fault - the "nil-in-fixture path is unchanged"
    /// half of the row.
    @Test("a fixture image is always a review, never a fault")
    func fixtureIsAlwaysReview() {
        #expect(CaptureShutterOutcome.resolve(usedFixture: true, cameraImage: false) == .review)
    }

    /// The row's headline: a real camera that returns nil outside the fixture
    /// path is the fault the caller must surface.
    @Test("a real camera returning nothing is a fault")
    func realCameraNilIsFault() {
        #expect(CaptureShutterOutcome.resolve(usedFixture: false, cameraImage: false) == .cameraFault)
    }

    @Test("a real camera returning a frame is a review")
    func realCameraFrameIsReview() {
        #expect(CaptureShutterOutcome.resolve(usedFixture: false, cameraImage: true) == .review)
    }
}
