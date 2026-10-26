import Foundation

/// **A SWAP TO ANOTHER NETWORK, THROUGH ACROSS (prd §1553).** Across is a
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
/// one of those by the pools (§1542), in the same transaction; a swap on
/// the receiving network is not built.
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
    static func feesURL(_ asset: Asset, from: Int, to: Int, amount: String, account: String) -> URL? {
        guard carries(asset, from: from, to: to), let input = bridged(asset, on: from),
              let output = bridged(asset, on: to), YourAccountSwap.isPositive(amount) else { return nil }
        var parts = URLComponents(string: feesEndpoint)
        var items = [URLQueryItem(name: "inputToken", value: input), URLQueryItem(name: "outputToken", value: output),
                     URLQueryItem(name: "originChainId", value: String(from)),
                     URLQueryItem(name: "destinationChainId", value: String(to)),
                     URLQueryItem(name: "amount", value: amount), URLQueryItem(name: "depositor", value: account.lowercased())]
        if asset == .eth {
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

    static let depositSignature = "deposit(bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,bytes32,uint32,uint32,uint32,bytes)"
    static let approveSelector = YourAccountSwap.approveSelector

    /// The SpokePool's `deposit`, the account as depositor (so a refund is
    /// the account's), the account as recipient (the handler for ETH).
    static func deposit(_ leg: Leg, fees: Fees, account: String) -> [UInt8]? {
        typealias A = YourAccountSwap.Arg
        guard let input = bridged(leg.asset, on: leg.from), let output = bridged(leg.asset, on: leg.to),
              let inAmount = A.amount(leg.inputAmount), let outAmount = A.amount(leg.outputAmount),
              SafeABI.word(address: account) != nil, fees.exclusivity >= 0 else { return nil }
        let recipient: String
        let note: [UInt8]
        switch leg.asset {
        case .eth:
            guard let m = message(to: leg.to, amount: leg.outputAmount, account: account) else { return nil }
            recipient = handler
            note = m
        case .dollar:
            recipient = account
            note = []
        }
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
        switch leg.asset {
        case .eth:
            guard word(d, 1).flatMap(address) == handler,
                  note == message(to: leg.to, amount: leg.outputAmount, account: account) else { return nil }
        case .dollar:
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

    // MARK: - In words

    /// "Through Across · 0.11% fee": rounded as a pool fee is (§1545).
    static func words(_ leg: Leg) -> String {
        String(localized: "Through Across · \(YourAccountSwap.percent(pips: leg.feePips)) fee")
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

    // MARK: - The crossing the Wallet shows (prd §1553)

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
            if x.state == .waiting, x.from == chainId, c == x.refundContract, sender.map(isSpoke) == true,
               same(value, units: x.inputUnits, decimals: x.decimals),
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
        guard received, let hit = settles(wallet: wallet, chainId: chainId, contract: contract, from: sender,
                                          value: value, at: at, in: list) else { return nil }
        return (hit.crossing.id, .settles(hit.state))
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
            let back = Op.display(c.inputUnits, decimals: c.decimals)
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
        let shown = Op.display(units, decimals: c.decimals, places: c.decimals == 6 ? 2 : 6)
        guard c.decimals == 6 else { return shown }
        let parts = shown.split(separator: ".", omittingEmptySubsequences: false)
        let cents = parts.count > 1 ? String(parts[1]) : ""
        return String(parts[0]) + "." + cents + String(repeating: "0", count: max(0, 2 - cents.count))
    }
}
