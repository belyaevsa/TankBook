import SwiftUI
import TankbookCore

/// A diagnostics log shown in full, however long. One `Text` holding the whole
/// log stops drawing past a size SwiftUI will lay out (a log of about 900 KB
/// rendered as an empty screen), so the text is drawn in chunks of lines inside
/// a lazy stack, which only lays out what is on screen. To accessibility it is
/// still one static text carrying every byte - the text that is sent.
struct LogTextView: View {
    let identifier: String
    private let text: String
    private let chunks: [String]

    /// Lines per drawn block: small enough that any one block lays out fast,
    /// large enough that a long log is a few hundred views, not tens of thousands.
    static let linesPerChunk = 200

    init(text: String, identifier: String) {
        self.text = text
        self.identifier = identifier
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        chunks = stride(from: 0, to: lines.count, by: Self.linesPerChunk).map {
            lines[$0..<min($0 + Self.linesPerChunk, lines.count)].joined(separator: "\n")
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(chunks.indices, id: \.self) { index in
                Text(verbatim: chunks[index])
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.Palette.ink)
                    .textSelection(.enabled)
                    .lineSpacing(1.2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier(identifier)
    }
}
