import Foundation
import SwiftData

/// A pasted URL saves instantly with the URL as its face; this fetches the
/// page's real <title> right after and renames the thing — the link lands
/// named, not naked. Best-effort: offline or titleless pages keep the URL.
enum LinkTitle {

    /// Fetches the page title (5s cap, first 64KB — titles live in <head>).
    /// The lightweight path used by the `-linkTitleProbe` hook; `enrich` uses
    /// `fetchPage`, which pulls title AND body in one request.
    static func fetch(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        // Attributed to the registry's "Saved links" entry: the host is the
        // site you saved, which is why that entry's host reads as prose.
        NetworkLedger.shared.record(request, as: "Saved links")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
        else { return nil }
        return parseTitle(in: String(decoding: data.prefix(65_536), as: UTF8.self))
    }

    /// Fetches a saved page's READABLE substance (2026-07-15) — the meta
    /// description plus its opening paragraphs — so an answer can reach what a
    /// link is ABOUT, not just its title. The `-linkBodyProbe` hook's path;
    /// `enrich` uses `fetchPage`. Best-effort and bounded (see `parseReadable`).
    static func fetchReadable(_ url: URL) async -> String? {
        guard let html = await fetchHTML(url) else { return nil }
        return parseReadable(in: html)
    }

    /// Title AND readable body from ONE request (2026-07-15) — so `enrich`
    /// downloads the page once, not twice. nil fields where the page had no
    /// title / nothing readable.
    static func fetchPage(_ url: URL) async -> (title: String?, body: String?) {
        guard let html = await fetchHTML(url) else { return (nil, nil) }
        return (parseTitle(in: html), parseReadable(in: html))
    }

