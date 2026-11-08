import Foundation

/// WHAT CROSSES BETWEEN THE APP AND THE RAILGUN ENGINE (prd §1713).
///
/// The engine is Railgun's open wallet SDK in a hidden web view
/// (`RailgunEngine`). Swift calls one function, `casberiRailgun.call(method,
/// paramsJSON)`, and always gets one JSON envelope back:
/// `{"ok":true,"value":…}` or `{"ok":false,"error":{"name":…,"message":…}}`.
/// Big numbers travel as 0x-hex strings. What comes back is public — a
/// transaction to send, an amount, a root's verdict, a timing — while the
/// wallet's keys, its notes and every proof stay inside the page.
///
/// Pure (Foundation only), so a harness can compile it against stubs; the
/// host check is `PrivacyEngineWire.allows`, the one rule for both engines.
enum RailgunEngineWire {

    enum Method: String, CaseIterable {
        case info, open, sync, balances, prepareShield, prepareUnshield, close
    }

    struct Failure: Error, Equatable, Decodable {
        let name: String
        let message: String
    }

    struct Empty: Codable, Equatable {}

    private struct Envelope<Value: Decodable>: Decodable {
        let ok: Bool
        let value: Value?
        let error: Failure?
    }

    /// Decodes an envelope into `Value`, or throws the engine's `Failure`.
    /// A reply that is not an envelope is a failure too, never a value.
    static func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: data) else {
            throw Failure(name: "BadReply", message: String(json.prefix(200)))
        }
        if envelope.ok, let value = envelope.value { return value }
        throw envelope.error ?? Failure(name: "BadReply", message: "ok without a value")
    }

    static func encode<Params: Encodable>(_ params: Params) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(params), as: UTF8.self)
    }

    /// Ethereum's placeholder for the native coin, as the Wallet spells it.
    static let eth = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    // MARK: - Requests

    /// Opens the 0zk wallet. Without a mnemonic the page makes a random one
    /// and keeps nothing (a probe); with one, the Keychain's (prd §1713 item 3).
    struct Open: Encodable {
        var mnemonic: String? = nil
        /// 0x-hex, 32 bytes: the phrase's entropy, from your private root.
        var entropy: String? = nil
        /// 32 bytes, hex without 0x: the SDK's wallet encryption key.
        var encryptionKey: String? = nil
        /// A wallet the store already keeps, opened by its id.
        var walletID: String? = nil
        /// The account's own node (§1713 item 9).
        let rpcUrl: String
        var creationBlock: Int? = nil
        /// Trees kept on disk (IndexedDB in the engine's own store), or in
        /// memory only.
        var persist = true
    }

    struct Sync: Encodable, Equatable {
        let capMs: Int
    }

    struct Shield: Encodable, Equatable {
        let token: String
        /// 0x-hex base units.
        let amount: String
    }

    struct Unshield: Encodable, Equatable {
        let token: String
        let amount: String
        let to: String
        /// True: refuse anything but a plain call to Railgun's proxy, which
        /// is what a Safe can send. False: a plain wallet's, which for ETH is
        /// an EIP-7702 transaction.
        var forSafe = true
        var maxFeePerGas: String? = nil
        var maxPriorityFeePerGas: String? = nil
    }

    // MARK: - Replies

    struct Info: Decodable, Equatable {
        let sdk: String
        let engine: String
        let snarkjs: String
        let secureContext: Bool
        let webAssembly: Bool
        let workers: Bool
        let cores: Int
    }

    struct Opened: Decodable, Equatable {
        /// The 0zk address. Casberi never shows it (§1713 item 4).
        let address: String
        let walletID: String
        /// Opened from the store, not made now.
        let loaded: Bool
        let generated: Bool
        /// `indexeddb` or `memory`.
        let storage: String?
        /// Tree 4's leaves already kept when the wallet opened: 0 on a first
        /// launch.
        let keptLeaves: Int
        let headBlock: Int
        let shieldFeeBps: String?
        let unshieldFeeBps: String?
        let ms: Int
    }

    struct TreeState: Decodable, Equatable {
        let status: String
        let progress: Int
    }

    struct TreeRoot: Decodable, Equatable {
        let tree: Int
        let length: Int
        let onChain: Bool
    }

    /// One token the wallet holds: the whole balance, and what the screening
    /// node has listed (spendable now). Hex base units.
    struct Balance: Decodable, Equatable {
        let token: String
        let amount: String
        let spendable: String
    }

    struct Synced: Decodable, Equatable {
        let done: Bool
        let utxo: TreeState?
        let txid: TreeState?
        let trees: [TreeRoot]
        let utxoRootsValid: Bool
        let txidIndex: Int
        let screeningIndex: Int?
        let txidRootValid: Bool
        let balances: [Balance]
        let syncMs: Int
        let ms: Int
    }

    struct Balances: Decodable, Equatable {
        let balances: [Balance]
    }

    struct Tx: Codable, Equatable {
        let to: String
        let data: String
        let value: String
    }

    /// A shield, for your account to send: the proxy call, and the approval
    /// it needs first (none for ETH). `fee` is Railgun's, read live.
    struct PreparedShield: Decodable, Equatable {
        let tx: Tx
        let approve: Tx?
        let token: String
        let amount: String
        let fee: String?
        let ms: Int
    }

    /// An unshield, proved: the proxy call for your account to send. `type`
    /// 4 with a `delegate` is the plain wallet's EIP-7702 form; `forSafe`
    /// never returns one.
    struct PreparedUnshield: Decodable, Equatable {
        let tx: Tx
        let type: Int
        let delegate: String?
        let gasEstimate: String
        let token: String
        let amount: String
        let to: String
        let fee: String?
        let proofMs: Int
        let ms: Int
    }

    // MARK: - Rules

    /// A sync the app may spend from: both trees complete, every UTXO root
    /// in the proxy's history, the TXID root the screening node's at our
    /// index, and our index no further than the node's own.
    static func trusted(_ s: Synced) -> Bool {
        guard s.done, s.utxoRootsValid, s.txidRootValid else { return false }
        if let node = s.screeningIndex { return s.txidIndex <= node }
        return true
    }

    /// Whether the engine may reach `url`: the one rule both engines share.
    static func allows(_ url: URL, declared: [String]) -> Bool {
        PrivacyEngineWire.allows(url, declared: declared)
    }
}
