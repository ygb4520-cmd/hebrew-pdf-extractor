import AppKit
import UniformTypeIdentifiers

enum RichDocumentImportError: LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let message): return "Couldn't read this document: \(message)"
        }
    }
}

/// Imports RTF/RTFD, legacy Word (.doc), Word Open XML (.docx), OpenDocument Text (.odt), and HTML
/// files via `NSAttributedString`'s native document readers — no third-party dependency needed;
/// verified directly that AppKit reads and writes all of these correctly with Hebrew/RTL content.
///
/// Unlike a PDF's content stream, these formats store text in logical reading order with
/// direction/alignment as separate attributes rather than glyph-drawing tricks, so — like
/// `TextFileImporter` — there's no visual-vs-logical ambiguity to correct here: `.string` already
/// gives correct logical order.
enum RichDocumentImporter {
    private static let documentTypesByExtension: [String: NSAttributedString.DocumentType] = [
        "rtf": .rtf,
        "rtfd": .rtfd,
        "doc": .docFormat,
        "docx": .officeOpenXML,
        "odt": .openDocument,
        "html": .html,
        "htm": .html,
    ]

    static var supportedExtensions: Set<String> { Set(documentTypesByExtension.keys) }

    static func importText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        guard let documentType = documentTypesByExtension[ext] else {
            throw RichDocumentImportError.unreadable("unsupported file type .\(ext)")
        }

        do {
            let attributedString = try NSAttributedString(
                url: url,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
            // These formats' paragraph storage always terminates with an implicit trailing
            // newline that isn't meaningful content — trimmed so a round-tripped file doesn't
            // pick up a stray blank line every time.
            return attributedString.string.trimmingCharacters(in: .newlines)
        } catch {
            throw RichDocumentImportError.unreadable(error.localizedDescription)
        }
    }
}
