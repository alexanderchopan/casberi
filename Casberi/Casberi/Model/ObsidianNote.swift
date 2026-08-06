import Foundation

/// What a Markdown note in a vault actually SAYS, and where Obsidian itself
/// would open it (2026-08-06). Deliberately pure — Foundation only, no
/// SwiftData, no FileManager, no `Thing` — so `scripts/obsidian-selftest.sh`
/// compiles this file WHOLE and unmodified and every assertion is about the
/// shipped code rather than a copy of it.
///
/// It exists because `ObsidianIngest` used to hand a note's first 300 raw
/// bytes straight to `Thing.content` and call that the note. For a vault whose
/// notes open with YAML frontmatter — which is most vaults, and every vault
/// using Dataview, templates or the tag pane — those 300 bytes were
/// `---\ntags: [reading, 2026]\naliases:` and not one word the person wrote.
/// The row read as metadata, the excerpt read as metadata, and the retriever
/// scanned metadata.
enum ObsidianNote {

    /// The row/sheet excerpt clamp — what a feed row shows. Unchanged from the
    /// bridge's original 300, but now measured against the note's WORDS
    /// (frontmatter already removed) rather than its first bytes.
    static let excerptLimit = 300

    /// The retrieval clamp (`Thing.enrichedText`, retrieval-only by the
    /// 2026-07-15 ruling — nothing draws it). Notes are the one corpus in this
    /// app written to be read at length, and clamping them at the row excerpt
    /// meant a 2,000-word note was findable only by its opening paragraph.
    /// 8,000 characters is roughly 1,300 words: long enough that a real note
    /// arrives whole, bounded enough that a pathological file can't put a
    /// megabyte into every `@Query` that faults this column.
    static let retrievalLimit = 8_000

    /// A note is allowed to be about a few things, not fifty. A vault with a
    /// tag-per-thought convention would otherwise put hundreds of tags on the
    /// feed's filter surface, where the useful ones become unfindable.
    static let tagLimit = 12

    struct Parsed: Equatable {
        /// The note's own words, frontmatter removed, clamped for retrieval.
        let body: String
        /// The display excerpt — the same words, clamped shorter.
        let excerpt: String
        /// Frontmatter `tags:` plus inline `#tags`, normalized and de-duped.
        let tags: [String]
    }

    static func parse(_ markdown: String) -> Parsed {
        let split = splitFrontmatter(markdown)
        let body = split.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanned = strippingCode(body)
        let raw = frontmatterTags(split.frontmatter ?? "") + inlineTags(in: scanned)
        return Parsed(body: String(body.prefix(retrievalLimit)),
                      excerpt: String(body.prefix(excerptLimit)),
                      tags: normalize(raw))
    }

    // MARK: - Frontmatter

    /// Splits a leading YAML frontmatter block off the note.
    ///
    /// Two rules, both load-bearing, both the reason this isn't a regex:
    ///   • The block opens on the VERY FIRST line and nowhere else. A `---`
    ///     halfway down a note is a horizontal rule, and treating it as an
    ///     opener would delete everything above it.
    ///   • An opener with NO closing fence is not frontmatter either — it's a
    ///     note that begins with a horizontal rule. Returning the whole text
    ///     unchanged is the safe direction to be wrong in: the worst case is
    ///     a `---` in the excerpt, where the alternative is silently emptying
    ///     the note.
    static func splitFrontmatter(_ markdown: String) -> (frontmatter: String?, body: String) {
        let lines = markdown.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        else { return (nil, markdown) }

        for (index, line) in lines.enumerated().dropFirst() {
            // `.whitespacesAndNewlines` rather than `.whitespaces` so a CRLF
            // file's trailing `\r` doesn't stop the fence matching — this is
            // split on "\n" alone, which leaves the `\r` on every line.
            let fence = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard fence == "---" || fence == "..." else { continue }
            return (lines[1..<index].joined(separator: "\n"),
                    lines[(index + 1)...].joined(separator: "\n"))
        }
        return (nil, markdown)
    }

