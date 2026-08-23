import Foundation
import os

/// Generator state for RFC 9562 version-7 UUIDs.
private struct UUIDv7State {
    var lastMillis: UInt64
    var counter: UInt16

    init() {
        lastMillis = UUIDv7State.currentMillis()
        counter = .random(in: 0 ... 0x0FFF)
    }

    static func currentMillis() -> UInt64 {
        let millis = Date().timeIntervalSince1970 * 1000
        return UInt64(max(0, millis.rounded()))
    }
}

private let uuidv7Lock = OSAllocatedUnfairLock(initialState: UUIDv7State())

extension UUID {
    /// Generates a version-7 (RFC 9562) UUID: a 48-bit millisecond timestamp
    /// followed by version/variant bits and a 12-bit monotonic counter, so IDs
    /// generated within the same millisecond still sort in creation order.
    /// IDs are generated on device and stay stable across sync/backup
    /// (docs/SCHEMA.md, Identifiers & sync envelope).
    public static func v7() -> UUID {
        uuidv7Lock.withLock { state in
            let now = UUIDv7State.currentMillis()
            if now > state.lastMillis {
                state.lastMillis = now
                state.counter = .random(in: 0 ... 0x0FFF)
            } else {
                // Same millisecond (or a stepped-back clock): bump the counter
                // to preserve ordering. On 12-bit overflow, advance the stored
                // millisecond by one to keep strict monotonic ordering.
                state.counter &+= 1
                if state.counter > 0x0FFF {
                    state.counter = 0
                    state.lastMillis &+= 1
                }
            }
            return makeV7UUID(millis: state.lastMillis, counter: state.counter)
        }
    }

    /// The RFC 9562 version nibble of this UUID (7 for v7).
    var versionNibble: UInt8 {
        withUnsafeBytes(of: uuid) { bytes in
            bytes[6] >> 4
        }
    }

    /// The RFC 9562 variant bits of this UUID (2 for the standard layout).
    var variantBits: UInt8 {
        withUnsafeBytes(of: uuid) { bytes in
            bytes[8] >> 6
        }
    }
}

private func makeV7UUID(millis: UInt64, counter: UInt16) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    bytes[0] = UInt8((millis >> 40) & 0xFF)
    bytes[1] = UInt8((millis >> 32) & 0xFF)
    bytes[2] = UInt8((millis >> 24) & 0xFF)
    bytes[3] = UInt8((millis >> 16) & 0xFF)
    bytes[4] = UInt8((millis >> 8) & 0xFF)
    bytes[5] = UInt8(millis & 0xFF)
    bytes[6] = 0x70 | UInt8((counter >> 8) & 0x0F)
    bytes[7] = UInt8(counter & 0xFF)
    var generator = SystemRandomNumberGenerator()
    bytes[8] = 0x80 | UInt8.random(in: 0 ... 0x3F, using: &generator)
    for index in 9 ..< 16 {
        bytes[index] = UInt8.random(in: 0 ... 0xFF, using: &generator)
    }
    return UUID(uuid: bytes.withUnsafeBytes { raw in
        raw.load(as: uuid_t.self)
    })
}
