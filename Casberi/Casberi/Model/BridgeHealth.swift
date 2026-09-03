import Foundation

/// Whether a connected bridge is still being LET IN — the one failure this app
/// could not see.
///
/// **Why this exists.** Every bridge here is written so that a failed read
/// returns nil and lands nothing, which is the right shape (a hiccup must
/// never wipe a room) and has one consequence nobody could observe: a bridge
/// whose key was revoked, whose token expired, or whose account was closed
/// looks *exactly* like a bridge with no news. The room goes quiet, the tile
/// stays connected, and nothing anywhere says why. With ~60 seats and most of
/// them never measured against a live account, that is the likeliest real
/// failure in the product and the only one with no symptom.
///
/// **The ruling that keeps it honest: health means DID WE REACH IT, never DID
/// IT HAVE NEWS.** A quiet room is usually a correct room — that is the point
/// of most of these bridges — so a check that flags silence is a lint that
/// cries wolf, and this codebase's own history says those get ignored inside a
/// week. Whether a specific bridge's silence is meaningful is per-bridge
/// knowledge and already lives where it belongs (`StripeSilence`,
/// `TokenBridge.emptyReadNote`, `FeedFreshness`'s three-miss floor). This
/// answers the one question that needs no tuning at all.
///
/// **And only one state is ever shown.** A 401/403 is unambiguous, actionable
/// and never heals on its own, so it is sticky and it is surfaced. Everything
/// else — 429, 5xx, a dead network — is transient by definition, so it is
/// recorded and shown to nobody: a marker that appears and disappears on its
/// own is the badge this was explicitly asked not to be (user, 2026-08-10:
/// "i don't want to have some badge on it for users").
enum BridgeHealth {

    struct Record: Codable {
        /// Last time this bridge answered with a 2xx.
        var lastOK: Date?
        /// The last status seen, whatever it was — diagnostic only, never a
        /// user-facing state on its own.
        var lastStatus: Int?
        /// When the CURRENT run of auth refusals began. Held at its first
        /// sighting rather than restamped, so the surface can say how long
        /// this has been broken rather than "just now" forever. nil = fine.
        var authFailedAt: Date?
    }

    private static let key = "bridge.health.v1"

    // MARK: - Recording

    /// Fold one response into the record. Called from `IngestSupport.send`,
    /// which is the single transport funnel for ~167 bridge call sites and
    /// already holds the `HTTPURLResponse` it was throwing away for everyone
    /// but the immediate caller — so this costs no new request anywhere.
    ///
    /// `named` is what the CALL SITE says it reached, used only when the host
    /// itself can't be attributed. Host attribution wins because it is the
    /// registry's answer rather than a caller's claim — the same order
    /// `NetworkLedger` already uses, deliberately reused rather than a second
    /// opinion that could disagree with the receipts screen.
    static func record(host: String?, status: Int, named: String?) {
        guard let bridge = owningBridge(host: host, named: named) else { return }
        var book = load()
        book[bridge] = folded(book[bridge] ?? Record(), status: status, now: .now)
        save(book)
    }

    /// The whole state machine, pure — one response folded into one record.
    ///
    /// Split out from the plumbing above so it can be compiled and
    /// mutation-tested with no stubs at all (`scripts/bridge-health-selftest.sh`).
    /// That matters more here than usual: no key for most of these bridges
    /// exists on any machine this is developed on, so there is no live path
    /// that can ever exercise a 401 — a harness is the only proof these three
    /// rules hold, and every way they can break is a silent wrong answer that
    /// renders as a perfectly ordinary tile.
    static func folded(_ record: Record, status: Int, now: Date) -> Record {
        var next = record
        next.lastStatus = status
        switch status {
        case 200...299:
            next.lastOK = now
            // A good read is the ONLY thing that clears the flag. Not a
            // timeout, not a retry, not app launch — being let back in.
            next.authFailedAt = nil
        case 401, 403:
            // Sticky, and FIRST SIGHTING WINS. Restamping on every pass would
            // make a month-old breakage read as a fresh one, which is exactly
            // backwards: the longer a bridge has been shut out, the more it
            // matters and the more certain it is that it will not self-heal.
            if next.authFailedAt == nil { next.authFailedAt = now }
        default:
            // Transient — 429, a 5xx, a dead network. Recorded for the probe,
            // shown to nobody. A marker that appears and disappears on its own
            // is the badge this feature was asked not to be.
            break
        }
        return next
    }

    /// Which seat owns this call. `NetworkReach` already maps host → service
    /// and declares which bridge owns each service, so this reads that
    /// registry rather than introducing a second mapping to keep in step.
    private static func owningBridge(host: String?, named: String?) -> String? {
        if let host, let service = NetworkReach.service(forHost: host),
           let bridge = NetworkReach.bridge(forService: service) {
            return bridge
        }
        // A host built from the person's own input (a followed feed, a
        // self-hosted PostHog) can never be in the registry — those call sites
        // name their service, and it counts only if the registry declares it,
        // the same guard `NetworkLedger` applies for the same reason.
        if let named, NetworkReach.declares(service: named) {
            return NetworkReach.bridge(forService: named)
        }
        return nil
    }

    // MARK: - Reading

