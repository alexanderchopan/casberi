import Foundation

/// **A SWAP TO ANOTHER NETWORK, THROUGH ACROSS (prd §1555).** Across is a
/// bridge whose relayers are anyone (permissionless), whose contracts are
/// open, and whose refund is the contract's, not a company's promise: a
/// deposit no relayer fills by its deadline goes back to its depositor on
/// the network it left. The phone writes the deposit itself, as it writes a
/// swap (§1542): Across's API is asked only what its relayers charge now
/// (`suggested-fees`), and every byte signed is built here and checked
/// again before Face ID (`checked`), then simulated.
///
/// **What it carries.** ETH and each network's dollar, between Base,
/// Ethereum and Robinhood Chain — every one of the twelve routes measured
/// open on Across's `available-routes` (2026-10-26): ETH↔ETH on all six
/// pairs, USDC↔USDC between Base and Ethereum, USDC↔USDG to and from
/// Robinhood. Anything else is first swapped on the sending network into
/// one of those by the pools (§1542), in the same transaction; any other
/// token on the receiving network is bought there by its pools, through the
/// handler's message (`Arrival`, prd §1566), and a swap there that fails
/// pays the account the bridged token instead.
///
/// **ETH arrives as ETH.** A SpokePool pays a contract recipient WETH, never
/// ETH (`_unwrapwrappedNativeTokenTo`, read in Across's source), and the
/// account is a contract wherever it has been used. So ETH goes to Across's
/// own MulticallHandler with a message of two calls — unwrap exactly the
/// amount filled, then pay the handler's ETH to the account — and the
/// account as the fallback recipient, so a call that fails sends the WETH
/// to the account instead of leaving it.
///
/// Pure (Foundation, `SafeABI`, `YourAccount`'s encoders, `YourAccountSwap`'s
/// ABI encoder): the requests are `YourAccountChain+Across.swift`'s, and
/// `across-swap-selftest.sh` reads this whole file with no network.
enum YourAccountAcross {
    typealias Op = YourAccountOp
    typealias Call = YourAccountSwap.Call

    // MARK: - Pinned (each read on chain, 2026-10-26)

    /// Across's SpokePool on each network: the only contract a deposit
    /// calls, and the only spender approved. Each is a proxy with code, its
    /// `chainId()` this network and its `wrappedNativeToken()` the WETH
    /// below; named in Across's own `broadcast/deployed-addresses.json` and
    /// in every `suggested-fees` answer (`spokePoolAddress`), which `fees`
    /// refuses when it names another.
    static let spokes: [Int: String] = [
        1: "0x5c7bcd6e7de5423a257d81b442095a1a6ced35c5",
        8453: "0x09aea4b2242abc8bb4bb78d537a67a245a7bec64",
        4663: "0xd29c85f15df544ba632c9e25829fd29d767d7978",
    ]

    /// Across's MulticallHandler: the same 3,758 bytes of code at this
    /// address on all three networks (named for Ethereum and Base in the
    /// same file; Robinhood's read on chain).
    static let handler = "0x0f7ae28de1c8532170ad4ee566b5801485c13a0e"

    /// The fee question: what relayers charge for this route and amount now.
    static let feesEndpoint = "https://app.across.to/api/suggested-fees"

    /// The most a crossing may cost, in basis points of what is sent: past
    /// it, the route is not offered ("costs more than 5%").
    static let maxFeeBps = 500

    /// A fill deadline further out than this is refused: Across's own is two
    /// hours, and a deadline is how long the money can be in flight.
    static let maxDeadlineSeconds = 6 * 3_600

    static func spoke(_ chainId: Int) -> String? { spokes[chainId] }

    static func isSpoke(_ address: String) -> Bool { spokes.values.contains(address.lowercased()) }

    /// Across's own contracts by address, on any network: the history names
    /// a move to or from one "Across".
    static func isAcross(_ address: String) -> Bool {
        let a = address.lowercased()
        return isSpoke(a) || a == handler
    }

    // MARK: - Routes

    /// What crosses: the network's own coin, or its dollar.
    enum Asset: String, Equatable, Sendable, Codable {
        case eth, dollar
    }

    /// The asset `token` is on `network`, if it is one that crosses.
    static func asset(of token: Op.Token, on network: Op.Network) -> Asset? {
        guard let contract = token.contract?.lowercased() else { return .eth }
        return contract == network.dollar.lowercased() ? .dollar : nil
    }

    /// The contract that crosses: WETH (ETH is wrapped by the SpokePool) or
    /// the dollar, lowercased.
    static func bridged(_ asset: Asset, on chainId: Int) -> String? {
        switch asset {
        case .eth: YourAccountSwap.book(chainId)?.weth
        case .dollar: Op.networks.first { $0.chainId == chainId }?.dollar.lowercased()
        }
    }

    /// The token the account holds after a crossing of `asset` lands.
    static func token(_ asset: Asset, on network: Op.Network) -> Op.Token {
        asset == .eth ? Op.eth : Op.dollar(on: network)
    }

    /// Whether Across carries `asset` from one of the account's networks to
    /// another: every pair of the three, both assets (measured, above).
    static func carries(_ asset: Asset, from: Int, to: Int) -> Bool {
        from != to && spokes[from] != nil && spokes[to] != nil
            && bridged(asset, on: from) != nil && bridged(asset, on: to) != nil
    }

    // MARK: - The fee question

