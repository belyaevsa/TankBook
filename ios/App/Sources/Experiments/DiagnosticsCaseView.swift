#if EXPERIMENTS
import SwiftUI
import TankbookCore
import UIKit

/// The "Send diagnostics" sheet (docs/SCREENMAP.md -> Send diagnostics): what
/// goes, the tap that sends it, and the id to share. Every failure names its
/// next step and leaves the sheet ready to send again (hard rule 7).
struct DiagnosticsCaseView: View {
    @State private var model: DiagnosticsCaseModel
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    init(model: DiagnosticsCaseModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if case .sent(let receipt) = model.state {
                        sent(receipt)
                    } else {
                        compose
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, 16)
            }
            .background(Theme.Palette.midnight)
            .navigationTitle("Send diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("diagnosticsCaseCloseButton")
                }
            }
            .task {
                await model.load()
                #if DEBUG
                // Screenshot seam: `simctl` cannot tap Send.
                if ProcessInfo.processInfo.arguments.contains("-diagnosticsCaseAutoSend") { await model.submit() }
                #endif
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Compose

    private var compose: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sends this app's log from the last 24 hours and your recent scans to Tankbook. You get an ID to pass on; it's kept 30 days.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                row(label: Text("Log"), value: Text("\(model.logLineCount) lines"))
                Divider().overlay(Theme.Palette.hairline)
                if model.scans.isEmpty {
                    row(label: Text("Recent scans"), value: Text("None yet"))
                } else {
                    scansToggle
                }
            }
            .formCard()
            seeLog
            if case .failed(let error) = model.state {
                failure(error)
            }
            sendButton
        }
    }

    private var scansToggle: some View {
        Toggle(isOn: $model.includeScans) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent scans")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(model.scans.count) photos with what was read from them")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .tint(Theme.Palette.taillight)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("diagnosticsCaseScansToggle")
    }

    private var seeLog: some View {
        NavigationLink {
            logPreview
        } label: {
            HStack {
                Text("See the log")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .formCard()
        }
        .buttonStyle(.plain)
        .disabled(model.state == .loading)
        .accessibilityIdentifier("diagnosticsCaseSeeLog")
    }

    private func row(label: Text, value: Text) -> some View {
        HStack {
            label
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            value
                .font(.custom(AppFonts.dinAlternateBold, size: 17))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sendButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            HStack(spacing: 8) {
                if model.state == .sending { ProgressView().controlSize(.small) }
                Text(model.state == .sending ? "Sending" : "Send")
            }
            .font(.body.weight(.bold))
            .foregroundStyle(Theme.Palette.midnight)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.Palette.taillight)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(model.state == .loading || model.state == .sending)
        .accessibilityIdentifier("diagnosticsCaseSendButton")
    }

    private func failure(_ error: DebugCaseError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Text(message(error))
                .font(.footnote)
                .foregroundStyle(Theme.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("diagnosticsCaseFailure")
    }

    private func message(_ error: DebugCaseError) -> LocalizedStringKey {
        switch error {
        case .offline: "No connection – connect and send again."
        case .rateLimited: "Sent too often – try again in a minute."
        case .tooLarge: "Too large to send – turn off Recent scans and send again."
        case .failed: "Couldn't send – try again."
        }
    }

    private var logPreview: some View {
        ScrollView {
            Text(verbatim: model.logText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.screenMargin)
                .accessibilityIdentifier("diagnosticsCaseLogText")
        }
        .background(Theme.Palette.midnight)
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sent

    private func sent(_ receipt: DebugCaseReceipt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sent. Pass this ID on so the diagnostics can be found:")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: receipt.caseId)
                .font(.custom(AppFonts.dinAlternateBold, size: 40))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .formCard()
                .accessibilityIdentifier("diagnosticsCaseId")
            Button {
                UIPasteboard.general.string = receipt.caseId
                copied = true
            } label: {
                Text(copied ? "Copied" : "Copy ID")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("diagnosticsCaseCopyButton")
            Text("Kept until \(receipt.expiresAt.formatted(date: .abbreviated, time: .omitted)), then deleted.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }
}
#endif
