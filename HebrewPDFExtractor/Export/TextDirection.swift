import Foundation

/// Decides a paragraph's base direction from its first strongly-directional letter — the same rule
/// the Unicode bidi algorithm uses — so Hebrew paragraphs lay out right-to-left and English ones
/// left-to-right, instead of forcing one direction on everything. A paragraph with no letters
/// (blank, digits only) defaults to right-to-left, since this app is Hebrew-focused.
enum TextDirection {
    static func isRightToLeft(_ paragraph: String) -> Bool {
        for scalar in paragraph.unicodeScalars {
            let v = scalar.value
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) {
                return true
            }
            if scalar.properties.isAlphabetic { return false }
        }
        return true
    }
}
