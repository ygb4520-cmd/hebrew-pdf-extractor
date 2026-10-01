import Foundation
import CoreFoundation

/// `String.Encoding` has no built-in members for these, and Swift doesn't even import the
/// symbolic `kCFStringEncodingWindowsHebrew`/`kCFStringEncodingISOLatinHebrew` C constants from
/// `CFStringEncodingExt.h` — so the raw values from that header are used directly, bridged to an
/// `NSStringEncoding`-backed `String.Encoding` via `CFStringConvertEncodingToNSStringEncoding`.
/// Verified against a real Windows-1255-encoded Hebrew string before use.
private extension String.Encoding {
    static let windowsHebrew = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(0x0505) // kCFStringEncodingWindowsHebrew
    )
    static let isoLatinHebrew = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(0x0208) // kCFStringEncodingISOLatinHebrew
    )
}

enum TextFileImportError: LocalizedError {
    case undecodable

    var errorDescription: String? {
        "Couldn't decode this file as text (tried UTF-8, Windows-1255, and ISO-8859-8)."
    }
}

/// Reads a plain-text file for the `.txt` import path, independent of the PDF pipeline entirely.
///
/// Unlike a PDF's content stream, a `.txt` file has no visual-vs-logical character ordering
/// ambiguity — its bytes decode directly to Unicode codepoints in whatever order they were saved,
/// which for any normally-authored Hebrew text file is already correct logical reading order. So
/// there's no analogue of `LineReconstructor`/`ColumnDetector` needed here: the decoded string is
/// handed straight to the existing `LineWrapper` and `TextImageRenderer`, which already operate on
/// plain `String` with no dependency on PDFKit-derived line data.
enum TextFileImporter {
    /// Encodings tried in order after UTF-8: Windows-1255 (the more commonly seen legacy Hebrew
    /// Windows encoding in the wild) before ISO-8859-8.
    private static let legacyEncodings: [String.Encoding] = [.windowsHebrew, .isoLatinHebrew]

    static func importText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        let decoded = String(data: data, encoding: .utf8)
            ?? legacyEncodings.lazy.compactMap { String(data: data, encoding: $0) }.first

        guard let text = decoded else { throw TextFileImportError.undecodable }
        return collapseConsecutiveBlankLines(in: text)
    }

    private static func collapseConsecutiveBlankLines(in text: String) -> String {
        var result: [Substring] = []
        var previousWasBlank = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && previousWasBlank { continue }
            result.append(line)
            previousWasBlank = isBlank
        }
        return result.joined(separator: "\n")
    }
}
