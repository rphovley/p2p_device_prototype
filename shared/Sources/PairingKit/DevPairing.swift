import Foundation
import CryptoKit

/// A single fixed `PairingIdentity` baked into every target for M1-M3, so the
/// Mac app, iOS app, and `ble-smoke-test` tool can talk to each other before
/// QR pairing (M4) exists. Never used for anything beyond local dev/testing.
///
/// Delete this file once M4 lands — every call site should move to a
/// `PairingKeychainStore`-loaded identity instead.
public enum DevPairing {
    public static let identity = PairingIdentity(
        pairingID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        secretKey: SymmetricKey(data: Data(repeating: 0x42, count: 32))
    )
}
