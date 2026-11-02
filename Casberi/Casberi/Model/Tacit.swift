import Foundation

/// Tacit's contracts, named in the Wallet (2026-10-12, prd §1281). A label,
/// not a seat, as zk.money is (§1273): Tacit's moves are a watched wallet's
/// own transfers, so they land as Wallet rows and the Wallet NAMES them —
/// "Deposited 0.88 ETH into Tacit", "Withdrew 0.45 ETH from Tacit".
///
/// Tacit (github.com/z0r0z/tacit) keeps two shielded pools. Inside them,
/// amounts and owners are hidden; what enters and leaves is public, amount
/// included, by design. MEASURED 2026-10-12 on Ethereum:
/// • the ETH pool (`TacitEvmPool`, one address on Ethereum, Base, Robinhood
///   Chain and MegaETH): a deposit is the person calling `transact` with
///   ETH; a withdrawal is the pool paying ETH out, relayed by Tacit's keeper,
///   which takes a small fee in the same transaction;
/// • the confidential pool (`ConfidentialPool`, Ethereum only): ETH goes in
///   through `WrapTipForwarder`, tokens through the zap or
///   `WrapTokenTipForwarder`; the pool pays out ETH and tokens (wTAC farm
///   rewards among them) to whoever unwraps.
/// Every address is the deployment Tacit's own repository lists
/// (`docs/DEPLOYMENTS.md`, `contracts/deployments/evm-pool.json`), with its
/// code read on each chain named.
enum Tacit {
    static let name = "Tacit"

    static let evmPool = "0x000000c2a20657ce25f2ba99737933d031afbee9"
    static let confidentialPool = "0x000000000ed1eabd231be41d93b719056f7febfc"

    /// Value out of a pool is a withdrawal; ETH or a token in, a deposit.
    static let pools: Set<String> = [evmPool, confidentialPool]

    /// Doors into a pool: what a wallet sends them is a deposit.
    static let entrances: Set<String> = [
        "0x0000008ebbf2323f95c4fbc18254f3d65c53998c", // TacitEvmPoolZap (Ethereum, Base, Robinhood)
        "0x000000d218b03db5837943b0b05dea2965ae956e", // WrapTipForwarder
        "0x0000007b1d93d72f698a861aa86ac675d6af7216", // WrapTokenTipForwarder
    ]

    /// Tacit's other contracts a transfer can meet: named, no verb.
    static let named: Set<String> = [
        "0x0000006c96afa6f1cd4df8fe19bc0d8b6a6cd7b5", // TacitEvmPoolRouter
        "0x000000005da3e3b73726af3c774deeb9472d4992", // ConfidentialRouter
        "0x00000000e36c7ec997cc59dcda9e03673b448119", // TacitPublicAmm
        "0x000000009c28617ac88b52eae5efaacdd4ac34c3", // TacitRelayer
        "0x000000003f608bddf0ca45934003ffb9dbdf70db", // CollateralEngine
        "0x000031c47cb61fab1ce2790a69625fabb71ede24", // FarmManager
        "0x000000c918e44a3a443937fa7594ea4f7c95d6b9", // PointsDistributor
        "0x4b4cb98d0c836c2783ac46f0078b904dab533ae8", // TacAirdrop
    ]

    static func knownName(for address: String) -> String? {
        let a = address.lowercased()
        return pools.contains(a) || entrances.contains(a) || named.contains(a) ? name : nil
    }

    enum Verb: Equatable { case deposited, withdrew }

    /// What a transfer with `counterparty` did, or nil when its shape says
    /// nothing certain: a receipt from an entrance is a refund, and anything
    /// to or from the routers is part of a larger call.
    static func verb(counterparty: String, received: Bool) -> Verb? {
        let a = counterparty.lowercased()
        if pools.contains(a) { return received ? .withdrew : .deposited }
        if entrances.contains(a), !received { return .deposited }
        return nil
    }

    static func title(_ verb: Verb, amount: String, asset: String) -> String {
        switch verb {
        case .deposited: return "Deposited \(amount) \(asset) into \(name)"
        case .withdrew:  return "Withdrew \(amount) \(asset) from \(name)"
        }
    }

    static var note: String {
        String(localized: "Money entering and leaving Tacit is public; inside its pools, amounts and owners are private.")
    }

    // MARK: - Withdrawals off the pool's own event (prd §1676)

