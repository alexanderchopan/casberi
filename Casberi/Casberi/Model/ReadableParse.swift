import Foundation

/// Reading a web page's own words out of its HTML — the whole extractor, in
/// one Foundation-only file (prd §645 pass 5, 2026-09-08).
///
/// **EXTRACTED FROM `LinkTitle` SO A HARNESS CAN DRIVE IT.** These functions
/// were `private` inside a file that imports SwiftData and reaches `Thing`,
/// `OEmbed` and `ProductMeta`, so nothing could compile them and every
/// assertion about them was a claim. Since §645 pass 1 their output is DRAWN
/// on the thing sheet rather than merely indexed, and pass 5 changed the two
/// constants that bound it — which is exactly when "we believe it extracts
/// prose" stops being good enough. `scripts/readable-body-selftest.sh`
/// compiles this file WHOLE AND UNMODIFIED.
///
/// No behaviour moved with it. `LinkTitle` still owns the fetch, the receipts
/// entry and the enrichment pass; this owns only the parse.
enum ReadableParse {

    /// How many `<p>` blocks a page's content region may contribute, and how
    /// long the flattened result may be (prd §645 pass 5, 2026-09-08 — was 6
    /// and 1,200).
    ///
    /// **THESE ARE THE READING BOUNDS NOW, AND 6/1,200 WERE MEASURED TO BE THE
    /// WRONG WAY ROUND.** They were written when this text existed only to be
    /// searched — the old doc said so: *"Capped so it stays a lede, not a
    /// mirror of the page."* §645 pass 1 put that same text on the sheet at
    /// `reading20`, and fifteen real pages through this exact code said the
    /// lede bound was not merely too small but actively harmful:
    ///
    /// **Leading chrome sits in exactly the slots a six-paragraph limit
    /// spends.** A Verge article's first six `<p>`s are "News Close News Posts
    /// from this topic will be added to your daily email digest…" three times
    /// over, a share row and a byline; its actual first sentence is paragraph
    /// NINE. A GitHub repo page spends paragraphs 0 and 1 on "Fork 10.8k Star
    /// 70.3k" and reaches the README's prose at 2. So the small limit does not
    /// protect the excerpt from chrome — it guarantees the excerpt is nothing
    /// BUT chrome, because the article never gets a slot to displace it. That
    /// is the inverse of what `docs/reading-spec.md` A.5 predicted, and it is
    /// why the measurement it insisted on came first.
    ///
    /// The trailing risk is real and much smaller: on a page with no
    /// `<main>`/`<article>` marker `contentRegion` returns the whole body, so
    /// the last paragraphs can be footer ("This is a link post by…", a sponsor
    /// line — two of twelve on the one measured example). A stray line after
    /// the piece is a visibly finished article; a piece cut at 1,200 characters
    /// mid-sentence is not.
    ///
    /// **The character cap is the real bound; the paragraph limit only stops
    /// the regex loop running away on a pathological page.** 200 is chosen so
    /// that it CANNOT bind first — the harness's own fixture proves it, and 60
    /// failed that fixture: a page written in short paragraphs hit the
    /// paragraph limit at ~4,500 characters and was cut by the wrong bound.
    /// No article measured for §645 reached even 40. The cap itself is
    /// `ReadableBody.limit`, which lives in `Shared/` because the share
    /// extension clamps the same field in another process and the two must not
    /// diverge — see that constant.
    ///
    /// Read by `fetchReadable`, `fetchPage` and `-linkBodyProbe`, so they move
    /// together by construction.
    static let maxParagraphs = 200

