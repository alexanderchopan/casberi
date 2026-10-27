import Foundation

/// **ROUND-UPS SAVED FROM BASE OR ROBINHOOD (prd §1574, user: "yes do phase
/// b").** A save with nothing on Ethereum: one operation on the network the
/// money is on approves its dollar to Across's SpokePool and deposits it with
/// a message; on Ethereum Across's MulticallHandler approves the ppUSDC
/// router, runs the deposit this phone proved, and pays what is left back to
/// the account.
///
/// - **The note is yours whoever pays.** The proof binds the note data, never
///   the sender (PoolVault), and ragequit pays the proof's owner — your
///   account — so Take it back works on a deposit the handler made.
/// - **A deposit that cannot run on Ethereum is refunded where it left.** The
///   message names no fallback recipient, so a failed call reverts the fill;
///   the deposit expires and Across refunds the account on its own network,
///   never strands USDC on Ethereum where there may be no ETH for gas.
/// - **Across is paid half again its quoted fee**: a fill that runs a deposit
///   is gas-heavy, and 0xBow measured fills priced at the quote going unfilled
///   (`ACROSS_RELAYER_GAS_HEADROOM_BPS`, 5000).
/// - **Registration stays on Ethereum**: the keystore takes the viewing key
///   only from the account itself, so an account not registered there is
///   told so and nothing is bridged.
enum PrivateBridge {
    typealias Op = YourAccountOp
    typealias Across = YourAccountAcross
    typealias A = YourAccountSwap.Arg

    static var ethereum: Int { RoundUps.ethereumPool }

    /// Half again the quoted fee, for the deposit's gas.
    static let gasHeadroomBps = 5_000

    /// Whether a save can leave from `chainId`: a network Across carries the
    /// dollar from to Ethereum.
    static func carries(from chainId: Int) -> Bool {
        chainId != ethereum && Across.carries(.dollar, from: chainId, to: ethereum)
    }

    /// `abi.encode(Instructions)` for the handler on Ethereum: approve the
    /// router for `budget`, run the deposit, drain what is left to the
    /// account; the zero fallback recipient reverts the fill if any call fails.
    static func message(router: String, deposit: [UInt8], budget: String, account: String) -> [UInt8]? {
        guard let usdc = Across.bridged(.dollar, on: ethereum), let amount = A.amount(budget),
              SafeABI.word(address: account) != nil, SafeABI.word(address: router) != nil, !deposit.isEmpty else { return nil }
        let approve = YourAccountSwap.call("approve(address,uint256)", [.address(router), amount])
        let drain = YourAccountSwap.call("drainLeftoverTokens(address,address)", [.address(usdc), .address(account)])
        let calls: A = .array([.tuple([.address(usdc), .bytes(approve), .uint(0)]),
                               .tuple([.address(router), .bytes(deposit), .uint(0)]),
                               .tuple([.address(Across.handler), .bytes(drain), .uint(0)])])
        return YourAccountSwap.encode([.tuple([calls, .address(YourAccountSwap.native)])])
    }

    /// Across's fee question for this exact message, to the handler.
    static func feesURL(from: Int, amount: String, account: String, message: [UInt8]) -> URL? {
        guard carries(from: from), let input = Across.bridged(.dollar, on: from),
              let output = Across.bridged(.dollar, on: ethereum), YourAccountSwap.isPositive(amount) else { return nil }
        var parts = URLComponents(string: Across.feesEndpoint)
        parts?.queryItems = [URLQueryItem(name: "inputToken", value: input), URLQueryItem(name: "outputToken", value: output),
                             URLQueryItem(name: "originChainId", value: String(from)),
                             URLQueryItem(name: "destinationChainId", value: String(ethereum)),
                             URLQueryItem(name: "amount", value: amount), URLQueryItem(name: "depositor", value: account.lowercased()),
                             URLQueryItem(name: "recipient", value: Across.handler),
                             URLQueryItem(name: "message", value: SafeABI.hex(message))]
        return parts?.url
    }

    /// What is sent so that `budget` arrives: the budget, the fee Across
    /// asked for it, and half that fee again; nil when the fee is more than
    /// Across's ceiling (`maxFeeBps`) or the answer is malformed.
    static func input(budget: String, quotedOutput: String) -> String? {
        guard YourAccountSwap.isPositive(budget), Op.atMost(quotedOutput, budget),
              let b = Decimal(string: budget), let o = Decimal(string: quotedOutput) else { return nil }
        let fee = b - o
        var extra = fee * Decimal(gasHeadroomBps) / 10_000, up = Decimal()
        NSDecimalRound(&up, &extra, 0, .up)
        let total = b + fee + up
        guard (total - b) * 10_000 <= b * Decimal(Across.maxFeeBps) else { return nil }
        return NSDecimalNumber(decimal: total).stringValue
    }

    /// The two calls on the network the money is on: approve the dollar to
    /// the SpokePool, then its deposit carrying the message; `budget` is what
    /// arrives on Ethereum, exactly.
    static func calls(from: Int, input: String, budget: String, fees: Across.Fees, message: [UInt8],
                      account: String) -> [Across.Call]? {
        guard let pool = Across.spoke(from), fees.spokePool == pool,
              let token = Across.bridged(.dollar, on: from), let output = Across.bridged(.dollar, on: ethereum),
              let inAmount = A.amount(input), let outAmount = A.amount(budget), let approveAmount = SafeABI.word(uint256: input),
              Op.atMost(budget, input), SafeABI.word(address: account) != nil, fees.exclusivity >= 0 else { return nil }
        let deposit = YourAccountSwap.call(Across.depositSignature, [
            .address(account), .address(Across.handler), .address(token), .address(output),
            inAmount, outAmount, .uint(ethereum), .address(fees.exclusiveRelayer),
            .uint(fees.quoteTimestamp), .uint(fees.fillDeadline), .uint(fees.exclusivity), .bytes(message),
        ])
        return [Across.Call(to: token, value: "0", data: Across.approveSelector + YourAccount.w(pool) + approveAmount),
                Across.Call(to: pool, value: "0", data: deposit)]
    }
}
