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
            ImportTestSeed.seedDatabaseIfRequested()
            if model == nil, let repository = try? AppStore.repository() {
                model = ImportService.makeModel(repository: repository,
                                                configService: configService)
            }
            if let model {
                await model.loadFormats()
                ImportTestSeed.seedFlowIfRequested(model: model)
            }
            // PJ.20: the send-file consent flow's seed - opens the not-supported
            // sheet so the consent + share sheet render without a real tap.
            if ProcessInfo.processInfo.arguments.contains("-seedSendFile") {
                showingNotSupported = true
            }
        }
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .item],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  let model else { return }
            let preferred = carSelection.selectedVehicle((try? model.repository.liveVehicles()) ?? [])?.id
            model.parse(fileURL: url, preferredVehicleID: preferred)
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
                onBack: { dismiss() })
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
                onImport: {
                    Task {
                        let ok = await model.confirmImport()
                        if ok {
                            toastCenter.show(L10n.importedFillUps(model.commitCount))
                            dismiss()
                        }
                    }
                })
        case .review:
            ImportReviewView(
                model: model,
                onBack: { model.showPreview() },
                onDone: { model.showPreview() })
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
    @State private var showingSendFile = false
    @State private var didSeed = false

    private var supportedNames: String {
        guard let model else { return "" }
        return model.formats.map(\.displayName).joined(separator: ", ")
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
            Spacer()
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
        .presentationDetents([.medium])
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .item],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            pickedFileURL = url
            showingSendFile = true
        }
        .sheet(isPresented: $showingSendFile) {
            SendFileConsentSheet(fileURL: pickedFileURL)
        }
        .task { seedIfRequested() }
    }

    /// PJ.20 DEBUG seed: with `-seedSendFile` a temp file is "picked" and the
    /// consent sheet opens, so the L4 test and screenshot reach the share sheet
    /// without driving the system file picker.
    private func seedIfRequested() {
        guard !didSeed else { return }
        didSeed = true
        guard ProcessInfo.processInfo.arguments.contains("-seedSendFile") else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyFuelManager_export.csv")
        try? Data("Date;Odometer;Volume\n1/1/2024;120000;42.5".utf8).write(to: url)
        pickedFileURL = url
        showingSendFile = true
    }
}

/// The explicit-consent step before the file is shared (PJ.20, docs/ERRORS.md
/// -> Import wizard). The file is attached only after this consent is given:
/// the copy states plainly what the file may contain, and "Share file" is the
/// affirmative act. Nothing is uploaded or queued until then.
struct SendFileConsentSheet: View {
    let fileURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false

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
            ImportPrimaryBar(action: { showingShare = true },
                             label: { Text(L10n.sendFileShare) })
                .accessibilityIdentifier("sendFileShareButton")
            Button("Cancel") {
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
        .sheet(isPresented: $showingShare) {
            // PJ.20: the actual file rides the share sheet, with the consent
            // sentence alongside it - never the sentence alone.
            ActivityView(items: [fileURL as Any, L10n.sendFileMessage])
                .presentationDetents([.medium, .large])
        }
    }
}
