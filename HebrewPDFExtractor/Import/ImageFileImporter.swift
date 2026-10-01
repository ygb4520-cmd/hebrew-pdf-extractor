import CoreGraphics
import Foundation
import ImageIO

enum ImageImportError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Couldn't read this image file." }
}

/// Loads a standalone image file (a photo or scan, as opposed to a PDF page) as a `CGImage` for
/// OCR. A raster image has no text layer to check first — unlike a PDF page, there's no "does
/// this page already have extractable text" question — so `ExtractionCoordinator` always runs
/// OCR directly on whatever this loads, no scanned-page decision prompt involved.
enum ImageFileImporter {
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic"]

    static func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageImportError.unreadable
        }
        return image
    }
}
