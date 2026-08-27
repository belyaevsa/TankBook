import SwiftUI
import TankbookCore

// Import step 2b: the rows that need a look (design/screens/ImportReview.dc.html,
// docs/JOURNEYS.md F6b). Partial parse is the goal, so this is a normal
// outcome, not a failure screen: no red, and the import stays live behind it.
// Fields are PARSED AND LABELLED, never raw CSV - the server mapped most of the
// row, so only the field that is wrong is marked, and a missing value stays
// blank, never `0` (the Confirm-sheet rule). The original line lives behind
// "Original row" for the rarer case where the MAPPING is wrong.
struct ImportReviewView: View {
    let model: ImportFlowModel
    let onBack: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ImportHeader(title: Text(L10n.rowsNeedALook(model.reviewRows.count)),
                         backLabel: "Back",
                         trailingLabel: "Skip all",
                         onBack: onBack,
                         onTrailing: skipAll)
            Text(L10n.rowsReadyIntro(ready: model.summary?.readyCount ?? 0,
                                     review: model.reviewRows.count))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.reviewRows) { row in
                        ImportReviewRowView(row: row, model: model)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            bottomBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importReviewScreen")
    }

    private func skipAll() {
        for row in model.reviewRows where row.fill != nil {
            if !model.isSkipped(sourceRow: row.sourceRow) {
                model.toggleSkipped(sourceRow: row.sourceRow)
            }
        }
    }

    private var bottomBar: some View {
        ImportPrimaryBar(action: onDone) {
            Text("Done · back to review")
        }
        .accessibilityIdentifier("importReviewDoneButton")
        .padding(.vertical, 12)
    }
}

// MARK: - One review row

/// A single review row: the parsed labelled fields, the one field that is
/// wrong marked, and both next steps named (hard rule 7).
private struct ImportReviewRowView: View {
    let row: ImportReviewRow
    let model: ImportFlowModel

