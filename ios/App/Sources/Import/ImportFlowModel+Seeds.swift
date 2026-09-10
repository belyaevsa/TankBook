import Foundation
import TankbookCore

// RV.86/RV.93: the model's DEBUG/test seams and single-file adopt helpers, in
// an extension so ImportFlowModel's declaration stays under the repo's lint
// floors. `syncMergedParse` is production (the whole-export batch re-derives
// through it after every pick or date-format answer); the installSeeded*
// methods drive the UI tests and screenshots from launch arguments
// (ImportTestSeed) and from core unit tests, never from a server or picker.

extension ImportFlowModel {
    // MARK: - Test seams

    /// Re-derives the merged parse (`parse`, `mergedRawLines`) from the current
    /// `parseFiles` and the once-per-export `dateFormatAnswer` (RV.93). Called
    /// after every change to either. The merge is pure core logic: it re-keys
    /// every file's rows into one global space, unions the cars by name and
    /// applies the D/M date flip per file that needs it - so the single `parse`
    /// every downstream reader already understands becomes the whole export.
    func syncMergedParse() {
        guard !parseFiles.isEmpty else {
            parse = nil
            mergedRawLines = [:]
            return
        }
        let view = ImportBatchMerge.merge(
            files: parseFiles.map {
                ImportParsedFile(parse: $0.parse,
                                 rawLines: ImportRawLines.dataLines(from: $0.rawData))
            },
            dateFormatAnswer: dateFormatAnswer)
        parse = view?.parse
        mergedRawLines = view?.rawLinesByRow ?? [:]
    }

    /// Replaces the pick with one parsed file (the single-file seeds) and
    /// re-derives the merged view.
    func adoptSingleFile(fileName: String, rawData: Data, parse: ImportParseResponse) {
        parseFiles = [ImportParseFile(fileName: fileName, rawData: rawData, parse: parse)]
        pickedFileName = fileName
        uploadedFileData = rawData
        syncMergedParse()
    }

