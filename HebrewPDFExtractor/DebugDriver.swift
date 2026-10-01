import AppKit
import Foundation

extension Notification.Name {
    static let debugSelectDocument = Notification.Name("HebrewDebugSelectDocument")
}

/// Opt-in debug mode (modelled on the Catan app's DebugDriver). Launch with `HEBREW_DEBUG_DRIVER`
/// set to a scratch directory and the real app runs normally, but also:
///  - writes `status.txt` (documents, settings, preview text, exports, log) and `snapshot.png` (the
///    window's own rendered content) into that directory about twice a second, and
///  - executes commands written one per line to `command.txt` (consumed and deleted when applied).
/// Everything is in-process, so no Accessibility or Screen Recording permission is needed. Exports go
/// to `<dir>/exports`, never the user's remembered export folder, and never prompt. Inert unless the
/// environment variable is set.
@MainActor
final class DebugDriver {
    static var shared: DebugDriver?

    static func startIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["HEBREW_DEBUG_DRIVER"] else { return }
        shared = DebugDriver(directory: URL(fileURLWithPath: dir))
    }

    private let directory: URL
    private var exportsDirectory: URL { directory.appendingPathComponent("exports") }
    private weak var coordinator: ExtractionCoordinator?
    private var selectedIndex: Int?
    private var log: [String] = []
    private var busy = false
    private var lastSnapshot = Date.distantPast
    private var timer: Timer?

    private init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        note("driver started")
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func attach(_ coordinator: ExtractionCoordinator) {
        self.coordinator = coordinator
        note("attached to coordinator")
    }

    private func note(_ message: String) {
        log.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(message)")
        if log.count > 40 { log.removeFirst(log.count - 40) }
    }

    private func tick() {
        guard let coordinator else { return }
        let commandURL = directory.appendingPathComponent("command.txt")
        if !busy, let text = try? String(contentsOf: commandURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: commandURL)
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            busy = true
            Task {
                for line in lines { await run(line, coordinator: coordinator) }
                busy = false
                writeStatus(coordinator)
                writeSnapshot()
            }
        }
        writeStatus(coordinator)
        if Date().timeIntervalSince(lastSnapshot) > 2 { writeSnapshot() }
    }

    // MARK: Commands

    private func run(_ line: String, coordinator: ExtractionCoordinator) async {
        note("> \(line)")
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1] : ""
        switch name {
        case "add":
            coordinator.addDocuments(at: [URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)])
        case "select":
            if let index = Int(arg), coordinator.documents.indices.contains(index) {
                selectedIndex = index
                NotificationCenter.default.post(name: .debugSelectDocument, object: coordinator.documents[index].id)
            } else { note("select: bad index") }
        case "extract":
            await coordinator.processAll()
            if selectedIndex == nil, !coordinator.documents.isEmpty {
                selectedIndex = 0
                NotificationCenter.default.post(name: .debugSelectDocument, object: coordinator.documents[0].id)
            }
        case "hebrewonly":
            coordinator.settings.hebrewOnlyOCR = (arg.lowercased() == "on")
        case "maxchars":
            coordinator.settings.maxCharactersPerLine = Int(arg) ?? 0
        case "split":
            // split <line>: insert a split marker as its own line after that (1-based) line.
            if let doc = selectedDocument(coordinator), let lineNumber = Int(arg) {
                var lines = doc.extractedText.components(separatedBy: "\n")
                lines.insert(SplitMarker.line, at: min(max(lineNumber, 0), lines.count))
                doc.extractedText = lines.joined(separator: "\n")
                doc.isManuallyEdited = true
            } else { note("split: need a selected document and a line number") }
        case "exportjpg":
            for doc in coordinator.documents where doc.status == .completed {
                let base = doc.sourceURL.deletingPathExtension().lastPathComponent
                let n = TextExporter.writeJPEGs(for: doc.extractedText, named: base, in: exportsDirectory, autoSplit: true)
                note("exportjpg \(base): wrote \(n) file(s)")
            }
        case "exportsegmentsjpg", "exportsegmentstxt":
            if let doc = selectedDocument(coordinator) {
                let base = doc.sourceURL.deletingPathExtension().lastPathComponent
                for (i, seg) in SplitMarker.segments(in: doc.extractedText).enumerated() {
                    let fileName = "\(base) - part \(i + 1)"
                    if name == "exportsegmentsjpg" {
                        let n = TextExporter.writeJPEGs(for: seg, named: fileName, in: exportsDirectory, autoSplit: true)
                        note("segment \(i + 1): wrote \(n) jpg(s)")
                    } else {
                        try? seg.write(to: exportsDirectory.appendingPathComponent(fileName + ".txt"), atomically: true, encoding: .utf8)
                        note("segment \(i + 1): wrote txt")
                    }
                }
            }
        case "exportpdf":
            for doc in coordinator.documents where doc.status == .completed {
                let base = doc.sourceURL.deletingPathExtension().lastPathComponent
                let ok = TextImageRenderer.renderPDF(for: doc.extractedText, to: exportsDirectory.appendingPathComponent(base + ".pdf"))
                note("exportpdf \(base): \(ok ? "ok" : "FAILED")")
            }
        case "shot":
            writeSnapshot()
        case "quit":
            NSApp.terminate(nil)
        default:
            note("unknown command: \(name)")
        }
    }

    private func selectedDocument(_ coordinator: ExtractionCoordinator) -> PDFDocumentItem? {
        guard let i = selectedIndex, coordinator.documents.indices.contains(i) else { return nil }
        return coordinator.documents[i]
    }

    // MARK: Output

    private func writeStatus(_ coordinator: ExtractionCoordinator) {
        var out = "busy: \(busy)\nprocessing: \(coordinator.isProcessing)\n"
        out += "settings: maxCharactersPerLine=\(coordinator.settings.maxCharactersPerLine) hebrewOnlyOCR=\(coordinator.settings.hebrewOnlyOCR)\n"
        out += "documents (\(coordinator.documents.count)):\n"
        for (i, doc) in coordinator.documents.enumerated() {
            out += "  [\(i)]\(i == selectedIndex ? "*" : " ") \(doc.displayName) — \(doc.status.label), \(doc.extractedText.count) chars, edited: \(doc.isManuallyEdited)\n"
        }
        if let doc = selectedDocument(coordinator) {
            let segments = SplitMarker.segments(in: doc.extractedText)
            out += "selected: \(doc.displayName); segments: \(doc.extractedText.contains(SplitMarker.line) ? segments.count : 0)\n"
            out += "--- first 12 lines of preview text ---\n"
            out += doc.extractedText.components(separatedBy: "\n").prefix(12).joined(separator: "\n") + "\n"
        }
        let exported = (try? FileManager.default.contentsOfDirectory(atPath: exportsDirectory.path))?.sorted() ?? []
        out += "--- exports (\(exported.count)) in \(exportsDirectory.path) ---\n" + exported.joined(separator: "\n") + "\n"
        out += "--- log ---\n" + log.suffix(15).joined(separator: "\n") + "\n"
        out += "--- commands: add <path> | select <i> | extract | hebrewonly on|off | maxchars <n> | split <afterLine> | exportjpg | exportsegmentsjpg | exportsegmentstxt | exportpdf | shot | quit ---\n"
        try? out.write(to: directory.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    }

    private func writeSnapshot() {
        lastSnapshot = Date()
        guard let view = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent("snapshot.png"), options: .atomic)
        }
    }
}
