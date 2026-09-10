import SwiftUI
import TankbookCore

/// RV.117b: the timeline neighbourhood panel under an F9a conflict
/// (docs/ERRORS.md -> Confirm -> F9a; the Drivvo presentation, RV.117). Three
/// parts, in the card's reading order:
///
/// 1. A chart of the surrounding entries, the offending point plotted off the
///    trend through the valid ones. Amber is attention (hard rule 5); the point
///    is a WARN diamond, distinct from the valid neighbours' ink circles by
///    shape and size as well as colour, and each point is its own accessibility
///    element (colour is never the only channel).
/// 2. The bracketing rows - the previous entry and this one, their odometers in
///    DIN with tabular alignment (hard rule 6).
/// 3. The bidirectional statement, one sentence per side of the validator's
///    range (`TimelineNeighbourhoodSentences`). The panel reads `validRange`
///    and derives no bound of its own.
///
/// The card renders ONLY when the form's candidate flags and carries a
/// `validRange`; otherwise the whole thing is absent - no panel, no empty box.
struct TimelineNeighbourhoodCard: View {
    let model: TimelineNeighbourhood
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Around this entry")
            TimelineNeighbourhoodChart(model: model, distanceUnit: distanceUnit)
                .frame(height: 150)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("neighbourhoodChart")
            bracketRows
            statements
        }
        .padding(Theme.Spacing.cardPadding)
        .accessibilityElement(children: .contain)
        .formCard()
        .accessibilityIdentifier("timelineNeighbourhoodCard")
    }

    // MARK: - The bracketing rows

    private var bracketRows: some View {
        VStack(spacing: 4) {
            if let previous = model.previous {
                bracketRow(label: Text("Previous entry"),
                           date: previous.date, odometer: previous.odometer,
                           isOffending: false)
            }
            bracketRow(label: Text("This entry"),
                       date: model.entryDate, odometer: model.entryOdometer,
                       isOffending: true)
            if let next = model.next {
                bracketRow(label: Text("Next entry"),
                           date: next.date, odometer: next.odometer,
                           isOffending: false)
            }
        }
    }

    private func bracketRow(label: Text, date: Date, odometer: Int,
                            isOffending: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            label
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(EntryDateText.dayMonth(date))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Text("\(OdometerFormat.grouped(odometer)) \(L10n.distanceUnit(distanceUnit))")
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .monospacedDigit()
                .foregroundStyle(isOffending ? Theme.Palette.warn : Theme.Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: Self.bracketValue(date: date,
                                                             odometer: odometer,
                                                             unit: distanceUnit)))
    }

    /// "10 Jul, 490 500 km" - a point's accessibility value, composed once so
    /// the VoiceOver label stays readable and this file's lines short. Shared
    /// by the bracket rows and the chart's per-point elements.
    static func bracketValue(date: Date, odometer: Int, unit: DistanceUnit) -> String {
        "\(EntryDateText.dayMonth(date)), \(OdometerFormat.grouped(odometer)) \(L10n.distanceUnit(unit))"
    }

    // MARK: - The bidirectional statement

    private var statements: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.statementItems(for: model, distanceUnit: distanceUnit)) { statement in
                Text(statement.text)
                    .font(.footnote)
                    .foregroundStyle(statement.isAttention
                        ? Theme.Palette.warn : Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(statement.identifier)
            }
        }
    }

    private struct Statement: Identifiable {
        let id = UUID()
        let text: String
        let identifier: String
        let isAttention: Bool
    }

    /// Builds the panel's sentences from the validator's two intervals. Both
    /// sides `.none` means the neighbourhood itself is inconsistent - one
    /// sentence says so (never a blank panel); otherwise each side that
    /// constrains something gets its own sentence. The `.none` date side is the
    /// row's whole point (the odometer is the field to question), so it reads
    /// in warn; the numeric between/open sentences are quiet copy.
    private static func statementItems(for model: TimelineNeighbourhood,
                                       distanceUnit: DistanceUnit) -> [Statement] {
        switch (model.validRange.odometer, model.validRange.dates) {
        case (.none, .none):
            // The dead end RV.188 fixes: name every failed comparison rather
            // than gesturing at "the entries around this one". The validator
            // carried the side of each flag, so each sentence points at the
            // pair that disagrees. The generic sentence remains only as the
            // no-culprit fallback - never a blank panel.
            guard !model.culprits.isEmpty else {
                return [Statement(text: TimelineNeighbourhoodSentences.inconsistentNeighbourhood,
                                  identifier: "neighbourhoodInconsistentStatement",
                                  isAttention: true)]
            }
            return model.culprits.map { culprit in
                Statement(text: TimelineNeighbourhoodSentences.culprit(culprit, unit: distanceUnit),
                          identifier: "neighbourhoodCulpritStatement",
                          isAttention: true)
            }
        default:
            let unit = distanceUnit
            let dateText = EntryDateText.dayMonth(model.entryDate)
            let odometerText = OdometerFormat.grouped(model.entryOdometer)
            var result: [Statement] = []
            if let sentence = TimelineNeighbourhoodSentences.odometer(
                model.validRange.odometer, dateText: dateText, unit: unit) {
                result.append(Statement(text: sentence,
                                        identifier: "neighbourhoodOdometerStatement",
                                        isAttention: false))
            }
            if let sentence = TimelineNeighbourhoodSentences.dates(
                model.validRange.dates, odometerText: odometerText, unit: unit) {
                result.append(Statement(text: sentence,
                                        identifier: "neighbourhoodDateStatement",
                                        isAttention: model.validRange.dates == .none))
            }
            return result
        }
    }
}

