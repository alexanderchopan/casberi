import Foundation
import SwiftData

/// One transaction, one row (2026-08-01, prd §271).
///
/// The wallet-riding seats — Railgun, Privacy Pools, Peer, Gnosis Pay — read
/// protocols whose activity IS an ordinary token transfer. So on any chain the
/// generic wallet sweep also covers, the same transaction landed twice: once as
/// `Sent 1.2 WETH` under `Wallet`, and once as `Shielded 1.2 WETH into Railgun`
/// under `Railgun`, both pointing at the same explorer link, with nothing to
/// collapse them (`SyncReconcile.dedupeBySourceRef` can't — the refs are
/// namespaced per source, so they're legitimately different rows).
///
/// This shipped with 0xBow Privacy Pools and went unnoticed for weeks, because
/// its deposits are rare enough that the pair rarely appeared side by side.
/// Railgun made it obvious. Peer and Gnosis Pay escaped only by living on
/// chains the wallet sweep doesn't read.
///
/// **The labelled row wins, always.** It says everything the generic one does
/// plus what the transaction MEANT, which is the entire reason the seat
/// exists. A person who sees both learns nothing from the second and has to
/// work out that they aren't two separate movements of money.
///
/// Two halves, and both are needed — either alone flaps:
///
///  1. `coveredContent` is consulted by the wallet sweep BEFORE it lands a leg,
///     so a transaction a seat already owns never lands generically again.
///  2. `prune` removes the generic rows already sitting in the corpus — the
///     backlog, plus the ones that land in the same pass as their labelled
///     twin (the sweep runs before the seats do, so on the pass a shield first
///     appears the generic row is written before anything knows better).
///
/// Without (1), (2) would delete a row the next refresh re-lands, forever.
/// Without (2), the pair that arrives together this pass would never separate.
///
/// Matching is on the EXPLORER URL alone, deliberately — the same key the
/// adjacent Zerion-cutover guard in `WalletIngest.refresh` already uses, and
/// the same tolerance: a transaction carrying several legs loses all of its
/// generic rows to one labelled one. That is the right trade here. These
/// protocols move one asset per transaction in practice, and the failure it
/// risks (one fewer row) is far cheaper than the failure a finer key risks
/// (matching on a re-formatted amount string, and silently suppressing
/// nothing).
enum WalletRowSupersede {

    /// The seats whose rows describe a transaction the generic wallet sweep
    /// would otherwise also land. A seat belongs here only if its `content` is
    /// an explorer transaction URL — Privacy Pools' status ALERTS point at
    /// 0xbow.io and simply never match, which is correct and needs no special
    /// case.
    static let sources: Set<String> = ["Railgun", "Privacy Pools", "Peer", "Gnosis Pay"]

    /// Every explorer URL a labelled seat has claimed.
    ///
    /// Cheap by construction: these seats land RARE events (a shield, a
    /// deposit, a fill, a card spend), so this fetch is small where a scan of
    /// `Wallet` rows would not be — which is why the lookup runs in this
    /// direction rather than the obvious one.
    @MainActor
    static func coveredContent(_ context: ModelContext) -> Set<String> {
        var out = Set<String>()
        for source in sources {
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source })
            guard let rows = try? context.fetch(descriptor) else { continue }
            for row in rows where row.isLive && !row.content.isEmpty {
                out.insert(row.content)
            }
        }
        return out
    }

    /// Deletes generic `Wallet` rows whose transaction a labelled seat owns.
    /// Returns how many went. Call AFTER the seats have run in a pass.
    @MainActor
    @discardableResult
    static func prune(_ context: ModelContext, covered: Set<String>) -> Int {
        guard !covered.isEmpty else { return 0 }
        var removed = 0
        // One predicate fetch per claimed URL rather than one scan of every
        // wallet row: `covered` is small, the corpus is not, and string
        // equality is the one predicate shape that's safe to push down here
        // (the CLAUDE.md trap is `.contains` on an array-typed attribute).
        for url in covered {
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == "Wallet" && $0.content == url })
            guard let rows = try? context.fetch(descriptor) else { continue }
            let doomed = rows.filter(\.isLive)
            guard !doomed.isEmpty else { continue }
            // Drop them from Spotlight before the models die — reading `id`
            // off a deleted Thing is the trap the liveness rules exist for.
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for row in doomed {
                context.delete(row)
                removed += 1
            }
        }
        if removed > 0 { _ = context.saveHonestly() }
        return removed
    }
}
