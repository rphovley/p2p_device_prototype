import SwiftUI
import PairingKit

struct PairingView: View {
    let payload: PairingQRPayload
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Scan with your phone")
                .font(.headline)

            if let cgImage = QRCodeGenerator.image(for: payload.encodedString()) {
                Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: 220, height: 220)))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
            } else {
                Text("Failed to generate QR code")
                    .foregroundStyle(.secondary)
                    .frame(width: 220, height: 220)
            }

            Text("Open P2P Example on your phone and scan this code. Advertising has already started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 220)

            Button("Done", action: onDone)
        }
        .padding()
        .frame(width: 280)
    }
}
