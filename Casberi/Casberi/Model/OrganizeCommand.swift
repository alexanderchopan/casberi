import Foundation
import SwiftData

/// Typed organize commands (2026-07-07) — "tag my lisbon links as Trip",
/// "rename Work to Clients". The composer ruling holds: typed words never
/// write silently. A command streams a PROPOSAL — the matched things, the
/// change, one Apply button — and the write happens on the tap, with Undo
/// in the toast. Two verbs to start; the sheet's tag machinery does the work.
enum OrganizeCommand: Equatable {
    case tag(query: String, tag: String)
    case rename(from: String, to: String)

    /// Command detection — leading verbs only, so questions stay questions.
    ///   tag <things> as <name>        · label <things> as <name>
    ///   rename (tag) <a> to <b>       · change (all) <a> (tags) to <b>
    static func parse(_ raw: String) -> OrganizeCommand? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = line.lowercased()

        for verb in ["tag ", "label "] where lower.hasPrefix(verb) {
            let rest = line.dropFirst(verb.count)
            guard let range = rest.range(of: " as ", options: [.caseInsensitive, .backwards])
            else { continue }
            let query = rest[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let tag = rest[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty, !tag.isEmpty else { continue }
            return .tag(query: query, tag: tag)
        }

        for verb in ["rename tag ", "rename ", "change all ", "change "] where lower.hasPrefix(verb) {
            let rest = line.dropFirst(verb.count)
            guard let range = rest.range(of: " to ", options: [.caseInsensitive, .backwards])
            else { continue }
            var from = rest[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let to = rest[range.upperBound...].trimmingCharacters(in: .whitespaces)
            for suffix in [" tags", " tag"] where from.lowercased().hasSuffix(suffix) {
                from = String(from.dropLast(suffix.count))
            }
            guard !from.isEmpty, !to.isEmpty else { continue }
            return .rename(from: from, to: to)
        }
        return nil
    }
}

/// What a command would do — shown before anything happens.
struct OrganizeProposal {
    let command: OrganizeCommand
    /// One-line statement of the change: "Tag 7 things as Trip".
    let headline: String
    /// The things the change touches (empty when blocked or nothing matched).
    let things: [Thing]
    /// A reason Apply is impossible ("Link is a built-in type…"); nil = go.
    let blocked: String?

    var canApply: Bool { blocked == nil && !things.isEmpty }
}

enum Organize {

    /// Words that pick a kind instead of matching text: "links" → .link.
    private static var kindWords: [String: ThingKind] {
        var map: [String: ThingKind] = [:]
        for kind in ThingKind.allCases {
            map[kind.typeTag.lowercased()] = kind
            map[kind.typeTagPlural.lowercased()] = kind
        }
        return map
    }

    private static let filler: Set<String> = ["my", "all", "the", "a", "an", "every", "things", "thing", "stuff"]

    @MainActor
    static func propose(_ command: OrganizeCommand, context: ModelContext) -> OrganizeProposal {
        let all = (try? context.fetch(FetchDescriptor<Thing>())) ?? []

        switch command {
        case .tag(let query, let tagRaw):
            let tag = canonicalTag(tagRaw, in: all)
            if ThingKind.from(typeTag: tag) != nil {
                return OrganizeProposal(
                    command: command, headline: "",
                    things: [],
                    blocked: "\(tag) is a built-in type — pick another name.")
            }
            let matched = match(query, in: all)
                .filter { thing in !thing.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            let headline = matched.isEmpty
                ? "Nothing new matches \"\(query)\""
                : "Tag \(matched.count) thing\(matched.count == 1 ? "" : "s") as \(tag)"
            return OrganizeProposal(command: .tag(query: query, tag: tag),
                                    headline: headline, things: matched, blocked: nil)

        case .rename(let fromRaw, let toRaw):
            // The person means an existing tag — find its real casing.
            let allTags = Set(all.flatMap(\.tags))
            guard let from = allTags.first(where: { $0.caseInsensitiveCompare(fromRaw) == .orderedSame })
            else {
                return OrganizeProposal(
                    command: command, headline: "",
                    things: [],
                    blocked: "No tag called \"\(fromRaw)\" — nothing to rename.")
            }
            if ThingKind.from(typeTag: from) != nil {
                return OrganizeProposal(
                    command: command, headline: "",
                    things: [],
                    blocked: "\(from) is a built-in type — it can't be renamed.")
            }
            let to = toRaw.trimmingCharacters(in: .whitespaces)
            let matched = all.filter { $0.tags.contains(from) }
            let headline = "Rename tag \(from) to \(to) — \(matched.count) thing\(matched.count == 1 ? "" : "s")"
            return OrganizeProposal(command: .rename(from: from, to: to),
                                    headline: headline, things: matched, blocked: nil)
        }
    }

    /// Applies a proposal. Returns the toast line and an undo that restores
    /// every touched thing's tags exactly.
    @MainActor
    static func apply(_ proposal: OrganizeProposal,
                      context: ModelContext) -> (summary: String, undo: () -> Void) {
        let before: [(Thing, [String])] = proposal.things.map { ($0, $0.tags) }

        switch proposal.command {
        case .tag(_, let tag):
            for thing in proposal.things {
                thing.tags.append(tag)
            }
        case .rename(let from, let to):
            for thing in proposal.things {
                thing.tags = thing.tags.map { $0 == from ? to : $0 }
            }
        }
        context.saveHonestly()
        SpotlightIndex.index(proposal.things)
        // Home composes from tags — a rename/retag leaves count unchanged, so
        // signal the composition to repaint (else Home still shows the old tag).
        CorpusSignal.shared.bump()

        let summary: String
        switch proposal.command {
        case .tag(_, let tag):
            summary = "Tagged \(before.count) — \(tag)"
        case .rename(let from, let to):
            summary = "\(from) is now \(to)"
        }
        let undo = { @MainActor in
            for (thing, tags) in before { thing.tags = tags }
            context.saveHonestly()
            SpotlightIndex.index(before.map(\.0))
            CorpusSignal.shared.bump()
        }
        return (summary, { Task { @MainActor in undo() } })
    }

    // MARK: - Matching (a write wants precision: every meaningful word must hit)

    private static func match(_ query: String, in all: [Thing]) -> [Thing] {
        var kinds: Set<ThingKind> = []
        var terms: [String] = []
        for word in query.lowercased().split(separator: " ").map(String.init) {
            if filler.contains(word) { continue }
            if let kind = kindWords[word] { kinds.insert(kind); continue }
            terms.append(word)
        }
        return all.filter { thing in
            if !kinds.isEmpty, !kinds.contains(thing.kind) { return false }
            guard !terms.isEmpty || !kinds.isEmpty else { return false }
            let hay = (thing.title + " " + thing.content + " "
                       + thing.source + " " + thing.tags.joined(separator: " ")).lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// True when a source NAME survives match() as a faithful source query —
    /// no word of it would be swallowed as a kind filter or filler stopword.
    /// The composer's organize invite only offers faithful sources: "tag
    /// reminders as X" would match by KIND across every source, and "The
    /// Browser" would shrink to the bare term "browser" (review 2026-07-10).
    static func faithfulSourceQuery(_ source: String) -> Bool {
        let words = source.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { !filler.contains($0) && kindWords[$0] == nil }
    }

    /// A new tag reuses an existing tag's casing when one matches.
    private static func canonicalTag(_ raw: String, in all: [Thing]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let existing = Set(all.flatMap(\.tags))
        return existing.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }
}
