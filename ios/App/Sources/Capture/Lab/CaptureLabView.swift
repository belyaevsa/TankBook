#if EXPERIMENTS
import SwiftUI
import TankbookCore

/// The Capture Lab, a beta experiment (`BetaExperiment.captureLab`). The owner
/// shoots one scene under every camera preset back to back and compares capture
/// latency, bytes, pixel size and what the reader committed, then picks a
/// production setting by measurement. Reached from About's Experiments section;
/// compiled into Debug and Beta, absent from Release.
struct CaptureLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var controller = CameraController()
    @State private var runner = CaptureLabRunner()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // The shutter sits directly under the preview: shooting means
                    // watching the scene, so both must be on screen at once without
                    // scrolling. The run's settings follow below.
                    VStack(spacing: 12) {
                        preview
                        shutter(proxy)
                        if let message = runner.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.warn)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        controls
                        presetList
                        if !runner.results.isEmpty {
                            resultsSection
                                .id(Self.resultsAnchor)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Theme.Palette.midnight)
                .navigationTitle("Capture lab")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("captureLabCloseButton")
                    }
                }
                .task {
                    controller.start()
                    #if DEBUG
                    applySourceArgument()
                    if ProcessInfo.processInfo.arguments.contains("-captureLabAutoRun") {
                        try? await Task.sleep(for: .milliseconds(500))
                        await runner.run(controller: controller)
                        scrollToResults(proxy)
                    }
                    #endif
                }
            }
        }
    }

    private static let resultsAnchor = "captureLabResults"

    /// Brings the results table into view once a run finishes - the table is
    /// the point of the screen, and it starts below the fold.
    private func scrollToResults(_ proxy: ScrollViewProxy) {
        guard !runner.results.isEmpty else { return }
        withAnimation { proxy.scrollTo(Self.resultsAnchor, anchor: .top) }
    }

    // MARK: - Preview

    private var preview: some View {
        CameraPreview(controller: controller)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1))
            .accessibilityIdentifier("captureLabPreview")
    }

    // MARK: - Source + run controls

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Which pipeline scores the shot", selection: sourceBinding) {
                ForEach(CaptureLabSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("captureLabSourcePicker")

            HStack(spacing: 12) {
                Text("Progress")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text("\(runner.progress)/\(runner.total)")
                    .font(.custom(AppFonts.dinAlternateBold, size: 16))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("captureLabProgress")
                Spacer(minLength: 8)
                if runner.isRunning {
                    ProgressView().controlSize(.small).tint(Theme.Palette.inkSoft)
                }
                if let directory = runner.sessionDirectory {
                    Button {
                        SharePresenter.present(items: [directory])
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.taillight)
                    }
                    .accessibilityIdentifier("captureLabShareButton")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .formCard()
    }

    private var sourceBinding: Binding<CaptureLabSource> {
        Binding(get: { runner.source }, set: { runner.source = $0 })
    }

    // MARK: - Presets

    private var presetList: some View {
        VStack(spacing: 0) {
            SectionEyebrow("Presets")
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(CaptureLabPreset.allCases) { preset in
                    presetRow(preset)
                    if preset != CaptureLabPreset.allCases.last {
                        CardDivider()
                    }
                }
            }
            .formCard()
        }
    }

    private func presetRow(_ preset: CaptureLabPreset) -> some View {
        Toggle(isOn: presetBinding(preset)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: preset.id)
                    .font(.custom(AppFonts.dinAlternateBold, size: 15))
                    .foregroundStyle(Theme.Palette.ink)
                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("captureLabPreset-\(preset.id)")
    }

    private func presetBinding(_ preset: CaptureLabPreset) -> Binding<Bool> {
        Binding(
            get: { runner.selected.contains(preset) },
            set: { on in
                if on { runner.selected.insert(preset) } else { runner.selected.remove(preset) }
            })
    }

    // MARK: - Shutter

    private func shutter(_ proxy: ScrollViewProxy) -> some View {
        Button {
            Task {
                await runner.run(controller: controller)
                scrollToResults(proxy)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(runner.canRun ? Theme.Palette.taillight : Theme.Palette.inkSoft.opacity(0.3))
                Circle()
                    .stroke(Theme.Palette.midnight, lineWidth: 4)
                    .padding(6)
            }
            .frame(width: 76, height: 76)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!runner.canRun)
        .accessibilityLabel("Run")
        .accessibilityIdentifier("captureLabShutterButton")
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Results")
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    ForEach(runner.results, id: \.preset) { result in
                        resultRow(result)
                    }
                }
                .formCard()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            header("Preset", 92)
            header("Capture ms", 78)
            header("Pixels", 116)
            header("Bytes", 84)
            header("Path", 62)
            header("Display", 66)
            header("Rows", 54)
            header("Committed", 86)
            header("Pipeline ms", 84)
            header("Resolved", 76)
            header("Cross-check", 96)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func resultRow(_ result: CaptureLabResult) -> some View {
        HStack(spacing: 0) {
            number(result.preset, 92, identifier: "captureLabResult-\(result.preset)")
            number("\(result.captureMs)", 78)
            number("\(result.width)×\(result.height)", 116)
            number("\(result.bytes)", 84)
            number(result.classifyPath ?? "–", 62)
            symbol(result.isDisplay, 66)
            number("\(result.rows)", 54)
            number("\(result.committedCount)/3", 86)
            number("\(result.pipelineMs)", 84)
            number(result.resolvedFields.map(String.init) ?? "–", 76)
            number(result.crossCheck ?? "–", 96)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Palette.midnight.opacity(0.35))
        .accessibilityElement(children: .contain)
    }

    private func header(_ text: LocalizedStringKey, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .fixedSize()
            .frame(width: width, alignment: .leading)
    }

    private func number(_ text: String, _ width: CGFloat, identifier: String? = nil) -> some View {
        Text(verbatim: text)
            .font(.custom(AppFonts.dinAlternateBold, size: 13))
            .monospacedDigit()
            .foregroundStyle(Theme.Palette.ink)
            .fixedSize()
            .frame(width: width, alignment: .leading)
            .accessibilityIdentifier(identifier ?? "")
    }

    private func symbol(_ on: Bool, _ width: CGFloat) -> some View {
        Image(systemName: on ? "checkmark" : "xmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(on ? Theme.Palette.ok : Theme.Palette.inkSoft)
            .frame(width: width, alignment: .leading)
    }

    #if DEBUG
    /// Screenshot seam: `-captureLabSource receipt` opens the lab scoring the
    /// receipt path, so both pipelines can be screenshotted.
    private func applySourceArgument() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-captureLabSource"),
              arguments.indices.contains(index + 1),
              let source = CaptureLabSource(rawValue: arguments[index + 1]) else { return }
        runner.source = source
    }
    #endif
}
#endif
