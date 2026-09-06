import SwiftUI
import TankbookCore

// Import step 1b: the multi-car mapping gate (RV.86 - no artboard, built from
// the wizard's own vocabulary: ImportHeader / ImportPrimaryBar, the figures-row
// style of ImportPreviewView, the destination-row idiom of ImportTargetCarSheet).
// Shown ONLY when the parse exposes more than one distinct source car. Each
// source car gets a card: its OWN row count, odometer span and date range, and
// an explicit destination - leave out / a new car / an existing garage car.
// The gate's Continue stays disabled until every car is decided (hard rule 13:
// the wizard never guesses a mapping and never funnels into the pre-selected
// car), and committing stays the ONE write on the model.

struct ImportCarsView: View {
    let model: ImportFlowModel
    let onBack: () -> Void
    let onCancel: () -> Void
    let onShowReview: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ImportHeader(title: Text(L10n.importCarsTitle),
                         backLabel: "Back",
                         trailingLabel: "Cancel",
                         onBack: onBack,
                         onTrailing: onCancel)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    intro
                    ForEach(Array(model.carPlan.enumerated()), id: \.element.id) { index, _ in
                        ImportCarMappingCard(model: model, index: index)
                    }
                    if !model.reviewRows.isEmpty {
                        reviewRow
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
            }
            bottomBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importCarsScreen")
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.importCarsTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(L10n.importCarsIntro(model.sourceCars.count))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
            Text(L10n.fromFileNothingSaved(fileName: model.pickedFileName ?? ""))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Review row

    /// The "N rows need a look" door into the review list, exactly as the
    /// preview gate carries it (F6b): rows that still need a person are one tap
    /// away, and Done returns to THIS gate.
    private var reviewRow: some View {
        Button(action: onShowReview) {
            HStack(spacing: 10) {
                Text(L10n.rowsNeedALook(model.reviewRows.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
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
        .accessibilityIdentifier("importCarsReviewRow")
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.carsGateIsReady {
                Text(L10n.importLandsInCars(model.plannedDestinationCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            } else {
                Text(L10n.importCarsHint)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            ImportPrimaryBar(action: onImport,
                             enabled: model.carsGateIsReady) {
                Text(L10n.importFillUps(model.plannedFillCount))
            }
            .accessibilityIdentifier("importCarsConfirmButton")
            Text("Nothing has been saved yet. Cancel leaves your garage untouched.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.bottom, 12)
        }
        .padding(.top, 6)
    }
}

// MARK: - One source car's mapping card

/// One source car: its own figures (row count, odometer span, date range) and
/// the explicit destination choice. The card never preselects - Leave out and
/// New car and every existing garage car are offered, and the chosen one is
/// marked (hard rule 13: the app suggests by listing, the user decides).
private struct ImportCarMappingCard: View {
    let model: ImportFlowModel
    let index: Int

    private var row: ImportCarRow { model.carPlan[index] }
    private var figures: ImportCarFigures { model.carFigures(row.group) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CardDivider()
            figuresBlock
            CardDivider()
            destinationBlock
            if let duplicateCount = mergeDuplicateCount, duplicateCount > 0 {
                CardDivider()
                duplicateLine(duplicateCount)
            }
        }
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importCarCard-\(index)")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionEyebrow("In this file")
            Text(displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isLeftOut ? Theme.Palette.inkSoft : Theme.Palette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    /// The group's own name; a blank file name renders as the generic imported
    /// car name (nothing is silently anonymous).
    private var displayName: String {
        let trimmed = row.group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.importedCarName : trimmed
    }

    private var isLeftOut: Bool {
        row.destination == .leaveOut
    }

    // MARK: Figures (the source car's own, never across cars)

    private var figuresBlock: some View {
        VStack(spacing: 0) {
            figureRow("Rows", value: "\(figures.count)")
            CardDivider()
            figureRow("Odometer", value: odometerText)
            CardDivider()
            figureRow("Dates", value: ImportFormatting.dateRange(figures.firstDate,
                                                                 figures.lastDate))
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
    }

    private func figureRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.vertical, 8)
    }

    private var odometerText: String {
        guard let min = figures.odometerMin, let max = figures.odometerMax else {
            return "–"
        }
        let unit = model.distanceUnit(forPlanRow: row)
        return "\(ImportFormatting.odometer(min)) – \(ImportFormatting.odometer(max)) \(L10n.distanceUnit(unit))"
    }

    // MARK: Destination

    private var destinationBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Imports into")
            optionRow(label: Text("Leave out"),
                      selected: row.destination == .leaveOut,
                      identifier: "importCarLeaveOut-\(index)",
                      select: { model.leaveOutCar(at: index) })
            optionRow(label: Text("New car"),
                      selected: isNewCar,
                      identifier: "importCarNewCar-\(index)",
                      select: { model.importAsNewCar(at: index) })
            ForEach(model.liveVehicles, id: \.id) { vehicle in
                optionRow(label: Text(vehicle.name),
                          selected: row.destinationVehicleID == vehicle.id,
                          identifier: "importCarExisting-\(index)-\(vehicle.id)",
                          select: { model.importIntoExistingVehicle(vehicle, at: index) })
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 11)
    }

    private var isNewCar: Bool {
        if case .new = row.destination { return true }
        return false
    }

    /// A destination option row: the label, a checkmark when chosen. Never
    /// disabled - Leave out is always a legal, explicit decision (hard rule 13).
    private func optionRow(label: Text, selected: Bool, identifier: String,
                           select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 8) {
                label
                    .font(.subheadline)
                    .foregroundStyle(selected ? Theme.Palette.action : Theme.Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.action)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The S2 duplicate count when merging into an existing car (0 elsewhere),
    /// recomputed live from the current decisions.
    private var mergeDuplicateCount: Int? {
        guard row.destinationVehicleID != nil else { return nil }
        let count = model.mergeDuplicateCount(for: row)
        return count > 0 ? count : nil
    }

    private func duplicateLine(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
                .padding(.top, 1)
            Text(L10n.lookLikeDuplicates(count))
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
                .lineSpacing(1.4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 11)
        .accessibilityIdentifier("importCarDuplicate-\(index)")
    }
}
