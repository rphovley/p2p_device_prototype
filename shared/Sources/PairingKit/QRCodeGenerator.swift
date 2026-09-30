import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Renders a string as a QR code `CGImage` — platform-agnostic, so `mac-app`
/// wraps it in `NSImage` and `ios-app` wraps it in `UIImage`.
public enum QRCodeGenerator {
    public static func image(for string: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
