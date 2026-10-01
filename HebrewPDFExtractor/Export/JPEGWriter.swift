import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum JPEGWriter {
    @discardableResult
    static func write(_ image: CGImage, to url: URL, quality: CGFloat = 0.9) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
