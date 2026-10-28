import Foundation
import SwiftData

/// The reads behind the renew card (2026-08-31, prd §540; stablecoins since
/// ENSv2, prd §1585) — `ENSRenew` is the pure half and this is the half that
/// talks to a chain.
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
        /// Which contract will take this renewal, as the chain said at quote
        /// time.
        let contract: ENSRenew.Contract
        /// What it is paid in: the first token the sender holds enough of,
        /// else USDC.
        let token: ENSRenew.Token
        /// What `renew` will pull, exactly as the chain wrote it.
        let amount: ENSRenew.Amount
        /// false when the sender holds less than `amount` of every accepted
        /// token — the renewal would revert. nil when there is no sender to
        /// ask about.
        let covered: Bool?
        /// The allowance is short, so the wallet approves `amount` first.
        let needsApproval: Bool
        /// "~0.0004 ETH" — the network fee, nil when it couldn't be read.
        /// Never invented; the card simply omits the line.
        let feeLine: String?
        /// The wallet-ready payload (`ENSRenew.handoffJSON`). nil when there is
        /// no address to send FROM — a "Copy" yielding a broken object is the
        /// dead control §83 bans. The ENS door still works in that case.
        let transactionJSON: String?
        /// ENS's own app, at this name. The primary door: they ship a real
        /// renewal UI, so this lands somebody exactly where the act happens.
        let ensURL: String
    }

    /// The cheap gate, checked before any network read is spent.
    ///
    /// Renewing is only the act in two of the ladder's rungs. Before
    /// `.expiring` there is nothing to do for years and a card would be noise;
    /// once `.released` the name is gone and `renew` REVERTS
    /// (`NameNotRenewable`) — the call for a released name is `register`, at a
    /// different price, with a premium, and this app does not do that.
    static func applies(to thing: Thing) -> Bool {
        guard thing.isLive,
              thing.source == ENSWatch.source,
              let ref = thing.sourceRef,
              let name = ENSName.name(fromRef: ref),
              ENSName.label(of: name) != nil,
              let reading = ENSState.reading(name),
              !reading.unregistered
        else { return false }
        switch ENSName.stage(expiry: reading.expiry, migrated: reading.isMigrated) {
        case .expiring, .grace: return true
        case .active, .premium, .released, .unregistered: return false
        }
    }

    /// Prices one term and prepares the transactions. `from` is the address
    /// the renewal would be sent from — the newest watched wallet, or nil.
    ///
    /// MainActor like `WalletPrepare.outcome`: the model reads stay on main
    /// and only the RPC awaits hop off.
    @MainActor
    static func quote(name: String, term: ENSRenew.Term, from: String?) async -> Quote? {
        guard let label = ENSName.label(of: name),
              let contract = await renewingContract(label: label)
        else { return nil }

        // Every accepted token's price, and the sender's balance of each, at
        // once. A token whose price read fails is not offered: a missing
        // price is never read as zero (`Amount(reply:)` refuses "0x").
        var prices: [ENSRenew.Token: ENSRenew.Amount] = [:]
        var balances: [ENSRenew.Token: ENSRenew.Amount] = [:]
        await withTaskGroup(of: (ENSRenew.Token, Bool, ENSRenew.Amount?).self) { group in
            for token in ENSRenew.Token.allCases {
                group.addTask {
                    (token, true, await read(to: contract.address,
                                             ENSRenew.priceCalldata(label: label, term: term, token: token)))
                }
                if let from {
                    group.addTask {
                        (token, false, await read(to: token.address, ENSRenew.balanceCalldata(owner: from)))
                    }
                }
            }
            for await (token, isPrice, amount) in group {
                guard let amount else { continue }
                if isPrice { prices[token] = amount } else { balances[token] = amount }
            }
        }

        let priced = ENSRenew.Token.allCases.filter { prices[$0].map { !$0.isZero } ?? false }
        let payable = priced.first { token in
            guard let balance = balances[token], let price = prices[token] else { return false }
            return price <= balance
        }
        guard let token = payable ?? priced.first, let amount = prices[token] else { return nil }
        // "Covered" only from a read of every priced token's balance; a
        // balance that did not answer is not a shortfall.
        let covered: Bool? = from == nil ? nil
            : payable != nil ? true
            : priced.allSatisfy { balances[$0] != nil } ? false : nil

        // No sender, no allowance to ask about: nothing to approve from.
        var needsApproval = from != nil
        if let from, let allowance = await read(
            to: token.address, ENSRenew.allowanceCalldata(owner: from, spender: contract)) {
            needsApproval = allowance < amount
        }

        // The fee, and a dry run in one: `eth_estimateGas` fails for a
        // renewal that would revert. Asked only when the renewal could run as
        // it stands — with an approval still to send, the estimate reverts on
        // the missing allowance, and a fee for the approval alone would be a
        // number for half the purchase.
        var feeLine: String?
        if let from, !needsApproval, covered == true,
           let data = ENSRenew.calldata(label: label, term: term, token: token) {
            async let gasRead = WalletApprovals.rpcRead(
                network: network, method: "eth_estimateGas",
                params: [["from": from, "to": contract.address, "data": data]])
            async let priceRead = WalletApprovals.rpcRead(
                network: network, method: "eth_gasPrice", params: [])
            if let gasHex = await gasRead as? String,
               let gasPriceHex = await priceRead as? String {
                let fee = WalletIngest.hexToDouble(gasHex) * WalletIngest.hexToDouble(gasPriceHex)
                if fee > 0 { feeLine = "~" + ENSRenew.ethLine(fee) }
            }
        }

        // No hand-off the chain would refuse: a wallet short of every token
        // would pay gas for the approval and then revert on the renewal.
        let json = covered == false ? nil : from.flatMap {
            ENSRenew.handoffJSON(from: $0, contract: contract, label: label, term: term,
                                 token: token, amount: amount, needsApproval: needsApproval)
        }
        return Quote(name: name, label: label, term: term, contract: contract,
                     token: token, amount: amount, covered: covered,
                     needsApproval: needsApproval, feeLine: feeLine,
                     transactionJSON: json,
                     ensURL: "https://app.ens.domains/\(name)")
    }

    /// The one contract whose `isRenewable` says yes. nil when neither does
    /// (a released name, a read that failed) and when both do, which the two
    /// sources make impossible: a card naming the wrong contract is a
    /// transaction that reverts after the approval was paid for.
    private static func renewingContract(label: String) async -> ENSRenew.Contract? {
        guard let data = ENSRenew.isRenewableCalldata(label: label) else { return nil }
        async let renewer = read(to: ENSRenew.Contract.renewer.address, data)
        async let registrar = read(to: ENSRenew.Contract.registrar.address, data)
        let yes = [(ENSRenew.Contract.renewer, await renewer), (.registrar, await registrar)]
            .filter { $0.1.map { !$0.isZero } ?? false }
        return yes.count == 1 ? yes[0].0 : nil
    }

    private static func read(to: String, _ data: String?) async -> ENSRenew.Amount? {
        guard let data,
              let hex = await WalletApprovals.rpcRead(
                network: network, method: "eth_call",
                params: [["to": to, "data": data], "latest"]) as? String
        else { return nil }
        return ENSRenew.Amount(reply: hex)
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
    /// It exists because a missing renew card has several causes that render
    /// as one empty space: the name isn't followed, its reading hasn't landed,
    /// it is nowhere near expiring, it has been released, neither contract
    /// says it is renewable, or no price answered. `contract=` and `price=`
    /// separate the last two from the rest.
    @MainActor
    static func probe(name raw: String, context: ModelContext) async -> [String] {
        guard let name = ENSName.normalized(raw) else { return ["ensRenew| not a .eth name: \(raw)"] }
        var out: [String] = []
        let reading = ENSState.reading(name)
        let stage = ENSName.stage(expiry: reading?.expiry, migrated: reading?.isMigrated ?? false)
        out.append("ensRenew| name=\(name) label=\(ENSName.label(of: name) ?? "?")"
                   + " stage=\(stage.rawValue) read=\(reading == nil ? "never" : "yes")")
        let ref = ENSName.ref(for: name)
        let row = try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref })).first
        let applicable = row.map { applies(to: $0) } ?? false
        out.append("ensRenew| followed=\(row != nil ? "YES" : "NO") cardWouldShow=\(applicable ? "YES" : "NO")"
                   + " yours=\(isYours(name: name, context: context) ? "YES" : "NO")")
        guard ENSRenew.prepares else {
            out.append("ensRenew| prepares=NO — the sheet shows Renew on ENS, no price or transaction")
            return out
        }
        let from = sender()
        out.append("ensRenew| from=\(from ?? "none (no watched wallet)")")
        for term in ENSRenew.Term.allCases {
            if let q = await quote(name: name, term: term, from: from) {
                out.append("ensRenew| term=\(term.rawValue)y contract=\(q.contract.rawValue)"
                           + " price=\(ENSRenew.tokenLine(q.amount, q.token))"
                           + " covered=\(q.covered.map { $0 ? "YES" : "NO" } ?? "unknown")"
                           + " approve=\(q.needsApproval ? "YES" : "NO")"
                           + " fee=\(q.feeLine ?? "unread")"
                           + " tx=\(q.transactionJSON.map { "\($0.count) chars" } ?? "none")")
            } else {
                out.append("ensRenew| term=\(term.rawValue)y NOT RENEWABLE OR PRICE UNREADABLE")
            }
        }
        return out
    }
}