    /// The `tags:` / `tag:` key out of a frontmatter block, in the three
    /// shapes YAML writes it: an inline array (`tags: [a, b]`), an inline
    /// comma list (`tags: a, b`), and a block list of `- item` lines beneath
    /// the key.
    ///
    /// TOP-LEVEL ONLY — an indented `tags:` belongs to whatever key it's
    /// nested under (a Dataview block, a plugin's own config) and is not the
    /// note's subject. This is a line scanner and not a YAML parser on
    /// purpose: a real parser fails the whole block on one malformed line,
    /// and a note whose frontmatter has a typo should still land its words.
    static func frontmatterTags(_ yaml: String) -> [String] {
        let lines = yaml.components(separatedBy: "\n")
        var out: [String] = []
        var index = 0
        while index < lines.count {
            let raw = lines[index]
            index += 1
            guard let first = raw.first, first != " ", first != "\t" else { continue }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon]
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "tags" || key == "tag" else { continue }

            var value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("[") {
                value = String(value.dropFirst())
                if value.hasSuffix("]") { value = String(value.dropLast()) }
            }
            if value.isEmpty {
                // A block list: consume the `- item` lines that follow.
                while index < lines.count {
                    let item = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard item.hasPrefix("-") else { break }
                    out.append(String(item.dropFirst()))
                    index += 1
                }
            } else {
                out.append(contentsOf: value.components(separatedBy: ","))
            }
        }
        return out
    }

    // MARK: - Inline tags

    /// `#tag` as Obsidian means it. The leading boundary is what keeps this
    /// honest, and each alternative below is a real false positive it stops:
    ///   • `# Heading` / `## Sub` — the char after `#` must be a tag char, and
    ///     a space and a second `#` are both not.
    ///   • `https://example.com/page#anchor` — the `#` must follow a space,
    ///     a line start, or an opening bracket, never a word character.
    ///   • `#2026` — a purely numeric tag is not a tag in Obsidian either;
    ///     `normalize` drops it by requiring a letter.
    private static let inlinePattern = #"(?:^|[\s(\[>])#([\w/\-]+)"#

    static func inlineTags(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: inlinePattern,
                                                   options: [.anchorsMatchLines])
        else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        where match.numberOfRanges > 1 {
            out.append(ns.substring(with: match.range(at: 1)))
        }
        return out
    }

    /// Code is not prose. A fenced block of shell or C puts `#include`,
    /// `#define` and `#!/usr/bin/env` in front of the scanner, and an inline
    /// span puts `#include` in the middle of a sentence ABOUT code — none of
    /// them is a subject the person tagged this note with.
    ///
    /// Fences are stripped by line and inline spans by pattern, in that
    /// order: a backtick pair can't span lines, so doing it the other way
    /// would let a fence's own content be re-joined into one.
    static func strippingCode(_ text: String) -> String {
        var kept: [String] = []
        var fence: String?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") { fence = "```"; continue }
            if trimmed.hasPrefix("~~~") { fence = "~~~"; continue }
            kept.append(line)
        }
        let joined = kept.joined(separator: "\n")
        guard let regex = try? NSRegularExpression(pattern: "`[^`\n]*`") else { return joined }
        let ns = joined as NSString
        return regex.stringByReplacingMatches(
            in: joined, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }

    // MARK: - Normalization

    /// Trims YAML quoting and any `#` the person wrote in their frontmatter,
    /// drops anything without a letter (a bare year, a hex colour), de-dupes
    /// case-insensitively while KEEPING the first spelling seen, and caps.
    ///
    /// Case-insensitive de-dupe with the original spelling kept matters more
    /// than it looks: Obsidian treats `#Reading` and `#reading` as one tag, so
    /// landing both would put two chips on the filter surface that can never
    /// be told apart, while lowercasing the survivor would rename a person's
    /// deliberately-capitalized tag.
    static func normalize(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for candidate in raw {
            var tag = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            tag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            while tag.hasPrefix("#") { tag.removeFirst() }
            while let last = tag.last, last == "/" || last == "-" { tag.removeLast() }
            tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag.count <= 40,
                  tag.rangeOfCharacter(from: .letters) != nil,
                  seen.insert(tag.lowercased()).inserted else { continue }
            out.append(tag)
            if out.count == tagLimit { break }
        }
        return out
    }
}

/// Where Obsidian itself would open a landed note (2026-08-06).
///
/// The vault bridge is the one source in this app that reads a folder the
/// person also has an EDITOR for, and until now the corpus was a dead end: a
/// note you found in Casberi could be read here and nowhere else, even though
/// the app that owns it was one tap away. Obsidian registers `obsidian://`,
/// and both halves of the URL are already stored — the vault's own folder name
/// (`ObsidianStore.vaultName`) and the note's path inside it (its `sourceRef`).
///
/// Pure, and in this file rather than `Verbs.swift`, so the harness can pin the
/// encoding: the failure this guards against is a note whose name contains a
/// space, an ampersand or a `#`, where a naively-built URL silently opens the
/// wrong note or no note at all.
enum ObsidianLink {

    /// The vault-relative path a `obsidian:<rel>` sourceRef carries, with the
    /// leading separator removed. nil for any other bridge's ref.
    static func relativePath(from sourceRef: String?) -> String? {
        guard let ref = sourceRef, ref.hasPrefix("obsidian:") else { return nil }
        var rel = String(ref.dropFirst("obsidian:".count))
        while rel.hasPrefix("/") { rel.removeFirst() }
        return rel.isEmpty ? nil : rel
    }

    /// `obsidian://open?vault=<name>&file=<path>` — Obsidian's own documented
    /// shape. The extension is dropped because `file` is documented as taking
    /// the path with or without one, and a vault configured to use `.markdown`
    /// would otherwise never match.
    static func openURL(vault: String, sourceRef: String?) -> URL? {
        let name = vault.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let rel = relativePath(from: sourceRef) else { return nil }
        let file = (rel as NSString).deletingPathExtension
        guard !file.isEmpty, let vaultPart = encode(name), let filePart = encode(file)
        else { return nil }
        return URL(string: "obsidian://open?vault=\(vaultPart)&file=\(filePart)")
    }

    /// Percent-encoding for a QUERY VALUE, which is stricter than
    /// `.urlQueryAllowed` — that set is what's legal in a query STRING, so it
    /// leaves `&`, `=`, `+`, `?` and `/` intact and a note named "Q&A" would
    /// end the `vault` parameter early. `+` is encoded too, since a reader
    /// that decodes it as a space is within its rights.
    private static func encode(_ raw: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#/")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
