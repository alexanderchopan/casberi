import Foundation

/// WHAT CROSSES BETWEEN THE APP AND THE PRIVACY POOLS ENGINE (prd §1540).
///
/// The engine is 0xBow's open TypeScript SDK in a hidden web view
/// (`PrivacyEngine`). Swift calls one function, `casberiEngine.call(method,
/// paramsJSON)`, and always gets one JSON envelope back:
/// `{"ok":true,"value":…}` or `{"ok":false,"error":{"name":…,"message":…}}`.
/// Big numbers travel as 0x-hex strings. What comes back is public — a
/// transaction to sign, a commitment, an amount, a timing — while the keys,
/// note secrets and proofs stay inside the page (`handle` names one).
///
/// Pure (Foundation only): `privacy-engine-selftest.sh` compiles it.
enum PrivacyEngineWire {

    enum Method: String, CaseIterable {
        case info, open, close, isRegistered, prepareRegister, prepareDeposit
        case discover, prepareTransfer, prepareWithdraw, bench, labelHash
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

    // MARK: - Requests

    struct Open: Encodable {
        /// 32 bytes, 0x-hex: the software key (`PrivacyPoolsKey`).
        let seed: String
        let revocableKeyIndex: String
        /// The address that owns the keystore entry: your account.
        let owner: String
        let network: PrivacyNetwork
    }

    struct Deposit: Encodable, Equatable {
        let tokenId: String
        let value: String
    }

    struct Spend: Encodable, Equatable {
        let tokenId: String
        let amount: String
        let recipient: String
    }

    struct Label: Encodable, Equatable {
        /// 0x-hex, as `PreparedDeposit.label` carries it.
        let label: String
    }

    struct Bench: Encodable, Equatable {
        let circuit: String
        let singleThread: Bool
    }

    // MARK: - Replies

    struct Info: Decodable, Equatable {
        let sdk: String
        let snarkjs: String
        let secureContext: Bool
        let webAssembly: Bool
        let workers: Bool
        let cores: Int
    }

    struct Opened: Decodable, Equatable {
        let viewingPublicKey: String
        let keysMs: Int
        let sessionMs: Int
    }

    struct Registered: Decodable, Equatable {
        let registered: Bool
        let ms: Int
    }

    struct Tx: Codable, Equatable {
        let to: String
        let data: String
        let value: String
    }

    struct Registration: Decodable, Equatable {
        let alreadyRegistered: Bool
        let txs: [Tx]
        let ms: Int
    }

    struct Proof: Decodable, Equatable {
        let circuit: String?
        let ms: Int
    }

    struct PreparedDeposit: Decodable, Equatable {
        let handle: String
        let tx: Tx
        let approvals: [Tx]
        let commitment: String
        let label: String
        /// Poseidon(label), decimal: what 0xBow's ASP files the deposit
        /// under (prd §1554). The raw label reads `unknown` forever.
        let labelHash: String
        let ms: Int
        let proofs: [Proof]
    }

    struct LabelHash: Decodable, Equatable {
        let labelHash: String
    }

    struct Note: Decodable, Equatable {
        let commitment: String
        let tokenId: String
        let value: String
        let status: String
        let label: String
    }

    struct Balance: Decodable, Equatable {
        let tokenId: String
        let value: String
    }

    struct Discovered: Decodable, Equatable {
        let notes: [Note]
        let balances: [Balance]
        let ms: Int
    }

    struct PreparedSpend: Decodable, Equatable {
        let handle: String
        let ms: Int
        let proofs: [Proof]
    }

    struct Benched: Decodable, Equatable {
        let circuit: String
        let loadMs: Int
        let witnessMs: Int
        let proveMs: Int
        let verifies: Bool
        let wasmBytes: Int
        let zkeyBytes: Int
    }

    // MARK: - Where a node request goes (prd §1554)

    /// The JSON-RPC methods a request body names: one object or a batch.
    static func rpcMethods(_ body: String?) -> [String] {
        guard let data = body?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let calls = (json as? [[String: Any]]) ?? ((json as? [String: Any]).map { [$0] } ?? [])
        return calls.compactMap { $0["method"] as? String }
    }

    /// The URL a request to the network's node is sent to: one asking for
    /// logs goes to the node that keeps the whole history (`logsUrl`), and
    /// everything else, or any request to another host, where it was going.
    static func routed(_ url: URL, body: String?, rpcUrl: String, logsUrl: String) -> URL {
        guard let node = URL(string: rpcUrl), url.host?.lowercased() == node.host?.lowercased(),
              rpcMethods(body).contains("eth_getLogs"), let logs = URL(string: logsUrl) else { return url }
        return logs
    }

