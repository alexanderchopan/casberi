import Foundation

/// A thing rendered as context for SOMEBODY ELSE'S agent (2026-08-06).
///
/// The keyed path (`AgentAnswer`) reaches seven providers, and every one of
/// them needs an API key, a paid account, and an entry in this app's own
/// switch statement. That leaves out most of how people actually use agents:
/// a chat window in a browser, a coding agent in a terminal, a colleague's
/// tool, anything that shipped last week. For all of those the universal
/// interchange format is the clipboard.
///
/// So this is the cheapest possible interoperability and the widest: no API,
/// no key, no provider list, no network at all. It works with every agent that
/// exists and every one that will.
///
/// **Redacted like any other export.** The text is on its way into somebody
/// else's context window, which is the same boundary `AgentAnswer.synthesize`
/// scrubs at (prd §277) — so it goes through `SecretScan` too. The on-device
/// model is the only reader in this app exempt from that, because it never
/// leaves; a clipboard is the opposite of not leaving.
enum AgentContext {

    /// How much of a thing's body travels. Generous — an agent's whole value
    /// here is reading the substance — but bounded, because a 40,000-word
    /// imported transcript on the clipboard is a paste nobody wants and a
    /// context window most agents don't have.
    static let bodyLimit = 8_000

    /// Markdown, because every agent reads it and a person can read it too.
    /// The header block is what makes the paste self-describing: an agent
    /// handed a bare paragraph has to guess what it is, and guessing is what
    /// this whole app is built to stop.
    static func render(_ thing: Thing, related: [Thing] = []) -> String {
        guard thing.isLive else { return "" }
        var lines: [String] = []
        lines.append("# \(SecretScan.redacted(thing.title))")
        lines.append("")
        var facts = ["**Kind:** \(thing.kind.typeTag)", "**From:** \(thing.source)"]
        facts.append("**Saved:** \(stamp(thing.capturedAt))")
        if !thing.tags.isEmpty {
            facts.append("**Tags:** " + SecretScan.safeTags(thing.tags).joined(separator: ", "))
        }
        lines.append(facts.joined(separator: "  \n"))

        // A link's permalink lives in `content`, so it is offered as a link
        // rather than dumped as a body — the one field whose meaning changes
        // with the kind.
        let body = SecretScan.redacted(String(thing.content.prefix(bodyLimit)))
        if !body.isEmpty {
            lines.append("")
            if thing.kind == .link, body.hasPrefix("http") {
                lines.append("**Link:** \(body)")
            } else {
                lines.append("---")
                lines.append("")
                lines.append(body)
            }
        }
        // The post's own full words, when the row carries them separately
        // from its clamped title (a social row's `postText`).
        if let post = thing.postText, !post.isEmpty, post != thing.content {
            lines.append("")
            lines.append(SecretScan.redacted(String(post.prefix(bodyLimit))))
        }
        if let summary = thing.summary, !summary.isEmpty {
            lines.append("")
            lines.append("**Summary:** \(SecretScan.redacted(summary))")
        }

        // Related things travel as TITLES only, never bodies. They are here so
        // the other agent knows what else exists to ask for — turning one
        // paste into a paste of twenty documents is how a helpful verb becomes
        // one nobody uses.
        let live = related.filter { $0.isLive && $0.id != thing.id }.prefix(8)
        if !live.isEmpty {
            lines.append("")
            lines.append("## Related things I've saved")
            for row in live {
                lines.append("- \(SecretScan.redacted(row.title)) — \(row.kind.typeTag), from \(row.source), \(stamp(row.capturedAt))")
            }
        }
        lines.append("")
        // Named, not branded: an agent reading this should know the provenance
        // of what it was handed, and "saved in Casberi" is a fact about the
        // text rather than an advertisement inside somebody's prompt.
        lines.append("_Saved in Casberi._")
        return lines.joined(separator: "\n")
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