    /// One 8s / 512KB fetch of a page's HTML (article body lives well past
    /// <head>). nil on a network error or a non-2xx status.
    private static func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        NetworkLedger.shared.record(request, as: "Saved links")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
        else { return nil }
        return String(decoding: data.prefix(524_288), as: UTF8.self)
    }

    /// The `<title>` element's text, decoded and capped — nil when absent/empty.
    private static func parseTitle(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: [.caseInsensitive]),
              let openEnd = html.range(of: ">", options: [],
                                       range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: [.caseInsensitive],
                                     range: openEnd.upperBound..<html.endIndex)
        else { return nil }
        let raw = html[openEnd.upperBound..<close.lowerBound]
        let title = decodeEntities(String(raw))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return title.count > 120 ? String(title.prefix(120)) + "…" : title
    }

    /// The meta description plus opening paragraphs, de-duped and flattened —
    /// what lands in `Thing.enrichedText` (retrieval-only). Capped so it stays a
    /// lede, not a mirror of the page. nil when nothing readable comes back.
    private static func parseReadable(in html: String) -> String? {
        var pieces: [String] = []
        // The meta description lives in <head>, so read it off the whole page;
        // paragraphs come from the main CONTENT region (below), which skips the
        // header/nav chrome that would otherwise lead the excerpt with menu
        // scraps ("About · Search · Log in"). Narrowing generalizes across
        // sites, not just one (review 2026-07-15).
        if let desc = metaDescription(in: html) { pieces.append(desc) }
        pieces.append(contentsOf: paragraphs(in: contentRegion(html), limit: 6))

        // De-dupe (a description often repeats the first paragraph) and flatten.
        var seen = Set<String>()
        let text = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 24 && seen.insert($0).inserted }   // skip nav scraps
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return nil }
        return text.count > 1200 ? String(text.prefix(1200)) + "…" : text
    }

    /// The HTML from the first main-content marker onward — `<main>`,
    /// `<article>`, or a well-known content container id — so paragraph
    /// extraction skips the header/nav that precedes it. The whole page when no
    /// marker is found (a plain page's body IS its content).
    private static func contentRegion(_ html: String) -> String {
        for marker in ["<main", "<article", "id=\"mw-content-text\"",
                       "id=\"bodyContent\"", "id=\"content\"", "role=\"main\""] {
            if let r = html.range(of: marker, options: .caseInsensitive) {
                return String(html[r.lowerBound...])
            }
        }
        return html
    }

    /// The page's `<meta name="description">` / `og:description`, decoded.
    private static func metaDescription(in html: String) -> String? {
        for pattern in [
            "<meta[^>]+(?:name|property)=[\"'](?:og:)?description[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:name|property)=[\"'](?:og:)?description[\"']",
        ] {
            if let m = firstCapture(pattern, in: html) {
                let d = decodeEntities(m).trimmingCharacters(in: .whitespacesAndNewlines)
                if !d.isEmpty { return d }
            }
        }
        return nil
    }

    /// Text inside the first `<p>` blocks, inner tags stripped and entities
    /// decoded — a cheap readability pass, no DOM. Scripts/styles are dropped
    /// first so an inline `<script>` can't leak code into the excerpt.
    private static func paragraphs(in html: String, limit: Int) -> [String] {
        let cleaned = html
            .replacingOccurrences(of: "<script[^>]*>.*?</script>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[^>]*>.*?</style>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
        guard let re = try? NSRegularExpression(
            pattern: "<p[^>]*>(.*?)</p>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = cleaned as NSString
        var out: [String] = []
        for match in re.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let inner = ns.substring(with: match.range(at: 1))
            let stripped = inner
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            let text = decodeEntities(stripped)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep prose, drop chrome: a real paragraph carries a sentence
            // (a period), while nav/menu `<p>`s ("About · Search · Log in") run
            // long without one — those would only add noise to the index.
            let isProse = text.contains(". ") || text.hasSuffix(".")
            if !text.isEmpty, isProse { out.append(text) }
            if out.count >= limit { break }
        }
        return out
    }

    /// First capture group of `pattern` in `html`, case-insensitive.
    private static func firstCapture(_ pattern: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Renames a just-saved link thing once the title arrives — only when the
    /// person hasn't already given it a better face (the title still LOOKS
    /// like the URL it was born with). A pasted PRODUCT page goes further: it
    /// becomes a `.product`, its price captured so a re-check can catch a drop
    /// (2026-07-14).
    /// **Every read of `thing` below is guarded, at entry and after each
    /// suspension** — the build-256 crash, and the async half of the
    /// never-read-a-dead-Thing rule (corollary 6).
    ///
    /// All four callers spell this the same way:
    /// `Task { @MainActor in await LinkTitle.enrich(thing, context: context) }`
    /// — detached on purpose, so an 8-second page fetch never serializes the
    /// landing loop behind it. But a detached task does not run at the moment
    /// it is created: it is scheduled, the pass that created it carries on, and
    /// only then does this body start. §286's `SocialTopics.reconcile` deletes
    /// unexplained social rows on EVERY refresh pass, so a link landed at the
    /// top of a Farcaster sweep could be deleted before its own enrichment task
    /// had run a single line — and the first thing this function did was read
    /// `thing.kind`, which traps on a detached backing store.
    ///
    /// That is what crashed the Mac at launch from 2026-08-02 (`Fatal error:
    /// This backing data was detached from a context without resolving
    /// attribute faults … \Thing.kind`). `applyOEmbed` already carried this
    /// guard for the oEmbed branch, with a comment naming the exact hazard; the
    /// lesson simply never reached the function above it or the two fetches
    /// below.
    @MainActor
    static func enrich(_ thing: Thing, context: ModelContext) async {
        // Entry: the task was scheduled, not run, and the row may already be
        // gone. This is the crashing read.
        guard thing.isLive else { return }
        guard thing.kind == .link,
              let url = URL(string: thing.content.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? firstURL(in: thing.content),
              thing.title.contains(url.host() ?? "") || thing.title == thing.content
        else { return }
        // An allowlisted host answers what a link IS directly, keylessly, in
        // one request (`OEmbed`) — and it beats the page fetch below on
        // exactly the sites that don't serve a usable <head> to a non-browser
        // client at all. A TikTok link enriched by the generic path lands
        // wearing the site's stock page title with no thumbnail and no
        // creator; this names it by its caption instead. A miss (non-200, an
        // unrecognised shape, a retired endpoint) falls through unchanged.
        if OEmbed.handles(url), let embed = await OEmbed.resolve(url) {
            applyOEmbed(embed, to: thing, url: url, context: context)
            return
        }
        // A product page (one with a machine-readable price) upgrades the link
        // to a watched product — priced in the title, ready for a drop check.
        // A product's page is a store listing, not an article, so it gets no
        // readable-body pass.
        var namedFromMeta = false
        let meta = await ProductMeta.fetch(url)
        // The product fetch is an await, and this row can be deleted under it.
        guard thing.isLive else { return }
        if let meta {
            if meta.isProduct {
                upgradeToProduct(thing, meta: meta)
                thing.embedding = nil
                context.saveHonestly()
                SpotlightIndex.index([thing])
                return
            }
            if let title = meta.title, title != thing.title, !title.isEmpty {
                thing.title = title
                namedFromMeta = true
            }
        }
        // One fetch pulls the page's title and its readable lede.
        let page = await fetchPage(url)
        // The longest await in this function — up to 8 seconds, and every
        // write below touches the row.
        guard thing.isLive else { return }
        var changed = namedFromMeta
        // Take the raw <title> only when meta didn't already give a cleaner
        // name — meta's og:title beats "Article — SiteName" (review 2026-07-15).
        if !namedFromMeta, let title = page.title, title != thing.title {
            thing.title = title
            changed = true
        }
        // The readable lede → `enrichedText`, retrieval-only substance the title
        // alone can't carry. Best-effort; a miss leaves the link title-only.
        if let body = page.body, body != thing.enrichedText {
            thing.enrichedText = body
            changed = true
        }
        // Only when something actually changed: drop the stale vector so the
        // next semantic sweep re-embeds on the real text (EmbeddingIndex), and
        // save + reindex. A no-change fetch leaves the good vector alone.
        guard changed else { return }
        thing.embedding = nil
        context.saveHonestly()
        SpotlightIndex.index([thing])
    }

    /// Names a link from its own site's oEmbed answer: the caption (or, for a
    /// captionless post, its creator) as the face, the poster art as the
    /// preview, and caption + creator as the retrieval text — the only text
    /// the corpus will ever hold for a link with no readable page behind it.
    ///
    /// Mirrors `enrich`'s save discipline exactly: nothing is written unless
    /// something actually changed, and a change drops the stale vector so the
    /// next semantic sweep re-embeds on the real words.
    @MainActor
    private static func applyOEmbed(_ embed: OEmbed.Response, to thing: Thing,
                                    url: URL, context: ModelContext) {
        // The fetch above is an await, and a delete can land under one — a
        // heal or a CloudKit-propagated removal reaching this exact thing.
        // Reading a stored property off a tombstoned model traps inside
        // SwiftData (the liveness rule, CLAUDE.md).
        guard thing.isLive else { return }
        var changed = false
        if let title = OEmbed.title(embed, host: url.host()), title != thing.title {
            thing.title = title
            changed = true
        }
        if let art = embed.thumbnailURL, art != thing.previewImageURL {
            thing.previewImageURL = art
            changed = true
        }
        if let text = OEmbed.enrichedText(embed), text != thing.enrichedText {
            thing.enrichedText = text
            changed = true
        }
        guard changed else { return }
        thing.embedding = nil
        context.saveHonestly()
        SpotlightIndex.index([thing])
    }

    /// Turns a link thing into a priced product thing from its parsed page.
    @MainActor
    private static func upgradeToProduct(_ thing: Thing, meta: ProductMeta) {
        let name = (meta.title?.isEmpty == false ? meta.title! : thing.title)
        if let price = meta.priceValue,
           let money = PriceFormat.string(price, currency: meta.priceCurrency) {
            thing.title = IngestSupport.titleLine("\(name) · \(money)")
            thing.priceValue = price
            thing.priceCurrency = meta.priceCurrency
        } else {
            thing.title = IngestSupport.titleLine(name)
        }
        thing.kind = .product
        // The type tag rode `.link` ("Link"); re-tag it as a product so the
        // pill matches the new kind.
        thing.tags = ([ThingKind.product.typeTag] + thing.tags.filter { $0 != ThingKind.link.typeTag }).reduced()
        if let image = meta.image { thing.previewImageURL = image }
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }

    /// One decoder for every ingest path (moved to IngestSupport 2026-07-10;
    /// it also handles numeric references now).
    private static func decodeEntities(_ s: String) -> String {
        IngestSupport.decodeHTMLEntities(s)
    }
}
