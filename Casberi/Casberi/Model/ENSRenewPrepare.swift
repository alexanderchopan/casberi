import Foundation
import SwiftData

/// The reads behind the renew card (2026-08-31, prd §540) — `ENSRenew` is the
/// pure half and this is the half that talks to a chain.
///
/// Every call is a keyless JSON-RPC READ on the mainnet hosts
/// `WalletApprovals` already measured and `NetworkReach` already declares — no
/// new host, no key, and nothing here can move funds. What it produces is a
/// quote and a payload; a signature happens in the person's own wallet
/// (§112).
enum ENSRenewPrepare {

    /// `.eth` is on Ethereum mainnet and nowhere else.
    static let network = "eth-mainnet"

    struct Quote: Equatable {
        let name: String
        let label: String
        let term: ENSRenew.Term
        /// What the controller says the term costs, as of this read.
        let price: ENSRenew.Price
        /// Base plus `ENSRenew.bufferPercent`, which is what `value` carries.
        let payableWei: Double
        /// "~0.0004 ETH" — the network fee, nil when it couldn't be read.
        /// Never invented; the card simply omits the line.
        let feeLine: String?
        /// The wallet-ready payload. nil when there is no address to send
        /// FROM — a transaction without a sender is not a transaction, and a
        /// "Copy" button that yields a broken object is the dead control §83
        /// bans. The ENS door still works in that case.
        let transactionJSON: String?
        /// ENS's own app, at this name. The primary door: they ship a real
        /// renewal UI, so unlike the approval card's Revoke.cash hand-off this
        /// one lands somebody exactly where the act happens.
        let ensURL: String
    }

    /// The cheap gate, checked before any network read is spent.
    ///
    /// Renewing is only the act in two of the ladder's rungs. Before
    /// `.expiring` there is nothing to do for years and a card would be noise;
    /// once `.released` the name is gone and `renew` REVERTS — the call for a
    /// released name is `register`, at a different price, with a premium, and
    /// this app does not do that. Offering "Renew" there would be a control
    /// that takes money and fails.
    static func applies(to thing: Thing) -> Bool {
        guard thing.isLive,
              thing.source == ENSWatch.source,
              let ref = thing.sourceRef,
              let name = ENSName.name(fromRef: ref),
              ENSName.label(of: name) != nil,
              let reading = ENSState.reading(name),
              !reading.unregistered
        else { return false }
        switch ENSName.stage(expiry: reading.expiry) {
        case .expiring, .grace: return true
        case .active, .premium, .released, .unregistered: return false
        }
    }

    /// Prices one term and prepares the transaction. `from` is the address the
    /// renewal would be sent from — the newest watched wallet, or nil.
    ///
    /// MainActor like `WalletPrepare.outcome`: the model reads stay on main
    /// and only the RPC awaits hop off.
    @MainActor
    static func quote(name: String, term: ENSRenew.Term, from: String?) async -> Quote? {
        guard let label = ENSName.label(of: name),
              let priceData = ENSRenew.priceCalldata(label: label, term: term)
        else { return nil }

        guard let hex = await WalletApprovals.rpcRead(
                network: network, method: "eth_call",
                params: [["to": ENSRenew.controller, "data": priceData], "latest"]) as? String,
              // The reply is a two-word `Price` struct. A revert or an empty
              // reply is "0x", which would parse to a price of ZERO — free
              // renewal, shown to somebody about to sign. Fail CLOSED: no
              // card at all rather than a number we did not read
              // (`WalletPrepare`'s lesson 2, and it costs more here).
              hex.count >= 2 + 64 * 2
        else { return nil }
        let clean = String(hex.dropFirst(2))
        let base = WalletIngest.hexToDouble("0x" + clean.prefix(64))
        let premium = WalletIngest.hexToDouble("0x" + clean.dropFirst(64).prefix(64))
        guard base > 0 else { return nil }

        let payable = ENSRenew.payable(base: base)
        let json = from.flatMap {
            ENSRenew.transactionJSON(from: $0, label: label, term: term, base: base)
        }

        // The fee. Two independent reads, awaited together — one round trip's
        // wait, not two. `eth_estimateGas` doubles as a dry run: a renewal
        // that would revert fails the estimate, so a quoted fee also means
        // "this would go through".
        var feeLine: String?
        if let from, let data = ENSRenew.calldata(label: label, term: term) {
            async let gasRead = WalletApprovals.rpcRead(
                network: network, method: "eth_estimateGas",
                params: [["from": from, "to": ENSRenew.controller,
                          "data": data, "value": ENSRenew.weiHex(payable)]])
            async let priceRead = WalletApprovals.rpcRead(
                network: network, method: "eth_gasPrice", params: [])
            if let gasHex = await gasRead as? String,
               let gasPriceHex = await priceRead as? String {
                let fee = WalletIngest.hexToDouble(gasHex)
                    * WalletIngest.hexToDouble(gasPriceHex) / 1e18
                if fee > 0 { feeLine = "~" + ENSRenew.ethLine(fee * 1e18) }
            }
        }

        return Quote(name: name, label: label, term: term,
                     price: ENSRenew.Price(base: base, premium: premium),
                     payableWei: payable, feeLine: feeLine,
                     transactionJSON: json,
                     ensURL: "https://app.ens.domains/\(name)")
    }

