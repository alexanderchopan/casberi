import Foundation
import SwiftData
import Observation

/// The synthesized "Noticed" line on Home — one genuine cross-thing
/// connection, written by the on-device model over the person's recent things.
///
/// prd §36c left this door open: the deterministic co-occurrence version ("a
/// screenshot matches this session's chat") was removed for manufacturing
/// connections and costing screen space above what the person came to see. Its
/// note said a real, model-written version would be "a fresh build, not a
/// revival of this." This is that build — and the model is allowed to DECLINE
/// (write NONE → no line), so the line is only ever a real observation.
///
/// Computed OFF the render path and painted on the next compose: a recompose
/// storm (a foreground fires ~25 bridge refreshes) never triggers a model run,
/// and a device without Apple Intelligence simply shows no line — Home exactly
/// as it was before this. Persisted so a relaunch paints the last line
/// instantly, then refreshes only if the corpus (or the day) moved.
@MainActor
@Observable
final class HomeInsightStore {
    static let shared = HomeInsightStore()

    /// The current line, or nil for "nothing worth noting" / no model. Read by
    /// `HomeComposition.compose` (emitted as an `Insight` under the cover) and
    /// observed by HomeScreen so a landed line repaints.
    private(set) var line: String?

    /// The corpus+day signature the current line was written from — a refresh
    /// over the same signature is a no-op, so no inference is ever wasted.
    @ObservationIgnored private var signature: String
    /// One run at a time — a storm of corpus changes can't stack inferences.
    @ObservationIgnored private var running = false

    private static let lineKey = "home.insight.line"
    private static let sigKey = "home.insight.sig"

    private init() {
        line = UserDefaults.standard.string(forKey: Self.lineKey)
        signature = UserDefaults.standard.string(forKey: Self.sigKey) ?? ""
    }

    /// Recompute the line if the recent corpus (or the calendar day) changed.
    /// Cheap and idempotent: builds a signature from the newest things and
    /// returns early when it matches the live line's, so it's safe to call on
    /// every compose. `things` is expected newest-first (Home's `@Query` order).
    func refresh(from things: [Thing]) {
        // No model → no line. Clear any persisted line so a device that turned
        // Apple Intelligence off doesn't keep showing a stale one.
        guard OnDeviceModel.isAvailable else {
            signature = ""
            if line != nil { line = nil; persist() }
            return
        }
        let recent = Self.window(from: things)
        let sig = Self.signature(of: recent)
        guard sig != signature, !running else { return }
        // Too few things to notice anything ACROSS — no line, but remember the
        // signature so we don't re-check until things actually move.
        guard recent.count >= 3 else {
            signature = sig
            if line != nil { line = nil; persist() }
            return
        }
        running = true
        let candidates = recent.map(Self.candidate)
        Task { @MainActor in
            defer { running = false }
            let text = await OnDeviceModel.homeInsight(candidates: candidates)
            // Stamp the signature alongside the result so the next compose's
            // refresh sees a match and doesn't re-run for the same corpus.
            signature = sig
            line = text
            persist()
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        if let line { d.set(line, forKey: Self.lineKey) } else { d.removeObject(forKey: Self.lineKey) }
        d.set(signature, forKey: Self.sigKey)
    }

    // MARK: - Signature & candidates

    /// How many of the newest things the line is written from — enough for a
    /// real cross-source connection, capped so the prompt fits the on-device
    /// context window (the same budget `RootShell.answerSnippet` sizes for).
    private static let windowSize = 18

    /// The things the line is written from: the newest `windowSize`, with the
    /// Wallet/Tokens firehose excluded. Those sources auto-ingest at high volume
    /// and own their own Home surfaces (the wallet treemap, token charts), so in
    /// the newest-N window they crowd out the meaningful saves and the small
    /// model latches onto "Sent X TOKEN" spam — measured 2026-07-18: 8 of 18
    /// were transactions/watchlist links, and the line either echoed one or
    /// fabricated a story around them. Dropping them leaves the window for what
    /// the person actually saved (notes, chats, events, articles), which is what
    /// a "Noticed a connection" line is about. Not a manufactured connection —
    /// just better evidence.
    private static func window(from things: [Thing]) -> [Thing] {
        Array(things.lazy.filter { $0.source != "Wallet" && $0.source != "Tokens" }
            .prefix(windowSize))
    }

    /// A stable signature of the recent set plus the calendar day, so the line
    /// refreshes when new things land or the day turns — and only then.
    private static func signature(of things: [Thing]) -> String {
        let day = Int(Date.now.timeIntervalSinceReferenceDate / 86_400)
        let ids = things.map { $0.id.uuidString }.joined(separator: ",")
        return "\(day)|\(things.count)|\(ids)"
    }

    private static func candidate(_ t: Thing) -> OnDeviceModel.Candidate {
        OnDeviceModel.Candidate(title: t.title, kind: t.kind.typeTag,
                                source: t.source, when: shortTime(t.capturedAt),
                                note: snippet(t))
    }

    /// A short one-line excerpt of the thing's body — the substance the title
    /// can't carry (a note's text, a saved article's lede). Empty for a bare
    /// URL or when the body just echoes the title. A compact twin of
    /// `RootShell.answerSnippet`, kept local so the store has no cross-file
    /// private dependency.
    private static func snippet(_ t: Thing) -> String {
        let body = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let bareURL = body.lowercased().hasPrefix("http") && !body.contains(" ")
        var text = (body.isEmpty || body == t.title || bareURL) ? "" : body
        if text.isEmpty, let extra = t.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines) {
            text = extra
        }
        guard !text.isEmpty else { return "" }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        return flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    #if DEBUG
    /// `-homeInsightProbe` support — run the line over `things` bypassing the
    /// cache, logging the candidates fed and the post-guard result (nil =
    /// declined), so the prompt's voice/decline-rate can be sampled headlessly.
    /// The raw model text is logged separately by `FoundationAnswer.homeInsight`.
    func debugProbe(from things: [Thing]) async -> String? {
        let recent = Self.window(from: things)
        let candidates = recent.map(Self.candidate)
        let listing = candidates.enumerated().map { i, c in
            var l = "\(i + 1). \(c.title) — \(c.kind), from \(c.source), \(c.when)"
            if !c.note.isEmpty { l += "\n   \"\(c.note)\"" }
            return l
        }.joined(separator: "\n")
        NSLog("[Casberi] homeInsightProbe candidates (%d):\n%@", candidates.count, listing)
        return await OnDeviceModel.homeInsight(candidates: candidates)
    }
    #endif
}
