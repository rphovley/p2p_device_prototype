import Foundation
import CryptoKit

/// The result of a successful QR pairing: who we're talking to, and the key
/// used to encrypt everything that follows (BLE payloads, push tickets).
///
/// Both apps store this in the Keychain and never show it again — encoding
/// it back into a QR code is a one-way operation used only at pairing time.
public struct PairingIdentity: Codable, Equatable, Sendable {
    public let pairingID: UUID
    public let secretKey: SymmetricKey

    public init(pairingID: UUID, secretKey: SymmetricKey) {
        self.pairingID = pairingID
        self.secretKey = secretKey
    }

    public init() {
        self.init(pairingID: UUID(), secretKey: SymmetricKey(size: .bits256))
    }

    enum CodingKeys: String, CodingKey {
        case pairingID
        case secretKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairingID = try container.decode(UUID.self, forKey: .pairingID)
        let keyData = try container.decode(Data.self, forKey: .secretKey)
        secretKey = SymmetricKey(data: keyData)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pairingID, forKey: .pairingID)
        try container.encode(secretKey.withUnsafeBytes { Data($0) }, forKey: .secretKey)
    }
}

// MARK: - QR payload

/// What actually goes into the QR code. Kept separate from `PairingIdentity`
/// so the wire format (versioned, base64) can evolve independently of the
/// in-memory/Keychain representation.
public struct PairingQRPayload: Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let identity: PairingIdentity

    public init(identity: PairingIdentity) {
        self.version = Self.currentVersion
        self.identity = identity
    }

    /// Encodes as `p2pexample:v1:<base64url(pairingID || secretKey)>`.
    public func encodedString() -> String {
        var data = Data()
        withUnsafeBytes(of: identity.pairingID.uuid) { data.append(contentsOf: $0) }
        identity.secretKey.withUnsafeBytes { data.append(contentsOf: $0) }
        let base64url = Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "p2pexample:v\(version):\(base64url)"
    }

    public init?(encodedString: String) {
        let parts = encodedString.split(separator: ":", maxSplits: 2)
        guard parts.count == 3,
              parts[0] == "p2pexample",
              parts[1] == "v\(Self.currentVersion)"
        else { return nil }

        var base64 = String(parts[2])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64), data.count == 16 + 32 else { return nil }

        let idBytes = data.prefix(16)
        let keyBytes = data.suffix(32)
        let uuid = idBytes.withUnsafeBytes { raw -> uuid_t in
            raw.load(as: uuid_t.self)
        }

        self.version = Self.currentVersion
        self.identity = PairingIdentity(
            pairingID: UUID(uuid: uuid),
            secretKey: SymmetricKey(data: keyBytes)
        )
    }
}
