import Foundation
import SwiftData

/// Capture — text in, thing out (S3: no destination decision, no title, no
/// folder). Kind inference is deliberately small at M1: a URL is a link, a
/// question mark defers to search (handled upstream), everything else is a
/// note. The /parse card refines this at M6.
enum Capture {

    /// Makes a Thing from composer input. Returns nil for empty input.
    /// Inline #tags ride along: "call dentist #Health" tags the thing Health
    /// and keeps the text clean.
    static func thing(from raw: String, source: String = "You") -> Thing? {
        let (stripped, tags) = extractTags(from: raw)
        let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let thing: Thing
        if let url = detectURL(in: text) {
            thing = Thing(
                kind: .link,
                title: linkTitle(url: url, text: text),
                content: text,
                source: source
            )
        } else {
            thing = Thing(
                kind: .note,
                title: noteTitle(text),
                content: text,
                source: source
            )
        }
        thing.tags.append(contentsOf: tags.filter { !thing.tags.contains($0) })
        return thing
    }

    /// Pulls inline #tags out of the text: returns the text without them and
    /// the tag words (# stripped). "#" alone or mid-word marks stay put.
    static func extractTags(from text: String) -> (String, [String]) {
        var tags: [String] = []
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        let kept = words.filter { word in
            guard word.hasPrefix("#"), word.count > 1 else { return true }
            let tag = String(word.dropFirst())
            guard tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return true }
            if !tags.contains(tag) { tags.append(tag) }
            return false
        }
        return (kept.joined(separator: " "), tags)
    }

    /// First URL in the text, if any.
    static func detectURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }

    /// A link's title: the text minus the URL if there is prose, else the host.
    private static func linkTitle(url: URL, text: String) -> String {
        let prose = text
            .replacingOccurrences(of: url.absoluteString, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !prose.isEmpty { return firstLine(prose) }
        return url.host()?.replacingOccurrences(of: "www.", with: "") ?? firstLine(text)
    }

    /// A note's title: its first line, capped for the row.
    private static func noteTitle(_ text: String) -> String {
        firstLine(text)
    }

    private static func firstLine(_ s: String, cap: Int = 80) -> String {
        let line = s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
        return line.count > cap ? String(line.prefix(cap)) + "…" : line
    }
}