    /// `suggested-fees` for `amount` of `asset` from one network to another.
    /// ETH is priced with the handler as the recipient and the message it
    /// will carry, since relayers charge for running it.
    /// A swap on arrival (`through`, prd §1566) is priced with its own
    /// message's shape: relayers pay the gas of running it.
    static func feesURL(_ asset: Asset, from: Int, to: Int, amount: String, account: String,
                        through route: YourAccountSwap.Route? = nil, now: Int = 0) -> URL? {
        guard carries(asset, from: from, to: to), let input = bridged(asset, on: from),
              let output = bridged(asset, on: to), YourAccountSwap.isPositive(amount) else { return nil }
        var parts = URLComponents(string: feesEndpoint)
        var items = [URLQueryItem(name: "inputToken", value: input), URLQueryItem(name: "outputToken", value: output),
                     URLQueryItem(name: "originChainId", value: String(from)),
                     URLQueryItem(name: "destinationChainId", value: String(to)),
                     URLQueryItem(name: "amount", value: amount), URLQueryItem(name: "depositor", value: account.lowercased())]
        if let route {
            guard let message = pricing(asset, to: to, amount: amount, route: route, account: account, now: now) else { return nil }
            items += [URLQueryItem(name: "recipient", value: handler), URLQueryItem(name: "message", value: SafeABI.hex(message))]
        } else if asset == .eth {
            guard let message = message(to: to, amount: amount, account: account) else { return nil }
            items += [URLQueryItem(name: "recipient", value: handler), URLQueryItem(name: "message", value: SafeABI.hex(message))]
        } else {
            items.append(URLQueryItem(name: "recipient", value: account.lowercased()))
        }
        parts?.queryItems = items
        return parts?.url
    }

    /// What Across's relayers charge now, as `suggested-fees` answered.
    struct Fees: Equatable, Sendable {
        /// What the recipient receives, exactly (a fill pays this, no less).
        let outputAmount: String
        /// The HubPool time the fee was set at; the SpokePool takes it for
        /// up to its `depositQuoteTimeBuffer`.
        let quoteTimestamp: Int
        let fillDeadline: Int
        /// The relayer that may fill alone until `exclusivity`; zero for none.
        let exclusiveRelayer: String
        /// An offset in seconds, or a timestamp, as the SpokePool reads it.
        let exclusivity: Int
        /// Across's own estimate of the fill, in seconds.
        let seconds: Int?
        let spokePool: String
        let tooLow: Bool
        let minDeposit: String?
        let maxDeposit: String?
    }

