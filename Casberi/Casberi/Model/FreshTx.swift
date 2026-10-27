import Foundation

/// **A FRESH ADDRESS'S OWN TRANSACTION ON ETHEREUM (prd §1565).**
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
/// - a token's `approve` of exactly that token's own router, carrying no ETH.
///
/// Nothing else can be built here, so no fresh key can be made to pay
/// anyone, call anything, or sign on another chain. The bytes are EIP-1559
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
            self.chainId = network.chainId; self.nonce = nonce; self.maxPriorityFeePerGas = maxPriorityFeePerGas
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
}
