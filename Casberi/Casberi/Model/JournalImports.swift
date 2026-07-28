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

        let existing = IngestSupport.existingSourceRefs(context, source: "Day One")
        // Read BEFORE anything lands (delight, 2026-07-28) — the corpus's
        // own reach, for `NoteMoments.checkFloorPushedBack` below.
        let priorFloor = NoteMoments.corpusFloor(context)

        // IngestSupport.isoDate, not a bare ISO8601DateFormatter — Day One
        // stamps both plain and fractional-second forms, and the bare
        // formatter silently dropped every fractional entry (review 2026-07-11).
        let dated: [(date: Date, entry: [String: Any])] = entries.compactMap { entry in
            guard let date = IngestSupport.isoDate(entry["creationDate"]) else { return nil }
            return (date, entry)
        }.sorted { $0.date > $1.date }
        // Entries that exist but none parseable is a FAILED read, not
        // "Nothing new" — a fake success here registers a connected seat
        // for an import that brought nothing (honesty rule, review 2026-07-11).
        guard !dated.isEmpty else { return Summary(failed: true) }

        var summary = Summary()
        var landed: [Thing] = []
        for (date, entry) in dated.prefix(500) {
            // Dedupe BEFORE the markdown cleanup — a re-import of an
            // unchanged export should cost set lookups, not regex passes.
            let id = (entry["uuid"] as? String) ?? "\(date.timeIntervalSince1970)"
            let ref = "dayone:\(id)"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }
            let text = cleanMarkdown(entry["text"] as? String ?? "")
            guard !text.isEmpty else { summary.skipped += 1; continue }

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
            landed.append(thing)
            summary.imported += 1
        }
        finish(&summary, landed: landed, context: context)
        if summary.imported > 0 {
            NoteMoments.checkFloorPushedBack(priorFloor: priorFloor, landed: landed, source: "Day One")
        }
        return summary
    }

    /// The shared tail of both importers: one save whose failure is REPORTED
    /// (a swallowed save with a success screen is fake status), and one
    /// batched Spotlight submission instead of an XPC round-trip per entry.
    @MainActor
    static func finish(_ summary: inout Summary, landed: [Thing], context: ModelContext) {
        guard summary.imported > 0 else { return }
        do {
            try context.save()
            SpotlightIndex.index(landed)
        } catch {
            summary.failed = true
            summary.imported = 0
        }
    }

    /// Day One embeds media as `![](dayone-moment://…)` placeholders — the
    /// media itself stays in the export (said on the screen), so the
    /// placeholders leave the text rather than reading as broken links.
    /// Day One also backslash-escapes markdown-special punctuation (e.g. a
    /// period after a number, so "4.8" doesn't read as an ordered-list
    /// marker) — left alone, those backslashes show up literally ("4\.8").
    private static func cleanMarkdown(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: #"!\[[^\]]*\]\(dayone-moment:[^)]*\)"#,
            with: "", options: .regularExpression)
        let unescaped = unescapeMarkdown(stripped)
        let lines = unescaped.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let joined = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.count > 4000 ? String(joined.prefix(4000)) + "…" : joined
    }

    static func unescapeMarkdown(_ text: String) -> String {
        text.replacingOccurrences(
            of: ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\]^_`{|}~])"##,
            with: "$1", options: .regularExpression)
    }

    /// One-time heal for entries landed before the unescape fix above
    /// (2026-07-28): Day One's dedupe is keyed on `sourceRef`, so a plain
    /// re-import of an unchanged export silently skips every entry already
    /// in the corpus — without this, already-landed titles/content would
    /// carry the literal escaping backslashes ("4\.8") forever.
    @MainActor
    static func healEscapedText(context: ModelContext) -> Int {
        let things = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Day One" }))) ?? []
        var healed = 0
        for t in things {
            let cleaned = unescapeMarkdown(t.content)
            guard cleaned != t.content else { continue }
            t.content = cleaned
            t.title = title(from: cleaned)
            healed += 1
        }
        return healed
    }

    /// The first real line, unburdened of markdown heading marks. The clamp
    /// is IngestSupport.titleLine's — one definition of "titles are one line".
    static func title(from text: String) -> String {
        let first = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .first { !$0.isEmpty } ?? "Journal entry"
        return IngestSupport.titleLine(first)
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
    static func run(folder: URL, context: ModelContext) async -> Summary {
        let existing = IngestSupport.existingSourceRefs(context, source: "Apple Journal")
        // Read BEFORE anything lands (delight, 2026-07-28) — the corpus's
        // own reach, for `NoteMoments.checkFloorPushedBack` below.
        let priorFloor = NoteMoments.corpusFloor(context)

        // The folder walk + per-entry HTML read happen off the main
        // thread: the export folder often still lives in iCloud Drive, and
        // FileManager/Data(contentsOf:) silently block on the iCloud
        // download for any file they touch, synchronously on the calling
        // thread. Left on @MainActor, a large export freezes the UI and can
        // trip the main-thread watchdog.
        let outcome: (processed: Int, items: [(ref: String, date: Date, title: String, body: String)])? =
            await Task.detached(priority: .userInitiated) { () -> (Int, [(ref: String, date: Date, title: String, body: String)])? in
                let fm = FileManager.default
                guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else {
                    return nil
                }
                var files: [URL] = []
                for case let url as URL in walker where url.pathExtension.lowercased() == "html" {
                    files.append(url)
                }
                guard !files.isEmpty else { return nil }

                let dated: [(date: Date, title: String, url: URL)] = files.compactMap { url in
                    guard let (date, title) = parseName(url.deletingPathExtension().lastPathComponent)
                    else { return nil }
                    return (date, title, url)
                }.sorted { $0.date > $1.date }
                // HTML files exist but no filename parsed: the export's
                // shape isn't what we assumed — that's a FAILED read the
                // person should see, not "Nothing new" plus a connected
                // seat (honesty rule, review 2026-07-11).
                guard !dated.isEmpty else { return nil }

                var seen = existing
                let processed = dated.prefix(500)
                var result: [(ref: String, date: Date, title: String, body: String)] = []
                for (date, nameTitle, url) in processed {
                    let ref = "journal:\(url.lastPathComponent)"
                    guard !seen.contains(ref) else { continue }
                    guard let data = try? Data(contentsOf: url),
                          let html = String(data: data, encoding: .utf8) else { continue }
                    let body = plainText(fromHTML: html)
                    let title = nameTitle.isEmpty
                        ? (body.isEmpty ? "Journal entry" : DayOneImport.title(from: body))
                        : nameTitle
                    result.append((ref, date, title, body))
                    // Two same-named files in one walk (a Resources/ backup
                    // copy) must not both land under one ref — the set
                    // grows as RSSIngest's does (review 2026-07-11).
                    seen.insert(ref)
                }
                return (processed.count, result)
            }.value

        guard let outcome else { return Summary(failed: true) }

        var summary = Summary()
        summary.skipped = outcome.processed - outcome.items.count
        var landed: [Thing] = []
        for item in outcome.items {
            let thing = Thing(
                kind: .note,
                title: item.title,
                content: item.body,
                source: "Apple Journal",
                capturedAt: item.date,
                sourceRef: item.ref
            )
            context.insert(thing)
            landed.append(thing)
            summary.imported += 1
        }
        DayOneImport.finish(&summary, landed: landed, context: context)
        if summary.imported > 0 {
            NoteMoments.checkFloorPushedBack(priorFloor: priorFloor, landed: landed, source: "Apple Journal")
        }
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
    /// Entity decoding is IngestSupport.decodeHTMLEntities — the shared
    /// helper decodes numeric refs ("&#8217;", Apple Journal's typographic
    /// punctuation) and &amp; LAST, which the hand map here got wrong twice:
    /// no numeric refs, and dictionary order could double-decode "&amp;lt;"
    /// (review 2026-07-11). Only &apos;/&nbsp; stay local (HTML-only names).
    static func plainText(fromHTML html: String) -> String {
        var s = html.replacingOccurrences(
            of: #"(?is)<(style|script)[^>]*>.*?</\1>"#,
            with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br[^>]*>|</p>|</div>|</h[1-6]>"#,
                                   with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        s = IngestSupport.decodeHTMLEntities(s)
        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        return joined.count > 4000 ? String(joined.prefix(4000)) + "…" : joined
    }
}
