import Foundation

/// **RECEIVE ON BASE OR ROBINHOOD, EARN ON ETHEREUM (prd §1878).** A receive
/// address is a plain address, good on every EVM network, so people pay it
/// on Base and Robinhood too. ETH found there is sent home: the address's
/// own Across deposit to itself on Ethereum (`FreshTx.homeDeposit`), its gas
/// out of what arrived. Once it lands there, the Ethereum look moves it into
/// your private balance as it moves anything paid there.
///
/// - **Only when it will move on.** What Across delivers must reach what
///   Ethereum's look would move (the pool's least plus that deposit's gas,
///   today), and Across may keep at most 5%; otherwise nothing leaves.
/// - **Kept before it goes.** The deposit's hash is kept before the node is
///   asked; while it is out nothing new is sent from that network for that
///   address, and the next look asks the chain.
/// - **A deposit Across does not fill is refunded where it left**, to the
///   address, as WETH: the address holds it and nothing more is done (said
///   in the log; the row stays).
/// - ETH only: a token there would need ETH for its own approval.
extension FreshReceive {

    /// A deposit home that is out, by "<entry id>@<chain>".
    struct HomeSent: Codable, Equatable {
        let tx: String
        let at: Date
        let amount: String
        let network: String
    }

    private static let homeKey = "freshAddresses.home.v1"

    static var homeSent: [String: HomeSent] {
        UserDefaults.standard.data(forKey: homeKey)
            .flatMap { try? JSONDecoder().decode([String: HomeSent].self, from: $0) } ?? [:]
    }

    private static func keepHome(_ key: String, _ sent: HomeSent?) {
        var book = homeSent
        book[key] = sent
        guard let data = try? JSONEncoder().encode(book) else { return }
        DefaultsWrite.set(data, forKey: homeKey)
    }

    /// Your own account's node for that network, the first it lists.
    private static func node(_ chainId: Int) -> String? {
        YourAccountOp.networks.first { $0.chainId == chainId }?.rpcs.first
    }

    /// One look at `entry` on Base and on Robinhood.
    func lookHome(_ entry: FreshAddress.Entry, network: PrivacyNetwork) async {
        guard entry.network == FreshTx.homeChain, let root = entry.root, !network.isTest else { return }
        for origin in FreshTx.homeOrigins {
            guard !Task.isCancelled, let node = Self.node(origin.chainId) else { continue }
            let key = "\(entry.id)@\(origin.chainId)"
            if let sent = Self.homeSent[key] {
                await resolveHome(key, sent: sent, node: node, origin: origin, entry: entry)
                continue
            }
            guard let raw = try? await PrivateRPC.call(at: node, named: origin.name, "eth_getBalance", [entry.address, "latest"]) as? String
            else { continue }
            let eth = PrivateMoney.decimal(hex: raw)
            // The dollar first, while the address's ETH pays its gas (prd §1880);
            // the ETH left is looked at next time.
            let dollar = await Self.tokenBalance(origin.dollar, of: entry.address, node: node, name: origin.name)
            if dollar != "0" {
                await sendDollarHome(entry, root: root, held: dollar, eth: eth, origin: origin, node: node, network: network, key: key)
                continue
            }
            homeNeedsGas[entry.id] = nil
            guard eth != "0" else { continue }
            await sendHome(entry, root: root, balance: eth, origin: origin, node: node, network: network, key: key)
        }
    }

    /// `balanceOf(owner)` of `token` on `node`, base units ("0" when unread).
    private static func tokenBalance(_ token: String, of owner: String, node: String, name: String) async -> String {
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
        let answer = (try? await PrivateRPC.call(at: node, named: name, "eth_call", [["to": token, "data": data], "latest"])) as? String
        return answer.flatMap { PrivateYield.word($0, 0) } ?? "0"
    }

    /// `allowance(owner, spender)` of `token` on `node`, base units.
    private static func allowance(_ token: String, owner: String, spender: String, node: String, name: String) async -> String {
        let data = "0xdd62ed3e" + String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
            + String(repeating: "0", count: 24) + spender.dropFirst(2).lowercased()
        let answer = (try? await PrivateRPC.call(at: node, named: name, "eth_call", [["to": token, "data": data], "latest"])) as? String
        return answer.flatMap { PrivateYield.word($0, 0) } ?? "0"
    }

    /// The gas a dollar's approval and its home deposit may use there (the
    /// deposit carries the proof's call, so it is heavier than ETH's).
    static let dollarApproveGas = 80_000
    static let dollarDepositGas = 400_000

