import Foundation

/// Reads a picked file's bytes off the main thread. Every import screen
/// (ChatGPT/Claude/Gemini/Kindle/Day One/Bookmarks/the Casberi export) picks
/// a file via `.fileImporter` and then reads it with `Data(contentsOf:)`.
/// When that file is an iCloud placeholder — not yet downloaded to this
/// device, which is the common case for a big export saved straight into
/// Files — `Data(contentsOf:)` silently triggers the download and blocks
/// the calling thread until it finishes (seconds to minutes). On the main
/// thread that reads as a freeze, and long enough it trips iOS's
/// main-thread watchdog and kills the app outright. Running the read on a
/// detached task keeps the UI responsive while the download completes.
/// Callers still own the security-scoped access window
/// (`startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource`).
enum SecurityScopedFileReader {
    static func readData(at url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }
}
