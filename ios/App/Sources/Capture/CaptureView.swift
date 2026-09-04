import SwiftUI
import TankbookCore
import UIKit

/// PJ.1 - the capture camera screen (design/screens/Capture.dc.html). The
/// whole product thesis on one screen: capture replaces typing.
///
/// The shutter now takes a real frame and the Photos pick feeds the same path:
/// image -> the RV.5 **review step** (`CaptureReviewView`: see the photo, Use
/// this / Re-take / Type it) -> `CapturePipeline` (Vision OCR + fiscal-QR
/// detection -> the core `ExtractionAssembler`) -> the existing
/// `ManualFillUpView` with a `ConfirmPrefill`. A scan that resolves nothing
/// lands the ordinary empty manual form, never an error (hard rule 15).
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
    @Environment(ExpenseEntrySession.self) private var expenseSession

    @State private var cameraStatus: CaptureCameraStatus = .notDetermined
    @State private var mode: CaptureMode = .fillUpAuto
    @State var activeSheet: CaptureSheet?
    /// RV.5: the captured frame awaiting the user's verdict. Non-nil means the
    /// review step is up; the capture pipeline has NOT run yet.
    @State private var reviewSubject: CaptureReviewSubject?
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
    /// RV.12: called once an entry started here has been written. The capture
    /// screen is a MODAL over the tab the user was on, not a tab root, so the
    /// Confirm sheet's own `dismiss()` only uncovers the camera again - a
    /// completed entry looked like a failed one. The host closes the cover;
    /// this screen only says when.
    private let onEntrySaved: () -> Void

    init(authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
         injectedPowertrain: Powertrain? = nil,
         onServiceEntry: @escaping () -> Void = {},
         onEntrySaved: @escaping () -> Void = {}) {
        self.authorizer = authorizer
        self.injectedPowertrain = injectedPowertrain
        self.onServiceEntry = onServiceEntry
        self.onEntrySaved = onEntrySaved
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
        .onAppear {
            loadPowertrain(); loadAlphaNotice()
            presentTypeItIfRequested(); presentReviewIfRequested()
        }
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
            case .manualForm(let form):
                // The typed door has the same shape and had the same bug: its
                // save dismissed the sheet and left the camera underneath.
                SheetDestinationView(route: form.sheetRoute, onSaved: leaveCaptureAfterSave)
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
                ScannedFillUpSheet(prefill: prefill, onSaved: leaveCaptureAfterSave)
            }
        }
        // RV.5. A cover, not a second `.sheet`: two `.sheet` modifiers on one
        // view is the known SwiftUI pitfall the enum above exists to avoid,
        // and the review needs the whole screen anyway (see CaptureReviewView).
        .fullScreenCover(item: $reviewSubject) { subject in
            CaptureReviewView(image: subject.image,
                              onUse: { acceptReview(subject.image) },
                              onRetake: { reviewSubject = nil },
                              onTypeIt: { typeItAfterReview() })
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
        // PJ.6: `-captureMode <rawValue>` pins the selected mode (tests, and
        // the denied state which has no mode row to tap). A mode the car is
        // not offered is ignored rather than honoured, exactly as the row
        // would not show it.
        if let forcedMode = ProcessInfo.processInfo.arguments.captureModeOverride,
           offeredModes.contains(forcedMode) {
            mode = forcedMode
        } else if !offeredModes.contains(mode) {
            mode = CaptureMode.defaultMode(for: powertrain)
        }
    }

    func currentVehicle() throws -> Vehicle? {
        let repository = try AppStore.repository()
        return carSelection.selectedVehicle(try repository.liveVehicles())
    }

    /// DEBUG/test-only: `-captureAutoTypeIt` opens the "Type it" sheet for the
    /// current mode a beat after the surface appears, so a screenshot can show
    /// the Service form open over the capture surface without a UI test driving
    /// a tap (`simctl` cannot tap). Production never passes the argument; it
    /// routes through the exact call the button makes.
    private func presentTypeItIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-captureAutoTypeIt") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            activeSheet = .manualForm(mode.manualEntryForm)
        }
        #endif
    }

    /// DEBUG/test-only: `-captureAutoReview` (with `-captureFixtureImage`)
    /// presents the RV.5 review step a beat after the surface appears, so
    /// `simctl` - which cannot tap - can screenshot it. Production never
    /// passes the argument; it routes through the exact call the shutter makes.
    private func presentReviewIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-captureAutoReview"),
              let image = fixtureImage() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            processScanned(image)
        }
        #endif
    }

    // MARK: - Alpha notice (P6.10)

    /// Seeds first (the `-presentScreen capture` screenshots and tests open the
    /// cover straight at launch, before Home's own `.task` has run) and then
    /// derives whether the notice should show: not retired (fewer than three
    /// captures and fewer than three dismissals) and not dismissed today.
    private func loadAlphaNotice() {
        #if DEBUG
        CaptureAlphaNoticeState.resetForTestsIfRequested()
        HomeTestSeed.seedIfRequested()
        #endif
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

    /// One image in, one review step, whichever door it came through. The
    /// shutter's frame and the Photos pick land here identically.
    ///
    /// RV.5: the pipeline deliberately does NOT run here. The user sees the
    /// raw image immediately and decides; OCR runs in `acceptReview` only once
    /// they have accepted, so a re-take costs nothing.
    private func processScanned(_ image: UIImage) {
        reviewSubject = CaptureReviewSubject(image: image)
    }

    /// "Use this": exactly where the flow went before the review existed - the
    /// pipeline, then the Confirm sheet. The cover is dismissed FIRST and the
    /// sheet presented after the pipeline's await, because SwiftUI will not
    /// present a sheet in the same runloop turn it dismisses a cover.
    ///
    /// RV.62: Expense mode takes its own exit after the same pipeline - the
    /// recognised total/currency/date go to the expense form through
    /// `ExpenseEntrySession`, never to the fill-up Confirm sheet.
    private func acceptReview(_ image: UIImage) {
        guard !isProcessing else { return }
        isProcessing = true
        reviewSubject = nil
        Task {
            defer { isProcessing = false }
            if mode == .expense {
                await acceptExpenseScan(image)
            } else {
                await acceptFillUpScan(image)
            }
        }
    }

    /// The pause between dismissing the review cover and presenting a sheet.
    /// SwiftUI will not present a sheet in the same runloop turn it dismisses a
    /// cover, and `acceptReview` gets that separation for free from the
    /// pipeline's await; this path has no await, so it needs one explicitly.
    ///
    /// A COMPILED constant (docs/PRACTICES.md): it is coupled to the system's
    /// cover-dismissal animation, so it is not a knob for a user or a remote
    /// flag to turn - it belongs next to the code whose timing it matches.
    static let coverDismissBeat: Duration = .milliseconds(350)

    /// "Type it" from the review: the manual door for the selected mode, the
    /// same call the capture surface's own affordance makes (hard rule 15 -
    /// one door, not a lesser copy of it). The photo is dropped, exactly as a
    /// re-take drops it; nothing is silently carried into a typed entry.
    private func typeItAfterReview() {
        let form = mode.manualEntryForm
        reviewSubject = nil
        Task {
            // Same cover-then-sheet ordering as `acceptReview`, without a
            // pipeline await to separate them, so the beat is explicit.
            try? await Task.sleep(for: Self.coverDismissBeat)
            activeSheet = .manualForm(form)
        }
    }

    /// RV.12: a successful save inside capture closes the capture modal, so the
    /// user lands back on the tab they came from with the new entry visible
    /// (`toastCenter.noteEntryChanged()` has already told Home to reload). Only
    /// the success path calls this: a cancel or a save that threw leaves the
    /// modal exactly where it is, with the photo and the typing intact (hard
    /// rule 8 - nothing lost silently).
    ///
    /// The cover is closed a beat AFTER the Confirm sheet's own `dismiss()`,
    /// for the same reason `typeItAfterReview` waits: SwiftUI does not
    /// reliably act on a dismissal in the same runloop turn as the one above
    /// it. The reload, the gateway seal and the odometer-reconcile `Task` have
    /// all already run by the time the save calls this, so nothing here can
    /// cancel them.
    private func leaveCaptureAfterSave() {
        activeSheet = nil
        Task {
            try? await Task.sleep(for: Self.coverDismissBeat)
            onEntrySaved()
        }
    }

    /// The shutter: takes a real frame (or, under `-captureFixtureImage`, a
    /// test-injected one) and hands it to the RV.5 review step. In Service
    /// mode it is still the door into the document camera (J7).
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
            processScanned(image)
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
                    activeSheet = .manualForm(mode.manualEntryForm)
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
            Text(captureCaption)
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

    /// The caption under the mode row, tailored per powertrain and per the
    /// pump-photo accuracy gate (PJ.12b). "Receipts and pump displays" is true
    /// only for a fuel-tank car AND only while `PumpPhotoGate` lets pump photo
    /// ship - so the pump claim is the gate's answer, never a constant, and a
    /// future build that turns the gate on gets the copy it has earned. An EV
    /// (no `.fillUpAuto` mode) is never offered the pump claim at all: there is
    /// no fuel tank and no pump display to read. `offeredModes` is the same
    /// source of truth as the mode row, so the screen decides what it offers
    /// and what it promises in one place.
    private var captureCaption: LocalizedStringKey {
        if offeredModes.contains(.fillUpAuto), PumpPhotoGate.allowsPumpPhoto {
            return "Receipts and pump displays are detected automatically"
        }
        return "Receipts are detected automatically"
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
            activeSheet = .manualForm(mode.manualEntryForm)
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

    // MARK: - Expense-mode scan (RV.62)

    /// An Expense-mode capture: the same frame and the same `CapturePipeline`
    /// as any receipt - but only total / currency / date may reach the expense
    /// form. A shop receipt is not a fuel receipt: liters, unit price and fuel
    /// kind are meaningless on it, and `ExpensePrefillBuilder` (core, L1)
    /// enforces that boundary - nothing here decides what crosses, it only
    /// hands the mapping's result to ExpenseEntry through the shared session
    /// and opens the expense sheet. A scan that resolves nothing writes an
    /// all-nil prefill, so the form opens empty, never an error (hard rule 7).
    private func acceptExpenseScan(_ image: UIImage) async {
        let extraction: FuelExtraction
        #if DEBUG
        // DEBUG/test-only (`ExpenseScanTestSeed`): a canned recognition lets a
        // UI test assert what the user SEES without OCR over a corpus image.
        // It substitutes only the pipeline's output - the session hand-off and
        // the form's apply path below are exactly the shipped ones.
        if let seeded = ExpenseScanTestSeed.extraction(
            from: ProcessInfo.processInfo.arguments) {
            extraction = seeded
            // The seeded path has no pipeline await to separate the cover's
            // dismissal from the sheet's presentation (see `coverDismissBeat`);
            // OCR's real wait does that for free in production.
            try? await Task.sleep(for: Self.coverDismissBeat)
        } else {
            extraction = await expenseExtraction(from: image)
        }
        #else
        extraction = await expenseExtraction(from: image)
        #endif
        expenseSession.pendingPrefill = ExpensePrefillBuilder.prefill(from: extraction)
        activeSheet = .manualForm(.expense)
    }

    /// Runs the recognition an Expense-mode scan shares with the fill-up path.
    /// `CapturePipeline` is the FILL-UP OCR, and that is deliberate here: its
    /// assembler is what resolves total, currency and date on a receipt; the
    /// fuel-specific fields it also resolves are dropped by the prefill
    /// builder, never carried.
    private func expenseExtraction(from image: UIImage) async -> FuelExtraction {
        let vehicle = try? currentVehicle()
        let prefill = await CapturePipeline.process(
            image, source: .receipt,
            bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle?.id))
        return prefill.extraction ?? FuelExtraction()
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
