# p2p_example

Example project: a Mac menu bar app sends small messages to a paired iPhone
app, over BLE when in range, falling back to push notifications through a
small AWS Lambda relay when it isn't. See [`docs/PROTOCOL.md`](docs/PROTOCOL.md)
for the full design and wire format.

## Layout

- `shared/` — `PairingKit`, a Swift Package with the pairing/crypto/BLE-UUID
  code both native apps import, so the wire format can't drift between them.
- `mac-app/` — SwiftUI menu bar app (macOS 14+). Xcode project is generated,
  not committed — see below.
- `ios-app/` — SwiftUI app (iOS 17+). Same story.
- `lambda/` — TypeScript + AWS CDK push relay (`register` / `notify`
  functions behind Lambda Function URLs).
- `tools/ble-smoke-test/` — CLI that plays the BLE central role, used to
  validate `mac-app`'s peripheral before the iOS app exists.
- `docs/` — protocol spec, PRD, and design notes.

## Getting set up

```sh
brew install xcodegen   # generates the .xcodeproj files from project.yml

cd mac-app && xcodegen generate && open P2PExampleMac.xcodeproj
cd ios-app && xcodegen generate && open P2PExampleIOS.xcodeproj
```

The `.xcodeproj` files are gitignored on purpose — `project.yml` is the
source of truth for build settings, targets, and entitlements. Re-run
`xcodegen generate` after pulling changes to either `project.yml`.

### Shared package

```sh
cd shared && swift test
```

### Lambda

```sh
cd lambda && npm install && npm run synth   # `npm run deploy` requires AWS credentials
```

### Validating the Mac app's BLE peripheral

```sh
cd mac-app && xcodegen generate
xcodebuild -project P2PExampleMac.xcodeproj -scheme P2PExampleMac -destination 'platform=macOS' build
open <path-to-built .app>          # look for the menu bar icon

cd tools/ble-smoke-test && swift run ble-smoke-test 45
```

**Run `ble-smoke-test` from a second BLE-capable device, not the same Mac.**
A single Mac generally can't discover its own `CBPeripheralManager`
advertisement via a `CBCentralManager` scan on the same machine/radio — the
Mac app's own log will confirm the service published and advertising
started with no errors, but a same-machine scan will just time out. See
`docs/PRD.md` M1 for details. Once `ios-app` exists (M2) it becomes the real
second device for this test.

### Validating the full pairing + BLE round trip (Mac + iPhone)

The iOS BLE central role — and the QR scanner — only work on a physical
device: CoreBluetooth central scanning of real hardware and
`VisionKit.DataScannerViewController` are both unavailable in the iOS
Simulator. **Confirmed working end-to-end on a real Mac + iPhone — see
`docs/PRD.md` M2-M4 for the log evidence.**

**One-time device setup**, if Xcode hasn't talked to this iPhone before:
1. Connect via USB, tap **Trust** on the phone when prompted.
2. **Settings → Privacy & Security → Developer Mode** on the phone → on →
   restart → confirm again after reboot.
3. In Xcode: **Settings → Accounts** → sign in with an Apple ID (a personal/
   free team is enough — but see the note below).
4. Select the `P2PExampleIOS` target → **Signing & Capabilities** →
   automatic signing → pick your team.

**Note on personal/free teams:** the Push Notifications entitlement
(`aps-environment`) isn't available to a free Apple Developer team and will
block automatic signing outright ("Personal development teams... do not
support the Push Notifications capability"). `ios-app/project.yml` doesn't
declare it for exactly this reason — it'll need to come back (and a paid
membership) for M5.

**The test itself:**
1. Build and run `mac-app`. It should show "Not paired" with a "Pair with
   phone…" button.
2. Run `ios-app` on the phone (⌘R in Xcode, or see below for CLI). It should
   show the QR scanner.
3. On the Mac, click "Pair with phone…" — a QR code appears (advertising
   starts immediately, before the phone scans).
4. Scan it with the phone. It should then show "Connected" within a few
   seconds; the Mac's popover should show "Phone connected" too.
5. Click "Send test message" in the Mac menu bar — it should appear on the
   phone, and the Mac should then show "Delivered".
6. Force-quit and relaunch the iOS app; it should reconnect without
   re-pairing (both sides now have a real Keychain-stored identity from the
   QR scan — see `docs/PRD.md` M4).
7. "Forget pairing…" on either app clears its Keychain entry and returns to
   the pairing UI, for re-testing without reinstalling.

**Watching the iOS app's logs from the Mac, without Xcode's console:** both
`BLEPeripheralController` and `BLECentralController` `print()` (with
`fflush(stdout)`) every state transition. Once the app's installed once via
Xcode, you can relaunch it from Terminal with its console streamed live:

```sh
xcrun devicectl list devices                        # find the device UDID
xcrun devicectl device process launch \
  --device <udid> --console --terminate-existing \
  com.example.p2pexample.ios
```

If `devicectl` reports the device as `unavailable`/unpaired first, that's
usually the CoreDevice pairing handshake, separate from the USB trust
prompt — `xcrun devicectl manage pair --device <udid>` resolves it (after
the USB "Trust This Computer" prompt has already been accepted).

## Status

See [`docs/PRD.md`](docs/PRD.md) for the milestone plan and current status.
**M0-M4 are done and device-verified** (scaffolding, Mac BLE peripheral, iOS
BLE central, message/ack round trip, QR pairing) — confirmed 2026-09-30 on a
real Mac + iPhone. M5 (push fallback) is next, blocked on a paid Apple
Developer Program membership (see the note above); the Lambda's actual
DynamoDB + APNs/FCM calls are still TODOs (see the `TODO`s in
`lambda/src/`).
