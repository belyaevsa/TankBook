import SwiftUI
import TankbookCore
import UIKit

/// PJ.1 - the capture camera screen (design/screens/Capture.dc.html). The
/// whole product thesis on one screen: capture replaces typing.
///
/// The shutter now takes a real frame and the Photos pick feeds the same path:
/// image -> `CapturePipeline` (Vision OCR + fiscal-QR detection -> the core
/// `ExtractionAssembler`) -> the existing `ManualFillUpView` with a
/// `ConfirmPrefill`. A scan that resolves nothing lands the ordinary empty
/// manual form, never an error (hard rule 15).
///
/// F8 (docs/ERRORS.md -> Capture): camera permission denied opens the manual
/// form with the top card "Scanning needs the camera – enable in Settings."
/// and its three next steps (Settings deep link, Type it, Photos). The denied
/// state is never a dead end: the embedded manual form saves normally and
/// dismisses straight back to the opener.
struct CaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(ServiceInvoiceSession.self) private var invoiceSession

    @State private var cameraStatus: CaptureCameraStatus = .notDetermined
    @State private var mode: CaptureMode = .fillUpAuto
    @State private var activeSheet: CaptureSheet?
    @State private var hasUnsavedChanges = false
    @State private var resolved = false
    /// Guards against a double shutter tap starting two pipelines.
    @State private var isProcessing = false
    /// The P6.10 alpha-testing disclosure, derived on appear from the capture
    /// count and the persisted dismissal state (see `CaptureAlphaNoticeState`).
    @State private var alphaNoticeVisible = false

    /// The selected car's powertrain, which decides the mode row
    /// (`CaptureMode.modes(for:)`). Defaults to `.ice` so the screen renders
    /// sensibly before the load completes and in previews; the real value is
    /// read on appear, and `injectedPowertrain` overrides it for tests and the
    /// screenshot runs.
    @State private var powertrain: Powertrain = .ice

    /// The shared camera session: the live preview and the shutter's photo
    /// capture are the SAME session, so what the preview shows is what a scan
    /// reads.
    @State private var camera = CameraController()

    private let authorizer: CameraAuthorizing
    private let injectedPowertrain: Powertrain?
    /// The Capture -> ServiceEntry exit (SCREENMAP.md): called once the Service
    /// invoice has been scanned and processed, so the presenting tab can close
    /// this cover and open the ServiceEntry sheet.
    private let onServiceEntry: () -> Void

    init(authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
         injectedPowertrain: Powertrain? = nil,
         onServiceEntry: @escaping () -> Void = {}) {
        self.authorizer = authorizer
        self.injectedPowertrain = injectedPowertrain
        self.onServiceEntry = onServiceEntry
    }

    var body: some View {
        ZStack {
            cameraBackground
            if cameraStatus == .denied {
                deniedLayout
            } else {
                liveLayout
            }
        }
        .task { await resolvePermission() }
        .onAppear { loadPowertrain(); loadAlphaNotice() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings after a denial: re-read the status so
            // a grant in Settings resumes the camera surface without a relaunch.
            guard phase == .active else { return }
            let current = authorizer.status()
            if current != .notDetermined {
                cameraStatus = current
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .manualForm:
                SheetDestinationView(route: .confirmManual)
            case .photoPicker:
                PhotoPickerView(isPresented: Binding(
                    get: { activeSheet == .photoPicker },
                    set: { isShown in if !isShown { activeSheet = nil } }
                )) { image in
                    if let image {
                        processScanned(image)
                    }
                }
            case .documentCamera:
                DocumentCamera(
                    onCancel: { activeSheet = nil },
                    onResult: { images in
                        activeSheet = nil
                        scanServiceInvoice(images)
                    })
            case .scanned(let prefill):
                ScannedFillUpSheet(prefill: prefill)
            }
        }
    }

    // MARK: - Permission

    private func resolvePermission() async {
        guard !resolved else { return }
        resolved = true
        let initial = authorizer.status()
        if initial == .notDetermined {
            cameraStatus = await authorizer.request()
        } else {
            cameraStatus = initial
        }
        if cameraStatus == .authorized {
            camera.start()
        }
    }

    /// Reads the selected car's powertrain so the mode row offers only what
    /// that car can actually log. Failing to read it is not an error state: the
    /// screen keeps the `.ice` default and stays fully usable, because capture
    /// must never be blocked by a database read (CLAUDE.md rule 1).
    private func loadPowertrain() {
        if let injectedPowertrain {
            powertrain = injectedPowertrain
        } else if let forced = ProcessInfo.processInfo.arguments.powertrainOverride {
            powertrain = forced
        } else if let selected = try? currentVehicle() {
            powertrain = selected.powertrain
        }
        if !offeredModes.contains(mode) {
            mode = CaptureMode.defaultMode(for: powertrain)
        }
    }

    private func currentVehicle() throws -> Vehicle? {
        let repository = try AppStore.repository()
        return carSelection.selectedVehicle(try repository.liveVehicles())
    }

    // MARK: - Alpha notice (P6.10)

    /// Seeds first (the `-presentScreen capture` screenshots and tests open the
    /// cover straight at launch, before Home's own `.task` has run) and then
    /// derives whether the notice should show: not retired (fewer than three
    /// captures and fewer than three dismissals) and not dismissed today.
    private func loadAlphaNotice() {
        CaptureAlphaNoticeState.resetForTestsIfRequested()
        HomeTestSeed.seedIfRequested()
        alphaNoticeVisible = CaptureAlphaNoticeState.shouldShow(captureCount: captureEntryCount())
    }

    /// How many captures the device holds - every entry, across every live
    /// vehicle. The retirement threshold of three is the same "enough first-hand
    /// data" number as the floor-3 consumption model.
    private func captureEntryCount() -> Int {
        guard let repository = try? AppStore.repository(),
              let vehicles = try? repository.liveVehicles() else { return 0 }
        return vehicles.reduce(0) { count, vehicle in
            count + ((try? repository.liveEntries(forVehicle: vehicle.id))?.count ?? 0)
        }
    }

    private func dismissAlphaNotice() {
        CaptureAlphaNoticeState.dismiss()
        alphaNoticeVisible = false
    }

    // MARK: - The capture path (PJ.1)

    /// One image in, one `ConfirmPrefill` out, whichever door it came through.
    /// The shutter's frame and the Photos pick land here identically.
    private func processScanned(_ image: UIImage) {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            let prefill = await CapturePipeline.process(image, source: .receipt)
            activeSheet = .scanned(prefill)
        }
    }

    /// The shutter: takes a real frame (or, under `-captureFixtureImage`, a
    /// test-injected one) and feeds the pipeline. In Service mode it is still
    /// the door into the document camera (J7).
    private func captureFrame() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            let image: UIImage?
            if let fixture = fixtureImage() {
                image = fixture
            } else {
                image = await camera.capture()
            }
            guard let image else { return }
            let prefill = await CapturePipeline.process(image, source: .receipt)
            activeSheet = .scanned(prefill)
        }
    }

    /// The `-captureFixtureImage <path>` test double: when set, both the shutter
    /// (no camera on the simulator) and the Photos pick (out of process, not
    /// automatable) resolve to this image, so the capture pipeline is reachable
    /// from a UI test. Production never passes the argument.
    private func fixtureImage() -> UIImage? {
        guard let path = ProcessInfo.processInfo.arguments.captureFixtureImagePath else { return nil }
        return UIImage(contentsOfFile: path)
    }

    // MARK: - Background

    @ViewBuilder
    private var cameraBackground: some View {
        if cameraStatus == .authorized {
            CameraPreview(controller: camera)
                .ignoresSafeArea()
        } else {
            Theme.Palette.midnight
                .ignoresSafeArea()
        }
    }

    // MARK: - Denied (F8): permission card over the manual form

    private var deniedLayout: some View {
        VStack(spacing: 0) {
            permissionCard
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 10)
            ManualFillUpView(hasUnsavedChanges: $hasUnsavedChanges)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.taillight)
                Text("Scanning needs the camera – enable in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
            HStack(spacing: 8) {
                permissionAction("Settings",
                                 identifier: "capturePermissionSettingsButton",
                                 action: openSettings)
                permissionAction("Type it",
                                 identifier: "capturePermissionTypeItButton") {
                    activeSheet = .manualForm
                }
                permissionAction("Photos",
                                 identifier: "capturePermissionPhotosButton") {
                    openPhotos()
                }
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capturePermissionCard")
    }

    private func permissionAction(_ label: LocalizedStringKey,
                                  identifier: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.midnight))
                .overlay(Capsule().stroke(Theme.Palette.ink.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// The Photos door, shared by the permission card and the granted layout:
    /// under the fixture double the image is injected directly; otherwise the
    /// system picker opens and its result feeds the same pipeline.
    private func openPhotos() {
        if let fixture = fixtureImage() {
            processScanned(fixture)
        } else {
            activeSheet = .photoPicker
        }
    }

    // MARK: - Granted: caption, mode row, bottom actions

    private var liveLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Receipts and pump displays are detected automatically")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 36)
                .padding(.bottom, 22)
            modeRow
                .padding(.bottom, 14)
            if alphaNoticeVisible {
                CaptureAlphaNotice(dismiss: dismissAlphaNotice)
            }
            bottomActions
        }
        .padding(.bottom, 24)
        .background(
            LinearGradient(colors: [Theme.Palette.midnight.opacity(0),
                                    Theme.Palette.midnight.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// The modes offered for the selected car's powertrain. A petrol car never
    /// sees Charge and an EV never sees Fill-up (`CaptureMode.modes(for:)`).
    private var offeredModes: [CaptureMode] {
        CaptureMode.modes(for: powertrain)
    }

    /// One line that **scrolls** rather than wrapping. The powertrain filter
    /// already removes a chip for every powertrain except `.phev`, which still
    /// offers four - and in Russian four chips do not fit on an iPhone 12
    /// width, so wrapping would strand a single chip on its own row and read as
    /// broken. Scrolling degrades honestly instead.
    private var modeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(offeredModes, id: \.self) { candidate in
                    modeChip(candidate)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("captureModeRow")
    }

    private func modeChip(_ candidate: CaptureMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            mode = candidate
        } label: {
            Text(candidate.label)
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Theme.Palette.taillight.opacity(0.16)
                                              : Theme.Palette.midnight.opacity(0.8))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Theme.Palette.taillight
                                                : Theme.Palette.ink.opacity(0.15),
                                     lineWidth: isSelected ? 1.5 : 1)
                )
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(candidate.identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The shutter is centred **independently of its neighbours**. With a plain
    /// `HStack { photos; Spacer(); shutter; Spacer(); typeIt }` the shutter sits
    /// midway between two side items of unequal width, so a longer label on one
    /// side visibly shoves the primary action off-axis - which is exactly what
    /// the Russian screenshot showed ("Ввести вручную" is three times the width
    /// of "Фото"). Overlaying the two affordances on a centred shutter makes the
    /// centring immune to label length in any language.
    private var bottomActions: some View {
        shutter
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) { photosButton }
            .overlay(alignment: .trailing) { typeItButton }
            .padding(.horizontal, 48)
    }

    private var photosButton: some View {
        Button {
            openPhotos()
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11)
                    .fill(Theme.Palette.midnight.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .stroke(Theme.Palette.ink.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Icon-only to match the manual-entry affordance opposite it. A caption
        // on one side only makes the two tiles different heights, so they no
        // longer sit on the shutter's axis - visible in the first RU capture.
        .accessibilityLabel("Photos")
        .accessibilityIdentifier("capturePhotosButton")
    }

    private var typeItButton: some View {
        Button {
            activeSheet = .manualForm
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11)
                    .fill(Theme.Palette.midnight.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .stroke(Theme.Palette.ink.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Icon-only, so the label moves to VoiceOver rather than disappearing.
        // It stays in the String Catalog: an accessibility label is user-facing
        // text and hard rule 10 applies to it exactly as to visible copy.
        .accessibilityLabel("Type it")
        .accessibilityIdentifier("captureTypeItButton")
    }

    /// The shutter circle. In every mode it captures a frame and runs the
    /// pipeline (a scan that resolves nothing lands the empty manual form);
    /// in Service mode it is the door into the document camera (J7).
    private var shutter: some View {
        shutterButton
    }
}

// MARK: - Service invoice capture (P3.1b)

private extension CaptureView {
    /// The document camera returned pages: OCR them, split deterministically,
    /// persist the pages, hand the pre-fill to ServiceEntry and leave Capture.
    /// The pre-fill is default input the user edits (hard rule 13) - a failed
    /// split is the lump sum, never an error.
    func scanServiceInvoice(_ images: [UIImage]) {
        Task {
            let prefill = await ServiceInvoiceScanner.process(images: images)
            invoiceSession.pendingPrefill = prefill
            onServiceEntry()
        }
    }

    /// The shutter circle: in Service mode the document camera (J7); in the
    /// other modes a real frame capture into the PJ.1 pipeline.
    var shutterButton: some View {
        let isService = mode == .service
        return Button {
            if isService {
                activeSheet = .documentCamera
            } else {
                captureFrame()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.Palette.taillight)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().stroke(Theme.Palette.ink, lineWidth: 4))
                    .shadow(color: Theme.Palette.taillight.opacity(0.45), radius: 18, y: 4)
                Circle()
                    .stroke(Theme.Palette.ink, lineWidth: 2.2)
                    .frame(width: 30, height: 30)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shutterAccessibilityLabel)
        .accessibilityIdentifier("captureShutterButton")
    }

    private var shutterAccessibilityLabel: LocalizedStringKey {
        mode == .service ? "Scan invoice" : "Capture"
    }
}
