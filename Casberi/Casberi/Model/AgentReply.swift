import Foundation

/// The answer, split so it can be SET rather than poured (prd §581).
///
/// Every ask surface before this one drew the question, the destination's name
/// and the reply in the same bold sans on the same ink, at 40 / 24 / 20, and
/// the user's verdict on a screenshot was that the text "always looks like ass
/// and blends into the question and bankr name". It did: three things in one
/// voice with only size between them read as one paragraph, and size is the
/// weakest separator there is when everything on the surface is already large.
///
/// The ruling (2026-09-03) is that **the answer is the screen**. The question
/// folds to a one-line caption behind a stamp — you wrote it, you know what it
/// says — and the reply's FIRST SENTENCE takes the display rung alone, with
/// whatever follows stepping down to `heading22` in secondary ink. That is a
/// real hierarchy rather than a size ladder: one sentence in white at 40, a
/// paragraph in grey at 24, and nothing else on the paper.
///
/// It works because of what Bankr's own prompt asks for — "a few plain
/// sentences, no preamble" (`BankrAgent.prompt`) — so the first sentence is
/// reliably the news and the rest is the detail behind it. **That dependency is
/// the reason this is a function and not a view**: it is the one part of the
/// treatment that can be wrong about a real reply, so it is the part that gets
/// a harness.
///
/// Foundation-only by design, and it stays that way: `GenEls` is the parser's
/// own dictionary (`GenUI/GenParser.swift`, no SwiftUI), so this whole file
/// compiles under a bare `swiftc` beside it and `agent-reply-selftest.sh`
/// mutation-tests every rule below against the shipped source.
enum AgentReply {

    /// The longest first sentence that may take the display rung.
    ///
    /// MEASURED against the shape rather than chosen: at 40pt on a 390pt
    /// screen roughly 110 characters is four lines, which is already the whole
    /// upper half of the paper. A first sentence longer than that is not a
    /// headline, it IS the answer — so past this the split is abandoned and
    /// the entire reply is set at `heading22`, which is the honest fallback
    /// rather than a wall of display type.
    static let leadCap = 110

    // MARK: - Is this a written reply at all?

    /// The prose of a document that is nothing but prose, else nil.
    ///
    /// `RootShell.proseDoc` emits exactly `root = Stack([ins])` /
    /// `ins = Insight("…")` for a keyed answer that came back as sentences —
    /// which is every Bankr answer, and every on-device answer that found
    /// nothing to attach. Anything richer (a `modelDoc` with picks, a brief, a
    /// Find) is a DOCUMENT and must keep going through `GenRender`, because
    /// its rows are the answer and re-setting them as a paragraph would throw
    /// the things away.
    ///
    /// So this is deliberately narrow: it recognises the one shape it can
    /// safely re-set and returns nil for everything else. A false nil costs
    /// the display treatment; a false positive would delete content.
    static func prose(_ els: GenEls) -> String? {
        guard let root = els["root"] else { return nil }
        if root.comp == "Insight" { return text(of: root) }
        guard root.comp == "Stack" else { return nil }
        let refs = root.refs(0)
        guard refs.count == 1, let only = els[refs[0]], only.comp == "Insight" else { return nil }
        // Two elements and no more: a Stack holding one Insight is prose, a
        // Stack holding one Insight PLUS anything the root doesn't reference
        // is a document mid-stream and will grow.
        guard els.count == 2 else { return nil }
        return text(of: only)
    }

    private static func text(of el: GenEl) -> String? {
        let s = el.str(0).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: - The split

    /// The first sentence, and everything after it.
    ///
    /// An empty `lead` means "do not set this at the display rung" — the
    /// caller then draws `rest` alone at reading size. An empty `rest` is the
    /// ordinary one-sentence reply.
    static func split(_ text: String) -> (lead: String, rest: String) {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !whole.isEmpty else { return ("", "") }
        guard let cut = firstBreak(in: whole) else {
            // No sentence end at all — a fragment, a single clause, a number.
            return whole.count <= leadCap ? (whole, "") : ("", whole)
        }
        let lead = String(whole[whole.startIndex...cut])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(whole[whole.index(after: cut)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lead.isEmpty, lead.count <= leadCap else { return ("", whole) }
        return (lead, rest)
    }

    /// The index of the character that ends the first sentence.
    ///
    /// A newline counts, because a reply that opens with its own line has
    /// already told us where the break is.
    private static func firstBreak(in s: String) -> String.Index? {
        let chars = Array(s)
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if ch == "\n" {
                return s.index(s.startIndex, offsetBy: index)
            }
            if ch == "." || ch == "!" || ch == "?" {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                let ends = next == nil || next!.isWhitespace
                if ends, ch != "." || !looksLikeAbbreviation(chars, dotAt: index) {
                    return s.index(s.startIndex, offsetBy: index)
                }
            }
            index += 1
        }
        return nil
    }

    /// Is the full stop at `dotAt` part of an abbreviation rather than a
    /// sentence end?
    ///
    /// The run before it decides. "Mr.", "Dr.", "No.", the "S" of "U.S." are
    /// all two characters or fewer and none of them ends a sentence; "ETH.",
    /// "Base." and "$0.04." are three or more, or carry a digit, and all of
    /// them do.
    ///
    /// **A decimal point never reaches here**: "0.62" has no whitespace after
    /// its stop, so `ends` is already false. That is the case worth stating,
    /// because it is the one that would break every reply Bankr writes about
    /// money — and it is handled by the whitespace rule rather than by this
    /// one, which is why this function may stay as coarse as it is.
    private static func looksLikeAbbreviation(_ chars: [Character], dotAt: Int) -> Bool {
        var start = dotAt
        while start > 0, !chars[start - 1].isWhitespace { start -= 1 }
        let run = chars[start..<dotAt]
        if run.contains(where: { $0.isNumber }) { return false }
        // A run with a stop already INSIDE it is a dotted abbreviation —
        // "U.S.", "e.g." — and the last of its stops ends nothing. Tested
        // after the digit rule and not before it, because "$0.04." carries a
        // stop too and that one really does end the sentence.
        if run.contains(".") { return true }
        return run.count <= 2
    }
}
