import SwiftUI
import AppKit

/// An editable text view backed by `NSTextView`/`NSScrollView`, for displaying and editing
/// potentially large bodies of extracted text.
///
/// SwiftUI's `Text` (even with `.textSelection(.enabled)`) lays out its *entire* string at once
/// rather than incrementally as the user scrolls — fine for a few lines, but it can make the whole
/// window stall for several seconds (looking like a freeze) once the string reaches the size of a
/// real multi-page extracted document. `NSTextView` is built for exactly this and scales fine.
///
/// Edits flow back out via `text` (two-way binding to `PDFDocumentItem.extractedText` — session-
/// only, never written back to the source file on disk). Right-clicking anywhere adds an "Add
/// Split Point Here" item to the standard context menu, which inserts `SplitMarker.line` as its
/// own line at that point — see `PreviewView`'s split-export bar for turning those into files.
/// `usesFindBar` opts into AppKit's standard inline find bar (⌘F, wired up in
/// `HebrewPDFExtractorApp`'s menu commands) for searching within the text.
struct SelectableTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        // A monospaced font has no Hebrew glyphs, forcing a per-run font fallback that makes scrolling
        // choppy on long text; the regular system font covers Hebrew natively.
        textView.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        Coordinator.applyDirections(to: textView)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        Coordinator.highlightSplitMarkers(in: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        Coordinator.applyDirections(to: textView)
        Coordinator.highlightSplitMarkers(in: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        weak var textView: NSTextView?
        private var pendingSplitCharIndex: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            Self.applyDirections(to: textView, in: textView.selectedRange())
            Self.highlightSplitMarkers(in: textView)
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            pendingSplitCharIndex = charIndex
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Add Split Point Here", action: #selector(insertSplitPoint(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return menu
        }

        @objc private func insertSplitPoint(_ sender: NSMenuItem) {
            guard let textView, let charIndex = pendingSplitCharIndex else { return }
            let nsString = textView.string as NSString
            let clampedIndex = min(max(charIndex, 0), nsString.length)
            let lineStart = nsString.lineRange(for: NSRange(location: clampedIndex, length: 0)).location
            textView.insertText("\n\(SplitMarker.line)\n", replacementRange: NSRange(location: lineStart, length: 0))
        }

        /// A plain-text NSTextView lays every paragraph out left-aligned regardless of language, so
        /// Hebrew needs an explicit right-to-left, right-aligned paragraph style. But forcing that on
        /// everything would also right-align English, so each paragraph gets its own style chosen from
        /// its first strong letter (see `TextDirection`). `range` limits the work to the paragraphs
        /// touching it (used while typing, so a keystroke doesn't restyle the whole document).
        static func applyDirections(to textView: NSTextView, in range: NSRange? = nil) {
            guard let storage = textView.textStorage else { return }
            let nsString = storage.string as NSString
            guard nsString.length > 0 else { return }
            let target = nsString.paragraphRange(for: range ?? NSRange(location: 0, length: nsString.length))
            let rtl = paragraphStyle(rightToLeft: true), ltr = paragraphStyle(rightToLeft: false)
            textView.defaultParagraphStyle = rtl

            storage.beginEditing()
            var location = target.location
            while location < NSMaxRange(target) {
                let paragraph = nsString.paragraphRange(for: NSRange(location: location, length: 0))
                let isRTL = TextDirection.isRightToLeft(nsString.substring(with: paragraph))
                storage.addAttribute(.paragraphStyle, value: isRTL ? rtl : ltr, range: paragraph)
                location = NSMaxRange(paragraph)
            }
            storage.endEditing()
            if let caret = textView.selectedRanges.first?.rangeValue, caret.location <= nsString.length {
                let probe = nsString.paragraphRange(for: NSRange(location: min(caret.location, max(nsString.length - 1, 0)), length: 0))
                textView.typingAttributes[.paragraphStyle] = TextDirection.isRightToLeft(nsString.substring(with: probe)) ? rtl : ltr
            }
        }

        private static func paragraphStyle(rightToLeft: Bool) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
            style.alignment = rightToLeft ? .right : .left
            return style
        }

        /// Gives every occurrence of the split marker a highlighted background so it's easy to
        /// spot in the text, without altering the actual text content.
        static func highlightSplitMarkers(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let nsString = storage.string as NSString
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: nsString.length))

            var searchRange = NSRange(location: 0, length: nsString.length)
            while searchRange.location < nsString.length {
                let found = nsString.range(of: SplitMarker.line, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: found)
                let nextLocation = found.location + found.length
                searchRange = NSRange(location: nextLocation, length: nsString.length - nextLocation)
            }
        }
    }
}
