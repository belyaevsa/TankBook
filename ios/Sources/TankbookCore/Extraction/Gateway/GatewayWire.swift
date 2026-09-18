import Foundation

// MARK: - P6.3 the /extract wire shapes (docs/API.md -> "LLM gateway (Pro)").
//
// POST /extract -> { fields: { <FieldRef>: { value, confidence } }, pipeline }.
// The response is exactly the SCHEMA.md `ExtractionMeta` shape; the client
// decodes it into typed, optional field values - the gateway is a suggestion
// engine, so a field it could not read is absent, never guessed (hard rule 13).
//
// FieldRef uses the existing `FieldRef` enum (total, volume, unitPrice, date,
// fuelKind, currency, vendor, category) so the gateway and the on-device
// pipeline speak one vocabulary of fields.

/// One field value from the gateway plus its confidence. The confidence is
/// carried and shown, never used to decide - the corpus proved a wrong digit at
/// confidence 1.00 (docs/EXTRACTION.md -> pump-004).
///
/// `Codable` (RV.38) so a late answer can be persisted into the device-local
/// inbox and re-read on relaunch - the inbox is best-effort, but an answer that
/// DID arrive must not be lost because the app happened to close.
public struct GatewayFieldValue<Value: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {
    public var value: Value
    public var confidence: Double

    public init(value: Value, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }
}

/// The decoded `/extract` response: the fields the model read, each a
/// suggestion the user may accept, edit or reject.
///
/// `Codable` (RV.38) so a late answer can live in the device-local inbox
/// (`GatewayInboxItem`) and survive a relaunch; the inbox is best-effort about
/// answers that never arrive, but an arrived answer is retained (30-day-style
/// tombstone not needed - inbox items are cleared by resolution, not age).
public struct GatewayExtraction: Sendable, Equatable, Codable {
    public var total: GatewayFieldValue<Decimal>?
    public var volume: GatewayFieldValue<Double>?
    public var unitPrice: GatewayFieldValue<Decimal>?
    public var date: GatewayFieldValue<String>?
    public var fuelKind: GatewayFieldValue<FuelKind>?
    public var currency: GatewayFieldValue<CurrencyCode>?
    /// The VENDOR an `invoice` answer read (PJ.29a): a service invoice's header
    /// names the workshop, and `ServiceRecognition` offers it to the form and
    /// the inbox. The `invoice` and `expense` prompts allow it; a fuel answer
    /// that carries one has no home here and it is simply not offered.
    public var vendor: GatewayFieldValue<String>?
    /// The expense CATEGORY an `expense`-kind answer read (PJ.29): a shop or
    /// parking receipt has no fuel fields, so the field the form needs is the
    /// kind of expense it is. Absent on every fuel answer and on an answer whose
    /// category string the device does not know - the value is decoded against
    /// the `ExpenseCategory` codes, and an unknown string is dropped, never
    /// guessed (hard rule 13).
    public var category: GatewayFieldValue<ExpenseCategory>?
    /// The invoice's LINE ITEMS a multi-page `invoice` answer read (PJ.302,
    /// docs/API.md "multi-page invoices"): `lineItem[n].title/amount/category`
    /// gathered by index, in printed order. Empty on every other answer and on
    /// a header-only invoice reading. A line with neither a title nor an
    /// amount is dropped at decode; a category string the device does not know
    /// is dropped from its line, never guessed (hard rule 13).
    public var lineItems: [GatewayLineItem]
    /// The provider/pipeline id the server reports (docs/SCHEMA.md,
    /// `ExtractionMeta.pipeline`), for regression tracking.
    public var pipeline: String

    public init(
        total: GatewayFieldValue<Decimal>? = nil,
        volume: GatewayFieldValue<Double>? = nil,
        unitPrice: GatewayFieldValue<Decimal>? = nil,
        date: GatewayFieldValue<String>? = nil,
        fuelKind: GatewayFieldValue<FuelKind>? = nil,
        currency: GatewayFieldValue<CurrencyCode>? = nil,
        vendor: GatewayFieldValue<String>? = nil,
        category: GatewayFieldValue<ExpenseCategory>? = nil,
        lineItems: [GatewayLineItem] = [],
        pipeline: String = ""
    ) {
        self.total = total
        self.volume = volume
        self.unitPrice = unitPrice
        self.date = date
        self.fuelKind = fuelKind
        self.currency = currency
        self.vendor = vendor
        self.category = category
        self.lineItems = lineItems
        self.pipeline = pipeline
    }

    /// The fields this answer actually carries values for. The late-answer
    /// policy (docs/API.md rule 3) is decided per field over this set.
    public var providedFields: Set<FieldRef> {
        var out = Set<FieldRef>()
        if total != nil { out.insert(.total) }
        if volume != nil { out.insert(.volume) }
        if unitPrice != nil { out.insert(.unitPrice) }
        if date != nil { out.insert(.date) }
        if fuelKind != nil { out.insert(.fuelKind) }
        if currency != nil { out.insert(.currency) }
        if vendor != nil { out.insert(.vendor) }
        if category != nil { out.insert(.category) }
        return out
    }
}

