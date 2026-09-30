import Testing
import Foundation
import CryptoKit
@testable import PairingKit

@Test func qrRoundTrip() throws {
    let identity = PairingIdentity()
    let payload = PairingQRPayload(identity: identity)
    let encoded = payload.encodedString()

    let decoded = try #require(PairingQRPayload(encodedString: encoded))
    #expect(decoded.identity.pairingID == identity.pairingID)
    #expect(decoded.identity.secretKey.withUnsafeBytes { Data($0) }
        == identity.secretKey.withUnsafeBytes { Data($0) })
}

@Test func envelopeRoundTrip() throws {
    let key = SymmetricKey(size: .bits256)
    let plaintext = Data("hello phone".utf8)

    let sealed = try SecureEnvelope.seal(plaintext, using: key)
    let opened = try SecureEnvelope.open(sealed, using: key)

    #expect(opened == plaintext)
}

@Test func envelopeFailsWithWrongKey() throws {
    let plaintext = Data("hello phone".utf8)
    let sealed = try SecureEnvelope.seal(plaintext, using: SymmetricKey(size: .bits256))

    #expect(throws: (any Error).self) {
        _ = try SecureEnvelope.open(sealed, using: SymmetricKey(size: .bits256))
    }
}

@Test func keychainStoreRoundTrip() throws {
    let store = PairingKeychainStore(service: "com.example.p2pexample.pairing.tests")
    let identity = PairingIdentity()

    try store.save(identity)
    let loaded = try #require(try store.load())
    #expect(loaded == identity)

    try store.clear()
    #expect(try store.load() == nil)
}
