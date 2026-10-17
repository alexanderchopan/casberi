import Foundation

/// POST ON X FROM THE SHARE TRAY (prd §1299, user: "we should have share to
/// twitter in the app isntead of behind the ios share sheet"): X's own public
/// post link, which opens X's composer — the app when it is installed, the
/// site when not — with the words and the link filled in. The person presses
/// Post there; Casberi never posts and never touches a session (the X seat
/// stays read-only, `docs` cookie-seat rule).
///
/// Two links (prd §1299, user: "it doesn't open each time or share the
/// casberi card"). `x.com/intent/post` is a universal link the X app does not
/// claim every time — it landed in Safari or on X's home — so the X app's own
/// scheme, `twitter://post`, goes first when the app is installed, and the
/// web composer is the fallback. Neither link can carry a picture, so a tray
/// with a card hands the system sheet the card and `message` instead, and X's
/// share extension attaches it (prd §1366); the links serve a tray with none.
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
        var items: [URLQueryItem] = []
        if !text.isEmpty { items.append(URLQueryItem(name: "text", value: text)) }
        if let link { items.append(URLQueryItem(name: "url", value: link.absoluteString)) }
        return compose(scheme: "https", host: "x.com", path: "/intent/post", items: items)
    }

    /// The X app's scheme, listed in `LSApplicationQueriesSchemes`.
    static let appScheme = "twitter"

    /// `twitter://post?message=…`, or nil with nothing to say. The scheme has
    /// one field, so the link rides at the end of the words.
    static func appURL(words: String, link: URL?) -> URL? {
        let message = message(words: words, link: link)
        guard !message.isEmpty else { return nil }
        return compose(scheme: appScheme, host: "post", path: "",
                       items: [URLQueryItem(name: "message", value: message)])
    }

    /// The words within the limit with the link at their end — the app link's
    /// one field, and the text the share sheet hands X beside the card.
    static func message(words: String, link: URL?) -> String {
        [text(words, link: link), link?.absoluteString ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func compose(scheme: String, host: String, path: String,
                                items: [URLQueryItem]) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.path = path
        parts.queryItems = items
        // `queryItems` leaves a `+` bare, and a bare `+` in a query reads as a
        // space, so "C++" would arrive as "C  ".
        parts.percentEncodedQuery = parts.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}
