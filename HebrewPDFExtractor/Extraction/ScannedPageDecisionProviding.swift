import Foundation

/// Supplies the action to take for a page with no extractable text layer, asking the user
/// (via whatever UI it's backed by) when neither a per-PDF nor a run-wide choice is already set.
@MainActor
protocol ScannedPageDecisionProviding: AnyObject {
    func decideAction(for document: PDFDocumentItem, pageNumber: Int, pageCount: Int) async -> ScannedPageAction
}
