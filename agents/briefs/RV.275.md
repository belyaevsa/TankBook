# RV.275 - the car's photo is missing from the Garage list and the car switcher

**Scenarios: J1 · the Garage, J13 · which car is which.** Reported by the product owner
2026-09-13 with screenshots of both lists: a photo added to a car renders on Home, while the
Garage tab and the *My garage* switcher sheet show the same SF glyph for every car.

`GarageView.swift:322` draws `Image(systemName: "car")` and `CarSwitcherView.swift:283`
`car.fill` in every 42 pt tile, unconditionally. Only `HomeView` (`photoData`) and
`VehicleDetailView.loadPhoto` (`:566-573`) read the `vehicle.photo` attachment - two private
loaders that do the same thing. The photo the user added to tell three cars apart is shown
exactly where it is not needed.

## Build

1. **One tile**: a shared `VehicleTile` (photo when present, the glyph when not; 42 pt, the
   artboard's corner radius, the same in both lists and on Home's garage card) - read
   `design/screens/Garage.dc.html` and the switcher artboard for the drawn tile; match them.
2. **One loader**: move `loadPhoto` into a shared place (`VehiclePhotoStore` already owns the
   directory - a `data(for: Vehicle, repository:)` there is the natural home) and make Home,
   Vehicle detail, the Garage and the switcher all call it. Never a third copy.
3. **Reload**: the Garage reloads on a car save today (`GarageView.swift:78`); make sure a photo
   saved on Vehicle detail reaches both lists on return, and the switcher on open. Cost: the
   Garage renders N tiles - load thumbnails, not full renditions, if the store holds only the
   full file (say what the store holds and what you decided).

## Tests

- **L4 `GarageUITests`, FAILS TODAY**: a seeded car with a photo shows the image tile (an
  identifier the glyph tile does not carry), a car without shows the glyph.
- **L4 `CarSwitcherUITests`, FAILS TODAY**: the same on the switcher sheet.
- **L1**: the shared loader returns the attachment's bytes for a car with a photo and nil for one
  without; a tombstoned attachment reads as nil.
- Screenshots EN + RU of the Garage and the switcher with one photographed car:
  `RV.275-garage-photo`, `RV.275-switcher-photo`, dark. Own invocations, counts reported; the
  existing Home frames must not change (no re-shoot unless the tile's pixels moved).

## Mutation - named

Render the glyph unconditionally in the shared tile; both L4s go red. Verbatim.

## Vacuous trap

Asserting the tile exists rather than WHICH of the two it shows.
