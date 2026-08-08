import Foundation

/// WHAT POINTS AT THIS — the corpus's incoming edges, for any thing
/// (2026-08-08, prd §340).
///
/// The app has computed graph edges since Obsidian landed, but each one lived
/// on exactly one surface and answered exactly one question: `NoteLinks`
/// resolved wikilinks for Obsidian notes and nothing else, `CrossSourceEcho`
/// found a link you had written about but reported only the EARLIEST one, as a
/// dead spec-table row you could not tap. So the edges existed and the shelf
/// that would make them useful did not.
///
/// This is that shelf's model: given a thing and a bounded corpus, which OTHER
/// things point at it, and why. Two edge kinds, and the shortlist is short on
/// purpose — see "What is deliberately not an edge" below.
///
/// ## Pure and Foundation-only, like `AddressConnections` and for the same reason
///
/// The failure mode here is a WRONG EDGE, which renders perfectly: a shelf
/// saying "your March note links here" over a note that does not is the §83
/// fake status, on the surface where the person is deciding whether to trust
/// what the app tells them about their own corpus. Nothing here touches
/// SwiftData; `ThingLinksSource.swift` holds the `Thing`-reading half and is
/// not compiled by `scripts/thinglinks-selftest.sh`, which feeds this file
/// cases whose answers are known.
///
/// Values, never model references — a `Tie` carries the target's id as a
/// `String` and its display fields as plain values, so nothing this returns can
/// be tombstoned under an open sheet (CLAUDE.md's liveness corollaries 1-6 are
/// avoided by construction here rather than guarded against).
///
/// ## What is deliberately NOT an edge
///
/// Every rule here is EXACT — a link somebody wrote, or a title somebody typed
/// inside `[[…]]`. The tempting additions are all inferences, and each was
/// considered and refused for the reason `CrossSourceEcho` already records: a
/// wrong "this points at that" reads as a bug, and a missed one costs nothing.
///
///   • **Shared tag** is not a pointer. Two things carrying `Onchain` are
///     co-members of a cluster, which the Themes treemap already draws over the
///     whole corpus; restating it per-thing would also need an unbounded scan
///     to count honestly (`$0.tags.contains` is the SwiftData predicate that
///     crashes at runtime — see CLAUDE.md — so a tag count is a Swift-side walk
///     of everything).
///   • **Semantic neighbours** are not pointers either, and already have their
///     own shelf: `RelatedThings.neighbours` sits directly below this one and
///     is explicitly the weaker claim ("related", floor 0.5). Promoting a
///     cosine into "points at this" is exactly the claim `RelatedThings`
///     refuses to make about `keptBefore`.
///   • **Same author, same source, same day** — co-occurrence, not reference.
///
/// ## The one accepted imprecision
///
/// A mention is matched on the CANONICAL link (host + path, scheme and
/// tracking parameters off), so a post that wrote `https://example.com/a` is
/// found for a thing saved as `www.example.com/a?utm_source=x` — the `www.`
/// prefix and the tracking parameter are exactly what canonicalization drops.
/// That canonicalization is what makes the edge findable at all, and it is
/// `RelatedThings.canonicalLink`'s own rule, forwarded here so there is one
/// implementation rather than two that drift.
enum ThingLinks {

    /// How many ties one shelf may show. A vault's hub note has hundreds of
    /// backlinks and a sheet is not a graph view — the reasoning
    /// `NoteLinks.backlinks` shipped this cap under before it retired into
    /// this file, kept at its number.
    static let cap = 20

    /// Why one thing points at another. Ordered strongest-first, which is also
    /// the order the shelf draws: a `[[wikilink]]` is a person deliberately
    /// naming another note, a mention is a person having written the URL down
    /// somewhere. Both are facts; the first is more deliberate.
    enum Edge: Int, Comparable, Sendable {
        /// Its text names this thing's title inside `[[…]]`.
        case wikilink = 0
        /// Its text carries this thing's link.
        case mention = 1

        static func < (a: Edge, b: Edge) -> Bool { a.rawValue < b.rawValue }

        /// The shelf's own words for this edge, and the agent tool's — one
        /// wording, so a sentence the model writes about a tie matches the row
        /// the person can see. Deliberately a verb phrase about the OTHER
        /// thing, since the row already leads with that thing's title.
        var reason: String {
            switch self {
            case .wikilink: return "links here"
            case .mention:  return "mentions this"
            }
        }
    }

    /// The minimal shape of a thing, as both callers can build it: the sheet's
    /// adapter from a live `Thing`, and the agent's snapshot. Everything needed
    /// to compute an edge and to draw the row it produces, and nothing else.
    struct Node: Sendable {
        let id: String
        let title: String
        let source: String
        let when: Date
        /// The canonical link this thing IS, when it is a link. nil for a note,
        /// a screenshot, a transaction.
        let link: String?
        /// The canonical links this thing's own text NAMES — its outgoing link
        /// edges. Built by `canonicalLinks(in:)` so the extraction rule is
        /// tested in one place.
        let mentions: [String]
        /// The note titles this thing's text names inside `[[…]]`. Only
        /// Obsidian populates this today; nothing here is scoped to Obsidian,
        /// so a second vault-shaped bridge inherits the edge for free.
        let wikilinks: [String]
        /// The bridge's own id for this row. Two rows sharing one is a DEDUPE
        /// BUG (`-corpusDupeProbe`'s territory) and must never be surfaced as a
        /// relationship — `RelatedThings.keptBefore`'s rule, for the same
        /// reason: it would launder our own defect into a feature.
        let sourceRef: String?

        init(id: String, title: String, source: String, when: Date,
             link: String? = nil, mentions: [String] = [],
             wikilinks: [String] = [], sourceRef: String? = nil) {
            self.id = id
            self.title = title
            self.source = source
            self.when = when
            self.link = link
            self.mentions = mentions
            self.wikilinks = wikilinks
            self.sourceRef = sourceRef
        }
    }

