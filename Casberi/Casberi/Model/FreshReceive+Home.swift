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
            guard let balance = try? await PrivateRPC.call(at: node, named: origin.name, "eth_getBalance", [entry.address, "latest"]) as? String,
                  PrivateMoney.decimal(hex: balance) != "0" else { continue }
            await sendHome(entry, root: root, balance: PrivateMoney.decimal(hex: balance), origin: origin, node: node, network: network, key: key)
        }
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
