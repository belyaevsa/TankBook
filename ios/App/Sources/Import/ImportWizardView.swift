import SwiftUI
import TankbookCore
import UniformTypeIdentifiers

// The import wizard host (P5.5b) - the three screens from the artboards
// (ImportSource / ImportPreview / ImportReview) over one `ImportFlowModel`.
// Wired to `Route.importWizard` in `Destinations.swift`. The whole screen
// exists to honour F6a: nothing is written until the user confirms, so the only
// repository mutation anywhere in this file is `confirmImport`.
struct ImportWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCarSelection.self) private var carSelection
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppConfigService.self) private var configService

    @State private var model: ImportFlowModel?
    @State private var showingFilePicker = false
    @State private var showingCarPicker = false
    @State private var showingNotSupported = false
    @State private var showingSendFile = false
    @State private var didLoad = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .background(Theme.Palette.midnight)
        // The artboards draw their own header (Back/close | title | trailing
        // action), so the system nav bar - which would stack a second "Import"
        // title above it (P6.15a) - is hidden for all three wizard steps.
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !didLoad else { return }
            didLoad = true
            #if DEBUG
            ImportTestSeed.seedDatabaseIfRequested()
            #endif
            if model == nil, let repository = try? AppStore.repository() {
                model = ImportService.makeModel(repository: repository,
                                                configService: configService)
            }
            if let model {
                await model.loadFormats()
                #if DEBUG
                ImportTestSeed.seedFlowIfRequested(model: model)
                // RV.255 screenshot seam: `simctl` cannot tap, so a seeded flow
                // is committed through the REAL confirm path (selection and all)
                // to reach the returned Home.
                if ProcessInfo.processInfo.arguments.contains("-seedImportAutoConfirm") {
                    confirm(model)
                }
                #endif
            }
            // PJ.20: the send-file consent flow's seed - opens the not-supported
            // sheet so the consent + share sheet render without a real tap.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSendFile") {
                showingNotSupported = true
            }
            #endif
        }
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .item],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty,
                  let model else { return }
            // RV.73: a picked URL is security-scoped and the scope dies with
            // this handler, but the bytes are read later (the parse upload,
            // the review). Each pick is copied into the app container UNDER
            // the scope first; `stage` releases the scope on every path and
            // logs a read failure's type/code (never the path or name). If the
            // copy fails, the file could not be read at all - that is the
            // read-failure state, NOT a parse rejection.
            // RV.93: `allowsMultipleSelection: true` - a whole-export pick is
            // several files. Each is staged under its OWN scope and parsed as
            // its own `/import/parse` call; one file must keep working exactly
            // as it did, so a single pick still runs the single-file path.
            let stager = ImportService.makePickedFileStager()
            let preferred = carSelection.selectedVehicle((try? model.repository.liveVehicles()) ?? [])?.id
            model.preparePick()
            var staged: [URL] = []
            var readFailedNames: [String] = []
            for url in urls {
                switch stager.stage(url, log: AppLog.shared) {
                case .staged(let copy):
                    staged.append(copy)
                case .readFailed:
                    readFailedNames.append(url.lastPathComponent)
                }
            }
            if readFailedNames.isEmpty, staged.count == 1 {
                // The single-file path, byte-for-byte today's flow. parse() reads
                // the copy synchronously before starting the upload, so the
                // staged file has served its purpose once it returns.
                model.parse(fileURL: staged[0], preferredVehicleID: preferred)
                stager.dispose(staged[0])
            } else if staged.isEmpty {
                // Nothing could be read at all - the single read-failure state,
                // exactly as a single unreadable pick renders it.
                model.reportPickedFileCouldNotBeRead()
            } else {
                // A whole-export pick (several files, or a mixed pick where some
                // could not be read): read every staged copy now, dispose it (its
                // bytes live in the uploads), then parse each as its own
                // `/import/parse` call. A per-file failure joins `fileFailures`
                // and the run survives the rest (hard rule 7).
                var uploads: [ImportFileUpload] = []
                for copy in staged {
                    if let data = try? Data(contentsOf: copy) {
                        uploads.append(ImportFileUpload(fileName: copy.lastPathComponent,
                                                        data: data))
                    } else {
                        readFailedNames.append(copy.lastPathComponent)
                    }
                    stager.dispose(copy)
                }
                for name in readFailedNames {
                    model.reportBatchReadFailure(fileName: name)
                }
                model.beginBatchParse(uploads: uploads, preferredVehicleID: preferred)
            }
        }
        .sheet(isPresented: $showingCarPicker) {
            if let model { ImportTargetCarSheet(model: model) }
        }
        .sheet(isPresented: $showingNotSupported) {
            ImportNotSupportedSheet(model: model)
        }
    }

    @ViewBuilder
    private func content(_ model: ImportFlowModel) -> some View {
        switch model.step {
        case .source:
            ImportSourceView(
                model: model,
                onChooseFile: { showingFilePicker = true },
                onNotSupported: { showingNotSupported = true },
                onBack: { dismiss() },
                onContinueBatch: { model.continueAfterBatchFailures() })
        case .cars:
            // RV.86: a file holding several source cars lands here - the mapping
            // gate. Its Continue bar performs the SAME one write as the preview's.
            ImportCarsView(
                model: model,
                onBack: { model.backToSource() },
                onCancel: {
                    Task {
                        await model.cancelImport()
                        dismiss()
                    }
                },
                onShowReview: { model.showReview() },
                onImport: { confirm(model) })
        case .preview:
            ImportPreviewView(
                model: model,
                onBack: { model.backToSource() },
                onCancel: {
                    Task {
                        await model.cancelImport()
                        dismiss()
                    }
                },
                onChangeCar: { showingCarPicker = true },
                onShowReview: { model.showReview() },
                onImport: { confirm(model) })
        case .review:
            ImportReviewView(
                model: model,
                onBack: { model.reviewReturn() },
                onDone: { model.reviewReturn() })
        }
    }

    /// The one write, shared by the preview and the multi-car gate: confirm and,
    /// on success, select the car it created, toast the count and leave the
    /// wizard.
    private func confirm(_ model: ImportFlowModel) {
        Task {
            let ok = await model.confirmImport()
            if ok {
                selectCreatedCar(model)
                toastCenter.show(L10n.importedFillUps(model.commitCount))
                dismiss()
            }
        }
    }

    /// RV.255: the returned Home must show the car the import created, not the
    /// one the user had selected before. The model reports the created car; the
    /// selection write lives here, beside the switcher's own, so there is one
    /// selection path. An import into an existing car reports nothing created,
    /// so the user's chosen car stays selected.
    private func selectCreatedCar(_ model: ImportFlowModel) {
        guard let created = model.createdVehicle else { return }
        do {
            try carSelection.select(created)
        } catch {
            AppLog.error(operation: "import.selectCreatedCar", category: .ui, error: error)
        }
    }
}

