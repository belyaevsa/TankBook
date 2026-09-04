import Foundation
import Testing
@testable import TankbookCore

// The catalog pack body, decoded exactly as the server shipped it (docs/API.md
// -> "GET /catalog"). Split out of VehicleCatalogUpdaterTests, which owns the
// updater's behaviour - this file owns the wire shape alone and needs no
// transport double, only the raw bytes.

// MARK: - Wire builders (camelCase, as the server writes them)

private func packJSON(version: Int, entries: [String], kind: String? = nil) -> Data {
    let kindJSON = kind.map { ", \"kind\": \"\($0)\"" } ?? ""
    return Data("{ \"packVersion\": \(version), \"entries\": [\(entries.joined(separator: ","))]\(kindJSON) }".utf8)
}

private func v60EntryJSON(id: String = "11111111-1111-1111-1111-111111111111",
                          tank: String = "71", years: String = "[2018, 2024]") -> String {
    "{ \"id\": \"\(id)\", \"make\": \"Volvo\", \"model\": \"V60\", \"generation\": \"SPA\", "
        + "\"years\": \(years), \"powertrain\": \"ice\", \"fuelKinds\": [\"petrol95\",\"diesel\"], "
        + "\"tankCapacityL\": \(tank), \"batteryCapacityKwh\": null }"
}

// MARK: - Decoding

@Test func packDecodesExactlyFromTheWire() throws {
    let body = packJSON(version: 7, entries: [
        v60EntryJSON(id: "11111111-1111-1111-1111-111111111111", tank: "71", years: "[2018, 2024]"),
        // An open-ended model line arrives as years: null; generation may be null.
        #"{"id":"22222222-2222-2222-2222-222222222222","make":"Tesla","model":"Model 3","#
            + #""generation":null,"years":null,"powertrain":"ev","fuelKinds":["electricity"],"#
            + #""tankCapacityL":null,"batteryCapacityKwh":60}"#,
        // A line still in production: a start year with a NULL end, which is
        // not the same thing as no range (docs/API.md "GET /catalog").
        #"{"id":"33333333-3333-3333-3333-333333333333","make":"Haval","model":"Jolion","#
            + #""generation":"2021-","years":[2021,null],"powertrain":"ice","fuelKinds":["petrol95"],"#
            + #""tankCapacityL":55,"batteryCapacityKwh":null}"#
    ])
    let pack = try RemoteVehicleCatalogFetcher.decodePack(body)
    #expect(pack.packVersion == 7)

    let v60 = try #require(pack.entries.first { $0.model == "V60" })
    #expect(v60.id == "11111111-1111-1111-1111-111111111111")
    #expect(v60.years == [2018, 2024], "inclusive pair, not half-open")
    #expect(v60.yearsEnd == 2024)
    #expect(v60.tankCapacityL == 71)

    let tesla = try #require(pack.entries.first { $0.model == "Model 3" })
    #expect(tesla.years == [nil, nil])
    #expect(tesla.yearsEnd == nil)
    #expect(tesla.generation == "")
    #expect(tesla.batteryCapacityKWh == 60)

    // The open end keeps its start year: `yearsStart` must be 2021, never 0 -
    // Add-car renders a 0 as "0-".
    let jolion = try #require(pack.entries.first { $0.model == "Jolion" })
    #expect(jolion.years == [2021, nil])
    #expect(jolion.yearsStart == 2021)
    #expect(jolion.yearsEnd == nil)
}

@Test func unknownPowertrainOrFuelKindRejectsThePackWhole() throws {
    let unknownPowertrain = packJSON(version: 8, entries: [
        v60EntryJSON().replacingOccurrences(of: "\"powertrain\": \"ice\"",
                                            with: "\"powertrain\": \"warp\"")
    ])
    #expect(throws: CatalogFetchError.invalidResponse) {
        _ = try RemoteVehicleCatalogFetcher.decodePack(unknownPowertrain)
    }

    let unknownFuel = packJSON(version: 8, entries: [
        v60EntryJSON().replacingOccurrences(of: "[\"petrol95\",\"diesel\"]",
                                            with: "[\"hydrofluorocarbons\"]")
    ])
    #expect(throws: CatalogFetchError.invalidResponse) {
        _ = try RemoteVehicleCatalogFetcher.decodePack(unknownFuel)
    }
}
