# Protocol

The contract between `shared/` (Swift), `mac-app/`, `ios-app/`, and `lambda/`.
Update this file first when the wire format changes — the code should follow it,
not the other way around.

## 1. Pairing

1. The PC generates a `PairingIdentity` (random `pairingID: UUID`, random 256-bit
   `secretKey`) and shows it as a QR code: `p2pexample:v1:<base64url(pairingID || secretKey)>`
   (see `PairingQRPayload` in `shared/`).
2. The phone scans it, decodes the same struct, and stores it in the Keychain.
3. The PC also stores its own copy in the Keychain and starts advertising.

No OS-level Bluetooth pairing/bonding ever happens — the app-level `secretKey` is
what secures the channel, so there's no system pairing dialog to walk the user
through.

## 2. BLE advertising & connection

- Service UUID: `6E9A0001-6A3F-4E8C-9C3B-3F2C6E9A0001` (`BLEConstants.serviceUUID`).
- The PC advertises this service UUID (`CBPeripheralManager.startAdvertising`
  only supports local name + service UUIDs — no manufacturer data, unlike a
  standalone BLE peripheral chip — so the pairing ID can't ride in the
  advertisement itself).
- The phone scans for the service UUID and connects to any match — then,
  before subscribing to anything, reads the PairingID characteristic and
  disconnects immediately if it doesn't match the `pairingID` in its
  Keychain. This is how a phone that's scanned multiple PCs' QR codes over
  time tells them apart.

### Characteristics

| Characteristic | UUID (suffix) | Direction | Write type |
|---|---|---|---|
| PairingID | `...0005` | PC → phone | read (plaintext) |
| Message | `...0002` | PC → phone | indicate |
| Ack | `...0003` | phone → PC | write without response |
| Push ticket | `...0004` | phone → PC | write |

## 3. Message envelope

Every value written to the Message and Push ticket characteristics is a
`SecureEnvelope.Sealed` (AES-256-GCM: 12-byte nonce, ciphertext, 16-byte tag),
JSON- or binary-encoded, sealed with the pairing `secretKey`. Plaintext bodies:

- Message characteristic: JSON-encoded `OutboundMessage`.
- Ack characteristic (plaintext is fine here since it never leaves the link,
  but kept sealed for consistency): JSON-encoded `MessageAck`.

## 4. Push fallback

1. On first launch (and whenever its push token rotates), the phone registers
   with the Lambda: `POST /register { platform, pushToken }` → `{ ticket, expiresAt }`.
   `ticket` is opaque — only the Lambda can map it back to a push token.
2. The phone writes the ticket to the PC over the Push ticket characteristic
   (sealed with the pairing key) the next time they're connected over BLE.
3. If the PC sends a message and doesn't get an ack within a timeout (default:
   a few seconds), it calls `POST /notify { ticket, encryptedPayload }`, where
   `encryptedPayload` is the same `SecureEnvelope.Sealed` it would have sent
   over BLE. The Lambda forwards to APNs/FCM as a data-only or visible push;
   it never sees plaintext.
4. The phone decrypts the payload locally with the pairing key when the push
   arrives.

## 5. Reconnect backstop

Whenever the iOS app enters the foreground, it re-checks the BLE connection
state and re-scans if needed, so the failure mode is "open the app," not a
silent drop.

## Open questions / TODO

- Ticket refresh policy (rotate before `expiresAt`, not after).
- Rate limiting on `/notify` (per-ticket and/or per-source-IP).
- Android equivalent of the iOS background-connect story (foreground service,
  optionally Companion Device Manager) — not yet scaffolded in this repo.
