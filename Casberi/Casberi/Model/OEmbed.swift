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
/// MEASURED (2026-08-02): every endpoint below was called keylessly against a
/// real public link and answered with the fields `parse` reads — a `title` and
/// a `thumbnail_url` in all six, plus an `author_name` in all but Spotify.
/// Instagram was measured the same day and REMOVED for answering with none of
/// them (see the table). It still fails SAFE in every direction — a non-200, a
/// shape we don't recognise, or a host that has retired its endpoint all
/// return nil, and the caller falls through to the page-fetch path that runs
/// today. Re-measure with `-oembedProbe <url>` before hardening anything here.
///
/// THE PREMISE WAS ALSO MEASURED, and it holds where it was written. Fetching
/// each of these pages with the app's own `safariUserAgent` and reading the
/// head the generic path reads: TikTok serves NO `og:title` and a `<title>` of
/// "TikTok - Make Your Day"; YouTube serves NO `og:title` and a `<title>` of
/// "YouTube". Those two are the whole reason this file exists and there is no
/// other route to them. SoundCloud, Vimeo, Flickr and Spotify DO serve usable
/// og tags, so for them this path is an improvement of degree — it adds the
/// `author_name` none of their heads carry (Spotify excepted, where it ties)
/// and costs one small request instead of a 100–400KB page fetch. Do not
/// "simplify" this file away as redundant with `ProductMeta`: for its two
/// headline hosts it is the only thing that works.
///
/// Instagram is the exact inverse and that is why it is NOT in the table: its
/// oEmbed carries nothing and its page head carries everything.
enum OEmbed {

    /// What a link's own site says it is. Every field is optional because
    /// providers differ in what they fill; `resolve` returns nil rather than
    /// an empty shell when nothing usable came back.
    struct Response {
        let title: String?
        let authorName: String?
        let thumbnailURL: String?
        let providerName: String?
        /// The creator's @handle, where the provider gives one separately from
        /// their display name (TikTok's `author_unique_id`; measured present
        /// 2026-08-02). Kept apart from `authorName` because a handle is DATA —
        /// it groups, and "Scout, Suki & Stella" does not — which is what makes
        /// a room's "Who you save most" possible. nil for every provider that
        /// names neither field, and no reader may assume it.
        let authorHandle: String?
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
        // NOT INSTAGRAM — added 2026-07-31 (prd §245), removed 2026-08-02.
        //
        // The entry was taken while its fields were in doubt, on the reasoning
        // that the cost of being wrong was zero. The doubt is now settled by
        // measurement, and the answer is that the entry could never have paid:
        // `graph.facebook.com/v23.0/instagram_oembed` is live and keyless, and
        // answers a public post with `provider_name`, `type`, `width` and an
        // embed `html` blockquote — and NOTHING ELSE. No `title`, no
        // `author_name`, no `thumbnail_url`, which are the only three fields
        // `parse` reads. So `resolve` returned nil on every call: a request
        // spent to learn nothing, against a host we then had to disclose in
        // `NetworkReach`. Of the three disagreeing sources, Meta's April 2025
        // announcement (author and thumbnail stripped) is the true one.
        //
        // Facebook's own `oembed_video` was measured the same day and is no
        // better — keyless, but an embed script with no fields — and
        // `oembed_post` refuses keyless calls outright. Neither Meta host
        // belongs in this table. Re-add only against a fresh `-oembedProbe`
        // showing a real title or author, not against a doc.
        (["youtube.com", "youtu.be"], "https://www.youtube.com/oembed?format=json"),
        (["vimeo.com"],               "https://vimeo.com/api/oembed.json"),
        (["soundcloud.com"],          "https://soundcloud.com/oembed?format=json"),
        (["open.spotify.com"],        "https://open.spotify.com/oembed"),
        (["flickr.com", "flic.kr"],   "https://www.flickr.com/services/oembed?format=json"),
        // X, added 2026-08-02. The strongest case in this table after TikTok,
        // and for the same reason, measured directly rather than assumed: an
        // x.com post URL fetched with this app's own `safariUserAgent` answers
        // 200 with ~210KB of markup carrying ZERO `og:` tags and no `<title>`
        // element at all. So the generic path names an X link nothing, and the
        // row keeps the naked URL it was born with — the exact failure this
        // file exists for. `publish.x.com/oembed` answers the same link
        // keylessly with the author, their handle, and — inside the embed
        // `html` — the post's own words.
        //
        // NOT THE INSTAGRAM CASE, though the two payloads look alike. Both
        // answer with an `html` blockquote and no `title`; the difference is
        // what the blockquote HOLDS. Instagram's is a skeleton whose only text
        // is "View this post on Instagram" — the caption is filled in later,
        // client-side, by their embeds.js — which is why that entry could
        // never pay and was removed. X writes the post itself into the `<p>`,
        // so `blockquoteText` has real words to lift and `resolve` returns a
        // real answer. Measured against two live posts on 2026-08-02.
        //
        // X gives no `thumbnail_url` and never has; these rows stay text, the
        // same as any `.link` with no preview image. `twitter.com` is carried
        // beside `x.com` because saved links are old — the endpoint resolves
        // either, and a link saved in 2019 deserves the same face as one saved
        // today.
        (["x.com", "twitter.com"],    "https://publish.x.com/oembed?omit_script=1"),
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
    static func resolve(_ url: URL) async -> Response? { await ask(url).response }

