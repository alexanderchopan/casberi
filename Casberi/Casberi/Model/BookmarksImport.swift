import Foundation
import SwiftData

/// Bookmarks import — Safari and Chrome, one screen (prd §224). Neither
/// offers a live read (Safari has no bookmarks API at all; Chrome's export
/// never includes its separate Reading List store), so the sanctioned way
/// in is the browser's own export — and it's the SAME file for both: the
/// Netscape Bookmark File Format both Safari's "Export Bookmarks…" (Mac)
/// and Chrome's "Export bookmarks" write. One parser, one catalog offer.
///
/// Safari's Reading List rides along for free: it's stored as a special
/// "Reading List" folder inside the same Bookmarks.plist Safari exports
/// from, so it just shows up as a folder here — no separate integration.
/// Chrome's Reading List is a genuinely different store Chrome's own export
/// never includes, so a Chrome file simply has no such folder; the split
/// degrades silently to "All bookmarks" only, never a dead promise.
enum BookmarksImport {

    struct Entry {
        let title: String
        let url: String
        let date: Date
        let tags: [String]
        let isReadingList: Bool
    }

    struct Parsed {
        var entries: [Entry]
        var readingListCount: Int { entries.filter(\.isReadingList).count }
    }

    struct Summary {
        var imported = 0
        var skipped = 0
        var failed = false
    }

    /// Root container names Chrome/Safari wrap real folders in — never
    /// meaningful user taxonomy, so they're excluded from tags. "Reading
    /// List" stays OUT of this list on purpose: it's a real folder worth
    /// keeping as a tag too, even on an item landed via "All bookmarks".
    private static let structuralFolders: Set<String> = [
        "bookmarks bar", "bookmarks menu", "other bookmarks",
        "mobile bookmarks", "favorites bar", "favorites", "bookmarks",
    ]

    /// Parses a Netscape Bookmark File Format export (`.html`) — tolerant
    /// line-by-line walk of the standard pretty-printed shape both browsers
    /// write (one tag per line, folders as `<H3>` opening a nested `<DL>`).
    /// An unparseable line is skipped, never guessed at. nil when the file
    /// doesn't carry the format's own signature at all.
    static func parse(data: Data) -> Parsed? {
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              html.contains("NETSCAPE-Bookmark-file") else { return nil }

        var stack: [String] = []
        var pendingFolder: String?
        var entries: [Entry] = []

        for line in html.components(separatedBy: .newlines) {
            if let name = folderName(line) {
                pendingFolder = name
                continue
            }
            if line.contains("<DL>") {
                stack.append(pendingFolder ?? "")
                pendingFolder = nil
                continue
            }
            if line.contains("</DL>") {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            if let entry = bookmark(line, folders: stack) {
                entries.append(entry)
            }
        }
        return Parsed(entries: entries)
    }

    /// `<DT><H3 …>Name</H3>` → "Name", entity-decoded.
    private static func folderName(_ line: String) -> String? {
        guard let r = line.range(of: #"<H3[^>]*>[^<]*</H3>"#, options: .regularExpression)
        else { return nil }
        let inner = line[r]
            .replacingOccurrences(of: #"<H3[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "</H3>", with: "")
        return IngestSupport.decodeHTMLEntities(inner)
    }

    /// `<DT><A HREF="…" ADD_DATE="…">Title</A>` → an Entry, tags from the
    /// live folder stack (structural containers filtered out).
    private static func bookmark(_ line: String, folders: [String]) -> Entry? {
        guard let hrefRange = line.range(of: #"HREF="[^"]*""#, options: .regularExpression),
              let titleRange = line.range(of: #"<A[^>]*>[^<]*</A>"#, options: .regularExpression)
        else { return nil }
        let href = line[hrefRange].dropFirst(6).dropLast()
        guard href.hasPrefix("http://") || href.hasPrefix("https://") else { return nil }

        let titleRaw = line[titleRange]
            .replacingOccurrences(of: #"<A[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "</A>", with: "")
        let title = IngestSupport.decodeHTMLEntities(titleRaw)

        var addDate = Date()
        if let dateRange = line.range(of: #"ADD_DATE="\d+""#, options: .regularExpression),
           let seconds = Double(line[dateRange].dropFirst(10).dropLast()) {
            addDate = Date(timeIntervalSince1970: seconds)
        }

        let realFolders = folders.filter { !$0.isEmpty }
        let isReadingList = realFolders.contains { $0.caseInsensitiveCompare("Reading List") == .orderedSame }
        let tags = realFolders.filter { !structuralFolders.contains($0.lowercased()) }
        let url = String(href)
        return Entry(title: title.isEmpty ? url : title, url: url,
                     date: addDate, tags: tags, isReadingList: isReadingList)
    }

    /// Lands the person's chosen scope (Reading List only, or everything).
    /// Dedupe on the URL itself — re-importing, or importing both scopes
    /// from the same file across two visits, never doubles a row.
    @MainActor
    static func land(_ chosen: [Entry], context: ModelContext) -> Summary {
        var existing = IngestSupport.existingSourceRefs(context, source: "Bookmarks")
        var summary = Summary()
        var landed: [Thing] = []
        for entry in chosen.prefix(2000) {
            let ref = "bookmark:\(entry.url)"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(entry.title),
                content: entry.url,
                source: "Bookmarks",
                capturedAt: entry.date,
                tags: entry.tags,
                sourceRef: ref
            )
            context.insert(thing)
            landed.append(thing)
            existing.insert(ref)
            summary.imported += 1
        }
        guard summary.imported > 0 else { return summary }
        do {
            try context.save()
            SpotlightIndex.index(landed)
        } catch {
            summary.failed = true
            summary.imported = 0
        }
        return summary
    }
}
