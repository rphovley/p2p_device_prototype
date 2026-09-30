import Foundation
import CoreBluetooth
import PairingKit

/// Plays the BLE central role that `ios-app` will eventually play, so `mac-app`'s
/// peripheral implementation can be validated end-to-end without a phone.
///
/// Run this while P2PExampleMac.app is running and advertising, then click
/// "Send test message" in the Mac app's menu. Exits 0 on a full verified round
/// trip (discover -> connect -> subscribe -> decrypt message -> send ack),
/// exits 1 with a stage-labeled failure otherwise.
@MainActor
final class SmokeTestRunner: NSObject {
    private var central: CBCentralManager!
    private var messageChar: CBCharacteristic?
    private var ackChar: CBCharacteristic?
    private var timeoutTimer: Timer?

    func start(timeoutSeconds: TimeInterval) {
        print("[ble-smoke-test] Looking for service \(BLEConstants.serviceUUIDString)…")
        print("[ble-smoke-test] Make sure P2PExampleMac.app is running (menu bar icon visible).")
        central = CBCentralManager(delegate: self, queue: nil)
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.fail("timed out after \(Int(timeoutSeconds))s")
            }
        }
    }

    private func advance(_ message: String) {
        print("[ble-smoke-test] \(message)")
        fflush(stdout)
    }

    private func fail(_ message: String) -> Never {
        print("[ble-smoke-test] FAIL: \(message)")
        fflush(stdout)
        exit(1)
    }

    private func succeed() -> Never {
        print("[ble-smoke-test] PASS: discovered, connected, subscribed, decrypted a message, and acked it")
        fflush(stdout)
        exit(0)
    }
}

extension SmokeTestRunner: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            advance("Bluetooth powered on, scanning…")
            central.scanForPeripherals(withServices: [BLEConstants.serviceUUID])
        case .unauthorized:
            fail("Bluetooth permission denied — grant it to your terminal app in System Settings > Privacy & Security > Bluetooth")
        default:
            fail("Bluetooth unavailable (state: \(central.state.rawValue))")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        advance("Discovered \(peripheral.name ?? peripheral.identifier.uuidString), connecting…")
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        advance("Connected, discovering services…")
        peripheral.discoverServices([BLEConstants.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        fail("failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        fail("disconnected unexpectedly: \(error?.localizedDescription ?? "no error given")")
    }
}

extension SmokeTestRunner: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error { fail("service discovery failed: \(error)") }
        guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else {
            fail("advertised service not found after connect")
        }
        advance("Service found, discovering characteristics…")
        peripheral.discoverCharacteristics(
            [BLEConstants.messageCharacteristicUUID, BLEConstants.ackCharacteristicUUID, BLEConstants.pushTicketCharacteristicUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error { fail("characteristic discovery failed: \(error)") }
        let characteristics = service.characteristics ?? []

        messageChar = characteristics.first { $0.uuid == BLEConstants.messageCharacteristicUUID }
        ackChar = characteristics.first { $0.uuid == BLEConstants.ackCharacteristicUUID }
        let ticketChar = characteristics.first { $0.uuid == BLEConstants.pushTicketCharacteristicUUID }

        guard let messageChar, ackChar != nil, ticketChar != nil else {
            fail("missing expected characteristics (found \(characteristics.map(\.uuid)))")
        }

        advance("All three characteristics present. Subscribing to Message…")
        peripheral.setNotifyValue(true, for: messageChar)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error { fail("subscribe failed: \(error)") }
        advance("Subscribed. Now click \"Send test message\" in the Mac app…")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == BLEConstants.messageCharacteristicUUID else { return }
        if let error { fail("value update error: \(error)") }
        guard let data = characteristic.value else { fail("empty message value") }

        do {
            let sealed = try JSONDecoder().decode(SecureEnvelope.Sealed.self, from: data)
            let plaintext = try SecureEnvelope.open(sealed, using: DevPairing.identity.secretKey)
            let message = try JSONDecoder().decode(OutboundMessage.self, from: plaintext)
            advance("Decrypted message \(message.id.uuidString.prefix(8)): \"\(message.title)\" / \"\(message.body)\"")

            guard let ackChar else { fail("ack characteristic missing") }
            let ack = MessageAck(messageID: message.id)
            let ackSealed = try SecureEnvelope.seal(try JSONEncoder().encode(ack), using: DevPairing.identity.secretKey)
            peripheral.writeValue(try JSONEncoder().encode(ackSealed), for: ackChar, type: .withoutResponse)
            advance("Ack sent for \(message.id.uuidString.prefix(8))")
            succeed()
        } catch {
            fail("failed to decrypt/decode message: \(error)")
        }
    }
}

@main
@MainActor
struct SmokeTestMain {
    static func main() {
        let timeoutSeconds: TimeInterval = CommandLine.arguments.dropFirst().first.flatMap(TimeInterval.init) ?? 60
        let runner = SmokeTestRunner()
        runner.start(timeoutSeconds: timeoutSeconds)
        RunLoop.main.run()
    }
}
