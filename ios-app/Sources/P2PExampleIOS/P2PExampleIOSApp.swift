import SwiftUI
import PairingKit

@main
struct P2PExampleIOSApp: App {
    @StateObject private var pairing = PairingCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(pairing: pairing)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                pairing.bleController?.refreshConnectionIfNeeded()
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var pairing: PairingCoordinator

    var body: some View {
        if let bleController = pairing.bleController {
            ContentView(bleController: bleController, onForgetPairing: pairing.forgetPairing)
        } else {
            PairingScannerView { payload in
                pairing.completePairing(with: payload)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var bleController: BLECentralController
    let onForgetPairing: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: statusSymbolName)
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.headline)
                }

                Divider()

                Text("Messages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if bleController.receivedMessages.isEmpty {
                    Text("Nothing yet — send a test message from the Mac app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    List(bleController.receivedMessages.reversed()) { message in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.title).font(.body.bold())
                            Text(message.body).font(.body)
                            Text(message.receivedAt.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }

                Spacer()

                Button("Forget pairing…", role: .destructive, action: onForgetPairing)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .navigationTitle("P2P Example")
        }
    }

    private var statusText: String {
        switch bleController.status {
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothUnauthorized: "Bluetooth permission denied"
        case .scanning: "Scanning for Mac…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        }
    }

    private var statusSymbolName: String {
        switch bleController.status {
        case .connected: "dot.radiowaves.left.and.right"
        case .scanning, .connecting: "wave.3.right"
        default: "wave.3.right.circle"
        }
    }

    private var statusColor: Color {
        bleController.status == .connected ? .green : .secondary
    }
}
