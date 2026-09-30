import Foundation

/// A single PC -> phone notification. `id` is used for ack matching and for
/// de-duplicating a message that arrives both over BLE and (late) over push.
public struct OutboundMessage: Codable, Equatable, Sendable {
    public let id: UUID
    public let sentAt: Date
    public let title: String
    public let body: String

    public init(id: UUID = UUID(), sentAt: Date = Date(), title: String, body: String) {
        self.id = id
        self.sentAt = sentAt
        self.title = title
        self.body = body
    }
}

/// Written back to `BLEConstants.ackCharacteristicUUID` by the phone.
public struct MessageAck: Codable, Equatable, Sendable {
    public let messageID: UUID

    public init(messageID: UUID) {
        self.messageID = messageID
    }
}

/// Sealed by the Lambda, opaque to the PC. The PC hands this back to the
/// Lambda verbatim when it wants to push to this one phone.
public struct PushTicket: Codable, Equatable, Sendable {
    public let opaqueToken: String
    public let expiresAt: Date

    public init(opaqueToken: String, expiresAt: Date) {
        self.opaqueToken = opaqueToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { Date() >= expiresAt }
}
