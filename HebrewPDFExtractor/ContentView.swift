import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var coordinator = ExtractionCoordinator()
    @State private var selectedDocumentID: PDFDocumentItem.ID?
    @State private var isTargeted = false
    @State private var isTargetedAnywhere = false
    @State private var showDiscardEditsConfirmation = false

    private var selectedDocument: PDFDocumentItem? {
        coordinator.documents.first { $0.id == selectedDocumentID }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.addDocuments(at: urls)
            return true
        } isTargeted: { targeted in
            isTargetedAnywhere = targeted
        }
        .onAppear { DebugDriver.shared?.attach(coordinator) }
        .onReceive(NotificationCenter.default.publisher(for: .debugSelectDocument)) { note in
            selectedDocumentID = note.object as? PDFDocumentItem.ID
        }
        .overlay {
            if isTargetedAnywhere {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(12)
                    Label("Drop documents anywhere", systemImage: "doc.badge.plus")
                        .font(.title3)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                // Extract/Export live as the prominent labeled buttons in the sidebar now — no
                // need to duplicate them here as icon-only toolbar buttons.
                Button {
                    presentFilePicker()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
            }
        }
        .sheet(item: $coordinator.pendingScannedPagePrompt) { request in
            ScannedPagePromptSheet(request: request) { response in
                coordinator.resolvePendingPrompt(with: response)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Max characters per line")
                    .font(.callout)
                Spacer()
                TextField("0 = no limit", value: $coordinator.settings.maxCharactersPerLine, formatter: NumberFormatter())
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 16)
            .padding(.horizontal)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $coordinator.settings.hebrewOnlyOCR) {
                    Label("Hebrew-only OCR", systemImage: "checkmark.seal")
                        .font(.callout.weight(.semibold))
                }
                .toggleStyle(.switch)
                Text("On: sharper OCR readings, but any English words or numbers on the page will be misread as Hebrew. Off (default): safe for mixed-language pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(coordinator.settings.hebrewOnlyOCR ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            )
            .padding(.horizontal)
            .padding(.bottom, 10)

            Button {
                if coordinator.manuallyEditedDocuments.isEmpty {
                    Task { await coordinator.processAll() }
                } else {
                    showDiscardEditsConfirmation = true
                }
            } label: {
                HStack {
                    if coordinator.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(coordinator.isProcessing ? "Processing…" : "Extract Text")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(coordinator.documents.isEmpty || coordinator.isProcessing)
            .padding(.horizontal)
            .padding(.bottom, 10)
            .confirmationDialog(
                "This will discard your edits to \(coordinator.manuallyEditedDocuments.map(\.displayName).joined(separator: ", "))",
                isPresented: $showDiscardEditsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Extract and Discard Edits", role: .destructive) {
                    Task { await coordinator.processAll() }
                }
                Button("Cancel", role: .cancel) {}
            }

            Menu {
                Button(coordinator.hasMultipleCompletedDocuments ? "Separate .txt file per source" : "Save as .txt") {
                    TextExporter.export(coordinator.documents, mode: .separateFiles)
                }
                if coordinator.hasMultipleCompletedDocuments {
                    Button("One combined .txt file") {
                        TextExporter.export(coordinator.documents, mode: .combinedFile)
                    }
                }
                Button("Extracted text as image (.jpg, one per file)") {
                    TextExporter.export(coordinator.documents, mode: .renderedTextImages)
                }
                if !coordinator.containsNonPDFDocuments {
                    Button("Original PDF pages as image (.jpg, one per page)") {
                        TextExporter.export(coordinator.documents, mode: .originalPageImages)
                    }
                }
                Menu("Other Format") {
                    Button("PDF (.pdf)") { TextExporter.export(coordinator.documents, mode: .pdf) }
                    Button("PNG image (.png)") { TextExporter.export(coordinator.documents, mode: .png) }
                    Button("Rich Text (.rtf)") { TextExporter.export(coordinator.documents, mode: .richDocument(.rtf)) }
                    Button("Word Document (.docx)") { TextExporter.export(coordinator.documents, mode: .richDocument(.docx)) }
                    Button("OpenDocument Text (.odt)") { TextExporter.export(coordinator.documents, mode: .richDocument(.odt)) }
                    Button("Web Page (.html)") { TextExporter.export(coordinator.documents, mode: .richDocument(.html)) }
                    Button("EPUB (.epub)") { TextExporter.export(coordinator.documents, mode: .epub) }
                }
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!coordinator.documents.contains { $0.status == .completed })
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            List(selection: $selectedDocumentID) {
                ForEach(coordinator.documents) { document in
                    FileRow(document: document) {
                        coordinator.removeDocument(document)
                    }
                    .tag(document.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            coordinator.removeDocument(document)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 260)
    }

    private var detail: some View {
        Group {
            if coordinator.documents.isEmpty {
                DropZoneView(isTargeted: $isTargeted) { urls in
                    coordinator.addDocuments(at: urls)
                }
                .padding(60)
            } else if let document = selectedDocument {
                PreviewView(document: document)
                    .id(document.id)
            } else {
                emptyDetailState
            }
        }
        .overlay(alignment: .bottom) {
            if coordinator.isProcessing {
                ProgressView("Processing…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
            Text("Select a file to preview its extracted text")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.allowedImportTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            coordinator.addDocuments(at: panel.urls)
        }
    }

    /// Named `UTType` constants exist for the common cases; the rest are resolved by extension
    /// since AppKit doesn't expose named constants for every format `RichDocumentImporter`/
    /// `EPUBImporter` can read.
    private static var allowedImportTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf, .rtfd, .html, .jpeg, .png, .tiff, .heic]
        for ext in ["doc", "docx", "odt", "epub"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}

#Preview {
    ContentView()
}
