import Foundation
import PairingKit

/// Owns the paired identity's lifecycle: load from Keychain on launch, or
/// persist a freshly scanned one. Creates the `BLECentralController` once an
/// identity exists either way.
@MainActor
final class PairingCoordinator: ObservableObject {
    @Published private(set) var identity: PairingIdentity?
    @Published private(set) var bleController: BLECentralController?

    private let store = PairingKeychainStore()

    init() {
        if let loaded = try? store.load() {
            activate(loaded)
        }
    }

    func completePairing(with payload: PairingQRPayload) {
        try? store.save(payload.identity)
        activate(payload.identity)
    }

    func forgetPairing() {
        try? store.clear()
        identity = nil
        bleController = nil
    }

    private func activate(_ identity: PairingIdentity) {
        self.identity = identity
        bleController = BLECentralController(identity: identity)
    }
}
