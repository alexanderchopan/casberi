import Foundation

/// **A SWAP TO ANOTHER NETWORK, ASKED AND WATCHED (prd §1553).** The one
/// thing Across is asked is its fee (`suggested-fees`, through the same
/// funnel and Tor as every read of the account's, measured answering
/// through Tor); the calls are `YourAccountAcross`'s, written here on the
/// phone. A token that does not cross itself is first swapped on the
/// sending network into one that does, by the pools (§1542), in the same
/// transaction, and only the swap's minimum crosses: what the pools pay
/// over it stays on the sending network.
///
/// After it lands, the fill is READ, never guessed: the deposit's own log
/// in the sending transaction's receipt gives its relay hash, and the
/// receiving SpokePool's `fillStatuses` says whether a relayer has paid it.
extension YourAccountChain {
    typealias Across = YourAccountAcross

    /// Across's fee for `amount` of `asset` from one network to another,
    /// read; a refusal in Across's own words, drawn as theirs.
    static func acrossFees(_ asset: Across.Asset, from: Network, to: Network, amount: String,
                           account: String) async throws -> Across.Fees {
        guard let url = Across.feesURL(asset, from: from.chainId, to: to.chainId, amount: amount, account: account) else {
            throw Failure(message: String(localized: "Across does not carry this from \(from.name) to \(to.name)"))
        }
        guard let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account") else {
            throw Failure(message: String(localized: "Across did not answer"))
        }
        let json = try? JSONSerialization.jsonObject(with: data)
        guard http.statusCode == 200, let fees = Across.fees(json, from: from.chainId) else {
            let said = (json as? [String: Any])?["message"] as? String
            throw said.map { Failure(message: $0, from: "Across") } ?? Failure(message: String(localized: "Across did not answer"))
        }
        return fees
    }

    /// **A SWAP WHOSE TOKEN IS ON ANOTHER NETWORK.** What arrives must be
    /// ETH or the receiving network's dollar; what is sold, if it is not the
    /// asset that crosses, is swapped into it here first. The quote's calls
    /// are the swap's (if any), then the crossing's; what it buys is exactly
    /// what Across's relayers pay.
    static func crossQuote(_ net: Network, to dest: Network, sell: YourAccountOp.Token, buy: YourAccountOp.Token,
                           amount: String, account: String) async throws -> YourAccountSwap.Quote {
        guard let asset = Across.asset(of: buy, on: dest), Across.carries(asset, from: net.chainId, to: dest.chainId) else {
            throw Failure(message: String(localized: "Across does not carry \(buy.symbol) to \(dest.name)"))
        }
        let crossing = Across.token(asset, on: net)
        // The demo's estimate comes off its own prices (§1475), never Across.
        if YourAccountDemo.isDemo(account) {
            let bridged = sell == crossing ? amount : (YourAccountDemo.quote(sell: sell, buy: crossing, amount: amount)?.minimumBuy ?? "0")
            let out = YourAccountSwap.minimum(bridged, bps: 6) ?? "0"
            let leg = Across.Leg(asset: asset, from: net.chainId, to: dest.chainId, toName: dest.name, inputAmount: bridged,
                                 outputAmount: out, seconds: 10, fillDeadline: Int(Date().timeIntervalSince1970) + 7_200)
            return YourAccountSwap.Quote(sellAmount: amount, buyAmount: out, minimumBuy: out, route: nil, calls: [], across: leg)
        }
        var swap: YourAccountSwap.Quote?
        if sell != crossing {
            swap = try await swapQuote(net, sell: sell, buy: crossing, amount: amount, account: account)
        }
        let bridged = swap?.minimumBuy ?? amount
        let fees = try await acrossFees(asset, from: net, to: dest, amount: bridged, account: account)
        if fees.tooLow || fees.minDeposit.map({ !YourAccountOp.atMost($0, bridged) }) == true {
            let least = fees.minDeposit.map { YourAccountOp.spoken($0, decimals: crossing.decimals) } ?? "more"
            throw Failure(message: String(localized: "Too little for Across: at least \(least) \(crossing.symbol)"))
        }
        if let most = fees.maxDeposit, !YourAccountOp.atMost(bridged, most) {
            throw Failure(message: String(localized: "More than Across carries at once"))
        }
        let leg = Across.Leg(asset: asset, from: net.chainId, to: dest.chainId, toName: dest.name, inputAmount: bridged,
                             outputAmount: fees.outputAmount, seconds: fees.seconds, fillDeadline: fees.fillDeadline)
        guard Across.acceptable(leg, now: Int(Date().timeIntervalSince1970)) else {
            throw Failure(message: String(localized: "Across's fee is too high for this amount"))
        }
        guard let crossCalls = Across.calls(leg, fees: fees, account: account) else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        return YourAccountSwap.Quote(sellAmount: amount, buyAmount: fees.outputAmount, minimumBuy: fees.outputAmount,
                                     route: swap?.route, calls: (swap?.calls ?? []) + crossCalls, across: leg)
    }

    /// **ETH ARRIVES AS ETH, PROVEN BEFORE FACE ID.** The handler's message
    /// run on the receiving network as a fill would run it — the handler
    /// holding the WETH a relayer pays it (the ETH it wraps given by a state
    /// override), then the SpokePool's call into it — and the account's ETH
    /// read around it. True only if the account gains at least what is
    /// filled; nil when the node would not simulate.
    static func arrivalCheck(_ dest: Network, leg: Across.Leg, account: String) async -> Bool? {
        guard leg.asset == .eth, let weth = YourAccountSwap.book(dest.chainId)?.weth, let pool = Across.spoke(dest.chainId),
              let message = Across.message(to: dest.chainId, amount: leg.outputAmount, account: account),
              let amountWord = SafeABI.word(uint256: leg.outputAmount) else { return nil }
        let quantity: String = {
            let digits = SafeABI.hex(amountWord).dropFirst(2).drop { $0 == "0" }
            return "0x" + (digits.isEmpty ? "0" : String(digits))
        }()
        let read: [String: Any] = ["to": YourAccountSwap.multicall3,
                                   "data": SafeABI.hex(YourAccount.sel("getEthBalance(address)") + YourAccount.w(account))]
        let handle = YourAccountSwap.call("handleV3AcrossMessage(address,uint256,address,bytes)",
                                          [.address(weth), .word(amountWord), .address(pool), .bytes(message)])
        let calls: [[String: Any]] = [
            read,
            ["from": Across.handler, "to": weth, "value": quantity, "data": SafeABI.hex(YourAccount.sel("deposit()"))],
            ["from": pool, "to": Across.handler, "data": SafeABI.hex(handle)],
            read,
        ]
        let block: [String: Any] = ["calls": calls, "stateOverrides": [Across.handler: ["balance": quantity]]]
        // A node that would not simulate is unknown; a refused call is a no.
        guard let answer = try? await rpc(dest, "eth_simulateV1", [["blockStateCalls": [block], "validation": false], "latest"]),
              let results = (answer as? [[String: Any]])?.first?["calls"] as? [[String: Any]], results.count == 4
        else { return nil }
        guard results.allSatisfy({ ($0["status"] as? String) == "0x1" }),
              let before = (results[0]["returnData"] as? String).flatMap({ YourAccountOp.decimal(hexQuantity: String($0.prefix(66))) }),
              let after = (results[3]["returnData"] as? String).flatMap({ YourAccountOp.decimal(hexQuantity: String($0.prefix(66))) })
        else { return false }
        return YourAccountOp.atMost(leg.outputAmount, YourAccountOp.difference(after, before))
    }

    /// **WHETHER IT HAS ARRIVED, READ.** The relay hash first (once, off the
    /// sending transaction's receipt, kept on the note), then the receiving
    /// SpokePool's `fillStatuses`. Nil when either network did not answer.
    static func acrossFill(_ c: Across.Crossing) async -> Across.Fill? {
        guard let tx = c.tx, let origin = YourAccountOp.networks.first(where: { $0.chainId == c.from }),
              let dest = YourAccountOp.networks.first(where: { $0.chainId == c.to }),
              let pool = Across.spoke(c.to) else { return nil }
        var hash = c.relayHash.flatMap(SafeABI.hexBytes)
        if hash == nil {
            guard let receipt = try? await rpc(origin, "eth_getTransactionReceipt", [tx]) as? [String: Any],
                  let logs = receipt["logs"] as? [[String: Any]],
                  let deposited = Across.deposited(logs, origin: c.from, account: c.account) else { return nil }
            let h = Across.relayHash(deposited)
            hash = h
            Across.update(c.id) { $0.relayHash = SafeABI.hex(h) }
        }
        guard let hash, let hex = try? await ethCall(dest, to: pool, data: Across.fillStatusCall(hash)),
              let bytes = SafeABI.hexBytes(hex) else { return nil }
        return Across.fill(bytes)
    }
}
