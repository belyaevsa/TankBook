import SwiftUI
import TankbookCore

// MARK: - Fuel kind + full-tank toggle

struct ManualFillUpFuelFullCard: View {
    @Binding var form: ManualFillUpFormState
    let fuelKinds: [FuelKind]

    var body: some View {
        VStack(spacing: 0) {
            fuelKindSection
            CardDivider()
            fullToggleRow
        }
        .formCard()
    }

    /// THE LIKELY OFFER SET (P2.3c): `Vehicle.fuelKinds` is a suggestion, not a
    /// limit (hard rule 13) - petrol grades share a tank, so a 95 car is
    /// routinely filled with 92 or 100. A car whose kinds include any petrol
    /// grade is offered ALL petrol grades plus its other kinds; a diesel (or
    /// EV/gas) car is offered its own kinds. Every other kind stays reachable
    /// through the correction affordance - nothing is ever blocked.
    private var offeredKinds: [FuelKind] {
        FuelKind.offeredKinds(for: Set(fuelKinds))
    }

    /// The chips to render: the offer set, plus the currently-selected kind if
    /// the correction menu put one outside the offer set - the selection must
    /// always be visible, never a chip-less value.
    private var visibleKinds: [FuelKind] {
        var result = offeredKinds
        if !result.contains(form.fuelKind) {
            result.append(form.fuelKind)
        }
        return result
    }

    /// Kinds not yet visible, reachable through the "+" correction menu.
    private var remainingKinds: [FuelKind] {
        FuelKind.allCases.filter { !visibleKinds.contains($0) }
    }

    private var fuelKindSection: some View {
        FieldRow("Fuel") {
            if offeredKinds.count > 1 {
                chooser
            } else if offeredKinds.count == 1 {
                singleKindValue()
            }
        }
    }

    /// The multi-kind chooser: chips for the likely offer set plus the "+"
    /// correction menu (P2.3c). It wraps - a petrol + LPG car is six items -
    /// so the offer set can be honest instead of truncated. The grid fills the
    /// row's trailing space and right-aligns, keeping the Fuel label on the
    /// same line for the common four-grade car.
    private var chooser: some View {
        // `minimum: 44` squeezed "100" and "LPG" until their labels wrapped
        // INSIDE the capsule ("10"/"0", "LP"/"G") - caught in a screenshot, not
        // by any test. The grid must wrap chips onto the next row instead of
        // compressing them, so the minimum is the widest chip, and each label
        // is pinned to one line below.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)],
                  alignment: .trailing, spacing: 6) {
            ForEach(visibleKinds, id: \.self) { kind in
                chip(kind)
            }
            if !remainingKinds.isEmpty {
                addMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// A single-kind car renders its fuel as a STATIC value, not a chooser
    /// (docs/DESIGN.md, now governing input) - and it stays correctable
    /// (hard rule 13): the value is a menu, one tap lists every kind, so a
    /// wrongly-configured car's entry can be fixed without re-logging it.
    private func singleKindValue() -> some View {
        Menu {
            ForEach(FuelKind.allCases, id: \.self) { option in
                Button {
                    form.fuelKind = option
                } label: {
                    Text(option.labelKey)
                }
                .accessibilityIdentifier("manualFillUpFuelCorrection_\(option.rawValue)")
            }
        } label: {
            HStack(spacing: 4) {
                Text(form.fuelKind.labelKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .accessibilityIdentifier("manualFillUpFuelValue")
    }

    /// The "+" correction menu (P2.3c): every kind not already visible. This is
    /// what makes the multi-kind path as permissive as the single-kind one - a
    /// `[95, LPG]` car can still record diesel, 98 or CNG, nothing is blocked.
    private var addMenu: some View {
        Menu {
            ForEach(remainingKinds, id: \.self) { kind in
                Button {
                    form.fuelKind = kind
                } label: {
                    Text(kind.labelKey)
                }
                .accessibilityIdentifier("manualFillUpFuelCorrection_\(kind.rawValue)")
            }
        } label: {
            Text("+")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineLimit(1)
                .frame(minWidth: 24)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.dash))
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .accessibilityIdentifier("manualFillUpFuelMoreMenu")
    }

    private func chip(_ kind: FuelKind) -> some View {
        let selected = form.fuelKind == kind
        return Button {
            form.fuelKind = kind
        } label: {
            Text(kind.labelKey)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("manualFillUpFuelKind_\(kind.rawValue)")
    }

    private var fullToggleRow: some View {
        HStack {
            Text("Full tank")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { form.isFull },
                set: { full in
                    form.isFull = full
                    // The 100 ⇔ full invariant (docs/SCHEMA.md): turning the
                    // toggle on is a 100% tank, turning it off from a full
                    // state is a bare partial (the tank row then offers the
                    // sheet to set a real level).
                    if full {
                        form.tankLevelAfterPct = 100
                    } else if form.tankLevelAfterPct == 100 {
                        form.tankLevelAfterPct = nil
                    }
                }
            ))
            .labelsHidden()
            .tint(Theme.Palette.taillight)
            .accessibilityIdentifier("manualFillUpIsFullToggle")
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
    }
}
