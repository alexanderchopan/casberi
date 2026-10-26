import Foundation
import SwiftData

/// **A SWAP TO ANOTHER NETWORK, AS ONE ROW IN ACTIVITY (prd §1553, the
/// user's design).** Each crossing this phone sent (`YourAccountAcross.
/// crossings`) is one Wallet thing, `wallet:across:<id>`, kept in step with
/// what is known of it: "USDC arriving on Base" while it waits, "Swapped
/// 0.02 ETH for USDC" once the receiving SpokePool says it was filled (read,
/// `YourAccountChain.acrossFill`) or the arrival is met, "Refunded 0.01 WETH
/// on Ethereum" when the refund is met. `WalletIngest` lands none of the
/// legs it is made of. The row is `AcrossCrossingRow`.
@MainActor
enum WalletAcross {
    /// How many waiting crossings a pass asks about: each is one or two reads.
    static let askPerPass = 4

    /// Reads what waits, then writes every crossing's row. Returns how many
    /// rows were added.
    @discardableResult
    static func sync(context: ModelContext) async -> Int {
        let cutoff = Date().addingTimeInterval(-YourAccountAcross.unsentAfter)
        var list = YourAccountAcross.crossings
        // A note that never got its transaction (Face ID cancelled, the send
        // refused) is no crossing.
        let unsent = list.filter { $0.tx == nil && $0.at < cutoff }.map(\.id)
        if !unsent.isEmpty {
            YourAccountAcross.save(list.filter { !unsent.contains($0.id) })
            list = YourAccountAcross.crossings
        }
        guard !list.isEmpty, !YourAccountDemo.isOn else { return 0 }
        for c in list.filter({ $0.state == .waiting && $0.tx != nil }).suffix(askPerPass) {
            if await YourAccountChain.acrossFill(c) == .filled {
                YourAccountAcross.update(c.id) { x in
                    if x.state == .waiting { x.state = .filled; x.settledAt = .now }
                }
            }
        }
        list = YourAccountAcross.crossings
        let now = Int(Date().timeIntervalSince1970)
        var added = 0
        for c in list where c.tx != nil {
            let ref = YourAccountAcross.ref(c)
            let thing = existing(ref, context) ?? {
                let t = Thing(kind: .transaction, title: YourAccountAcross.title(c),
                              content: explorer(c.from).map { $0 + (c.tx ?? "") } ?? "",
                              source: "Wallet", capturedAt: c.at, sourceRef: ref)
                t.walletAddress = c.account
                context.insert(t)
                added += 1
                return t
            }()
            let title = YourAccountAcross.title(c)
            let line = YourAccountAcross.line(c, now: now)
            let tags = ["Across", c.state.rawValue]
            if thing.title != title { thing.title = title }
            if thing.summary != line { thing.summary = line }
            if thing.tags != tags { thing.tags = tags }
            // The row stands where it settled; waiting, where it was sent.
            let when = c.settledAt ?? c.at
            if thing.capturedAt != when { thing.capturedAt = when }
        }
        _ = context.saveHonestly()
        return added
    }

    private static func existing(_ ref: String, _ context: ModelContext) -> Thing? {
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func explorer(_ chainId: Int) -> String? {
        switch chainId {
        case 1: "https://etherscan.io/tx/"
        case 8453: "https://basescan.org/tx/"
        case 4663: "https://robinhoodchain.blockscout.com/tx/"
        default: nil
        }
    }

    /// The crossing a row is, by its ref.
    static func crossing(of thing: Thing) -> YourAccountAcross.Crossing? {
        guard let ref = thing.sourceRef, ref.hasPrefix(YourAccountAcross.refPrefix) else { return nil }
        let id = String(ref.dropFirst(YourAccountAcross.refPrefix.count))
        return YourAccountAcross.crossings.first { $0.id == id }
    }
}
