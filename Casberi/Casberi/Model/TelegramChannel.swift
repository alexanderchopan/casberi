import Foundation

/// A public Telegram channel, read keylessly from the channel's own web
/// preview at `t.me/s/<channel>` (prd §456, 2026-08-23).
///
/// **WHY THIS DOOR AND NOT THE OTHER THREE.** §57's 2026-07-14 amendment cut
/// Telegram from the catalog after weighing all three ways in, and two of them
/// are unchanged: the Bot API is capture-only (a bot sees what is forwarded to
/// it and can never speak as the person), and TDLib reads real chats on-device
/// but is a client-grade dependency behind a platform wall. What that ruling
/// did not consider is that a public CHANNEL is not a chat at all — it is
/// broadcast media with a public web page, so following one is the §312
/// feed-follow shape (Substack/Reddit/YouTube/Podcasts), not the MTProto
/// problem. No account, no key, no server, nothing to mint.
///
/// **THE PARSE IS SCRAPE-GRADE AND HAS NO CONTRACT** — this is somebody's web
/// page, not a documented feed. That is the whole reason
/// `scripts/live-integrations.sh` asserts the four markers below nightly: when
/// they move the room does not break, it goes QUIET, which from outside is
/// indistinguishable from a channel that stopped posting.
///
/// Every rule here was MEASURED against real channels on 2026-08-23 (durov,
/// telegram, toncoin, telegramtips, varlamov, meduzalive, tginfo,
/// breakingmash) before a line of it was written. Re-measure before "fixing"
/// any of them:
///
///   1. **`/s/<name>` answering 200 IS the definition of a followable
///      channel.** A 302 to `/<name>` means it is not one, and the landing
///      page says why (`standing(_:)`): "subscribers" is a channel with its
///      preview off, "members" is a GROUP, neither is an unclaimed name. Three
///      different answers that would otherwise render as one empty room.
///   2. **Posts arrive OLDEST FIRST.** The newest post on the page is the
///      LAST element, not the first. Assuming the other order silently makes
///      the room's newest row its oldest.
///   3. **Slice BETWEEN wrapper starts, never lookahead-match.** A regex that
///      needs a following wrapper to close the current one drops the final
///      message — which, given (2), is the newest one. Cost one round of a
///      reference parser reporting 19 of 20 posts.
///   4. **The text container CAN nest a `<div>`** (measured: 1 post in 19 on
///      @meduzalive), so its end is found by DEPTH, not by the first
///      `</div>`. A naive scan truncates exactly those posts mid-sentence.
///   5. **`telegram.org/img/emoji/...` is a decoy.** Every emoji is an `<i
///      class="emoji">` whose `background-image` is a sprite PNG, so the naive
///      photo read files every emoji as a photograph. A real picture is on
///      `telesco.pe`; nothing else counts.
///   6. **"Please open Telegram to view this post" is CHROME, not words.**
///      Telegram writes it into the text container for a post its own preview
///      cannot render. Landed, rows read as that sentence instead of the
///      author's.
///   7. **The view count is REFUSED.** The page publishes it already rounded
///      ("12.6M"), and the only field that could hold it (`Thing.viewCount`)
///      is an Int — so landing it would turn a rounded string into a precise
///      number nobody measured. YouTube's `media:statistics` is exact and is
///      landed; this is not, and is not. (§83, in the one place a figure looks
///      most like a fact.)
///
/// Foundation-only BY DESIGN so `scripts/telegram-selftest.sh` can compile it
/// WHOLE and unmodified — the strongest form a harness here takes, and the
/// only proof these rules hold, since nothing in a build or a screen sweep can
/// see a parse that quietly returns the wrong nineteen posts.
enum TelegramChannel {

    // MARK: - Identity

    /// The namespace every LIVE row lands under. Shared with
    /// `Corpus.liveRefPrefixes`, which is what lets a followed channel's posts
    /// reach the All feed while the same source's imported export does not —
    /// so the two spellings must agree, and the harness asserts they do.
    static let refPrefix = "telegram:post:"

    /// The `Thing.source` both halves of this seat land under.
    static let source = "Telegram"

