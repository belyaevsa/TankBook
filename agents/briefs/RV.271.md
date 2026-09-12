# RV.271 - two unit residues outside RV.234's list

**Scenario: J3b · type it (the unit in the sentence).** The last v1 row naming J3b. Small; the
seam `RV.234` finished, two places it found beyond its list.

1. **Pace limit** - `VehicleDetailSections.swift:125` labels the field `km/day` on a miles car.
   `paceLimitKmPerDay` IS km (the model's unit), so the label is honest to the model and wrong to
   the user. Label AND edit the field in the car's distance unit, converting to km at the boundary
   the way the odometer field does (find it - one converter, not a copy); a value the user typed
   stays theirs (rule 13).
2. **Inbox values** - `InboxValueFormat.yours(.volume)` and `fuelReceipt(.volume)` print the stored
   litre figure under `L10n.volumeUnit(.l)` whatever the car's unit; the LABEL is per-unit since
   `RV.234`, the VALUE is not - an imperial car's inbox compares *12.4 L* against a receipt that
   said gallons. Convert both columns to the car's unit the way Home/Trends now do (`RV.234`'s
   converter), and the receipt column in the unit the receipt was read in if that is different -
   say what the receipt column shows and why.

## Tests

- **L1 per residue, FAILS TODAY**, metric and imperial: the pace-limit label and round-trip;
  the inbox volume values.
- **L4 `InboxUITests`** on an imperial car: *gal* in both columns; **L4 `VehicleDetailUITests`**
  (or the suite that owns the pace-limit row): the row reads *mi/day* on a miles car. EN + RU,
  screenshots `RV.271-inbox-imperial` and `RV.271-pace-limit-imperial`, dark.

## Mutation - named

Hardcode `.l` back in the inbox value; the imperial L1 goes red. Verbatim.
