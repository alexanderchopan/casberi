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
        // Every zk.money payment link's claim secret leaves the text before
        // any branch reads it (prd §1384): only the first is staged, and
        // only a site that inserts the row keeps it (`ZkMoneyClaims.commit`).
        // The zk.money branch reads the ORIGINAL text: its payment link is
        // known by its fragment, and `capture` scrubs the content itself
        // (seen on a simulator 2026-10-17: reading the scrubbed text titled a
        // payment link as a plain one).
        let original = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let scrubbed = ZkMoneyLink.scrub(original)
        let text = scrubbed.text
        guard !text.isEmpty else { return nil }

        let thing: Thing
        // A payment link pasted with no scheme is not a URL to the detector
        // (`.money` is not a TLD it knows, measured), so the scrubbed secret
        // names the link instead.
        let zkURL = detectURL(in: original).flatMap { ZkMoneyLink.link($0.absoluteString) == nil ? nil : $0 }
            ?? scrubbed.secrets.first.flatMap(URL.init(string:))
        if let url = zkURL, let zk = ZkMoneyLink.capture(url: url, text: original) {
            // A zk.money link (2026-10-11): a payment link's claim secret is
            // never kept, and a request link says what it asks for.
            thing = Thing(kind: .link, title: zk.title, content: zk.content, source: source)
            thing.enrichedText = zk.note
            thing.dueAt = zk.expires
        } else if detectURL(in: text) != nil {
            // The link is kept without the parameters that exist only to say
            // who shared it and where it was clicked (prd §1819).
            let kept = withoutTrackers(text)
            thing = Thing(
                kind: .link,
                title: detectURL(in: kept).map { linkTitle(url: $0, text: kept) } ?? noteTitle(kept),
                content: kept,
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
        if let secret = scrubbed.secrets.first {
            if thing.enrichedText == nil { thing.enrichedText = ZkMoneyLink.paymentNote(kept: false) }
            ZkMoneyClaims.stage(secret, for: thing.id)
        }
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

    /// One shared detector — construction compiles the data-detector regex
    /// (milliseconds), and the shaped feed rows call this per row per render.
    /// NSDataDetector is immutable and thread-safe for matching.
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// First URL in the text, if any.
    static func detectURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        return linkDetector?.firstMatch(in: text, range: range)?.url
    }

    /// Parameters that attribute a click and do nothing else, on any site.
    ///
    /// NARROWER than `ThingLinks.trackingParams` on purpose. That set decides
    /// whether two saves are one page and may over-match; this one rewrites
    /// what the person kept, so a name that is load-bearing somewhere (`ref`,
    /// `s`, `t`) is never here. Those come off only on the hosts below, where
    /// they are measured to be the share stamp.
    static let clickTrackers: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gbraid", "wbraid", "dclid", "msclkid", "twclid", "yclid",
        "igshid", "igsh", "mc_cid", "mc_eid", "mkt_tok", "_hsenc", "_hsmi",
        "ref_src", "ref_url", "spm", "_branch_match_id",
    ]

    /// A share stamp that names the SHARER, by the site that writes it. A
    /// YouTube `t` is a timestamp and stays; X's `t` is the share's id.
    static let shareStamps: [(hosts: [String], names: Set<String>)] = [
        (["youtube.com", "youtu.be", "music.youtube.com", "open.spotify.com"], ["si", "pp"]),
        (["x.com", "twitter.com"], ["s", "t"]),
        (["tiktok.com"], ["_r", "_t", "is_from_webapp", "sender_device"]),
        (["reddit.com"], ["share_id", "rdt"]),
    ]

    /// One link without its trackers; the same string when it carries none,
    /// is not http(s), or does not parse. Percent-encoding and the order of
    /// what stays are untouched, so a signed or ordered query still works.
    static func withoutTrackers(link raw: String) -> String {
        guard raw.contains("?"),
              var comps = URLComponents(string: raw),
              comps.scheme == "http" || comps.scheme == "https",
              var host = comps.host?.lowercased(),
              let items = comps.percentEncodedQueryItems
        else { return raw }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.hasPrefix("m.") { host = String(host.dropFirst(2)) }
        let stamps = shareStamps.first { entry in
            entry.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }?.names ?? []
        let kept = items.filter {
            let name = $0.name.lowercased()
            return !clickTrackers.contains(name) && !stamps.contains(name)
        }
        guard kept.count != items.count else { return raw }
        comps.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return comps.string ?? raw
    }

    /// `text` with every link in it stripped as above, the words around them
    /// left alone.
    static func withoutTrackers(_ text: String) -> String {
        guard text.contains("?"), let linkDetector else { return text }
        let whole = text as NSString
        var out = text as NSString
        let matches = linkDetector.matches(in: text, range: NSRange(location: 0, length: whole.length))
        for match in matches.reversed() {
            let raw = whole.substring(with: match.range)
            let clean = withoutTrackers(link: raw)
            if clean != raw { out = out.replacingCharacters(in: match.range, with: clean) as NSString }
        }
        return out as String
    }

    /// The same text with every URL in it carrying a `.link` attribute, so a
    /// `Text` renders them as real links instead of inert characters.
    ///
    /// Attributes only — no colour, no underline. This file is compiled into
    /// the extension targets too and can't see the design tokens; the view
    /// that displays it paints the link runs (see `ThingSheetView.postWords`).
    ///
    /// EVERY match, not `firstMatch`: a post that ends in two links would
    /// otherwise have one live and one dead, which is the honesty rule's dead
    /// control in miniature. Ranges come back as UTF-16 offsets into the same
    /// string the `AttributedString` was built from, so they map across
    /// directly; a range that somehow doesn't map is skipped rather than
    /// forced.
    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = linkDetector else { return attributed }
        let full = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: full) {
            guard let url = match.url,
                  let range = Range(match.range, in: attributed) else { continue }
            attributed[range].link = url
        }
        return attributed
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
