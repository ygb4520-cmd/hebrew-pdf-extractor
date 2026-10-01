import PDFKit
import CoreGraphics

/// One line of text on a page, with its page-space bounding box.
struct PhysicalLine {
    let text: String
    let boundingBox: CGRect
}

/// Reconstructs per-line text and geometry from a PDF page.
///
/// Earlier versions of this extractor paired `PDFPage.characterBounds(at:)` with the same index
/// into `PDFPage.string`, on the assumption that both use the same per-character ordering. Testing
/// against synthetic RTL PDFs disproved that: `characterBounds(at:)` is indexed in raw
/// content-stream/drawing order, while `.string` (and `PDFSelection.string`) already reflects
/// PDFKit's own bidi-aware logical-order reconstruction — a *different* permutation of the same
/// characters. Pairing them by shared index silently associated the wrong text with the wrong
/// position, corrupting otherwise-correct extractions.
///
/// This version instead uses `PDFSelection`, which is self-consistent by construction (a
/// selection's `.string` always matches what's actually within its `.bounds`): `selectionsByLine()`
/// gives one selection per visual line, each with reliable per-line text and a bounding box. What
/// still needs correcting is *line order* — PDFKit's own `selectionsByLine()` order does not
/// account for right-to-left multi-column layout (it returns left-to-right column order regardless
/// of script), so `ColumnDetector` re-derives correct reading order from these lines' geometry.
enum LineReconstructor {
    static func reconstructLines(from page: PDFPage) -> [PhysicalLine] {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let pageSelection = page.selection(for: pageBounds) else { return [] }

        return pageSelection.selectionsByLine().compactMap { lineSelection in
            guard let text = lineSelection.string, !text.isEmpty else { return nil }
            return PhysicalLine(text: text, boundingBox: lineSelection.bounds(for: page))
        }
    }
}
