import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Same rendering as `JPEGWriter`, but lossless — no compression artifacts, which reads crisper
/// for text than JPEG.
enum PNGWriter {
    @discardableResult
    static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