    /// Does a watched wallet hold this name? Decides one sentence on the card
    /// — see `ENSRenew.ownershipNote`.
    ///
    /// Answered from the corpus, never a fresh read: `ENSExpiry` only ever
    /// lands a `wallet:ensexpiry:` row for a name one of the watched addresses
    /// resolves to, so the row's own existence IS the evidence, and asking the
    /// chain again on every card open would buy nothing.
    ///
    /// **A false answer here is one-directional on purpose.** Unknown reads as
    /// "not yours", which shows the ownership warning to somebody who may in
    /// fact own the name — a redundant sentence. The other way round hides it
    /// from somebody about to pay for a stranger's name.
    @MainActor
    static func isYours(name: String, context: ModelContext) -> Bool {
        let walletRef = ENSName.walletRef(for: name)
        let count = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == walletRef }))) ?? 0
        if count > 0 { return true }
        // The seat ADOPTS a wallet-found row on follow (`ENSWatch.follow`), so
        // a name that arrived that way no longer HAS a `wallet:ensexpiry:` row
        // to find — the adoption records it on the reading instead.
        return ENSState.reading(name)?.fromWallet == true
    }

    /// The address a renewal would be sent from — the newest watched wallet.
    /// nil when nothing is watched, which is a real and ordinary state: the
    /// card still prices the renewal and still opens ENS.
    @MainActor
    static func sender() -> String? {
        WalletStore.shared.addresses.first(where: { ENS.isHexAddress($0.address) })?.address
    }

    /// `-ensRenewProbe "<name>"` — the whole path for one followed name, fact
    /// by fact, spending no signature and raising no prompt.
    ///
    /// It exists because a missing renew card has SIX causes that render as
    /// one empty space, and only two are bugs: the name isn't followed, its
    /// reading hasn't landed yet, it is nowhere near expiring, it has already
    /// been released, the price read didn't answer, or the controller moved.
    /// The `price=` line is what separates the last two from the rest.
    @MainActor
    static func probe(name raw: String, context: ModelContext) async -> [String] {
        guard let name = ENSName.normalized(raw) else { return ["ensRenew| not a .eth name: \(raw)"] }
        var out: [String] = []
        let reading = ENSState.reading(name)
        let stage = ENSName.stage(expiry: reading?.expiry)
        out.append("ensRenew| name=\(name) label=\(ENSName.label(of: name) ?? "?")"
                   + " stage=\(stage.rawValue) read=\(reading == nil ? "never" : "yes")")
        out.append("ensRenew| controller=\(ENSRenew.controller) renewSel=0x\(ENSRenew.renewSelector)")
        let ref = ENSName.ref(for: name)
        let row = try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref })).first
        let applicable = row.map { applies(to: $0) } ?? false
        out.append("ensRenew| followed=\(row != nil ? "YES" : "NO") cardWouldShow=\(applicable ? "YES" : "NO")"
                   + " yours=\(isYours(name: name, context: context) ? "YES" : "NO")")
        let from = sender()
        out.append("ensRenew| from=\(from ?? "none (no watched wallet)")")
        for term in ENSRenew.Term.allCases {
            if let q = await quote(name: name, term: term, from: from) {
                out.append("ensRenew| term=\(term.rawValue)y base=\(ENSRenew.ethLine(q.price.base))"
                           + " premium=\(ENSRenew.ethLine(q.price.premium))"
                           + " pay=\(ENSRenew.ethLine(q.payableWei))"
                           + " fee=\(q.feeLine ?? "unread")"
                           + " tx=\(q.transactionJSON.map { "\($0.count) chars" } ?? "none")")
            } else {
                out.append("ensRenew| term=\(term.rawValue)y PRICE UNREADABLE")
            }
        }
        return out
    }
}
