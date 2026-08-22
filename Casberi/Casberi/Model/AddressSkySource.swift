import Foundation
import SwiftData

/// What the sky reads (prd §435) — the SwiftData/UserDefaults half, kept apart
/// from `AddressSky` so the layout stays Foundation-only and harness-compilable
/// (the `AddressConnections`/`AddressConnectionsSource` split, one file over).
///
/// Nothing here computes a position. It gathers who is watched, who connects to
/// whom (straight from `AddressConnections`, so the sky and the spine can never
/// disagree about what "connected" means), how each address is filed, and which
/// connections have appeared since the last time this screen was looked at.
enum AddressSkySource {

    /// The connections we have already shown, so a new one can draw itself
    /// LAST and dashed rather than arriving pre-existing.
    ///
    /// A flat UserDefaults set, the `X402State` shape — not a `Thing` field: a
    /// "have you seen this" mark is a fact about this device's own screen, not
    /// about the corpus, and a new stored property is a CloudKit Production
    /// deploy (docs/cloudkit-deploy.md) for something that must not sync
    /// anyway. Seeing it on the iPhone should not make it old on the Mac.
    private static let seenKey = "wallet.sky.seen.v1"

    /// Capped so a long-lived book can't grow this without bound. The cap is
    /// far above `AddressConnections.nodeLimit`, so it can never evict a
    /// connection that is currently drawn.
    private static let seenCap = 200

    static func seen() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
    }

    /// Marks every currently-connected address as seen. Called when the sky
    /// has actually been on screen — never at build time, or a connection
    /// would be new for exactly as long as it took to compose the view and
    /// never draw itself as new at all.
    ///
    /// **First sight seeds SILENTLY.** On a device that has never opened this
    /// screen, every connection is "new", which would draw the whole sky dashed
    /// and announce a year of history as today's news — the Hyperliquid
    /// first-sight bug (2026-07-30) in a new room. `markSeen` is therefore also
    /// called on the very first composition, before anything is flagged; see
    /// `sky(context:)`.
    static func markSeen(_ keys: [String]) {
        var all = seen()
        all.formUnion(keys)
        // Oldest-first is not knowable here (a set has no order), so an
        // over-cap book keeps an arbitrary but STABLE slice: sorted, truncated.
        // The consequence of evicting a key is one connection reading as new
        // once more, which is the harmless direction.
        let capped = all.count > seenCap ? Array(all.sorted().prefix(seenCap)) : Array(all)
        UserDefaults.standard.set(capped, forKey: seenKey)
    }

    /// Forgets what has been seen — for the demo teardown and for a book that
    /// has been emptied, where leaving the marks would silence the first
    /// connection of the NEXT book.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    /// Builds the sky over the live corpus, or nil when there isn't one.
    ///
    /// Returns nil for exactly the reasons `AddressSky.layout` and
    /// `AddressConnections.map` already return nil — fewer than two watched
    /// wallets — so the manager's fallback has one condition, not three.
    @MainActor
    static func sky(context: ModelContext) -> AddressSky.Sky? {
        let store = WalletStore.shared
        let book = AddressBook.shared
        let watched = store.addresses.map { addr in
            AddressSky.Wallet(key: AddressBook.key(for: addr.address),
                              address: addr.address,
                              name: store.displayName(for: addr))
        }
        guard watched.count >= AddressSky.minWallets else { return nil }

        // The SAME reading the spine draws — `AddressConnections` decides what
        // connected means (a landed transfer, two or more of your wallets, no
        // inference) and this only re-dresses it. Building a second definition
        // here is how a map and a card start disagreeing about the same book.
        let map = AddressConnections.map(context: context)
        let nodes = map?.nodes ?? []

        // FIRST SIGHT: nothing has ever been marked, so everything would be
        // new. Seed the whole set silently and draw the sky as settled.
        let alreadySeen = seen()
        let firstSight = alreadySeen.isEmpty && !nodes.isEmpty
        if firstSight { markSeen(nodes.map(\.id)) }

        let connected = nodes.map { node in
            AddressSky.Connected(
                key: node.id,
                address: node.address,
                name: node.name,
                walletKeys: node.walletKeys,
                groups: book.entry(for: node.address)?.groupNames ?? [],
                isNew: !firstSight && !alreadySeen.contains(node.id))
        }
        return AddressSky.layout(watched: watched,
                                 connected: connected,
                                 canWatchMore: store.canWatchMore)
    }
}
