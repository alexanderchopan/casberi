import Foundation

/// The bound on a scraped readable body, in the one place both processes can
/// see it.
///
/// In `Shared/` rather than beside either scraper because that is the whole
/// point: the app and the share extension are separate binaries that clamp the
/// same column, and a constant only one of them can read is two constants.
/// Foundation-only, so `scripts/readable-body-selftest.sh` compiles it beside
/// `ReadableParse.swift` unmodified.
enum ReadableBody {
    /// How long a SCRAPED readable body may be on `enrichedText` (prd §645
    /// pass 5, 2026-09-08 — was 1,200 in two places that could not see each
    /// other).
    ///
    /// **ONE bound, because two processes write the column.** The app scrapes
    /// a body in two processes: `LinkTitle.parseReadable` in the app, and the
    /// share extension, whose Safari preprocessing script hands over the
    /// page's own reader text. Both clamped at 1,200 independently, and after
    /// §645 pass 1 both are DRAWN — so a divergence would mean the same
    /// article read at two lengths depending on whether you pasted it or
    /// shared it. `LinkTitle.enrich` cannot paper over that: it bails on a row
    /// already wearing a real title, which is exactly what a Safari share
    /// arrives with, so the extension's clamp is final for that row.
    ///
    /// 8,000 is `ObsidianNote.retrievalLimit`, and deliberately the same
    /// number for the same reason on the same column: *"roughly 1,300 words:
    /// long enough that a real note arrives whole, bounded enough that a
    /// pathological file can't put a megabyte into every `@Query` that faults
    /// this column."* Not referenced across the target boundary because
    /// `ObsidianNote` is app-only — the reason is what is shared, and it is
    /// written here.
    static let limit = 8_000

    /// What separates two paragraphs on `enrichedText` — a blank line, which
    /// is the one break `NoteSheet.blocks` honours for every source (prd §645
    /// amendment 4, 2026-09-08).
    ///
    /// Until this pass both scrapers flattened a page to ONE LINE: the app
    /// joined its `<p>`s with a space and the share extension's script
    /// collapsed `innerText`'s newlines the same way. That was harmless while
    /// the text was retrieval-only and became the "giant wall of text" the
    /// moment §645 drew it — 8,000 characters at `reading20` with no break
    /// anywhere. User: *"could we format it somewhat w/ rules, like every three
    /// or four sentences enter a line break"*. The parse now keeps the page's
    /// own paragraphs; `paragraphed` is that rule, for a body that arrived
    /// without any.
    static let separator = "\n\n"

    /// How many sentences a paragraph gets when the text arrived with none.
    /// Three, with a remainder of one folded into the previous group so no
    /// paragraph is ever a lone sentence — "three or four", the rule as asked.
    static let sentencesPerParagraph = 3

    /// The body with paragraph breaks, whether or not it arrived with any.
    ///
    /// Blocks the text already separates with a blank line are kept as they
    /// are when they hold four sentences or fewer. A longer block — a page
    /// whose `<p>`s were one run, or a row scraped before this pass and stored
    /// flat — is broken every `sentencesPerParagraph` sentences. Sentence
    /// boundaries come from Foundation's own `.bySentences` enumeration rather
    /// than a regex on full stops, so "U.S." and "Mr." do not start paragraphs.
    ///
    /// Applied at DRAW time by `ArticleBody`, never written back: a stored row
    /// keeps the page's own breaks (or its lack of them), so a later, better
    /// rule reaches every row instead of only rows scraped after it.
    static func paragraphed(_ text: String) -> String {
        let normalised = text.replacingOccurrences(of: "\\n[ \\t]*\\n", with: separator,
                                                   options: .regularExpression)
        let blocks = normalised.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // A section title is left as it is, and one with no section under it
        // — the last block, or a title straight before another — is dropped
        // (§645 amendment 5). The parse already holds a heading until a
        // paragraph follows; this is the same rule for a body the share
        // extension's script marked, which cannot see what follows.
        var out: [String] = []
        for (i, block) in blocks.enumerated() {
            if isHeading(block) {
                let next = i + 1 < blocks.count ? blocks[i + 1] : nil
                if let next, !isHeading(next) { out.append(block) }
                continue
            }
            out.append(contentsOf: grouped(block))
        }
        return out.joined(separator: separator)
    }

