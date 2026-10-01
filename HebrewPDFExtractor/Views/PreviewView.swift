import SwiftUI

struct PreviewView: View {
    @ObservedObject var document: PDFDocumentItem

    var body: some View {
        Group {
            if document.status == .completed {
                SelectableTextView(
                    text: Binding(
                        get: { document.extractedText },
                        set: { newValue in
                            document.extractedText = newValue
                            document.isManuallyEdited = true
                        }
                    )
                )
            } else {
                Text(placeholderText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if !splitSegments.isEmpty {
                    splitExportBar
                }
                if !document.flaggedPageNumbers.isEmpty || !document.skippedPageNumbers.isEmpty {
                    warningsBar
                }
            }
        }
        .navigationTitle(document.displayName)
    }

    private var placeholderText: String {
        switch document.status {
        case .pending: return "Not yet processed. Click Extract to begin."
        case .processing: return "Processing…"
        case .failed(let message): return message
        case .completed: return "No text was found in this file."
        }
    }

    private var splitSegments: [String] {
        document.extractedText.contains(SplitMarker.line) ? SplitMarker.segments(in: document.extractedText) : []
    }

    /// Right-click anywhere in the text and choose "Add Split Point Here" to add as many split
    /// points as you want; this bar appears once there's at least one, to export the resulting
    /// pieces as separate files in one go.
    private var splitExportBar: some View {
        HStack {
            Text("\(splitSegments.count) segments — right-click to add more split points")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Export Segments as .txt") {
                TextExporter.exportSegments(
                    splitSegments,
                    baseName: baseName,
                    asImage: false,
                    directoryHint: document.sourceURL.deletingLastPathComponent()
                )
            }
            Button("Export Segments as .jpg") {
                TextExporter.exportSegments(
                    splitSegments,
                    baseName: baseName,
                    asImage: true,
                    directoryHint: document.sourceURL.deletingLastPathComponent()
                )
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.12))
    }

    private var baseName: String {
        document.sourceURL.deletingPathExtension().lastPathComponent
    }

    private var warningsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !document.flaggedPageNumbers.isEmpty {
                Text("Flagged (no extractable text): page \(document.flaggedPageNumbers.map(String.init).joined(separator: ", "))")
            }
            if !document.skippedPageNumbers.isEmpty {
                Text("Skipped (no extractable text): page \(document.skippedPageNumbers.map(String.init).joined(separator: ", "))")
            }
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }
}
