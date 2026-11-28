import Foundation

/// WHAT CROSSES BETWEEN THE APP AND THE TACIT ENGINE.
///
/// The engine is Tacit's own standalone private-ETH wallet in a hidden web
/// view (`TacitEngine`), opened view-only. Swift calls one function,
/// `casberiEngine.call(method, paramsJSON)`, and gets the same envelope the
/// Privacy Pools engine answers with (`PrivacyEngineWire.decode`). Big numbers
/// travel as 0x-hex strings. The key goes in once, at `open`; nothing that
/// comes back is a secret.
///
/// Pure (Foundation only).
enum TacitEngineWire {

    enum Method: String, CaseIterable {
        case info, open, read, chain, defi, close
        case farms, farmed
        case farmClaim, farmRelease, farmTakeOut
        case shieldQuote, shieldProve, shieldHand, shieldOffer, shieldStatus
        case outQuote, outProve, outHand, owed
        case payQuote, payProve, payCheck
    }

    typealias Failure = PrivacyEngineWire.Failure

    struct Empty: Codable, Equatable {}

    // MARK: - Requests

    struct Open: Encodable {
        /// 32 bytes, 0x-hex: the Tacit identity key (`TacitPocket.key`).
        let key: String
        let networks: [TacitNetwork]
    }

    struct Read: Encodable {
        let chainId: Int
    }

    struct Chain: Encodable {
        let rpcUrl: String
        let blocks: String
        let leader: String
        /// Where the last scan stopped, and the notes it found: the scan
        /// tries only what came after, and asks again whether these are spent.
        var from: Int = 0
        var known: [KeptNote] = []
    }

    /// One note of yours on the Tacit chain, as a scan found it: its place in
    /// the chain's list, its shares, its secret and its leaf, 0x-hex. Kept on
    /// this phone only (`TacitChainScan`), never sent but back to the engine.
    struct KeptNote: Codable, Equatable {
        let index: Int
        let value: String
        let s: String
        let leaf: String
    }

    // MARK: - Answers

    struct Info: Decodable, Equatable {
        let pool: String
        let router: String
        let chains: [Int]
    }

    struct OpenedNetwork: Decodable, Equatable {
        let chainId: Int
        /// The Tacit address others pay privately: the same on every network.
        let address: String
        /// The plain address anyone can pay; what lands is swept into the pool.
        let receive: String
        let ms: Int
    }

    struct Opened: Decodable, Equatable {
        let address: String?
        let networks: [OpenedNetwork]
    }

    struct Reading: Decodable, Equatable {
        let chainId: Int
        /// Wei, 0x-hex: what your notes on this network add up to.
        let balance: String
        /// Wei, 0x-hex: paid to your receive address and not yet in the pool.
        let waiting: String
        /// Wei, 0x-hex: what the whole pool holds on this network; nil when
        /// the node did not say.
        let pool: String?
        let notes: Int
        /// How much of the pool was read: its entries, and the block read to.
        let leaves: Int
        let block: Int
        let behind: Int
        let ms: Int
    }

    /// Your private TAC on the Tacit chain: notes that are SHARES of one pool.
    struct ChainReading: Decodable, Equatable {
        /// 0x-hex, 8 decimals: your unspent notes' shares, added up.
        let shares: String
        /// 0x-hex, 8 decimals: what those shares are worth in TAC at the
        /// pool's rate, read from the chain's contract.
        let worth: String
        let notes: Int
        let spent: Int
        /// How many of the chain's notes were tried.
        let leaves: Int
        /// 0x-hex, 8 decimals: the pool's TAC and its shares; their ratio is
        /// what one share is worth, and it only rises.
        let pool: String
        let allShares: String
        /// The key's record names another chain address: a PQ ID, whose notes
        /// are under a passkey's root this phone does not hold.
        let elsewhere: Bool
        let ms: Int
        /// The next entry a scan should try, and your unspent notes.
        let next: Int
        let kept: [KeptNote]
        /// Your Tacit chain address (`tc1…`): what a sender of private TAC pays.
        let chainAddress: String
    }

    // MARK: - Making TAC private

