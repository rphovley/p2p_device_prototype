import CoreBluetooth

/// GATT layout shared by the mac (peripheral/advertiser) and iOS (central) apps.
///
/// The service UUID is advertised in the clear so the phone can find the PC;
/// everything sent over these characteristics is app-level encrypted with the
/// pairing key (see `SecureEnvelope`), so no OS-level BLE pairing/bonding is needed.
public enum BLEConstants {
    /// Advertised primary service. The PC advertises this continuously while running.
    public static let serviceUUIDString = "6E9A0001-6A3F-4E8C-9C3B-3F2C6E9A0001"

    /// PC -> phone: encrypted message envelopes (indications).
    public static let messageCharacteristicUUIDString = "6E9A0002-6A3F-4E8C-9C3B-3F2C6E9A0001"

    /// Phone -> PC: per-message acknowledgements (write without response).
    public static let ackCharacteristicUUIDString = "6E9A0003-6A3F-4E8C-9C3B-3F2C6E9A0001"

    /// Phone -> PC: sealed push ticket handoff, sent once after registering for push (write).
    public static let pushTicketCharacteristicUUIDString = "6E9A0004-6A3F-4E8C-9C3B-3F2C6E9A0001"

    /// PC -> phone: the PC's `pairingID`, plaintext, read-only. `CBPeripheralManager`
    /// advertising only supports local name + service UUIDs (no manufacturer data), so
    /// this is how a phone that's scanned multiple PCs' QR codes tells them apart: read
    /// this right after connecting, before subscribing to Message, and disconnect if it
    /// doesn't match the locally stored `PairingIdentity.pairingID`.
    public static let pairingIDCharacteristicUUIDString = "6E9A0005-6A3F-4E8C-9C3B-3F2C6E9A0001"

    /// Advertisement local name prefix. Cosmetic only (helps a human eyeballing a BLE
    /// scanner) — `pairingIDCharacteristicUUID` is the actual match key.
    public static let advertisedNamePrefix = "P2PExample-"

    public static var serviceUUID: CBUUID { CBUUID(string: serviceUUIDString) }
    public static var messageCharacteristicUUID: CBUUID { CBUUID(string: messageCharacteristicUUIDString) }
    public static var ackCharacteristicUUID: CBUUID { CBUUID(string: ackCharacteristicUUIDString) }
    public static var pushTicketCharacteristicUUID: CBUUID { CBUUID(string: pushTicketCharacteristicUUIDString) }
    public static var pairingIDCharacteristicUUID: CBUUID { CBUUID(string: pairingIDCharacteristicUUIDString) }
}