/// The tiny plot (docs/DESIGN.md chart rules - no chart junk, thin grid): the
/// entry's odometer-bearing neighbours as quiet ink circles with a trend line
/// through them, and the offending entry as an amber diamond plotted off it.
/// X is the entries' dates (proportional, never invented spacing); Y their
/// odometer readings. Each point carries its own accessibility element, so the
/// offending point is identifiable by label and shape, never by colour alone.
struct TimelineNeighbourhoodChart: View {
    let model: TimelineNeighbourhood
    let distanceUnit: DistanceUnit

    var body: some View {
        GeometryReader { geo in
            let layout = TimelineNeighbourhoodChartLayout(points: model.points, size: geo.size)
            ZStack(alignment: .topLeading) {
                grid(geo.size)
                trendLine(layout)
                neighbourMarks(layout)
                offendingMark(layout)
                pointLabels(layout, size: geo.size)
                accessibilityOverlay(layout)
            }
        }
    }

    /// A thin baseline plus two quiet rules at the thirds - the sparkline's own
    /// grid treatment, reused so the panel reads as part of the app's charts.
    private func grid(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height * CGFloat(index + 1) / 3))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(index + 1) / 3))
                }
                .stroke(Theme.Palette.inkSoft.opacity(0.14), lineWidth: 1)
            }
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height - 0.5))
                path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            }
            .stroke(Theme.Palette.inkSoft.opacity(0.25), lineWidth: 1)
        }
    }

    /// The trend through the valid points, one segment per neighbouring pair -
    /// the offending point is never on this path (it is the point off it).
    @ViewBuilder
    private func trendLine(_ layout: TimelineNeighbourhoodChartLayout) -> some View {
        if layout.validPoints.count >= 2 {
            Path { path in
                path.move(to: layout.validPoints[0].position)
                for point in layout.validPoints.dropFirst() {
                    path.addLine(to: point.position)
                }
            }
            .stroke(Theme.Palette.inkSoft.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func neighbourMarks(_ layout: TimelineNeighbourhoodChartLayout) -> some View {
        ForEach(layout.validPoints) { point in
            Circle()
                .fill(Theme.Palette.inkSoft)
                .frame(width: 6, height: 6)
                .position(point.position)
        }
    }

    /// The offending entry: a WARN diamond (rotated square) with an ink stroke,
    /// larger than the neighbours - shape, size AND colour distinguish it
    /// (hard rule 5's accessibility floor).
    @ViewBuilder
    private func offendingMark(_ layout: TimelineNeighbourhoodChartLayout) -> some View {
        if let point = layout.offendingPoint {
            Diamond()
                .fill(Theme.Palette.warn)
                .frame(width: 12, height: 12)
                .overlay(Diamond().stroke(Theme.Palette.ink.opacity(0.6), lineWidth: 1))
                .position(point.position)
        }
    }

    /// The per-point accessibility elements: each neighbour names its reading
    /// and day; the offending point is labelled "This entry" - the panel stays
    /// legible to VoiceOver before colour is consulted.
    private func accessibilityOverlay(_ layout: TimelineNeighbourhoodChartLayout) -> some View {
        ForEach(layout.allPoints) { entry in
            Color.clear
                .frame(width: 44, height: 44)
                .position(entry.position)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pointLabel(isOffending: entry.isOffending))
                .accessibilityValue(Text(verbatim: TimelineNeighbourhoodCard.bracketValue(
                    date: entry.date, odometer: entry.odometer, unit: distanceUnit)))
                .accessibilityIdentifier(entry.isOffending
                    ? "neighbourhoodOffendingPoint"
                    : "neighbourhoodNeighbourPoint")
        }
    }

    /// Visible labels on the plotted points (RV.188): the odometer in DIN and
    /// the day, so the point that disagrees is named on the chart and not only
    /// to VoiceOver. Placement is computed by
    /// `TimelineNeighbourhoodChartLayout.labelFrames` - see there for why the
    /// side cannot be chosen by the point's index. The per-point accessibility
    /// overlay above remains the VoiceOver channel; these carry
    /// `neighbourhoodChartOdometerLabel` / `…DateLabel` so a UI test can read the
    /// visible text back.
    private func pointLabels(_ layout: TimelineNeighbourhoodChartLayout,
                             size: CGSize) -> some View {
        let frames = layout.labelFrames(in: size)
        return ForEach(layout.allPoints) { mark in
            VStack(spacing: 0) {
                Text("\(OdometerFormat.grouped(mark.odometer)) \(L10n.distanceUnit(distanceUnit))")
                    .font(.custom(AppFonts.dinAlternateBold, size: 10))
                    .monospacedDigit()
                    .accessibilityIdentifier("neighbourhoodChartOdometerLabel")
                Text(EntryDateText.dayMonth(mark.date))
                    .font(.system(size: 9))
                    .accessibilityIdentifier("neighbourhoodChartDateLabel")
            }
            .foregroundStyle(mark.isOffending ? Theme.Palette.warn : Theme.Palette.inkSoft)
            .fixedSize()
            .position(frames[mark.id]?.center ?? mark.position)
        }
    }

    private func pointLabel(isOffending: Bool) -> Text {
        if isOffending {
            return Text("This entry")
        }
        return Text("Neighbouring entry")
    }
}

/// A unit square drawn as a diamond (the offending point's shape). Kept a tiny
/// type so the chart marks read as shapes, not rotated squares with corners.
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Resolves the chart's points to positions. X is the date proportion across
/// the plotted span (the entries keep their true time gaps), Y the odometer
/// value within the plotted span. A single-point span centres it, like the
/// Sparkline does for a flat series.
struct TimelineNeighbourhoodChartLayout {
    struct Mark: Identifiable {
        let id: UUID
        let position: CGPoint
        let odometer: Int
        let date: Date
        let isOffending: Bool
    }

    let allPoints: [Mark]
    let validPoints: [Mark]

    var offendingPoint: Mark? {
        allPoints.first { $0.isOffending }
    }

    /// The label box, sized for the widest string this chart draws: a grouped
    /// six-figure odometer with its unit over a short date. RU is the wider
    /// locale, so the width is set from it.
    static let labelSize = CGSize(width: 84, height: 26)

    /// Where each point's label sits, keyed by the point's id.
    ///
    /// **The side is chosen by the point's own height, never by its index.** The
    /// series rises left to right, so the free space is BELOW a point in the
    /// lower half of the plot and ABOVE one in the upper half - the line itself
    /// occupies the other side. Alternating by index instead put the offending
    /// point's label on top of its neighbour's mark and the neighbour's label on
    /// top of that, which is what the RV.188 screenshots showed: two labels
    /// printed over each other at the same corner, one of the three points
    /// effectively unlabelled.
    ///
    /// Overlaps are then resolved by pushing the later label further from the
    /// plot, so two points close in x (a day apart on a three-week span) still
    /// read as two labels. Everything stays inside `size`.
    func labelFrames(in size: CGSize) -> [UUID: CGRect] {
        let box = Self.labelSize
        let midY = size.height / 2
        var placed: [CGRect] = []
        var frames: [UUID: CGRect] = [:]

        // Nearest the plot's vertical centre first: the points with the least
        // room get the side they need before the outer ones claim it.
        for mark in allPoints.sorted(by: { abs($0.position.y - midY) < abs($1.position.y - midY) }) {
            let goesUp = mark.position.y < midY
            var frame = Self.frame(for: mark.position, box: box, goesUp: goesUp, step: 0, in: size)
            var step = 1
            while placed.contains(where: { $0.intersects(frame) }), step <= 3 {
                frame = Self.frame(for: mark.position, box: box, goesUp: goesUp, step: step, in: size)
                step += 1
            }
            placed.append(frame)
            frames[mark.id] = frame
        }
        return frames
    }

    /// One candidate box, `step` label-heights away from the point on the chosen
    /// side, clamped so no part of it leaves the chart.
    private static func frame(for point: CGPoint, box: CGSize, goesUp: Bool,
                              step: Int, in size: CGSize) -> CGRect {
        let gap = box.height / 2 + 8 + CGFloat(step) * box.height
        let rawY = goesUp ? point.y - gap : point.y + gap
        let clampedY = min(max(rawY, box.height / 2), max(size.height - box.height / 2, box.height / 2))
        let clampedX = min(max(point.x, box.width / 2), max(size.width - box.width / 2, box.width / 2))
        return CGRect(x: clampedX - box.width / 2, y: clampedY - box.height / 2,
                      width: box.width, height: box.height)
    }

    init(points: [TimelineNeighbourhood.Point], size: CGSize) {
        // Room above and below for the point labels RV.188 draws: marks stay
        // clear of the edges so a label never runs off the chart.
        let topPad: CGFloat = 24
        let bottomPad: CGFloat = 24
        let usableHeight = max(size.height - topPad - bottomPad, 1)

        let minDate = points.map(\.date).min() ?? Date()
        let maxDate = points.map(\.date).max() ?? minDate
        let minOdo = points.map(\.odometer).min() ?? 0
        let maxOdo = points.map(\.odometer).max() ?? 0
        let dateSpan = maxDate.timeIntervalSince(minDate)
        let odoSpan = CGFloat(maxOdo - minOdo)

        func xPosition(date: Date) -> CGFloat {
            if dateSpan <= 0 { return size.width / 2 }
            return size.width * CGFloat(date.timeIntervalSince(minDate) / dateSpan)
        }
        func yPosition(odometer: Int) -> CGFloat {
            if odoSpan <= 0 { return size.height / 2 }
            let ratio = CGFloat(odometer - minOdo) / odoSpan
            return topPad + (1 - ratio) * usableHeight
        }

        let marks = points.map { point in
            Mark(id: point.id,
                 position: CGPoint(x: xPosition(date: point.date),
                                   y: yPosition(odometer: point.odometer)),
                 odometer: point.odometer,
                 date: point.date,
                 isOffending: point.isOffending)
        }
        allPoints = marks
        validPoints = marks.filter { !$0.isOffending }
    }
}

extension CGRect {
    /// The box's centre - what SwiftUI's `.position` takes, where the layout
    /// reasons in frames so overlaps can be tested.
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
