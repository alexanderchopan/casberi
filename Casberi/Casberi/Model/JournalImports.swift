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
        /// Entries the cap REFUSED — never landed, never looked at (prd §398,
        /// 2026-08-17). Separate from `skipped`, which means "already here":
        /// one is a re-import doing its job and the other is history we
        /// declined to read, and a receipt that folds them together tells
        /// somebody with a fifteen-year journal that the run went fine.
        var dropped = 0
        var failed = false
    }

    /// How many entries one run will land.
    ///
    /// It was **500 across both importers** until 2026-08-17, applied with no
    /// count of what it refused — the silent-truncation class prd §307 found in
    /// the X archive and §309 carried to Instagram, TikTok and Snapchat, in the
    /// two import rooms nobody went back for. A journal is at most an entry a
    /// day, so 500 is thirteen months: anybody who has kept one for longer
    /// imported a fraction of it and read "412 entries in" as the whole thing.
    ///
    /// 5,000 is ~14 years at one a day, and the numbers are the reason a cap
    /// still exists at all rather than being removed: each entry is a regex
    /// pass and an insert, and `ImportCommit`'s chunking is what keeps the main
    /// thread free — the cap bounds the tail, the counting is what makes it
    /// honest.
    static let entryCap = 5_000

    /// Parses a Day One JSON export (the `.json` inside the export zip) —
    /// `{"entries": [...]}` with ISO-8601 dates, markdown text, and tags.
    /// Caps at the newest `entryCap`, and REPORTS what it refused.
    ///
    /// `exportRoot` is the unzipped export FOLDER when the person picked one,
    /// and is
    /// what makes the photographs reachable: Day One files them at
    /// `photos/<md5>.<type>` beside the JSON, and a scoped grant on the `.json`
    /// alone cannot read a sibling directory. Nil (or a folder that isn't
    /// granted) simply yields no pictures and every entry lands exactly as it
    /// did before — the `ImportMedia` contract, which is why this needs no
    /// second code path for the file pick.
    @MainActor
    static func run(data: Data, context: ModelContext,
                    exportRoot: URL? = nil,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else {
            return Summary(failed: true)
        }

        let existing = IngestSupport.existingSourceRefs(context, source: "Day One")

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
        // COUNT THE REFUSAL, don't just apply it. A dropped entry is
        // indistinguishable from one that never existed once the run is over,
        // so this is the only moment it can be said out loud.
        summary.dropped = max(0, dated.count - entryCap)
        var landed: [Thing] = []
        var photoStems: [String: String] = [:]
        for (date, entry) in dated.prefix(entryCap) {
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
            // NOT inserted here (prd §398): the rows go down through
            // `ImportCommit` below, in chunks that each save and then yield.
            // With the cap at `entryCap` an insert-everything-then-save-once
            // run is precisely the frozen main thread §310 exists to prevent.
            landed.append(thing)
            if let stem = photoStem(entry) { photoStems[ref] = stem }
            summary.imported += 1
        }
        // The export's own pictures, before the rows go down so a thumbnail
        // rides the same insert (prd §310's ordering). Inside the scoped grant,
        // which is why this can't be a later heal — there is no second chance
        // at a folder the person has stopped granting.
        if let exportRoot, !photoStems.isEmpty {
            let index = ImportMedia.mediaIndex(in: "photos", under: exportRoot)
            var jobs: [ImportMedia.Job] = []
            for thing in landed {
                guard jobs.count < ImportMedia.perImport,
                      let ref = thing.sourceRef,
                      let stem = photoStems[ref],
                      let file = index[stem] else { continue }
                jobs.append(ImportMedia.Job(ref: ref, file: file))
            }
            ImportMedia.apply(await ImportMedia.decode(jobs), to: landed)
        }
        await finish(&summary, landed: landed, source: "Day One",
                     context: context, progress: progress)
        return summary
    }

    /// The stem of an entry's first photograph — the key `ImportMedia.mediaIndex`
    /// files `photos/` under.
    ///
    /// `md5` is the name Day One uses on disk and `identifier` is the one the
    /// body's `dayone-moment://` placeholder uses; both are tried because the
    /// export's own vintages disagree about which it writes, and a stem that
    /// matches nothing costs one dictionary miss.
    ///
    /// FIRST photograph only: `previewImageData` holds one picture, and an entry
    /// with nine of them still reads as one row.
    static func photoStem(_ entry: [String: Any]) -> String? {
        guard let photos = entry["photos"] as? [[String: Any]] else { return nil }
        for photo in photos {
            if let md5 = photo["md5"] as? String, !md5.isEmpty { return md5 }
            if let id = photo["identifier"] as? String, !id.isEmpty { return id }
        }
        return nil
    }

    /// The shared tail of both importers, CHUNKED since 2026-08-17 (prd §398):
    /// insert, save, index and yield 200 rows at a time, with a failure that is
    /// REPORTED (a swallowed save behind a success screen is fake status).
    ///
    /// It was one insert-all-then-save-once pass, which was correct while both
    /// caps were 500 and became the frozen main thread §310 describes the moment
    /// they went to `entryCap`. `ImportCommit` also carries the Live Activity, so
    /// a long journal import is legible from the lock screen like every other
    /// import in the app.
    ///
    /// A CHUNK IS A COMMIT: a run that dies partway keeps what it landed, and a
    /// re-import fills the rest in — both importers dedupe on `sourceRef`, so
    /// re-importing is already the supported repair.
    @MainActor
    static func finish(_ summary: inout Summary, landed: [Thing], source: String,
                       context: ModelContext,
                       progress: ((Int) -> Void)? = nil) async {
        guard summary.imported > 0 else { return }
        guard await ImportCommit.commit(landed, context: context,
                                        source: source, progress: progress) else {
            summary.failed = true
            summary.imported = 0
            return
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

    /// How many of a journal's rows carry pixels — the probes' one measurement
    /// of the media pass (prd §398).
    ///
    /// It is asked of the whole ROOM rather than of one run's `landed`, because
    /// the question it answers is "did the pictures ever arrive", and a
    /// re-import of an unchanged export lands nothing while the pictures from
    /// the first run are still there. A run that reports `0 imported, 40 with
    /// photos` is healthy; `40 imported, 0 with photos` is a `photos/` folder
    /// that was never reachable, which is the one failure here that is
    /// completely invisible from the receipt.
    @MainActor
    static func thumbnailed(source: String, context: ModelContext) -> Int {
        let rows = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source }))) ?? []
        return rows.filter { $0.isLive && $0.previewImageData != nil }.count
    }

    /// The export's JSON, given the unzipped FOLDER (prd §398).
    ///
    /// Day One writes `Journal.json` for the default journal and `<Name>.json`
    /// for a named one, so the well-known name is tried first and any `.json`
    /// after it — never a guess at what a journal might be called. One level of
    /// nesting is searched too, because unzipping in Files routinely produces a
    /// folder containing a folder.
    ///
    /// Nil is an honest "that isn't a Day One export", which is the sentence the
    /// screen already had for the wrong pick.
    static func findJSON(inFolder folder: URL) -> URL? {
        let manager = FileManager.default
        func json(in dir: URL) -> URL? {
            guard let files = try? manager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return nil }
            let jsons = files.filter { $0.pathExtension.lowercased() == "json" }
            return jsons.first { $0.lastPathComponent == "Journal.json" }
                // Sorted, so a folder holding two journals imports the same one
                // every time rather than whichever the filesystem listed first.
                ?? jsons.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        }
        if let here = json(in: folder) { return here }
        guard let children = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for child in children
        where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let nested = json(in: child) { return nested }
        }
        return nil
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
    static func run(folder: URL, context: ModelContext,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        let existing = IngestSupport.existingSourceRefs(context, source: "Apple Journal")

        // The folder walk + per-entry HTML read happen off the main
        // thread: the export folder often still lives in iCloud Drive, and
        // FileManager/Data(contentsOf:) silently block on the iCloud
        // download for any file they touch, synchronously on the calling
        // thread. Left on @MainActor, a large export freezes the UI and can
        // trip the main-thread watchdog.
        typealias Item = (ref: String, date: Date, title: String, body: String, photo: String?)
        let outcome: (processed: Int, dropped: Int, items: [Item])? =
            await Task.detached(priority: .userInitiated) { () -> (Int, Int, [Item])? in
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
                // The same refusal Day One counts, in the room that needed it
                // more: a Journal export is one HTML page per entry, so a deep
                // one is thousands of files and the old 500 read the newest
                // sixteen months of them (prd §398).
                let dropped = max(0, dated.count - DayOneImport.entryCap)
                let processed = dated.prefix(DayOneImport.entryCap)
                var result: [Item] = []
                for (date, nameTitle, url) in processed {
                    let ref = "journal:\(url.lastPathComponent)"
                    guard !seen.contains(ref) else { continue }
                    guard let data = try? Data(contentsOf: url),
                          let html = String(data: data, encoding: .utf8) else { continue }
                    let body = plainText(fromHTML: html)
                    let title = nameTitle.isEmpty
                        ? (body.isEmpty ? "Journal entry" : DayOneImport.title(from: body))
                        : nameTitle
                    // The entry's own picture, named while its HTML is in hand
                    // (prd §398). Read HERE rather than on the main side because
                    // this is the only place the markup exists — the main actor
                    // sees the stripped text and could not recover an `<img>`
                    // from it if it wanted to.
                    result.append((ref, date, title, body, photoStem(fromHTML: html)))
                    // Two same-named files in one walk (a Resources/ backup
                    // copy) must not both land under one ref — the set
                    // grows as RSSIngest's does (review 2026-07-11).
                    seen.insert(ref)
                }
                return (processed.count, dropped, result)
            }.value

        guard let outcome else { return Summary(failed: true) }

        var summary = Summary()
        summary.skipped = outcome.processed - outcome.items.count
        summary.dropped = outcome.dropped
        var landed: [Thing] = []
        var photoStems: [String: String] = [:]
        for item in outcome.items {
            let thing = Thing(
                kind: .note,
                title: item.title,
                content: item.body,
                source: "Apple Journal",
                capturedAt: item.date,
                sourceRef: item.ref
            )
            // NOT inserted here — see `DayOneImport.finish`. With the cap at
            // `entryCap` this loop can build thousands of rows, and saving them
            // in one transaction is the frozen main thread §310 exists to
            // prevent.
            landed.append(thing)
            if let photo = item.photo { photoStems[item.ref] = photo }
            summary.imported += 1
        }
        // Journal's own pictures live in the `Resources/` folder its export
        // ships beside `Entries/`, and unlike Day One they have always been
        // inside the granted scope — this folder IS the pick. Before the rows go
        // down, so a thumbnail rides the same insert (prd §310's ordering).
        if !photoStems.isEmpty {
            let index = ImportMedia.mediaIndex(in: "Resources", under: folder)
            var jobs: [ImportMedia.Job] = []
            for thing in landed {
                guard jobs.count < ImportMedia.perImport,
                      let ref = thing.sourceRef,
                      let stem = photoStems[ref],
                      let file = index[stem] else { continue }
                jobs.append(ImportMedia.Job(ref: ref, file: file))
            }
            ImportMedia.apply(await ImportMedia.decode(jobs), to: landed)
        }
        await DayOneImport.finish(&summary, landed: landed, source: "Apple Journal",
                                  context: context, progress: progress)
        return summary
    }

    /// The stem of the first `<img>` an entry's HTML points at — the key
    /// `ImportMedia.mediaIndex` files `Resources/` under (prd §398).
    ///
    /// Only the STEM is kept, and that is what makes this tolerant of a
    /// structure Apple has never documented: the `src` may be
    /// `Resources/x.jpeg`, `../Resources/x.jpeg` or anything else Apple decides
    /// tomorrow, and every one of those forms carries the same basename. The
    /// depth of the path is Apple's business; the name is the only part we rely
    /// on.
    ///
    /// FIRST picture only — `previewImageData` holds one, and an entry with
    /// nine still reads as one row. A `data:` URI is refused rather than
    /// treated as a filename: it names no file, and its stem would be a
    /// meaningless slice of base64 that could collide with a real one.
    static func photoStem(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']",
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let whole = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: whole),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: html) else { return nil }
        let src = IngestSupport.decodeHTMLEntities(String(html[captured]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !src.lowercased().hasPrefix("data:") else { return nil }
        let stem = URL(fileURLWithPath: src).deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
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
