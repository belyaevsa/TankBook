#!/usr/bin/env swift
// Tankbook payload-schema generator (P0.10).
// Emits a JSON Schema (draft 2020-12) per synced entity into
// docs/schemas/v<N>/<entityType>.schema.json, from the declarative field table
// below. The table is the machine-checkable contract the iOS client, the
// backend (`payload_schemas` registry) and the fixture corpus share
// (docs/SYNC.md -> "Payload contract and versioning", docs/SCHEMA.md ->
// "Payload schemas").
//
// Run from anywhere: `swift scripts/generate-payload-schemas.swift`
//
// Two drift guards keep the schemas honest:
//   1. The test suite (PayloadContractTests) encodes every synced entity with
//      the iOS codec and fails when an emitted key is missing from the schema.
//   2. This script cross-checks every canonical fixture under
//      docs/fixtures/payloads/v1/ against the table and fails when a fixture
//      key is not declared.
//
// The output is canonical (sorted keys), so re-running produces no diff.

import Foundation

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Schema building blocks

let schemaString = ["type": "string"]
let schemaNumber = ["type": "number"]
let schemaInteger = ["type": "integer"]
let schemaBoolean = ["type": "boolean"]
let schemaUUID = ["type": "string", "format": "uuid"]
let schemaDate = ["type": "string", "format": "date-time"]
let schemaDecimal = ["type": "string"]
let schemaCurrency = ["type": "string", "pattern": "^[A-Z]{3}$"]

func strEnum(_ cases: [String]) -> [String: Any] {
    ["type": "string", "enum": cases]
}

func schemaArray(_ item: Any) -> [String: Any] {
    ["type": "array", "items": item]
}

func schemaRef(_ name: String) -> [String: Any] {
    ["$ref": "#/$defs/\(name)"]
}

func schemaObject(_ properties: [String: Any], _ required: [String]) -> [String: Any] {
    var object: [String: Any] = ["type": "object", "additionalProperties": true]
    if !required.isEmpty { object["required"] = required }
    if !properties.isEmpty { object["properties"] = properties }
    return object
}

func schemaObject(_ properties: [String: Any], _ required: [String], additionalProperties: Any) -> [String: Any] {
    var object: [String: Any] = ["type": "object", "additionalProperties": additionalProperties]
    if !required.isEmpty { object["required"] = required }
    if !properties.isEmpty { object["properties"] = properties }
    return object
}

/// A tagged-object enum: `{ "tag": <case>, ...payload }` with
/// `additionalProperties: true`, so unknown tags stay legal (forward
/// compatibility).
func taggedEnum(_ tags: [String], _ payload: [String: Any]) -> [String: Any] {
    var properties = payload
    properties["tag"] = strEnum(tags)
    return ["type": "object", "required": ["tag"], "additionalProperties": true, "properties": properties]
}

// MARK: - Shared enum vocabularies (exact SCHEMA.md spellings)

let fuelKinds = ["diesel", "petrol95", "petrol98", "lpg", "cng", "e85", "electricity"]
let powertrains = ["ice", "ev", "hybrid", "phev"]
let chargeTypes = ["acHome", "acPublic", "dcPublic"]
let distanceUnits = ["km", "mi"]
let volumeUnits = ["l", "galUS", "galUK"]
let consumptionUnits = ["lPer100", "mpgUS", "mpgUK", "kmPerL"]
let energyUnits = ["kWhPer100", "miPerKWh"]
let rateSources = ["ecb", "cis", "manual"]
let conflictKinds = ["order", "pace"]
let fieldRefUnitCases = ["total", "volume", "unitPrice", "date", "station", "fuelKind", "energy", "currency", "vendor"]
let serviceCategories = ["oil", "brakes", "tires", "battery", "filters", "inspection", "repair", "parts", "wash", "other"]
let expenseCategories = ["insurance", "tax", "parking", "toll", "fine", "accessory", "parts", "other"]
let reminderCategories = serviceCategories + ["insurance", "custom"]
let attachmentKinds = ["photo", "pdf"]
let provenanceTags = ["receiptScan", "pumpPhoto", "fiscalQR", "screenshot", "manual", "import"]

// MARK: - Shared $defs

let fieldRefDef: [String: Any] = [
    "type": "string",
    "anyOf": [
        strEnum(fieldRefUnitCases),
        ["type": "string", "pattern": "^lineItem\\(\\d+\\)$"],
    ],
]

