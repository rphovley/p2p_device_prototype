import Foundation
import CryptoKit

/// Encrypts/decrypts payloads with the pairing key. Used for both BLE message
/// bodies and the content field inside push-notification tickets, so the
/// Lambda relay and the OS push services never see plaintext.
public enum SecureEnvelope {
    public struct Sealed: Codable, Sendable {
        public let nonce: Data
        public let ciphertext: Data
        public let tag: Data

        public init(nonce: Data, ciphertext: Data, tag: Data) {
            self.nonce = nonce
            self.ciphertext = ciphertext
            self.tag = tag
        }
    }

    public enum EnvelopeError: Error {
        case invalidNonce
        case sealFailed
    }

    public static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Sealed {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw EnvelopeError.sealFailed }
        // combined = nonce (12) || ciphertext || tag (16)
        let nonce = combined.prefix(12)
        let tag = combined.suffix(16)
        let ciphertext = combined.dropFirst(12).dropLast(16)
        return Sealed(nonce: Data(nonce), ciphertext: Data(ciphertext), tag: Data(tag))
    }

    public static func open(_ sealed: Sealed, using key: SymmetricKey) throws -> Data {
        guard let nonce = try? AES.GCM.Nonce(data: sealed.nonce) else {
            throw EnvelopeError.invalidNonce
        }
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: sealed.ciphertext, tag: sealed.tag)
        return try AES.GCM.open(box, using: key)
    }
}