    /// **A DOLLAR GOES HOME INTO THE POOL (prd §1880).** All of it leaves in
    /// one Across deposit whose message runs the ppUSDC deposit this phone
    /// proves for what arrives: what arrives is what was paid less half
    /// again Across's fee (the headroom §1574 measured fills need). Its
    /// approval first, if the SpokePool may not take it yet. Gas from the
    /// address's own ETH there; with too little, it waits, and Receive says so.
    private func sendDollarHome(_ entry: FreshAddress.Entry, root: String, held: String, eth: String, origin: FreshTx.HomeOrigin,
                                node: String, network: PrivacyNetwork, key: String) async {
        do {
            let price = UInt64(PrivateMoney.decimal(hex: try await PrivateRPC.call(at: node, named: origin.name, "eth_gasPrice", []) as? String ?? "0x0")) ?? 0
            let tipRaw = (try? await PrivateRPC.call(at: node, named: origin.name, "eth_maxPriorityFeePerGas", [])) as? String
            let fees = TestnetTx.fees(gasPrice: price, tip: UInt64(PrivateMoney.decimal(hex: tipRaw ?? "0x0")) ?? 0)
            let allowed = await Self.allowance(origin.dollar, owner: entry.address, spender: origin.spoke, node: node, name: origin.name)
            let approving = (Decimal(string: allowed) ?? 0) < (Decimal(string: held) ?? 0)
            let gasNeeded = Decimal((approving ? Self.dollarApproveGas : 0) + Self.dollarDepositGas) * Decimal(fees.maxFee)
            guard (Decimal(string: eth) ?? 0) >= gasNeeded else {
                homeNeedsGas[entry.id] = "\(origin.dollarSymbol)|\(origin.name)"
                NSLog("freshAddress| home dollar | %@ | %u | %@ %@ waits for gas | holds %@ wei, needs %@", origin.name, entry.index,
                      held, origin.dollarSymbol, eth, PrivateMoney.plain(gasNeeded))
                return
            }
            homeNeedsGas[entry.id] = nil
            guard let pool = network.yield.first(where: { !$0.native }), let least = await minimumBudget(pool, on: network),
                  let h = Decimal(string: held), h >= (Decimal(string: least) ?? 0) else {
                NSLog("freshAddress| home dollar | %@ | %u | %@ under the pool's least", origin.name, entry.index, held)
                return
            }
            // A first proof for a guess, to price the message's fill; then
            // the budget from Across's fee, proved again if it moved.
            var budget = PrivateMoney.plain(h * Decimal(string: "0.99")!).components(separatedBy: ".")[0]
            var proved = try await PrivateOnEthereum.bridgedDeposit(budget: budget)
            guard let router = FreshTx.homeRouter, let first = await quoteDollar(origin, held: held, address: entry.address, router: router,
                                                                               deposit: SafeABI.hex(proved.data), budget: budget) else {
                NSLog("freshAddress| home dollar | %@ | %u | Across did not answer", origin.name, entry.index)
                return
            }
            let fee = h - (Decimal(string: first.outputAmount) ?? h)
            var headroom = fee * Decimal(PrivateBridge.gasHeadroomBps) / 10_000, up = Decimal()
            NSDecimalRound(&up, &headroom, 0, .up)
            let target = h - fee - up
            guard target > 0, (h - target) * 10_000 <= h * Decimal(YourAccountAcross.maxFeeBps),
                  target >= (Decimal(string: least) ?? 0) else {
                NSLog("freshAddress| home dollar | %@ | %u | too little to move | %@ leaves, %@ fee", origin.name, entry.index,
                      held, PrivateMoney.plain(fee))
                return
            }
            let want = PrivateMoney.plain(target)
            if want != budget {
                budget = want
                proved = try await PrivateOnEthereum.bridgedDeposit(budget: budget)
            }
            guard let quote = await quoteDollar(origin, held: held, address: entry.address, router: router,
                                                deposit: SafeABI.hex(proved.data), budget: budget),
                  (Decimal(string: quote.outputAmount) ?? 0) >= target else {
                NSLog("freshAddress| home dollar | %@ | %u | Across's fee rose", origin.name, entry.index)
                return
            }
            let now = Int(Date().timeIntervalSince1970)
            guard quote.fillDeadline > now, quote.fillDeadline <= now + YourAccountAcross.maxDeadlineSeconds,
                  let call = FreshTx.homeDollarDeposit(origin, address: entry.address, input: held, output: budget,
                                                       routerDeposit: SafeABI.hex(proved.data), relayer: quote.exclusiveRelayer,
                                                       quoteTimestamp: quote.quoteTimestamp, fillDeadline: quote.fillDeadline,
                                                       exclusivity: quote.exclusivity) else { return }
            if approving {
                guard let approval = FreshTx.approveData(spender: origin.spoke, amount: held) else { return }
                let hash = try await FreshSigner.sendDollar(chainId: origin.chainId, node: node, name: origin.name, to: origin.dollar,
                                                            data: "0x" + approval, index: entry.index, root: root, from: entry.address,
                                                            gas: Self.dollarApproveGas, tip: fees.tip, maxFee: fees.maxFee) { _, _ in }
                try await PrivateRPC.waitFor(at: node, named: origin.name, hash, seconds: 90)
                NSLog("freshAddress| home dollar approved | %@ | %u | %@", origin.name, entry.index, hash)
            }
            let estimate = Int(PrivateMoney.decimal(hex: try await PrivateRPC.call(at: node, named: origin.name, "eth_estimateGas",
                [["from": entry.address, "to": origin.spoke, "data": call, "value": "0x0"]]) as? String ?? "0x0")) ?? 0
            NSLog("freshAddress| home dollar | %@ | %u | %@ leaves, %@ arrives | estimate %d of %d", origin.name, entry.index,
                  held, budget, estimate, Self.dollarDepositGas)
            guard estimate > 0, estimate <= Self.dollarDepositGas else { return }
            let note = proved.note
            _ = try await FreshSigner.sendDollar(chainId: origin.chainId, node: node, name: origin.name, to: origin.spoke, data: call,
                                                 index: entry.index, root: root, from: entry.address, gas: Self.dollarDepositGas,
                                                 tip: fees.tip, maxFee: fees.maxFee) { hash, _ in
                Self.keepHome(key, HomeSent(tx: hash, at: Date(), amount: held, network: origin.name))
                // Its note waits for the pool to show it, as a bridged round-up's does (§1574).
                PrivateMoneyStore.shared.add(.init(commitment: note.commitment, label: note.label, labelHash: note.labelHash,
                                                   symbol: note.symbol, amount: note.amount, decimals: note.decimals,
                                                   chainId: note.chainId, tx: hash, at: Date(), status: .waiting,
                                                   root: note.root, share: note.share))
                homeMoving[entry.id] = origin.name
                NSLog("freshAddress| home dollar kept | %@ | %u | %@ | %@", origin.name, entry.index, hash, proved.figure)
            }
        } catch {
            NSLog("freshAddress| home dollar failed | %@ | %u | %@", origin.name, entry.index, String(describing: error))
        }
    }