    /// What a host said, INCLUDING the status when there's nothing to parse.
    ///
    /// `resolve` collapses every failure into nil, which is right for
    /// enrichment — a link keeps the title it has either way. It is wrong for a
    /// caller that wants to know WHY (2026-08-05, prd §307): a 404 or 410 from
    /// these hosts means the post is gone for good, a 403 means it went
    /// private, and an unreachable network means try later. Those are three
    /// different facts about the person's own corpus and only the last is worth
    /// retrying, so the one caller that acts on the difference reads it here.
    ///
    /// `status` is nil when the request never completed at all, which is the
    /// case that must never be mistaken for a deletion.
    static func ask(_ url: URL) async -> (response: Response?, status: Int?) {
        guard let endpoint = endpoint(for: url), let request = request(endpoint, for: url)
        else { return (nil, nil) }
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request)
        else { return (nil, nil) }
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200,
              data.count <= 512_000,        // an oEmbed answer is small; a page isn't
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, status) }
        return (parse(json), status)
    }

    /// Status codes that mean the thing itself is gone rather than that we
    /// couldn't reach it. 403 is included because these hosts answer it for a
    /// post whose account went private, which is "you can't see this any more"
    /// wearing a different number — and both readings are honest under the
    /// wording the room uses ("gone or private").
    static func meansGone(_ status: Int?) -> Bool {
        guard let status else { return false }
        return status == 404 || status == 410 || status == 403
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
        // A provider that names the link in `title` is read from `title`. The
        // fallback is for the one shape that puts the words in the embed
        // instead (X) — and it can only ever ADD a title where there was none,
        // so it cannot change what the six providers above already answer.
        let response = Response(title: text("title") ?? blockquoteText(json["html"] as? String),
                                authorName: text("author_name"),
                                thumbnailURL: IngestSupport.imageURL(json["thumbnail_url"] as? String),
                                providerName: text("provider_name"),
                                authorHandle: text("author_unique_id")
                                    ?? handle(inAuthorURL: text("author_url")))
        // An answer that names nothing is not an answer — fall through to the
        // page fetch rather than saving an empty enrichment over a real title.
        guard response.title != nil || response.authorName != nil
                || response.thumbnailURL != nil else { return nil }
        return response
    }

    /// The @handle inside an `author_url`, for the providers that name their
    /// creator only by their profile link (2026-08-05).
    ///
    /// X is why this exists: `publish.x.com/oembed` answers with an
    /// `author_name` — a display name, which does not group — and an
    /// `author_url` whose single path component is the handle (their post host
    /// followed by `/Interior`). Without this, every liked post in an X archive lands
    /// with `authorHandle` nil and the room can never rank whose posts you
    /// like, which is the one board this corpus is shaped for.
    ///
    /// A SINGLE PATH COMPONENT ONLY, and that rule is what keeps it from
    /// inventing handles for the rest of the table rather than a scoping
    /// accident: X's `/Interior`, SoundCloud's `/artist`, Vimeo's `/user123`
    /// and YouTube's `/@name` are all one component and all genuinely handles,
    /// while YouTube's other two shapes (`/channel/UC…`, `/user/Name`) are two
    /// components and are refused — a channel id is not something to print
    /// beside a face. A leading "@" is dropped so the stored value is the bare
    /// handle every other stamper in this app writes.
    ///
    /// Bounded and charset-checked because the value reaches a room's own
    /// chrome: a provider is free to answer with anything, and a ranking board
    /// is not the place to find that out.
    private static func handle(inAuthorURL raw: String?) -> String? {
        guard let raw, let url = URL(string: raw) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        var handle = parts[0]
        if handle.hasPrefix("@") { handle.removeFirst() }
        guard (1...30).contains(handle.count),
              handle.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" })
        else { return nil }
        return handle
    }

    /// The words inside an embed's `<blockquote><p>…</p>`, for the one provider
    /// shape that carries the post there instead of in a `title` (X).
    ///
    /// ORDER IS LOAD-BEARING: tags are stripped from the RAW html and entities
    /// are decoded only afterwards. Decoding first would turn an escaped
    /// `&lt;b&gt;` that somebody actually typed into a tag the stripper then
    /// eats, silently deleting words the person wrote.
    ///
    /// Only the FIRST `<p>` is read. What follows it in a `twitter-tweet`
    /// blockquote is the attribution — "— Developers (@XDevelopers) April 16,
    /// 2026" — whose author we already carry as its own field and whose date
    /// the thing gets from the capture; appended, it would read as part of the
    /// sentence the person wrote.
    ///
    /// A `<br>` becomes a space rather than a newline: this text is a title
    /// clamped to one line and retrieval substance, and in both a hard break
    /// is worth less than the words either side of it staying apart.
    ///
    /// Bounded at 64KB of html. This is a fallback for a missing title, not a
    /// licence for a provider to hand us a page to store.
    private static func blockquoteText(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 64_000,
              let regex = try? NSRegularExpression(
                pattern: "<p[^>]*>(.*?)</p>",
                options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let inner = Range(match.range(at: 1), in: raw)
        else { return nil }
        var text = String(raw[inner])
            .replacingOccurrences(of: "<br\\s*/?>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = IngestSupport.decodeHTMLEntities(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
