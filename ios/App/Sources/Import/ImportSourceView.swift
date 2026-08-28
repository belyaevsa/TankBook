import SwiftUI
import TankbookCore

// Import step 1: the source picker (design/screens/ImportSource.dc.html,
// docs/ERRORS.md -> Import wizard -> "Choosing the source"). The user DECLARES
// the format - the app never sniffs it, because two vendors' CSVs look alike
// and a confident mis-mapping is worse than a question (hard rule 13). The list
// is the transport's `GET /import/formats` response, rendered as-is; a
// hardcoded list would make the server-side parser unselectable and defeat the
// architecture (docs/API.md). Offline is stated here, before the tap.
struct ImportSourceView: View {
    let model: ImportFlowModel
    let onChooseFile: () -> Void
    let onNotSupported: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if model.serverBackedPaused {
                    // P6.18b: under `.required` the parse is withheld (the
                    // server has stopped supporting this build, docs/CONFIG.md)
                    // and the non-dismissible update notice replaces the
                    // picker. Everything else about import stays local.
                    UpdateRequiredNotice()
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        titleBlock
                        formatList
                        notYetBlock
                        notSupportedCard
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                }
            }
            if !model.serverBackedPaused {
                offlineNotice
                bottomBar
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.Palette.dash))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("importSourceClose")
            Spacer()
            Text("Import")
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which app is this file from?")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("importSourceTitle")
            Text("Exports look alike, so we ask instead of guessing. Guessing wrong would import every number in the wrong column.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    // MARK: - The server-driven list

    @ViewBuilder
    private var formatList: some View {
        switch model.formatsState {
        case .loading, .idle:
            VStack(spacing: 8) {
                ProgressView().tint(Theme.Palette.inkSoft)
                Text("Loading supported apps…")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        case .offline, .failed:
            offlineCard
        case .loaded:
            VStack(spacing: 9) {
                ForEach(model.formats, id: \.id) { format in
                    formatRow(format)
                }
            }
            if model.formats.isEmpty {
                Text("Nothing listed yet")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func formatRow(_ format: ImportFormat) -> some View {
        let selected = model.pickedFormat?.id == format.id
        return Button {
            model.selectFormat(format)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .frame(width: 34, height: 34)
                    .background(Theme.Palette.dash.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(L10n.fileKindsLabel(format.fileKinds))
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.body)
                    .foregroundStyle(selected ? Theme.Palette.action : Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(selected ? Theme.Palette.action : Theme.Palette.hairline,
                            lineWidth: selected ? 1.5 : 1)
            )
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("importFormatRow-\(format.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Not yet / not supported

    private var notYetBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Not yet")
            HStack(spacing: 7) {
                chip("Fuelio")
                chip("Drivvo")
                chip("Fuelly")
                chip("Spritmonitor")
                chip("CarScope")
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func chip(_ name: LocalizedStringKey) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Palette.midnight)
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            .clipShape(Capsule())
    }

    /// Hard rule 7: the dead end gets a next step. This is where the corpus
    /// grows - the same ask as the capture notice, with explicit consent.
    private var notSupportedCard: some View {
        Button(action: onNotSupported) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your app isn't here?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Send us the file and we'll add it. Nothing is imported until you confirm.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineSpacing(1.4)
                Text("Send us the file")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.Palette.dash.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.inkSoft.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("importNotSupportedCard")
        .padding(.top, 6)
    }

    // MARK: - Offline

    /// Offline is stated here, not discovered at tap time (docs/ERRORS.md ->
    /// Import wizard): reading these files happens on our server - hard rule
    /// 1's named exception, and the ONLY part of import that needs a
    /// connection.
    private var offlineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Importing needs a connection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Reading the file happens on our server, so this step needs a connection. Everything else in the app keeps working.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
            Button("Retry") {
                Task { await model.loadFormats() }
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.action)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
        .accessibilityIdentifier("importOfflineCard")
        .padding(.top, 6)
    }

    private var offlineNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)
            Text("Reading the file happens on our server, so this step needs a connection.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.vertical, 10)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let failure = model.parseFailure {
                parseErrorCard(failure)
            }
            ImportPrimaryBar(action: onChooseFile,
                             enabled: model.pickedFormat != nil && !model.isParsing) {
                if model.isParsing {
                    ProgressView().tint(.white)
                } else {
                    Text("Choose file")
                }
            }
            .accessibilityIdentifier("importChooseFileButton")
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
    }

    /// A wrong declared source (422) shows the specific message, never a
    /// generic failure (F7) - and the picker is still there to choose again.
    @ViewBuilder
    private func parseErrorCard(_ failure: ImportFlowModel.ParseFailure) -> some View {
        switch failure {
        case .doesNotMatchDeclared(let displayName):
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.doesNotLookLike(displayName: displayName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.warn)
                Text("Pick another app from the list, or send us the file.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .formCard()
            .accessibilityIdentifier("import422Card")
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 10)
        case .transportUnreachable:
            EmptyView()
        case .oversize:
            errorCard("That file is larger than 8 MB – try a smaller export.")
        case .unrecognisedFormat:
            errorCard("We don't recognise that format.")
        case .server:
            errorCard("The server couldn't read the file right now – try again.")
        case .unknown:
            errorCard("We couldn't read that file – try again, or send it to us.")
        }
    }

    private func errorCard(_ message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
            Text("Choose a different app, or try the file again.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .formCard()
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.bottom, 10)
    }
}
