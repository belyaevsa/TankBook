import SwiftUI
import TankbookCore

// MARK: - Fuel kind + full-tank toggle

struct ManualFillUpFuelFullCard: View {
    @Binding var form: ManualFillUpFormState
    let fuelKinds: [FuelKind]

    var body: some View {
        VStack(spacing: 0) {
            FieldRow("Fuel") {
                if offeredKinds.count > 1 {
                    chooser
                } else if offeredKinds.count == 1 {
                    singleKindValue()
                }
            }
            CardDivider()
            fullToggleRow
        }
        .formCard()
    }

    /// THE FILTER (P2.3b): exactly the kinds this vehicle accepts - never a
    /// kind the car cannot burn. The seeds once held `[.petrol95, .diesel]`,
    /// a car that burns both; the row offers the vehicle's kinds, nothing more.
    private var offeredKinds: [FuelKind] {
        fuelKinds
    }

    private var chooser: some View {
        HStack(spacing: 6) {
            ForEach(offeredKinds, id: \.self) { kind in
                chip(kind)
            }
        }
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

    private func chip(_ kind: FuelKind) -> some View {
        let selected = form.fuelKind == kind
        return Button {
            form.fuelKind = kind
        } label: {
            Text(kind.labelKey)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
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
