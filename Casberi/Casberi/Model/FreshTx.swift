import Foundation

/// **A FRESH ADDRESS'S OWN TRANSACTION ON ETHEREUM (prd §1567).**
///
/// What a stranger pays a fresh address is moved into your private balance
/// by a deposit SENT FROM THAT ADDRESS (prd §1560), its gas out of what
/// arrived. On Sepolia the DEBUG `TestnetTx` signs it; on Ethereum this does,
/// and it can make only the transactions a fresh address has any reason to
/// send — by construction, as `TestnetTx` can make nothing off a testnet:
///
/// - a deposit to one of the network's yield routers, by the router's own
///   deposit function (`depositExactSharesNative` to ppETH's, carrying the
///   ETH; `depositExactShares` to a token's, carrying none);
/// - a token's `approve` of exactly that token's own router, carrying no ETH;
/// - on Ethereum, for a token Railgun holds (prd §1713 item 7, §1724): its
///   `approve` of Railgun's proxy, and the proxy's `shield`, carrying no ETH;
/// - on Ethereum, the proxy's `transact` carrying no ETH (prd §1726): a send
///   from your Railgun wallet that a fresh SENDER submits when no broadcaster
///   can. The key cannot spend with it: what moves is fixed by a proof only
///   your Railgun wallet makes, behind Face ID; the key only pays the gas.
/// - on Base or Robinhood, Across's deposit of the address's ETH to ITSELF
///   on Ethereum (prd §1878), no message: money paid there goes home.
///
/// Nothing else can be built here, so no fresh key can be made to pay
/// anyone, call anything, or sign anywhere but these four networks. The bytes are EIP-1559
/// (type 2), the same RLP as `TestnetTx`, pinned against viem's by
/// `private-money-selftest.sh`.
///
/// Pure (Foundation + `Keccak256`, `TestnetTx`'s RLP, `PrivacyNetwork`).
enum FreshTx {

    /// `depositExactSharesNative((uint256[2],uint256[2][2],uint256[2],uint256[4]),(bytes32,bytes),bytes)`.
    static let nativeDeposit = "0x31c09bb4"
    /// `depositExactShares(…,bytes,uint256)`: a token's router, the token approved first.
    static let tokenDeposit = "0xc63148e8"
    static let approve = "0x095ea7b3"

    /// Whether a fresh address may send this on `network`: a router's
    /// deposit, or a token's approval of its own router. Nothing else.
    static func allowed(to: String, data: String, value: String, network: PrivacyNetwork) -> Bool {
        guard !network.isTest, PrivateMoney.isAddress(to), let carried = TestnetTx.quantity(value) else { return false }
        let t = to.lowercased(), d = data.lowercased()
        if let pool = network.yield.first(where: { $0.router.lowercased() == t }) {
            return pool.native ? (d.hasPrefix(nativeDeposit) && !carried.isEmpty) : (d.hasPrefix(tokenDeposit) && carried.isEmpty)
        }
        // Railgun, Ethereum only: the proxy's shield, or a listed token's
        // approval of the proxy. Nothing carries ETH.
        if network.chainId == railgunChain {
            if t == railgunProxy { return (d.hasPrefix(railgunShield) || d.hasPrefix(railgunTransact)) && carried.isEmpty }
            // A private swap (prd §1875): the classic relay adapter's proved
            // `relay`, carrying no ETH; never its 7702 twin.
            if t == railgunRelayAdapt { return d.hasPrefix(railgunRelay) && carried.isEmpty }
            if railgunTokens.contains(where: { $0.contract.lowercased() == t }) {
                guard d.hasPrefix(approve), d.count == 2 + 8 + 128, carried.isEmpty else { return false }
                return String(d.dropFirst(10).prefix(64)) == String(repeating: "0", count: 24) + railgunProxy.dropFirst(2)
            }
        }
        guard let pool = network.yield.first(where: { !$0.native && $0.underlying.lowercased() == t }),
              d.hasPrefix(approve), d.count == 2 + 8 + 128, carried.isEmpty else { return false }
        let spender = String(d.dropFirst(10).prefix(64))
        return spender == String(repeating: "0", count: 24) + pool.router.dropFirst(2).lowercased()
    }

    /// One transaction, nil unless `allowed`: no mainnet transaction of any
    /// other shape can come out of this file.
    struct Tx: Equatable {
        let chainId: Int
        let nonce: String
        let maxPriorityFeePerGas: String
        let maxFeePerGas: String
        let gas: String
        let to: String
        let value: String
        let data: String

        init?(network: PrivacyNetwork, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
              gas: String, to: String, value: String, data: String) {
            guard FreshTx.allowed(to: to, data: data, value: value, network: network) else { return nil }
            for q in [nonce, maxPriorityFeePerGas, maxFeePerGas, gas, value] where TestnetTx.quantity(q) == nil { return nil }
            guard let address = TestnetTx.bytes(to), address.count == 20, TestnetTx.bytes(data) != nil else { return nil }
            self.init(chainId: network.chainId, nonce: nonce, maxPriorityFeePerGas: maxPriorityFeePerGas,
                      maxFeePerGas: maxFeePerGas, gas: gas, to: to, value: value, data: data)
        }