    /// Across's terms for all `held` of the network's dollar leaving the
    /// address, priced with the message it will carry, through Tor.
    private func quoteDollar(_ origin: FreshTx.HomeOrigin, held: String, address: String, router: String,
                             deposit: String, budget: String) async -> YourAccountAcross.Fees? {
        guard let message = FreshTx.bridgeMessage(router: router, deposit: deposit, budget: budget, drainTo: address) else { return nil }
        var parts = URLComponents(string: YourAccountAcross.feesEndpoint)
        parts?.queryItems = [URLQueryItem(name: "inputToken", value: origin.dollar), URLQueryItem(name: "outputToken", value: FreshTx.homeUSDC),
                             URLQueryItem(name: "originChainId", value: String(origin.chainId)),
                             URLQueryItem(name: "destinationChainId", value: String(FreshTx.homeChain)),
                             URLQueryItem(name: "amount", value: held),
                             URLQueryItem(name: "depositor", value: address.lowercased()),
                             URLQueryItem(name: "recipient", value: FreshTx.awayHandler),
                             URLQueryItem(name: "message", value: "0x" + message)]
        guard let url = parts?.url,
              let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"), http.statusCode == 200,
              let fees = YourAccountAcross.fees(try? JSONSerialization.jsonObject(with: data), from: origin.chainId), !fees.tooLow
        else { return nil }
        return fees
    }

    private func resolveHome(_ key: String, sent: HomeSent, node: String, origin: FreshTx.HomeOrigin, entry: FreshAddress.Entry) async {
        let receipt = (try? await PrivateRPC.call(at: node, named: origin.name, "eth_getTransactionReceipt", [sent.tx])) as? [String: Any]
        if let receipt {
            let ok = (receipt["status"] as? String) == "0x1"
            NSLog("freshAddress| home %@ | %@ | %u | %@", ok ? "landed" : "reverted", origin.name, entry.index, sent.tx)
            Self.keepHome(key, nil)
            homeMoving[entry.id] = nil
            return
        }
        // Never seen in half an hour: dropped; the next look reads the balance again.
        if Date().timeIntervalSince(sent.at) > 1_800 {
            NSLog("freshAddress| home dropped | %@ | %u | %@", origin.name, entry.index, sent.tx)
            Self.keepHome(key, nil)
            homeMoving[entry.id] = nil
        } else {
            homeMoving[entry.id] = sent.network
        }
    }

