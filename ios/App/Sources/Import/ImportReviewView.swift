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
        for row in model.reviewRows where row.fill != nil || row.nonFuel != nil {
            model.leaveOut(sourceRow: row.sourceRow)
        }
    }

    private var bottomBar: some View {
        ImportPrimaryBar(action: onDone) {
            Text("Done · back to preview")
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
            if case .timelineConflict = row.kind {
                ImportTimelineDetail(row: row, distanceUnit: model.distanceUnit(for: row))
            }
            if case .consumptionOutlier(let per100, _) = row.kind {
                // The CHECK 5 outlier is a different error from a timeline
                // break: the fields to question are the litres and the
                // odometer, so the next step is the F9a check vocabulary the
                // edit screen uses (RV.229, hard rule 7). "Check litres"
                // reveals the source line the litres came from; "Check
                // odometer" opens the row's odometer editor.
                ImportConsumptionDetail(
                    per100: per100,
                    unit: model.headlineUnit(for: row),
                    onCheckLiters: { showingRawLine = true },
                    onCheckOdometer: { showingOdometerEditor = true })
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
            let symbol = AddVehicleSupport.moneySymbol(for: currency ?? .eur)
            let value = ImportFormatting.decimal(abs(offBy), fractionDigits: 2)
            return L10n.offBy(amount: "\(value) \(symbol)")
        case .timelineConflict: return L10n.localize("Breaks the timeline")
        case .consumptionOutlier: return L10n.localize("Unusual consumption")
        case .noFuel: return nonFuelBadgeText
        case .unmappable, .unparsed: return L10n.localize("Couldn't read this row")
        }
    }

    /// "Service" / "Expense" - the `.noFuel` row names what it is, so the
    /// "import as what it is" action is legible (F6b, PJ.9).
    private var nonFuelBadgeText: String {
        switch row.nonFuel {
        case .service: return L10n.localize("Service")
        case .expense: return L10n.localize("Expense")
        case nil: return L10n.localize("No fuel on this row")
        }
    }

    private var badgeColor: Color {
        switch row.kind {
        case .missingOdometer, .crossCheckMismatch, .timelineConflict,
             .consumptionOutlier, .unmappable, .unparsed:
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
            } else {
                // The original line is genuinely absent (the client and the
                // server disagreed on row numbering, or the file is gone). Say
                // so in words - never a serialized candidate (P6.15c).
                Text(L10n.originalLineUnavailable)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Theme.Palette.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        default:
            if let fill = row.fill {
                fieldGrid(fill)
            } else if let nonFuel = row.nonFuel {
                nonFuelGrid(nonFuel)
            }
        }
    }

    /// A `.noFuel` row's fields (PJ.9): the service/expense renders as parsed,
    /// labelled fields - date, total, odometer, note - so "import as what it
    /// is" is a decision about data the user has seen (F6b), never a raw line.
    @ViewBuilder
    private func nonFuelGrid(_ nonFuel: ImportReviewRow.NonFuel) -> some View {
        let record = nonFuelRecord(nonFuel)
        HStack(spacing: 8) {
            ImportFieldCell(label: "Date", value: ImportFormatting.day(record.date), marked: false)
            if let amount = record.money?.amount {
                ImportFieldCell(label: "Total",
                                value: ImportFormatting.decimal(amount, fractionDigits: 2),
                                marked: false)
            }
            if let odometer = record.odometer {
                ImportFieldCell(label: "Odometer",
                                value: "\(ImportFormatting.odometer(odometer)) "
                                    + L10n.distanceUnit(model.distanceUnit(for: row)),
                                marked: false)
            } else {
                // A blank stays a blank - never `0` (F6b).
                ImportFieldCell(label: "Odometer",
                                value: "– \(L10n.distanceUnit(model.distanceUnit(for: row)))",
                                marked: false)
            }
            if let note = record.note, !note.isEmpty {
                ImportFieldCell(label: "Note", value: note, marked: false)
            }
        }
    }

    /// The service/expense's display fields, extracted outside the `@ViewBuilder`
    /// so the switch is data, never a builder block.
    private func nonFuelRecord(_ nonFuel: ImportReviewRow.NonFuel) -> NonFuelFields {
        switch nonFuel {
        case .service(let service):
            return NonFuelFields(date: service.date, money: service.money,
                                 odometer: service.odometer, note: service.note)
        case .expense(let expense):
            return NonFuelFields(date: expense.date, money: expense.money,
                                 odometer: expense.odometer,
                                 note: expense.note?.isEmpty == false ? expense.note : expense.title)
        }
    }

    /// The display fields one non-fuel row contributes to the review grid.
    private struct NonFuelFields {
        let date: Date
        let money: Money?
        let odometer: Int?
        let note: String?
    }

    @ViewBuilder
    private func fieldGrid(_ fill: FillUp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let station = row.stationName, !station.isEmpty {
                ImportStationCell(name: station)
            }
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
                                   distanceUnit: model.distanceUnit(for: row),
                                   isEditing: showingOdometerEditor,
                                   text: $odometerText, onSubmit: commitOdometer,
                                   marked: odometerMarked)
                if row.kind == .noFuel, let note = fill.note, !note.isEmpty {
                    ImportFieldCell(label: "Note", value: note, marked: false)
                }
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

    /// The PJ.11 timeline row marks the ODOMETER (the field that broke the
    /// order) - F6b: only the broken field is marked.
    private var odometerMarked: Bool {
        if case .timelineConflict = row.kind { return true }
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

    // MARK: - Actions

    /// The row's two next steps (hard rule 7) plus the "Original row" reveal.
    /// `ViewThatFits` stacks the actions when RU's 20-30% expansion would
    /// hyphenate «Исправить / Импортировать как есть / Пропустить» mid-word on
    /// one line (P6.15b); a stacked action is still a named next step.
    private var actions: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            toggleActions
            Spacer(minLength: 0)
            Text("Original row")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
                .onTapGesture { showingRawLine.toggle() }
        }
        .padding(.top, 10)
    }

    /// The deciding actions (primary + "Import as-is" + "Leave out"): one line
    /// when it fits, stacked when it does not. The compact candidate measures at
    /// its ideal width (`.fixedSize`) so a too-wide row is rejected, not squeezed.
    @ViewBuilder
    private var toggleActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                primaryAction
                if showsImportAsIs {
                    importAsIs
                }
                leaveOut
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                primaryAction
                if showsImportAsIs {
                    importAsIs
                }
                leaveOut
            }
        }
    }

    /// "Import as-is" applies where the row is committable as-is - a cross-check
    /// mismatch or a PJ.11 timeline conflict (hard rule 13); a missing odometer
    /// has no "as-is".
    private var showsImportAsIs: Bool {
        if case .crossCheckMismatch = row.kind { return true }
        if case .timelineConflict = row.kind { return true }
        if case .consumptionOutlier = row.kind { return true }
        return false
    }

    private var importAsIs: some View {
        Text("Import as-is")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .onTapGesture { model.keep(sourceRow: row.sourceRow) }
    }

    private var leaveOut: some View {
        Text("Leave out")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSkipped ? Theme.Palette.action : Theme.Palette.inkSoft)
            .onTapGesture { model.leaveOut(sourceRow: row.sourceRow) }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch row.kind {
        case .missingOdometer, .timelineConflict:
            if showingOdometerEditor {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .onTapGesture { commitOdometer() }
            } else {
                Text(primaryActionLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .onTapGesture {
                        odometerText = row.fill?.odometer.map(String.init) ?? ""
                        showingOdometerEditor = true
                    }
            }
        case .crossCheckMismatch:
            if showingTotalEditor {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .onTapGesture { commitTotal() }
            } else {
                Text("Fix")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .onTapGesture {
                        totalText = row.fill?.money.map { ImportFormatting.decimal($0.amount, fractionDigits: 2) } ?? ""
                        showingTotalEditor = true
                    }
            }
        case .noFuel:
            if row.nonFuel != nil {
                Text(nonFuelActionLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSkipped ? Theme.Palette.inkSoft : Theme.Palette.action)
                    .onTapGesture { model.keep(sourceRow: row.sourceRow) }
            }
        case .unmappable, .unparsed:
            EmptyView()
        case .consumptionOutlier:
            // The next steps are the F9a check chips in the consumption detail
            // above; a second primary action here would duplicate them.
            EmptyView()
        }
    }

    /// A missing odometer says "Add odometer"; a timeline conflict says "Fix" -
    /// both open the odometer editor, the one field the row needs a person on.
    private var primaryActionLabel: String {
        if case .timelineConflict = row.kind { return L10n.localize("Fix") }
        return L10n.localize("Add odometer")
    }

    /// "Import as service" / "Import as expense" - the `.noFuel` row's deciding
    /// action (PJ.9). It KEEPS the row (idempotent), and only "Leave out" skips
    /// it, so the record is never dropped by the action that names keeping it.
    private var nonFuelActionLabel: String {
        switch row.nonFuel {
        case .service: return L10n.importAsService
        case .expense: return L10n.importAsExpense
        case nil: return ""
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
            // Never a serialized candidate here either (P6.15c): the line is
            // absent, so say so in words.
            Text(L10n.originalLineUnavailable)
        }
    }
}
