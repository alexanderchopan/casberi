import Foundation
import NaturalLanguage
import SwiftData

/// What a screenshot library is ABOUT, derived from OCR text — the cells the
/// Photos feed's treemap counts (2026-07-30, replacing the generic "Your
/// capture year" heatmap, which only ever answered WHEN you shot). A
/// screenshot's whole value is the text in its pixels, so the honest portrait
/// is the terms that recur across the library: the sites you screenshot, the
/// apps, the people, the places.
///
/// Deterministic and off the model (the honesty rule, `FeedInsight`'s doctrine):
/// every cell label is a phrase that LITERALLY appears in a screenshot — a
/// domain the shot shows, or an entity NLTagger names in the OCR — never a
/// category a model invented. Two stages, split so the second is a pure,
/// harness-testable function:
///   • `terms(in:)` reads the salient terms off ONE screenshot's OCR text.
///     Run once at heal time and stored on `Thing.ocrTopics`, so the render
///     path never touches NLTagger (a few ms per shot × the whole library
///     would be a per-paint disaster).
///   • `cells(perShot:)` turns the stored per-shot term lists into ranked
///     treemap cells — global term frequency, keep only terms that RECUR,
///     credit each shot to its most common qualifying term. Pure arithmetic.
///
/// **The name is historical (2026-07-31).** Both stages take text and know
/// nothing about pixels, and the sweep now runs over Instagram's imported
/// captions and comments as well — "what you write about", the same treemap
/// the Photos room leads with, over a person's own words instead of their
/// screenshots. The type kept its name rather than churning every reference
/// to it; `healTopics(source:)` is where the per-source difference lives.
enum ScreenshotTopics {

    // MARK: - Extraction (heal-time, per screenshot)

