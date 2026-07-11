import Foundation
import SwiftData

/// The journal importers (prd 55) — Day One and Apple Journal, both the
/// ChatGPT pattern: neither offers a live read (Day One has no public API;
/// Apple Journal has no read API at all), so the person's own export is the
/// sanctioned way in. One-time, deduped on stable refs, re-runs add only
/// what's new. Apple Notes completes the group as the share-path explainer —
/// no importer here because Apple offers no export for Notes at all.
enum DayOneImport {

    struct Summary {
        var imported = 0
        var skipped = 0
        var failed = false
    }

    /// Parses a Day One JSON export (the `.json` inside the export zip) —
    /// `{"entries": [...]}` with ISO-8601 dates, markdown text, and tags.
    /// Caps at the newest 500, the ChatGPT precedent.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else {
            return Summary(failed: true)
        }

        let existing = IngestSupport.existingSourceRefs(context)
        let iso = ISO8601DateFormatter()

        let dated: [(date: Date, entry: [String: Any])] = entries.compactMap { entry in
            guard let stamp = entry["creationDate"] as? String,
                  let date = iso.date(from: stamp) else { return nil }
            return (date, entry)
        }.sorted { $0.date > $1.date }

        var summary = Summary()
        for (date, entry) in dated.prefix(500) {
            let text = cleanMarkdown(entry["text"] as? String ?? "")
            guard !text.isEmpty else { summary.skipped += 1; continue }
            let id = (entry["uuid"] as? String) ?? "\(date.timeIntervalSince1970)"
            let ref = "dayone:\(id)"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }

            let thing = Thing(
                kind: .note,
                title: title(from: text),
                content: text,
                source: "Day One",
                capturedAt: date,
                tags: (entry["tags"] as? [String]) ?? [],
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 { try? context.save() }
        return summary
    }

    /// Day One embeds media as `![](dayone-moment://…)` placeholders — the
    /// media itself stays in the export (said on the screen), so the
    /// placeholders leave the text rather than reading as broken links.
    private static func cleanMarkdown(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: #"!\[[^\]]*\]\(dayone-moment:[^)]*\)"#,
            with: "", options: .regularExpression)
        let lines = stripped.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let joined = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.count > 4000 ? String(joined.prefix(4000)) + "…" : joined
    }

    /// The first real line, unburdened of markdown heading marks.
    static func title(from text: String) -> String {
        let first = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .first { !$0.isEmpty } ?? "Journal entry"
        return first.count > 80 ? String(first.prefix(80)) + "…" : first
    }
}

/// Apple Journal's export (`AppleJournalEntries.zip`, iOS 18+) unzips to an
/// Entries/ folder of per-entry HTML plus a Resources/ media folder. The
/// structure is Apple's and undocumented, so the parse is deliberately
/// tolerant: the filename carries the date and title (`YYYY-MM-DD_Title.html`),
/// the body is read as stripped text, and anything unrecognizable is skipped,
/// never guessed at.
enum JournalImport {

    typealias Summary = DayOneImport.Summary

    /// Walks a picked folder (the unzipped export) for entry HTML files.
    /// Call within the folder's security scope.
    @MainActor
    static func run(folder: URL, context: ModelContext) -> Summary {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return Summary(failed: true)
        }
        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "html" {
            files.append(url)
        }
        guard !files.isEmpty else { return Summary(failed: true) }

        let existing = IngestSupport.existingSourceRefs(context)
        var summary = Summary()

        let dated: [(date: Date, title: String, url: URL)] = files.compactMap { url in
            guard let (date, title) = parseName(url.deletingPathExtension().lastPathComponent)
            else { return nil }
            return (date, title, url)
        }.sorted { $0.date > $1.date }

        for (date, nameTitle, url) in dated.prefix(500) {
            let ref = "journal:\(url.lastPathComponent)"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }
            guard let data = try? Data(contentsOf: url),
                  let html = String(data: data, encoding: .utf8) else {
                summary.skipped += 1; continue
            }
            let body = plainText(fromHTML: html)
            let title = nameTitle.isEmpty
                ? (body.isEmpty ? "Journal entry" : DayOneImport.title(from: body))
                : nameTitle
            let thing = Thing(
                kind: .note,
                title: title,
                content: body,
                source: "Apple Journal",
                capturedAt: date,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 { try? context.save() }
        return summary
    }

    /// `2026-07-04_Morning walk` → (July 4 2026 noon, "Morning walk").
    /// Noon, not midnight: the export drops the time, and midnight puts the
    /// entry on the wrong day for anyone west of its zone.
    private static func parseName(_ name: String) -> (Date, String)? {
        let parts = name.split(separator: "_", maxSplits: 1)
        guard let datePart = parts.first else { return nil }
        let comps = datePart.split(separator: "-").compactMap { Int($0) }
        guard comps.count == 3, comps[0] > 1970 else { return nil }
        var dc = DateComponents()
        dc.year = comps[0]; dc.month = comps[1]; dc.day = comps[2]; dc.hour = 12
        guard let date = Calendar.current.date(from: dc) else { return nil }
        let title = parts.count > 1 ? String(parts[1]) : ""
        return (date, title.trimmingCharacters(in: .whitespaces))
    }

    /// Tags and entities out, line structure kept — tolerant by design.
    static func plainText(fromHTML html: String) -> String {
        var s = html.replacingOccurrences(
            of: #"(?is)<(style|script)[^>]*>.*?</\1>"#,
            with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br[^>]*>|</p>|</div>|</h[1-6]>"#,
                                   with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                               "&#39;": "'", "&apos;": "'", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        return joined.count > 4000 ? String(joined.prefix(4000)) + "…" : joined
    }
}