/// One line item a multi-page invoice answer read (PJ.302). Each member is
/// its own field on the wire with its own confidence; the index is the printed
/// order the provider assigned.
public struct GatewayLineItem: Sendable, Equatable, Codable {
    public var index: Int
    public var title: GatewayFieldValue<String>?
    public var amount: GatewayFieldValue<Decimal>?
    public var category: GatewayFieldValue<ServiceCategory>?

    public init(index: Int, title: GatewayFieldValue<String>? = nil,
                amount: GatewayFieldValue<Decimal>? = nil,
                category: GatewayFieldValue<ServiceCategory>? = nil) {
        self.index = index
        self.title = title
        self.amount = amount
        self.category = category
    }
}

/// The request body for `POST /extract`.
public struct GatewayExtractRequest: Sendable, Equatable {
    /// One of the kinds the server accepts (docs/API.md): `receipt`, `pump`,
    /// `chargeScreenshot`, `invoice`, `expense`.
    public var kind: String
    /// The rendition's JPEG bytes, produced by `GatewayRendition` - the one
    /// page of every kind but a multi-page invoice, whose pages are `pages`.
    public var imageJPEG: Data
    /// The FURTHER pages of a multi-page invoice (PJ.302), after `imageJPEG`,
    /// in order. Non-empty only for `kind == "invoice"`; the encoder then sends
    /// `images` (every page) and the answer carries the line items. Empty for
    /// every other kind and for an invoice sent the header-only way.
    public var pages: [Data]
    /// The optional context hints the server forwards to the provider.
    public var hints: GatewayExtractHints
    /// The device's own correlation token (RV.44): echoed opaquely into the
    /// delivery-outbox payload when the answer cannot be handed back, so the
    /// device can match a drained answer to the entry it belongs to. nil for a
    /// caller that has nothing to correlate (an older path).
    public var captureId: String?

    public init(
        kind: String,
        imageJPEG: Data,
        pages: [Data] = [],
        hints: GatewayExtractHints = GatewayExtractHints(),
        captureId: String? = nil
    ) {
        self.kind = kind
        self.imageJPEG = imageJPEG
        self.pages = pages
        self.hints = hints
        self.captureId = captureId
    }

    /// Every page in order: `imageJPEG` first, then `pages`.
    public var allPages: [Data] { [imageJPEG] + pages }

    /// Whether this request travels as `images` (the multi-page invoice shape
    /// that asks for line items): an invoice with any page beyond the first.
    public var isMultiPage: Bool { kind == "invoice" && !pages.isEmpty }
}

/// The optional `hints` object of the request (docs/API.md): what the device
/// already knows, offered as context - never as facts the provider must obey.
public struct GatewayExtractHints: Sendable, Equatable {
    public var currency: String?
    public var locale: String?
    public var vehicleFuelKinds: [String]

    public init(currency: String? = nil, locale: String? = nil, vehicleFuelKinds: [String] = []) {
        self.currency = currency
        self.locale = locale
        self.vehicleFuelKinds = vehicleFuelKinds
    }
}

/// Client-side failures the transport can raise that are not a server
/// classification. The server status codes themselves are consumed as
/// `SyncServerError` (P6.11) - this enum is only for a malformed response or an
/// envelope the client itself produced.
public enum GatewayExtractError: Error, Equatable, Sendable {
    /// The response body was not a decodable `{ fields, pipeline }` shape.
    case invalidResponse
    /// The request's base64 image would exceed the 4 MB envelope cap
    /// (docs/API.md). The rendition settings are tuned far below this, so
    /// reaching it means a bug, not a normal path.
    case envelopeTooLarge
    /// More invoice pages than the served cap (`extract.maxInvoicePages`,
    /// PJ.302): the camera stops at the cap, so reaching this is a bug too.
    case tooManyPages(cap: Int)
}

// MARK: - Decoding