// MARK: - Shared chrome (artboards: custom header + bottom bar)

/// The wizard's custom header: Back | title | trailing action. The artboards
/// draw their own chrome, so the system nav bar is hidden on this screen.
/// `title` is a `Text` (not a `LocalizedStringKey`) so a dynamic, already
/// localised count like "3 rows need a look" renders without being looked up as
/// a key a second time.
struct ImportHeader: View {
    let title: Text
    let backLabel: LocalizedStringKey?
    let trailingLabel: LocalizedStringKey?
    var onBack: () -> Void = {}
    var onTrailing: () -> Void = {}

    var body: some View {
        HStack {
            if let backLabel {
                Button(action: onBack) {
                    Text(backLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("importHeaderBack")
            }
            Spacer()
            title
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            if let trailingLabel {
                Button(action: onTrailing) {
                    Text(trailingLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("importHeaderTrailing")
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// The primary action bar, drawn like the artboards' taillight button.
struct ImportPrimaryBar<Label: View>: View {
    let label: Label
    var enabled: Bool
    let action: () -> Void

    init(action: @escaping () -> Void, enabled: Bool = true, @ViewBuilder label: () -> Label) {
        self.enabled = enabled
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.body.weight(.bold))
                // P6.19 moved this off Color.white for AA on the taillight fill.
                // But the DISABLED state dims the fill, and midnight on a dimmed
                // dark red is nearly unreadable - the label became harder to read
                // than the white it replaced, which a screenshot caught and no
                // contrast test would, since WCAG exempts disabled controls.
                // ConfirmableFormScreen already had this right; this bar did not.
                .foregroundStyle(enabled ? Theme.Palette.midnight : Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.Palette.taillight)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(color: Theme.Palette.taillight.opacity(0.3), radius: 18, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }
}

// MARK: - Target car chooser (the "Imports into … Change" sheet)

/// Where the import lands, chosen before it lands (hard rule 13: the car is a
/// default the user decides, and the preview recomputes against it).
struct ImportTargetCarSheet: View {
    let model: ImportFlowModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow("Imports into")
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.liveVehicles, id: \.id) { vehicle in
                        carRow(vehicle, isSelected: isSelected(vehicle))
                    }
                    newCarRow
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func isSelected(_ vehicle: Vehicle) -> Bool {
        if case .existing(let current) = model.targetCar {
            return current.id == vehicle.id
        }
        return false
    }

    private func carRow(_ vehicle: Vehicle, isSelected: Bool) -> some View {
        Button {
            model.selectExistingVehicle(vehicle)
            dismiss()
        } label: {
            HStack {
                Text(vehicle.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.action)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 13)
            .formCard()
        }
        .buttonStyle(.plain)
    }

    private var newCarRow: some View {
        Button {
            model.selectNewCar()
            dismiss()
        } label: {
            HStack {
                Text("New car")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 13)
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("importNewCarRow")
    }
}

// MARK: - "Your app isn't here?" sheet

/// The not-listed next step (docs/ERRORS.md -> Import wizard): names what IS
/// supported rather than dead-ending, and offers to take the file.
struct ImportNotSupportedSheet: View {
    let model: ImportFlowModel?
    @Environment(\.dismiss) private var dismiss
    @State private var showingFilePicker = false
    @State private var pickedFileURL: URL?
    @State private var sendFileReadFailed = false
    @State private var showingSendFile = false
    @State private var didSeed = false

    private var supportedNames: String {
        guard let model else { return "" }
        return model.formats.map(\.displayName).joined(separator: ", ")
    }

    /// PJ.33: the per-source export guide, from the supported formats' `helpUrl`
    /// (the wire is the single source; no hardcoded URL here). A stuck user's
    /// next step that exists (hard rule 7).
    private var guideURL: URL? {
        guard let model else { return nil }
        return model.formats.compactMap { $0.helpUrl.flatMap(URL.init(string:)) }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We don't read that one yet.")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(L10n.weReadThese(supportedNames: supportedNames))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.5)
            if let guideURL {
                Link(destination: guideURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                        Text("How to export")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Palette.action)
                }
                .accessibilityIdentifier("importNotSupportedHelp")
            }
            Spacer()
            if sendFileReadFailed {
                // RV.73: the pick could not be copied into the container, so
                // there is nothing to send - the card names the next step
                // (hard rule 7) instead of a consent sheet for unreadable bytes.
                VStack(alignment: .leading, spacing: 6) {
                    Text("We couldn't read that file.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.warn)
                    Text("It may still be downloading from iCloud Drive. In Files, open it once, then pick it again.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineSpacing(1.4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .formCard()
                .accessibilityIdentifier("importSendFileReadFailed")
            }
            ImportPrimaryBar(action: { showingFilePicker = true },
                             label: { Text(L10n.sendFileTitle) })
            Button("Pick a different app") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .item],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            // RV.73: same security-scope discipline as the parse path - the
            // picked URL dies with this handler, so its bytes are copied under
            // the scope before the consent step reads the file later.
            let stager = ImportService.makePickedFileStager()
            switch stager.stage(url, log: AppLog.shared) {
            case .staged(let copy):
                sendFileReadFailed = false
                pickedFileURL = copy
                showingSendFile = true
            case .readFailed:
                sendFileReadFailed = true
            }
        }
        .sheet(isPresented: $showingSendFile) {
            if let fileURL = pickedFileURL {
                SendFileConsentSheet(fileURL: fileURL, dispose: {
                    ImportService.makePickedFileStager().dispose(fileURL)
                })
            }
        }
        #if DEBUG
        .task { seedIfRequested() }
        #endif
    }

    /// PJ.20 DEBUG seed: with `-seedSendFile` a temp file is "picked" and the
    /// consent sheet opens, so the L4 test and screenshot reach the share sheet
    /// without driving the system file picker.
    #if DEBUG
    private func seedIfRequested() {
        guard !didSeed else { return }
        didSeed = true
        guard ProcessInfo.processInfo.arguments.contains("-seedSendFile") else { return }
        let stager = ImportService.makePickedFileStager()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyFuelManager_export.csv")
        try? Data("Date;Odometer;Volume\n1/1/2024;120000;42.5".utf8).write(to: url)
        guard case .staged(let copy) = stager.stage(url, log: nil) else { return }
        pickedFileURL = copy
        showingSendFile = true
    }
    #endif
}

/// The explicit-consent step before the file is shared (PJ.20, docs/ERRORS.md
/// -> Import wizard). The file is attached only after this consent is given:
/// the copy states plainly what the file may contain, and "Share file" is the
/// affirmative act. Nothing is uploaded or queued until then.
///
/// RV.73: `fileURL` is always the staged container copy of the user's pick
/// (the security scope died with the file-picker handler). `dispose` deletes
/// that copy once its use is over - when the share sheet settles, or when this
/// sheet is cancelled - so the user data never outlives the flow (hard rule 8,
/// the "must not outlive its use" promise).
struct SendFileConsentSheet: View {
    let fileURL: URL?
    var dispose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    /// Whether the share sheet was offered. Guards `onDisappear` against the
    /// SwiftUI gotcha where presenting a sheet on top fires the presenter's
    /// `onDisappear`: once sharing has begun, only the share sheet's own
    /// completion may dispose, never the disappearance.
    @State private var didShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.sendFileTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(L10n.sendFileConsent)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.5)
            if let fileURL {
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.action)
                    Text(verbatim: fileURL.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("sendFileFileName")
                }
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.vertical, 12)
                .formCard()
            }
            Spacer()
            ImportPrimaryBar(action: presentShare,
                             label: { Text(L10n.sendFileShare) })
                .accessibilityIdentifier("sendFileShareButton")
            Button("Cancel") {
                dispose?()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .presentationDetents([.medium])
        .onDisappear {
            // Cancelled or swiped away without sharing - dispose only when the
            // share sheet was never offered (its completion handles that path).
            if !didShare { dispose?() }
        }
    }

    /// PJ.20: the actual file rides the share sheet, with the consent sentence
    /// alongside it - never the sentence alone. Presented from the top-most
    /// controller (RV.181), so the consent sheet underneath stays alive while
    /// the destination's UI is up.
    private func presentShare() {
        guard let fileURL else { return }
        didShare = true
        SharePresenter.present(items: [fileURL as Any, L10n.sendFileMessage]) { outcome in
            // Shape only: that the share ended, how, and that the payload was
            // the staged file - never its name, its bytes or a destination app
            // (hard rule 12).
            AppLog.share(operation: "import.sendFile.share", kind: "file",
                         outcome: outcome)
            // The share sheet has read the file (or the user dismissed it);
            // the staged copy has served its purpose either way.
            dispose?()
        }
    }
}
