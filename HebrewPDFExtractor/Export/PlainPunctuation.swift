import Foundation

/// Replaces typographic ("smart") punctuation with plain keyboard characters, for devices that can't
/// decode UTF-8 (cheap MP3 players, old e-readers). Characters like the curly apostrophe in "it’s"
/// take three bytes in UTF-8; a reader that assumes a legacy Chinese encoding turns those bytes into
/// CJK characters. Plain ASCII means the same bytes in every encoding. Hebrew letters, niqqud,
/// maqaf, geresh and gershayim are left alone — only Latin-style punctuation and invisible
/// characters change.
enum PlainPunctuation {
    private static let replacements: [Character: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", "\u{02BC}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", "\u{2033}": "\"",
        "\u{2013}": "-", "\u{2014}": "-", "\u{2015}": "-", "\u{2212}": "-", "\u{2010}": "-", "\u{2011}": "-",
        "\u{2026}": "...",
        "\u{2022}": "*", "\u{00B7}": "*",
        "\u{00A0}": " ", "\u{2009}": " ", "\u{202F}": " ", "\u{2003}": " ", "\u{2002}": " ",
        "\u{200B}": "", "\u{FEFF}": "",
    ]

    static func apply(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf16.count)
        for scalar in text.unicodeScalars {
            if let replacement = replacements[Character(scalar)] {
                result += replacement
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
