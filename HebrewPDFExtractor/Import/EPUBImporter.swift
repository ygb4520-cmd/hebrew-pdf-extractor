import AppKit
import Foundation

enum EPUBImportError: LocalizedError {
    case unzipFailed
    case missingContainer
    case missingRootFile
    case missingOPF

    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "Couldn't unpack this EPUB file."
        case .missingContainer: return "This EPUB is missing its META-INF/container.xml."
        case .missingRootFile: return "Couldn't find the EPUB's package file reference."
        case .missingOPF: return "Couldn't find or read the EPUB's package (.opf) file."
        }
    }
}

/// Imports EPUB files without any bundled dependency: an EPUB is just a zip archive of XHTML
/// files plus an OPF package manifest, and macOS ships `/usr/bin/unzip` — so this shells out to
/// that (rather than bundling a zip-reading library) to extract the archive, then uses
/// `XMLParser` (built into Foundation) to find the spine's reading order, and
/// `NSAttributedString`'s native HTML reader to pull the text out of each chapter file in order.
enum EPUBImporter {
    static func importText(from url: URL) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try unzip(url, to: tempDir)

        let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
        guard let containerParser = XMLParser(contentsOf: containerURL) else {
            throw EPUBImportError.missingContainer
        }
        let containerDelegate = ContainerXMLDelegate()
        containerParser.delegate = containerDelegate
        containerParser.parse()

        guard let rootFilePath = containerDelegate.rootFilePath else {
            throw EPUBImportError.missingRootFile
        }

        let opfURL = tempDir.appendingPathComponent(rootFilePath)
        guard let opfParser = XMLParser(contentsOf: opfURL) else {
            throw EPUBImportError.missingOPF
        }
        let opfDelegate = OPFDelegate()
        opfParser.delegate = opfDelegate
        opfParser.parse()

        let opfDirectory = opfURL.deletingLastPathComponent()
        var chapters: [String] = []
        for idref in opfDelegate.spineOrder {
            guard let href = opfDelegate.manifestHrefsByID[idref] else { continue }
            let chapterURL = opfDirectory.appendingPathComponent(href)
            guard let attributedString = try? NSAttributedString(
                url: chapterURL,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            ) else { continue }
            let text = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { chapters.append(text) }
        }

        return chapters.joined(separator: "\n\n")
    }

    private static func unzip(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", source.path, "-d", destination.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EPUBImportError.unzipFailed }
    }
}

/// Finds the OPF package file's path from `META-INF/container.xml`'s `<rootfile full-path="...">`.
private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var rootFilePath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile" {
            rootFilePath = attributeDict["full-path"]
        }
    }
}

/// Reads the OPF package's manifest (item id -> href) and spine (ordered list of idrefs) — the
/// spine order is the book's actual reading order, which is what matters here.
private final class OPFDelegate: NSObject, XMLParserDelegate {
    var manifestHrefsByID: [String: String] = [:]
    var spineOrder: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifestHrefsByID[id] = href
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineOrder.append(idref)
            }
        default:
            break
        }
    }
}
