import Foundation
import Security

/// Stores the paired identity in the Keychain so pairing survives app
/// restarts, OS updates, and days of inactivity. Same code path on macOS
/// and iOS — only the accessibility/access-group semantics differ, and the
/// defaults here are the local-only, device-only ones we want for a secret
/// that should never leave the device.
public final class PairingKeychainStore: @unchecked Sendable {
    private let service: String
    private let account = "pairing-identity"

    public init(service: String = "com.example.p2pexample.pairing") {
        self.service = service
    }

    public func save(_ identity: PairingIdentity) throws {
        let data = try JSONEncoder().encode(identity)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public func load() throws -> PairingIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(PairingIdentity.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    public enum KeychainError: Error {
        case unhandled(OSStatus)
    }
}
