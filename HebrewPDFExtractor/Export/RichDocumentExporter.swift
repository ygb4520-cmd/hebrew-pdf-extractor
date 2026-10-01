import AppKit

enum RichDocumentExportError: LocalizedError {
    case renderingFailed
    var errorDescription: String? { "Couldn't generate this document format." }
}

enum RichDocumentFormat {
    case rtf
    case docx
    case odt
    case html

    var documentType: NSAttributedString.DocumentType {
        switch self {
        case .rtf: return .rtf
        case .docx: return .officeOpenXML
        case .odt: return .openDocument
        case .html: return .html
        }
    }

    var fileExtension: String {
        switch self {
        case .rtf: return "rtf"
        case .docx: return "docx"
        case .odt: return "odt"
        case .html: return "html"
        }
    }
}

/// Exports to RTF, Word (.docx), OpenDocument Text (.odt), and HTML via `NSAttributedString`'s
/// native document writers — verified directly that explicitly setting both
/// `baseWritingDirection` and `alignment` to right-to-left/right produces correctly right-aligned,
/// bidi-marked output in all four formats (e.g. `<w:bidi/>` in the .docx's XML), not just correct
/// word-internal character order.
enum RichDocumentExporter {
    static func makeAttributedString(for text: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.alignment = .right

        let font = NSFont(name: "Arial", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        return NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .paragraphStyle: paragraphStyle,
            .font: font,
        ])
    }

    @discardableResult
    static func write(_ text: String, format: RichDocumentFormat, to url: URL) -> Bool {
        let attributedString = makeAttributedString(for: text)
        let range = NSRange(location: 0, length: attributedString.length)
        guard let data = try? attributedString.data(from: range, documentAttributes: [.documentType: format.documentType]) else {
            return false
        }
        return (try? data.write(to: url)) != nil
    }
}
