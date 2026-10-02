import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ExportMode {
    case separateFiles
    case combinedFile
    case renderedTextImages
    case originalPageImages
    case pdf
    case png
    case richDocument(RichDocumentFormat)
    case epub
}

/// Writes completed documents to disk in the user's chosen format, prompting for a destination via
/// native save/open panels. The format choice is asked fresh on every export by the caller (see
/// `ContentView`'s export dialog) rather than remembered, per the user's explicit preference. The
/// destination *folder*, however, is remembered across exports (see `ExportDestinationMemory`) —
/// each panel still lets you pick somewhere else, which just updates what's remembered next time.
///
/// `document.extractedText` is already wrapped to the current "max characters per line" setting
/// (applied once at extraction time — see `ExtractionCoordinator.processAll()`), so nothing here
/// needs to wrap it again.
@MainActor
enum TextExporter {
    @discardableResult
    static func export(_ documents: [PDFDocumentItem], mode: ExportMode) -> Bool {
        let completed = documents.filter { $0.status == .completed }
        guard !completed.isEmpty else { return false }

        switch mode {
        case .separateFiles:
            return exportSeparately(completed)
        case .combinedFile:
            return exportCombined(completed)
        case .renderedTextImages:
            return exportRenderedTextImages(completed)
        case .originalPageImages:
            return exportOriginalPageImages(completed)
        case .pdf:
            return exportPDF(completed)
        case .png:
            return exportPNG(completed)
        case .richDocument(let format):
            return exportRichDocuments(completed, format: format)
        case .epub:
            return exportEPUB(completed)
        }
    }

    private static func exportSeparately(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .txt file per source file"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        writeSeparateTXT(documents, in: folder)
        return true
    }

    /// "Plain punctuation in .txt" (set from the Export menu; remembered across launches). The debug
    /// driver sets `plainPunctuationOverride` instead so tests never touch the user's saved setting.
    static let plainPunctuationKey = "plainPunctuationTXT"
    static var plainPunctuationOverride: Bool?

    static var plainPunctuationEnabled: Bool {
        plainPunctuationOverride ?? UserDefaults.standard.bool(forKey: plainPunctuationKey)
    }

    /// The text to write into a `.txt` file, honoring the plain-punctuation option.
    static func txtContent(_ text: String) -> String {
        plainPunctuationEnabled ? PlainPunctuation.apply(text) : text
    }