    struct ShieldAsk: Encodable {
        let rpcUrl: String
        let blocks: String
        let leader: String
        /// TAC, 8 decimals, 0x-hex.
        let units: String
    }

    /// Back to public (prd §1977): `to` an Ethereum address, `units` TAC
    /// at 8 decimals, 0x-hex; a quote reads with `to` empty.
    struct OutAsk: Encodable {
        let rpcUrl: String
        let blocks: String
        let leader: String
        let to: String
        let units: String
    }

    struct OutQuote: Decodable, Equatable {
        /// The chain's fee, 8 decimals.
        let fee: String
        /// What the pool's holders keep of it, 8 decimals.
        let holders: String
        /// The most that can go back now, 8 decimals.
        let most: String
    }

    struct OutProved: Decodable, Equatable {
        let proveMs: Int
    }

    struct OwedAsk: Encodable {
        let rpcUrl: String
        let blocks: String
        let leader: String
        let address: String
    }

    struct Owed: Decodable, Equatable {
        /// TAC wei (18 decimals), 0x-hex.
        let wei: String
    }

    struct ShieldQuote: Decodable, Equatable {
        /// The chain's fee, in its 8-decimal units, taken from the shares.
        let fee: String
        /// What lands, in TAC (8 decimals).
        let arrives: String
        /// The most one deposit may be, in TAC (8 decimals); nil for none.
        let cap: String?
        /// The leader's fee for sweeping the permit, in TAC wei (18 decimals).
        let sweepFee: String
    }

    struct Deposit: Codable, Equatable {
        let shares: String
        let amount: String
        let cx: String
        let cy: String
        let body: String
    }

    struct ShieldProved: Decodable, Equatable {
        /// What the permit lets take the TAC: the deposit's inbox.
        let inbox: String
        /// The return path: a deposit the chain does not take goes back to
        /// Tacit's DeFi pool under your key, at this commitment.
        let back: String
        let index: Int
        /// The permit's deadline, seconds since 1970.
        let deadline: Int
        /// The permit's value, TAC wei: the amount and the leader's fee.
        let value: String
        let sweepFee: String
        let fee: String
        let shares: String
        let units: String
        let proveMs: Int
        let deposit: Deposit
    }

    struct ShieldHand: Encodable {
        let owner: String
        let v: Int
        let r: String
        let s: String
    }

    struct ShieldHanded: Decodable, Equatable {
        let id: String
        /// The handed deposit as the chain client keeps it, to hand again.
        let kept: String
    }

    struct ShieldStatusAsk: Encodable {
        let leader: String
        let id: String
    }

    struct ShieldStatus: Decodable, Equatable {
        let ok: Bool
        let http: Int
        let status: String?
        let error: String?
        let height: Int?
    }

    /// Your private TAC in Tacit's DeFi pool, its private pool on Ethereum.
    struct DefiReading: Decodable, Equatable {
        /// 0x-hex, 8 decimals: your unspent cTAC.
        let worth: String
        let notes: Int
        let leaves: Int
        /// False when the library stopped before reading every note.
        let whole: Bool
        let errors: [String]
        let passes: Int
        let ms: Int
        /// Everything the pool holds for you, by asset (prd §2006): what a
        /// farm you left paid back. Nil from a page built before it.
        let held: [Held]?
    }

    /// One asset Tacit's DeFi pool holds for you: its ticker, 0x-hex value in
    /// the pool's own units, and how many decimals those units carry.
    struct Held: Decodable, Equatable {
        let ticker: String
        let value: String
        let decimals: Int

        /// The amount in whole coins; nil for a value that is not 0x-hex.
        var amount: Double? {
            TacitEngineWire.number(value).map { $0 / pow(10, Double(decimals)) }
        }
    }

    /// The farm a leave step acts on, by its pool's LP-share asset id.
    struct FarmAsk: Encodable {
        let lpAsset: String
    }

    /// A farm's claim (prd §2006): wTAC earned, 0x-hex value units, and
    /// whether there was a position at all.
    struct FarmClaimed: Decodable, Equatable {
        let claimed: String
        let position: Bool
        let tx: String?
    }

    /// A farm's shares released back as an LP-share note.
    struct FarmReleased: Decodable, Equatable {
        let shares: String
        let position: Bool
        let tx: String?
    }