    /// The answer read, or nil for anything that does not read as one: a
    /// SpokePool other than the pinned one, a field that is not a number.
    static func fees(_ json: Any?, from: Int) -> Fees? {
        guard let o = json as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            if let s = o[key] as? String { return s }
            if let n = o[key] as? NSNumber { return n.stringValue }
            return nil
        }
        func int(_ key: String) -> Int? { text(key).flatMap { Int($0) } }
        let limits = o["limits"] as? [String: Any]
        guard let out = text("outputAmount"), out.allSatisfy(\.isNumber), !out.isEmpty,
              let quoted = int("timestamp"), let deadline = int("fillDeadline"),
              let pool = (o["spokePoolAddress"] as? String)?.lowercased(), pool == spokes[from] else { return nil }
        let relayer = (o["exclusiveRelayer"] as? String)?.lowercased() ?? YourAccountSwap.native
        guard SafeABI.word(address: relayer) != nil else { return nil }
        return Fees(outputAmount: out, quoteTimestamp: quoted, fillDeadline: deadline,
                    exclusiveRelayer: relayer, exclusivity: int("exclusivityDeadline") ?? 0,
                    seconds: int("estimatedFillTimeSec"), spokePool: pool,
                    tooLow: (o["isAmountTooLow"] as? Bool) ?? false,
                    minDeposit: limits?["minDeposit"] as? String, maxDeposit: limits?["maxDeposit"] as? String)
    }

    // MARK: - The crossing, as the quote carries it

    /// One crossing: what leaves, what arrives, and Across's terms for it.
    struct Leg: Equatable, Sendable {
        let asset: Asset
        let from: Int
        let to: Int
        /// The destination's name, as the sentence says it.
        let toName: String
        /// What the SpokePool takes on `from`.
        let inputAmount: String
        /// What the account receives on `to`.
        let outputAmount: String
        let seconds: Int?
        let fillDeadline: Int
        /// A swap on the receiving network (prd §1566): what `outputAmount`
        /// buys there, through the handler's message. Nil when ETH or the
        /// dollar is what arrives.
        var swap: Arrival? = nil

        /// Across's whole fee, in millionths of what is sent.
        var feePips: Int {
            guard let i = Decimal(string: inputAmount), i > 0,
                  let o = Decimal(string: outputAmount) else { return 0 }
            var d = (i - o) * 1_000_000 / i
            var r = Decimal()
            NSDecimalRound(&r, &d, 0, .up)
            return max(0, NSDecimalNumber(decimal: r).intValue)
        }
    }

    /// Whether Across's terms for `leg` are ones the phone will sign: no more
    /// out than in, a fee under `maxFeeBps`, a deadline ahead and not far.
    static func acceptable(_ leg: Leg, now: Int) -> Bool {
        guard YourAccountSwap.isPositive(leg.inputAmount), YourAccountSwap.isPositive(leg.outputAmount),
              Op.atMost(leg.outputAmount, leg.inputAmount),
              let least = YourAccountSwap.minimum(leg.inputAmount, bps: maxFeeBps),
              Op.atMost(least, leg.outputAmount) else { return false }
        return leg.fillDeadline > now && leg.fillDeadline <= now + maxDeadlineSeconds
    }

    // MARK: - The calls

    /// The handler's message for ETH: unwrap exactly `amount` of WETH, pay
    /// the handler's ETH to `account`; the account takes anything left if a
    /// call fails. `abi.encode(Instructions)`, as `MulticallHandler` decodes it.
    static func message(to chainId: Int, amount: String, account: String) -> [UInt8]? {
        typealias A = YourAccountSwap.Arg
        guard let weth = YourAccountSwap.book(chainId)?.weth, let units = A.amount(amount),
              SafeABI.word(address: account) != nil else { return nil }
        let unwrap = YourAccountSwap.call("withdraw(uint256)", [units])
        let pay = YourAccountSwap.call("drainLeftoverTokens(address,address)", [.address(YourAccountSwap.native), .address(account)])
        let calls: A = .array([.tuple([.address(weth), .bytes(unwrap), .uint(0)]),
                               .tuple([.address(handler), .bytes(pay), .uint(0)])])
        return YourAccountSwap.encode([.tuple([calls, .address(account)])])
    }

    // MARK: - A swap on the receiving network (prd §1566)

    /// **WHAT ARRIVES IS SWAPPED THERE.** The bridged token — WETH for ETH
    /// (a SpokePool pays a contract WETH), or the dollar — reaches Across's
    /// handler, whose message approves the receiving network's pinned router
    /// exactly what was filled, swaps it along `route` for at least `minimum`
    /// of `buy`, paid straight to the account, and names the account the
    /// fallback: a swap that fails there (a price past the minimum, a pool
    /// emptied) leaves the handler holding the bridged token, which it then
    /// pays the account whole (`MulticallHandler`: `attemptCalls` reverts as
    /// one, `_drainRemainingTokens` follows). Never stranded.
    struct Arrival: Equatable, Sendable {
        /// Through the receiving network's own pools (`YourAccountSwap.book`).
        let route: YourAccountSwap.Route
        /// The token bought there, on the receiving network.
        let buy: Op.Token
        /// What the pools paid for the filled amount when the sentence asked.
        let quoted: String
        /// The least the swap takes: `quoted` less the receiving network's
        /// slippage limit (`Book.slippageBps`), exactly.
        let minimum: String
    }

    /// The swap's calls as the handler makes them: the bridged token's exact
    /// approval to the router, then one router call paying the account, with
    /// the fill deadline as its own (a fill may come any time before it; the
    /// minimum is what holds the price). Nil unless every rule holds: a
    /// router pinned on the receiving network, from exactly the bridged
    /// token, to exactly the token bought (never the bridged token itself),
    /// the minimum exactly the quote less that network's slippage.
    static func arrivalCalls(_ leg: Leg, account: String) -> [Call]? {
        guard let s = leg.swap, let book = YourAccountSwap.book(leg.to), book.venues.contains(s.route.venue),
              let into = bridged(leg.asset, on: leg.to), s.route.hops.first?.from.lowercased() == into,
              let target = s.buy.contract?.lowercased(), target != into, s.route.hops.last?.to.lowercased() == target,
              YourAccountSwap.isPositive(s.minimum), Op.atMost(s.minimum, s.quoted),
              s.minimum == YourAccountSwap.minimum(s.quoted, bps: book.slippageBps),
              let calls = YourAccountSwap.calls(s.route, in: book, sellsETH: false, buysETH: false, amount: leg.outputAmount,
                                                minimum: s.minimum, account: account, deadline: leg.fillDeadline),
              calls.allSatisfy({ $0.value == "0" }) else { return nil }
        return calls
    }

    /// `abi.encode(Instructions)`: the calls, none sending ETH, the account
    /// the fallback.
    private static func instructions(_ calls: [Call], account: String) -> [UInt8] {
        typealias A = YourAccountSwap.Arg
        let list: A = .array(calls.map { .tuple([.address($0.to), .bytes($0.data), .uint(0)]) })
        return YourAccountSwap.encode([.tuple([list, .address(account)])])
    }

    /// The message a deposit carries: the swap on arrival's, ETH's unwrap,
    /// or none for a dollar paid straight to the account.
    static func message(for leg: Leg, account: String) -> [UInt8]? {
        if leg.swap != nil { return arrivalCalls(leg, account: account).map { instructions($0, account: account) } }
        return leg.asset == .eth ? message(to: leg.to, amount: leg.outputAmount, account: account) : []
    }

    /// Whether the deposit pays Across's handler (its message runs there)
    /// rather than the account.
    static func viaHandler(_ leg: Leg) -> Bool { leg.asset == .eth || leg.swap != nil }

    /// The message the fee question carries for a swap on arrival: its
    /// shape, so relayers price its gas, before the output is known — the
    /// least Across's terms allow (`maxFeeBps` under what is sent) swapped
    /// for at least one unit, so the relayers' run of it succeeds. Never
    /// signed: the deposit carries `message(for:)`.
    static func pricing(_ asset: Asset, to: Int, amount: String, route: YourAccountSwap.Route, account: String,
                        now: Int) -> [UInt8]? {
        guard let book = YourAccountSwap.book(to), book.venues.contains(route.venue),
              route.hops.first?.from.lowercased() == bridged(asset, on: to),
              let least = YourAccountSwap.minimum(amount, bps: maxFeeBps), YourAccountSwap.isPositive(least),
              let calls = YourAccountSwap.calls(route, in: book, sellsETH: false, buysETH: false, amount: least,
                                                minimum: "1", account: account, deadline: now + maxDeadlineSeconds)
        else { return nil }
        return instructions(calls, account: account)
    }

    static let depositSignature = "deposit(bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,bytes32,uint32,uint32,uint32,bytes)"
    static let approveSelector = YourAccountSwap.approveSelector

    /// The SpokePool's `deposit`, the account as depositor (so a refund is
    /// the account's), the account as recipient (the handler for ETH).
    static func deposit(_ leg: Leg, fees: Fees, account: String) -> [UInt8]? {
        typealias A = YourAccountSwap.Arg
        guard let input = bridged(leg.asset, on: leg.from), let output = bridged(leg.asset, on: leg.to),
              let inAmount = A.amount(leg.inputAmount), let outAmount = A.amount(leg.outputAmount),
              SafeABI.word(address: account) != nil, fees.exclusivity >= 0,
              let note = message(for: leg, account: account) else { return nil }
        let recipient = viaHandler(leg) ? handler : account
        return YourAccountSwap.call(depositSignature, [
            .address(account), .address(recipient), .address(input), .address(output),
            inAmount, outAmount, .uint(leg.to), .address(fees.exclusiveRelayer),
            .uint(fees.quoteTimestamp), .uint(leg.fillDeadline), .uint(fees.exclusivity), .bytes(note),
        ])
    }

    /// The calls that cross: the dollar's exact approval to the SpokePool
    /// (none for ETH, sent with the call and wrapped by the pool), then the
    /// deposit.
    static func calls(_ leg: Leg, fees: Fees, account: String) -> [Call]? {
        guard let pool = spokes[leg.from], let data = deposit(leg, fees: fees, account: account),
              let amount = SafeABI.word(uint256: leg.inputAmount) else { return nil }
        switch leg.asset {
        case .eth:
            return [Call(to: pool, value: leg.inputAmount, data: data)]
        case .dollar:
            guard let token = bridged(.dollar, on: leg.from) else { return nil }
            return [Call(to: token, value: "0", data: approveSelector + YourAccount.w(pool) + amount),
                    Call(to: pool, value: "0", data: data)]
        }
    }

    // MARK: - The check

    /// **NOTHING SIGNED BUT WHAT THESE RULES ALLOW.** `calls` is exactly the
    /// crossing `leg` describes, read back field by field from the bytes:
    /// the pinned SpokePool of the sending network, the account as depositor
    /// (its refund) and as recipient (or the handler, carrying exactly the
    /// message that pays the account the amount filled), the pinned tokens,
    /// exactly the amount sent, Across's terms acceptable (`acceptable`), an
    /// exclusive relayer only with a deadline and the reverse; ETH out only
    /// as the deposit's value, a dollar only by its exact approval to that
    /// pool. Returns the approval apart, so a batch approves once for the
    /// sum; nil otherwise.
    static func checked(_ calls: [Call], leg: Leg, account: String, now: Int)
        -> (approvals: [(token: String, spender: String, amount: String)], calls: [Call])? {
        guard let pool = spokes[leg.from], let input = bridged(leg.asset, on: leg.from),
              let output = bridged(leg.asset, on: leg.to), acceptable(leg, now: now) else { return nil }
        var approvals: [(String, String, String)] = []
        var deposits: [Call] = []
        for call in calls {
            if call.data.starts(with: approveSelector) {
                guard leg.asset == .dollar, call.to.lowercased() == input, call.value == "0", call.data.count == 4 + 64,
                      word(call.data, 0).flatMap(address) == pool,
                      SafeCalldata.decimal(Array(call.data[36..<68])) == leg.inputAmount else { return nil }
                approvals.append((input, pool, leg.inputAmount))
                continue
            }
            guard call.to.lowercased() == pool, call.data.starts(with: YourAccount.sel(depositSignature)) else { return nil }
            guard call.value == (leg.asset == .eth ? leg.inputAmount : "0") else { return nil }
            deposits.append(call)
        }
        guard deposits.count == 1, approvals.count == (leg.asset == .dollar ? 1 : 0) else { return nil }
        let d = deposits[0].data
        let me = account.lowercased()
        guard word(d, 0).flatMap(address) == me,
              word(d, 2).flatMap(address) == input, word(d, 3).flatMap(address) == output,
              word(d, 4).map(SafeCalldata.decimal) == leg.inputAmount,
              word(d, 5).map(SafeCalldata.decimal) == leg.outputAmount,
              word(d, 6).map(SafeCalldata.decimal) == String(leg.to),
              word(d, 9).map(SafeCalldata.decimal) == String(leg.fillDeadline),
              let relayer = word(d, 7).flatMap(address), let exclusivity = word(d, 10).map(SafeCalldata.decimal),
              (exclusivity == "0") == (relayer == YourAccountSwap.native),
              let noteAt = word(d, 11).flatMap(small), let noteLength = small(d, at: 4 + noteAt),
              4 + noteAt + 32 + noteLength <= d.count else { return nil }
        let note = Array(d[(4 + noteAt + 32)..<(4 + noteAt + 32 + noteLength)])
        // To the handler only with exactly the message that pays the account
        // (ETH's unwrap, or the swap on arrival with the account its fallback).
        if viaHandler(leg) {
            guard word(d, 1).flatMap(address) == handler, let want = message(for: leg, account: account),
                  note == want else { return nil }
        } else {
            guard word(d, 1).flatMap(address) == me, note.isEmpty else { return nil }
        }
        return (approvals, deposits)
    }

    /// The `n`th argument word of a call's data.
    private static func word(_ data: [UInt8], _ n: Int) -> [UInt8]? {
        let at = 4 + 32 * n
        guard at + 32 <= data.count else { return nil }
        return Array(data[at..<(at + 32)])
    }

    private static func small(_ data: [UInt8], at i: Int) -> Int? {
        guard i >= 0, i + 32 <= data.count else { return nil }
        return small(Array(data[i..<(i + 32)]))
    }

    private static func small(_ w: [UInt8]) -> Int? {
        guard w.count == 32, w[0..<28].allSatisfy({ $0 == 0 }) else { return nil }
        return w[28..<32].reduce(0) { $0 << 8 | Int($1) }
    }

    private static func address(_ w: [UInt8]) -> String? {
        guard w.count == 32, w[0..<12].allSatisfy({ $0 == 0 }) else { return nil }
        return SafeABI.hex(Array(w[12..<32])).lowercased()
    }

    // MARK: - The fill, read on the other network

    /// `FundsDeposited`, as the SpokePool emits it (its bytes32 version).
    static let fundsDepositedTopic = "0x" + Keccak256.hexString(Keccak256.hash(Array(
        "FundsDeposited(bytes32,bytes32,uint256,uint256,uint256,uint256,uint32,uint32,uint32,bytes32,bytes32,bytes32,bytes)".utf8)))

    /// A deposit as it landed: every field the destination hashes.
    struct Deposited: Equatable, Sendable {
        let depositor: [UInt8]
        let recipient: [UInt8]
        let exclusiveRelayer: [UInt8]
        let inputToken: [UInt8]
        let outputToken: [UInt8]
        let inputAmount: [UInt8]
        let outputAmount: [UInt8]
        let originChainId: Int
        let destinationChainId: Int
        let depositId: [UInt8]
        let fillDeadline: [UInt8]
        let exclusivityDeadline: [UInt8]
        let message: [UInt8]

        var deadline: Int { small(fillDeadline) ?? 0 }
    }

    /// The account's deposit among a landed transaction's logs (`topics` and
    /// `data` as a receipt gives them), from the pinned SpokePool; nil when
    /// there is none.
    static func deposited(_ logs: [[String: Any]], origin: Int, account: String) -> Deposited? {
        guard let pool = spokes[origin], let me = SafeABI.word(address: account) else { return nil }
        for log in logs {
            guard (log["address"] as? String)?.lowercased() == pool,
                  let topics = (log["topics"] as? [String])?.compactMap(SafeABI.hexBytes), topics.count == 4,
                  SafeABI.hex(topics[0]).lowercased() == fundsDepositedTopic, topics[3] == me,
                  let data = (log["data"] as? String).flatMap(SafeABI.hexBytes), data.count >= 10 * 32,
                  let destination = small(topics[1]) else { continue }
            func w(_ i: Int) -> [UInt8] { Array(data[(32 * i)..<(32 * i + 32)]) }
            guard let at = small(w(9)), let length = small(data, at: at), at + 32 + length <= data.count else { continue }
            return Deposited(depositor: topics[3], recipient: w(7), exclusiveRelayer: w(8), inputToken: w(0),
                             outputToken: w(1), inputAmount: w(2), outputAmount: w(3), originChainId: origin,
                             destinationChainId: destination, depositId: topics[2], fillDeadline: w(5),
                             exclusivityDeadline: w(6), message: Array(data[(at + 32)..<(at + 32 + length)]))
        }
        return nil
    }

    /// The SpokePool's `getV3RelayHash`: `keccak256(abi.encode(relayData,
    /// destinationChainId))`, the key its `fillStatuses` is read by.
    static func relayHash(_ d: Deposited) -> [UInt8] {
        typealias A = YourAccountSwap.Arg
        let relay: A = .tuple([.word(d.depositor), .word(d.recipient), .word(d.exclusiveRelayer), .word(d.inputToken),
                               .word(d.outputToken), .word(d.inputAmount), .word(d.outputAmount), .uint(d.originChainId),
                               .word(d.depositId), .word(d.fillDeadline), .word(d.exclusivityDeadline), .bytes(d.message)])
        return Keccak256.hash(YourAccountSwap.encode([relay, .uint(d.destinationChainId)]))
    }

    static func fillStatusCall(_ hash: [UInt8]) -> [UInt8] {
        YourAccount.sel("fillStatuses(bytes32)") + hash
    }

    /// `fillStatuses`' answer: 0 unfilled, 1 a slow fill asked for, 2 filled.
    enum Fill: Equatable, Sendable { case waiting, slow, filled }

    static func fill(_ answer: [UInt8]) -> Fill? {
        guard answer.count >= 32, let n = small(Array(answer[0..<32])) else { return nil }
        switch n {
        case 0: return .waiting
        case 1: return .slow
        case 2: return .filled
        default: return nil
        }
    }

    // MARK: - A crossing read off chain (prd §1566)

    /// `FilledRelay`, as the receiving SpokePool emits it: `originChainId`,
    /// `depositId` and the relayer indexed.
    static let filledRelayTopic = "0x" + Keccak256.hexString(Keccak256.hash(Array(
        ("FilledRelay(bytes32,bytes32,uint256,uint256,uint256,uint256,uint256,uint32,uint32,bytes32,bytes32,bytes32,"
         + "bytes32,bytes32,(bytes32,bytes32,uint256,uint8))").utf8)))

    /// A fill as it landed on the receiving network.
    struct Filled: Equatable, Sendable {
        let originChainId: Int
        /// Decimal, as `Crossing.depositId` keeps it (an unsafe deposit's id
        /// is a full 256-bit hash, past any Int).
        let depositId: String
        let depositor: String
        let recipient: String
        let outputToken: String
        let outputAmount: String
    }

    /// The fills among a landed transaction's logs, from the pinned
    /// SpokePool of `dest` only.
    static func filled(_ logs: [[String: Any]], dest: Int) -> [Filled] {
        guard let pool = spokes[dest] else { return [] }
        var out: [Filled] = []
        for log in logs {
            guard let from = (log["address"] as? String)?.lowercased(), from == pool,
                  let topics = (log["topics"] as? [String])?.compactMap(SafeABI.hexBytes), topics.count == 4,
                  SafeABI.hex(topics[0]).lowercased() == filledRelayTopic,
                  let origin = small(topics[1]),
                  let data = (log["data"] as? String).flatMap(SafeABI.hexBytes), data.count == 15 * 32 else { continue }
            func w(_ i: Int) -> [UInt8] { Array(data[(32 * i)..<(32 * i + 32)]) }
            guard let depositor = address(w(8)), let recipient = address(w(11)), let token = address(w(1)) else { continue }
            out.append(Filled(originChainId: origin, depositId: SafeCalldata.decimal(topics[2]), depositor: depositor,
                              recipient: recipient, outputToken: token, outputAmount: SafeCalldata.decimal(w(13))))
        }
        return out
    }

    /// The deposit's id, decimal.
    static func depositId(_ d: Deposited) -> String { SafeCalldata.decimal(d.depositId) }

    /// **A CROSSING SENT FROM ANOTHER DEVICE, READ OFF CHAIN.** The Wallet
    /// saw the account send to a SpokePool; the deposit's own log says the
    /// rest: where it goes, what arrives, its deadline, what a refund would
    /// return. Only a crossing between the account's networks, of ETH or the
    /// dollar, to the account itself or to Across's handler (a swap or an
    /// unwrap on arrival, whose output then counts as a minimum until the
    /// arrival is met); nil for anything else, which lands as before.
    /// `sold` is what left the account when a swap went first ("12 AERO"),
    /// else the deposit's own input is said.
    static func chainCrossing(_ d: Deposited, tx: String, wallet: String, at: Date, sold: String? = nil) -> Crossing? {
        let me = wallet.lowercased()
        guard address(d.depositor) == me, d.originChainId != d.destinationChainId,
              let origin = Op.networks.first(where: { $0.chainId == d.originChainId && spokes[$0.chainId] != nil }),
              let dest = Op.networks.first(where: { $0.chainId == d.destinationChainId && spokes[$0.chainId] != nil }),
              let input = address(d.inputToken), let output = address(d.outputToken), let recipient = address(d.recipient),
              recipient == me || recipient == handler else { return nil }
        let refund: (symbol: String, decimals: Int, said: String)
        if input == bridged(.eth, on: origin.chainId) { refund = ("WETH", 18, "ETH") }
        else if input == bridged(.dollar, on: origin.chainId) { refund = (origin.dollarSymbol, 6, origin.dollarSymbol) }
        else { return nil }
        let arrives: (symbol: String, contract: String?, decimals: Int)
        if output == bridged(.eth, on: dest.chainId) { arrives = ("ETH", nil, 18) }
        else if output == bridged(.dollar, on: dest.chainId) { arrives = (dest.dollarSymbol, output, 6) }
        else { return nil }
        let inUnits = SafeCalldata.decimal(d.inputAmount), outUnits = SafeCalldata.decimal(d.outputAmount)
        let via = recipient == handler
        return Crossing(id: "chain-\(origin.chainId)-\(depositId(d))", account: me, from: origin.chainId, to: dest.chainId,
                        sold: sold ?? "\(Op.spoken(inUnits, decimals: refund.decimals)) \(refund.said)",
                        symbol: arrives.symbol, contract: arrives.contract, decimals: arrives.decimals, outputUnits: outUnits,
                        refundContract: input, refundSymbol: refund.symbol, inputUnits: inUnits, fillDeadline: d.deadline,
                        at: at, tx: tx.lowercased(), relayHash: SafeABI.hex(relayHash(d)),
                        atLeast: via ? true : nil, fallbackContract: via ? output : nil,
                        fallbackSymbol: via ? (output == bridged(.eth, on: dest.chainId) ? "WETH" : dest.dollarSymbol) : nil,
                        fallbackDecimals: via ? arrives.decimals : nil, fallbackUnits: via ? outUnits : nil,
                        refundDecimals: refund.decimals == arrives.decimals ? nil : refund.decimals,
                        depositId: depositId(d))
    }

    /// The crossing a fill finishes: the same deposit (its network, its id,
    /// its depositor), waiting or read filled, its fill not yet met.
    static func crossing(filledBy f: Filled, dest: Int, in list: [Crossing]) -> Crossing? {
        list.first {
            $0.to == dest && $0.from == f.originChainId && $0.depositId == f.depositId && $0.account == f.depositor
                && $0.state != .refunded && $0.fillTx == nil
        }
    }

    /// What the account received in the fill's transaction: its symbol,
    /// contract (nil for ETH) and amount in whole tokens, as the Wallet read it.
    struct Received: Equatable, Sendable {
        let contract: String?
        let symbol: String
        let value: Double
    }

    /// **THE FILL MET.** The crossing is filled by `tx`, and says what came:
    /// what it was to buy, at the amount that came (a swap on arrival pays at
    /// least its minimum); else, for a swap that failed there, the bridged
    /// token the handler paid instead; else, for a crossing read off chain
    /// whose message the phone did not write, whatever the account received.
    static func arrived(_ x: inout Crossing, received: [Received], fillTx: String, at: Date?) {
        x.fillTx = fillTx.lowercased()
        if x.state == .waiting { x.state = .filled }
        x.settledAt = x.settledAt ?? at ?? .now
        guard x.atLeast == true else { return }
        let fb = x.fallbackContract
        let pick = received.first { $0.contract?.lowercased() == x.contract && $0.contract?.lowercased() != fb }
            ?? received.filter { $0.contract?.lowercased() != fb }.max { $0.value < $1.value }
            ?? received.first
        guard let pick else { return }
        let c = pick.contract?.lowercased()
        if let fb, c == fb {
            fellBack(&x)
        } else {
            if c != x.contract { x.contract = c; x.symbol = pick.symbol; x.decimals = 18 }
            if let units = units(pick.value, decimals: x.decimals) { x.outputUnits = units }
        }
        x.atLeast = false
    }

    /// A swap on arrival that failed: what came is the bridged token, exactly.
    private static func fellBack(_ x: inout Crossing) {
        guard let fb = x.fallbackContract else { return }
        x.contract = fb
        x.symbol = x.fallbackSymbol ?? x.symbol
        x.decimals = x.fallbackDecimals ?? x.decimals
        x.outputUnits = x.fallbackUnits ?? x.outputUnits
        x.atLeast = false
    }

    /// `value` whole tokens in base units at `decimals`; nil when it does not read.
    static func units(_ value: Double, decimals: Int) -> String? {
        guard value.isFinite, value > 0, decimals >= 0, decimals <= 36 else { return nil }
        var d = Decimal(value) * pow(10, decimals)
        var r = Decimal()
        NSDecimalRound(&r, &d, 0, .plain)
        let s = NSDecimalNumber(decimal: r).stringValue
        return YourAccountSwap.isPositive(s) ? s : nil
    }

    // MARK: - In words

    /// "Through Across · 0.11% fee": rounded as a pool fee is (§1545).
    static func words(_ leg: Leg) -> String {
        String(localized: "Through Across · \(YourAccountSwap.percent(pips: leg.feePips)) fee")
    }

    /// A swap on arrival in the foot's words: "On Uniswap · 0.05% pool fee
    /// on Ethereum" (prd §1566).
    static func arrivalWords(_ leg: Leg) -> String? {
        leg.swap.map { String(localized: "\(YourAccountSwap.words($0.route)) on \(networkName(leg.to))") }
    }

    /// The same in Details' Swaps row, one line: "Uniswap · 0.05% on Ethereum".
    static func arrivalBrief(_ leg: Leg) -> String? {
        leg.swap.map { String(localized: "\(YourAccountSwap.brief($0.route)) on \(networkName(leg.to))") }
    }

    /// "About 7 seconds", "About 2 minutes": Details' row.
    static func time(_ seconds: Int?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        if s < 90 { return String(localized: "About \(s) seconds") }
        return String(localized: "About \((s + 30) / 60) minutes")
    }

    /// The same inside a line: "about 7 seconds".
    static func about(_ seconds: Int?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        if s < 90 { return String(localized: "about \(s) seconds") }
        return String(localized: "about \((s + 30) / 60) minutes")
    }

    // MARK: - The crossing the Wallet shows (prd §1555)

    /// **ONE ROW PER CROSSING, IN ACTIVITY (user's design, 2026-10-26).** What
    /// this phone sent across, noted before Face ID (device-only, newest
    /// 200) and given its transaction once it lands. The Wallet draws it as
    /// one row — "USDC arriving on Base", then "Swapped 0.02 ETH for USDC",
    /// or "Refunded 0.01 WETH on Ethereum" — and lands none of the legs it
    /// is made of: the sending transaction, the arrival, the refund.
    struct Crossing: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable { case waiting, filled, refunded }
        var id: String
        var account: String
        var from: Int
        var to: Int
        /// What was sold, as it reads: "0.01 ETH".
        var sold: String
        /// What arrives: its symbol, its contract on `to` (nil for ETH), its
        /// decimals and exact amount.
        var symbol: String
        var contract: String?
        var decimals: Int
        var outputUnits: String
        /// What the SpokePool took on `from`: the contract a refund comes
        /// back in (WETH for ETH: the pool refunds its wrapped coin) and the
        /// exact amount, in the same decimals.
        var refundContract: String
        var refundSymbol: String
        var inputUnits: String
        var fillDeadline: Int
        var at: Date
        /// The sending transaction, once it landed.
        var tx: String?
        /// `getV3RelayHash` of the deposit, once its receipt was read.
        var relayHash: String?
        var state: State = .waiting
        /// When it was seen filled or refunded.
        var settledAt: Date?
        /// The legs the Wallet met as this crossing's arrival or refund, by
        /// their ref: kept off the list on every later read too.
        var taken: [String] = []
        // Each below is optional, so a note kept before it existed still reads.
        /// A swap on arrival (prd §1566): `outputUnits` is its minimum until
        /// the arrival is met.
        var atLeast: Bool?
        /// What arrives if that swap fails there: the bridged token, exactly
        /// what was filled.
        var fallbackContract: String?
        var fallbackSymbol: String?
        var fallbackDecimals: Int?
        var fallbackUnits: String?
        /// What a refund is counted in, when not `decimals` (ETH sent for a
        /// token of other decimals).
        var refundDecimals: Int?
        /// The deposit's id at its SpokePool (read off chain, prd §1566),
        /// and the fill's transaction on the receiving network once met.
        var depositId: String?
        var fillTx: String?
    }

    private static let crossingsKey = "yourAccount.across.crossings"
    static let crossingCap = 200
    /// A note that never got its transaction is dropped after this.
    static let unsentAfter: TimeInterval = 24 * 60 * 60
    /// A fill lands in seconds, a slow fill in hours, a refund after the
    /// deadline and the next bundle: an arrival or a refund is matched no
    /// later than this after the note.
    static let matchWindow: TimeInterval = 3 * 24 * 60 * 60

    /// The Wallet's ref for a crossing's row.
    static let refPrefix = "wallet:across:"
    static func ref(_ c: Crossing) -> String { refPrefix + c.id }

    static var crossings: [Crossing] {
        UserDefaults.standard.data(forKey: crossingsKey).flatMap { try? JSONDecoder().decode([Crossing].self, from: $0) } ?? []
    }

    static func save(_ list: [Crossing]) {
        var list = list
        if list.count > crossingCap { list.removeFirst(list.count - crossingCap) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: crossingsKey) }
    }

    static func note(_ crossing: Crossing) {
        save(crossings.filter { $0.id != crossing.id } + [crossing])
    }

    static func update(_ id: String, _ change: (inout Crossing) -> Void) {
        var list = crossings
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        save(list)
    }

    /// Whether `value` whole tokens is exactly `units` at `decimals`.
    static func same(_ value: Double, units: String, decimals: Int) -> Bool {
        guard let u = Decimal(string: units) else { return false }
        let want = NSDecimalNumber(decimal: u / pow(10, decimals)).doubleValue
        return abs(value - want) <= max(want * 1e-9, 1e-15)
    }

    /// Whether `value` whole tokens is at least `units` at `decimals`.
    static func atLeast(_ value: Double, units: String, decimals: Int) -> Bool {
        guard let u = Decimal(string: units), u > 0 else { return false }
        let want = NSDecimalNumber(decimal: u / pow(10, decimals)).doubleValue
        return value >= want - max(want * 1e-9, 1e-15)
    }

    /// A leg the Wallet met settles `x`: kept off the list, its state, and
    /// for a swap on arrival what came (`arrived`).
    static func settle(_ x: inout Crossing, _ state: Crossing.State, ref: String, contract: String?,
                       value: Double, at: Date?) {
        x.taken.append(ref)
        // Move may have read the fill first; a refund settles it.
        if x.state == .waiting || state == .refunded { x.state = state }
        x.settledAt = x.settledAt ?? at ?? .now
        if state == .filled, x.atLeast == true {
            let c = contract?.lowercased()
            if c != x.contract, let fb = x.fallbackContract, c == fb {
                fellBack(&x)
            } else if let u = units(value, decimals: x.decimals) {
                x.outputUnits = u
                x.atLeast = false
            }
        }
    }

    /// The crossing a received leg finishes: its arrival on the destination
    /// (this token, exactly the amount filled), or its refund on the sending
    /// network (from the SpokePool, in what it took, exactly that amount,
    /// after the deadline). Nil for anything else.
    static func settles(wallet: String, chainId: Int, contract: String?, from sender: String?, value: Double, at: Date?,
                        in list: [Crossing]) -> (crossing: Crossing, state: Crossing.State)? {
        let w = wallet.lowercased(), c = contract?.lowercased()
        func inWindow(_ x: Crossing) -> Bool {
            guard let at else { return true }
            return at >= x.at.addingTimeInterval(-10 * 60) && at <= x.at.addingTimeInterval(matchWindow)
        }
        // Filled is also what Move read before the Wallet met the arrival.
        for x in list where x.account == w && x.state != .refunded && x.taken.isEmpty && x.tx != nil && inWindow(x) {
            if x.to == chainId, x.contract == c, same(value, units: x.outputUnits, decimals: x.decimals) {
                return (x, .filled)
            }
            // A swap on arrival (prd §1566): at least its minimum, after it
            // was sent; or, failed there, the bridged token whole, from the handler.
            if x.atLeast == true, x.to == chainId, at.map({ $0 >= x.at }) ?? true {
                if x.contract == c, atLeast(value, units: x.outputUnits, decimals: x.decimals) { return (x, .filled) }
                if let fb = x.fallbackContract, c == fb, sender?.lowercased() == handler,
                   same(value, units: x.fallbackUnits ?? "", decimals: x.fallbackDecimals ?? x.decimals) {
                    return (x, .filled)
                }
            }
            if x.state == .waiting, x.from == chainId, c == x.refundContract, sender.map(isSpoke) == true,
               same(value, units: x.inputUnits, decimals: x.refundDecimals ?? x.decimals),
               at.map({ Int($0.timeIntervalSince1970) > x.fillDeadline }) ?? true {
                return (x, .refunded)
            }
        }
        return nil
    }

    /// What a leg the Wallet read is to a crossing, if anything: one it
    /// already took, a leg of the sending transaction, or the arrival or
    /// refund that settles it. The Wallet lands none of these: the crossing's
    /// own row is the move.
    enum Take: Equatable, Sendable { case taken, sending, settles(Crossing.State) }

    static func take(ref: String, hash: String, received: Bool, wallet: String, chainId: Int, contract: String?,
                     from sender: String?, value: Double, at: Date?, in list: [Crossing]) -> (id: String, take: Take)? {
        let w = wallet.lowercased()
        if let x = list.first(where: { $0.taken.contains(ref) }) { return (x.id, .taken) }
        if !hash.isEmpty, let x = list.first(where: {
            $0.account == w && $0.from == chainId && $0.tx?.lowercased() == hash.lowercased()
        }) { return (x.id, .sending) }
        // The fill's own transaction, met off chain (prd §1566): every leg of it is the crossing's.
        if !hash.isEmpty, let x = list.first(where: {
            $0.account == w && $0.to == chainId && $0.fillTx == hash.lowercased()
        }) { return (x.id, .taken) }
        guard received, let hit = settles(wallet: wallet, chainId: chainId, contract: contract, from: sender,
                                          value: value, at: at, in: list) else { return nil }
        return (hit.crossing.id, .settles(hit.state))
    }

    /// **WHAT COMES BACK IS LISTED (prd §1556).** The token a crossing's
    /// refund returns as — WETH for ETH, since the pool refunds its wrapped
    /// coin, else the dollar — once it is refunded or its deadline passed
    /// unfilled; nil before. Move remembers it on the sending network, so
    /// its holdings read the WETH before the Wallet's next holdings read and
    /// it can be sent or swapped from there.
    static func returning(_ c: Crossing, now: Int) -> Op.Token? {
        guard c.tx != nil, c.state == .refunded || (c.state == .waiting && now > c.fillDeadline),
              SafeABI.word(address: c.refundContract) != nil else { return nil }
        return Op.Token(symbol: c.refundSymbol, decimals: c.refundDecimals ?? c.decimals, contract: c.refundContract.lowercased())
    }

    static func networkName(_ chainId: Int) -> String {
        Op.networks.first { $0.chainId == chainId }?.name ?? String(chainId)
    }

    /// The row's title, by what happened: "USDC arriving on Base", "Swapped
    /// 0.02 ETH for USDC", "Refunded 0.01 WETH on Ethereum".
    static func title(_ c: Crossing) -> String {
        switch c.state {
        case .waiting:
            return String(localized: "\(c.symbol) arriving on \(networkName(c.to))")
        case .filled:
            return String(localized: "Swapped \(c.sold) for \(c.symbol)")
        case .refunded:
            let back = Op.display(c.inputUnits, decimals: c.refundDecimals ?? c.decimals)
            return String(localized: "Refunded \(back) \(c.refundSymbol) on \(networkName(c.from))")
        }
    }

    /// The row's line, before its time: "Swapped 0.01 ETH on Ethereum",
    /// "Ethereum to Base", "The swap to Base wasn't filled"; past the
    /// deadline and not filled, "Not filled · coming back on Ethereum" until
    /// the refund is seen.
    static func line(_ c: Crossing, now: Int) -> String {
        switch c.state {
        case .waiting where now > c.fillDeadline:
            return String(localized: "Not filled · coming back on \(networkName(c.from))")
        case .waiting:
            return String(localized: "Swapped \(c.sold) on \(networkName(c.from))")
        case .filled:
            return String(localized: "\(networkName(c.from)) to \(networkName(c.to))")
        case .refunded:
            return String(localized: "The swap to \(networkName(c.to)) wasn't filled")
        }
    }

    /// The row's figure: what arrives (or arrived), or what came back.
    /// The figure alone, as the row's other figures stand ("24.87"); the
    /// title says the token. A dollar keeps its cents ("49.70").
    static func figure(_ c: Crossing) -> String {
        let units = c.state == .refunded ? c.inputUnits : c.outputUnits
        let decimals = c.state == .refunded ? c.refundDecimals ?? c.decimals : c.decimals
        let shown = Op.display(units, decimals: decimals, places: decimals == 6 ? 2 : 6)
        guard decimals == 6 else { return shown }
        let parts = shown.split(separator: ".", omittingEmptySubsequences: false)
        let cents = parts.count > 1 ? String(parts[1]) : ""
        return String(parts[0]) + "." + cents + String(repeating: "0", count: max(0, 2 - cents.count))
    }
}
