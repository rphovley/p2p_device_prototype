import Foundation
import PairingKit

/// Owns the paired identity's lifecycle: load from Keychain on launch, or
/// generate+persist a new one when the user starts pairing. Creates the
/// `BLEPeripheralController` once an identity exists either way.
@MainActor
final class PairingCoordinator: ObservableObject {
    @Published private(set) var identity: PairingIdentity?
    @Published private(set) var bleController: BLEPeripheralController?

    private let store = PairingKeychainStore()

    init() {
        if let loaded = try? store.load() {
            activate(loaded)
        }
    }

    /// Generates a fresh identity, persists it, and starts advertising
    /// immediately — so a phone that's mid-scan can already connect, rather
    /// than waiting for some separate "finish pairing" step.
    func startPairing() -> PairingQRPayload {
        let identity = PairingIdentity()
        try? store.save(identity)
        activate(identity)
        return PairingQRPayload(identity: identity)
    }

    func forgetPairing() {
        try? store.clear()
        identity = nil
        bleController = nil
    }

    private func activate(_ identity: PairingIdentity) {
        self.identity = identity
        bleController = BLEPeripheralController(identity: identity)
    }
}