    /// The salient terms/names in one screenshot's OCR text, most-identifying
    /// first, capped. Domains first (the strongest "what site/app is this"
    /// signal), then NLTagger's organizations / places / people. UI chrome and
    /// bare numbers are dropped — a treemap of "Settings", "Cancel", "9:41" is
    /// noise, not a portrait.
    static func terms(in text: String, cap: Int = 6) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<String>()            // lowercased dedupe
        var out: [String] = []
        func add(_ raw: String) {
            guard let term = normalize(raw),
                  seen.insert(term.lowercased()).inserted else { return }
            out.append(term)
        }
        for host in domains(in: trimmed) { add(host) }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = trimmed
        let range = trimmed.startIndex..<trimmed.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]) { tag, r in
            switch tag {
            case .some(.organizationName), .some(.placeName), .some(.personalName):
                add(String(trimmed[r]))
            default:
                break
            }
            return out.count < cap * 4      // gather a few extra; capped on return
        }
        return Array(out.prefix(cap))
    }

    /// The hostnames a screenshot's text shows — the single most reliable
    /// "what is this" clue in a screenshot (a browser bar, a share sheet, a
    /// link). Matched against a curated TLD set so a version string ("1.2.3")
    /// or a decimal never reads as a domain; leading "www." stripped, lowercased.
    static func domains(in text: String) -> [String] {
        let pattern = #"\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:com|org|net|io|co|app|dev|gov|edu|ai|xyz|me|tv|so|gg|fm|to|us|uk|de|jp|fr|ca|in|eu|store|shop|news|social|finance|health)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let lower = text.lowercased()
        let ns = lower as NSString
        var hosts: [String] = []
        var seen = Set<String>()
        for m in re.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            var host = ns.substring(with: m.range)
            if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
            if seen.insert(host).inserted { hosts.append(host) }
        }
        return hosts
    }

    /// UI chrome, units, and time words that name no topic — dropped from the
    /// entity stream (a domain is never in here, so a real ".com" always
    /// survives). Lowercased; conservative on purpose, so brands stay.
    private static let stop: Set<String> = [
        "settings", "search", "cancel", "done", "back", "next", "menu", "more",
        "notifications", "notification", "messages", "message", "battery",
        "wifi", "bluetooth", "airplane", "today", "yesterday", "tomorrow",
        "http", "https", "www", "untitled", "screenshot", "screenshots",
        "screen", "iphone", "ipad", "am", "pm", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday", "sunday",
    ]

    /// A candidate term cleaned for grouping, or nil to drop it: 3–40 chars,
    /// at least three letters (kills "9:41", "100%", "OK"), not on the stoplist.
    /// Casing is preserved for display — NLTagger returns "Amazon", a domain is
    /// already lowercased.
    private static func normalize(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n.,:;\"'()[]{}"))
        guard t.count >= 3, t.count <= 40 else { return nil }
        guard t.filter({ $0.isLetter }).count >= 3 else { return nil }
        guard !stop.contains(t.lowercased()) else { return nil }
        return t
    }

    // MARK: - Aggregation (render-time, pure)

    /// Rank the treemap cells from the per-screenshot term lists. A term is a
    /// topic only if it RECURS — one screenshot isn't a cluster — so `freq`
    /// counts the number of screenshots each term appears in (once per shot),
    /// and a term needs `minTermShots`. Each screenshot is then credited to the
    /// single most common qualifying term it carries (ties broken by name, for
    /// determinism), so it lands in exactly one cell and the counts sum to the
    /// screenshots actually covered. Largest cells first, capped at `maxCells`.
    static func cells(perShot: [[String]], minTermShots: Int = 2,
                      maxCells: Int = 6) -> [(label: String, count: Int)] {
        var freq: [String: Int] = [:]           // key = lowercased
        var display: [String: String] = [:]
        for terms in perShot {
            var once = Set<String>()
            for t in terms {
                let key = t.lowercased()
                guard once.insert(key).inserted else { continue }
                freq[key, default: 0] += 1
                if display[key] == nil { display[key] = t }
            }
        }
        var bucket: [String: Int] = [:]
        for terms in perShot {
            let qualifying = terms.map { $0.lowercased() }.filter { (freq[$0] ?? 0) >= minTermShots }
            guard let best = qualifying.max(by: { a, b in
                freq[a]! != freq[b]! ? freq[a]! < freq[b]!
                                     : (display[a] ?? a) > (display[b] ?? b)   // tie → earlier name wins
            }) else { continue }
            bucket[best, default: 0] += 1
        }
        return bucket
            .sorted { $0.value != $1.value ? $0.value > $1.value
                                           : (display[$0.key] ?? $0.key) < (display[$1.key] ?? $1.key) }
            .prefix(maxCells)
            .map { (display[$0.key] ?? $0.key, $0.value) }
    }

    // MARK: - Backfill sweep

    /// Which sources have a topics sweep in flight — a concurrent foreground
    /// refresh must not double-walk (mirrors `ScreenshotIngest.healing`). Keyed
    /// by source, not a single flag: Photos and Instagram sweep independently
    /// and a shared flag would make whichever ran second silently do nothing.
    @MainActor private static var sweeping: Set<String> = []

    /// What a source's topics are read off, for the sweep below (2026-07-31).
    ///
    /// The extraction never cared where text came from — `terms(in:)` reads a
    /// String — but until now only Photos handed it any, so the sweep was
    /// written around OCR. Instagram's captions and comments are the second
    /// corpus worth mapping, and they differ in exactly one way that matters:
    /// their text is present the moment they land, so there is nothing to wait
    /// for.
    private struct TopicSource {
        let kind: ThingKind
        /// Whether a row must have been OCR'd before its text can be read.
        /// TRUE for Photos and load-bearing there, not an optimization: topics
        /// come off the OCR `content`, so a shot whose OCR hasn't run yet has
        /// EMPTY content. Without the gate the sweep would extract [] from that
        /// emptiness and stamp `topicsAt` — and since the stamp blocks
        /// re-extraction, the words OCR writes moments later would never become
        /// topics. FALSE for imported text, which arrives whole.
        let needsOCR: Bool
    }

    private static func topicSource(_ source: String) -> TopicSource? {
        switch source {
        case "Photos":    return TopicSource(kind: .screenshot, needsOCR: true)
        case "Instagram": return TopicSource(kind: .note, needsOCR: false)
        // A connected folder is Photos' shape wearing a different kind
        // (2026-08-02): `FilesIngest.heal` OCRs the folder's images into
        // `content` exactly the way the screenshot heal does. `needsOCR` is
        // doubly load-bearing here — beyond the Photos race it guards
        // against, `ocrAt != nil` is also what scopes the sweep to IMAGE
        // files: a text file or PDF lands with a byte-preview `content` and
        // no `ocrAt`, and reading topics off those bytes would put file
        // previews in a map titled as what your images say.
        case "Files":     return TopicSource(kind: .file, needsOCR: true)
        default:          return nil
        }
    }

    /// Extract `ocrTopics` for a source's rows that don't have them yet — the
    /// standalone counterpart to `ScreenshotIngest.heal`, deliberately NOT
    /// folded into it: heal walks PHAssets (thumbnails, re-OCR), which is why
    /// it's throttled and skips already-healed rows; topics need only the
    /// `content` already stored, so this reads it straight from the store with
    /// no Photos-library round-trip. `topicsAt` marks the attempt (even a
    /// term-less row), so a completed corpus makes this a cheap empty fetch.
    /// Bounded per pass so a large first backfill spreads over a few opens.
    @MainActor
    static func healTopics(source: String = "Photos", context: ModelContext,
                           limit: Int = 80) async -> Int {
        guard let spec = topicSource(source), !sweeping.contains(source) else { return 0 }
        sweeping.insert(source)
        defer { sweeping.remove(source) }

        let descriptor: FetchDescriptor<Thing> = spec.needsOCR
            ? FetchDescriptor(predicate: #Predicate {
                $0.source == source && $0.topicsAt == nil && $0.ocrAt != nil })
            : FetchDescriptor(predicate: #Predicate {
                $0.source == source && $0.topicsAt == nil })
        // Kind filter runs in memory — #Predicate can't compare Codable enums.
        // The import receipt is excluded with it: it's the app's own row about
        // an import, and reading "312 saved · 1,204 comments" for topics would
        // put the app's voice in a map of the person's words.
        let rows = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.kind == spec.kind && !Corpus.isImportReceipt($0) }
            .prefix(limit)
        guard !rows.isEmpty else { return 0 }

        var changed = 0
        let now = Date.now
        for thing in rows where thing.isLive {
            thing.ocrTopics = terms(in: thing.content)
            thing.topicsAt = now
            changed += 1
        }
        if changed > 0 { _ = context.saveHonestly() }
        return changed
    }
}