    /// A `# …` line — the one marker a scraped body carries.
    static func isHeading(_ block: String) -> Bool {
        let hashes = block.prefix(while: { $0 == "#" })
        return !hashes.isEmpty && hashes.count <= 6 && block.dropFirst(hashes.count).hasPrefix(" ")
            && !block.contains("\n")
    }

    /// One block, as the paragraphs it should be.
    private static func grouped(_ block: String) -> [String] {
        let sentences = self.sentences(in: block)
        guard sentences.count > sentencesPerParagraph + 1 else { return [block] }
        var out: [[String]] = []
        for sentence in sentences {
            if let last = out.last, last.count < sentencesPerParagraph {
                out[out.count - 1].append(sentence)
            } else {
                out.append([sentence])
            }
        }
        // A trailing paragraph of one sentence joins the one before it.
        if out.count > 1, out[out.count - 1].count == 1 {
            let lone = out.removeLast()
            out[out.count - 1].append(contentsOf: lone)
        }
        return out.map { $0.joined(separator: " ") }
    }

    /// The block's sentences, each trimmed, empty ones dropped.
    ///
    /// Foundation's enumeration ends a sentence at "Mr." and at an initial
    /// (it survives "U.S."), so a piece that ends on an abbreviation, on a
    /// single letter, or whose successor starts lowercase is joined to the
    /// next — measured on a fixture before the guard existed: "written by
    /// Mr." became a paragraph's last line and "Smith." the next one's first.
    static func sentences(in block: String) -> [String] {
        var raw: [String] = []
        block.enumerateSubstrings(in: block.startIndex..<block.endIndex, options: .bySentences) { sub, _, _, _ in
            let s = (sub ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { raw.append(s) }
        }
        var out: [String] = []
        var pending: String?
        for s in raw {
            if let head = pending {
                pending = nil
                let joined = head + " " + s
                if endsOnAbbreviation(joined) { pending = joined } else { out.append(joined) }
                continue
            }
            if endsOnAbbreviation(s) { pending = s } else { out.append(s) }
        }
        if let pending { out.append(pending) }
        // A successor that starts lowercase was never a new sentence.
        var merged: [String] = []
        for s in out {
            if let first = s.first, first.isLowercase, !merged.isEmpty {
                merged[merged.count - 1] += " " + s
            } else {
                merged.append(s)
            }
        }
        return merged
    }

    /// Titles, Latin tags and units a full stop does not end a sentence after.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "mt", "ft",
        "vs", "etc", "e.g", "i.e", "cf", "ca", "approx",
        "inc", "ltd", "co", "corp", "dept", "est", "fig", "gen", "gov",
        "sen", "rep", "hon", "capt", "col", "lt", "sgt", "rev",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]

    private static func endsOnAbbreviation(_ s: String) -> Bool {
        guard s.hasSuffix(".") else { return false }
        let word = s.dropLast().split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let token = word.trimmingCharacters(in: CharacterSet(charactersIn: "(\"“‘'")).lowercased()
        if token.count == 1, token.first?.isLetter == true { return true }   // an initial
        return abbreviations.contains(token)
    }

    /// The share extension's body: the page's description, then its article,
    /// the description dropped when the article already carries it — the
    /// same lead-then-paragraphs shape `ReadableParse.parseReadable` builds
    /// in the app, so a shared link and a pasted one read alike.
    ///
    /// Until this pass the extension kept the DESCRIPTION whenever the page
    /// had one and the article only otherwise — right for a lede to index,
    /// and since §645 it meant a Safari share drew one sentence under a page
    /// whose whole text it had in hand.
    static func compose(description: String?, article: String?) -> String {
        let lead = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (article ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return lead }
        guard !lead.isEmpty else { return body }
        let flat = { (s: String) in
            s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        if flat(body).contains(flat(lead)) { return body }
        return lead + separator + body
    }
}
