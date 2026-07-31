import Foundation
import SwiftData

/// The EVIDENCE MARK behind a wallet-riding catalog seat (2026-07-30).
///
/// A handful of protocols in this app have no account and no key: Peer,
/// Privacy Pools, Gnosis Pay, Safe, Morpho, Hyperliquid, Aerodrome, Uniswap.
/// Watching a wallet is the whole consent (prd §207), and every one of their
/// sweeps runs unconditionally inside `WalletIngest.refresh` — the catalog
/// seat gates nothing, and never has since §207 took the connect switches
/// away. So a seat costs no requests at all; it is pure display.
///
/// Which leaves the only real question a seat has to answer honestly: **is
/// this protocol actually part of this person's life?** Most watched wallets
/// have never opened a Morpho position, held a veAERO lock, or touched Peer.
/// A seat reading "Aerodrome · watching 2 wallets" for someone who has never
/// used it is fake status, which the honesty rule forbids — and it's also a
/// worse showcase than the truth, because a seat that lights up the day your
/// first lock is seen is a moment, while one that's always on is wallpaper.
///
/// So each of these seats keeps a small mark: the watched wallets this
/// protocol has actually been seen at. `BridgeStore.reconcileWalletSeats()`
/// reads it, and reads nothing else — the mark is persisted precisely so
/// that reconciling (which runs on every foreground and on several screens'
/// `onAppear`) costs no network at all and can answer synchronously from a
/// view's body.
///
/// Two rules the sweeps must keep:
///
/// 1. **Stamp, never unstamp.** `remember` is called when a wallet's read
///    turns up something real; nothing calls `forget` except unwatching.
///    An empty read is not evidence of absence — a live-state read (`book()`)
///    returns an empty book for an unreachable host on some paths, and an
///    event read only ever sees the blocks since its cursor. Unstamping on
///    empty would make seats flap on a bad connection and vanish the week
///    someone closes a position they'll reopen.
/// 2. **The mark leaves with the watch.** Every owner calls `forget` from its
///    own `clearState`, which `WalletStore` already invokes on unwatch —
///    otherwise a seat stays lit for a wallet that's gone.
///
/// Addresses are stored lowercased hex, matching the resolved form every
/// sweep works in. This is deliberately the shape `GnosisPayBridge` invented
/// for itself on 2026-07-26 (`gnosispay.accounts`, an array of lowercased
/// addresses in `UserDefaults`); that bridge now reads through here against
/// its original key, so nothing needs migrating.
struct WalletSeatEvidence: Sendable {

    /// The `UserDefaults` key this mark persists under. Owned by the sweep,
    /// never reused — one protocol, one key.
    let key: String

    init(_ key: String) { self.key = key }

    /// The watched wallets this protocol has been seen at, lowercased.
    var addresses: [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }

    /// How many watched wallets carry this protocol — the number a seat's
    /// proof line states, and the gate `reconcileWalletSeats` reads.
    var count: Int { addresses.count }

    var isEmpty: Bool { count == 0 }

    /// Records that this protocol was really seen at `address`. Idempotent —
    /// every sweep calls it on every pass that finds something, so it must
    /// stay cheap and must not grow the array on a repeat.
    func remember(_ address: String) {
        let a = address.lowercased()
        var known = addresses
        guard !known.contains(a) else { return }
        known.append(a)
        UserDefaults.standard.set(known, forKey: key)
    }

    /// Drops a wallet's mark — called from each owner's `clearState` when the
    /// wallet is unwatched, never on an empty read (see rule 1 above).
    func forget(_ address: String) {
        let a = address.lowercased()
        let known = addresses
        guard known.contains(a) else { return }
        UserDefaults.standard.set(known.filter { $0 != a }, forKey: key)
    }

    /// One-time backfill from the corpus, for the EVENT-shaped sweeps only.
    ///
    /// A live-state sweep (Morpho, Hyperliquid, Aerodrome, Uniswap) reads the
    /// whole book every pass, so its mark stamps itself on the first refresh
    /// after this shipped — nothing to migrate. An event-shaped sweep does
    /// not: Peer and Privacy Pools read forward from a per-wallet block
    /// cursor, so for someone whose fills or deposits landed BEFORE the mark
    /// existed, the cursor has long since passed them and no future pass will
    /// ever see the evidence again. Their seat would go dark and stay dark —
    /// a real regression, since the protocol genuinely IS part of their life.
    ///
    /// The evidence is still on disk though, in the only place that outlives
    /// a cursor: the things themselves. Each carries the `walletAddress` it
    /// landed for, so one fetch reconstructs exactly what the mark would have
    /// recorded. Runs once per seat, ever.
    ///
    /// The flag is set only after a SUCCESSFUL fetch — a failed one must be
    /// allowed to retry next pass rather than permanently skipping the
    /// migration. A plain string-equality `#Predicate` is safe here; it's
    /// `.contains` on an array-typed attribute that traps inside SwiftData
    /// (see the CLAUDE.md gotcha), which this doesn't use.
    @MainActor
    func backfillFromCorpus(_ context: ModelContext, source: String) {
        let flag = key + ".backfilled"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        guard let landed = try? context.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        ) else { return }
        for thing in landed {
            guard thing.isLive, let wallet = thing.walletAddress, !wallet.isEmpty else { continue }
            remember(wallet)
        }
        UserDefaults.standard.set(true, forKey: flag)
    }
}
