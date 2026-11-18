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
    /// sender's Across deposit.
    static func send(amount: String, to chainId: Int, payee: String,
                     stage: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let network = PrivacyNetwork.forChain(FreshTx.homeChain),
              FreshTx.homeOrigins.contains(where: { $0.chainId == chainId }), PrivateMoney.isAddress(payee) else { throw Failure.notServed }
        let sender: (index: UInt32, address: String, root: String)
        let withdrawn: String
        if let p = pending {
            guard p.chainId == chainId, p.payee.lowercased() == payee.lowercased() else { throw Failure.earlierSend }
            sender = (p.index, p.address, p.root)
            withdrawn = p.withdrawal
            NSLog("privateAway| finishing an earlier send | %@", YourAccount.short(p.address))
        } else {
            sender = try RailgunPocket.senderAddress()
            // Ask first that Across will carry it, so nothing leaves for a route that is shut.
            let ethFees = try await PrivateRPC.fees(network)
            guard let planned = FreshTx.homeInput(balance: amount, maxFee: String(ethFees.maxFee), gas: FreshTx.awayGas),
                  let first = await quote(input: planned, to: chainId, sender: sender.address, payee: payee),
                  FreshTx.homeWorthIt(input: planned, output: first.outputAmount, floor: "1") else {
                throw Failure.across(String(localized: "Across won't carry this amount"))
            }
            await stage(String(localized: "Sending from your private balance…"))
            withdrawn = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: amount, to: sender.address)
            RailgunPocket.senderUsed(sender)
            keep(Pending(index: sender.index, address: sender.address, root: sender.root, chainId: chainId, payee: payee,
                         withdrawal: withdrawn))
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
                                                  gas: FreshTx.awayGas, tip: fees.tip, maxFee: fees.maxFee) { _, _ in keep(nil) }
        NSLog("privateAway| sent | %@ | to %@ on %d", hash, YourAccount.short(payee), chainId)
        return hash
    }
}