    /// One incoming edge, flattened for display.
    struct Tie: Sendable, Equatable {
        let id: String
        let title: String
        let source: String
        let when: Date
        let edge: Edge

        static func == (a: Tie, b: Tie) -> Bool {
            a.id == b.id && a.edge == b.edge
        }

        /// "your March note · links here · Obsidian" is three fields; this is
        /// the middle one plus the source, which is what the shelf's secondary
        /// line shows and what the agent tool prints.
        var detail: String { "\(edge.reason) · \(source)" }
    }

    // MARK: - The read

    /// Which things in `corpus` point at `target`, strongest edge first and
    /// newest first within an edge.
    ///
    /// A node is reported ONCE, under its strongest edge — a note that both
    /// wikilinks a thing and pastes its URL is one relationship, and two rows
    /// for it would read as two notes.
    static func pointingAt(_ target: Node, in corpus: [Node],
                           limit: Int = cap) -> [Tie] {
        var best: [String: Tie] = [:]

        func offer(_ node: Node, _ edge: Edge) {
            guard node.id != target.id else { return }
            // Our own bookkeeping, not the person's second thing.
            if let a = node.sourceRef, let b = target.sourceRef, a == b { return }
            if let existing = best[node.id], existing.edge <= edge { return }
            best[node.id] = Tie(id: node.id, title: node.title,
                                source: node.source, when: node.when, edge: edge)
        }

        // A title too short to be distinctive can't carry a claim — a vault
        // holding a note called "a" would otherwise match every `[[a]]` in it.
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if title.count >= 2 {
            for node in corpus where node.wikilinks.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title
            }) {
                offer(node, .wikilink)
            }
        }

        // A bare host names a site, not a thing: a post saying "example.com" is
        // not a post about this article. `CrossSourceEcho.writtenAbout`'s bar,
        // kept — a path, and enough of one to be about something.
        if let link = target.link, link.count >= 12, hasPath(link) {
            for node in corpus where node.mentions.contains(link) {
                // A thing that IS this link is a second copy of it, which
                // `RelatedThings.keptBefore` reports in its own words above
                // this shelf. Reporting it here too would say one fact twice.
                guard node.link != link else { continue }
                offer(node, .mention)
            }
        }

        return best.values
            .sorted {
                $0.edge != $1.edge ? $0.edge < $1.edge : $0.when > $1.when
            }
            .prefix(limit)
            .map { $0 }
    }

    /// True when a canonical link carries a path beyond the bare host.
    /// `canonicalLink` has already dropped the scheme, so the first `/` is the
    /// host boundary.
    static func hasPath(_ canonical: String) -> Bool {
        guard let slash = canonical.firstIndex(of: "/") else { return false }
        return canonical.index(after: slash) < canonical.endIndex
    }

    // MARK: - Extraction

    /// The canonical links a body of text names.
    ///
    /// Early-out on `http` before anything else: most things in a corpus carry
    /// no URL at all, and this runs over every row of a 2,000-thing snapshot on
    /// the main actor at composer-open time — the foreground-jank class this
    /// codebase already pays for elsewhere.
    ///
    /// A hand-rolled scan rather than `NSDataDetector`: the detector is far
    /// more thorough (it finds bare `example.com`, which we deliberately do not
    /// want) and costs an order of magnitude more per call. What is wanted here
    /// is exactly the URLs somebody actually wrote out.
    static func canonicalLinks(in text: String) -> [String] {
        guard text.contains("http") else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        var rest = Substring(text)
        while let start = rest.range(of: "http://") ?? rest.range(of: "https://") {
            let tail = rest[start.lowerBound...]
            let end = tail.firstIndex(where: { $0.isWhitespace || $0 == "\"" || $0 == "<" })
                ?? tail.endIndex
            let raw = String(tail[..<end])
            if let canonical = canonicalLink(raw), seen.insert(canonical).inserted {
                out.append(canonical)
            }
            rest = tail[end...]
        }
        return out
    }

    /// Tracking parameters that make one link look like two. Conservative: a
    /// query string is often load-bearing (a video timestamp, a search), so
    /// only the parameters that exist purely to attribute a click come off.
    ///
    /// Moved here from `RelatedThings` (2026-08-08) so the canonical form has
    /// ONE definition. `RelatedThings.canonicalLink(_ thing:)` forwards to the
    /// function below — two canonicalizers would drift, and then "you kept this
    /// before" and "mentions this" would disagree about whether two saves of
    /// one page are the same page, for a reason invisible from either file.
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref", "ref_src",
        "s", "si", "spm", "_branch_match_id",
    ]

    /// A link reduced so two saves of one page match: scheme and `www.`
    /// dropped, host lowercased, tracking parameters removed and the rest
    /// sorted, trailing slash gone. nil when this isn't an http(s) link.
    ///
    /// Trailing sentence punctuation comes off first — a URL written inside a
    /// sentence ends up with the full stop attached, and `example.com/a.` would
    /// otherwise never match `example.com/a`.
    static func canonicalLink(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = candidate.last, ".,;:!?)]}'\"".contains(last) {
            candidate.removeLast()
        }
        guard candidate.hasPrefix("http://") || candidate.hasPrefix("https://"),
              var comps = URLComponents(string: candidate),
              var host = comps.host?.lowercased()
        else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let kept = (comps.queryItems ?? []).filter { !trackingParams.contains($0.name.lowercased()) }
        comps.queryItems = kept.isEmpty ? nil : kept.sorted { $0.name < $1.name }
        var path = comps.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let query = comps.query.map { "?\($0)" } ?? ""
        return host + path + query
    }
}