    /// The `<title>` element's text, decoded and capped — nil when absent/empty.
    static func parseTitle(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: [.caseInsensitive]),
              let openEnd = html.range(of: ">", options: [],
                                       range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: [.caseInsensitive],
                                     range: openEnd.upperBound..<html.endIndex)
        else { return nil }
        let raw = html[openEnd.upperBound..<close.lowerBound]
        let title = ReadableParse.decodeEntities(String(raw))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return title.count > 120 ? String(title.prefix(120)) + "…" : title
    }

    /// The meta description plus the content region's paragraphs, de-duped,
    /// one paragraph per line-pair — what lands in `Thing.enrichedText` and,
    /// since §645 pass 1, what the thing sheet DRAWS. Bounded by `maxParagraphs` and `bodyLimit`;
    /// nil when nothing readable comes back.
    ///
    /// It said "capped so it stays a lede, not a mirror of the page" until
    /// 2026-09-08. That was the right bound for text nobody could read — see
    /// the constants for the fifteen pages that retired it.
    static func parseReadable(in html: String) -> String? {
        var pieces: [Piece] = []
        // The meta description lives in <head>, so read it off the whole page;
        // paragraphs come from the main CONTENT region (below), which skips the
        // header/nav chrome that would otherwise lead the excerpt with menu
        // scraps ("About · Search · Log in"). Narrowing generalizes across
        // sites, not just one (review 2026-07-15).
        if let desc = ReadableParse.metaDescription(in: html) { pieces.append(.paragraph(desc)) }
        pieces.append(contentsOf: ReadableParse.blocks(in: ReadableParse.contentRegion(html), limit: maxParagraphs))

        // De-dupe (a description often repeats the first paragraph). Each
        // piece is flattened to one line, and the pieces are joined with a
        // BLANK LINE, not a space (prd §645 amendment 4): the page's own
        // paragraphs are the breaks the sheet draws, and joining them with a
        // space was the wall of text. See `ReadableBody.separator`.
        //
        // A HEADING is held until a paragraph follows it (§645 amendment 5):
        // a section title with no section under it is chrome — "Related
        // stories", "Most popular" — or the last title on a page whose body
        // the cap will cut anyway. Headings take no 24-character floor (a
        // real one is "The bottom line") and no prose test (none carries a
        // full stop); their own bound is 3…120 characters.
        var seen = Set<String>()
        var lines: [String] = []
        var pendingHeading: String?
        for piece in pieces {
            switch piece {
            case .heading(let level, let raw):
                let text = ReadableParse.flattened(raw)
                guard text.count >= 3, text.count <= 120 else { continue }
                pendingHeading = String(repeating: "#", count: level) + " " + text
            case .paragraph(let raw):
                let text = ReadableParse.flattened(raw)
                guard text.count > 24, seen.insert(text).inserted else { continue }   // skip nav scraps
                if let heading = pendingHeading { lines.append(heading); pendingHeading = nil }
                lines.append(text)
            }
        }
        let text = lines
            .joined(separator: ReadableBody.separator)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return nil }
        return text.count > ReadableBody.limit
            ? String(text.prefix(ReadableBody.limit)) + "…" : text
    }

    /// One block of the content region, in document order.
    ///
    /// A heading's `level` is the level it takes IN THE BODY: an `<h2>` is 1
    /// and an `<h3>` is 2, because the page's `<h1>` is the title and is not
    /// part of the text. `NoteProse` indents by level, so a section title at
    /// 1 sits flush with its paragraphs the way it does on the page.
    enum Piece: Equatable {
        case heading(level: Int, String)
        case paragraph(String)
    }

    /// One piece's text on one line.
    static func flattened(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The HTML from the first main-content marker onward — `<main>`,
    /// `<article>`, or a well-known content container id — so paragraph
    /// extraction skips the header/nav that precedes it. The whole page when no
    /// marker is found (a plain page's body IS its content).
    static func contentRegion(_ html: String) -> String {
        for marker in ["<main", "<article", "id=\"mw-content-text\"",
                       "id=\"bodyContent\"", "id=\"content\"", "role=\"main\""] {
            if let r = html.range(of: marker, options: .caseInsensitive) {
                return String(html[r.lowerBound...])
            }
        }
        return html
    }

    /// The page's `<meta name="description">` / `og:description`, decoded.
    static func metaDescription(in html: String) -> String? {
        for pattern in [
            "<meta[^>]+(?:name|property)=[\"'](?:og:)?description[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:name|property)=[\"'](?:og:)?description[\"']",
        ] {
            if let m = ReadableParse.firstCapture(pattern, in: html) {
                let d = ReadableParse.decodeEntities(m).trimmingCharacters(in: .whitespacesAndNewlines)
                if !d.isEmpty { return d }
            }
        }
        return nil
    }

    /// Text inside the first `<p>` blocks, inner tags stripped and entities
    /// decoded — a cheap readability pass, no DOM. Headings dropped; see
    /// `blocks(in:limit:)`, which this reads through.
    static func paragraphs(in html: String, limit: Int) -> [String] {
        blocks(in: html, limit: limit).compactMap {
            if case .paragraph(let text) = $0 { return text } else { return nil }
        }
    }

    /// The content region's `<p>`, `<h2>` and `<h3>` blocks in document order,
    /// inner tags stripped and entities decoded — a cheap readability pass, no
    /// DOM. Scripts/styles are dropped first so an inline `<script>` can't leak
    /// code into the excerpt. `limit` bounds the PARAGRAPHS; headings ride
    /// free, because a page has few and the cap is the real bound.
    ///
    /// Section titles joined the walk in §645 amendment 5: a long explainer
    /// has five of them, and with only its `<p>`s taken it read as one
    /// unsigned stretch even after amendment 4 gave it paragraphs.
    static func blocks(in html: String, limit: Int) -> [Piece] {
        let cleaned = html
            .replacingOccurrences(of: "<script[^>]*>.*?</script>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[^>]*>.*?</style>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
        guard let re = try? NSRegularExpression(
            pattern: "<(p|h2|h3)\\b[^>]*>(.*?)</\\1\\s*>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = cleaned as NSString
        var out: [Piece] = []
        var paragraphs = 0
        for match in re.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 2 else { continue }
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let inner = ns.substring(with: match.range(at: 2))
            let stripped = inner
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            let text = ReadableParse.decodeEntities(stripped)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if tag != "p" {
                out.append(.heading(level: tag == "h2" ? 1 : 2, text))
                continue
            }
            // Keep prose, drop chrome: a real paragraph carries a sentence
            // (a period), while nav/menu `<p>`s ("About · Search · Log in") run
            // long without one — those would only add noise to the index.
            let isProse = text.contains(". ") || text.hasSuffix(".")
            if isProse { out.append(.paragraph(text)); paragraphs += 1 }
            if paragraphs >= limit { break }
        }
        return out
    }

    /// First capture group of `pattern` in `html`, case-insensitive.
    static func firstCapture(_ pattern: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// One decoder for every ingest path (moved to IngestSupport 2026-07-10;
    /// it also handles numeric references now).
    static func decodeEntities(_ s: String) -> String {
        IngestSupport.decodeHTMLEntities(s)
    }
}
