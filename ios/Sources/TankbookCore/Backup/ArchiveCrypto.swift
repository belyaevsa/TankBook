import CommonCrypto
import CryptoKit
import Foundation

// The optional passphrase protection of a user-held export (docs/SCHEMA.md ->
// "Protection ... a user-held export can optionally be passphrase-protected
// (AES) at export time - no user-held key is ever required"). docs/SECURITY.md
// -> "Passphrase-protected exports".
//
// Shape: the manifest is NEVER sealed (it must open for the restore UI); each
// sealed payload is an independent AES-GCM box carrying its own salt so the
// same passphrase can seal any number of files without reusing a nonce.

/// Key derivation + AES-GCM for archive sealing. Every sealed file embeds its
/// salt, so no external IV/state is needed and each file stays self-describing.
public enum ArchiveCrypto {
    public static let kdfIterations = 100_000
    public static let keyLength = 32

    /// Derives the 32-byte AES key from a passphrase and a fresh/embedded salt
    /// (PBKDF2-SHA256, 100k iterations - the KDF documented in docs/SECURITY.md).
    /// Iteration count is a parameter so tests can use a fast round.
    static func key(passphrase: String, salt: [UInt8],
                    iterations: Int = kdfIterations) -> SymmetricKey {
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBufferPointer { saltBuffer -> Int32 in
            key.withUnsafeMutableBufferPointer { keyBuffer -> Int32 in
                // Swift bridges the String to the C function's temporary UTF-8
                // CString; `utf8.count` is its exact byte length.
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase,
                    passphrase.utf8.count,
                    saltBuffer.baseAddress,
                    saltBuffer.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    keyBuffer.baseAddress,
                    keyBuffer.count)
            }
        }
        precondition(status == 0, "PBKDF2 key derivation failed with status \(status)")
        return SymmetricKey(data: key)
    }

    /// Seals `plaintext` into a self-contained box: `salt || AES-GCM sealed`.
    public static func seal(_ plaintext: Data, passphrase: String,
                            iterations: Int = kdfIterations) throws -> Data {
        var salt = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        precondition(status == errSecSuccess, "entropy source unavailable")
        let key = key(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw VehicleArchiveError.underlying("AES-GCM produced no combined ciphertext")
        }
        var out = Data()
        out.append(contentsOf: salt)
        out.append(combined)
        return out
    }

    /// Opens a box written by `seal`. A wrong passphrase or a tampered box
    /// fails authentication and maps to `wrongPassphrase` (the caller cannot
    /// distinguish the two, and should not - same user-facing next step).
    public static func open(_ box: Data, passphrase: String,
                            iterations: Int = kdfIterations) throws -> Data {
        guard box.count >= 16 else {
            throw VehicleArchiveError.wrongPassphrase
        }
        let salt = Array(box.prefix(16))
        let combined = box.dropFirst(16)
        let key = key(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.SealedBox(combined: combined)
        do {
            return try AES.GCM.open(sealed, using: key)
        } catch {
            throw VehicleArchiveError.wrongPassphrase
        }
    }
}

/// Fast KDF for tests: the 100k default would burn seconds per archive.
extension ArchiveCrypto {
    static let testIterations = 1_000
}