    /// A destination that never replaces anything: `<name>.<ext>` if that's free, otherwise
    /// `<name> (2).<ext>`, `<name> (3).<ext>`, … Files are written one at a time, so this also keeps
    /// two sources that share a name (e.g. `book.pdf` and `book.txt` exported as `.txt`) from
    /// overwriting each other within a single export — and keeps "Save as .txt" on a `.txt` source
    /// from overwriting the original when the export folder is the source's own folder.
    static func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) (\(counter))").appendingPathExtension(ext)
            counter += 1
        }
        return url
    }

    /// One `<source name>.txt` per document in `folder` (the writing half of "Save as .txt").
    static func writeSeparateTXT(_ documents: [PDFDocumentItem], in folder: URL) {
        for document in documents {
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            let destination = uniqueURL(in: folder, name: baseName, ext: "txt")
            try? txtContent(document.extractedText).write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    /// All documents joined into one text (the content half of "One combined .txt file").
    static func combinedText(_ documents: [PDFDocumentItem]) -> String {
        txtContent(documents
            .map { "===== \($0.displayName) =====\n\($0.extractedText)" }
            .joined(separator: "\n\n"))
    }

    private static func exportCombined(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = documents.count == 1
            ? documents[0].sourceURL.deletingPathExtension().lastPathComponent
            : "Combined"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        ExportDestinationMemory.remember(fileDestination: destination)

        try? combinedText(documents).write(to: destination, atomically: true, encoding: .utf8)
        return true
    }

    private static func exportRenderedTextImages(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .jpg image of each file's extracted text"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for document in documents {
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            writeJPEGs(for: document.extractedText, named: baseName, in: folder)
        }
        return true
    }

    /// Writes `text` as one `.jpg`, or — since JPEG can't be taller than 65,535 pixels — asks first
    /// whether to split text that would be too tall into several numbered images. Declining skips
    /// the file rather than writing a broken one; a failed write is always reported, never silent.
    /// `autoSplit` is nil for the normal interactive path (ask the user); the debug driver passes
    /// true/false to answer that question itself and to suppress alert dialogs. Returns files written.
    @discardableResult
    static func writeJPEGs(for text: String, named name: String, in folder: URL, autoSplit: Bool? = nil) -> Int {
        let interactive = autoSplit == nil
        let height = TextImageRenderer.imageHeight(for: text)
        if height <= TextImageRenderer.maxJPEGHeight {
            guard let image = TextImageRenderer.renderImage(for: text),
                  JPEGWriter.write(image, to: uniqueURL(in: folder, name: name, ext: "jpg")) else {
                if interactive { showExportFailure("\"\(name)\" couldn't be saved as a .jpg.") }
                return 0
            }
            return 1
        }

        let count = Int((height / TextImageRenderer.maxJPEGHeight).rounded(.up))
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\"\(name)\" is too tall for a single .jpg"
        alert.informativeText = "This text would make an image \(Int(height)) pixels tall, but .jpg files can't be taller than 65,535 pixels. Split it automatically into about \(count) images (\"\(name) (1 of \(count)).jpg\", …), or skip this one. Tip: adding split points yourself lets you choose where it divides."
        alert.addButton(withTitle: "Split Automatically")
        alert.addButton(withTitle: "Skip This File")
        let shouldSplit = autoSplit ?? (alert.runModal() == .alertFirstButtonReturn)
        guard shouldSplit else { return 0 }

        let images = TextImageRenderer.renderImages(for: text)
        var written = 0
        for (index, image) in images.enumerated() {
            let url = uniqueURL(in: folder, name: "\(name) (\(index + 1) of \(images.count))", ext: "jpg")
            if JPEGWriter.write(image, to: url) {
                written += 1
            } else if interactive {
                showExportFailure("Part \(index + 1) of \"\(name)\" couldn't be saved.")
            }
        }
        return written
    }

    private static func showExportFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Export problem"
        alert.informativeText = message
        alert.runModal()
    }

    /// Exports the segments a user has divided one file's text into (via split points inserted in
    /// the preview pane — see `SplitMarker`) as that many separate files in one chosen folder.
    @discardableResult
    static func exportSegments(_ segments: [String], baseName: String, asImage: Bool, directoryHint: URL?) -> Bool {
        guard !segments.isEmpty else { return false }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = asImage
            ? "Choose a folder to save each split-point segment as a .jpg"
            : "Choose a folder to save each split-point segment as a .txt"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: directoryHint)

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for (index, segment) in segments.enumerated() {
                        if asImage {
                writeJPEGs(for: segment, named: "\(baseName) - part \(index + 1)", in: folder)
            } else {
                try? txtContent(segment).write(to: uniqueURL(in: folder, name: "\(baseName) - part \(index + 1)", ext: "txt"), atomically: true, encoding: .utf8)
            }
        }
        return true
    }

    private static func exportPDF(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .pdf of each file's extracted text"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for document in documents {
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            let destination = uniqueURL(in: folder, name: baseName, ext: "pdf")
            TextImageRenderer.renderPDF(for: document.extractedText, to: destination)
        }
        return true
    }

    private static func exportPNG(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .png image of each file's extracted text"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for document in documents {
            guard let image = TextImageRenderer.renderImage(for: document.extractedText) else { continue }
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            let destination = uniqueURL(in: folder, name: baseName, ext: "png")
            PNGWriter.write(image, to: destination)
        }
        return true
    }

    private static func exportRichDocuments(_ documents: [PDFDocumentItem], format: RichDocumentFormat) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .\(format.fileExtension) file per source file"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for document in documents {
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            let destination = uniqueURL(in: folder, name: baseName, ext: format.fileExtension)
            RichDocumentExporter.write(document.extractedText, format: format, to: destination)
        }
        return true
    }

    private static func exportEPUB(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .epub per source file"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for document in documents {
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            let destination = uniqueURL(in: folder, name: baseName, ext: "epub")
            try? EPUBExporter.write(document.extractedText, title: baseName, to: destination)
        }
        return true
    }

    private static func exportOriginalPageImages(_ documents: [PDFDocumentItem]) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to save one .jpg image per PDF page"
        panel.directoryURL = ExportDestinationMemory.directoryURL(fallback: documents.first?.sourceURL.deletingLastPathComponent())

        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        ExportDestinationMemory.remember(folder: folder)

        for document in documents {
            guard let pdf = PDFDocument(url: document.sourceURL) else { continue }
            let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex),
                      let image = PDFPageRasterizer.renderCGImage(for: page, scale: 2.0) else { continue }
                let suffix = pdf.pageCount > 1 ? "_page\(pageIndex + 1)" : ""
                let destination = uniqueURL(in: folder, name: "\(baseName)\(suffix)", ext: "jpg")
                JPEGWriter.write(image, to: destination)
            }
        }
        return true
    }
}
