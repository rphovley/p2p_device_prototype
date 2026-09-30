import Foundation
import CoreBluetooth
import PairingKit

/// Hosts the GATT service from `BLEConstants` and advertises it continuously,
/// using whichever `PairingIdentity` it's given at init (either a real
/// QR-paired identity loaded from the Keychain, or `DevPairing.identity` for
/// quick local testing).
@MainActor
final class BLEPeripheralController: NSObject, ObservableObject {
    enum Status: Equatable {
        case bluetoothOff
        case bluetoothUnauthorized
        case advertising
        case phoneConnected
    }

    @Published private(set) var status: Status = .bluetoothOff
    @Published private(set) var eventLog: [String] = []
    @Published private(set) var lastSentMessageID: UUID?
    @Published private(set) var lastAckedMessageID: UUID?

    let identity: PairingIdentity

    private var peripheralManager: CBPeripheralManager!
    private var pairingIDCharacteristic: CBMutableCharacteristic!
    private var messageCharacteristic: CBMutableCharacteristic!
    private var ackCharacteristic: CBMutableCharacteristic!
    private var pushTicketCharacteristic: CBMutableCharacteristic!

    private var pendingMessageData: Data?

    init(identity: PairingIdentity) {
        self.identity = identity
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func sendTestMessage() {
        guard peripheralManager.state == .poweredOn else {
            log("Cannot send: Bluetooth is not powered on")
            return
        }

        let message = OutboundMessage(title: "Test", body: "Hello from Mac at \(Date().formatted(date: .omitted, time: .standard))")
        do {
            let sealed = try SecureEnvelope.seal(try JSONEncoder().encode(message), using: identity.secretKey)
            let data = try JSONEncoder().encode(sealed)
            lastSentMessageID = message.id
            log("Sending message \(message.id.uuidString.prefix(8))…")

            if !peripheralManager.updateValue(data, for: messageCharacteristic, onSubscribedCentrals: nil) {
                log("Transmit queue full, will retry when ready")
                pendingMessageData = data
            }
        } catch {
            log("Failed to seal message: \(error)")
        }
    }

    private func setupServiceIfNeeded() {
        guard messageCharacteristic == nil else { return }

        let pairingIDData = withUnsafeBytes(of: identity.pairingID.uuid) { Data($0) }
        pairingIDCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.pairingIDCharacteristicUUID,
            properties: [.read],
            value: pairingIDData,
            permissions: [.readable]
        )
        messageCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.messageCharacteristicUUID,
            properties: [.indicate],
            value: nil,
            permissions: []
        )
        ackCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.ackCharacteristicUUID,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        pushTicketCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.pushTicketCharacteristicUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )

        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [pairingIDCharacteristic, messageCharacteristic, ackCharacteristic, pushTicketCharacteristic]
        peripheralManager.add(service)
    }

    private func startAdvertising() {
        let shortID = identity.pairingID.uuidString.prefix(8)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "\(BLEConstants.advertisedNamePrefix)\(shortID)",
        ])
        status = .advertising
        log("Advertising as \(BLEConstants.advertisedNamePrefix)\(shortID)")
    }

    private func handleWrite(to characteristicUUID: CBUUID, value: Data) {
        switch characteristicUUID {
        case BLEConstants.ackCharacteristicUUID:
            handleAckWrite(value)
        case BLEConstants.pushTicketCharacteristicUUID:
            log("Received push ticket write (\(value.count) bytes) — handling arrives in M5")
        default:
            log("Received write to unexpected characteristic \(characteristicUUID)")
        }
    }

    private func handleAckWrite(_ value: Data) {
        do {
            let sealed = try JSONDecoder().decode(SecureEnvelope.Sealed.self, from: value)
            let plaintext = try SecureEnvelope.open(sealed, using: identity.secretKey)
            let ack = try JSONDecoder().decode(MessageAck.self, from: plaintext)
            lastAckedMessageID = ack.messageID
            log("Ack received for message \(ack.messageID.uuidString.prefix(8))")
        } catch {
            log("Failed to decode ack: \(error)")
        }
    }

    private func log(_ message: String) {
        eventLog.append(message)
        if eventLog.count > 50 {
            eventLog.removeFirst(eventLog.count - 50)
        }
        print("[BLEPeripheralController] \(message)")
        fflush(stdout)
    }
}

// CBPeripheralManager was created with `queue: nil`, so these delegate callbacks always
// land on the main queue already. `@preconcurrency` conformance lets them stay plain
// @MainActor methods instead of forcing every CoreBluetooth parameter to be Sendable.
extension BLEPeripheralController: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            setupServiceIfNeeded()
            startAdvertising()
        case .unauthorized:
            status = .bluetoothUnauthorized
            log("Bluetooth permission denied")
        default:
            status = .bluetoothOff
            log("Bluetooth is off or unavailable (\(peripheral.state.rawValue))")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if let error {
            log("Failed to add service: \(error)")
        } else {
            log("Service \(service.uuid) added successfully")
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error {
            log("Failed to start advertising: \(error)")
        } else {
            log("Advertising confirmed started by CoreBluetooth")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        status = .phoneConnected
        log("Central subscribed to \(characteristic.uuid)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        status = .advertising
        log("Central unsubscribed from \(characteristic.uuid)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLEConstants.pairingIDCharacteristicUUID else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }
        guard request.offset == 0 else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = pairingIDCharacteristic.value
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let value = request.value else { continue }
            handleWrite(to: request.characteristic.uuid, value: value)
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let data = pendingMessageData else { return }
        if peripheral.updateValue(data, for: messageCharacteristic, onSubscribedCentrals: nil) {
            pendingMessageData = nil
            log("Retried queued message send")
        }
    }
}
