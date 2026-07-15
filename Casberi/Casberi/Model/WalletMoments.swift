import Foundation
import Observation

/// The wallet's own delight bus (2026-07-15) — the sibling of the starred-repo
/// major-release rain (MainSurface's arrival watcher). NFTs and holdings never
/// land as things (prd §72: a treemap cell / NFT strip is a door, not a thing),
/// so they can't ride the corpus-arrival detector that fires the release rain.
/// Instead the data paths that already fetch them (WalletIngest.nftsByWallet,
/// WalletStore.recordSample) call in here when they spot something worth
/// marking; MainSurface observes `pulse` and deals the berry rain + names the
/// moment in a toast. One surface, so every wallet celebration looks like the
/// release one.
///
/// Detection is deliberately honest and quiet on the first sight of anything:
/// the first NFT read seeds the seen-set silently (no "you received 40 NFTs"
/// on connect), and the first value sample seeds the high-water mark silently
/// (a baseline isn't a new high). Only genuine NEW arrivals and NEW highs fire.
@MainActor
@Observable
final class WalletMoments {
    static let shared = WalletMoments()

    /// Bumped for each moment — MainSurface hangs the berry rain off it and
    /// drains `pending`.
    private(set) var pulse = 0
    /// Queued moment lines, oldest first — a QUEUE, not a single slot, so two
    /// moments in one pass (an NFT arrival AND a new high) don't collapse to
    /// one, and a moment fired while backgrounded survives until MainSurface
    /// next drains on foreground (SwiftUI defers the onChange while inactive).
    private(set) var pending: [String] = []

    private init() {}

    /// A moment worth marking — the caller has already decided it's real.
    func fire(_ text: String) {
        pending.append(text)
        pulse += 1
    }

    /// MainSurface takes the queued lines and clears them (rain once, show the
    /// most recent line). Returns [] when nothing is pending.
    func drain() -> [String] {
        defer { pending.removeAll() }
        return pending
    }

    // MARK: - NFT arrivals

    private static let seenNFTKey = "wallet.seenNFTs"
    private static let baselinedKey = "wallet.nftBaselined"

    /// Given every watched wallet's current NFTs, returns the pieces that are
    /// NEW since the last look and folds them into the persisted seen-set.
    ///
    /// Baselining is PER WALLET, not global (the fix for a partial first read):
    /// a wallet that 429'd on the first-ever pass — so it contributed no group
    /// — isn't marked baselined, and when it later succeeds its whole holding
    /// seeds SILENTLY instead of dumping as dozens of false "arrivals". Only a
    /// wallet already baselined fires for ids it hasn't seen. Empty when no
    /// wallet returned anything (a total fetch miss must never touch the set).
    func newlyArrived(from groups: [WalletIngest.NFTGroup])
        -> [(label: String, nft: WalletIngest.WalletNFT)] {
        guard !groups.isEmpty else { return [] }

        let defaults = UserDefaults.standard
        var seen = Set(defaults.stringArray(forKey: Self.seenNFTKey) ?? [])
        var baselined = Set(defaults.stringArray(forKey: Self.baselinedKey) ?? [])

        var fresh: [(label: String, nft: WalletIngest.WalletNFT)] = []
        var currentSet = Set<String>()
        for g in groups {
            let addr = g.address.lowercased()
            let alreadyBaselined = baselined.contains(addr)
            for nft in g.nfts {
                let key = seenKey(address: g.address, nft: nft)
                currentSet.insert(key)
                if alreadyBaselined, !seen.contains(key) {
                    fresh.append((g.label, nft))
                }
            }
            baselined.insert(addr)   // this wallet has now been seen once
        }
        seen.formUnion(currentSet)

        // Keep a bound so the set can't grow without end — but always retain
        // the CURRENT ids first, so trimming a whale's huge history can never
        // drop a piece you still hold and then re-celebrate it next pass.
        let older = seen.subtracting(currentSet)
        let merged = Array(currentSet) + Array(older.prefix(max(0, 2000 - currentSet.count)))
        defaults.set(merged, forKey: Self.seenNFTKey)
        defaults.set(Array(baselined), forKey: Self.baselinedKey)
        return fresh
    }

    private func seenKey(address: String, nft: WalletIngest.WalletNFT) -> String {
        "\(address.lowercased())|\(nft.id)"
    }

    // MARK: - High-water marks

    private static func highKey(_ scope: String) -> String { "wallet.high.\(scope)" }

    /// Records a value for a scope ("combined", or a wallet address) and
    /// returns true when it's a genuine NEW high above the stored mark. The
    /// FIRST value for a scope seeds the mark silently and returns false — a
    /// baseline is not a high. A drop never fires (asymmetric by design: a
    /// new high earns a moment, a drawdown earns only the honest red pill on
    /// the line). A tiny epsilon guards against a re-high on the same value.
    func notedNewHigh(scope: String, value: Double) -> Bool {
        guard value > 0 else { return false }
        let key = Self.highKey(scope)
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            defaults.set(value, forKey: key)
            return false
        }
        let prev = defaults.double(forKey: key)
        guard value > prev * 1.0001 else {
            // Still update the stored mark on a genuine rise below the fire
            // threshold isn't needed; only ever raise it on a real new high.
            return false
        }
        defaults.set(value, forKey: key)
        return true
    }
}
