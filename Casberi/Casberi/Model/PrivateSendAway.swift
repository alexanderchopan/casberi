import Foundation

/// **SEND FROM YOUR PRIVATE BALANCE TO BASE OR ROBINHOOD (prd §1879).** The
/// mirror of receiving there (§1878). Your private ETH is withdrawn by 0xBow's
/// relayer to a fresh sender on Ethereum (nothing names your account); once
/// it lands, the sender makes one Across deposit of what it holds, less that
/// deposit's own gas, to Across's handler on the other network, which
/// unwraps it and pays the recipient ETH (an account too). What the sentence
/// says is what leaves your private balance; what arrives is that less
/// Across's fee and the sender's gas, said before it goes.
///
/// - **A new sender each send** (`RailgunPocket.senderAddress`, one counter
///   with Railgun's), so two sends never share an address.
/// - **Across's fee is at most 5%**, the deadline at most six hours; a
///   deposit not filled is refunded to the sender on Ethereum as WETH.
/// - ETH only: a token at the sender would need ETH for its approval.
@MainActor
enum PrivateSendAway {

    enum Failure: Error, Equatable {
        case notServed, onItsWay(String), across(String), gas, earlierSend
    }

    /// A send whose withdrawal went out and whose deposit has not: the next
    /// send to the same recipient on the same network finishes it from the
    /// same sender, never withdrawing again.
    struct Pending: Codable, Equatable {
        let index: UInt32
        let address: String
        let root: String
        let chainId: Int
        let payee: String
        let withdrawal: String
        /// "USDC" for a dollar send (prd §1880); nil for ETH.
        var symbol: String? = nil
        /// A dollar send's gas, withdrawn in ETH beside it.
        var gasWithdrawal: String? = nil
        /// **WHAT ALREADY LEFT (prd §1988):** base units of the token that
        /// left your private balance; nil for a send kept before it was.
        var amount: String? = nil
    }

    /// **FINISHING SENDS WHAT ALREADY LEFT (prd §1988).** The earlier send to
    /// `payee` on `chainId`, if one waits: finishing it never reads the new
    /// amount, so the sentence takes this one's and Activity records it.
    static func earlier(to chainId: Int, payee: String) -> Pending? {
        guard let p = pending, p.chainId == chainId, p.payee.lowercased() == payee.lowercased() else { return nil }
        return p
    }

    /// What a send did: the Across deposit, and the base units of `symbol`
    /// that left your private balance for it (an earlier send's, finishing).
    struct Sent: Equatable {
        let hash: String
        let symbol: String
        let amount: String
    }

    private static let pendingKey = "privateAway.pending.v1"

    static var pending: Pending? {
        UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
    }

    private static func keep(_ p: Pending?) {
        if let p, let data = try? JSONEncoder().encode(p) { DefaultsWrite.set(data, forKey: pendingKey) }
        else { DefaultsWrite.remove(pendingKey) }
    }

    /// What arrives from `amount` (wei) leaving your private balance, read
    /// now: Across's quote for what the sender can deposit after its gas.
    static func arrives(amount: String, to chainId: Int, payee: String) async -> String? {
        guard let network = PrivacyNetwork.forChain(FreshTx.homeChain), let fees = try? await PrivateRPC.fees(network),
              let input = FreshTx.homeInput(balance: amount, maxFee: String(fees.maxFee), gas: FreshTx.awayGas),
              let quote = await quote(input: input, to: chainId, sender: payee, payee: payee) else { return nil }
        return quote.outputAmount
    }

    /// Across's terms for `input` leaving the sender, priced with the message
    /// it will carry, through Tor.
    private static func quote(input: String, to chainId: Int, sender: String, payee: String) async -> YourAccountAcross.Fees? {
        guard let origin = FreshTx.homeOrigins.first(where: { $0.chainId == chainId }),
              let message = FreshTx.awayMessage(to: chainId, amount: input, payee: payee) else { return nil }
        var parts = URLComponents(string: YourAccountAcross.feesEndpoint)
        parts?.queryItems = [URLQueryItem(name: "inputToken", value: FreshTx.homeWETH), URLQueryItem(name: "outputToken", value: origin.weth),
                             URLQueryItem(name: "originChainId", value: String(FreshTx.homeChain)),
                             URLQueryItem(name: "destinationChainId", value: String(chainId)),
                             URLQueryItem(name: "amount", value: input),
                             URLQueryItem(name: "depositor", value: sender.lowercased()),
                             URLQueryItem(name: "recipient", value: FreshTx.awayHandler),
                             URLQueryItem(name: "message", value: "0x" + message)]
        guard let url = parts?.url,
              let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"), http.statusCode == 200,
              let fees = YourAccountAcross.fees(try? JSONSerialization.jsonObject(with: data), from: FreshTx.homeChain), !fees.tooLow
        else { return nil }
        return fees
    }