    /// The ETH pool pays a withdrawal in an internal call, and a chain whose
    /// transfer read refuses `internal` (Robinhood: `WalletIngest.Chain
    /// .internalTransfers`) never saw one unless Zerion listed it. Every `transact` emits
    /// `Transact(bytes32 indexed nf0, bytes32 indexed nf1, bytes32 outLeaf0,
    /// bytes32 outLeaf1, uint256 firstIndex, bytes32 newRoot, address
    /// recipient, int256 extAmount, address relayer, uint256 fee, bytes memo0,
    /// bytes memo1)`, and `extAmount < 0` pays `-extAmount` to `recipient`
    /// (`TacitEvmPool.sol`). The recipient is not indexed, so the pool's
    /// whole log is read and filtered here. MEASURED on Robinhood 2026-11-02:
    /// 2,038 events since block 74,039,158, 1,013 of them withdrawals to 25
    /// recipients, one event per transaction.
    static let transactTopic = "0xdf0ed29e998ac2f2ff0f0516cb9c1b95af189e00d55af3764b95bdd2a835e53a"

    /// The chains whose withdrawals are read off the pool, each with the node
    /// that serves its log and the block of the pool's first event (a walk
    /// starts there, not at genesis). The chain's own node, because it is the
    /// one that answers: MEASURED 2026-11-02, Alchemy's free tier takes 10
    /// blocks per `eth_getLogs` and publicnode wants a token for history,
    /// while `rpc.mainnet.chain.robinhood.com` takes 10M blocks a call.
    struct PoolChain { let node: String; let firstBlock: Int }
    static let poolChains: [String: PoolChain] = [
        "robinhood-mainnet": PoolChain(node: "https://rpc.mainnet.chain.robinhood.com", firstBlock: 74_039_158),
    ]

    struct Withdrawal: Equatable {
        let hash: String
        let block: String       // hex, as the log spells it
        let logIndex: String
        let recipient: String   // lowercased
        let amount: Double      // ETH
    }

    /// A withdrawal, or nil for a deposit, an in-pool transfer, another
    /// contract's log or a log the chain took back.
    static func withdrawal(fromLog log: [String: Any]) -> Withdrawal? {
        guard (log["address"] as? String)?.lowercased() == evmPool,
              (log["topics"] as? [String])?.first?.lowercased() == transactTopic,
              (log["removed"] as? Bool) != true,
              let hash = log["transactionHash"] as? String,
              let block = log["blockNumber"] as? String,
              let data = log["data"] as? String
        else { return nil }
        let hex = Array((data.hasPrefix("0x") ? data.dropFirst(2) : Substring(data)).lowercased())
        guard hex.count >= 64 * 8 else { return nil }
        let recipientWord = hex[(64 * 4)..<(64 * 5)]
        guard recipientWord.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        let recipient = "0x" + String(recipientWord.suffix(40))
        guard recipient != "0x" + String(repeating: "0", count: 40),
              let wei = paidOut(Array(hex[(64 * 5)..<(64 * 6)])), wei > 0
        else { return nil }
        return Withdrawal(hash: hash.lowercased(), block: block,
                          logIndex: (log["logIndex"] as? String) ?? "0x0",
                          recipient: recipient, amount: wei / 1e18)
    }

    /// `-extAmount` in wei when `extAmount` (an int256 word, 64 hex digits)
    /// is negative, else nil: the two's complement is inverted and one added,
    /// digit by digit, so an amount past 2^64 wei (18.4 ETH) reads whole.
    static func paidOut(_ word: [Character]) -> Double? {
        guard word.count == 64, let top = word.first?.hexDigitValue, top >= 8 else { return nil }
        var digits = word.compactMap { $0.hexDigitValue.map { 15 - $0 } }
        guard digits.count == 64 else { return nil }
        var i = 63
        while i >= 0 {
            if digits[i] < 15 { digits[i] += 1; break }
            digits[i] = 0
            i -= 1
        }
        return digits.reduce(0.0) { $0 * 16 + Double($1) }
    }

    /// The withdrawal as the transfer read's own shape (`alchemy_getAssetTransfers`),
    /// so it lands through the same pipeline: "Withdrew … ETH from Tacit".
    static func transfer(_ w: Withdrawal) -> [String: Any] {
        [
            "hash": w.hash,
            "asset": "ETH",
            "value": w.amount,
            "category": "internal",
            "from": evmPool,
            "to": w.recipient,
            "blockNum": w.block,
            "uniqueId": "tacit:\(w.hash):\(w.logIndex)",
        ]
    }
}