    /// Since when has this bridge been refusing us? nil = it is fine, or we
    /// have never had a reason to think otherwise.
    ///
    /// Note what this deliberately does NOT answer: whether the bridge has
    /// landed anything, or whether it is quiet. See the type's own doc.
    static func needsReconnect(_ bridge: String) -> Date? {
        load()[bridge]?.authFailedAt
    }

    static func record(for bridge: String) -> Record? { load()[bridge] }

    /// Mark a bridge shut out when the refusal did NOT arrive as a 401 or 403.
    ///
    /// OAuth's token endpoint is the one place in this app where an auth
    /// refusal is spelled something else: RFC 6749 §5.2 reserves `400
    /// invalid_grant` for a refresh token that is expired, revoked, or was
    /// never ours. That is exactly the "unambiguous, actionable, never heals
    /// on its own" class `folded` makes sticky — arriving under a status
    /// `folded` is right to call transient for every REST bridge in the app.
    ///
    /// `lastStatus` is deliberately NOT written. It is the record of what the
    /// wire actually said, and stamping 401 over a 400 to reuse the state
    /// machine would put a number in the probe that no response ever carried.
    /// First sighting wins, for the reason it does in `folded`: the longer a
    /// bridge has been shut out the more it matters, and restamping would make
    /// a month-old breakage read as fresh.
    ///
    /// Nothing else clears this that doesn't already clear a 401 — a 2xx
    /// through the funnel, or `forget` when a new credential is pasted.
    static func markAuthRefused(_ bridge: String) {
        var book = load()
        let before = book[bridge] ?? Record()
        let after = markingAuthRefused(before, now: .now)
        guard after.authFailedAt != before.authFailedAt else { return }
        book[bridge] = after
        save(book)
    }

    /// The rule above, pure — one record, one refusal.
    ///
    /// Split from its plumbing for exactly the reason `folded` is, and the
    /// reason is sharper here: this is the SECOND writer of `authFailedAt`,
    /// and the harness could only see the first. A rule the proof cannot
    /// reach is a rule with no proof, and every way this one breaks is a
    /// silent wrong answer — a month-old breakage restamped as fresh, or a
    /// status written that no response ever carried.
    static func markingAuthRefused(_ record: Record, now: Date) -> Record {
        var next = record
        // First sighting wins, as in `folded`. And `lastStatus` and `lastOK`
        // are untouched on purpose: this refusal arrived under a status the
        // caller has already recorded truthfully, and overwriting it to reuse
        // the state machine would put a number in the probe that never came
        // off the wire.
        guard next.authFailedAt == nil else { return next }
        next.authFailedAt = now
        return next
    }

    /// The whole book, name-ordered — for the probe. Keyed by bridge name
    /// already, so nothing here needs the `BridgeStore` (which the probe hook
    /// table's `(String, ModelContext)` signature cannot hand it anyway).
    static func allRecords() -> [(bridge: String, record: Record)] {
        load().map { (bridge: $0.key, record: $0.value) }.sorted { $0.bridge < $1.bridge }
    }

    /// Everything currently shut out — for the probe, and for any surface that
    /// wants to speak about the set rather than one seat.
    static func allNeedingReconnect() -> [String] {
        load().compactMap { $0.value.authFailedAt == nil ? nil : $0.key }.sorted()
    }

    /// The status line a health-driven `.attention` wears. Spelled once and
    /// compared, because the reconcile below must only ever clear an attention
    /// state IT set — Photos, Obsidian and Files reach the same state for
    /// local-access reasons this knows nothing about, and healing those would
    /// be a lie told by the wrong file.
    static let attentionLine = String(localized: "Needs reconnecting — it stopped letting us in")

    /// Fold what the last sweep learned onto the seats' own status.
    ///
    /// Run at the START of a sweep, reflecting the PREVIOUS pass, and that is
    /// deliberate: this sweep's reads are staggered over seconds and have not
    /// happened yet when it begins, so reconciling at the end would report
    /// whatever the pass before it found anyway — one pass later, with a race
    /// in the middle. Reading last pass's settled result is the same
    /// information, honestly dated.
    @MainActor
    static func reconcile(store: BridgeStore) {
        let shutOut = Set(allNeedingReconnect())
        for bridge in store.bridges {
            let refusing = shutOut.contains(bridge.name)
            if refusing, bridge.status == .connected {
                store.markAttention(bridge.id, statusLine: attentionLine)
            } else if !refusing, bridge.status == .attention,
                      bridge.statusLine == attentionLine {
                // It let us back in. Only OUR line is cleared.
                store.reconnect(bridge.id, proof: String(localized: "Reconnected"))
            }
        }
    }

    /// Forget a bridge entirely. Called on connect and disconnect: pasting a
    /// new key is the person asserting the old refusal is over, and keeping
    /// the stale flag would tell them their fresh credential is broken before
    /// it has been used once.
    static func forget(_ bridge: String) {
        var book = load()
        guard book.removeValue(forKey: bridge) != nil else { return }
        save(book)
    }

    // MARK: - Storage

    // UserDefaults, the `FeedFreshness`/`X402State` shape — NOT a field on the
    // `Codable` bridge entry. Those decode with `try?` falling back to an EMPTY
    // list, and Swift's synthesized decoder does not apply defaults for a
    // missing key, so adding a field there silently unfollows every seat on
    // the device (measured, prd §312).
    private static func load() -> [String: Record] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let book = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return book
    }

    private static func save(_ book: [String: Record]) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
