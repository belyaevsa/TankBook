import SwiftUI
import TankbookCore

// Import step 2: the preview gate (design/screens/ImportPreview.dc.html,
// docs/JOURNEYS.md F6a). Nothing is written until the user confirms. The
// figures follow F7's rule, not a progress bar: trust is re-established with
// NUMBERS - the derived consumption is the headline, because a driver knows
// their own average and "8.2 L/100km" reads as right or wrong instantly where
// "220 rows parsed" does not. Every figure here comes from the candidates
// through the SAME engine that computes it after commit (F6a) - the model's
// `summary` is derived from the exact fills `confirmImport` writes.
struct ImportPreviewView: View {
    @Bindable var model: ImportFlowModel
    /// Drives the new-car name's underline (RV.185): visible at rest so the
    /// value reads as typeable, accented while it is being typed.
    @FocusState private var nameFocused: Bool
    let onBack: () -> Void
    let onCancel: () -> Void
    let onChangeCar: () -> Void
    let onShowReview: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ImportHeader(title: Text("Review import"),
                         backLabel: "Back",
                         trailingLabel: "Cancel",
                         onBack: onBack,
                         onTrailing: onCancel)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        intro
                        headlineCard
                        if model.hasDateFormatQuestion {
                            dateFormatCard
                        }
                        if model.hasCurrencyQuestion {
                            currencyCard
                        }
                        if model.hasUnsupportedColumns {
                            unsupportedNoticeCard
                        }
                        figuresCard
                        targetCarCard
                            .id(Self.targetCarAnchor)
                        if let message = model.outOfScopeMessage {
                            outOfScopeCard(message)
                        }
                        if reviewCount > 0 {
                            reviewRow
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                }
                .onAppear {
                    #if DEBUG
                    scrollToTargetCarIfRequested(proxy)
                    #endif
                }
            }
            bottomBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importPreviewScreen")
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Here's what we read")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(model.pickedFileSummary)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Headline

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Consumption this works out to")
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(consumptionText)
                    .font(.system(size: 40, weight: .heavy))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("importPreviewConsumption")
                Text("L/100km")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Text("Does that look like your car? If not, something was read wrong – check the date format or currency.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
    }

    private var consumptionText: String {
        guard let value = model.summary?.consumptionLPer100 else { return "–" }
        return ImportFormatting.consumption(value)
    }

    // MARK: - Figures

    private var figuresCard: some View {
        VStack(spacing: 0) {
            figureRow("Fill-ups", value: "\(model.summary?.fillUpCount ?? 0)")
            CardDivider()
            figureRow("Date range", value: dateRangeText)
            CardDivider()
            figureRow("Odometer", value: odometerText)
            CardDivider()
            figureRow("Total spend", value: totalSpendText, id: "importPreviewTotalSpend")
            CardDivider()
            figureRow("Units & currency", value: unitsCurrencyText)
        }
        .formCard()
    }

    private func figureRow(_ label: LocalizedStringKey, value: String, id: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id ?? "")
    }

    private var dateRangeText: String {
        ImportFormatting.dateRange(model.summary?.firstDate, model.summary?.lastDate)
    }

    private var odometerText: String {
        guard let min = model.summary?.odometerMin, let max = model.summary?.odometerMax else {
            return "–"
        }
        return "\(ImportFormatting.odometer(min)) – \(ImportFormatting.odometer(max)) \(L10n.distanceUnit(model.distanceUnit))"
    }

    private var totalSpendText: String {
        guard let spend = model.summary?.totalSpend, let currency = model.summary?.currency else {
            return "–"
        }
        return ImportFormatting.amount(spend, currency: currency)
    }

    private var unitsCurrencyText: String {
        guard let vehicle = model.targetCar?.vehicleValue else { return "–" }
        return ImportFormatting.unitsCurrency(units: vehicle.units,
                                              currency: model.summary?.currency)
    }

    // MARK: - Target car

    private var targetCarCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionEyebrow("Imports into")
                    // RV.185: a new car's name is editable where the car is
                    // offered, pre-filled with the derived suggestion (hard rule
                    // 13). An existing car is not renamed here - the import must
                    // not rewrite a car the user already owns.
                    if model.targetCarIsNew {
                        TextField("Car name", text: $model.newCarNameDraft)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .focused($nameFocused)
                            .editableValueUnderline(isFocused: nameFocused)
                            .accessibilityIdentifier("importNewCarNameField")
                    } else {
                        Text(targetCarName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .accessibilityIdentifier("importTargetCarName")
                    }
                }
                Spacer(minLength: 8)
                Button(action: onChangeCar) {
                    Text("Change")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("importChangeCarButton")
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.top, 12)
            .padding(.bottom, 11)

            if model.isMerging && model.duplicateCount > 0 {
                CardDivider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warn)
                        .padding(.top, 1)
                    Text(L10n.lookLikeDuplicates(model.duplicateCount))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warn)
                        .lineSpacing(1.4)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.vertical, 11)
                .accessibilityIdentifier("importDuplicateWarning")
            }
        }
        .formCard()
    }

    private var targetCarName: String {
        switch model.targetCar {
        case .existing(let vehicle): return vehicle.name
        case .new(let vehicle): return vehicle.name
        case nil: return "–"
        }
    }

    // MARK: - Partial parse

    private var reviewCount: Int { model.reviewRows.count }

    // MARK: - The F6 questions (PJ.10)

    /// The `dateFormat` question (docs/JOURNEYS.md F6, docs/API.md): the parser
    /// guessed M/D; the same rows may genuinely be D/M, and committing the
    /// guess silently shifts a year of history. Asked once, per file; confirm
    /// stays disabled until it is answered. Answering re-dates the candidates.
    private var dateFormatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow("Some dates could read either way")
                    Text(L10n.dateFormatQuestionSubtitle(model.dateFormatRowCount))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineSpacing(1.4)
                }
            }
            HStack(spacing: 8) {
                if let options = model.dateFormatOptions {
                    ForEach(options, id: \.self) { option in
                        dateFormatOption(option)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importDateFormatQuestion")
    }

    private func dateFormatOption(_ option: String) -> some View {
        let selected = model.dateFormatAnswer == option
        return Button(action: { model.answerDateFormat(option) }) {
            Text(option)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.Palette.midnight : Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Theme.Palette.taillight : Theme.Palette.midnight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.clear : Theme.Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("importDateFormatOption-\(option)")
    }

    /// The currency question (RV.113, docs/SCHEMA.md): a file with no currency
    /// column cannot say what its amounts are in, so the wizard asks - offering
    /// the destination car's home currency as the default the user can change
    /// (hard rule 13, hard rule 3). Asked once per file, never per row.
    private var currencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "banknote")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow("Currency for these amounts")
                    Text(L10n.currencyQuestionSubtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineSpacing(1.4)
                }
            }
            Menu {
                ForEach(AddVehicleSupport.currencyOptions, id: \.self) { code in
                    Button { model.answerCurrency(code) } label: {
                        HStack {
                            Text(AddVehicleSupport.currencyLabel(for: code))
                            if code == (model.currencyAnswer ?? model.defaultCurrency) {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("importCurrencyOption-\(code.rawValue)")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(AddVehicleSupport.currencyLabel(for: model.currencyAnswer ?? model.defaultCurrency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.Palette.midnight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Palette.hairline, lineWidth: 1)
                )
            }
            .accessibilityIdentifier("importCurrencyPicker")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importCurrencyQuestion")
    }

    /// A file whose rows are deliberately unmapped (income, reminders) says so
    /// here instead of silently showing nothing (docs/API.md).
    private func outOfScopeCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
        .accessibilityIdentifier("importOutOfScopeNotice")
    }

    /// RV.116: say what is NOT coming in, at the gate where nothing is written
    /// yet. Every entry is a column the format has no home for with the number
    /// of rows that carried a value in it - the count is what turns "driver is
    /// not imported" (trivia) into a decision. It is a notice, never an error,
    /// and it never gates Continue. The names are server-declared, so a column
    /// this build has never heard of still renders.
    private var unsupportedNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow("Not imported")
                    Text("Some columns in this file aren't imported. The file stays on your phone if you need them.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineSpacing(1.4)
                }
            }
            ForEach(model.unsupportedColumns, id: \.column) { item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.column)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer(minLength: 8)
                    Text(L10n.unsupportedColumnRows(item.rowCount))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("importUnsupportedColumn-\(item.column)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importUnsupportedNotice")
    }

    private var reviewRow: some View {
        Button(action: onShowReview) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.rowsNeedALook(model.reviewRows.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(L10n.otherRowsReady(model.reviewRows.count, total: model.summary?.fillUpCount ?? 0))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                Text("Review")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .padding(14)
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("importReviewRowsRow")
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 8) {
            ImportPrimaryBar(action: onImport,
                             enabled: model.canConfirm && !model.didConfirm) {
                Text(L10n.importFillUps(model.commitCount))
            }
            .accessibilityIdentifier("importConfirmButton")
            Text("Nothing has been saved yet. Cancel leaves your garage untouched.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.bottom, 12)
        }
    }
}

/// The preview's screenshot seam, kept in an extension so the view's own body
/// stays inside the type-length ceiling.
extension ImportPreviewView {
    /// The target-car card's scroll anchor. It sits below the figures table, so
    /// on a phone frame it is off-screen at rest - which is why the RV.185 name
    /// field needed a hook to be photographable at all.
    static var targetCarAnchor: String { "importPreviewTargetCar" }

    #if DEBUG
    /// Screenshot hook (RV.185): `-importScrollToTargetCar` parks the preview on
    /// the "Imports into" card, where a new car's editable name lives. Follows
    /// `-homeScrollToExcludedFootnote`'s shape - screenshot-only, no test drives
    /// it, because `simctl` cannot scroll.
    func scrollToTargetCarIfRequested(_ proxy: ScrollViewProxy) {
        guard ProcessInfo.processInfo.arguments.contains("-importScrollToTargetCar") else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            proxy.scrollTo(Self.targetCarAnchor, anchor: .center)
        }
    }
    #endif
}
