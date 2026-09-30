import SwiftUI
import VisionKit
import PairingKit

struct PairingScannerView: View {
    let onScanned: (PairingQRPayload) -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerRepresentable(onScanned: onScanned, onError: { errorMessage = $0 })
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Camera scanning isn't available on this device.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding()
            }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (PairingQRPayload) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency DataScannerViewControllerDelegate {
        let onScanned: (PairingQRPayload) -> Void
        let onError: (String) -> Void
        private var handled = false

        init(onScanned: @escaping (PairingQRPayload) -> Void, onError: @escaping (String) -> Void) {
            self.onScanned = onScanned
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payloadString = barcode.payloadStringValue else { continue }
                guard let payload = PairingQRPayload(encodedString: payloadString) else {
                    onError("Scanned code isn't a valid pairing code")
                    continue
                }
                handled = true
                onScanned(payload)
                break
            }
        }
    }
}
