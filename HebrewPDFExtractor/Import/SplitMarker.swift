import Foundation

/// A literal marker line the user inserts (via right-click in the editable preview) to mark a
/// split point. Deliberately just plain text rather than tracked character offsets or attributed-
/// string ranges: since it's part of the actual edited content, it naturally survives — and moves
/// correctly with — any further editing, with no separate position-tracking needed at all.
enum SplitMarker {
    static let line = "⟦✂ SPLIT HERE ✂⟧"

    /// Splits text on marker lines into the segments that would be exported, dropping any
    /// segment that's empty after trimming (e.g. from two markers placed back to back).
    static func segments(in text: String) -> [String] {
        text.components(separatedBy: line)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
