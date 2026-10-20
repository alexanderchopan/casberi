import Foundation

/// **YOUR ACCOUNT'S SWAP, THROUGH RELAY (prd §1440, replacing §1430's CoW).**
/// One provider for every network the account is on (user, 2026-10-19:
/// "lets switch"; "don't ship on cow"): Relay's keyless API quotes a swap and
/// hands back the transactions that do it — for ETH sold, one call to Relay's
/// router; for a token sold, an exact `approve` to Relay's approval proxy and
/// one call to it. The account signs those calls in its own operation, beside
/// any sends, so Add batches swaps as before.
///
/// Relay's route is packed bytes this phone cannot read, so nothing here
/// trusts it on its word:
///
/// 1. **Where it goes.** Every call must go to Relay's router or approval
///    proxy, pinned below from Relay's own `/chains` (measured 2026-10-19 on
///    Base, Ethereum and Robinhood Chain: the same addresses on each), or be
///    the sold token's own `approve` naming one of them.
/// 2. **How much.** ETH sent is exactly the amount sold; a token approved is
///    exactly the amount sold, never more.
/// 3. **What comes back** is proven by `YourAccountChain` before Face ID: the
///    whole operation is simulated (`eth_simulateV1`) and refused unless every
///    swap pays the account at least its quoted minimum.
///
/// Pure (Foundation, `SafeABI`); the requests are `YourAccountChain`'s.
enum YourAccountSwap {
    /// Relay's v3 and v3.2 router and approval proxy, the same on every chain
    /// Relay settles on (its `/chains`, read 2026-10-19).
    static let routers: Set<String> = [
        "0xb92fe925dc43a0ecde6c8b1a2709c170ec4fff4f", "0x0729e2a4716d9f7dd17858d5d504426d228697f7",
    ]
    static let approvalProxies: Set<String> = [
        "0xccc88a9d1b4ed6b0eaba998850414b24f1c315be", "0x5567954cd026cebfe486062cb75848e0f1c12e58",
    ]

    /// Relay's word for the network's own coin.
    static let native = "0x0000000000000000000000000000000000000000"

    /// Where the account swaps: Base and Ethereum. Never a test network.
    static func supported(_ network: YourAccountOp.Network) -> Bool {
        !network.isTest && (network.chainId == 8453 || network.chainId == 1)
    }

    static func currency(_ token: YourAccountOp.Token) -> String {
        token.contract?.lowercased() ?? native
    }

    // MARK: - The quote

    struct Call: Equatable, Sendable {
        let to: String
        let value: String
        let data: [UInt8]
    }

    struct Quote: Equatable, Sendable {
        /// What is sold, all of it.
        let sellAmount: String
        /// What Relay says comes back.
        let buyAmount: String
        /// At least this comes back, or the swap is refused before Face ID.
        let minimumBuy: String
        /// Relay's own fee, in the sold token's units ("0" when it charged it
        /// in something else).
        let fee: String
        let requestId: String?
        /// The calls that do it, as Relay gave them, checked by `checked`.
        let calls: [Call]
    }

    /// Relay's quote, read strictly: transaction steps only (a step asking
    /// for a signature is refused), every call on `chainId`, amounts plain
    /// digits. nil for anything else.
    static func quote(from json: [String: Any], chainId: Int, sell: YourAccountOp.Token) -> Quote? {
        guard let steps = json["steps"] as? [[String: Any]], !steps.isEmpty,
              let details = json["details"] as? [String: Any],
              let inn = details["currencyIn"] as? [String: Any],
              let out = details["currencyOut"] as? [String: Any],
              let sold = inn["amount"] as? String, sold.allSatisfy(\.isNumber),
              let back = out["amount"] as? String, back.allSatisfy(\.isNumber),
              let least = out["minimumAmount"] as? String, least.allSatisfy(\.isNumber)
        else { return nil }
        var calls: [Call] = []
        for step in steps {
            guard (step["kind"] as? String) == "transaction", let items = step["items"] as? [[String: Any]] else { return nil }
            for item in items {
                guard let d = item["data"] as? [String: Any],
                      let to = d["to"] as? String, SafeABI.word(address: to) != nil,
                      let hex = d["data"] as? String, let data = SafeABI.hexBytes(hex),
                      (d["chainId"] as? Int).map({ $0 == chainId }) ?? true else { return nil }
                let value = (d["value"] as? String) ?? "0"
                guard value.allSatisfy(\.isNumber) else { return nil }
                calls.append(Call(to: to.lowercased(), value: value.isEmpty ? "0" : value, data: data))
            }
        }
        var fee = "0"
        if let relayer = (json["fees"] as? [String: Any])?["relayer"] as? [String: Any],
           let amount = relayer["amount"] as? String, amount.allSatisfy(\.isNumber),
           let address = (relayer["currency"] as? [String: Any])?["address"] as? String,
           address.lowercased() == currency(sell) {
            fee = amount
        }
        return Quote(sellAmount: sold, buyAmount: back, minimumBuy: least, fee: fee,
                     requestId: json["requestId"] as? String ?? (steps.first?["requestId"] as? String),
                     calls: calls)
    }

