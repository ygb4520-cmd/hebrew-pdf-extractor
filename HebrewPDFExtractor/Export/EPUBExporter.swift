import Foundation

enum EPUBExportError: LocalizedError {
    case zipFailed
    var errorDescription: String? { "Couldn't package the EPUB file." }
}

/// Exports plain text as a minimal, valid EPUB3 file: one content document containing the text
/// (marked `dir="rtl"` for correct Hebrew reading order), plus the metadata/navigation files
/// EPUB3 requires. Built by hand rather than via a library — an EPUB is just a specifically-
/// structured zip archive, and macOS ships `/usr/bin/zip`, so no bundled dependency is needed
/// (mirrors `EPUBImporter`'s use of `/usr/bin/unzip`).
enum EPUBExporter {
    static func write(_ text: String, title: String, to destinationURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oebpsDir = tempDir.appendingPathComponent("OEBPS", isDirectory: true)
        let metaInfDir = tempDir.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: oebpsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metaInfDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let escapedTitle = xmlEscape(title)
        let bodyParagraphs = text
            .components(separatedBy: "\n")
            .map { "<p>\(xmlEscape($0))</p>" }
            .joined(separator: "\n")

        try "application/epub+zip".write(to: tempDir.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try containerXML.write(to: metaInfDir.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(UUID().uuidString)</dc:identifier>
            <dc:title>\(escapedTitle)</dc:title>
            <dc:language>he</dc:language>
          </metadata>
          <manifest>
            <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
          </manifest>
          <spine>
            <itemref idref="content"/>
          </spine>
        </package>
        """
        try opf.write(to: oebpsDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        let navXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" dir="rtl" lang="he">
        <head><title>\(escapedTitle)</title></head>
        <body>
          <nav epub:type="toc">
            <ol>
              <li><a href="content.xhtml">\(escapedTitle)</a></li>
            </ol>
          </nav>
        </body>
        </html>
        """
        try navXHTML.write(to: oebpsDir.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)

        let contentXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" dir="rtl" lang="he">
        <head><title>\(escapedTitle)</title></head>
        <body dir="rtl">
        \(bodyParagraphs)
        </body>
        </html>
        """
        try contentXHTML.write(to: oebpsDir.appendingPathComponent("content.xhtml"), atomically: true, encoding: .utf8)

        try zip(tempDir: tempDir, to: destinationURL)
    }

    /// The EPUB spec requires `mimetype` to be the archive's first entry and stored uncompressed
    /// — done here as two `zip` invocations: one that stores just `mimetype` (`-0`), then one
    /// that appends everything else (`-g`) with normal compression.
    private static func zip(tempDir: URL, to destinationURL: URL) throws {
        try? FileManager.default.removeItem(at: destinationURL)

        try runZip(arguments: ["-X", "-0", destinationURL.path, "mimetype"], workingDirectory: tempDir)
        try runZip(arguments: ["-X", "-r", "-g", destinationURL.path, "META-INF", "OEBPS"], workingDirectory: tempDir)
    }

    private static func runZip(arguments: [String], workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workingDirectory
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EPUBExportError.zipFailed }
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