    /// What a channel is called on the wire. Telegram usernames are 5–32 of
    /// `[A-Za-z0-9_]` starting with a letter; matching that here means a typo
    /// is refused before it becomes a request for somebody else's page.
    static func normalizeHandle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where s.lowercased().hasPrefix(scheme) {
            s = String(s.dropFirst(scheme.count))
        }
        for host in ["t.me/", "telegram.me/", "telegram.dog/", "www.t.me/"]
        where s.lowercased().hasPrefix(host) {
            s = String(s.dropFirst(host.count))
        }
        // `t.me/s/<name>` is the preview URL somebody may well paste back in.
        if s.lowercased().hasPrefix("s/") { s = String(s.dropFirst(2)) }
        if s.hasPrefix("@") { s = String(s.dropFirst()) }
        // Drop a post id, a query or a fragment — `t.me/durov/523` names the
        // channel just as well as `t.me/durov` does.
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[s.startIndex..<cut])
        }
        return s.lowercased()
    }

    /// Is this a name Telegram could actually serve? Refusing here is what
    /// keeps a fat-fingered follow from becoming a request, and keeps a
    /// pasted invite link (`t.me/+AbCd…`, which names no channel) out.
    static func isValidHandle(_ handle: String) -> Bool {
        guard handle.count >= 5, handle.count <= 32 else { return false }
        guard let first = handle.first, first.isLetter else { return false }
        return handle.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "_" }
    }

    static func previewURL(for handle: String) -> String {
        "https://t.me/s/" + handle
    }

    /// The permalink a row opens. Deliberately NOT the `/s/` form: that is the
    /// preview we read, while this is the post as Telegram itself shows it,
    /// and it is what opens the Telegram app when it is installed.
    static func postURL(handle: String, id: Int) -> String {
        "https://t.me/\(handle)/\(id)"
    }

    static func ref(handle: String, id: Int) -> String {
        "\(refPrefix)\(handle)/\(id)"
    }

    // MARK: - Shapes

    struct Post: Equatable {
        /// The channel as the PAGE spells it, off `data-post` — never the
        /// typed input, so a follow typed "Durov" and one typed "durov" can
        /// never land the same post under two refs.
        var channel: String
        var id: Int
        var text: String
        var date: Date?
        /// A real photograph, always a `telesco.pe` URL. nil for a post whose
        /// only images were emoji (see rule 5).
        var photoURL: String?
        var hasVideo: Bool
        /// Whose post this repeats, when the channel forwarded somebody. The
        /// display NAME, which is all the preview carries — never a handle,
        /// so nothing downstream may treat it as one.
        var forwardedFrom: String?
        /// The headline of the page this post links out to, when Telegram
        /// rendered a link preview for it.
        var linkTitle: String?

        var ref: String { TelegramChannel.ref(handle: channel, id: id) }
        var url: String { TelegramChannel.postURL(handle: channel, id: id) }

        /// A post carrying no words of its own — a bare photograph or video.
        /// The room draws these as pictures rather than as rows with a
        /// placeholder title (§375's ruling, one product over).
        var isWordless: Bool { text.isEmpty }
    }

    struct Channel: Equatable {
        var handle: String
        /// The channel's own display name, off `og:title`. Falls back to the
        /// handle rather than to an empty string, because this becomes the
        /// row's byline.
        var title: String
        var avatarURL: String?
        var about: String
        /// As published: OLDEST FIRST (rule 2).
        var posts: [Post]

        var newest: Post? { posts.last }
    }

    /// What a name turned out to BE, when `/s/` refused to serve it. Four
    /// answers rather than one silence, because only `.unknown` is a bug.
    enum Standing: Equatable {
        /// A real channel whose owner turned the web preview off. Nothing we
        /// can do, and worth saying so — the person's name was not wrong.
        case channelWithoutPreview
        /// A group, not a channel. Groups have no public web preview and are
        /// not broadcast media; this seat cannot read one and never claims to.
        case group
        /// No such public channel — a typo, a private invite, or a name that
        /// was never claimed.
        case absent
        /// It answered, and said nothing we recognise.
        case unknown
    }

    // MARK: - Parsing

    /// The channel's page, or nil when the body is not one at all — which is
    /// what a redirect, an error page or a interstitial looks like from here.
    static func parse(_ html: String, handle: String) -> Channel? {
        // The marker every real preview page carries. Without it there is
        // nothing to read, and reporting an empty channel would be a claim.
        guard html.contains("tgme_widget_message") || html.contains("tgme_channel_info") else {
            return nil
        }

        var posts: [Post] = []
        for (raw, fragment) in messageFragments(in: html) {
            guard let post = parsePost(raw: raw, fragment: fragment, fallbackHandle: handle) else {
                continue
            }
            posts.append(post)
        }

        let title = meta(html, property: "og:title").map(IngestSupport.decodeHTMLEntities) ?? ""
        let about = meta(html, property: "og:description").map(IngestSupport.decodeHTMLEntities) ?? ""
        let avatar = meta(html, property: "og:image")

        return Channel(
            handle: posts.first?.channel ?? handle,
            title: title.isEmpty ? handle : title,
            avatarURL: IngestSupport.imageURL(avatar),
            about: about,
            posts: posts
        )
    }

    /// Read the LANDING page (`t.me/<name>`, where `/s/` redirected) for the
    /// reason it is not followable. Measured 2026-08-23: a channel's counter
    /// reads "subscribers", a group's reads "members", and a name nobody has
    /// claimed carries no counter at all.
    static func standing(_ landingHTML: String) -> Standing {
        guard let extra = element(in: landingHTML,
                                  withClassContaining: "tgme_page_extra")?.lowercased() else {
            return landingHTML.contains("tgme_page_") ? .absent : .unknown
        }
        if extra.contains("subscriber") { return .channelWithoutPreview }
        if extra.contains("member") { return .group }
        return .unknown
    }

    // MARK: - One post

    private static func parsePost(raw: String, fragment: String, fallbackHandle: String) -> Post? {
        // `data-post` is "<channel>/<id>" and is the only stable identity on
        // the page — the DOM order is not one, and neither is the text.
        let parts = raw.split(separator: "/")
        guard parts.count == 2, let id = Int(parts[1]) else { return nil }
        let channel = String(parts[0])
        guard !channel.isEmpty else { return nil }

        var post = Post(
            channel: channel.lowercased(),
            id: id,
            text: "",
            date: nil,
            photoURL: nil,
            hasVideo: fragment.contains("tgme_widget_message_video"),
            forwardedFrom: nil,
            linkTitle: nil
        )

        if let body = element(in: fragment, withClassContaining: "tgme_widget_message_text") {
            post.text = plainText(body)
        }
        if let stamp = datetime(in: fragment) {
            post.date = timestamp(stamp)
        }
        post.photoURL = photograph(in: fragment)
        // A forward names its source in a `<span>`, with a SECOND span
        // (`…_forwarded_from_author`) repeating it beside in parentheses.
        // Scanning to `</a>` overran the whole post body and captured both —
        // "Pavel Durov (Pavel Durov)" plus the article — so this is scoped to
        // the name span itself.
        if let fwd = element(in: fragment,
                             withClassContaining: "tgme_widget_message_forwarded_from_name") {
            let name = plainText(fwd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { post.forwardedFrom = name }
        }
        if let lp = element(in: fragment, withClassContaining: "link_preview_title") {
            let t = plainText(lp).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { post.linkTitle = t }
        }

        // A post with neither words nor a picture nor a video is chrome we
        // failed to recognise, not a post. Dropping it is better than landing
        // a row with nothing in it. (`fallbackHandle` is unused on the happy
        // path and exists so a page whose `data-post` is malformed is skipped
        // rather than filed under a guessed channel.)
        _ = fallbackHandle
        guard !post.text.isEmpty || post.photoURL != nil || post.hasVideo else { return nil }
        return post
    }

    // MARK: - Text

    /// Telegram's own placeholder for a post its preview cannot render (rule
    /// 6). Stripped from the words, never from the record that the post
    /// exists — a video post is still a post.
    private static let chrome = "Please open Telegram to view this post"

    /// Markup to readable text. `<br>` becomes a newline BEFORE tags are
    /// stripped, or every multi-paragraph post collapses onto one line.
    ///
    /// Note an emoji survives this for free: its real character sits inside
    /// the `<i class="emoji">`'s `<b>`, so stripping tags keeps it while
    /// dropping the sprite that stands behind it.
    static func plainText(_ markup: String) -> String {
        var s = markup
        for br in ["<br>", "<br/>", "<br />", "</p>"] {
            s = s.replacingOccurrences(of: br, with: "\n", options: .caseInsensitive)
        }
        s = stripTags(s)
        // `&nbsp;` is not in the shared entity decoder (it handles the five
        // that titles use plus numeric references), and Telegram uses it for
        // typographic spacing constantly — "с&nbsp;Украиной" landed raw.
        // Folded to an ordinary space rather than U+00A0: this is body text
        // being read, not typeset.
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = IngestSupport.decodeHTMLEntities(s)
        s = s.replacingOccurrences(of: chrome, with: "")
        // The stripped chrome and the block tags around it leave a run of
        // blank lines behind.
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var depth = 0
        for ch in s {
            if ch == "<" { depth += 1 } else if ch == ">" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 {
                out.append(ch)
            }
        }
        return out
    }

    // MARK: - Media

    /// The first REAL photograph in a post. Only `telesco.pe` counts (rule 5).
    private static func photograph(in fragment: String) -> String? {
        var cursor = fragment.startIndex
        let needle = "background-image:url('"
        while let open = fragment.range(of: needle, range: cursor..<fragment.endIndex) {
            guard let close = fragment.range(of: "'", range: open.upperBound..<fragment.endIndex) else {
                return nil
            }
            let url = String(fragment[open.upperBound..<close.lowerBound])
            if isPhotograph(url) { return IngestSupport.imageURL(url) }
            cursor = close.upperBound
        }
        return nil
    }

    /// Telegram serves real media off `telesco.pe` and emoji sprites off
    /// `telegram.org`. Matched on the label boundary, never `contains`, so
    /// `telesco.pe.example.com` cannot pass for the CDN.
    static func isPhotograph(_ url: String) -> Bool {
        guard let host = host(of: url)?.lowercased() else { return false }
        return host == "telesco.pe" || host.hasSuffix(".telesco.pe")
    }

    private static func host(of url: String) -> String? {
        var s = url
        if s.hasPrefix("//") { s = "https:" + s }
        guard let u = URL(string: s), let h = u.host else { return nil }
        return h
    }

    // MARK: - Time

    /// `<time datetime="2026-06-09T19:33:51+00:00">` — an offset is always
    /// present, so the instant is unambiguous and no calendar or time zone of
    /// ours is involved. Read with an explicit formatter rather than a shared
    /// one, because a date that silently lands a day out is this parser's most
    /// expensive possible mistake and its correctness should be local.
    static func timestamp(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw)
    }

    // MARK: - Scanning

    /// Every message on the page, as (data-post value, fragment).
    ///
    /// Slices BETWEEN wrapper starts (rule 3): each fragment runs from its own
    /// opening tag to the next one, and the last runs to the end of the page.
    static func messageFragments(in html: String) -> [(String, String)] {
        let marker = "data-post=\""
        var starts: [(String, String.Index)] = []
        var cursor = html.startIndex
        while let open = html.range(of: marker, range: cursor..<html.endIndex) {
            guard let close = html.range(of: "\"", range: open.upperBound..<html.endIndex) else { break }
            let value = String(html[open.upperBound..<close.lowerBound])
            // Back up to this element's own `<div`, so the fragment carries the
            // wrapper's classes (the video/forward markers live on them).
            let elementStart = html.range(of: "<div", options: .backwards,
                                          range: html.startIndex..<open.lowerBound)?.lowerBound
                ?? open.lowerBound
            starts.append((value, elementStart))
            cursor = close.upperBound
        }
        var out: [(String, String)] = []
        for (index, entry) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].1 : html.endIndex
            guard entry.1 < end else { continue }
            out.append((entry.0, String(html[entry.1..<end])))
        }
        return out
    }

    /// The inner HTML of the first element whose class contains `needle`,
    /// matched by DEPTH so a nested element of the same tag cannot end it
    /// early (rule 4).
    ///
    /// The tag is INFERRED from the markup rather than supplied, because it is
    /// not stable: a forward from a public channel names its source in an
    /// `<a>` (carrying a link back to the original post), and a forward from a
    /// private one names it in a `<span>` — measured on the same day, one
    /// channel each. A caller passing a fixed tag reads one shape and silently
    /// returns nothing for the other, which looks exactly like a channel that
    /// never forwards anything.
    static func element(in html: String, withClassContaining needle: String) -> String? {
        guard let mark = html.range(of: needle) else { return nil }
        guard let tag = enclosingTag(in: html, before: mark.lowerBound) else { return nil }
        guard let tagEnd = html.range(of: ">", range: mark.upperBound..<html.endIndex) else { return nil }
        let opening = "<" + tag
        let closing = "</" + tag
        var depth = 1
        var cursor = tagEnd.upperBound
        let start = cursor
        while depth > 0, cursor < html.endIndex {
            // `</div` can never match `<div`, so the two searches are disjoint
            // and whichever lands first decides.
            let o = html.range(of: opening, range: cursor..<html.endIndex)
            guard let c = html.range(of: closing, range: cursor..<html.endIndex) else { return nil }
            if let o, o.lowerBound < c.lowerBound {
                depth += 1
                cursor = o.upperBound
            } else {
                depth -= 1
                if depth == 0 { return String(html[start..<c.lowerBound]) }
                cursor = c.upperBound
            }
        }
        return nil
    }

    /// The name of the element whose opening tag encloses `index` — found by
    /// walking back to the nearest `<` and reading the word after it.
    static func enclosingTag(in html: String, before index: String.Index) -> String? {
        guard let open = html.range(of: "<", options: .backwards,
                                    range: html.startIndex..<index) else { return nil }
        var name = ""
        var cursor = open.upperBound
        while cursor < html.endIndex {
            let ch = html[cursor]
            if ch.isLetter || ch.isNumber { name.append(ch) } else { break }
            cursor = html.index(after: cursor)
        }
        return name.isEmpty ? nil : name
    }

    /// The first `<time>` that actually CARRIES a `datetime`.
    ///
    /// Measured: a video post opens with `<time class="message_video_duration">`
    /// — a clip's running time, no `datetime` attribute — so reading the first
    /// `<time>` in the fragment left every video post undated (15 of 20 on
    /// @telegram). An undated post falls back to "now", which would file a
    /// four-month-old broadcast as today's news.
    static func datetime(in html: String) -> String? {
        var cursor = html.startIndex
        while let open = html.range(of: "<time", range: cursor..<html.endIndex) {
            guard let end = html.range(of: ">", range: open.upperBound..<html.endIndex) else { return nil }
            let inside = html[open.upperBound..<end.lowerBound]
            if let attr = inside.range(of: "datetime=\""),
               let close = inside.range(of: "\"", range: attr.upperBound..<inside.endIndex) {
                return String(inside[attr.upperBound..<close.lowerBound])
            }
            cursor = end.upperBound
        }
        return nil
    }

    static func meta(_ html: String, property: String) -> String? {
        guard let mark = html.range(of: "property=\"" + property + "\"") else { return nil }
        guard let contentMark = html.range(of: "content=\"",
                                           range: mark.upperBound..<html.endIndex) else { return nil }
        guard let close = html.range(of: "\"",
                                     range: contentMark.upperBound..<html.endIndex) else { return nil }
        let value = String(html[contentMark.upperBound..<close.lowerBound])
        return value.isEmpty ? nil : value
    }

    private static func between(_ html: String, after: String, before: String) -> String? {
        guard let open = html.range(of: after) else { return nil }
        // Step past the rest of the opening tag when `after` named a class.
        let from = html.range(of: ">", range: open.upperBound..<html.endIndex)?.upperBound
            ?? open.upperBound
        guard let close = html.range(of: before, range: from..<html.endIndex) else { return nil }
        return String(html[from..<close.lowerBound])
    }
}
