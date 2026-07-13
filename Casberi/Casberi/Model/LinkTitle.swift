import Foundation
import SwiftData

/// A pasted URL saves instantly with the URL as its face; this fetches the
/// page's real <title> right after and renames the thing — the link lands
/// named, not naked. Best-effort: offline or titleless pages keep the URL.
enum LinkTitle {

    /// Fetches the page title (5s cap, first 64KB — titles live in <head>).
    static func fetch(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
        else { return nil }
        let html = String(decoding: data.prefix(65_536), as: UTF8.self)
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

    /// Renames a just-saved link thing once the title arrives — only when the
    /// person hasn't already given it a better face (the title still LOOKS
    /// like the URL it was born with).
    @MainActor
    static func enrich(_ thing: Thing, context: ModelContext) async {
        guard thing.kind == .link,
              let url = URL(string: thing.content.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? firstURL(in: thing.content),
              thing.title.contains(url.host() ?? "") || thing.title == thing.content
        else { return }
        guard let title = await fetch(url), title != thing.title else { return }
        thing.title = title
        // The title just changed — drop the stale vector so the next semantic
        // sweep re-embeds this thing on its real title, not the URL it was born
        // with (EmbeddingIndex).
        thing.embedding = nil
        try? context.save()
        SpotlightIndex.index([thing])
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
