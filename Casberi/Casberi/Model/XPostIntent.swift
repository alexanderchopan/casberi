import Foundation

/// POST ON X FROM THE SHARE TRAY (prd §1299, user: "we should have share to
/// twitter in the app isntead of behind the ios share sheet"): X's own public
/// post link, which opens X's composer — the app when it is installed, the
/// site when not — with the words and the link filled in. The person presses
/// Post there; Casberi never posts and never touches a session (the X seat
/// stays read-only, `docs` cookie-seat rule).
///
/// The link carries text and a URL only, never a picture, so the share card
/// still goes through `Share…`.
enum XPostIntent {
    /// A post's length, and what X counts any link as (t.co), whatever its
    /// own length.
    static let limit = 280
    static let linkWeight = 23

    /// The words a post can carry beside `link`: the text whole when it fits,
    /// else cut at a word with an ellipsis, so X's composer never opens over
    /// its limit.
    static func text(_ words: String, link: URL?) -> String {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = limit - (link == nil ? 0 : linkWeight + 1)
        guard trimmed.count > room else { return trimmed }
        let cut = trimmed.prefix(room - 1)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// `https://x.com/intent/post?text=…&url=…`, or nil with nothing to say.
    static func url(words: String, link: URL?) -> URL? {
        let text = text(words, link: link)
        guard !text.isEmpty || link != nil else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "x.com"
        parts.path = "/intent/post"
        var items: [URLQueryItem] = []
        if !text.isEmpty { items.append(URLQueryItem(name: "text", value: text)) }
        if let link { items.append(URLQueryItem(name: "url", value: link.absoluteString)) }
        parts.queryItems = items
        return parts.url
    }
}
