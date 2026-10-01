import Foundation

/// User-configurable options that apply to every PDF processed in a run.
struct ExtractionSettings {
    /// 0 means "no wrapping" (lines are exported exactly as reconstructed).
    var maxCharactersPerLine: Int = 0

    /// Sticky decision applied to every image-only page for the remainder of the current batch run.
    var runWideScannedPageAction: ScannedPageAction?

    /// When true, OCR restricts recognition to the Hebrew alphabet, niqqud, and punctuation —
    /// eliminating a class of confident misreads where Tesseract mistakes niqqud marks for Latin
    /// letters or digits. Only safe when the scanned/photographed source is Hebrew-only: any
    /// genuine English word or digit (page numbers, verse numbers, mixed-language captions) would
    /// also be forced into a Hebrew misreading. Off by default since most real documents mix in at
    /// least page numbers.
    var hebrewOnlyOCR: Bool = false
}

/// What to do with a page that has no extractable text layer (i.e. it's a scanned image).
enum ScannedPageAction: String, CaseIterable, Identifiable {
    case ocr
    case skip
    case flagOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ocr: return "Run OCR (Vision)"
        case .skip: return "Skip this page"
        case .flagOnly: return "Flag and continue"
        }
    }
}

/// How broadly a scanned-page decision should be remembered once the user makes it.
enum ScannedPageDecisionScope: String, CaseIterable, Identifiable {
    case thisPageOnly
    case restOfThisPDF
    case restOfRun

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisPageOnly: return "Just this page"
        case .restOfThisPDF: return "Rest of this PDF"
        case .restOfRun: return "Rest of this run"
        }
    }
}