let moneyDef = schemaObject([
    "amount": schemaDecimal,
    "currency": schemaCurrency,
    "homeAmount": schemaDecimal,
    "homeCurrency": schemaCurrency,
    "rate": schemaDecimal,
    "rateDate": schemaDate,
    "rateSource": strEnum(rateSources),
], ["amount", "currency", "homeCurrency", "rateSource"])

let geoCoordinateDef = schemaObject([
    "latitude": schemaNumber,
    "longitude": schemaNumber,
], ["latitude", "longitude"])

let unitsDef = schemaObject([
    "distance": strEnum(distanceUnits),
    "volume": strEnum(volumeUnits),
    "consumption": strEnum(consumptionUnits),
    "energy": strEnum(energyUnits),
], ["distance", "volume", "consumption", "energy"])

let stationDefaultsDef = schemaObject([
    "fuelKind": strEnum(fuelKinds),
    "fuelGrade": schemaString,
], [])

let notificationsDef = schemaObject([
    "reminders": schemaBoolean,
    "anomalies": schemaBoolean,
    "monthlySummary": schemaBoolean,
], ["reminders", "anomalies", "monthlySummary"])

let localFileRefDef = schemaObject([
    "sha256": ["type": "string", "pattern": "^[a-f0-9]{64}$"],
    "relativePath": schemaString,
], ["sha256", "relativePath"])

let lifetimeDef = schemaObject([
    "km": schemaInteger,
    "months": schemaInteger,
], [])

let recurrenceRuleDef = schemaObject([
    "everyMonths": schemaInteger,
    "anchorDate": schemaDate,
], ["everyMonths"])

let reminderRecurrenceDef = schemaObject([
    "everyKm": schemaInteger,
    "everyMonths": schemaInteger,
], [])

let provenanceDef = taggedEnum(provenanceTags, [
    "source": schemaString,
])

let conflictStateDef = taggedEnum(["none", "flagged"], [
    "kind": strEnum(conflictKinds),
    "detectedAt": schemaDate,
])

let crossCheckStateDef = taggedEnum(["verified", "notApplicable", "mismatch"], [
    "field": schemaRef("fieldRef"),
])

let serviceCategoryDef = taggedEnum(serviceCategories, [
    "value": schemaString,
])

let expenseCategoryDef = taggedEnum(expenseCategories, [
    "value": schemaString,
])

let reminderCategoryDef = taggedEnum(reminderCategories, [
    "value": schemaString,
])

let reminderStatusDef = taggedEnum(["scheduled", "attention", "done", "dismissed"], [
    "entryId": schemaUUID,
    "reason": schemaString,
])

let fieldExtractionDef = schemaObject([
    "cropRect": schemaObject([
        "x": schemaNumber,
        "y": schemaNumber,
        "width": schemaNumber,
        "height": schemaNumber,
    ], ["x", "y", "width", "height"]),
    "confidence": schemaNumber,
    "userCorrected": schemaBoolean,
], ["confidence", "userCorrected"])

let extractionFieldsDef: [String: Any] = [
    "type": "object",
    "additionalProperties": schemaRef("fieldExtraction"),
    "propertyNames": schemaRef("fieldRef"),
]

let extractionMetaDef = schemaObject([
    "fields": extractionFieldsDef,
    "pipeline": schemaString,
], ["fields", "pipeline"])

let serviceItemDef = schemaObject([
    "title": schemaString,
    "category": schemaRef("serviceCategory"),
    "cost": schemaRef("money"),
    "partNumber": schemaString,
    "lifetime": schemaRef("lifetime"),
], ["title", "category"])

let allDefs: [String: Any] = [
    "money": moneyDef,
    "fieldRef": fieldRefDef,
    "geoCoordinate": geoCoordinateDef,
    "units": unitsDef,
    "stationDefaults": stationDefaultsDef,
    "notifications": notificationsDef,
    "localFileRef": localFileRefDef,
    "lifetime": lifetimeDef,
    "recurrenceRule": recurrenceRuleDef,
    "reminderRecurrence": reminderRecurrenceDef,
    "provenance": provenanceDef,
    "conflictState": conflictStateDef,
    "crossCheckState": crossCheckStateDef,
    "serviceCategory": serviceCategoryDef,
    "expenseCategory": expenseCategoryDef,
    "reminderCategory": reminderCategoryDef,
    "reminderStatus": reminderStatusDef,
    "fieldExtraction": fieldExtractionDef,
    "extractionMeta": extractionMetaDef,
    "serviceItem": serviceItemDef,
]

