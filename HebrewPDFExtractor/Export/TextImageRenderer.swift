import CoreGraphics
import CoreText
import Foundation

/// Renders a block of (already-corrected) text right-to-left, via CoreText's own paragraph
/// layout — for the "text as image" and "text as PDF" export options. This applies the real
/// Unicode Bidirectional Algorithm for on-screen shaping, independent of, and unaffected by, the
/// extraction-side ordering fix in `LineReconstructor`/`ColumnDetector`.
enum TextImageRenderer {
    /// Setting only `.baseWritingDirection` correctly reverses word/character order within a
    /// line, but leaves the paragraph block itself left-aligned — `.alignment` must be set
    /// explicitly to `.right` too, or the whole text block visually reads as an LTR layout despite
    /// each line's contents being in correct RTL order. English paragraphs get the matching
    /// left-to-right/left-aligned style instead (see `TextDirection`). The setting pointers must stay
    /// valid through the `CTParagraphStyleCreate` call itself, so everything happens inside the same
    /// nested `withUnsafeBytes` scopes rather than via bare `&` pointers.
    private static func paragraphStyle(rightToLeft: Bool) -> CTParagraphStyle {
        var writingDirection = rightToLeft ? CTWritingDirection.rightToLeft : CTWritingDirection.leftToRight
        var alignment = rightToLeft ? CTTextAlignment.right : CTTextAlignment.left
        return withUnsafeBytes(of: &writingDirection) { directionPtr -> CTParagraphStyle in
            withUnsafeBytes(of: &alignment) { alignmentPtr -> CTParagraphStyle in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .baseWritingDirection,
                        valueSize: MemoryLayout<CTWritingDirection>.size,
                        value: directionPtr.baseAddress!
                    ),
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPtr.baseAddress!
                    ),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    private static func framesetter(for text: String, fontSize: CGFloat) -> (framesetter: CTFramesetter, length: Int) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let displayText = text.isEmpty ? " " : text
        let attrString = CFAttributedStringCreateMutable(nil, 0)!
        CFAttributedStringReplaceString(attrString, CFRangeMake(0, 0), displayText as CFString)
        let whole = CFRangeMake(0, CFAttributedStringGetLength(attrString))
        CFAttributedStringSetAttribute(attrString, whole, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(attrString, whole, kCTForegroundColorAttributeName, CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1))

        let rtl = paragraphStyle(rightToLeft: true), ltr = paragraphStyle(rightToLeft: false)
        let ns = displayText as NSString
        var location = 0
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let isRTL = TextDirection.isRightToLeft(ns.substring(with: paragraph))
            CFAttributedStringSetAttribute(attrString, CFRangeMake(paragraph.location, paragraph.length), kCTParagraphStyleAttributeName, isRTL ? rtl : ltr)
            location = NSMaxRange(paragraph)
        }
        return (CTFramesetterCreateWithAttributedString(attrString), CFAttributedStringGetLength(attrString))
    }

    /// CoreText lays a single very long block of Hebrew out wrongly: past roughly 10,000 characters
    /// the whole block (even its first lines) comes out with every line's letters reversed. Verified by
    /// rendering successively longer prefixes of the same text. Long text is therefore always laid out
    /// in independent pieces, split only at line breaks, each small enough to render correctly.
    private static let maxChunkLength = 2500

    static func chunks(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentLength = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let piece = String(line) + "\n"
            if currentLength > 0 && currentLength + piece.utf16.count > maxChunkLength {
                result.append(current)
                current = ""
                currentLength = 0
            }
            current += piece
            currentLength += piece.utf16.count
        }
        if !current.isEmpty { result.append(current) }
        if let last = result.last, last.hasSuffix("\n"), !text.hasSuffix("\n") {
            result[result.count - 1] = String(last.dropLast())
        }
        return result.isEmpty ? [text] : result
    }

    /// JPEG cannot encode an image taller than 65,535 pixels; leave headroom below that.
    static let maxJPEGHeight: CGFloat = 65_000

    private static func pieceHeights(for text: String, canvasWidth: CGFloat, fontSize: CGFloat, margin: CGFloat) -> [(text: String, height: CGFloat)] {
        let textWidth = canvasWidth - margin * 2
        return chunks(of: text).map { piece in
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter(for: piece, fontSize: fontSize).framesetter, CFRangeMake(0, 0), nil,
                CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil
            )
            return (piece, size.height)
        }
    }

    /// Height in pixels `renderImage` would produce for this text.
    static func imageHeight(for text: String, canvasWidth: CGFloat = 1100, fontSize: CGFloat = 22, margin: CGFloat = 48) -> CGFloat {
        let total = pieceHeights(for: text, canvasWidth: canvasWidth, fontSize: fontSize, margin: margin).reduce(0) { $0 + $1.height }
        return max(total + margin * 2, margin * 2 + fontSize)
    }

    /// Renders the text as as many images as needed so none is taller than `maxHeight`, splitting
    /// only between the same line-break-aligned pieces `renderImage` already uses.
    static func renderImages(for text: String, maxHeight: CGFloat = maxJPEGHeight, canvasWidth: CGFloat = 1100, fontSize: CGFloat = 22, margin: CGFloat = 48) -> [CGImage] {
        var parts: [String] = []
        var current = ""
        var currentHeight = margin * 2
        for piece in pieceHeights(for: text, canvasWidth: canvasWidth, fontSize: fontSize, margin: margin) {
            if !current.isEmpty && currentHeight + piece.height > maxHeight {
                parts.append(current)
                current = ""
                currentHeight = margin * 2
            }
            current += piece.text
            currentHeight += piece.height
        }
        if !current.isEmpty { parts.append(current) }
        return parts.compactMap {
            renderImage(for: $0.hasSuffix("\n") ? String($0.dropLast()) : $0, canvasWidth: canvasWidth, fontSize: fontSize, margin: margin)
        }
    }

    static func renderImage(for text: String, canvasWidth: CGFloat = 1100, fontSize: CGFloat = 22, margin: CGFloat = 48) -> CGImage? {
        let textWidth = canvasWidth - margin * 2
        let pieces = chunks(of: text).map { framesetter(for: $0, fontSize: fontSize).framesetter }
        let sizes = pieces.map {
            CTFramesetterSuggestFrameSizeWithConstraints($0, CFRangeMake(0, 0), nil, CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil)
        }
        let textHeight = sizes.reduce(0) { $0 + $1.height }
        let canvasHeight = max(textHeight + margin * 2, margin * 2 + fontSize)

        guard let context = CGContext(
            data: nil,
            width: Int(canvasWidth.rounded(.up)),
            height: Int(canvasHeight.rounded(.up)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        // CoreText draws bottom-up: the first piece sits at the top, so start from the top edge.
        var top = canvasHeight - margin
        for (piece, size) in zip(pieces, sizes) {
            let framePath = CGPath(rect: CGRect(x: margin, y: top - size.height, width: textWidth, height: size.height), transform: nil)
            let frame = CTFramesetterCreateFrame(piece, CFRangeMake(0, 0), framePath, nil)
            CTFrameDraw(frame, context)
            top -= size.height
        }

        return context.makeImage()
    }

    /// Renders the same right-to-left CoreText layout to a PDF file, paginating automatically if the
    /// text is too long for a single page. Text is laid out in independent pieces (see `chunks(of:)`)
    /// flowed one after another down each page, each piece continued onto the next page if it doesn't
    /// fit in the space left.
    @discardableResult
    static func renderPDF(
        for text: String,
        to url: URL,
        pageWidth: CGFloat = 612,
        pageHeight: CGFloat = 792,
        fontSize: CGFloat = 14,
        margin: CGFloat = 54
    ) -> Bool {
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return false }

        let textWidth = pageWidth - margin * 2
        let pageTop = pageHeight - margin
        var pageOpen = false
        var y = pageTop

        func startPage() {
            context.beginPDFPage(nil)
            pageOpen = true
            y = pageTop
        }
        func endPage() {
            if pageOpen { context.endPDFPage() }
            pageOpen = false
        }

        for piece in chunks(of: text) {
            let (framesetter, length) = framesetter(for: piece, fontSize: fontSize)
            var offset = 0
            while offset < length {
                if !pageOpen { startPage() }
                let available = y - margin
                let framePath = CGPath(rect: CGRect(x: margin, y: margin, width: textWidth, height: available), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(offset, 0), framePath, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 {
                    if y == pageTop { break } // nothing fits even on a fresh page: never loop forever
                    endPage()
                    continue
                }
                let used = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter, CFRangeMake(offset, visible.length), nil, CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil
                ).height
                // Draw into a frame whose top edge is the current flow position.
                let drawPath = CGPath(rect: CGRect(x: margin, y: y - used, width: textWidth, height: used), transform: nil)
                CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRangeMake(offset, visible.length), drawPath, nil), context)
                y -= used
                offset += visible.length
                if offset < length { endPage() }
            }
        }
        endPage()
        context.closePDF()
        return true
    }
}