    @State private var showingOdometerEditor = false
    @State private var showingTotalEditor = false
    @State private var odometerText = ""
    @State private var totalText = ""
    @State private var showingRawLine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            fields
            if case .crossCheckMismatch = row.kind {
                detailLine
            }
            actions
            if showingRawLine, row.rawLine != nil {
                rawLineView
            }
        }
        .padding(14)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importReviewRow-\(row.sourceRow)")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            Text(badgeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(badgeColor)
        }
        .padding(.bottom, 10)
    }

    private var title: String {
        guard let fill = row.fill else {
            return L10n.rowLabel(sourceRow: row.sourceRow)
        }
        let day = ImportFormatting.day(fill.date)
        guard let note = fill.note, !note.isEmpty else { return day }
        return "\(day) · \(note)"
    }

    private var badgeText: String {
        switch row.kind {
        case .missingOdometer: return L10n.localize("Odometer missing")
        case .crossCheckMismatch(let offBy):
            let symbol = AddVehicleSupport.currencySymbol(for: currency ?? .eur)
            let value = ImportFormatting.decimal(abs(offBy), fractionDigits: 2)
            return L10n.offBy(amount: symbol.isEmpty ? value : "\(value) \(symbol)")
        case .noFuel: return L10n.localize("No fuel on this row")
        case .unmappable, .unparsed: return L10n.localize("Couldn't read this row")
        }
    }

    private var badgeColor: Color {
        switch row.kind {
        case .missingOdometer, .crossCheckMismatch, .unmappable, .unparsed:
            return Theme.Palette.warn
        case .noFuel:
            return Theme.Palette.inkSoft
        }
    }

    private var currency: CurrencyCode? {
        row.fill?.money?.currency ?? model.summary?.currency
    }

    // MARK: Fields

    @ViewBuilder
    private var fields: some View {
        switch row.kind {
        case .unmappable, .unparsed:
            if let raw = row.rawLine {
                Text(raw)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Theme.Palette.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        default:
            if let fill = row.fill {
                fieldGrid(fill)
            }
        }
    }

    @ViewBuilder
    private func fieldGrid(_ fill: FillUp) -> some View {
        HStack(spacing: 8) {
            if let volume = fill.volumeL as Double? {
                ImportFieldCell(label: "Litres",
                                value: ImportFormatting.decimal(Decimal(volume), fractionDigits: 2),
                                marked: volumeMarked)
            }
            if let price = fill.unitPrice {
                ImportFieldCell(label: "Price/L",
                                value: ImportFormatting.decimal(price, fractionDigits: 3),
                                marked: priceMarked)
            }
            if let amount = fill.money?.amount {
                ImportFieldCell(label: "Total",
                                value: ImportFormatting.decimal(amount, fractionDigits: 2),
                                marked: false)
            } else if case .crossCheckMismatch = row.kind, showingTotalEditor {
                ImportTotalEditorCell(text: $totalText, onSubmit: commitTotal)
            }
            ImportOdometerCell(fill: fill, sourceRow: row.sourceRow,
                               distanceUnit: model.distanceUnit,
                               isEditing: showingOdometerEditor,
                               text: $odometerText, onSubmit: commitOdometer)
            if row.kind == .noFuel, let note = fill.note, !note.isEmpty {
                ImportFieldCell(label: "Note", value: note, marked: false)
            }
        }
    }

    private var volumeMarked: Bool {
        if case .crossCheckMismatch = row.kind { return true }
        return false
    }

    private var priceMarked: Bool {
        if case .crossCheckMismatch = row.kind { return true }
        return false
    }

    // MARK: Detail

    private var detailLine: some View {
        let text: String
        if let fill = row.fill, let amount = fill.money?.amount, let price = fill.unitPrice {
            let computed = Decimal(fill.volumeL) * price
            text = L10n.crossCheckDetail(volume: ImportFormatting.decimal(Decimal(fill.volumeL), fractionDigits: 2),
                                         price: ImportFormatting.decimal(price, fractionDigits: 3),
                                         computed: ImportFormatting.decimal(computed, fractionDigits: 2),
                                         fileTotal: ImportFormatting.decimal(amount, fractionDigits: 2))
        } else {
            text = ""
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .lineSpacing(1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 16) {
            primaryAction
            if case .crossCheckMismatch = row.kind {
                Text("Import as-is")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .onTapGesture { model.toggleSkipped(sourceRow: row.sourceRow) }
            }
            Text("Leave out")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSkipped ? Theme.Palette.headlight : Theme.Palette.inkSoft)
                .onTapGesture { model.toggleSkipped(sourceRow: row.sourceRow) }
            Spacer(minLength: 0)
            Text("Original row")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
                .onTapGesture { showingRawLine.toggle() }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch row.kind {
        case .missingOdometer:
            if showingOdometerEditor {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .onTapGesture { commitOdometer() }
            } else {
                Text("Add odometer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .onTapGesture {
                        odometerText = row.fill?.odometer.map(String.init) ?? ""
                        showingOdometerEditor = true
                    }
            }
        case .crossCheckMismatch:
            if showingTotalEditor {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .onTapGesture { commitTotal() }
            } else {
                Text("Fix")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .onTapGesture {
                        totalText = row.fill?.money.map { ImportFormatting.decimal($0.amount, fractionDigits: 2) } ?? ""
                        showingTotalEditor = true
                    }
            }
        case .noFuel, .unmappable, .unparsed:
            EmptyView()
        }
    }

    private var isSkipped: Bool { model.isSkipped(sourceRow: row.sourceRow) }

    // MARK: Edits

    private func commitOdometer() {
        let digits = OdometerFormat.ungrouped(odometerText).trimmingCharacters(in: .whitespaces)
        model.setOdometer(Int(digits), for: row.sourceRow)
        showingOdometerEditor = false
    }

    private func commitTotal() {
        guard let index = model.reviewRows.firstIndex(where: { $0.sourceRow == row.sourceRow }),
              let amount = Decimal(string: totalText.replacingOccurrences(of: ",", with: "."),
                                   locale: Locale(identifier: "en_US_POSIX")) else {
            showingTotalEditor = false
            return
        }
        model.setTotal(amount, for: row.sourceRow)
        showingTotalEditor = false
    }

    private var rawLineView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Original row")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.inkSoft)
            // Split, never `Text(raw ?? "–")`: a coalesced String would render
            // the fallback in English (the recorded Text(_: String) trap).
            rawText
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .padding(.top, 8)
    }

    @ViewBuilder
    private var rawText: some View {
        if let raw = row.rawLine {
            Text(raw)
        } else {
            Text("–")
        }
    }
}
