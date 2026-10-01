import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                    Text("Drop documents here")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
            .dropDestination(for: URL.self) { items, _ in
                onDrop(items)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}