    /// Sends `amount` (wei) of your private ETH to `payee` on `chainId`.
    /// Face ID for the withdrawal (`PrivateOnEthereum.send`). Returns the
    /// sender's Across deposit and what left for it (prd §1988).
    static func send(amount: String, symbol: String = "ETH", to chainId: Int, payee: String,
                     stage: @escaping @MainActor (String) -> Void) async throws -> Sent {
        guard let network = PrivacyNetwork.forChain(FreshTx.homeChain),
              FreshTx.homeOrigins.contains(where: { $0.chainId == chainId }), PrivateMoney.isAddress(payee) else { throw Failure.notServed }
        if let p = pending, (p.symbol ?? "ETH") != symbol { throw Failure.earlierSend }
        if symbol == "USDC" { return try await sendDollar(amount: amount, to: chainId, payee: payee, network: network, stage: stage) }
        guard symbol == "ETH" else { throw Failure.notServed }
        let sender: (index: UInt32, address: String, root: String)
        let withdrawn: String
        // What left your private balance: the earlier send's, never `amount`.
        var left: String? = amount
        if let p = pending {
            guard p.chainId == chainId, p.payee.lowercased() == payee.lowercased() else { throw Failure.earlierSend }
            sender = (p.index, p.address, p.root)
            withdrawn = p.withdrawal
            left = p.amount
            NSLog("privateAway| finishing an earlier send | %@ | %@ wei", YourAccount.short(p.address), p.amount ?? "-")
        } else {
            sender = try RailgunPocket.senderAddress()
            // Ask first that Across will carry it, so nothing leaves for a route that is shut.
            let ethFees = try await PrivateRPC.fees(network)
            guard let planned = FreshTx.homeInput(balance: amount, maxFee: String(ethFees.maxFee), gas: FreshTx.awayGas),
                  let first = await quote(input: planned, to: chainId, sender: sender.address, payee: payee),
                  FreshTx.homeWorthIt(input: planned, output: first.outputAmount, floor: "1") else {
                throw Failure.across(String(localized: "Across won't carry this amount"))
            }
            await stage(String(localized: "Sending from Privacy Pools…"))
            withdrawn = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: amount, to: sender.address)
            RailgunPocket.senderUsed(sender)
            keep(Pending(index: sender.index, address: sender.address, root: sender.root, chainId: chainId, payee: payee,
                         withdrawal: withdrawn, amount: amount))
            NSLog("privateAway| withdrawn to sender | %@ | %@ wei | %@", YourAccount.short(sender.address), amount, withdrawn)
        }
        await stage(String(localized: "Waiting for Ethereum…"))
        guard try await FreshSigner.landed(withdrawn, on: network, seconds: 600) else { throw Failure.onItsWay(withdrawn) }
        // What the sender holds now, less its deposit's gas, leaves.
        let held = try await PrivateRPC.decimal(network, "eth_getBalance", [sender.address, "latest"])
        let fees = try await PrivateRPC.fees(network)
        guard let input = FreshTx.homeInput(balance: held, maxFee: String(fees.maxFee), gas: FreshTx.awayGas),
              let quote = await quote(input: input, to: chainId, sender: sender.address, payee: payee),
              FreshTx.homeWorthIt(input: input, output: quote.outputAmount, floor: "1") else {
            throw Failure.across(String(localized: "Across didn't answer. Your ETH waits at a one-time address."))
        }
        let now = Int(Date().timeIntervalSince1970)
        guard quote.fillDeadline > now, quote.fillDeadline <= now + YourAccountAcross.maxDeadlineSeconds,
              let data = FreshTx.awayDeposit(to: chainId, sender: sender.address, payee: payee, input: input,
                                             output: quote.outputAmount, relayer: quote.exclusiveRelayer,
                                             quoteTimestamp: quote.quoteTimestamp, fillDeadline: quote.fillDeadline,
                                             exclusivity: quote.exclusivity),
              let value = PrivateMoney.hex(input) else { throw Failure.across(String(localized: "Across's terms changed")) }
        let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                        [["from": sender.address, "to": FreshTx.awaySpoke, "data": data, "value": value]])) ?? 0
        NSLog("privateAway| deposit | %@ wei leaves, %@ arrives on %d | estimate %d of %d", input, quote.outputAmount, chainId,
              estimate, FreshTx.awayGas)
        guard estimate > 0, estimate <= FreshTx.awayGas else { throw Failure.gas }
        await stage(String(localized: "Moving it with Across…"))
        let hash = try await FreshSigner.sendAway(to: FreshTx.awaySpoke, data: data, value: value, index: sender.index,
                                                  root: sender.root, from: sender.address, network: network,
                                                  gas: FreshTx.awayGas, tip: fees.tip, maxFee: fees.maxFee) { _, _ in
            keep(nil)
            watch(sender, until: quote.fillDeadline)
        }
        NSLog("privateAway| sent | %@ | to %@ on %d", hash, YourAccount.short(payee), chainId)
        // A send kept before its amount was: what the sender held is what left.
        return Sent(hash: hash, symbol: "ETH", amount: left ?? held)
    }

    // MARK: - Refunds (prd §1882)

    /// A sender whose Across deposit may yet be refunded to it: watched until
    /// a day past the deposit's fill deadline.
    struct Watched: Codable, Equatable {
        let index: UInt32
        let address: String
        let root: String
        let until: Date
    }

    private static let watchedKey = "privateAway.watched.v1"

    static var watched: [Watched] {
        UserDefaults.standard.data(forKey: watchedKey).flatMap { try? JSONDecoder().decode([Watched].self, from: $0) } ?? []
    }

    private static func saveWatched(_ list: [Watched]) {
        if let data = try? JSONEncoder().encode(list) { DefaultsWrite.set(data, forKey: watchedKey) }
    }

    private static func watch(_ sender: (index: UInt32, address: String, root: String), until deadline: Int) {
        let until = Date(timeIntervalSince1970: TimeInterval(deadline)).addingTimeInterval(86_400)
        saveWatched(watched.filter { $0.address != sender.address } + [Watched(index: sender.index, address: sender.address, root: sender.root, until: until)])
    }

    /// The gas a refund's transfer may use.
    static let refundGas = 80_000

    /// **WHAT ACROSS GAVE BACK (prd §1882).** Each watched sender holding WETH
    /// or USDC sends it to your current receive address on Ethereum, whose
    /// look moves it into your private balance (WETH through Railgun, USDC
    /// into the pool); its gas from the ETH the sender kept. A sender past its
    /// watch is dropped.
    static func lookRefunds(receiveIndex: UInt32?, receiveRoot: String?) async {
        let now = Date()
        var list = watched
        let expired = list.filter { $0.until < now }
        if !expired.isEmpty { list.removeAll { $0.until < now }; saveWatched(list) }
        guard !list.isEmpty, let network = PrivacyNetwork.forChain(FreshTx.homeChain), let receiveIndex else { return }
        for s in list where s.root == receiveRoot {
            for token in [FreshTx.homeWETH, FreshTx.homeUSDC] {
                guard let held = try? await PrivateRPC.tokenBalance(network, token: token, of: s.address), held != "0" else { continue }
                do {
                    let fees = try await PrivateRPC.fees(network)
                    let eth = Decimal(string: try await PrivateRPC.decimal(network, "eth_getBalance", [s.address, "latest"])) ?? 0
                    // What the sender kept pays: up to the usual cap, at least
                    // today's price and tip (`TestnetTx.fees`: cap = 2×price + tip).
                    let floorFee = (fees.maxFee - fees.tip) / 2 + fees.tip
                    let affordable = NSDecimalNumber(decimal: eth / Decimal(refundGas)).uint64Value
                    guard affordable >= floorFee else {
                        NSLog("privateAway| refund waits for gas | %@ | %@ of %@", YourAccount.short(s.address), held, token)
                        continue
                    }
                    let hash = try await FreshSigner.sendRefund(token: token, amount: held, receiveIndex: receiveIndex, index: s.index,
                                                                root: s.root, from: s.address, network: network, gas: refundGas,
                                                                tip: fees.tip, maxFee: min(fees.maxFee, affordable))
                    NSLog("privateAway| refund sent on | %@ | %@ of %@ | %@", YourAccount.short(s.address), held, token, hash)
                } catch {
                    NSLog("privateAway| refund failed | %@ | %@", YourAccount.short(s.address), String(describing: error))
                }
            }
        }
    }

    // MARK: - Dollars (prd §1880)

    /// The gas a fresh sender's dollar approval and deposit may use on Ethereum.
    static let dollarApproveGas = 80_000
    static let dollarDepositGas = 150_000

    /// A dollar send's gas in ETH, base units: the approval and the deposit
    /// at today's cap, half again (the Railgun sender's way, §1726). Its own
    /// relayed withdrawal pays a second relayer fee beside it (prd §1988).
    static func dollarGas(maxFee: UInt64) -> Decimal {
        var gas = Decimal(dollarApproveGas + dollarDepositGas) * Decimal(maxFee) * Decimal(3) / Decimal(2), up = Decimal()
        NSDecimalRound(&up, &gas, 0, .up)
        return up
    }

    /// Across's terms for `amount` of Ethereum's USDC to `payee` as the
    /// network's dollar, no message, through Tor.
    private static func quoteDollar(amount: String, to chainId: Int, sender: String, payee: String) async -> YourAccountAcross.Fees? {
        guard let origin = FreshTx.homeOrigins.first(where: { $0.chainId == chainId }) else { return nil }
        var parts = URLComponents(string: YourAccountAcross.feesEndpoint)
        parts?.queryItems = [URLQueryItem(name: "inputToken", value: FreshTx.homeUSDC), URLQueryItem(name: "outputToken", value: origin.dollar),
                             URLQueryItem(name: "originChainId", value: String(FreshTx.homeChain)),
                             URLQueryItem(name: "destinationChainId", value: String(chainId)),
                             URLQueryItem(name: "amount", value: amount),
                             URLQueryItem(name: "depositor", value: sender.lowercased()),
                             URLQueryItem(name: "recipient", value: payee.lowercased())]
        guard let url = parts?.url,
              let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"), http.statusCode == 200,
              let fees = YourAccountAcross.fees(try? JSONSerialization.jsonObject(with: data), from: FreshTx.homeChain), !fees.tooLow
        else { return nil }
        return fees
    }

    /// **A PRIVATE DOLLAR TO BASE OR ROBINHOOD (prd §1880).** `amount` of
    /// your private USDC and its gas in your private ETH, both withdrawn to a
    /// fresh sender; then the sender's approval of Ethereum's SpokePool and
    /// its deposit straight to `payee` as the network's dollar. What arrives
    /// is the amount less Across's fee.
    private static func sendDollar(amount: String, to chainId: Int, payee: String, network: PrivacyNetwork,
                                   stage: @escaping @MainActor (String) -> Void) async throws -> Sent {
        let sender: (index: UInt32, address: String, root: String)
        var outs: [String]
        // What left your private balance: the earlier send's, never `amount`.
        var left: String? = amount
        if let p = pending {
            guard p.chainId == chainId, p.payee.lowercased() == payee.lowercased() else { throw Failure.earlierSend }
            sender = (p.index, p.address, p.root)
            outs = [p.withdrawal] + (p.gasWithdrawal.map { [$0] } ?? [])
            left = p.amount
            NSLog("privateAway| finishing an earlier dollar send | %@ | %@ units", YourAccount.short(p.address), p.amount ?? "-")
        } else {
            sender = try RailgunPocket.senderAddress()
            guard let first = await quoteDollar(amount: amount, to: chainId, sender: sender.address, payee: payee),
                  FreshTx.homeWorthIt(input: amount, output: first.outputAmount, floor: "1") else {
                throw Failure.across(String(localized: "Across won't carry this amount"))
            }
            // Its gas, half again, in your private ETH (the Railgun sender's way, §1726).
            // **WHAT GAS DOESN'T USE STAYS AT THE SENDER (prd §1988):** no
            // sweep brings leftover ETH back yet; the sender signs only the
            // approval, Across's deposit and a refund's token transfer
            // (`FreshSigner`), and `lookRefunds` spends that ETH on its gas.
            let fees = try await PrivateRPC.fees(network)
            let up = dollarGas(maxFee: fees.maxFee)
            guard let ethPool = network.yieldPool(for: PrivateMove.eth),
                  let fee = Decimal(string: await PrivateMove.relayerFee(ethPool, network: network, to: sender.address) ?? ""), fee > 0,
                  (Decimal(string: PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "ETH")) ?? 0) >= up + fee else {
                throw Failure.across(String(localized: "Its gas needs a little private ETH"))
            }
            await stage(String(localized: "Sending from Privacy Pools…"))
            let gasOut = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: PrivateMoney.plain(up), to: sender.address)
            RailgunPocket.senderUsed(sender)
            keep(Pending(index: sender.index, address: sender.address, root: sender.root, chainId: chainId, payee: payee,
                         withdrawal: gasOut, symbol: "USDC", gasWithdrawal: nil))
            let usdc = try await PrivateOnEthereum.send(token: FreshTx.homeUSDC, amount: amount, to: sender.address)
            keep(Pending(index: sender.index, address: sender.address, root: sender.root, chainId: chainId, payee: payee,
                         withdrawal: usdc, symbol: "USDC", gasWithdrawal: gasOut, amount: amount))
            outs = [usdc, gasOut]
            NSLog("privateAway| dollar withdrawn to sender | %@ | %@ USDC units + %@ wei gas", YourAccount.short(sender.address),
                  amount, PrivateMoney.plain(up))
        }
        await stage(String(localized: "Waiting for Ethereum…"))
        for out in outs { guard try await FreshSigner.landed(out, on: network, seconds: 600) else { throw Failure.onItsWay(out) } }
        let node = network.rpcUrl, name = network.name
        let held = try await PrivateRPC.tokenBalance(network, token: FreshTx.homeUSDC, of: sender.address)
        guard held != "0" else { throw Failure.across(String(localized: "Across didn't answer. Your USDC waits at a one-time address.")) }
        let fees = try await PrivateRPC.fees(network)
        // The approval, unless the SpokePool may already take it.
        let allowanceData = "0xdd62ed3e" + String(repeating: "0", count: 24) + sender.address.dropFirst(2).lowercased()
            + String(repeating: "0", count: 24) + FreshTx.awaySpoke.dropFirst(2)
        let allowed = ((try? await PrivateRPC.call(network, "eth_call", [["to": FreshTx.homeUSDC, "data": allowanceData], "latest"])) as? String)
            .flatMap { PrivateYield.word($0, 0) } ?? "0"
        if (Decimal(string: allowed) ?? 0) < (Decimal(string: held) ?? 0) {
            guard let approval = FreshTx.approveData(spender: FreshTx.awaySpoke, amount: held) else { throw Failure.gas }
            await stage(String(localized: "Moving it with Across…"))
            let hash = try await FreshSigner.sendDollar(chainId: FreshTx.homeChain, node: node, name: name, to: FreshTx.homeUSDC,
                                                        data: "0x" + approval, index: sender.index, root: sender.root,
                                                        from: sender.address, gas: dollarApproveGas, tip: fees.tip, maxFee: fees.maxFee) { _, _ in }
            try await PrivateRPC.waitFor(hash, on: network)
        }
        guard let quote = await quoteDollar(amount: held, to: chainId, sender: sender.address, payee: payee),
              FreshTx.homeWorthIt(input: held, output: quote.outputAmount, floor: "1") else {
            throw Failure.across(String(localized: "Across didn't answer. Your USDC waits at a one-time address."))
        }
        let now = Int(Date().timeIntervalSince1970)
        guard quote.fillDeadline > now, quote.fillDeadline <= now + YourAccountAcross.maxDeadlineSeconds,
              let data = FreshTx.awayDollarDeposit(to: chainId, sender: sender.address, payee: payee, input: held,
                                                   output: quote.outputAmount, relayer: quote.exclusiveRelayer,
                                                   quoteTimestamp: quote.quoteTimestamp, fillDeadline: quote.fillDeadline,
                                                   exclusivity: quote.exclusivity) else { throw Failure.across(String(localized: "Across's terms changed")) }
        let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                        [["from": sender.address, "to": FreshTx.awaySpoke, "data": data, "value": "0x0"]])) ?? 0
        NSLog("privateAway| dollar deposit | %@ leaves, %@ arrives on %d | estimate %d of %d", held, quote.outputAmount, chainId,
              estimate, dollarDepositGas)
        guard estimate > 0, estimate <= dollarDepositGas else { throw Failure.gas }
        await stage(String(localized: "Moving it with Across…"))
        let hash = try await FreshSigner.sendDollar(chainId: FreshTx.homeChain, node: node, name: name, to: FreshTx.awaySpoke, data: data,
                                                    index: sender.index, root: sender.root, from: sender.address,
                                                    gas: dollarDepositGas, tip: fees.tip, maxFee: fees.maxFee) { _, _ in
            keep(nil)
            watch(sender, until: quote.fillDeadline)
        }
        NSLog("privateAway| dollar sent | %@ | to %@ on %d", hash, YourAccount.short(payee), chainId)
        return Sent(hash: hash, symbol: "USDC", amount: left ?? held)
    }
}
