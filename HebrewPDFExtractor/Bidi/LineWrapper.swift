import Foundation

/// Wraps already logically-ordered text to a maximum line length, breaking only at whitespace and
/// never inside a word. Maqaf (־, U+05BE) joins two Hebrew words with no surrounding whitespace, so
/// splitting on whitespace already keeps a maqaf-joined compound intact as a single unbreakable unit
/// — no special-case handling is needed beyond that.
///
/// Known limitation: a single word/compound longer than the limit is left on its own line rather
/// than broken, since breaking mid-word is never allowed.
enum LineWrapper {
    static func wrap(_ text: String, maxCharactersPerLine: Int) -> String {
        guard maxCharactersPerLine > 0 else { return text }

        return text
            .components(separatedBy: "\n")
            .map { wrapSingleLine($0, maxCharactersPerLine: maxCharactersPerLine) }
            .joined(separator: "\n")
    }

    private static func wrapSingleLine(_ line: String, maxCharactersPerLine: Int) -> String {
        guard line.count > maxCharactersPerLine else { return line }

        let words = line.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > 1 else { return line }

        var wrappedLines: [String] = []
        var current = ""

        for word in words {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= maxCharactersPerLine {
                current += " " + word
            } else {
                wrappedLines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { wrappedLines.append(current) }
        return wrappedLines.joined(separator: "\n")
    }
}
