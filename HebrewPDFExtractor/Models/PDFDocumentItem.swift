import Foundation

enum ProcessingStatus: Equatable {
    case pending
    case processing
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .pending: return "Waiting"
        case .processing: return "Processing…"
        case .completed: return "Done"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

/// One source file selected by the user (a PDF or a plain `.txt` file), tracked through
/// extraction/import to export. PDF-specific fields (`flaggedPageNumbers`, `skippedPageNumbers`,
/// `stickyScannedPageAction`) simply stay at their defaults for a `.txt` source.
@MainActor
final class PDFDocumentItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL

    @Published var status: ProcessingStatus = .pending
    /// The extracted/imported text, wrapped to the "max characters per line" setting in effect at
    /// the time of the last (re-)extraction, and editable in the preview pane. Changing the wrap
    /// setting requires clicking Extract again — it always fully reprocesses (see
    /// `ExtractionCoordinator.processAll()`), warning first if this document has unsaved edits.
    @Published var extractedText: String = ""
    @Published var progress: Double = 0
    @Published var flaggedPageNumbers: [Int] = []
    @Published var skippedPageNumbers: [Int] = []

    /// Set whenever the user manually edits `extractedText` in the preview pane; cleared again
    /// once a fresh extraction overwrites it. Lets the UI warn before an "Extract" click would
    /// silently discard edits.
    @Published var isManuallyEdited = false

    /// Remembered scanned-page choice scoped to just this PDF ("rest of this PDF").
    var stickyScannedPageAction: ScannedPageAction?

    var displayName: String { sourceURL.lastPathComponent }

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }
}
