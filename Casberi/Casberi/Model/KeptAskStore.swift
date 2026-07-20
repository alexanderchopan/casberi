import Foundation
import SwiftData
import Observation

/// The agent's kept-ask list (docs/agent-brief.md, ruling 5) — the standing
/// questions someone chose to keep, rendered as B1 pill chips above the
/// existing ask-suggestion grid. Mirrors `AskMemory`'s shape (one dictionary
/// per UserDefaults key, keyed by an ask's stable KIND string — never a
/// display title, so a kept ask survives its wording changing later).
///
/// Two DIFFERENT "seen" concepts live in this system on purpose, and they
/// must not be merged:
///   - The bar's pulse (ruling 6) is coarse and SESSION-scoped — "has the
///     agent been raised at all this launch" — a plain, non-persisted flag,
///     not this store's concern.
///   - THIS store's `changed`/`markSeen` are PER-ASK and PERSISTED — "has
///     THIS kept ask's answer changed since I last opened it," the dot on
///     an individual pill.
@MainActor
@Observable
final class KeptAskStore {
    static let shared = KeptAskStore()

    /// Most-recently-kept first.
    private(set) var order: [String] = []
    /// kind -> the question, as it was asked, for display.
    private(set) var titles: [String: String] = [:]

    private static let orderKey = "keptAsks.order"
    private static let titlesKey = "keptAsks.titles"
    private static let seenPrefix = "keptAsks.seenDigest."

    private init() {
        order = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        titles = UserDefaults.standard.dictionary(forKey: Self.titlesKey) as? [String: String] ?? [:]
    }

    func isKept(_ kind: String) -> Bool { order.contains(kind) }

    func keep(_ kind: String, title: String) {
        guard !order.contains(kind) else { return }
        order.insert(kind, at: 0)
        titles[kind] = title
        persist()
    }

    func remove(_ kind: String) {
        order.removeAll { $0 == kind }
        titles[kind] = nil
        UserDefaults.standard.removeObject(forKey: Self.seenPrefix + kind)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(order, forKey: Self.orderKey)
        UserDefaults.standard.set(titles, forKey: Self.titlesKey)
    }

    /// Cheap synchronous diff — a kept ask's own composer supplies `digest`
    /// (whatever plain string honestly identifies "the current facts": an
    /// away count, a wallet total, the Noticed line's own text). Called on
    /// every agent open for every kept ask whose composer is itself cheap
    /// and synchronous (deterministic, per ruling 1 — never a model call).
    func changed(_ kind: String, digest: String) -> Bool {
        UserDefaults.standard.string(forKey: Self.seenPrefix + kind) != digest
    }

    /// Stamped when the person actually opens that ask's answer (taps the
    /// pill) — not merely when the agent rises.
    func markSeen(_ kind: String, digest: String) {
        UserDefaults.standard.set(digest, forKey: Self.seenPrefix + kind)
    }

    /// The CURRENT digest for each kept kind, as of the last `refreshDigests`
    /// — cheap to hold, so `anyChanged` can read it on every AgentBar render
    /// without re-running a single composer.
    private(set) var currentDigests: [String: String] = [:]

    /// The bar's pulse condition (ruling 6, combined with the caller's own
    /// "opened this launch" check) — true when some kept ask's current digest
    /// doesn't match what was last seen. A pure, cheap read: string compares
    /// over a short list, safe every render.
    var anyChanged: Bool {
        order.contains { changed($0, digest: currentDigests[$0] ?? "") }
    }

    /// Recomputes every kept kind's digest — the only place a kept ask's
    /// composer runs OUTSIDE the agent itself. Mirrors `HomeInsightStore`'s
    /// own discipline: gated to foreground (RootShell's `scenePhase ==
    /// .active` block), never to a render path, so an expensive kind
    /// (wallet/watchlist, both async) can't turn AgentBar into a per-frame
    /// fetch storm.
    func refreshDigests(things: [Thing], context: ModelContext) async {
        guard !order.isEmpty else { return }
        var digests: [String: String] = [:]
        for kind in order {
            if let result = await KeptAskComposers.compose(kind, things: things, context: context) {
                digests[kind] = result.digest
            }
        }
        currentDigests = digests
    }

    #if DEBUG
    /// `-keepAskProbe "<kind>:<title>"` — keep a kind headlessly (verifies the
    /// persistence + digest machinery without tapping through the UI, since
    /// computer-use typing trips the sim's accent picker). `-keepAskProbe
    /// clear` empties the whole store.
    static func seedFromLaunchArgs() {
        guard let spec = UserDefaults.standard.string(forKey: "keepAskProbe"),
              !spec.isEmpty else { return }
        if spec == "clear" {
            for kind in shared.order { shared.remove(kind) }
            NSLog("[Casberi] keepAskProbe: cleared")
            return
        }
        guard let colon = spec.firstIndex(of: ":") else { return }
        let kind = String(spec[spec.startIndex..<colon])
        let title = String(spec[spec.index(after: colon)...])
        shared.keep(kind, title: title)
        NSLog("[Casberi] keepAskProbe: kept \"%@\" (kind=%@) — order now [%@]",
              title, kind, shared.order.joined(separator: ", "))
    }
    #endif
}
