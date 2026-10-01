import SwiftUI

struct FileRow: View {
    @ObservedObject var document: PDFDocumentItem
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayName)
                    .lineLimit(1)
                Text(document.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if document.status == .processing {
                ProgressView(value: document.progress)
                    .frame(width: 40)
            } else if !document.flaggedPageNumbers.isEmpty || !document.skippedPageNumbers.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Some pages had no extractable text")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from list")
        }
        .padding(.vertical, 2)
    }
}
