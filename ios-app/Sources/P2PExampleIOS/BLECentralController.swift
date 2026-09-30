import Foundation
import CoreBluetooth
import PairingKit

/// Scans for and connects to the Mac's advertised GATT service. Before
/// subscribing to anything, reads the PairingID characteristic and verifies
/// it matches `identity.pairingID` — disconnecting and continuing to scan if
/// it doesn't, so a phone that's paired with more than one PC over time only
/// ever talks to the right one. Acks anything it decrypts successfully.
@MainActor
final class BLECentralController: NSObject, ObservableObject {
    enum Status: Equatable {
        case bluetoothOff
        case bluetoothUnauthorized
        case scanning
        case connecting
        case connected
    }

    struct ReceivedMessage: Identifiable, Equatable {
        let id: UUID
        let title: String
        let body: String
        let receivedAt: Date
    }

    @Published private(set) var status: Status = .bluetoothOff
    @Published private(set) var eventLog: [String] = []
    @Published private(set) var receivedMessages: [ReceivedMessage] = []

    let identity: PairingIdentity

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var pairingIDCharacteristic: CBCharacteristic?
    private var messageCharacteristic: CBCharacteristic?
    private var ackCharacteristic: CBCharacteristic?

    init(identity: PairingIdentity) {
        self.identity = identity
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Called on launch and whenever the app returns to the foreground — the
    /// M3 "backstop": the rare failure should cost one tap (foregrounding),
    /// not a manual re-pair.
    func refreshConnectionIfNeeded() {
        if let connectedPeripheral, connectedPeripheral.state == .connected {
            return
        }
        resetConnectionState()
        startScanningIfNeeded()
    }

    private func resetConnectionState() {
        connectedPeripheral = nil
        pairingIDCharacteristic = nil
        messageCharacteristic = nil
        ackCharacteristic = nil
    }

    private func startScanningIfNeeded() {
        guard central.state == .poweredOn, connectedPeripheral == nil else { return }
        status = .scanning
        log("Scanning for \(BLEConstants.serviceUUIDString)…")
        central.scanForPeripherals(withServices: [BLEConstants.serviceUUID])
    }

    private func log(_ message: String) {
        eventLog.append(message)
        if eventLog.count > 50 {
            eventLog.removeFirst(eventLog.count - 50)
        }
        print("[BLECentralController] \(message)")
        fflush(stdout)
    }
}

extension BLECentralController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanningIfNeeded()
        case .unauthorized:
            status = .bluetoothUnauthorized
            log("Bluetooth permission denied")
        default:
            status = .bluetoothOff
            log("Bluetooth is off or unavailable (\(central.state.rawValue))")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        log("Discovered \(peripheral.name ?? peripheral.identifier.uuidString), connecting…")
        central.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        status = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Connected, discovering services…")
        peripheral.discoverServices([BLEConstants.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        log("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        resetConnectionState()
        startScanningIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        log("Disconnected: \(error?.localizedDescription ?? "no error given")")
        resetConnectionState()
        startScanningIfNeeded()
    }
}

extension BLECentralController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            log("Service discovery failed: \(error)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else {
            log("Advertised service not found after connect")
            return
        }
        peripheral.discoverCharacteristics(
            [
                BLEConstants.pairingIDCharacteristicUUID,
                BLEConstants.messageCharacteristicUUID,
                BLEConstants.ackCharacteristicUUID,
                BLEConstants.pushTicketCharacteristicUUID,
            ],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            log("Characteristic discovery failed: \(error)")
            return
        }
        let characteristics = service.characteristics ?? []
        pairingIDCharacteristic = characteristics.first { $0.uuid == BLEConstants.pairingIDCharacteristicUUID }
        messageCharacteristic = characteristics.first { $0.uuid == BLEConstants.messageCharacteristicUUID }
        ackCharacteristic = characteristics.first { $0.uuid == BLEConstants.ackCharacteristicUUID }

        guard let pairingIDCharacteristic else {
            log("PairingID characteristic missing")
            return
        }
        log("Reading PairingID to verify this is our paired PC…")
        peripheral.readValue(for: pairingIDCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            log("Subscribe failed: \(error)")
            return
        }
        status = .connected
        log("Subscribed — connected")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            log("Value update error: \(error)")
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BLEConstants.pairingIDCharacteristicUUID:
            handlePairingIDValue(data, peripheral: peripheral)
        case BLEConstants.messageCharacteristicUUID:
            handleMessageValue(data, peripheral: peripheral)
        default:
            break
        }
    }

    private func handlePairingIDValue(_ data: Data, peripheral: CBPeripheral) {
        let remotePairingID = data.withUnsafeBytes { $0.load(as: uuid_t.self) }
        guard UUID(uuid: remotePairingID) == identity.pairingID else {
            log("PairingID mismatch — this isn't our paired PC, disconnecting")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard let messageCharacteristic else {
            log("PairingID verified, but Message characteristic missing")
            return
        }
        log("PairingID verified, subscribing to Message…")
        peripheral.setNotifyValue(true, for: messageCharacteristic)
    }

    private func handleMessageValue(_ data: Data, peripheral: CBPeripheral) {
        do {
            let sealed = try JSONDecoder().decode(SecureEnvelope.Sealed.self, from: data)
            let plaintext = try SecureEnvelope.open(sealed, using: identity.secretKey)
            let message = try JSONDecoder().decode(OutboundMessage.self, from: plaintext)
            receivedMessages.append(ReceivedMessage(id: message.id, title: message.title, body: message.body, receivedAt: Date()))
            log("Received \"\(message.title)\": \(message.body)")

            guard let ackCharacteristic else {
                log("Cannot ack: ack characteristic missing")
                return
            }
            let ack = MessageAck(messageID: message.id)
            let ackSealed = try SecureEnvelope.seal(try JSONEncoder().encode(ack), using: identity.secretKey)
            peripheral.writeValue(try JSONEncoder().encode(ackSealed), for: ackCharacteristic, type: .withoutResponse)
            log("Ack sent for \(message.id.uuidString.prefix(8))")
        } catch {
            log("Failed to decrypt/decode message: \(error)")
        }
    }
}
