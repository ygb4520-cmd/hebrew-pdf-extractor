import Foundation

/// A pending question shown to the user because a page has no extractable text layer.
/// Created by the extraction pipeline and resolved by the UI via `ExtractionCoordinator`.
struct ScannedPagePromptRequest: Identifiable {
    let id = UUID()
    let pdfDisplayName: String
    let pageNumber: Int
    let pageCountForPDF: Int
}

/// The user's answer to a `ScannedPagePromptRequest`.
struct ScannedPageDecisionResponse {
    let action: ScannedPageAction
    let scope: ScannedPageDecisionScope
}
