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

    /// The digest last seen for `kind`, or nil if never seen — lets a
    /// changed pill roll its numeric delta FROM what was seen TO what's
    /// current (delight, 2026-07-21) instead of popping cold to the new
    /// value.
    func lastSeenDigest(_ kind: String) -> String? {
        UserDefaults.standard.string(forKey: Self.seenPrefix + kind)
    }

    /// The CURRENT digest for each kept kind, as of the last `refreshDigests`
    /// — cheap to hold, so `anyChanged` can read it on every AgentBar render
    /// without re-running a single composer.
    private(set) var currentDigests: [String: String] = [:]

    /// The current ANSWER for each kept kind — `Result.delta`, the one-line
    /// reading its own composer wrote.
    ///
    /// Held since 2026-08-07 (prd §332). `refreshDigests` has always computed
    /// this: every composer returns `delta` alongside `digest`, and until now
    /// `refreshDigests` kept the digest — which decides whether to light a 7pt
    /// dot — and dropped the delta on the floor. So the app ran the full wallet
    /// read, the watchlist read and the deadline scan on every foreground, and
    /// spent the result on the word "something". `AgentOpen.tiles` prints it.
    ///
    /// Deliberately NOT persisted, unlike `titles`/`order`: a delta is a
    /// reading with a shelf life, and restoring "ETH is up 2.1%" from
    /// UserDefaults at launch would put a stale number in the largest type on
    /// the screen — §83's fake status in the one place it is most believed. An
    /// empty map means "not read yet this launch", which the tiles render as
    /// no tile at all.
    private(set) var currentDeltas: [String: String] = [:]

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
        var deltas: [String: String] = [:]
        for kind in order {
            if let result = await KeptAskComposers.compose(kind, things: things, context: context) {
                digests[kind] = result.digest
                deltas[kind] = result.delta
            }
        }
        currentDigests = digests
        currentDeltas = deltas
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
        // LAST colon, not first (fix 2026-07-20) — a compound kind
        // (`showtag:Book club`, `context:Calendar`) carries its own colon,
        // so splitting on the first one truncated the kind and swallowed
        // the rest into the title. A real title never ends in ": word".
        guard let colon = spec.range(of: ":", options: .backwards)?.lowerBound else { return }
        let kind = String(spec[spec.startIndex..<colon])
        let title = String(spec[spec.index(after: colon)...])
        shared.keep(kind, title: title)
        NSLog("[Casberi] keepAskProbe: kept \"%@\" (kind=%@) — order now [%@]",
              title, kind, shared.order.joined(separator: ", "))
    }
    #endif
}