    /// Installs a stub parse response directly (no file picker) so the UI tests
    /// and screenshots drive the preview/review against a known fixture. The
    /// parse bytes come from the same bundle resources the stub transport
    /// serves; `rawFileResource` is the ORIGINAL file (the real CSV export) the
    /// parse claims to have read, so the review list's "Original row" renders a
    /// real source line instead of the wire envelope (P6.15c).
    func installSeededParse(resourceName: String, fileName: String,
                            rawFileResource: String? = nil) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(ImportParseResponse.self, from: data) else { return }
        let rawData: Data
        if let rawFileResource,
           let rawURL = Bundle.main.url(forResource: rawFileResource, withExtension: "csv"),
           let csvData = try? Data(contentsOf: rawURL) {
            rawData = csvData
        } else {
            rawData = data
        }
        adoptSingleFile(fileName: fileName, rawData: rawData, parse: result)
        dateFormatAnswer = nil
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// Installs a stub parse whose candidates mix fill-ups and a `serviceRecord`
    /// row (PJ.9), so the UI tests and screenshots drive the non-fuel action and
    /// the mixed commit against a known fixture without a server. The uploaded
    /// file data is a real-looking MFM costs fragment so "Original row" renders
    /// a source line.
    func installSeededServiceParse() {
        let money = ImportMoney(amount: "125.50", currency: "USD")
        let item = ImportServiceItem(title: "Oil change", category: ImportCategoryTag(tag: "oil"),
                                     cost: money)
        let serviceCandidate = ImportCandidate(
            entityType: "serviceRecord",
            date: Date(timeIntervalSince1970: 1_752_307_200),  // 2026-07-20
            odometer: 119_486, volumeL: nil, unitPrice: nil, money: money,
            fuelKind: nil, isFull: nil, tankLevelAfterPct: nil, note: "Oil change",
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 1, items: [item])
        let fillCandidate = ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_752_393_600),  // 2026-07-21
            odometer: 119_486, volumeL: 55, unitPrice: "1.85", money: ImportMoney(amount: "101.75", currency: "USD"),
            fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: "Neste",
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 2)
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000303", format: "mfm",
            scope: "vehicle", candidates: [serviceCandidate, fillCandidate],
            unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        adoptSingleFile(fileName: "MyFuelManager_costs_2026.csv",
                        rawData: Data("""
                        My Fuel Manager - Costs
                        Date;Category;Odometer;Total price;Currency;Note;Vehicle name
                        7/20/2026;Oil;119486;125.50;USD;Oil change;"Volvo"
                        """.utf8),
                        parse: response)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// Installs a stub parse whose fills break the odometer order (PJ.11): row
    /// 2's `9` mirrors the real MFM defect (`Spike/ImportFixtures/mfm/README.md`)
    /// and must appear in the review list badged "Breaks the timeline".
    func installSeededTimelineParse() {
        func fill(_ row: Int, _ date: Date, _ odo: Int, _ note: String) -> ImportCandidate {
            ImportCandidate(
                entityType: "fillUp", date: date, odometer: odo, volumeL: 55,
                unitPrice: "1.85", money: ImportMoney(amount: "101.75", currency: "USD"),
                fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: note,
                vehicleName: "Volvo",
                provenance: ImportProvenance(tag: "import", source: "mfm"),
                sourceRow: row)
        }
        let fillCandidates = [
            fill(1, Date(timeIntervalSince1970: 1_787_529_600), 121_727, "Neste"),
            fill(2, Date(timeIntervalSince1970: 1_786_320_000), 9, "Shell"),
            fill(3, Date(timeIntervalSince1970: 1_784_332_800), 120_559, "Circle K")
        ]
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000304", format: "mfm",
            scope: "vehicle", candidates: fillCandidates,
            unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        adoptSingleFile(fileName: "MyFuelManager_2026-08.csv",
                        rawData: Data("""
                        My Fuel Manager - Fuel
                        Date;Odometer;Fillup volume;Total price;Currency;Note;Vehicle name
                        8/24/2026;121727;55;101.75;USD;Neste;"Volvo"
                        8/10/2026;9;55;101.75;USD;Shell;"Volvo"
                        7/18/2026;120559;55;101.75;USD;Circle K;"Volvo"
                        """.utf8),
                        parse: response)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// RV.85: installs a stub parse for a DETECTABLE file - one whose own rows
    /// prove D/M (12/01 and 13/05 only read day-first), so the post-fix server
    /// resolves every date and returns NO `dateFormat` ambiguity. The preview
    /// must not ask, and the dates it shows are the resolved readings: January
    /// and May 2026, never the M/D misreading (which would read 12/01 as
    /// December and could not read 13/05 at all).
    func installSeededResolvedDatesParse() {
        func fill(_ row: Int, _ date: Date, _ odo: Int) -> ImportCandidate {
            ImportCandidate(
                entityType: "fillUp", date: date, odometer: odo, volumeL: 55,
                unitPrice: "1.85", money: ImportMoney(amount: "101.75", currency: "USD"),
                fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100,
                note: nil, vehicleName: "Volvo",
                provenance: ImportProvenance(tag: "import", source: "mfm"),
                sourceRow: row)
        }
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000305", format: "mfm",
            scope: "vehicle",
            candidates: [
                fill(1, Date(timeIntervalSince1970: 1_768_176_000), 100_000),  // 2026-01-12
                fill(2, Date(timeIntervalSince1970: 1_778_630_400), 100_500),  // 2026-05-13
            ],
            unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        adoptSingleFile(fileName: "MyFuelManager_2026.csv",
                        rawData: Data("""
                        My Fuel Manager - Fuel
                        Date;Fillup volume;Odometer;Total price;Currency;Fuel;Tank status after fillup;%;Note;Vehicle name
                        12/01/2026;50;100000;92;USD;2;F;100;"";"Volvo"
                        13/05/2026;55;100500;101;USD;2;F;100;"";"Volvo"
                        """.utf8),
                        parse: response)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    // MARK: - Source step

    /// RV.86: installs a stub MULTI-CAR parse (no file picker/server) so the UI
    /// tests and screenshots drive the `.cars` mapping step against a known
    /// fixture. Same discipline as `installSeededParse`: the raw CSV is the
    /// ORIGINAL file the parse claims to have read, so "Original row" renders a
    /// real source line. Routing goes through `routeAfterParse`, so the wizard
    /// lands on the mapping step with every destination undecided.
    func installSeededCarsParse(resourceName: String, fileName: String,
                                rawFileResource: String?) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(ImportParseResponse.self, from: data) else { return }
        let rawData: Data
        if let rawFileResource,
           let rawURL = Bundle.main.url(forResource: rawFileResource, withExtension: "csv"),
           let csvData = try? Data(contentsOf: rawURL) {
            rawData = csvData
        } else {
            rawData = data
        }
        adoptSingleFile(fileName: fileName, rawData: rawData, parse: result)
        dateFormatAnswer = nil
        routeAfterParse(preferredVehicleID: nil)
        step = .cars
    }

    /// RV.113: installs a stub Drivvo parse whose candidates carry money with an
    /// EMPTY currency and a `currency` ambiguity with empty options - the wire's
    /// signal that the file has no currency column, so the wizard must ask. The
    /// default offered is the destination car's home currency (EUR for the seeded
    /// Volvo), and the answer reaches every committed row.
    /// RV.189: installs a stub Drivvo parse whose fill carries the file's
    /// station (`Газпром`) - the owner's case, where the Log row must title
    /// itself with the station. The destination car's usual fuel is set to the
    /// row's kind so the fuel kind earns no subtitle place: before the fix the
    /// fill lost its station in the batch merge and the row titled itself
    /// "92", the owner's report.
    func installSeededStationParse() {
        if var vehicle = (try? repository.liveVehicles())?.first {
            vehicle.fuelKinds = [.petrol92]
            try? repository.upsertVehicle(vehicle)
            liveVehicles = [vehicle]
            targetCar = .existing(vehicle)
        }
        let candidate = ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_786_924_800),  // 2026-08-17
            odometer: 121_727, volumeL: 40, unitPrice: "220",
            money: ImportMoney(amount: "8800", currency: "EUR"),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: 1, station: "Газпром")
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000189", format: "drivvo",
            scope: "vehicle", candidates: [candidate], unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        currencyAnswer = nil
        adoptSingleFile(fileName: "Drivvo_export.csv",
                        rawData: Data("""
                        ##Refuelling
                        "Odometer (km)","Date","Fuel","Price / l","Total cost","Volume","Full tank","Азс"
                        "121727.0","2025-08-24 17:37:33","Бензин АИ92","220","8800","40","Да","Газпром"
                        """.utf8),
                        parse: response)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    func installSeededCurrencyParse() {
        func fill(_ row: Int, _ date: Date, _ odo: Int, _ amount: String) -> ImportCandidate {
            ImportCandidate(
                entityType: "fillUp", date: date, odometer: odo, volumeL: 40,
                unitPrice: "220", money: ImportMoney(amount: amount, currency: ""),
                fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
                vehicleName: nil, provenance: ImportProvenance(tag: "import", source: "drivvo"),
                sourceRow: row)
        }
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000310", format: "drivvo",
            scope: "vehicle",
            candidates: [
                fill(1, Date(timeIntervalSince1970: 1_786_924_800), 491_206, "8442"),  // 2026-08-17
                fill(2, Date(timeIntervalSince1970: 1_787_529_600), 491_791, "6630"),  // 2026-08-24
            ],
            unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency", options: [], rowCount: 2)])
        dateFormatAnswer = nil
        currencyAnswer = nil
        adoptSingleFile(fileName: "Drivvo_export.csv",
                        rawData: Data("""
                        ##Refuelling
                        "Odometer (km)","Date","Fuel","Price / l","Total cost","Volume","Full tank"
                        "491206.0","2025-08-02 06:55:11","Petrol 92","220","8442","40","Yes"
                        "491791.0","2025-08-24 17:37:33","Petrol 92","225","6630","40","Yes"
                        """.utf8),
                        parse: response)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// RV.116: installs a stub Drivvo parse that reports unsupported columns
    /// with non-zero counts (Driver 250, Payment method 12) and declares them
    /// through the picked format. The preview must show the "not imported"
    /// notice WITH those counts and must not disable Continue.
    func installSeededUnsupportedParse() {
        guard let url = Bundle.main.url(forResource: "import-parse-unsupported", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(ImportParseResponse.self, from: data) else { return }
        pickedFormat = ImportFormat(id: "drivvo", displayName: "Drivvo", fileKinds: ["csv"],
                                    helpUrl: "https://tankbook.live/import-guide/",
                                    addedInPackVersion: 1,
                                    unsupportedColumns: ["Driver", "Payment method", "Discount"])
        dateFormatAnswer = nil
        currencyAnswer = nil
        adoptSingleFile(fileName: "Drivvo_export.csv",
                        rawData: Data("""
                        ##Refuelling
                        "Одометр (км)","Дата","Топливо","Цена / л","Общая стоимость","Объем","Полный бак","Азс","Водитель","Метод оплаты"
                        "491206.0","2026-08-17 06:55:11","Бензин АИ92","220","8442","40","Да","Газпром","driver-a","card"
                        "491791.0","2026-08-24 17:37:33","Бензин АИ92","225","6630","40","Да","Газпром","driver-b",""
                        """.utf8),
                        parse: result)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }

    /// RV.93: installs a stub WHOLE-EXPORT pick (two files, no picker/server)
    /// so the UI tests drive the "one mapping for several files" surface: the
    /// fuel file holds two cars (the RV.86 fixture), the costs file holds a
    /// Volvo service row. The merged view must ask ONE mapping question per
    /// distinct car - two cards, never three - and committing must land both
    /// kinds (a fill and a service) on the mapped cars.
    func installSeededBatchParse() {
        guard let url = Bundle.main.url(forResource: "import-parse-mfm-cars", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let fuelParse = try? decoder.decode(ImportParseResponse.self, from: data),
              let rawURL = Bundle.main.url(forResource: "import-mfm-cars", withExtension: "csv"),
              let fuelRaw = try? Data(contentsOf: rawURL) else { return }

        let money = ImportMoney(amount: "133", currency: "USD")
        let item = ImportServiceItem(title: "Replacement parts",
                                     category: ImportCategoryTag(tag: "parts"), cost: money)
        let service = ImportCandidate(
            entityType: "serviceRecord",
            date: Date(timeIntervalSince1970: 1_775_174_400),  // 2026-04-27
            odometer: 106_722, volumeL: nil, unitPrice: nil, money: money,
            fuelKind: nil, isFull: nil, tankLevelAfterPct: nil,
            note: "Замена колес зима -> лето", vehicleName: "Volvo",
            provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 1, items: [item])
        let costsParse = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000306", format: "mfm",
            scope: "vehicle", candidates: [service],
            unparsed: [], ambiguities: [])
        let costsRaw = Data("""
        My Fuel Manager - COSTS
        Date;Total price;Currency;Finance category;Odometer;Note;Vehicle name
        4/27/2026;133;USD;"Replacement parts";106722;"Замена колес зима -> лето";"Volvo"
        """.utf8)

        parseFiles = [
            ImportParseFile(fileName: "MyFuelManager_fuel.csv",
                            rawData: fuelRaw, parse: fuelParse),
            ImportParseFile(fileName: "MyFuelManager_costs.csv",
                            rawData: costsRaw, parse: costsParse),
        ]
        pickedFileName = nil
        fileFailures = []
        dateFormatAnswer = nil
        syncMergedParse()
        routeAfterParse(preferredVehicleID: nil)
        step = .cars
    }

    /// RV.93: installs a stub two-file pick whose SAME-car rows contradict
    /// ACROSS the files - the shape only a merged single timeline can flag
    /// before the write: the second file's fill (4/27 @ 107500) sits above the
    /// first file's 5/3 fill (107292), so 4/27 -> 5/3 falls. Classifying each
    /// file alone (the RV.93 defect) misses it entirely. The UI test drives
    /// the review gate to assert the flag appears BEFORE anything is written.
    func installSeededBatchAnomalyParse() {
        func fill(_ row: Int, _ date: Date, _ odo: Int) -> ImportCandidate {
            ImportCandidate(
                entityType: "fillUp", date: date, odometer: odo, volumeL: 60,
                unitPrice: "1.85", money: ImportMoney(amount: "111.00", currency: "USD"),
                fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100,
                note: nil, vehicleName: "Volvo",
                provenance: ImportProvenance(tag: "import", source: "mfm"),
                sourceRow: row)
        }
        let fuel = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000307", format: "mfm",
            scope: "vehicle",
            candidates: [
                fill(1, Date(timeIntervalSince1970: 1_776_643_200), 106_470),  // 2026-04-20
                fill(2, Date(timeIntervalSince1970: 1_777_766_400), 107_292),  // 2026-05-03
            ],
            unparsed: [], ambiguities: [],
            vehicleGroups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2])])
        let audiFill = ImportCandidate(
            entityType: "fillUp", date: Date(timeIntervalSince1970: 1_776_643_200),
            odometer: 420_000, volumeL: 60, unitPrice: "1.85",
            money: ImportMoney(amount: "111.00", currency: "USD"),
            fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100,
            note: nil, vehicleName: "AUDI A4",
            provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 3)
        let fuelWithAudi = ImportParseResponse(
            importId: fuel.importId, format: "mfm", scope: "vehicle",
            candidates: fuel.candidates + [audiFill], unparsed: [], ambiguities: [],
            vehicleGroups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2]),
                            ImportVehicleGroup(name: "AUDI A4", sourceRows: [3])])
        let second = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000308", format: "mfm",
            scope: "vehicle",
            candidates: [fill(1, Date(timeIntervalSince1970: 1_777_248_000), 107_500)],
            unparsed: [], ambiguities: [],
            vehicleGroups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1])])
        let fuelRaw = Data("""
        My Fuel Manager - Fuel
        Date;Odometer;Note;Vehicle name
        4/20/2026;106470;"";"Volvo"
        5/3/2026;107292;"";"Volvo"
        4/20/2026;420000;"";"AUDI A4"
        """.utf8)
        let secondRaw = Data("""
        My Fuel Manager - Fuel
        Date;Odometer;Note;Vehicle name
        4/27/2026;107500;"";"Volvo"
        """.utf8)

        parseFiles = [
            ImportParseFile(fileName: "MyFuelManager_fuel.csv", rawData: fuelRaw,
                            parse: fuelWithAudi),
            ImportParseFile(fileName: "MyFuelManager_costs.csv", rawData: secondRaw,
                            parse: second),
        ]
        pickedFileName = nil
        fileFailures = []
        dateFormatAnswer = nil
        syncMergedParse()
        routeAfterParse(preferredVehicleID: nil)
        step = .cars
    }

}