    /// The history node lags the head by a block, and answers a range that
    /// reaches past it with an error: that request goes back to the node.
    static func missesHead(_ body: String) -> Bool {
        body.range(of: "beyond current head", options: .caseInsensitive) != nil
    }

    /// A free node's "slow down", by status or in the body: retried after a
    /// pause, never handed to the SDK as an answer.
    static func throttled(status: Int, body: String) -> Bool {
        status == 429 || body.range(of: #"too many requests|rate.?limit"#,
                                    options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - The network door

    /// Whether the engine may reach `url`: https, no credentials in the URL,
    /// the default port, and a host the engine's own `NetworkReach` entries
    /// declare (`declared`), on the label boundary. Everything else the page
    /// asks for is refused before it leaves the phone.
    static func allows(_ url: URL, declared: [String]) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return declared.contains { declaredHost in
            let d = declaredHost.lowercased()
            return host == d || host.hasSuffix("." + d)
        }
    }
}

/// One Privacy Pools v2 deployment the engine may use. **Testnet only**
/// (prd §1540): `check` refuses every chain but Sepolia, so no code path here
/// can prepare a mainnet move.
struct PrivacyNetwork: Codable, Equatable {
    let chainId: Int
    let rpcUrl: String
    let aspUrl: String
    let relayerUrl: String
    /// The relayer's signer: on chain it posts transfers itself, so a
    /// transfer's proof names it as the processor.
    let relayerAddress: String
    let transferProcessor: String
    /// PrivacyPoolRelay: the caller of a relayed withdrawal.
    let withdrawProcessor: String
    let entrypoint: String
    let pool: String
    let keystore: String
    let aspRegistry: String
    let fromBlock: Int

    /// Sepolia's v2 deployment (V9, pool 4), as 0xBow's dev ASP lists it
    /// (`/global/public/entrypoints`), its staging relayer answers
    /// (`/v1/details/evm/11155111`) and the SDK's `DEPLOYMENTS` pins,
    /// read 2026-10-26. The relayer is the v2 staging one; the website's
    /// source writes it as `relayer-staging.example`.
    static let sepolia = PrivacyNetwork(
        chainId: 11_155_111,
        rpcUrl: "https://ethereum-sepolia-rpc.publicnode.com",
        aspUrl: "https://api-dev.0xbow.io",
        relayerUrl: "https://relayer-v2-staging-149184580131.us-east1.run.app",
        relayerAddress: "0x4Ba5fF376865b370790A56276C63e7984DCFf1f7",
        transferProcessor: "0x4Ba5fF376865b370790A56276C63e7984DCFf1f7",
        withdrawProcessor: "0x7430cc030d7eb8C83E76cD983996982C8C054204",
        entrypoint: "0xEB3e3961008952348445513e418ad6F43C23ca9a",
        pool: "0x09b94d3127019298757A6ceeB7911922085f7C01",
        keystore: "0x6d264aCb9C3A7A3105c29470AfE2F5F1EC203C73",
        aspRegistry: "0x35D29EFDCf067599ab4A53cf40229477f0b1cA9c",
        // The KEYSTORE's first block, not pool 4's (10,994,884): the SDK
        // takes one `deploymentBlock` for every contract, and the keystore
        // is older; scanning from the pool leaves holes in its tree and a
        // spend's witness fails (`keystoreLeaves.0 undefined`, prd §1554).
        fromBlock: 10_932_354)

    /// The node old logs come from (prd §1554): PublicNode answers "pruned
    /// history unavailable" for the keystore's first blocks, and every other
    /// free Sepolia node tried caps the range or rate-limits; Tenderly's
    /// gateway served the whole range (measured 2026-10-26). It lags the
    /// head by a block, so a request it answers "beyond current head" goes
    /// back to `rpcUrl` (`SepoliaLogs`).
    static let sepoliaLogsUrl = "https://sepolia.gateway.tenderly.co"

    static let testnets: Set<Int> = [11_155_111]

    enum Refusal: Error, Equatable { case notTestnet(Int), noPins(Int) }

    /// The gate every `open` passes first.
    func check() throws {
        guard Self.testnets.contains(chainId) else { throw Refusal.notTestnet(chainId) }
        guard PrivacyArtifacts.pins(chainId: chainId) != nil else { throw Refusal.noPins(chainId) }
    }

    /// The hosts this network's engine reaches, for the door above.
    var hosts: [String] {
        [rpcUrl, aspUrl, relayerUrl, Self.sepoliaLogsUrl].compactMap { URL(string: $0)?.host?.lowercased() }
    }
}
