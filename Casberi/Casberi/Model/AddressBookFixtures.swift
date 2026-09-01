import Foundation

/// The demo's own addresses, withheld from iCloud (2026-09-01, prd §549).
///
/// **The bug this closes shipped, and it reached real people.** `WalletStore`
/// has had a fixture rail since it started mirroring — `syncSnapshot` withholds
/// fixture addresses, `applyMerged` sweeps any that arrive over the wire on an
/// install not entitled to hold them — and the address book, which mirrors
/// through the very same `KeyValueMirror`, had none: `syncSnapshot` was a bare
/// `{ entries }`. So the demo is a SHIPPED feature (the onboarding CTA and the
/// Settings row both enter it), `DemoMode.pourIfNeeded` reaches
/// `DemoSeedAll.seedAddressBook` through `seedBridgeStateForDemo`, and every
/// `setName` pushes — meaning anyone who tapped "Try the demo" with iCloud sync
/// on wrote Sam, Mia, Coinbase, Stripe, Bitrefill, Uniswap, Peer, Gnosis Pay
/// and "Session key" into their iCloud and onto their other devices.
///
/// **Why that is worse than the ~400 demo rows `DemoMode` already accepts.**
/// That cost is written down and bounded by the standing banner: the demo says
/// what it is, on the device running it. `DemoMode.isActive` is per-device
/// state, so the SECOND device wears no banner — and there a fake contact is
/// not a demo, it is a name in your address book that you did not type. That is
/// exactly the §83 fake status the honesty rule bans, on the screen where a
/// wrong name is most expensive.
///
/// **Derived, never re-typed.** Every address here comes from the constant that
/// SEEDS it, so the rail and the seed cannot drift — the same rule
/// `demoFacedParties` and `demoWallets` already keep for the teardown. A
/// hand-copied list would go stale the first time a counterparty is added, and
/// a stale rail fails silently in the leaking direction.
///
/// **`keepsFixtures` is `WalletStore`'s, not a second copy.** One question
/// ("is this build or session entitled to hold fixtures at all"), one answer;
/// two spellings would eventually disagree, and then one store would sweep what
/// the other kept.
extension AddressBook {

    /// Every address the demo or a DEBUG seed can put in the book, folded to
    /// the same key `entries` is keyed by.
    static let fixtureKeys: Set<String> = {
        var out = Set(WalletStore.fixtureAddresses.map { key(for: $0) })
        for party in DemoSeedAll.demoCounterparties {
            out.insert(key(for: DemoSeedAll.counterpartyAddress(for: party.name)))
        }
        for address in DemoSeedAll.demoVibenetWatches { out.insert(key(for: address)) }
        out.insert(key(for: DemoSeedAll.demoVibenetKeySigner))
        return out
    }()

    static func isFixture(_ address: String) -> Bool {
        fixtureKeys.contains(key(for: address))
    }

    /// Whether THIS build/session may hold fixtures — a debug install that
    /// seeds them, or a demo actually running. Everywhere else they are litter,
    /// whether this device seeded them or another device sent them.
    static var keepsFixtures: Bool { WalletStore.keepsFixtures }
}