    // MARK: - The check

    static let approveSelector: [UInt8] = [0x09, 0x5e, 0xa7, 0xb3]

    /// The quote's calls, if every one is Relay's and moves exactly what is
    /// sold; nil with the reason otherwise. An `approve` is returned apart, so
    /// a batch can approve each token once for the sum it sells.
    static func checked(_ quote: Quote, sell: YourAccountOp.Token, amount: String)
        -> (approvals: [(token: String, spender: String, amount: String)], calls: [Call])? {
        guard quote.sellAmount == amount else { return nil }
        var approvals: [(String, String, String)] = []
        var calls: [Call] = []
        for call in quote.calls {
            if call.data.starts(with: approveSelector) {
                // approve(spender, amount) on the sold token, to Relay's proxy,
                // for exactly what is sold.
                guard let contract = sell.contract?.lowercased(), call.to == contract, call.value == "0",
                      call.data.count == 4 + 64,
                      let spender = address(fromWord: Array(call.data[4..<36])),
                      approvalProxies.contains(spender) || routers.contains(spender),
                      SafeCalldata.decimal(Array(call.data[36..<68])) == amount else { return nil }
                approvals.append((contract, spender, amount))
                continue
            }
            guard routers.contains(call.to) || approvalProxies.contains(call.to) else { return nil }
            // ETH leaves only when ETH is sold, and only the amount sold.
            if sell.contract == nil {
                guard call.value == amount || call.value == "0" else { return nil }
            } else {
                guard call.value == "0" else { return nil }
            }
            calls.append(call)
        }
        // Selling ETH must send it once; selling a token must approve it.
        if sell.contract == nil {
            guard calls.contains(where: { $0.value == amount }) else { return nil }
        } else {
            guard approvals.count == 1 else { return nil }
        }
        return (approvals, calls)
    }

    private static func address(fromWord word: [UInt8]) -> String? {
        guard word.count == 32, word[0..<12].allSatisfy({ $0 == 0 }) else { return nil }
        return SafeABI.hex(Array(word[12..<32])).lowercased()
    }

    /// Every swap's approvals, once per token and spender for the sum: an
    /// `approve` replaces an allowance, so two would leave the first swap
    /// short (the rule §1436 set for CoW, kept).
    static func approvalCalls(_ approvals: [(token: String, spender: String, amount: String)]) -> [YourAccount.Call]? {
        var order: [String] = []
        var sums: [String: (token: String, spender: String, amount: String)] = [:]
        for a in approvals {
            let key = a.token + "|" + a.spender
            if let have = sums[key] {
                sums[key] = (a.token, a.spender, YourAccountOp.sum(have.amount, a.amount))
            } else {
                order.append(key)
                sums[key] = a
            }
        }
        var out: [YourAccount.Call] = []
        for key in order {
            guard let a = sums[key], let amount = SafeABI.word(uint256: a.amount), let zero = SafeABI.word(uint256: "0")
            else { return nil }
            out.append(.init(operation: 0, to: a.token,
                             value: zero, data: approveSelector + YourAccount.w(a.spender) + amount))
        }
        return out
    }

    /// A checked call as one of the account's own.
    static func accountCall(_ call: Call) -> YourAccount.Call? {
        guard let value = SafeABI.word(uint256: call.value) else { return nil }
        return .init(operation: 0, to: call.to, value: value, data: call.data)
    }
}