        /// Only after one of the checked inits above has allowed it.
        fileprivate init(chainId: Int, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
                         gas: String, to: String, value: String, data: String) {
            self.chainId = chainId; self.nonce = nonce; self.maxPriorityFeePerGas = maxPriorityFeePerGas
            self.maxFeePerGas = maxFeePerGas; self.gas = gas; self.to = to; self.value = value; self.data = data
        }

        private var fields: [TestnetTx.RLP] {
            [.bytes(TestnetTx.minimal(UInt64(chainId))),
             .bytes(TestnetTx.quantity(nonce)!),
             .bytes(TestnetTx.quantity(maxPriorityFeePerGas)!),
             .bytes(TestnetTx.quantity(maxFeePerGas)!),
             .bytes(TestnetTx.quantity(gas)!),
             .bytes(TestnetTx.bytes(to)!),
             .bytes(TestnetTx.quantity(value)!),
             .bytes(TestnetTx.bytes(data)!),
             .list([])]
        }

        /// `0x02 ‖ rlp([chainId, nonce, tip, maxFee, gas, to, value, data, []])`.
        var unsigned: [UInt8] { [0x02] + TestnetTx.RLP.list(fields).encoded }

        /// What the fresh key signs.
        var signingHash: [UInt8] { Keccak256.hash(unsigned) }

        /// The raw transaction `eth_sendRawTransaction` takes.
        func signed(yParity: Int, r: [UInt8], s: [UInt8]) -> [UInt8]? {
            guard yParity == 0 || yParity == 1, r.count == 32, s.count == 32 else { return nil }
            return [0x02] + TestnetTx.RLP.list(fields + [.bytes(yParity == 0 ? [] : [1]),
                                                         .bytes(TestnetTx.stripped(r)), .bytes(TestnetTx.stripped(s))]).encoded
        }
    }

    /// A token's approval of its router for `amount` (base units, decimal).
    static func approval(pool: PrivacyNetwork.YieldPool, amount: String) -> (to: String, data: String)? {
        guard !pool.native, let word = PrivateYield.uint(amount) else { return nil }
        return (pool.underlying, approve + String(repeating: "0", count: 24) + pool.router.dropFirst(2).lowercased() + word)
    }

    /// The gas a fresh address's approval is held to: measured at 55,558 and
    /// 55,570 (mainnet simulation), ×1.25 rounded up, with room.
    static let approveGas = 80_000

    // MARK: - Railgun (prd §1713 item 7, §1724)

    static let railgunChain = 1
    /// Railgun's proxy on Ethereum (`RailgunPocket.proxy`).
    static let railgunProxy = "0xfa7093cdd9ee6932b4eb2c9e1cde7ce00b1fa4b9"
    /// `shield(((bytes32,(uint8,address,uint256),uint120),(bytes32[3],bytes32))[])`,
    /// from Railgun's own ABI (engine 9.9.1, RailgunSmartWallet).
    static let railgunShield = "0x044a40c3"
    /// `transact((…)[])`, Railgun's proved send (an unshield here), from the same ABI.
    static let railgunTransact = "0xd8ae136a"
    /// Railgun's classic relay adapter on Ethereum (`NETWORK_CONFIG.relayAdaptContract`),
    /// the one a private swap goes through (prd §1875).
    static let railgunRelayAdapt = "0xac9f360ae85469b27aeddeafc579ef2d052ad405"
    /// Its `relay((…)[],(bytes31,bool,uint256,(address,bytes,uint256)[]))`, from
    /// Railgun's own ABI (engine 9.9.1, V2/RelayAdapt).
    static let railgunRelay = "0x28223a77"
    /// The most a fresh sender's unshield may use (measured 516,069 from a
    /// plain key, §1713 item 8), with room; estimated each time and held to it.
    static let railgunSendGas = 900_000
    /// The most a fresh sender's private swap may use (prd §1875): Railgun's
    /// SDK floors a relay-adapt call's limit at 3,200,000
    /// (`MINIMUM_RELAY_ADAPT_CROSS_CONTRACT_CALLS_GAS_LIMIT_V2`); real swaps
    /// used 2.23–2.29M (mainnet, 2026-11-18). Estimated each time, held here.
    static let railgunSwapGas = 3_600_000
    /// The most a fresh address's shield may use; estimated each time and
    /// held to this.
    static let railgunShieldGas = 600_000

    /// A token a fresh address is watched for, to move into Railgun: the
    /// common Ethereum tokens, each asked by `balanceOf` (a node cannot list
    /// what an address holds). ETH and USDC stay Privacy Pools'.
    struct RailgunToken: Equatable {
        let symbol: String
        let contract: String
        let decimals: Int
    }

