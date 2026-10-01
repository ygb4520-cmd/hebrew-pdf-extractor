import Foundation

/// The app's central view model: owns the batch of selected source files (PDF and many other
/// formats — see `supportedExtensions`), drives extraction/import for each, and answers per-page
/// scanned-page questions the PDF extractor raises along the way — showing a sheet (via
/// `pendingScannedPagePrompt`) and suspending the extractor until the user responds. Every format
/// other than PDF bypasses that prompt entirely: `.txt`/rich-document/EPUB formats are just
/// read/parsed, and standalone image files always run straight through OCR (a raster image has no
/// text layer to check first, so there's no "does this page already have text" question to ask).
@MainActor
final class ExtractionCoordinator: ObservableObject, ScannedPageDecisionProviding {
    @Published var documents: [PDFDocumentItem] = []
    @Published var settings = ExtractionSettings()
    @Published var pendingScannedPagePrompt: ScannedPagePromptRequest?
    @Published var isProcessing = false

    private var runWideScannedPageAction: ScannedPageAction?
    private var pendingContinuations: [UUID: CheckedContinuation<ScannedPageDecisionResponse, Never>] = [:]
    private let ocrEngine = OCREngine()

    private static let supportedExtensions: Set<String> = Set(["pdf", "txt", "epub"])
        .union(RichDocumentImporter.supportedExtensions)
        .union(ImageFileImporter.supportedExtensions)

    /// Whether the batch contains anything that isn't a real PDF — used to hide the
    /// "original PDF pages as image" export option, which has no meaning for a `.txt` source.
    var containsNonPDFDocuments: Bool {
        documents.contains { $0.sourceURL.pathExtension.lowercased() != "pdf" }
    }

    /// Whether "combine into one file" is a meaningful choice — with only one completed
    /// document, it's nearly redundant with exporting separately.
    var hasMultipleCompletedDocuments: Bool {
        documents.filter { $0.status == .completed }.count > 1
    }

    /// Documents whose text has been manually edited since it was last (re-)extracted — clicking
    /// Extract would silently discard these unless the caller confirms first.
    var manuallyEditedDocuments: [PDFDocumentItem] {
        documents.filter { $0.isManuallyEdited }
    }

    func addDocuments(at urls: [URL]) {
        let supportedURLs = urls.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        let existing = Set(documents.map { $0.sourceURL })
        for url in supportedURLs where !existing.contains(url) {
            documents.append(PDFDocumentItem(sourceURL: url))
        }
    }

    func removeDocument(_ document: PDFDocumentItem) {
        documents.removeAll { $0.id == document.id }
    }

    /// (Re-)extracts every document in the batch — including ones already marked completed, so
    /// clicking Extract again always actually does something (e.g. to pick up a changed OCR
    /// choice, or just to start over). Callers should confirm with the user first if
    /// `manuallyEditedDocuments` is non-empty, since this will overwrite those edits.
    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let extractor = PDFTextExtractor(ocrEngine: ocrEngine, decisionProvider: self, hebrewOnlyOCR: settings.hebrewOnlyOCR)
        for document in documents {
            document.status = .processing
            document.isManuallyEdited = false
            document.flaggedPageNumbers = []
            document.skippedPageNumbers = []
            await Task.yield() // let the "Processing…" state actually render before the work starts
            do {
                let ext = document.sourceURL.pathExtension.lowercased()
                let rawText: String
                if ext == "txt" {
                    rawText = try TextFileImporter.importText(from: document.sourceURL)
                } else if ext == "epub" {
                    rawText = try EPUBImporter.importText(from: document.sourceURL)
                } else if RichDocumentImporter.supportedExtensions.contains(ext) {
                    rawText = try RichDocumentImporter.importText(from: document.sourceURL)
                } else if ImageFileImporter.supportedExtensions.contains(ext) {
                    let cgImage = try ImageFileImporter.loadCGImage(from: document.sourceURL)
                    rawText = try await ocrEngine.recognizeText(on: cgImage, hebrewOnly: settings.hebrewOnlyOCR)
                } else {
                    rawText = try await extractor.extractText(from: document)
                }
                document.extractedText = LineWrapper.wrap(rawText, maxCharactersPerLine: settings.maxCharactersPerLine)
                document.status = .completed
            } catch {
                document.status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - ScannedPageDecisionProviding

    func decideAction(for document: PDFDocumentItem, pageNumber: Int, pageCount: Int) async -> ScannedPageAction {
        if let runWide = runWideScannedPageAction { return runWide }
        if let sticky = document.stickyScannedPageAction { return sticky }

        let request = ScannedPagePromptRequest(
            pdfDisplayName: document.displayName,
            pageNumber: pageNumber,
            pageCountForPDF: pageCount
        )

        let response: ScannedPageDecisionResponse = await withCheckedContinuation { continuation in
            pendingContinuations[request.id] = continuation
            pendingScannedPagePrompt = request
        }

        switch response.scope {
        case .thisPageOnly:
            break
        case .restOfThisPDF:
            document.stickyScannedPageAction = response.action
        case .restOfRun:
            runWideScannedPageAction = response.action
        }
        return response.action
    }

    /// Called by the scanned-page sheet's buttons to resume the suspended extractor.
    func resolvePendingPrompt(with response: ScannedPageDecisionResponse) {
        guard let request = pendingScannedPagePrompt else { return }
        pendingScannedPagePrompt = nil
        pendingContinuations.removeValue(forKey: request.id)?.resume(returning: response)
    }
}