    /// What taking a pool's shares out paid back, coin by coin; `found`
    /// false when no share of that pool was there to take out.
    struct FarmTakenOut: Decodable, Equatable {
        let out: [Held]
        let found: Bool
    }

    /// Tacit's farms as its farm program reads them (prd §1993). Every
    /// figure is 0x-hex: TAC per year and reserves in value units (8
    /// decimals), shares as the pool counts them.
    struct Farms: Decodable, Equatable {
        struct Pool: Decodable, Equatable {
            let pair: String
            let lpAsset: String
            let perYear: String
            let staked: String
            let shares: String
            /// The pool's two assets by ticker; empty when Tacit names none.
            let a: String
            let b: String
            let reserveA: String
            let reserveB: String
        }
        let active: Bool
        /// Seconds until this round of rewards ends.
        let remaining: Int
        let pools: [Pool]
        let ms: Int
    }

    /// Your farm positions: LP shares bonded, and TAC earned, unclaimed.
    struct Farmed: Decodable, Equatable {
        struct Position: Decodable, Equatable {
            let pair: String
            let lpAsset: String
            let shares: String
            /// 0x-hex value units (8 decimals) of TAC.
            let pending: String
        }
        let positions: [Position]
        let ms: Int
    }

    /// A 0x-hex whole number as a Double; nil for anything else.
    static func number(_ hex: String) -> Double? {
        guard hex.hasPrefix("0x"), hex.count > 2, hex.count <= 66 else { return nil }
        var n = 0.0
        for character in hex.dropFirst(2) {
            guard let digit = character.hexDigitValue else { return nil }
            n = n * 16 + Double(digit)
        }
        return n
    }

    /// 0x-hex chain units (8 decimals) as TAC; nil for anything else.
    static func tac(_ hex: String) -> Decimal? {
        eth(hex).map { $0 * pow(Decimal(10), 10) }
    }

    /// 0x-hex wei as a decimal amount of ETH; nil for anything else.
    static func eth(_ hex: String) -> Decimal? {
        guard hex.hasPrefix("0x"), hex.count > 2, hex.count <= 66 else { return nil }
        var wei = Decimal(0)
        for character in hex.dropFirst(2) {
            guard let digit = character.hexDigitValue else { return nil }
            wei = wei * 16 + Decimal(digit)
        }
        return wei / pow(Decimal(10), 18)
    }
}

/// One network Tacit's private-ETH pool stands on, and where the engine reads
/// it: the network's own node, and Tacit's history feed for that network. The
/// wallet keeps a page of the feed only if the tree it builds is one the pool
/// itself has held, so the feed is checked against the chain, never trusted.
///
/// Ethereum and Robinhood. Base is left out on purpose: its pool holds
/// 274,000 entries, and a first read of them took 190 s and 120 MB on a Mac
/// (measured 2026-11-20); these two take about 2 s and under 1 MB.
/// The Tacit chain, where private TAC is held: its contract on Ethereum and
/// Tacit's server for its notes (`TACIT_CHAIN` in Tacit's own
/// `dapp/tacit-chain-config.js`, read 2026-11-24).
enum TacitChain {
    static let blocks = "0x00000000000a9147ffd8d41d152d730ca5f84e6c"
    static let leader = "https://tacit-chain-leader.onrender.com"
}

struct TacitNetwork: Codable, Equatable, Identifiable {
    let chainId: Int
    let name: String
    let rpcUrl: String
    let relayUrl: String

    var id: Int { chainId }

    static let ethereum = TacitNetwork(chainId: 1, name: "Ethereum",
                                       rpcUrl: "https://rpc.mevblocker.io",
                                       relayUrl: "https://tacit-evm-pool-keeper.onrender.com/evm-pool/keeper")
    static let robinhood = TacitNetwork(chainId: 4663, name: "Robinhood",
                                        rpcUrl: "https://rpc.mainnet.chain.robinhood.com",
                                        relayUrl: "https://tacit-evm-pool-keeper-robinhood.onrender.com/evm-pool/keeper")

    static let all: [TacitNetwork] = [.ethereum, .robinhood]
}