    static let railgunTokens: [RailgunToken] = [
        .init(symbol: "DAI", contract: "0x6b175474e89094c44da98b954eedeac495271d0f", decimals: 18),
        .init(symbol: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", decimals: 6),
        .init(symbol: "WBTC", contract: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", decimals: 8),
        .init(symbol: "WETH", contract: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", decimals: 18),
        .init(symbol: "LINK", contract: "0x514910771af9ca656af840dff83e8264ecf986ca", decimals: 18),
        .init(symbol: "UNI", contract: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", decimals: 18),
        .init(symbol: "AAVE", contract: "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9", decimals: 18),
    ]

    static func railgunToken(symbol: String?) -> RailgunToken? {
        guard let symbol else { return nil }
        return railgunTokens.first { $0.symbol == symbol }
    }

    /// A listed token's approval of Railgun's proxy for `amount` (base units, decimal).
    static func railgunApproval(_ token: RailgunToken, amount: String) -> (to: String, data: String)? {
        guard let word = PrivateYield.uint(amount) else { return nil }
        return (token.contract, approve + String(repeating: "0", count: 24) + railgunProxy.dropFirst(2) + word)
    }

    // MARK: - Home to Ethereum (prd §1878)

    /// **RECEIVE ON BASE OR ROBINHOOD, EARN ON ETHEREUM (prd §1878).** The
    /// same address is good on every EVM network, so ETH paid to it on Base
    /// or Robinhood is sent HOME: one Across deposit from the address to
    /// itself on Ethereum, ETH in, ETH out (a SpokePool pays an address with
    /// no code native ETH), no message. Once it lands there the Ethereum
    /// look moves it in as it moves anything paid there. A deposit Across
    /// does not fill is refunded to the address where it left.
    struct HomeOrigin: Equatable {
        let name: String
        let chainId: Int
        /// The network's WETH: what a SpokePool takes for native ETH.
        let weth: String
        /// Across's SpokePool there (`YourAccountAcross.spokes`, held equal
        /// by `private-money-selftest.sh`).
        let spoke: String
        /// The network's dollar (prd §1880): USDC on Base, USDG on Robinhood,
        /// both 6 decimals (`YourAccountOp`'s, held equal by `FreshAwayTests`).
        let dollar: String
        let dollarSymbol: String
    }

    static let homeOrigins: [HomeOrigin] = [
        .init(name: "Base", chainId: 8453, weth: "0x4200000000000000000000000000000000000006",
              spoke: "0x09aea4b2242abc8bb4bb78d537a67a245a7bec64",
              dollar: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", dollarSymbol: "USDC"),
        .init(name: "Robinhood", chainId: 4663, weth: "0x0bd7d308f8e1639fab988df18a8011f41eacad73",
              spoke: "0xd29c85f15df544ba632c9e25829fd29d767d7978",
              dollar: "0x5fc5360d0400a0fd4f2af552add042d716f1d168", dollarSymbol: "USDG"),
    ]

    /// Ethereum's USDC: what a dollar arrives as, and leaves as.
    static let homeUSDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    /// Ethereum's WETH: what the deposit names as its output.
    static let homeWETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
    static let homeChain = 1

    /// Across's `deposit(bytes32 depositor, bytes32 recipient, bytes32
    /// inputToken, bytes32 outputToken, uint256 inputAmount, uint256
    /// outputAmount, uint256 destinationChainId, bytes32 exclusiveRelayer,
    /// uint32 quoteTimestamp, uint32 fillDeadline, uint32 exclusivityParameter,
    /// bytes message)`.
    static let homeSignature = "deposit(bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,bytes32,uint32,uint32,uint32,bytes)"
    static var homeSelector: String {
        "0x" + Keccak256.hexString(Array(Keccak256.hash(Array(homeSignature.utf8)).prefix(4)))
    }

    /// The most the deposit may use, estimated each time and held to this
    /// (a native deposit is about 80,000; room for an L2's own overhead).
    static let homeGas = 200_000

    /// What leaves: everything but the gas the deposit may cost, nil when
    /// that leaves nothing.
    static func homeInput(balance: String, maxFee: String, gas: Int = homeGas) -> String? {
        guard let have = Decimal(string: balance), let fee = Decimal(string: maxFee), gas > 0 else { return nil }
        let left = have - Decimal(gas) * fee
        return left > 0 ? PrivateMoney.plain(left) : nil
    }

    /// Whether Across's quote is worth taking: what arrives is at least what
    /// Ethereum's look would move (`floor`, the pool's least plus the
    /// deposit's gas there), and Across keeps at most 5% of what leaves.
    static func homeWorthIt(input: String, output: String, floor: String) -> Bool {
        guard let i = Decimal(string: input), let o = Decimal(string: output), let f = Decimal(string: floor),
              i > 0, o > 0, o <= i else { return false }
        return o >= f && (i - o) * 10_000 <= i * 500
    }

    /// The deposit's data: the address as depositor (its refund) and as
    /// recipient, WETH in and out, to Ethereum, no message.
    static func homeDeposit(_ origin: HomeOrigin, address: String, input: String, output: String,
                            relayer: String, quoteTimestamp: Int, fillDeadline: Int, exclusivity: Int) -> String? {
        guard PrivateMoney.isAddress(address), PrivateMoney.isAddress(relayer),
              let i = PrivateYield.uint(input), let o = PrivateYield.uint(output),
              quoteTimestamp > 0, fillDeadline > 0, exclusivity >= 0,
              (exclusivity == 0) == (relayer.lowercased() == "0x" + String(repeating: "0", count: 40)) else { return nil }
        func word(_ a: String) -> String { String(repeating: "0", count: 24) + a.dropFirst(2).lowercased() }
        func small(_ n: Int) -> String { PrivateYield.uint(String(n)) ?? "" }
        let words = [word(address), word(address), word(origin.weth), word(homeWETH), i, o, small(homeChain),
                     word(relayer), small(quoteTimestamp), small(fillDeadline), small(exclusivity),
                     small(12 * 32), small(0)]
        guard words.allSatisfy({ $0.count == 64 }) else { return nil }
        return homeSelector + words.joined()
    }

    /// Whether `from` may send this on `chainId`: exactly a home deposit as
    /// `homeDeposit` writes it, to that network's SpokePool, its value the
    /// amount deposited. Read back word by word, so no fresh key can be made
    /// to send anything anywhere else, or to anyone else.
    /// With no value it is WETH the SpokePool pulls (a refund going home
    /// again, prd §1882), approved first; with a value, native ETH.
    static func homeAllowed(to: String, data: String, value: String, chainId: Int, from: String) -> Bool {
        guard let origin = homeOrigins.first(where: { $0.chainId == chainId }), to.lowercased() == origin.spoke,
              PrivateMoney.isAddress(from), let carried = TestnetTx.quantity(value) else { return false }
        let d = data.lowercased()
        guard d.hasPrefix(homeSelector), d.count == 10 + 13 * 64 else { return false }
        let words = (0..<13).map { i in String(d.dropFirst(10 + i * 64).prefix(64)) }
        func address(_ w: String) -> String? {
            w.hasPrefix(String(repeating: "0", count: 24)) ? "0x" + w.dropFirst(24) : nil
        }
        let me = from.lowercased()
        guard address(words[0]) == me, address(words[1]) == me,
              address(words[2]) == origin.weth, address(words[3]) == homeWETH,
              carried.isEmpty || PrivateMoney.decimal(hex: "0x" + words[4]) == PrivateMoney.decimal(hex: value),
              words[6] == PrivateYield.uint(String(homeChain)),
              address(words[7]) != nil,
              words[11] == PrivateYield.uint(String(12 * 32)), words[12] == PrivateYield.uint("0") else { return false }
        // What arrives is never more than what leaves.
        guard let i = Decimal(string: PrivateMoney.decimal(hex: "0x" + words[4])),
              let o = Decimal(string: PrivateMoney.decimal(hex: "0x" + words[5])), o > 0, o <= i else { return false }
        return true
    }
}

// MARK: - Away from Ethereum (prd §1879)

extension FreshTx {
    /// **SEND FROM YOUR PRIVATE BALANCE TO BASE OR ROBINHOOD (prd §1879).**
    /// The mirror of home: your private ETH is withdrawn to a fresh sender on
    /// Ethereum, and the sender makes one Across deposit of it to Base or
    /// Robinhood, to Across's MulticallHandler with exactly the message Swap's
    /// own crossings carry (`YourAccountAcross.message(to:amount:account:)`,
    /// held equal by `CasberiTests/FreshAwayTests`): unwrap what arrives and
    /// pay it to the recipient, the recipient the fallback. So an account
    /// (a contract) gets ETH, not WETH.
    static let awaySpoke = "0x5c7bcd6e7de5423a257d81b442095a1a6ced35c5"
    static let awayHandler = "0x0f7ae28de1c8532170ad4ee566b5801485c13a0e"
    static let awayGas = 200_000

    private static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    private static func addressWord(_ a: String) -> String { String(repeating: "0", count: 24) + a.dropFirst(2).lowercased() }

    /// The handler's message: unwrap exactly `amount` of the destination's
    /// WETH, drain its ETH to `payee`, `payee` the fallback. Hex, no 0x.
    static func awayMessage(to chainId: Int, amount: String, payee: String) -> String? {
        guard let origin = homeOrigins.first(where: { $0.chainId == chainId }), PrivateMoney.isAddress(payee),
              let units = PrivateYield.uint(amount) else { return nil }
        func n(_ v: Int) -> String { PrivateYield.uint(String(v)) ?? "" }
        let unwrap = selector("withdraw(uint256)") + units                                   // 36 bytes
        let drain = selector("drainLeftoverTokens(address,address)") + addressWord("0x" + String(repeating: "0", count: 40))
            + addressWord(payee)                                                              // 68 bytes
        func padded(_ hex: String) -> String {
            let bytes = hex.count / 2
            return hex + String(repeating: "0", count: ((bytes + 31) / 32 * 32 - bytes) * 2)
        }
        let first = addressWord(origin.weth) + n(0x60) + n(0) + n(unwrap.count / 2) + padded(unwrap)
        let second = addressWord(awayHandler) + n(0x60) + n(0) + n(drain.count / 2) + padded(drain)
        let calls = n(2) + n(0x40) + n(0x40 + first.count / 2) + first + second
        return n(0x20) + n(0x40) + addressWord(payee) + calls
    }

    /// The sender's deposit on Ethereum: itself the depositor (its refund),
    /// the handler the recipient, WETH in, the destination's WETH out.
    static func awayDeposit(to chainId: Int, sender: String, payee: String, input: String, output: String,
                            relayer: String, quoteTimestamp: Int, fillDeadline: Int, exclusivity: Int) -> String? {
        guard let origin = homeOrigins.first(where: { $0.chainId == chainId }), PrivateMoney.isAddress(sender),
              PrivateMoney.isAddress(relayer), let i = PrivateYield.uint(input), let o = PrivateYield.uint(output),
              let message = awayMessage(to: chainId, amount: output, payee: payee),
              quoteTimestamp > 0, fillDeadline > 0, exclusivity >= 0,
              (exclusivity == 0) == (relayer.lowercased() == "0x" + String(repeating: "0", count: 40)) else { return nil }
        func n(_ v: Int) -> String { PrivateYield.uint(String(v)) ?? "" }
        let words = [addressWord(sender), addressWord(awayHandler), addressWord(homeWETH), addressWord(origin.weth), i, o,
                     n(chainId), addressWord(relayer), n(quoteTimestamp), n(fillDeadline), n(exclusivity), n(12 * 32),
                     n(message.count / 2)]
        guard words.allSatisfy({ $0.count == 64 }) else { return nil }
        return homeSelector + words.joined() + message
    }

    /// Whether `from` may send this on Ethereum: exactly an away deposit as
    /// `awayDeposit` writes it, for some recipient, its value the amount
    /// deposited, what arrives no more than what leaves.
    static func awayAllowed(to: String, data: String, value: String, chainId: Int, from: String) -> Bool {
        guard chainId == homeChain, to.lowercased() == awaySpoke, PrivateMoney.isAddress(from),
              let carried = TestnetTx.quantity(value), !carried.isEmpty else { return false }
        let d = data.lowercased()
        guard d.hasPrefix(homeSelector), d.count > 10 + 13 * 64 else { return false }
        let words = (0..<13).map { i in String(d.dropFirst(10 + i * 64).prefix(64)) }
        func address(_ w: String) -> String? { w.hasPrefix(String(repeating: "0", count: 24)) ? "0x" + w.dropFirst(24) : nil }
        guard let dest = Int(PrivateMoney.decimal(hex: "0x" + words[6])),
              let origin = homeOrigins.first(where: { $0.chainId == dest }),
              address(words[0]) == from.lowercased(), address(words[1]) == awayHandler,
              address(words[2]) == homeWETH, address(words[3]) == origin.weth,
              PrivateMoney.decimal(hex: "0x" + words[4]) == PrivateMoney.decimal(hex: value),
              let relayer = address(words[7]),
              let quoted = Int(PrivateMoney.decimal(hex: "0x" + words[8])), let deadline = Int(PrivateMoney.decimal(hex: "0x" + words[9])),
              let exclusivity = Int(PrivateMoney.decimal(hex: "0x" + words[10])),
              words[11] == PrivateYield.uint(String(12 * 32)) else { return false }
        let message = String(d.dropFirst(10 + 13 * 64))
        // The message names its recipient as the fallback (its third word).
        guard message.count >= 3 * 64, let payee = address(String(message.dropFirst(128).prefix(64))),
              let input = Decimal(string: PrivateMoney.decimal(hex: "0x" + words[4])),
              let output = Decimal(string: PrivateMoney.decimal(hex: "0x" + words[5])), output > 0, output <= input,
              let want = awayDeposit(to: dest, sender: from, payee: payee, input: PrivateMoney.decimal(hex: "0x" + words[4]),
                                     output: PrivateMoney.decimal(hex: "0x" + words[5]), relayer: relayer,
                                     quoteTimestamp: quoted, fillDeadline: deadline, exclusivity: exclusivity) else { return false }
        return want == d
    }
}

// MARK: - Dollars home and away (prd §1880)

extension FreshTx {
    /// **DOLLARS, BOTH WAYS (prd §1880).** USDC paid on Base or USDG on
    /// Robinhood goes home in one Across deposit whose message lands it
    /// straight in the ppUSDC pool for your private account: the handler
    /// approves the router, runs the deposit this phone proved, and drains
    /// what is left to the same address on Ethereum (§1574's message, the
    /// drain to the address, never your account). A private USDC send to
    /// Base or Robinhood leaves from a fresh sender: its approval of
    /// Ethereum's SpokePool, then its deposit straight to the recipient as
    /// the network's dollar, no message.

    /// `abi.encode(Instructions)`: `(Call[] calls, address fallback)`, a
    /// call `(address target, bytes callData, uint256 value)`. Hex, no 0x.
    static func instructions(_ calls: [(target: String, data: String)], fallback: String) -> String? {
        guard PrivateMoney.isAddress(fallback), calls.allSatisfy({ PrivateMoney.isAddress($0.target) }) else { return nil }
        func n(_ v: Int) -> String { PrivateYield.uint(String(v)) ?? "" }
        let bodies: [String] = calls.map { c in
            let d = c.data.hasPrefix("0x") ? String(c.data.dropFirst(2)).lowercased() : c.data.lowercased()
            let bytes = d.count / 2
            let pad = String(repeating: "0", count: ((bytes + 31) / 32 * 32 - bytes) * 2)
            return addressWord(c.target) + n(0x60) + n(0) + n(bytes) + d + pad
        }
        var offsets: [String] = []
        var at = calls.count * 32
        for b in bodies { offsets.append(n(at)); at += b.count / 2 }
        return n(0x20) + n(0x40) + addressWord(fallback) + n(calls.count) + offsets.joined() + bodies.joined()
    }

    /// `approve(address,uint256)` as hex, no 0x.
    static func approveData(spender: String, amount: String) -> String? {
        guard PrivateMoney.isAddress(spender), let word = PrivateYield.uint(amount) else { return nil }
        return String(approve.dropFirst(2)) + addressWord(spender) + word
    }

    /// The message a dollar carries home: approve the ppUSDC router for
    /// `budget`, run `deposit` (the router's `depositExactShares`), drain
    /// Ethereum's USDC left to `drainTo`; no fallback, so a call that fails
    /// reverts the fill and the deposit is refunded where it left.
    static func bridgeMessage(router: String, deposit: String, budget: String, drainTo: String) -> String? {
        let d = deposit.lowercased().hasPrefix("0x") ? deposit.lowercased() : "0x" + deposit.lowercased()
        guard d.hasPrefix(tokenDeposit), PrivateMoney.isAddress(drainTo),
              let approval = approveData(spender: router, amount: budget) else { return nil }
        let drain = selector("drainLeftoverTokens(address,address)") + addressWord(homeUSDC) + addressWord(drainTo)
        return instructions([(homeUSDC, approval), (router, d), (awayHandler, drain)],
                            fallback: "0x" + String(repeating: "0", count: 40))
    }

    /// Ethereum's ppUSDC router: the only router a dollar's message runs.
    static var homeRouter: String? {
        PrivacyNetwork.ethereum.yield.first { !$0.native }?.router.lowercased()
    }

    /// The home deposit of a dollar: the address the depositor (its
    /// refund), the handler the recipient, its dollar in, Ethereum's USDC out.
    static func homeDollarDeposit(_ origin: HomeOrigin, address: String, input: String, output: String, routerDeposit: String,
                                  relayer: String, quoteTimestamp: Int, fillDeadline: Int, exclusivity: Int) -> String? {
        guard let router = homeRouter,
              let message = bridgeMessage(router: router, deposit: routerDeposit, budget: output, drainTo: address) else { return nil }
        return across(depositor: address, recipient: awayHandler, input: origin.dollar, output: homeUSDC, inAmount: input,
                      outAmount: output, to: homeChain, relayer: relayer, quoteTimestamp: quoteTimestamp,
                      fillDeadline: fillDeadline, exclusivity: exclusivity, message: message)
    }

    /// A fresh sender's dollar to `payee` on Base or Robinhood, no message.
    static func awayDollarDeposit(to chainId: Int, sender: String, payee: String, input: String, output: String,
                                  relayer: String, quoteTimestamp: Int, fillDeadline: Int, exclusivity: Int) -> String? {
        guard let origin = homeOrigins.first(where: { $0.chainId == chainId }), PrivateMoney.isAddress(payee) else { return nil }
        return across(depositor: sender, recipient: payee, input: homeUSDC, output: origin.dollar, inAmount: input,
                      outAmount: output, to: chainId, relayer: relayer, quoteTimestamp: quoteTimestamp,
                      fillDeadline: fillDeadline, exclusivity: exclusivity, message: "")
    }

    /// Across's `deposit` with any message (hex, no 0x).
    private static func across(depositor: String, recipient: String, input: String, output: String, inAmount: String,
                               outAmount: String, to chainId: Int, relayer: String, quoteTimestamp: Int, fillDeadline: Int,
                               exclusivity: Int, message: String) -> String? {
        guard PrivateMoney.isAddress(depositor), PrivateMoney.isAddress(recipient), PrivateMoney.isAddress(relayer),
              let i = PrivateYield.uint(inAmount), let o = PrivateYield.uint(outAmount),
              let a = Decimal(string: inAmount), let b = Decimal(string: outAmount), b > 0, b <= a,
              quoteTimestamp > 0, fillDeadline > 0, exclusivity >= 0, message.count % 64 == 0,
              (exclusivity == 0) == (relayer.lowercased() == "0x" + String(repeating: "0", count: 40)) else { return nil }
        func n(_ v: Int) -> String { PrivateYield.uint(String(v)) ?? "" }
        let words = [addressWord(depositor), addressWord(recipient), addressWord(input), addressWord(output), i, o,
                     n(chainId), addressWord(relayer), n(quoteTimestamp), n(fillDeadline), n(exclusivity), n(12 * 32),
                     n(message.count / 2)]
        guard words.allSatisfy({ $0.count == 64 }) else { return nil }
        return homeSelector + words.joined() + message.lowercased()
    }

    /// A deposit's 13 head words and its message, or nil.
    private static func acrossParts(_ data: String) -> (words: [String], message: String)? {
        let d = data.lowercased()
        guard d.hasPrefix(homeSelector), d.count >= 10 + 13 * 64, (d.count - 10) % 64 == 0 else { return nil }
        let words = (0..<13).map { i in String(d.dropFirst(10 + i * 64).prefix(64)) }
        guard words[11] == PrivateYield.uint(String(12 * 32)),
              let length = Int(PrivateMoney.decimal(hex: "0x" + words[12])), d.count == 10 + 13 * 64 + length * 2 else { return nil }
        return (words, String(d.dropFirst(10 + 13 * 64)))
    }

    private static func wordAddress(_ w: String) -> String? {
        w.hasPrefix(String(repeating: "0", count: 24)) ? "0x" + w.dropFirst(24) : nil
    }

    private static func wordInt(_ w: String) -> Int? { Int(PrivateMoney.decimal(hex: "0x" + w)) }

    /// What a dollar's approval on `chainId` may be: the network's dollar
    /// (Ethereum's USDC there) approving that network's SpokePool.
    static func dollarApprovalAllowed(to: String, data: String, value: String, chainId: Int) -> Bool {
        let token: String, spoke: String
        if chainId == homeChain { (token, spoke) = (homeUSDC, awaySpoke) }
        else if let origin = homeOrigins.first(where: { $0.chainId == chainId }) {
            // The dollar, or WETH a refund left there (prd §1882).
            (token, spoke) = (to.lowercased() == origin.weth ? origin.weth : origin.dollar, origin.spoke)
        }
        else { return false }
        guard to.lowercased() == token, let carried = TestnetTx.quantity(value), carried.isEmpty else { return false }
        let d = data.lowercased()
        return d.hasPrefix(approve) && d.count == 2 + 8 + 128 && wordAddress(String(d.dropFirst(10).prefix(64))) == spoke
    }

    /// Whether `from` may send this home deposit of a dollar on `chainId`:
    /// read back word by word, its message rebuilt from the router call it
    /// carries and compared whole.
    static func homeDollarAllowed(to: String, data: String, value: String, chainId: Int, from: String) -> Bool {
        guard let origin = homeOrigins.first(where: { $0.chainId == chainId }), to.lowercased() == origin.spoke,
              PrivateMoney.isAddress(from), let carried = TestnetTx.quantity(value), carried.isEmpty,
              let (w, message) = acrossParts(data), let relayer = wordAddress(w[7]),
              let q = wordInt(w[8]), let f = wordInt(w[9]), let x = wordInt(w[10]) else { return false }
        // The router call is the message's second call: found by its offset
        // (array data starts at byte 128), its length, then its bytes.
        func word(_ i: Int) -> String? { message.count >= (i + 1) * 64 ? String(message.dropFirst(i * 64).prefix(64)) : nil }
        guard let offset = word(5).flatMap(wordInt), offset % 32 == 0 else { return false }
        let first = (128 + offset) / 32
        guard let length = word(first + 3).flatMap(wordInt), message.count >= (first + 4) * 64 + length * 2 else { return false }
        let routerData = String(message.dropFirst((first + 4) * 64).prefix(length * 2))
        guard let want = homeDollarDeposit(origin, address: from.lowercased(), input: PrivateMoney.decimal(hex: "0x" + w[4]),
                                           output: PrivateMoney.decimal(hex: "0x" + w[5]), routerDeposit: routerData,
                                           relayer: relayer, quoteTimestamp: q, fillDeadline: f, exclusivity: x) else { return false }
        return want == data.lowercased()
    }

    /// Whether a fresh sender may send this dollar deposit on Ethereum: to
    /// Base or Robinhood, the network's dollar, any recipient, no message.
    static func awayDollarAllowed(to: String, data: String, value: String, chainId: Int, from: String) -> Bool {
        guard chainId == homeChain, to.lowercased() == awaySpoke, PrivateMoney.isAddress(from),
              let carried = TestnetTx.quantity(value), carried.isEmpty,
              let (w, message) = acrossParts(data), message.isEmpty,
              let dest = wordInt(w[6]), let payee = wordAddress(w[1]), let relayer = wordAddress(w[7]),
              let q = wordInt(w[8]), let f = wordInt(w[9]), let x = wordInt(w[10]),
              let want = awayDollarDeposit(to: dest, sender: from.lowercased(), payee: payee,
                                           input: PrivateMoney.decimal(hex: "0x" + w[4]), output: PrivateMoney.decimal(hex: "0x" + w[5]),
                                           relayer: relayer, quoteTimestamp: q, fillDeadline: f, exclusivity: x) else { return false }
        return want == data.lowercased()
    }
}

// MARK: - Refunds (prd §1882)

extension FreshTx {
    /// `transfer(address,uint256)`, hex with 0x.
    static func transferData(to: String, amount: String) -> String? {
        guard PrivateMoney.isAddress(to), let word = PrivateYield.uint(amount) else { return nil }
        return "0xa9059cbb" + addressWord(to) + word
    }

    /// **WHAT ACROSS GAVE BACK GOES TO YOUR OWN RECEIVE ADDRESS (prd §1882).**
    /// A fresh sender on Ethereum whose deposit Across refunded holds WETH or
    /// USDC; it may send exactly that token, all or part, to `recipient`,
    /// which the signer derives itself as one of your receive addresses, and
    /// nothing else.
    static func refundAllowed(to: String, data: String, value: String, chainId: Int, recipient: String) -> Bool {
        guard chainId == homeChain, [homeWETH, homeUSDC].contains(to.lowercased()), PrivateMoney.isAddress(recipient),
              let carried = TestnetTx.quantity(value), carried.isEmpty else { return false }
        let d = data.lowercased()
        guard d.hasPrefix("0xa9059cbb"), d.count == 2 + 8 + 128, wordAddress(String(d.dropFirst(10).prefix(64))) == recipient.lowercased(),
              let amount = Decimal(string: PrivateMoney.decimal(hex: "0x" + String(d.dropFirst(74)))), amount > 0 else { return false }
        return true
    }
}

extension FreshTx.Tx {
    /// A dollar's move: its approval of a SpokePool, a home deposit on Base
    /// or Robinhood, or a fresh sender's deposit on Ethereum (prd §1880);
    /// nil for anything else.
    init?(dollar chainId: Int, from: String, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
          gas: String, to: String, value: String, data: String) {
        guard FreshTx.dollarApprovalAllowed(to: to, data: data, value: value, chainId: chainId)
            || FreshTx.homeDollarAllowed(to: to, data: data, value: value, chainId: chainId, from: from)
            || FreshTx.awayDollarAllowed(to: to, data: data, value: value, chainId: chainId, from: from) else { return nil }
        for q in [nonce, maxPriorityFeePerGas, maxFeePerGas, gas, value] where TestnetTx.quantity(q) == nil { return nil }
        guard let address = TestnetTx.bytes(to), address.count == 20, TestnetTx.bytes(data) != nil else { return nil }
        self.init(chainId: chainId, nonce: nonce, maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas,
                  gas: gas, to: to, value: value, data: data)
    }

    /// A refund sent on to your own receive address, nil unless `refundAllowed`.
    init?(refund recipient: String, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
          gas: String, to: String, data: String) {
        guard FreshTx.refundAllowed(to: to, data: data, value: "0x0", chainId: FreshTx.homeChain, recipient: recipient) else { return nil }
        for q in [nonce, maxPriorityFeePerGas, maxFeePerGas, gas] where TestnetTx.quantity(q) == nil { return nil }
        guard let address = TestnetTx.bytes(to), address.count == 20, TestnetTx.bytes(data) != nil else { return nil }
        self.init(chainId: FreshTx.homeChain, nonce: nonce, maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas,
                  gas: gas, to: to, value: "0x0", data: data)
    }

    /// An away deposit on Ethereum, nil unless `awayAllowed`.
    init?(away from: String, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
          gas: String, to: String, value: String, data: String) {
        guard FreshTx.awayAllowed(to: to, data: data, value: value, chainId: FreshTx.homeChain, from: from) else { return nil }
        for q in [nonce, maxPriorityFeePerGas, maxFeePerGas, gas, value] where TestnetTx.quantity(q) == nil { return nil }
        guard let address = TestnetTx.bytes(to), address.count == 20, TestnetTx.bytes(data) != nil else { return nil }
        self.init(chainId: FreshTx.homeChain, nonce: nonce, maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas,
                  gas: gas, to: to, value: value, data: data)
    }

    /// A home deposit on Base or Robinhood, nil unless `homeAllowed`.
    init?(home chainId: Int, from: String, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
          gas: String, to: String, value: String, data: String) {
        guard FreshTx.homeAllowed(to: to, data: data, value: value, chainId: chainId, from: from) else { return nil }
        for q in [nonce, maxPriorityFeePerGas, maxFeePerGas, gas, value] where TestnetTx.quantity(q) == nil { return nil }
        guard let address = TestnetTx.bytes(to), address.count == 20, TestnetTx.bytes(data) != nil else { return nil }
        self.init(chainId: chainId, nonce: nonce, maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas,
                  gas: gas, to: to, value: value, data: data)
    }
}
