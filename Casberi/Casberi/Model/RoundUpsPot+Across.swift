import Foundation

/// **CHANGE CARRIED TO ROUND-UPS FROM ETHEREUM OR ROBINHOOD (prd §1690).**
/// One operation on the network the send is on: approve that network's
/// dollar to Across's SpokePool for the input, then its deposit to Base with
/// a message. On Base, Across's MulticallHandler approves Aave's Pool for
/// exactly what arrived, supplies it on behalf of your account, and drains
/// what is left to the account. Like §1574's bridged save, the message names
/// no fallback recipient: a call that fails reverts the fill, and Across
/// refunds the account on the network it left.
///
/// Pure (Foundation, `SafeABI`, `YourAccountSwap`'s encoder, the Across
/// pins): `round-ups-pot-selftest.sh` compiles it.
extension RoundUpsPot {
    typealias Across = YourAccountAcross
    private typealias A = YourAccountSwap.Arg

    /// Aave's USDC market on Base: where Round-ups is kept.
    static var market: AaveLend.Market? { AaveLend.market(chainId: home, symbol: "USDC") }

    /// Whether a carry can leave from `chainId` for Round-ups on Base.
    static func acrossCarries(from chainId: Int) -> Bool {
        chainId != home && Across.carries(.dollar, from: chainId, to: home)
    }

    /// `abi.encode(Instructions)` for the handler on Base: approve the Pool
    /// for `budget`, supply it on behalf of `account`, drain the rest to the
    /// account; the zero fallback reverts the fill if any call fails.
    static func message(budget: String, account: String) -> [UInt8]? {
        guard let m = market, let amount = A.amount(budget), YourAccountSwap.isPositive(budget),
              SafeABI.word(address: account) != nil else { return nil }
        let approve = YourAccountSwap.call("approve(address,uint256)", [.address(m.pool), amount])
        let supply = YourAccountSwap.call("supply(address,uint256,address,uint16)",
                                          [.address(m.asset), amount, .address(account), .uint(0)])
        let drain = YourAccountSwap.call("drainLeftoverTokens(address,address)", [.address(m.asset), .address(account)])
        let calls: A = .array([.tuple([.address(m.asset), .bytes(approve), .uint(0)]),
                               .tuple([.address(m.pool), .bytes(supply), .uint(0)]),
                               .tuple([.address(Across.handler), .bytes(drain), .uint(0)])])
        return YourAccountSwap.encode([.tuple([calls, .address(YourAccountSwap.native)])])
    }

    /// Across's fee question for this exact message, to the handler on Base.
    static func feesURL(from: Int, amount: String, account: String, message: [UInt8]) -> URL? {
        guard acrossCarries(from: from), let input = Across.bridged(.dollar, on: from),
              let output = Across.bridged(.dollar, on: home), YourAccountSwap.isPositive(amount) else { return nil }
        var parts = URLComponents(string: Across.feesEndpoint)
        parts?.queryItems = [URLQueryItem(name: "inputToken", value: input), URLQueryItem(name: "outputToken", value: output),
                             URLQueryItem(name: "originChainId", value: String(from)),
                             URLQueryItem(name: "destinationChainId", value: String(home)),
                             URLQueryItem(name: "amount", value: amount), URLQueryItem(name: "depositor", value: account.lowercased()),
                             URLQueryItem(name: "recipient", value: Across.handler),
                             URLQueryItem(name: "message", value: SafeABI.hex(message))]
        return parts?.url
    }

    /// The two calls on the network the change is on: approve the dollar to
    /// the SpokePool, then its deposit carrying the message; `budget` is
    /// what arrives on Base, exactly. `input` is `PrivateBridge.input`'s:
    /// the budget, Across's fee and half again, under Across's 5% ceiling.
    static func calls(from: Int, input: String, budget: String, fees: Across.Fees, message: [UInt8],
                      account: String) -> [Across.Call]? {
        guard acrossCarries(from: from), let pool = Across.spoke(from), fees.spokePool == pool,
              let token = Across.bridged(.dollar, on: from), let output = Across.bridged(.dollar, on: home),
              let inAmount = A.amount(input), let outAmount = A.amount(budget), let approveAmount = SafeABI.word(uint256: input),
              YourAccountOp.atMost(budget, input), SafeABI.word(address: account) != nil, fees.exclusivity >= 0 else { return nil }
        let deposit = YourAccountSwap.call(Across.depositSignature, [
            .address(account), .address(Across.handler), .address(token), .address(output),
            inAmount, outAmount, .uint(home), .address(fees.exclusiveRelayer),
            .uint(fees.quoteTimestamp), .uint(fees.fillDeadline), .uint(fees.exclusivity), .bytes(message),
        ])
        return [Across.Call(to: token, value: "0", data: Across.approveSelector + YourAccount.w(pool) + approveAmount),
                Across.Call(to: pool, value: "0", data: deposit)]
    }
}