    private func sendHome(_ entry: FreshAddress.Entry, root: String, balance: String, origin: FreshTx.HomeOrigin,
                          node: String, network: PrivacyNetwork, key: String) async {
        do {
            let price = UInt64(PrivateMoney.decimal(hex: try await PrivateRPC.call(at: node, named: origin.name, "eth_gasPrice", []) as? String ?? "0x0")) ?? 0
            let tipRaw = (try? await PrivateRPC.call(at: node, named: origin.name, "eth_maxPriorityFeePerGas", [])) as? String
            let fees = TestnetTx.fees(gasPrice: price, tip: UInt64(PrivateMoney.decimal(hex: tipRaw ?? "0x0")) ?? 0)
            guard let input = FreshTx.homeInput(balance: balance, maxFee: String(fees.maxFee)) else { return }
            // What Ethereum's look would move: the pool's least plus its deposit's gas there.
            guard let pool = network.yieldPool(for: PrivateMove.eth), let least = await minimumBudget(pool, on: network) else { return }
            let ethereum = try await PrivateRPC.fees(network)
            guard let floor = FreshAddress.tooLittleBelow(minimumBudget: least, maxFee: String(ethereum.maxFee)) else { return }
            // Across's terms for exactly this deposit, through Tor.
            var parts = URLComponents(string: YourAccountAcross.feesEndpoint)
            parts?.queryItems = [URLQueryItem(name: "inputToken", value: origin.weth), URLQueryItem(name: "outputToken", value: FreshTx.homeWETH),
                                 URLQueryItem(name: "originChainId", value: String(origin.chainId)),
                                 URLQueryItem(name: "destinationChainId", value: String(FreshTx.homeChain)),
                                 URLQueryItem(name: "amount", value: input),
                                 URLQueryItem(name: "depositor", value: entry.address.lowercased()),
                                 URLQueryItem(name: "recipient", value: entry.address.lowercased())]
            guard let url = parts?.url,
                  let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"), http.statusCode == 200,
                  let quote = YourAccountAcross.fees(try? JSONSerialization.jsonObject(with: data), from: origin.chainId) else {
                NSLog("freshAddress| home | %@ | %u | Across did not answer", origin.name, entry.index)
                return
            }
            let now = Int(Date().timeIntervalSince1970)
            guard !quote.tooLow, FreshTx.homeWorthIt(input: input, output: quote.outputAmount, floor: floor),
                  quote.fillDeadline > now, quote.fillDeadline <= now + YourAccountAcross.maxDeadlineSeconds else {
                NSLog("freshAddress| home | %@ | %u | too little to move | %@ wei, %@ arrives, %@ needed", origin.name, entry.index,
                      input, quote.outputAmount, floor)
                return
            }
            guard let call = FreshTx.homeDeposit(origin, address: entry.address, input: input, output: quote.outputAmount,
                                                 relayer: quote.exclusiveRelayer, quoteTimestamp: quote.quoteTimestamp,
                                                 fillDeadline: quote.fillDeadline, exclusivity: quote.exclusivity),
                  let value = PrivateMoney.hex(input) else { return }
            let estimate = Int(PrivateMoney.decimal(hex: try await PrivateRPC.call(at: node, named: origin.name, "eth_estimateGas",
                [["from": entry.address, "to": origin.spoke, "data": call, "value": value]]) as? String ?? "0x0")) ?? 0
            NSLog("freshAddress| home | %@ | %u | %@ wei leaves, %@ arrives | estimate %d of %d", origin.name, entry.index,
                  input, quote.outputAmount, estimate, FreshTx.homeGas)
            guard estimate > 0, estimate <= FreshTx.homeGas else { return }
            let figure = PrivateMoney.figure(input, decimals: 18, symbol: "ETH")
            _ = try await FreshSigner.sendHome(chainId: origin.chainId, node: node, name: origin.name, to: origin.spoke, data: call,
                                               value: value, index: entry.index, root: root, from: entry.address,
                                               gas: FreshTx.homeGas, tip: fees.tip, maxFee: fees.maxFee) { hash, _ in
                Self.keepHome(key, HomeSent(tx: hash, at: Date(), amount: input, network: origin.name))
                homeMoving[entry.id] = origin.name
                NSLog("freshAddress| home kept | %@ | %u | %@ | %@", origin.name, entry.index, hash, figure)
            }
        } catch {
            NSLog("freshAddress| home failed | %@ | %u | %@", origin.name, entry.index, String(describing: error))
        }
    }
}
