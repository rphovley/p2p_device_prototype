import SwiftUI
import PairingKit

@main
struct P2PExampleMacApp: App {
    @StateObject private var pairing = PairingCoordinator()

    var body: some Scene {
        MenuBarExtra("P2P Example", systemImage: "dot.radiowaves.left.and.right") {
            RootView(pairing: pairing)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @ObservedObject var pairing: PairingCoordinator
    @State private var qrPayload: PairingQRPayload?

    var body: some View {
        if let qrPayload {
            PairingView(payload: qrPayload) {
                self.qrPayload = nil
            }
        } else if let bleController = pairing.bleController {
            ContentView(bleController: bleController, onForgetPairing: pairing.forgetPairing)
        } else {
            NotPairedView {
                qrPayload = pairing.startPairing()
            }
        }
    }
}

struct NotPairedView: View {
    let onPair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P2P Example")
                .font(.headline)
            Text("Not paired")
                .foregroundStyle(.secondary)
            Divider()
            Button("Pair with phone…", action: onPair)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 220)
    }
}

struct ContentView: View {
    @ObservedObject var bleController: BLEPeripheralController
    let onForgetPairing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P2P Example")
                .font(.headline)
            Text(statusText)
                .foregroundStyle(.secondary)
            Divider()
            Button("Send test message") {
                bleController.sendTestMessage()
            }
            .disabled(bleController.status == .bluetoothOff || bleController.status == .bluetoothUnauthorized)
            if let lastSent = bleController.lastSentMessageID {
                Text(lastSent == bleController.lastAckedMessageID ? "Delivered" : "Sent, awaiting ack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(bleController.eventLog.suffix(10).enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            Divider()
            Button("Forget pairing…", action: onForgetPairing)
                .foregroundStyle(.red)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var statusText: String {
        switch bleController.status {
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothUnauthorized: "Bluetooth permission denied"
        case .advertising: "Advertising, waiting for phone"
        case .phoneConnected: "Phone connected"
        }
    }
}
