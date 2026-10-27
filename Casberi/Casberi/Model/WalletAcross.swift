import Foundation
import SwiftData

/// **A SWAP TO ANOTHER NETWORK, AS ONE ROW IN ACTIVITY (prd §1555, the
/// user's design).** Each crossing this phone sent (`YourAccountAcross.
/// crossings`) is one Wallet thing, `wallet:across:<id>`, kept in step with
/// what is known of it: "USDC arriving on Base" while it waits, "Swapped
/// 0.02 ETH for USDC" once the receiving SpokePool says it was filled (read,
/// `YourAccountChain.acrossFill`) or the arrival is met, "Refunded 0.01 WETH
/// on Ethereum" when the refund is met. `WalletIngest` lands none of the
/// legs it is made of. The row is `AcrossCrossingRow`. A crossing another
/// phone of the account sent is read off chain into the same list
/// (`foldFromChain`, prd §1565), so it is one row here too.
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
            // What a refund returns (WETH for ETH) is listed in Move's
            // holdings from the deadline on (prd §1556).
            if let back = YourAccountAcross.returning(c, now: now),
               let net = YourAccountOp.networks.first(where: { $0.chainId == c.from }),
               !YourAccountTokens.remembered(on: net).contains(back) {
                YourAccountTokens.remember(back, on: net)
            }
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

    // MARK: - Read off chain (prd §1565)

    /// One leg the Wallet read this pass, as the fold off chain needs it.
    struct Seen: Sendable {
        let ref: String
        let hash: String
        let received: Bool
        let wallet: String
        let chainId: Int
        /// Lowercased; nil for the network's own coin.
        let contract: String?
        let symbol: String
        /// Who it went to (sent) or came from (received).
        let counterparty: String?
        let value: Double
        let at: Date?
    }

    /// How many receipts one pass reads to fold crossings off chain.
    static let receiptsPerPass = 8

    /// **A CROSSING FROM ANOTHER DEVICE IS ONE ROW TOO (prd §1565).** The
    /// phone that sent a crossing keeps a note of it; another phone of the
    /// same account has none, and saw two moves: a send to Across and, on
    /// another network, a receive. So the fold is read off chain, where both
    /// halves name the same deposit. A send to the sending network's pinned
    /// SpokePool that no note knows has its receipt read: the pool's own
    /// `FundsDeposited` with the account as depositor is the crossing, noted
    /// (`chainCrossing`). A receive on the network a crossing goes to, in its
    /// window, has its receipt read for the receiving pool's `FilledRelay` of
    /// that deposit (its network and id): that transaction is the fill, and
    /// every leg of it the crossing's (`arrived`, `fillTx`). The rest —
    /// waiting, filled, refunded — is the note's, as §1555 and §1556 have it.
    static func foldFromChain(_ legs: [Seen]) async {
        var list = YourAccountAcross.crossings
        var reads = 0
        func key(_ s: Seen) -> String { "\(s.wallet.lowercased())|\(s.chainId)|\(s.hash.lowercased())" }
        // The deposits: sends to a pinned SpokePool no crossing knows.
        let sends = Dictionary(grouping: legs.filter { !$0.received && !$0.hash.isEmpty }, by: key)
        for k in sends.keys.sorted() {
            guard reads < receiptsPerPass, let group = sends[k], let first = group.first,
                  let pool = YourAccountAcross.spoke(first.chainId),
                  group.contains(where: { $0.counterparty?.lowercased() == pool }),
                  !list.contains(where: { $0.from == first.chainId && $0.tx?.lowercased() == first.hash.lowercased() }),
                  let net = YourAccountOp.networks.first(where: { $0.chainId == first.chainId }) else { continue }
            reads += 1
            guard let receipt = try? await YourAccountChain.rpc(net, "eth_getTransactionReceipt", [first.hash]) as? [String: Any],
                  let logs = receipt["logs"] as? [[String: Any]],
                  let deposit = YourAccountAcross.deposited(logs, origin: first.chainId, account: first.wallet) else { continue }
            // A swap went first when something else left too: that is what was sold.
            let sold = group.filter { $0.counterparty?.lowercased() != pool }.max { $0.value < $1.value }
                .map { "\(WalletIngest.format($0.value)) \($0.symbol)" }
            guard let c = YourAccountAcross.chainCrossing(deposit, tx: first.hash, wallet: first.wallet, at: first.at ?? .now,
                                                          sold: sold),
                  !list.contains(where: { $0.id == c.id }) else { continue }
            YourAccountAcross.note(c)
            list = YourAccountAcross.crossings
            #if DEBUG
            NSLog("acrossFold| deposit %@ %@→%@ id=%@", first.hash, YourAccountAcross.networkName(c.from),
                  YourAccountAcross.networkName(c.to), c.depositId ?? "-")
            #endif
        }
        // The fills: receives where a crossing whose deposit is known goes,
        // in its window; Across's own contracts first, then what it was to buy.
        func waits(_ s: Seen) -> YourAccountAcross.Crossing? {
            list.first { x in
                x.account == s.wallet.lowercased() && x.to == s.chainId && x.depositId != nil && x.fillTx == nil
                    && x.state != .refunded
                    && (s.at.map { $0 >= x.at.addingTimeInterval(-10 * 60) && $0 <= x.at.addingTimeInterval(YourAccountAcross.matchWindow) } ?? true)
            }
        }
        let receives = Dictionary(grouping: legs.filter { $0.received && !$0.hash.isEmpty }, by: key)
        func rank(_ k: String) -> (Int, Int, Date) {
            let g = receives[k] ?? []
            let across = g.contains { $0.counterparty.map(YourAccountAcross.isAcross) == true } ? 0 : 1
            let x = g.first.flatMap(waits)
            let named = g.contains { $0.contract == x?.contract || $0.contract == x?.fallbackContract } ? 0 : 1
            return (across, named, g.first?.at ?? .distantFuture)
        }
        for k in receives.keys.sorted(by: { rank($0) < rank($1) }) {
            guard reads < receiptsPerPass, let group = receives[k], let first = group.first, waits(first) != nil,
                  let net = YourAccountOp.networks.first(where: { $0.chainId == first.chainId }) else { continue }
            reads += 1
            guard let receipt = try? await YourAccountChain.rpc(net, "eth_getTransactionReceipt", [first.hash]) as? [String: Any],
                  let logs = receipt["logs"] as? [[String: Any]] else { continue }
            for f in YourAccountAcross.filled(logs, dest: first.chainId) {
                guard let x = YourAccountAcross.crossing(filledBy: f, dest: first.chainId, in: list) else { continue }
                let got = group.map { YourAccountAcross.Received(contract: $0.contract, symbol: $0.symbol, value: $0.value) }
                YourAccountAcross.update(x.id) { YourAccountAcross.arrived(&$0, received: got, fillTx: first.hash, at: first.at) }
                list = YourAccountAcross.crossings
                #if DEBUG
                NSLog("acrossFold| fill %@ for %@", first.hash, x.id)
                #endif
            }
        }
    }

    /// The crossing a row is, by its ref.
    static func crossing(of thing: Thing) -> YourAccountAcross.Crossing? {
        guard let ref = thing.sourceRef, ref.hasPrefix(YourAccountAcross.refPrefix) else { return nil }
        let id = String(ref.dropFirst(YourAccountAcross.refPrefix.count))
        return YourAccountAcross.crossings.first { $0.id == id }
    }
}
