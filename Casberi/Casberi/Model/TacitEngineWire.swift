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
        case info, open, read, close
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
