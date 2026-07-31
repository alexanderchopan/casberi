import Foundation

/// oEmbed (oembed.com) — a published spec a handful of sites answer keylessly
/// with a link's real identity: its title, its author, its thumbnail.
///
/// WHY THIS EXISTS. The generic enrichment path (`LinkTitle.enrich` →
/// `ProductMeta.fetch` / `fetchPage`) fetches a saved page and reads its
/// `<head>`. That works for the open web and fails on sites that don't serve a
/// usable head to a non-browser client at all. TikTok is the worst of them: a
/// saved TikTok link lands wearing the site's generic page title (or the naked
/// URL) with no thumbnail and no creator, while every other link in the corpus
/// gets a real face. TikTok's oEmbed endpoint answers the same question with no
/// key, no account and one request — so the branch that fixes TikTok is the
/// same branch that improves YouTube, Vimeo, SoundCloud and the rest.
///
/// DELIBERATELY NOT A BRIDGE (prd §244). Nothing is connected, nothing syncs,
/// there is no catalog seat and nothing for `catalog-sync.sh` to keep in step
/// with the website. This is a better READ of a link the person already saved,
/// which is why it lands in the enrichment chain and not in `BridgeCatalog`.
/// It is also the whole of what TikTok honestly offers us: their export is
/// 1–4 days stale (declined, prd §36), they have never had RSS, their Display
/// API reads only the authenticated account's own posts, and the EEA Data
/// Portability API needs a server this app doesn't have yet.
///
/// ALLOWLISTED, NEVER DISCOVERED. The spec also lets a page advertise its own
/// endpoint via `<link rel="alternate" type="application/json+oembed">`. Doing
/// that would mean fetching the page first — the exact fetch this path exists
/// to beat — and would let any saved URL name an arbitrary host for us to
/// call. A fixed table costs one request and can't be redirected by the page.
///
/// UNMEASURED (2026-07-31): authored with no egress to any of these hosts, so
/// every endpoint below is doc-derived, not observed. It fails SAFE in every
/// direction — a non-200, a shape we don't recognise, or a host that has
/// retired its endpoint all return nil, and the caller falls through to the
/// page-fetch path that runs today. Re-measure with `-oembedProbe <url>`
/// before hardening anything here.
enum OEmbed {

    /// What a link's own site says it is. Every field is optional because
    /// providers differ in what they fill; `resolve` returns nil rather than
    /// an empty shell when nothing usable came back.
    struct Response {
        let title: String?
        let authorName: String?
        let thumbnailURL: String?
        let providerName: String?
    }

    // MARK: - The allowlist

    /// Host suffix → endpoint. Each endpoint is keyless and documented by its
    /// own provider; the query string is carried here rather than assembled,
    /// because providers disagree about `format` (TikTok's docs show `url`
    /// alone, YouTube wants `format=json`, Vimeo puts it in the path).
    ///
    /// Adding a host: confirm the endpoint needs no key, then probe it. A host
    /// whose oEmbed answer would be WORSE than the page fetch doesn't belong
    /// here — this table is for sites the generic path reads badly.
    private static let endpoints: [(hosts: [String], endpoint: String)] = [
        (["tiktok.com"],              "https://www.tiktok.com/oembed"),
        // Instagram (2026-07-31, prd §245). The generic path reads Instagram
        // as badly as it reads TikTok — a logged-out post URL serves a login
        // wall, so a shared post lands wearing a stock title and no art.
        //
        // THE FIELDS ARE IN DOUBT and the table entry is worth having anyway.
        // Three sources disagree: Meta announced in April 2025 that
        // `/instagram_oembed` would stop returning `thumbnail_url`,
        // `thumbnail_width`, `thumbnail_height` and `author_name`; a June 2026
        // change made the endpoint callable with NO token and no App Review;
        // and an April 2026 reference still documents `author_name` and
        // `thumbnail_url` as present. If the fields are stripped, `parse`
        // finds nothing usable, `resolve` returns nil, and the caller falls
        // through to exactly today's behaviour — so the cost of being wrong
        // here is zero, and the payoff if `author_name` survives is a saved
        // post reading "natgeo on Instagram" instead of a login wall's title.
        // Note this endpoint answers for PUBLIC posts, carousels and reels
        // only — never stories, never a private account, never a profile.
        // MEASURE IT with `-oembedProbe` before trusting any field.
        (["instagram.com"],           "https://graph.facebook.com/v23.0/instagram_oembed"),
        (["youtube.com", "youtu.be"], "https://www.youtube.com/oembed?format=json"),
        (["vimeo.com"],               "https://vimeo.com/api/oembed.json"),
        (["soundcloud.com"],          "https://soundcloud.com/oembed?format=json"),
        (["open.spotify.com"],        "https://open.spotify.com/oembed"),
        (["flickr.com", "flic.kr"],   "https://www.flickr.com/services/oembed?format=json"),
    ]

