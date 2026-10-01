import PDFKit

enum ExtractionError: LocalizedError {
    case unreadable
    case encrypted

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file couldn't be read as a PDF (it may be corrupted)."
        case .encrypted: return "This PDF is password-protected and couldn't be unlocked automatically."
        }
    }
}

/// Orchestrates extraction for one PDF: walks its pages, reconstructs correct reading order for
/// text-layer pages, and defers to OCR (or skip/flag) for image-only pages per the user's choice.
@MainActor
struct PDFTextExtractor {
    let ocrEngine: OCREngine
    unowned let decisionProvider: ScannedPageDecisionProviding
    var hebrewOnlyOCR: Bool = false

    func extractText(from document: PDFDocumentItem) async throws -> String {
        guard let pdf = PDFDocument(url: document.sourceURL) else {
            throw ExtractionError.unreadable
        }
        if pdf.isLocked {
            _ = pdf.unlock(withPassword: "")
            if pdf.isLocked {
                throw ExtractionError.encrypted
            }
        }

        let pageCount = pdf.pageCount
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pageCount)

        for pageIndex in 0..<pageCount {
            document.progress = pageCount > 0 ? Double(pageIndex) / Double(pageCount) : 1
            // Without this, a page with a text layer never hits an `await` at all (OCR/prompt
            // only happen for image-only pages), so this @MainActor loop runs start-to-finish
            // with no chance for SwiftUI to redraw or the window to respond to input — the app
            // looks completely frozen for the whole extraction instead of just "processing."
            await Task.yield()
            guard let page = pdf.page(at: pageIndex) else { continue }

            let lines = LineReconstructor.reconstructLines(from: page)
            let hasText = lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            if hasText {
                let pageWidth = page.bounds(for: .mediaBox).width
                let columns = ColumnDetector.detectColumns(in: lines, pageWidth: pageWidth)
                pageTexts.append(renderColumns(columns))
            } else {
                let action = await decisionProvider.decideAction(
                    for: document,
                    pageNumber: pageIndex + 1,
                    pageCount: pageCount
                )
                switch action {
                case .ocr:
                    let ocrText = (try? await ocrEngine.recognizeText(on: page, hebrewOnly: hebrewOnlyOCR)) ?? ""
                    pageTexts.append(ocrText)
                case .skip:
                    document.skippedPageNumbers.append(pageIndex + 1)
                case .flagOnly:
                    document.flaggedPageNumbers.append(pageIndex + 1)
                }
            }
        }

        document.progress = 1
        return pageTexts.joined(separator: "\n\n")
    }

    private func renderColumns(_ columns: [PageColumn]) -> String {
        columns.map { column in
            column.lines.map { $0.text }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
