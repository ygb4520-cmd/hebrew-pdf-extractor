import CoreGraphics

/// A vertical band of the page containing a subset of lines, in top-to-bottom order.
struct PageColumn {
    var lines: [PhysicalLine]
    var xRange: ClosedRange<Double>
}

/// Detects multi-column layouts from reconstructed lines by looking for a vertical whitespace
/// "gutter" wide enough, and consistent enough down the page, to be a real column break rather
/// than an incidental short-line gap. Columns are returned right-to-left, matching the reading
/// order of a Hebrew document (rightmost column first).
enum ColumnDetector {
    static func detectColumns(in lines: [PhysicalLine], pageWidth: CGFloat) -> [PageColumn] {
        let topToBottom = lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        guard lines.count > 1, pageWidth > 0 else {
            return lines.isEmpty ? [] : [PageColumn(lines: topToBottom, xRange: 0...Double(pageWidth))]
        }

        // Bin width and minimum gutter width scale with the page's own width, so this works
        // whether `pageWidth`/rects are in PDF points (PDFKit) or normalized 0...1 units (Vision OCR).
        let binCount = 200
        let binWidth = pageWidth / CGFloat(binCount)
        var coverage = [Int](repeating: 0, count: binCount)

        for line in lines {
            let startBin = max(0, Int(line.boundingBox.minX / binWidth))
            let endBin = min(binCount - 1, Int(line.boundingBox.maxX / binWidth))
            guard startBin <= endBin else { continue }
            for b in startBin...endBin { coverage[b] += 1 }
        }

        guard let firstOccupied = coverage.firstIndex(where: { $0 > 0 }),
              let lastOccupied = coverage.lastIndex(where: { $0 > 0 }),
              firstOccupied < lastOccupied else {
            return [PageColumn(lines: topToBottom, xRange: 0...Double(pageWidth))]
        }

        let sparseThreshold = max(1, Int(Double(lines.count) * 0.05))
        var gutterBins = coverage.map { $0 <= sparseThreshold }
        for i in 0..<gutterBins.count where i < firstOccupied || i > lastOccupied {
            gutterBins[i] = false
        }

        let minGutterWidth: CGFloat = pageWidth * 0.02
        var gutterRanges: [(start: Int, end: Int)] = []
        var runStart: Int?
        for i in 0..<gutterBins.count {
            if gutterBins[i] {
                if runStart == nil { runStart = i }
            } else if let start = runStart {
                if CGFloat(i - start) * binWidth >= minGutterWidth {
                    gutterRanges.append((start, i - 1))
                }
                runStart = nil
            }
        }
        if let start = runStart, CGFloat(gutterBins.count - start) * binWidth >= minGutterWidth {
            gutterRanges.append((start, gutterBins.count - 1))
        }

        guard !gutterRanges.isEmpty else {
            return [PageColumn(lines: topToBottom, xRange: 0...Double(pageWidth))]
        }

        let splitXs = gutterRanges.map { Double($0.start + $0.end) / 2.0 * Double(binWidth) }
        let boundaries = ([0.0] + splitXs + [Double(pageWidth)]).sorted()

        var columns: [PageColumn] = []
        for i in 0..<(boundaries.count - 1) {
            let isLastBand = i == boundaries.count - 2
            let lower = boundaries[i]
            let upper = boundaries[i + 1]
            let columnLines = lines
                .filter { line in
                    let mid = Double(line.boundingBox.midX)
                    return mid >= lower && (isLastBand ? mid <= upper : mid < upper)
                }
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY } // top-to-bottom
            guard !columnLines.isEmpty else { continue }
            columns.append(PageColumn(lines: columnLines, xRange: lower...upper))
        }

        // Rightmost column's content first, matching Hebrew document reading order.
        return columns.sorted { $0.xRange.lowerBound > $1.xRange.lowerBound }
    }
}
