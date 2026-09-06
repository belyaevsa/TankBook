import SwiftUI
import TankbookCore

// Import step 1: the source picker (design/screens/ImportSource.dc.html,
// docs/ERRORS.md -> Import wizard -> "Choosing the source"). The user DECLARES
// the format - the app never sniffs it, because two vendors' CSVs look alike
// and a confident mis-mapping is worse than a question (hard rule 13). The list
// is the transport's `GET /v1/v1/import/formats` response, rendered as-is; a
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
            if !model.serverBackedPaused && !showsParseErrorCard {
                offlineNotice
            }
        }
        // PR.6b: the bottom bar is anchored, not grown into. As the last child
        // of a plain VStack its lower content (the parsing Cancel) laid out
        // where the tab bar is once the phantom bottom safe area appears - the
        // affordance existed for the test and not for the user (hard rule 7).
        // `safeAreaInset(edge: .bottom)` reserves the space instead of growing
        // into it - the anchoring ConfirmManual's save bar has always used.
        .safeAreaInset(edge: .bottom) {
            if !model.serverBackedPaused {
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
        case .offline:
            offlineCard
        case .contractError:
            loadErrorCard(
                title: Text("We couldn't read the list of apps"),
                message: Text("The app and server don't match – try again, and update Tankbook if it keeps happening."),
                identifier: "importContractErrorCard")
        case .serverError:
            loadErrorCard(
                title: Text("The server couldn't load the list"),
                message: Text("It's on our side – try again in a moment."),
                identifier: "importServerErrorCard")
        case .failed:
            loadErrorCard(
                title: Text("We couldn't load the list"),
                message: Text("Something went wrong – try again in a moment."),
                identifier: "importLoadFailedCard")
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
        return VStack(spacing: 0) {
            Button {
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
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("importFormatRow-\(format.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])

            // PJ.33: "How to export" - the per-source export guide, on the row
            // itself. J2's switcher is anxious about the export step ("their UIs
            // hide export"), and hard rule 7: a link must point at a page that
            // exists, so this renders only when the wire carries a `helpUrl`.
            if let helpUrl = format.helpUrl, let url = URL(string: helpUrl) {
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                helpLink(url, identifier: "importFormatHelp-\(format.id)")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(selected ? Theme.Palette.action : Theme.Palette.hairline,
                        lineWidth: selected ? 1.5 : 1)
        )
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    /// The shared "How to export" link into the source app's guide page
    /// (PJ.33) - defined in the `ImportSourceView` extension below, out of this
    /// struct body, so the type stays under the lint ceiling.

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

    /// A non-offline failure to load the supported-app list, each with its own
    /// honest message and its own Retry (RV.68). These exist so a server error,
    /// a client/server contract break or an unknown failure never render as
    /// "Importing needs a connection" - the offline card is reserved for a
    /// genuine connectivity failure, and a wrong next step ("check your
    /// connection") is worse than none (hard rule 7).
    private func loadErrorCard(title: Text, message: Text,
                               identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            message
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
        .accessibilityIdentifier(identifier)
        .padding(.top, 6)
    }

    /// True when the bottom bar shows a parse-error card (RV.80). The standing
    /// offline notice yields to it - the error names its own next step (hard
    /// rule 7), and showing BOTH doubles the fixed chrome below the ScrollView,
    /// which is how RU (20-30% longer text) pushed the dead-end card's action
    /// below the fold and dropped it from the screen. `.transportUnreachable`
    /// renders NO card - the standing notice IS its surface - so it stays.
    private var showsParseErrorCard: Bool {
        guard let failure = model.parseFailure else { return false }
        if case .transportUnreachable = failure { return false }
        return true
    }

    /// Offline is stated here, not discovered at tap time (docs/ERRORS.md ->
    /// Import wizard): reading these files happens on our server - hard rule
    /// 1's named exception, and the ONLY part of import that needs a
    /// connection. It is the default bottom strip; a parse-error card (with
    /// its own message and next step) takes its place while shown.
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
        .accessibilityIdentifier("importServerNotice")
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
                    // PR.6b: a spinner with no text tells the user nothing
                    // about what is happening - the parse state is legible on
                    // the bar itself, never only through the Cancel.
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.Palette.inkSoft)
                        Text("Reading file…")
                    }
                } else {
                    Text("Choose file")
                }
            }
            .accessibilityIdentifier("importChooseFileButton")
            .padding(.bottom, 12)
            .padding(.top, 6)
            if model.isParsing {
                // PR.6: the parse is the one part of import that needs the
                // connection (hard rule 9's exception), and it can sit on a
                // half-connected radio for the upload budget. The user must be
                // able to stop it (hard rule 7 - the next step exists).
                // PR.6b: the Cancel's visibility is asserted by frame, not by
                // existence - `isHittable` does not model occlusion.
                Button {
                    model.cancelParse()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("importCancelButton")
                .padding(.bottom, 12)
            }
        }
    }

    /// A wrong declared source (422) shows the specific message, never a
    /// generic failure (F7) - and the picker is still there to choose again.
    @ViewBuilder
    private func parseErrorCard(_ failure: ImportFlowModel.ParseFailure) -> some View {
        switch failure {
        case .doesNotMatchDeclared(let displayName):
            VStack(alignment: .leading, spacing: 8) {
                // PJ.33: the card identifier sits on the message block only -
                // a container identifier propagates to descendants and would
                // override the link's own, making `import422Help` unreachable
                // (the accessibility tree proved it).
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.doesNotLookLike(displayName: displayName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.warn)
                    Text("Pick another app from the list, or send us the file.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .accessibilityIdentifier("import422Card")
                // PJ.33: this is where a stuck user sits - the declared source
                // rejected their file. "How to export" is the next step that
                // EXISTS (hard rule 7): the guide page tells them what a real
                // export looks like before they try again.
                if let helpUrl = model.pickedFormat?.helpUrl,
                   let url = URL(string: helpUrl) {
                    helpLink(url, identifier: "import422Help")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .formCard()
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 10)
        case .inconsistentDates:
            // RV.85: an inconsistent file - rows proving M/D and rows proving
            // D/M - has no single answer for the dateFormat question to offer,
            // so it is its own message naming its next step, never a question
            // the user cannot answer correctly. The card body lives in an
            // extension so this struct stays under the lint ceiling.
            inconsistentDatesCard
        case .transportUnreachable:
            EmptyView()
        case .couldNotRead:
            // RV.73: the file could not be READ locally - the bytes never left
            // the device, so no parse was attempted. Distinct from a parse
            // rejection, whose next step is re-uploading or another app: for an
            // unreadable file the fix is the file itself (still downloading
            // from iCloud, moved, permission), and re-picking IS the next step
            // (hard rule 7) - "send us the file" would fail the same way.
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("We couldn't read that file.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.warn)
                    Text("It may still be downloading from iCloud Drive. In Files, open it once, then pick it again.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineSpacing(1.4)
                }
                .accessibilityIdentifier("importReadFailedCard")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .formCard()
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 10)
        case .oversize:
            errorCard("That file is larger than 8 MB – try a smaller export.")
        case .unrecognisedFormat:
            errorCard("We don't recognise that format.")
        case .server:
            errorCard("The server couldn't read the file right now – try again.")
        case .unknown:
            errorCard("We read the file, but couldn't process it. Try again, or send us the file.")
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

// MARK: - The "How to export" link and the inconsistent-dates card (RV.85)

extension ImportSourceView {
    /// The shared "How to export" link into the source app's guide page
    /// (PJ.33). `Text` is a literal so the label localises (never a `String`).
    fileprivate func helpLink(_ url: URL, identifier: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                Text("How to export")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.Palette.action)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .accessibilityIdentifier(identifier)
    }

    /// The mixed-date-order file's own card (RV.85). Lives in an extension so
    /// `parseErrorCard`'s switch and this struct stay under the lint ceilings.
    fileprivate var inconsistentDatesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This file mixes two date formats.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
            Text("Some dates only read one way, others the other way.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
            Text("Fix the dates in the export, then pick the file again.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .formCard()
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.bottom, 10)
        .accessibilityIdentifier("importInconsistentDatesCard")
    }
}