// MARK: - Entity field tables
//
// `required` is exactly the set of non-optional Swift properties of the entity
// (Sources/TankbookCore/Domain). The test suite asserts every encoded key is
// declared here, so a Swift field added without a schema entry fails CI.

let vehicleProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "name": schemaString,
    "make": schemaString,
    "model": schemaString,
    "year": schemaInteger,
    "plate": schemaString,
    "powertrain": strEnum(powertrains),
    "fuelKinds": schemaArray(strEnum(fuelKinds)),
    "tankCapacityL": schemaNumber,
    "batteryCapacityKWh": schemaNumber,
    "homeCurrency": schemaCurrency,
    "units": schemaRef("units"),
    "photo": schemaUUID,
    "archived": schemaBoolean,
    "paceLimitKmPerDay": schemaNumber,
    // Optional, so it stays out of `required` below - a car saved without an
    // odometer reading is valid (docs/ERRORS.md -> Add car: the implausible
    // reading is a warning that never blocks save).
    "initialOdometer": schemaInteger,
]

let fillUpProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "date": schemaDate,
    "odometer": schemaInteger,
    "money": schemaRef("money"),
    "note": schemaString,
    "attachments": schemaArray(schemaUUID),
    "provenance": schemaRef("provenance"),
    "conflict": schemaRef("conflictState"),
    "purchaseGroupId": schemaUUID,
    "volumeL": schemaNumber,
    "unitPrice": schemaDecimal,
    "fuelKind": strEnum(fuelKinds),
    "fuelGrade": schemaString,
    "isFull": schemaBoolean,
    "tankLevelAfterPct": schemaNumber,
    "stationId": schemaUUID,
    "crossCheck": schemaRef("crossCheckState"),
    "extraction": schemaRef("extractionMeta"),
]

let chargeSessionProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "date": schemaDate,
    "odometer": schemaInteger,
    "money": schemaRef("money"),
    "note": schemaString,
    "attachments": schemaArray(schemaUUID),
    "provenance": schemaRef("provenance"),
    "conflict": schemaRef("conflictState"),
    "purchaseGroupId": schemaUUID,
    "energyKWh": schemaNumber,
    "unitPrice": schemaDecimal,
    "chargeType": strEnum(chargeTypes),
    "provider": schemaString,
    "tariffId": schemaUUID,
    "durationMin": schemaInteger,
    "socStartPct": schemaNumber,
    "socEndPct": schemaNumber,
    "extraction": schemaRef("extractionMeta"),
]

let serviceRecordProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "date": schemaDate,
    "odometer": schemaInteger,
    "money": schemaRef("money"),
    "note": schemaString,
    "attachments": schemaArray(schemaUUID),
    "provenance": schemaRef("provenance"),
    "conflict": schemaRef("conflictState"),
    "purchaseGroupId": schemaUUID,
    "vendor": schemaString,
    "items": schemaArray(schemaRef("serviceItem")),
    "usedParts": schemaArray(schemaUUID),
    "tireSetId": schemaUUID,
    "proposedReminderId": schemaUUID,
]

let expenseProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "date": schemaDate,
    "odometer": schemaInteger,
    "money": schemaRef("money"),
    "note": schemaString,
    "attachments": schemaArray(schemaUUID),
    "provenance": schemaRef("provenance"),
    "conflict": schemaRef("conflictState"),
    "purchaseGroupId": schemaUUID,
    "category": schemaRef("expenseCategory"),
    "title": schemaString,
    "recurrence": schemaRef("recurrenceRule"),
    "installedInServiceId": schemaUUID,
]

let reminderProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "title": schemaString,
    "category": schemaRef("reminderCategory"),
    "dueDate": schemaDate,
    "dueOdometer": schemaInteger,
    "recurrence": schemaRef("reminderRecurrence"),
    "sourceEntryId": schemaUUID,
    "status": schemaRef("reminderStatus"),
]

let stationProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "name": schemaString,
    "brand": schemaString,
    "location": schemaRef("geoCoordinate"),
    "favorite": schemaBoolean,
    "defaults": schemaRef("stationDefaults"),
    "lastUsedAt": schemaDate,
]

let tariffProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "name": schemaString,
    "pricePerKWh": schemaDecimal,
    "currency": schemaCurrency,
    "validFrom": schemaDate,
]

let tireSetProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "vehicleId": schemaUUID,
    "name": schemaString,
    "purchaseExpenseId": schemaUUID,
]

let attachmentProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "kind": strEnum(attachmentKinds),
    "file": schemaRef("localFileRef"),
    "extractedTimestamp": schemaDate,
    "ocrText": schemaString,
]

let preferencesProperties: [String: Any] = [
    "id": schemaUUID,
    "createdAt": schemaDate,
    "updatedAt": schemaDate,
    "deletedAt": schemaDate,
    "notifications": schemaRef("notifications"),
    "eagerMediaOnWiFi": schemaBoolean,
    "defaultVehicleId": schemaUUID,
    "proFeedbackDiagnostics": schemaBoolean,
]

/// The fields every timeline entry carries. Spelled out once so the per-entity
/// lists below stay readable; `required` is an ordered JSON array, so the
/// concatenation order here is part of the generated bytes - prefix first.
let entryCommonRequired = [
    "id", "createdAt", "updatedAt", "vehicleId", "date", "attachments", "provenance", "conflict",
]

/// entityType -> (properties, required). Required = non-optional Swift fields.
let entities: [String: ([String: Any], [String])] = [
    "vehicle": (vehicleProperties, [
        "id", "createdAt", "updatedAt", "name", "powertrain", "fuelKinds",
        "homeCurrency", "units", "archived", "paceLimitKmPerDay",
    ]),
    "fillUp": (fillUpProperties, entryCommonRequired + ["volumeL", "fuelKind", "isFull", "crossCheck"]),
    "chargeSession": (chargeSessionProperties, entryCommonRequired + ["energyKWh", "chargeType"]),
    "serviceRecord": (serviceRecordProperties, entryCommonRequired + ["items", "usedParts"]),
    "expense": (expenseProperties, entryCommonRequired + ["category", "title"]),
    "reminder": (reminderProperties, ["id", "createdAt", "updatedAt", "vehicleId", "title", "category", "status"]),
    "station": (stationProperties, ["id", "createdAt", "updatedAt", "name", "favorite", "defaults"]),
    "tariff": (tariffProperties, ["id", "createdAt", "updatedAt", "name", "pricePerKWh", "currency", "validFrom"]),
    "tireSet": (tireSetProperties, ["id", "createdAt", "updatedAt", "vehicleId", "name"]),
    "attachment": (attachmentProperties, ["id", "createdAt", "updatedAt", "kind", "file"]),
    "preferences": (preferencesProperties, ["id", "createdAt", "updatedAt", "notifications", "eagerMediaOnWiFi", "proFeedbackDiagnostics"]),
]

// MARK: - Fixture cross-check

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let fixturesDir = repoRoot.appendingPathComponent("docs/fixtures/payloads/v1")
let schemasDir = repoRoot.appendingPathComponent("docs/schemas/v1")

let fileManager = FileManager.default
guard fileManager.fileExists(atPath: fixturesDir.path) else {
    die("fixtures directory not found: \(fixturesDir.path)")
}
try? fileManager.createDirectory(at: schemasDir, withIntermediateDirectories: true)

let fixtureFiles = try fileManager.contentsOfDirectory(atPath: fixturesDir.path)
    .filter { $0.hasSuffix(".json") }
    .sorted()

for fixtureFile in fixtureFiles {
    let entityType = String(fixtureFile.dropLast(".json".count))
    guard let table = entities[entityType] else {
        die("fixture \(fixtureFile) has no field table entry for entity '\(entityType)'")
    }
    let data = try Data(contentsOf: fixturesDir.appendingPathComponent(fixtureFile))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        die("fixture \(fixtureFile) is not a JSON object")
    }
    let (properties, _) = table
    for key in json.keys.sorted() where properties[key] == nil {
        die("fixture \(fixtureFile) contains key '\(key)' that is missing from the \(entityType) field table")
    }
}

// MARK: - Emission

func emitSchema(entityType: String, properties: [String: Any], required: [String]) throws {
    var document: [String: Any] = [
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://tankbook.app/schemas/v1/\(entityType).schema.json",
        "title": entityType,
        "type": "object",
        "additionalProperties": true,
        "$defs": allDefs,
    ]
    if !required.isEmpty { document["required"] = required }
    if !properties.isEmpty { document["properties"] = properties }
    let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    let url = schemasDir.appendingPathComponent("\(entityType).schema.json")
    try data.write(to: url)
    print("wrote \(url.path)")
}

for entityType in entities.keys.sorted() {
    let (properties, required) = entities[entityType]!
    try emitSchema(entityType: entityType, properties: properties, required: required)
}