    /// The endpoint for a link's host, or nil when the host isn't allowlisted.
    ///
    /// Matches on the host's own label boundary (`== suffix` or
    /// `.hasSuffix("." + suffix)`) — NEVER `contains`, which would match
    /// `tiktok.com.attacker.example` and hand a stranger's domain our request.
    private static func endpoint(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        for entry in endpoints {
            for suffix in entry.hosts where host == suffix || host.hasSuffix("." + suffix) {
                return entry.endpoint
            }
        }
        return nil
    }

    /// True when this path has anything to say about a URL — the cheap check
    /// `LinkTitle.enrich` makes before spending a request.
    static func handles(_ url: URL) -> Bool { endpoint(for: url) != nil }

    // MARK: - The read

    /// Asks an allowlisted host what a link is. nil for any host we don't
    /// carry, any non-200, or an answer with no title, author or thumbnail in
    /// it — the caller keeps its generic path in every one of those cases.
    static func resolve(_ url: URL) async -> Response? {
        guard let endpoint = endpoint(for: url), let request = request(endpoint, for: url)
        else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 512_000,        // an oEmbed answer is small; a page isn't
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(json)
    }

    /// Builds the endpoint request, percent-encoding the link BY HAND.
    ///
    /// `URLComponents.queryItems` is not usable here: its setter escapes only
    /// what's illegal in a query COMPONENT, and `&` and `=` are both legal
    /// there — so a TikTok URL carrying tracking parameters would be handed
    /// over split into several query items and the endpoint would see a
    /// truncated link. Encoding against the RFC 3986 unreserved set instead
    /// leaves nothing that can end the parameter early.
    private static func request(_ endpoint: String, for url: URL) -> URLRequest? {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved),
              let full = URL(string: endpoint + (endpoint.contains("?") ? "&" : "?") + "url=" + encoded)
        else { return nil }
        var request = URLRequest(url: full)
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The same Safari-shaped UA the page fetches use — free, and a
        // bot-shaped client is exactly what these hosts are hostile to.
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Reads the four fields worth keeping out of an oEmbed payload. Entities
    /// are decoded (a caption arrives HTML-escaped from more than one
    /// provider) and blanks are dropped, so a provider that answers with an
    /// empty `title` doesn't rename a thing to nothing.
    static func parse(_ json: [String: Any]) -> Response? {
        func text(_ key: String) -> String? {
            guard let raw = json[key] as? String else { return nil }
            let clean = IngestSupport.decodeHTMLEntities(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        let response = Response(title: text("title"),
                                authorName: text("author_name"),
                                thumbnailURL: IngestSupport.imageURL(json["thumbnail_url"] as? String),
                                providerName: text("provider_name"))
        // An answer that names nothing is not an answer — fall through to the
        // page fetch rather than saving an empty enrichment over a real title.
        guard response.title != nil || response.authorName != nil
                || response.thumbnailURL != nil else { return nil }
        return response
    }

    // MARK: - Shaping a thing

    /// The one-line face for a link, from what the provider actually said.
    ///
    /// A caption is the best name a short video has, so it leads. A post with
    /// no caption at all (common on TikTok) falls back to naming its creator
    /// rather than staying a naked URL — "Charlie on TikTok" is a real thing
    /// you can find later; "https://www.tiktok.com/@…/video/7…" is not. nil
    /// when the provider gave neither, so the caller keeps the title it has.
    static func title(_ response: Response, host: String?) -> String? {
        if let title = response.title { return IngestSupport.titleLine(title) }
        guard let author = response.authorName else { return nil }
        guard let provider = response.providerName ?? host else {
            return IngestSupport.titleLine(author)
        }
        return IngestSupport.titleLine("\(author) on \(provider)")
    }

    /// The retrieval substance for a link — what `Thing.enrichedText` carries
    /// so the answer path can reach a video by its caption or its creator, the
    /// way it reaches an article by its lede. There is no readable page body
    /// behind these links, so this is the only text the corpus will ever have
    /// for one. nil when there's nothing but a thumbnail.
    ///
    /// Joined with " · " and deliberately NOT deduped against the title: the
    /// title is clamped to 80 characters, so a long caption survives here in
    /// full even when the face it wears is truncated.
    static func enrichedText(_ response: Response) -> String? {
        var pieces: [String] = []
        if let title = response.title { pieces.append(title) }
        if let author = response.authorName {
            if let provider = response.providerName {
                pieces.append("\(author) on \(provider)")
            } else {
                pieces.append(author)
            }
        }
        guard !pieces.isEmpty else { return nil }
        let text = pieces.joined(separator: " · ")
        return text.count > 1200 ? String(text.prefix(1200)) + "…" : text
    }
}
