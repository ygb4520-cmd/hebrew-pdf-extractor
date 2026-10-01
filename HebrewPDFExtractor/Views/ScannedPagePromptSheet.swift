import SwiftUI

struct ScannedPagePromptSheet: View {
    let request: ScannedPagePromptRequest
    let onRespond: (ScannedPageDecisionResponse) -> Void

    @State private var selectedAction: ScannedPageAction = .ocr
    @State private var selectedScope: ScannedPageDecisionScope = .thisPageOnly

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("No extractable text found", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            Text("Page \(request.pageNumber) of \(request.pageCountForPDF) in \u{201c}\(request.pdfDisplayName)\u{201d} appears to be a scanned image with no text layer.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("What should we do?").font(.subheadline.bold())
                Picker("", selection: $selectedAction) {
                    ForEach(ScannedPageAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Apply this choice to").font(.subheadline.bold())
                Picker("", selection: $selectedScope) {
                    ForEach(ScannedPageDecisionScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Continue") {
                    onRespond(ScannedPageDecisionResponse(action: selectedAction, scope: selectedScope))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
