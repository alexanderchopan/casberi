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
    ///
    /// `includeDomains` is the WRITING/PIXELS fork (2026-08-06). For a
    /// screenshot the hostname on screen is the strongest "what is this"
    /// signal, which is why it leads. For a person's own sentences it is the
    /// WEAKEST — the words are right there, and the domain of a link they
    /// pointed at is not what they wrote about. The X room proved it the
    /// expensive way: `XArchiveImport.clean` expands `entities.urls` and never
    /// `entities.media`, so every post with a picture kept its bare
    /// `t.co` shortlink, and that hostname cleared `normalize` (four
    /// characters, three letters, no stoplist entry) and recurred across
    /// thousands of posts — and since `cells` credits each row to its single
    /// most common qualifying term, one `t.co` cell swallowed the room under
    /// the title "What you post about". Quote-tweets added `twitter.com`
    /// beside it. Off, the reading surface is `prose(of:)` — hashtags harvested
    /// first (the one place a person states their own topic outright), then
    /// entities over text with URLs, @mentions and hashtags removed, so a
    /// reply's addressing prefix stops reading as a subject.
    static func terms(in text: String, cap: Int = 6, includeDomains: Bool = true) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<String>()            // lowercased dedupe
        var out: [String] = []
        func add(_ raw: String) {
            guard let term = normalize(raw),
                  seen.insert(term.lowercased()).inserted else { return }
            out.append(term)
        }
        let read: String
        if includeDomains {
            for host in domains(in: trimmed) { add(host) }
            read = trimmed
        } else {
            for tag in hashtags(in: trimmed) { add(tag) }
            read = prose(of: trimmed)
        }
        guard !read.isEmpty else { return Array(out.prefix(cap)) }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = read
        let range = read.startIndex..<read.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]) { tag, r in
            switch tag {
            case .some(.organizationName), .some(.placeName), .some(.personalName):
                add(String(read[r]))
            default:
                break
            }
            return out.count < cap * 4      // gather a few extra; capped on return
        }
        // The subjects themselves, for a writing corpus only — see
        // `subjects(in:)`. Last, so a name the tagger recognised keeps the
        // casing and the multi-word join it came with.
        if !includeDomains {
            for noun in subjects(in: read, cap: cap * 2) { add(noun) }
        }
        return Array(out.prefix(cap))
    }

    /// The ordinary nouns a person's own sentences are ABOUT — the second half
    /// of the writing fork, and the half that makes the map worth drawing.
    ///
    /// **Measured 2026-08-06, and the reason this exists:** `.nameType` names
    /// only PROPER nouns. Over a screenshot library that is the whole signal
    /// (a shot's identity really is the site, the app, the person on screen),
    /// but over somebody's own posts it is almost nothing — a sample of
    /// ordinary tech posts yielded a term for **2 rows in 12**, and
    /// `FeedInsight.topicMap` needs six rows carrying terms before it will draw
    /// at all. So the domains fix earlier the same day traded a wrong map (one
    /// `t.co` cell swallowing the room) for no map, which is not obviously the
    /// better failure: both mean the room never says what it is about. The
    /// same sample read for nouns gives design / layer / dashboard / product /
    /// treemap / problem, which is a portrait.
    ///
    /// Still deterministic and still off the model, so the honesty rule holds:
    /// a label is a word the person actually typed, picked by a part-of-speech
    /// tagger, never a category anything invented.
    ///
    /// Two guards keep it from filling with noise:
    ///   • `genericNouns` — the nouns English uses to build a sentence rather
    ///     than to name a subject ("thing", "way", "someone"). They recur in
    ///     everything, which under `cells`' recurrence rule is exactly what
    ///     makes a term win, so unfiltered they would be the whole map.
    ///   • Inflection folding, so "dashboards" and "dashboard" are one cell
    ///     and not two that each look too small to draw. The lemma is taken
    ///     ONLY when it is a prefix of what was written, which is what makes
    ///     the fold provably a trim of their own word ("systems" → "system")
    ///     rather than a substitution — an irregular ("people" → "person")
    ///     fails that test and keeps the surface form the person typed.
    static func subjects(in text: String, cap: Int = 12) -> [String] {
        guard !text.isEmpty else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, r in
            guard tag == .noun else { return true }
            let surface = String(text[r])
            var term = surface
            if let lemma = tagger.tag(at: r.lowerBound, unit: .word, scheme: .lemma).0?.rawValue,
               lemma.count >= 3, surface.lowercased().hasPrefix(lemma.lowercased()) {
                term = lemma
            }
            guard let clean = normalize(term),
                  !genericNouns.contains(clean.lowercased()),
                  seen.insert(clean.lowercased()).inserted else { return true }
            out.append(clean)
            return out.count < cap
        }
        return out
    }

    /// The hostnames a screenshot's text shows — the single most reliable
    /// "what is this" clue in a screenshot (a browser bar, a share sheet, a
    /// link). Matched against a curated TLD set so a version string ("1.2.3")
    /// or a decimal never reads as a domain; leading "www." stripped, lowercased.
    static func domains(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: domainPattern, options: [.caseInsensitive]) else { return [] }
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

    /// The hostname shape, spelled ONCE (2026-08-06) because two readers need
    /// to agree on it exactly: `domains(in:)` harvests these as terms for a
    /// pixels corpus, and `prose(of:)` removes the very same spans for a
    /// writing one. Spelling it twice is how the two silently drift into a
    /// host that is neither counted nor stripped.
    /// (One line on purpose — `x-selftest.sh` lifts it with `grabline`, which
    /// reads a single line and would otherwise hand the compiler half a regex.)
    static let domainPattern = #"\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:com|org|net|io|co|app|dev|gov|edu|ai|xyz|me|tv|so|gg|fm|to|us|uk|de|jp|fr|ca|in|eu|store|shop|news|social|finance|health)\b"#

    /// The topics a person declared outright. A hashtag is the one place
    /// somebody says what their own post is about, so for a writing corpus it
    /// leads the way a domain leads for a screenshot.
    ///
    /// The `#` is DROPPED from the returned term on purpose: "#WWDC" and a
    /// plain mention of WWDC in the next post are the same subject, and
    /// keeping the mark would file them as two cells that each look too small.
    /// The label still literally appears in the post, which is the honesty rule
    /// this whole type is built on. Three characters minimum, matching
    /// `normalize`, and never mid-token so a URL fragment can't produce one.
    static func hashtags(in text: String) -> [String] {
        let pattern = #"(?<![\w#/])#([A-Za-z][A-Za-z0-9_]{2,39})\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [String] = []
        var seen = Set<String>()
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges > 1 else { continue }
            let word = ns.substring(with: m.range(at: 1))
            if seen.insert(word.lowercased()).inserted { out.append(word) }
        }
        return out
    }

    /// A post's WORDS, with its plumbing removed — what the entity tagger
    /// should read when the corpus is somebody's own writing.
    ///
    /// Four spans go, in this order because the earlier patterns are the more
    /// specific ones: full URLs (a scheme or a `www.`), then bare hosts and
    /// whatever path trails them (`t.co/xyz`, the shortlink an X archive keeps
    /// for every attached picture), then @mentions, then hashtags (already
    /// harvested above — leaving them lets the tagger join a mark to the word
    /// beside it and name something nobody wrote).
    ///
    /// Mentions are the half that fixes the reply prefix: an X reply's
    /// `full_text` opens with the handles it answers, and NLTagger reads those
    /// as people — so a room of replies produced a map of the people you reply
    /// TO, filed under "What you post about". Addressing is not a subject.
    ///
    /// This is the reading surface for `subjects(in:)` as well, and both stages
    /// run over it in that order: the tagger names what it can, then the plain
    /// nouns fill in everything it can't.
    static func prose(of text: String) -> String {
        var out = text
        for pattern in [
            #"\b(?:https?://|www\.)\S+"#,
            domainPattern + #"\S*"#,
            #"(?<![\w])@[A-Za-z0-9_]{1,15}\b"#,
            #"(?<![\w])#[A-Za-z0-9_]+\b"#,
        ] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let ns = out as NSString
            out = re.stringByReplacingMatches(
                in: out, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// The nouns English builds a SENTENCE out of rather than names a subject
    /// with — dropped from the noun stream only (`subjects(in:)`), never from
    /// the entity one, so a company or a place that happens to be spelled like
    /// one of these survives as the name it is.
    ///
    /// They have to go, and the reason is `cells`' own recurrence rule: a term
    /// wins a cell by appearing in the most rows, and "thing" appears in
    /// everything. Unfiltered, a map of somebody's writing is a map of English.
    /// Lemma forms are enough for the regular plurals (`subjects` folds before
    /// it checks) but both are listed where the fold can't reach.
    private static let genericNouns: Set<String> = [
        "thing", "things", "way", "ways", "time", "times", "people", "person",
        "someone", "somebody", "anyone", "anybody", "everyone", "everybody",
        "nobody", "something", "anything", "nothing", "everything", "stuff",
        "guy", "guys", "kind", "sort", "type", "part", "bit", "lot", "lots",
        "day", "days", "week", "weeks", "month", "months", "year", "years",
        "morning", "afternoon", "evening", "night", "moment", "while",
        "place", "case", "point", "fact", "reason", "number", "end", "side",
        "half", "rest", "one", "ones", "everyone's", "take", "sense", "worth",
        "course", "line", "bunch", "couple", "few", "many", "much", "none",
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

    /// Extraction for a batch of rows, OFF the main actor (2026-08-06).
    ///
    /// `terms(in:)` is an `NLTagger` pass per row and it ran on the main actor
    /// because that is where the `Thing` it reads lives — but nothing about
    /// the work needs to be there: it takes a `String` and returns `[String]`,
    /// and both cross an actor boundary freely. Only the FETCH and the write
    /// back onto the model have to stay on main.
    ///
    /// This is the whole post-271 jank fix in one line of structure. A sweep
    /// over a bulk import room is thousands of tagger passes, and on the main
    /// actor every one of them is time the app cannot draw a frame or answer a
    /// scroll — which is what "laggy after 271" was. Off it, the same work is
    /// invisible: the main actor is touched only to read the text out and to
    /// stamp the result back.
    ///
    /// Batched rather than one row at a time so the hop is paid per batch, and
    /// returns a parallel array so the caller can `zip` it back onto the rows
    /// it came from — no `Thing`, and nothing else non-`Sendable`, crosses.
    private nonisolated static func extract(_ texts: [String],
                                            includeDomains: Bool) async -> [[String]] {
        await Task.detached(priority: .utility) {
            texts.map { terms(in: $0, includeDomains: includeDomains) }
        }.value
    }

    /// What a source's topics are read off, for the sweep below (2026-07-31).
    ///
    /// The extraction never cared where text came from — `terms(in:)` reads a
    /// String — but until now only Photos handed it any, so the sweep was
    /// written around OCR. Instagram's captions and comments are the second
    /// corpus worth mapping, and they differ in exactly one way that matters:
    /// their text is present the moment they land, so there is nothing to wait
    /// for.
    private struct TopicSource {
        /// A SET since 2026-08-06, mirroring `FeedInsight.topicMap`'s own
        /// (prd §309 gave the map a kind set and left this switch behind, so
        /// TikTok's map — whose writing spans `.link` captions and `.note`
        /// comments — had no way to get terms at all: `topicSource` answered
        /// nil for it, `healTopics` returned 0, and the card could never
        /// render. Exactly the defect X shipped with, still live in the room
        /// beside it.)
        let kinds: Set<ThingKind>
        /// Whether a row must have been OCR'd before its text can be read.
        /// TRUE for Photos and load-bearing there, not an optimization: topics
        /// come off the OCR `content`, so a shot whose OCR hasn't run yet has
        /// EMPTY content. Without the gate the sweep would extract [] from that
        /// emptiness and stamp `topicsAt` — and since the stamp blocks
        /// re-extraction, the words OCR writes moments later would never become
        /// topics. FALSE for imported text, which arrives whole.
        let needsOCR: Bool
        /// Whether a hostname counts as a topic here — see `terms(in:)`. TRUE
        /// for a corpus of PIXELS (the domain on screen is what the shot is),
        /// FALSE for a corpus of WRITING (the domain of a link somebody
        /// pointed at is not what they wrote about). It also decides which
        /// rows the one-time `restamp` below re-reads: only the writing rooms
        /// changed rules, so only they have anything to repair.
        let includeDomains: Bool
    }

    private static func topicSource(_ source: String) -> TopicSource? {
        switch source {
        case "Photos":    return TopicSource(kinds: [.screenshot], needsOCR: true, includeDomains: true)
        case "Instagram": return TopicSource(kinds: [.note], needsOCR: false, includeDomains: false)
        // X is Instagram's shape exactly (2026-08-05): the room's `.note` half
        // is the person's own posts and replies, its `.link` half is posts
        // somebody else wrote, and a map over both would be titled a lie.
        //
        // `XArchiveImportScreen` has called `healTopics(source: "X")` since the
        // seat shipped and this switch answered nil for it every time, so the
        // call did nothing and the map it was meant to fill never had terms —
        // one of three separate places X was missing from a registry the other
        // import rooms are in.
        case "X":         return TopicSource(kinds: [.note], needsOCR: false, includeDomains: false)
        // TikTok, 2026-08-06 — the room prd §309 gave a map and this switch
        // never learned about. Its writing spans TWO kinds (a video's caption
        // rides the `.link` row, a comment is a `.note`), which is why the
        // kind above became a set; `FeedInsight.topicMap` narrows to the
        // person's OWN rows by tag, so a saved stranger's video getting terms
        // here costs nothing and reaches no card.
        case "TikTok":    return TopicSource(kinds: [.link, .note], needsOCR: false, includeDomains: false)
        // A connected folder is Photos' shape wearing a different kind
        // (2026-08-02): `FilesIngest.heal` OCRs the folder's images into
        // `content` exactly the way the screenshot heal does. `needsOCR` is
        // doubly load-bearing here — beyond the Photos race it guards
        // against, `ocrAt != nil` is also what scopes the sweep to IMAGE
        // files: a text file or PDF lands with a byte-preview `content` and
        // no `ocrAt`, and reading topics off those bytes would put file
        // previews in a map titled as what your images say.
        case "Files":     return TopicSource(kinds: [.file], needsOCR: true, includeDomains: true)
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
        let rows = Array(((try? context.fetch(descriptor)) ?? [])
            .filter { spec.kinds.contains($0.kind) && !Corpus.isImportReceipt($0) }
            .prefix(limit))

        // Read the text on main, tag it off main, stamp the result back on
        // main (2026-08-06 — see `extract`).
        let extracted = await extract(rows.map(\.content),
                                      includeDomains: spec.includeDomains)
        var changed = 0
        let now = Date.now
        // Per-ROW liveness AFTER the await, not the array filter that ran
        // before it (COROLLARY 6): a bridge heal can tombstone a row while the
        // tagger runs, and this is the first read of a stored property since.
        for (thing, topics) in zip(rows, extracted) where thing.isLive {
            thing.ocrTopics = topics
            thing.topicsAt = now
            changed += 1
        }
        if changed > 0 { _ = context.saveHonestly() }
        // Only once the NEW rows are drained — a fresh import is what somebody
        // is looking at, and a repair that starves it would be the wrong
        // trade. The repair then gets every later pass to itself.
        guard changed == 0 else { return changed }
        return await restamp(source: source, spec: spec, context: context)
    }

    /// When the term rules last changed. A row stamped before this was read
    /// under the old ones and says so by its `topicsAt` alone — no new `Thing`
    /// field, and therefore no CloudKit Production deploy, which is the whole
    /// reason it is a date rather than a version number.
    ///
    /// 2026-08-06 (morning): domains stopped counting as topics for a writing
    /// corpus, hashtags started, and @mentions stopped.
    ///
    /// 2026-08-06 (afternoon): ordinary nouns started counting — see
    /// `subjects(in:)`. Bumped past the morning's own value, which is the
    /// point of the two entries: a row stamped BETWEEN them was read under
    /// rules that were already fixed and still wrong, and a date that only
    /// moved once a day could not tell those rows apart from good ones. That
    /// is not hypothetical — the morning's epoch was midnight, so every row
    /// the app restamped in the hours after it shipped was excluded from its
    /// own repair.
    ///
    /// The next rules change bumps this and NOTHING else: `restamp`'s
    /// done-flag is keyed by the epoch, so moving the date re-arms the repair
    /// by construction. It used to be a bare `topics.restamp.<source>`, which
    /// meant a device that had already run one repair would refuse the next
    /// one forever — the fix landing in the same commit as the rules it fixes,
    /// and doing nothing.
    static let termsEpoch = Date(timeIntervalSince1970: 1_786_030_000)

    /// Re-read a writing room's rows that were stamped under the old rules.
    ///
    /// This exists because `topicsAt` is a "we looked" mark and nothing else:
    /// the normal sweep skips any row that has one, so a rules change reaches
    /// only rows imported AFTER it — which for a bulk import room, where
    /// everything landed on one afternoon, means it reaches nothing at all and
    /// the broken map stays broken forever. (The `recheckContractsOnce` /
    /// `kindRecheck.7702` shape, one directory over.)
    ///
    /// It drains the room in ONE pass rather than `limit` rows at a time, and
    /// chunks with a yield instead (`ImportCommit`'s shape). At the sweep's
    /// bound a repaired room would take some forty foregrounds to come right,
    /// which for the person who reported the broken map reads as the fix not
    /// having landed. This is a once-per-install cost, and it declares itself
    /// done through a UserDefaults flag rather than by re-running the query —
    /// so the steady state afterwards is a `bool(forKey:)` and NO fetch, which
    /// is the cheap-empty-fetch property the sweep above is careful to keep.
    ///
    /// `chunk` is what keeps the main actor answering, and since 2026-08-06 it
    /// bounds the SAVE rather than the tagging: extraction hops off the actor
    /// per batch (`extract`), so what is left here is a batch of assignments
    /// and one `saveHonestly()`, which re-emits the feed's `@Query` and is now
    /// the expensive half. Each chunk still saves, so a run interrupted
    /// halfway keeps what it repaired and the next pass resumes from the same
    /// query.
    @MainActor
    private static func restamp(source: String, spec: TopicSource,
                                context: ModelContext, chunk: Int = 100) async -> Int {
        // Only the writing rooms changed rules. Photos and Files read exactly
        // what they always read, so re-walking them would be work with a
        // guaranteed-identical result.
        guard !spec.includeDomains else { return 0 }
        // Keyed by the EPOCH, not just the source — so a rules change re-arms
        // the repair on a device that already ran the previous one. See
        // `termsEpoch`; this is the half of that bug that no bumped date could
        // have fixed on its own.
        let key = "topics.restamp.\(source).\(Int(termsEpoch.timeIntervalSince1970))"
        guard !UserDefaults.standard.bool(forKey: key) else { return 0 }

        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source && $0.topicsAt != nil })
        let stale = ((try? context.fetch(descriptor)) ?? [])
            .filter { spec.kinds.contains($0.kind) && !Corpus.isImportReceipt($0) }
            .filter { ($0.topicsAt ?? Date.distantPast) < termsEpoch }
        guard !stale.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return 0
        }

        var changed = 0
        let now = Date.now
        for start in stride(from: 0, to: stale.count, by: chunk) {
            let batch = Array(stale[start..<min(start + chunk, stale.count)])
            // The tagger runs off the main actor; only the read out and the
            // stamp back happen here (2026-08-06 — see `extract`). Before
            // this, a room of several thousand posts spent every one of its
            // `NLTagger` passes on the actor the app draws with, in chunks of
            // a hundred, which is a visible freeze per chunk for as many
            // chunks as the room is long.
            let texts = batch.map(\.content)
            let extracted = await extract(texts, includeDomains: spec.includeDomains)
            // Per-ROW liveness, not a re-filter of the array (COROLLARY 6).
            // This list is held across the extraction hop and every yield
            // below, and a bridge heal can tombstone a row inside one;
            // checking at the point of the read is the same guarantee,
            // evaluated later than any bulk filter could be.
            for (thing, topics) in zip(batch, extracted) where thing.isLive {
                thing.ocrTopics = topics
                thing.topicsAt = now
                changed += 1
            }
            // One save per batch, then hand the actor back. The save is now
            // the expensive half of this loop — it re-emits the feed's own
            // `@Query` — so the yield is what keeps a scroll answering
            // between them rather than a nicety.
            _ = context.saveHonestly()
            await Task.yield()
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }
}
