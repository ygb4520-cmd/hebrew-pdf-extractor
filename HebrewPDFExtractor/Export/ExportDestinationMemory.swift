import Foundation

/// Remembers the last folder/location used for any export, so every save/open panel defaults
/// there next time instead of always defaulting to "next to the source file." The panel still
/// lets you pick a different location for any individual export — picking one just updates what's
/// remembered for next time, it doesn't lock you in.
enum ExportDestinationMemory {
    private static let key = "lastExportDirectoryPath"

    static var lastDirectory: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: key) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: key)
        }
    }

    /// Convenience for panels: remembered folder if there is one, else the given fallback
    /// (typically the source file's own folder).
    static func directoryURL(fallback: URL?) -> URL? {
        lastDirectory ?? fallback
    }

    /// Records where a folder-picking panel (`NSOpenPanel` in directory mode) landed.
    static func remember(folder: URL) {
        lastDirectory = folder
    }

    /// Records where a single-file save panel (`NSSavePanel`) landed, using its containing folder.
    static func remember(fileDestination: URL) {
        lastDirectory = fileDestination.deletingLastPathComponent()
    }
}
