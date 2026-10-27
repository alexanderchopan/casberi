import Foundation

/// **A SWAP TO ANOTHER NETWORK, ASKED AND WATCHED (prd §1555).** The one
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
    /// read; a refusal in Across's own words, drawn as theirs. A swap on
    /// arrival (`through`, prd §1565) is priced with its message's shape.
    static func acrossFees(_ asset: Across.Asset, from: Network, to: Network, amount: String,
                           account: String, through route: YourAccountSwap.Route? = nil) async throws -> Across.Fees {
        guard let url = Across.feesURL(asset, from: from.chainId, to: to.chainId, amount: amount, account: account,
                                       through: route, now: Int(Date().timeIntervalSince1970)) else {
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

    /// **A SWAP WHOSE TOKEN IS ON ANOTHER NETWORK.** ETH or the receiving
    /// network's dollar arrives as itself; any other token there is bought
    /// on arrival by that network's pools (prd §1565), from ETH when ETH is
    /// sold or nothing that crosses is, else from the dollar. What is sold,
    /// if it is not the asset that crosses, is swapped into it here first.
    /// The quote's calls are the swap's (if any), then the crossing's; what
    /// it buys is what Across's relayers pay, or for a swap on arrival what
    /// the receiving network's pools pay for exactly that, quoted now.
    static func crossQuote(_ net: Network, to dest: Network, sell: YourAccountOp.Token, buy: YourAccountOp.Token,
                           amount: String, account: String) async throws -> YourAccountSwap.Quote {
        let arrivesAsItself = Across.asset(of: buy, on: dest)
        let asset = arrivesAsItself ?? Across.asset(of: sell, on: net) ?? .eth
        guard Across.carries(asset, from: net.chainId, to: dest.chainId),
              arrivesAsItself != nil || (YourAccountSwap.supported(dest) && buy.contract != nil) else {
            throw Failure(message: String(localized: "Across does not carry \(buy.symbol) to \(dest.name)"))
        }
        let crossing = Across.token(asset, on: net)
        let landing = Across.token(asset, on: dest)
        let destBook = YourAccountSwap.book(dest.chainId)
        // The demo's estimate comes off its own prices (§1475), never Across.
        if YourAccountDemo.isDemo(account) {
            let bridged = sell == crossing ? amount : (YourAccountDemo.quote(sell: sell, buy: crossing, amount: amount)?.minimumBuy ?? "0")
            let out = YourAccountSwap.minimum(bridged, bps: 6) ?? "0"
            var leg = Across.Leg(asset: asset, from: net.chainId, to: dest.chainId, toName: dest.name, inputAmount: bridged,
                                 outputAmount: out, seconds: 10, fillDeadline: Int(Date().timeIntervalSince1970) + 7_200)
            if arrivesAsItself == nil, let destBook, let there = YourAccountDemo.quote(sell: landing, buy: buy, amount: out),
               let into = Across.bridged(asset, on: dest.chainId), let target = buy.contract?.lowercased(),
               let least = YourAccountSwap.minimum(there.buyAmount, bps: destBook.slippageBps) {
                let route = YourAccountSwap.Route(venue: destBook.venues[0], hops: [.init(from: into, to: target, step: 500)])
                leg.swap = Across.Arrival(route: route, buy: buy, quoted: there.buyAmount, minimum: least)
            }
            let got = leg.swap?.quoted ?? out, least = leg.swap?.minimum ?? out
            return YourAccountSwap.Quote(sellAmount: amount, buyAmount: got, minimumBuy: least, route: nil, calls: [], across: leg)
        }
        var swap: YourAccountSwap.Quote?
        if sell != crossing {
            swap = try await swapQuote(net, sell: sell, buy: crossing, amount: amount, account: account)
        }
        let bridged = swap?.minimumBuy ?? amount
        // A swap on arrival: its pools found for what is sent, so the fee
        // question carries the message's shape (prd §1565).
        var arrivalRoute: YourAccountSwap.Route?
        if arrivesAsItself == nil {
            guard let into = Across.bridged(asset, on: dest.chainId), let target = buy.contract?.lowercased(),
                  let found = try await bestRoute(dest, sell: into, buy: target, amount: bridged) else {
                throw Failure(message: String(localized: "No pool on \(dest.name) swaps \(landing.symbol) for \(buy.symbol)"))
            }
            arrivalRoute = found.route
        }
        let fees = try await acrossFees(asset, from: net, to: dest, amount: bridged, account: account, through: arrivalRoute)
        if fees.tooLow || fees.minDeposit.map({ !YourAccountOp.atMost($0, bridged) }) == true {
            let least = fees.minDeposit.map { YourAccountOp.spoken($0, decimals: crossing.decimals) } ?? "more"
            throw Failure(message: String(localized: "Too little for Across: at least \(least) \(crossing.symbol)"))
        }
        if let most = fees.maxDeposit, !YourAccountOp.atMost(bridged, most) {
            throw Failure(message: String(localized: "More than Across carries at once"))
        }
        var leg = Across.Leg(asset: asset, from: net.chainId, to: dest.chainId, toName: dest.name, inputAmount: bridged,
                             outputAmount: fees.outputAmount, seconds: fees.seconds, fillDeadline: fees.fillDeadline)
        guard Across.acceptable(leg, now: Int(Date().timeIntervalSince1970)) else {
            throw Failure(message: String(localized: "Across's fee is too high for this amount"))
        }
        // The swap there, quoted now for exactly what a relayer will pay.
        if arrivesAsItself == nil {
            guard let destBook, let into = Across.bridged(asset, on: dest.chainId), let target = buy.contract?.lowercased(),
                  let best = try await bestRoute(dest, sell: into, buy: target, amount: fees.outputAmount),
                  let least = YourAccountSwap.minimum(best.out, bps: destBook.slippageBps), YourAccountSwap.isPositive(least) else {
                throw Failure(message: String(localized: "No pool on \(dest.name) swaps \(landing.symbol) for \(buy.symbol)"))
            }
            leg.swap = Across.Arrival(route: best.route, buy: buy, quoted: best.out, minimum: least)
        }
        guard let crossCalls = Across.calls(leg, fees: fees, account: account) else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        return YourAccountSwap.Quote(sellAmount: amount, buyAmount: leg.swap?.quoted ?? fees.outputAmount,
                                     minimumBuy: leg.swap?.minimum ?? fees.outputAmount,
                                     route: swap?.route, calls: (swap?.calls ?? []) + crossCalls, across: leg)
    }

    /// **WHAT ARRIVES, PROVEN BEFORE FACE ID (prd §1555, §1565).** The
    /// handler's message run on the receiving network as a fill would run
    /// it — the handler holding what a relayer pays it (WETH it wraps from
    /// ETH given by a state override, or the dollar handed it by the
    /// SpokePool, which holds plenty), then the SpokePool's call into it —
    /// and the account's balance of what it should gain read around it: ETH
    /// for an unwrap, the token bought for a swap on arrival. True only if
    /// the account gains at least what is filled, or the swap's minimum (a
    /// swap that fell back pays the bridged token, never the one bought, so
    /// it reads false); nil when the node would not simulate.
    static func arrivalCheck(_ dest: Network, leg: Across.Leg, account: String) async -> Bool? {
        guard Across.viaHandler(leg), let into = Across.bridged(leg.asset, on: dest.chainId), let pool = Across.spoke(dest.chainId),
              let message = Across.message(for: leg, account: account),
              let amountWord = SafeABI.word(uint256: leg.outputAmount) else { return nil }
        let quantity: String = {
            let digits = SafeABI.hex(amountWord).dropFirst(2).drop { $0 == "0" }
            return "0x" + (digits.isEmpty ? "0" : String(digits))
        }()
        let read: [String: Any]
        let least: String
        if let s = leg.swap, let bought = s.buy.contract {
            read = ["to": bought, "data": SafeABI.hex(YourAccount.sel("balanceOf(address)") + YourAccount.w(account))]
            least = s.minimum
        } else {
            read = ["to": YourAccountSwap.multicall3,
                    "data": SafeABI.hex(YourAccount.sel("getEthBalance(address)") + YourAccount.w(account))]
            least = leg.outputAmount
        }
        let fund: [String: Any] = leg.asset == .eth
            ? ["from": Across.handler, "to": into, "value": quantity, "data": SafeABI.hex(YourAccount.sel("deposit()"))]
            : ["from": pool, "to": into,
               "data": SafeABI.hex(YourAccount.sel("transfer(address,uint256)") + YourAccount.w(Across.handler) + amountWord)]
        let handle = YourAccountSwap.call("handleV3AcrossMessage(address,uint256,address,bytes)",
                                          [.address(into), .word(amountWord), .address(pool), .bytes(message)])
        let calls: [[String: Any]] = [read, fund, ["from": pool, "to": Across.handler, "data": SafeABI.hex(handle)], read]
        let block: [String: Any] = ["calls": calls, "stateOverrides": [Across.handler: ["balance": quantity]]]
        // A node that would not simulate is unknown; a refused call is a no.
        guard let answer = try? await rpc(dest, "eth_simulateV1", [["blockStateCalls": [block], "validation": false], "latest"]),
              let results = (answer as? [[String: Any]])?.first?["calls"] as? [[String: Any]], results.count == 4
        else { return nil }
        guard results.allSatisfy({ ($0["status"] as? String) == "0x1" }),
              let before = (results[0]["returnData"] as? String).flatMap({ YourAccountOp.decimal(hexQuantity: String($0.prefix(66))) }),
              let after = (results[3]["returnData"] as? String).flatMap({ YourAccountOp.decimal(hexQuantity: String($0.prefix(66))) })
        else { return false }
        return YourAccountOp.atMost(least, YourAccountOp.difference(after, before))
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
            // Its id too, so the Wallet can meet its fill off chain (prd §1565).
            Across.update(c.id) { $0.relayHash = SafeABI.hex(h); $0.depositId = $0.depositId ?? Across.depositId(deposited) }
        }
        guard let hash, let hex = try? await ethCall(dest, to: pool, data: Across.fillStatusCall(hash)),
              let bytes = SafeABI.hexBytes(hex) else { return nil }
        return Across.fill(bytes)
    }
}
