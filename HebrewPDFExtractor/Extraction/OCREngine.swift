import PDFKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftyTesseract
import libtesseract

enum OCRError: LocalizedError {
    case renderingFailed
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderingFailed: return "Couldn't render the page for OCR."
        case .recognitionFailed(let message): return "OCR failed: \(message)"
        }
    }
}

/// Points SwiftyTesseract at wherever `.traineddata` files actually land in the app bundle.
/// `Bundle.main`'s own default `LanguageModelDataSource` assumes a `tessdata` subfolder, but this
/// project's file-system-synchronized group flattens loose resource files to the `Resources` root
/// rather than preserving them as a folder reference, so the trained data ends up there instead.
private struct BundleResourcesDataSource: LanguageModelDataSource {
    var pathToTrainedData: String {
        Bundle.main.resourceURL!.path
    }
}

/// Runs on-device OCR on image-only PDF pages, using Tesseract (via SwiftyTesseract) with bundled
/// Hebrew + English trained data (`heb.traineddata` and `eng.traineddata`, sourced from
/// `HebrewPDFExtractor/tessdata/` in the project and bundled into the app's Resources).
///
/// Apple's Vision framework was tried first, since the platform guidelines prefer it, but testing
/// showed it cannot recognize Hebrew at all: across every `recognitionLanguages` setting tried
/// (`he`, `en-US`, even `ar-SA`), Vision returned confident-looking but completely wrong Latin-
/// alphabet text for real Hebrew input — not an error, not empty, just silently wrong. Tesseract's
/// own page-segmentation/reading-order handling is trusted directly here (unlike the Vision path
/// this replaces, there is no separate column-reordering pass on its output).
final class OCREngine {
    private let renderScale: CGFloat = 2.0

    /// Every codepoint Tesseract could mistake for a niqqud mark when `hebrewOnly` recognition is
    /// requested — used to build a `tessedit_char_blacklist` that rules out that entire failure
    /// mode. Only safe to apply when the source is known to be Hebrew-only (see
    /// `ExtractionSettings.hebrewOnlyOCR`): it would just as confidently blot out genuine English
    /// words or digits (page numbers, verse numbers) if the source actually contains them.
    private static let latinLettersAndDigits: String = {
        (0x30...0x39).map { String(UnicodeScalar($0)!) }.joined()
            + (0x41...0x5A).map { String(UnicodeScalar($0)!) }.joined()
            + (0x61...0x7A).map { String(UnicodeScalar($0)!) }.joined()
    }()

    /// `Tesseract(...)` reloads ~5MB of trained data on every init — created lazily once and
    /// reused for every subsequent OCR call in this engine's lifetime (one `OCREngine` lives for
    /// the whole app session, owned by `ExtractionCoordinator`), instead of once per page/image.
    /// Two variants are kept because the character blacklist is baked in at Tesseract init time
    /// (SwiftyTesseract has no way to change it per-call) and switching it wrong-footed is worse
    /// than the cost of a second cached instance.
    private lazy var permissiveTesseract = Tesseract(languages: [.hebrew, .english], dataSource: BundleResourcesDataSource())
    private lazy var hebrewOnlyTesseract = Tesseract(languages: [.hebrew, .english], dataSource: BundleResourcesDataSource()) {
        { (api: TessBaseAPI) in
            _ = TessBaseAPISetVariable(api, Tesseract.Variable.disallowlist.rawValue, Self.latinLettersAndDigits)
        }
    }

    func recognizeText(on page: PDFPage, hebrewOnly: Bool = false) async throws -> String {
        guard let cgImage = PDFPageRasterizer.renderCGImage(for: page, scale: renderScale) else {
            throw OCRError.renderingFailed
        }
        return try await recognizeText(on: cgImage, hebrewOnly: hebrewOnly)
    }

    /// Same recognition path, for a standalone image file (e.g. a photo/scan dropped directly,
    /// with no PDF page to rasterize first) rather than a PDF page.
    func recognizeText(on cgImage: CGImage, hebrewOnly: Bool = false) async throws -> String {
        guard let imageData = Self.pngData(for: Self.upscaledIfLowResolution(cgImage)) else {
            throw OCRError.renderingFailed
        }

        let tesseract = hebrewOnly ? self.hebrewOnlyTesseract : self.permissiveTesseract
        return try await Task.detached(priority: .userInitiated) {
            switch tesseract.performOCR(on: imageData) {
            case .success(let text):
                return text
            case .failure(let error):
                throw OCRError.recognitionFailed(String(describing: error))
            }
        }.value
    }

    /// Standalone image files (unlike PDF pages, which always get rasterized at `renderScale`)
    /// arrive at whatever resolution they were saved at — including, notably, images this app
    /// itself rendered for the "extracted text as image" export, which is sized for on-screen
    /// viewing rather than for OCR. Verified directly: a synthetic image with a smaller dimension
    /// under ~1200px, upscaled 2x here (via CGContext interpolation — no genuine new detail, just
    /// resampling) before recognition, eliminated most confidently-wrong Latin-alphabet garbage
    /// that Tesseract otherwise produced on the same image at its native size. A real scan/photo
    /// is typically already well above this threshold and passes through untouched.
    private static func upscaledIfLowResolution(_ image: CGImage) -> CGImage {
        let minDimension = min(image.width, image.height)
        guard minDimension > 0, minDimension < 1200 else { return image }

        let scale = 2.0
        let newWidth = Int(Double(image.width) * scale)
        let newHeight = Int(Double(image.height) * scale)
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