extension GatewayExtraction {
    /// Decodes a `POST /extract` response body. Unknown field refs and
    /// unparseable values are skipped - a newer server may return fields this
    /// client does not render, and dropping them is forward compatibility, not
    /// data loss (the on-device result already stands).
    public static func decode(_ data: Data) throws -> GatewayExtraction {
        let tree: JSONValue
        do {
            tree = try JSONValue.parse(data)
        } catch {
            throw GatewayExtractError.invalidResponse
        }
        guard let object = tree.objectValue else { throw GatewayExtractError.invalidResponse }
        let fields = object["fields"]?.objectValue ?? [:]
        let pipeline = object["pipeline"]?.stringValue ?? ""

        var extraction = GatewayExtraction(pipeline: pipeline)
        var lines: [Int: GatewayLineItem] = [:]
        for (rawRef, fieldNode) in fields {
            guard let field = fieldNode.objectValue,
                  let valueNode = field["value"] else { continue }
            let confidence = field["confidence"]?.numericValue ?? 0
            if let (index, member) = lineItemRef(rawRef) {
                var line = lines[index] ?? GatewayLineItem(index: index)
                line.apply(member: member, valueNode: valueNode, confidence: confidence)
                lines[index] = line
                continue
            }
            guard let ref = FieldRef(string: rawRef) else { continue }
            extraction.apply(ref: ref, valueNode: valueNode, confidence: confidence)
        }
        extraction.lineItems = lines.values
            .filter { $0.title != nil || $0.amount != nil }
            .sorted { $0.index < $1.index }
        return extraction
    }

    /// `lineItem[n].member` → (n, member); nil for any other ref.
    static func lineItemRef(_ raw: String) -> (Int, String)? {
        guard raw.hasPrefix("lineItem["),
              let close = raw.firstIndex(of: "]"),
              let index = Int(raw[raw.index(raw.startIndex, offsetBy: 9)..<close]),
              raw[raw.index(after: close)...].hasPrefix(".") else { return nil }
        let member = String(raw[raw.index(close, offsetBy: 2)...])
        return member.isEmpty ? nil : (index, member)
    }

    /// Decodes one field node into the typed value the extraction holds, or nil
    /// when the value is unparseable for its field (skipped, never fatal).
    private static func parsedValue(ref: FieldRef, node: JSONValue) -> (any Sendable & Equatable)? {
        switch ref {
        case .total, .unitPrice:
            guard let token = numericToken(node),
                  let value = Decimal(string: token, locale: posix) else { return nil }
            return value
        case .volume:
            guard let token = numericToken(node), let value = Double(token) else { return nil }
            return value
        case .date, .vendor:
            return node.stringValue
        default:
            return parsedEnumValue(ref: ref, node: node)
        }
    }

    /// The string-valued fields - the fuel kind, the currency and the expense
    /// category - decoded from their canonical string. An unknown string is nil
    /// for that field, dropped rather than guessed (hard rule 13).
    private static func parsedEnumValue(ref: FieldRef, node: JSONValue) -> (any Sendable & Equatable)? {
        guard let raw = node.stringValue else { return nil }
        switch ref {
        case .fuelKind: return FuelKind(rawValue: raw)
        case .currency: return CurrencyCode(rawValue: raw)
        case .category: return ExpenseCategory(gatewayValue: raw)
        default: return nil
        }
    }

    /// The raw number token: `.number` carries it exactly; a quoted string the
    /// provider sometimes emits is accepted when it parses as a number.
    fileprivate static func numericToken(_ node: JSONValue) -> String? {
        switch node {
        case .number(let token): return token
        case .string(let token) where Double(token) != nil: return token
        default: return nil
        }
    }

    fileprivate static let posix = Locale(identifier: "en_US_POSIX")
}

extension GatewayLineItem {
    /// One `lineItem[n].<member>` field; an unknown member or an unparseable
    /// value is skipped, never fatal.
    fileprivate mutating func apply(member: String, valueNode: JSONValue, confidence: Double) {
        switch member {
        case "title":
            if let text = valueNode.stringValue, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                title = .init(value: text, confidence: confidence)
            }
        case "amount":
            if let token = GatewayExtraction.numericToken(valueNode),
               let value = Decimal(string: token, locale: GatewayExtraction.posix) {
                amount = .init(value: value, confidence: confidence)
            }
        case "category":
            if let raw = valueNode.stringValue, let category = ServiceCategory(gatewayValue: raw) {
                self.category = .init(value: category, confidence: confidence)
            }
        default:
            break
        }
    }
}

extension GatewayExtraction {
    private mutating func apply(ref: FieldRef, valueNode: JSONValue, confidence: Double) {
        guard let value = GatewayExtraction.parsedValue(ref: ref, node: valueNode) else { return }
        switch ref {
        case .total: total = (value as? Decimal).map { .init(value: $0, confidence: confidence) }
        case .volume: volume = (value as? Double).map { .init(value: $0, confidence: confidence) }
        case .unitPrice: unitPrice = (value as? Decimal).map { .init(value: $0, confidence: confidence) }
        case .date: date = (value as? String).map { .init(value: $0, confidence: confidence) }
        case .fuelKind: fuelKind = (value as? FuelKind).map { .init(value: $0, confidence: confidence) }
        case .currency: currency = (value as? CurrencyCode).map { .init(value: $0, confidence: confidence) }
        case .vendor: vendor = (value as? String).map { .init(value: $0, confidence: confidence) }
        case .category: category = (value as? ExpenseCategory).map { .init(value: $0, confidence: confidence) }
        default: break
        }
    }
}
