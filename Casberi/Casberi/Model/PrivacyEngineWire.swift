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
        case discover, prepareTransfer, prepareWithdraw, bench, labelHash, relay
        case prepareRagequit, prepareYieldDeposit
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

    /// Into a yield pool (prd §1563): the most of the token the deposit may
    /// spend, 0x-hex base units, fees included.
    struct YieldDeposit: Encodable, Equatable {
        let tokenId: String
        let budget: String
    }

    struct Label: Encodable, Equatable {
        /// 0x-hex, as `PreparedDeposit.label` carries it.
        let label: String
    }

    /// One note to take back (prd §1561), by its commitment.
    struct Ragequit: Encodable, Equatable {
        let commitment: String
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

    /// A yield deposit, proved (prd §1563): the router's call (for ETH its
    /// value is `maxUnderlyingIn`, the router refunding what it did not use),
    /// a token's approvals, the note, and the sizing — shares bought, the
    /// token they cost now, the most it may cost. Hex base units.
    struct PreparedYieldDeposit: Decodable, Equatable {
        let handle: String
        let tx: Tx
        let approvals: [Tx]
        let commitment: String
        let label: String
        let labelHash: String
        let share: String
        let shares: String
        let underlyingNeeded: String
        let maxUnderlyingIn: String
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
        /// The relayer's signed quote, as far as the app reads it: on a yield
        /// pool (prd §1563) the fee is shares, and what the router pays the
        /// recipient is `quotedUnderlyingOut`, never less than the floor.
        var fee: SpendFee? = nil
    }

    struct SpendFee: Decodable, Equatable {
        var feeAmount: String? = nil
        var amountSent: String? = nil
        var quotedUnderlyingOut: String? = nil
        var minUnderlyingOut: String? = nil
    }

    /// A prepared spend, named for the relayer (prd §1554).
    struct Handle: Codable, Equatable {
        let handle: String
    }

    /// What the relayer posted: the transaction's hash.
    struct Relayed: Decodable, Equatable {
        let tx: String
        let ms: Int
    }

    /// A ragequit, proved (prd §1561): the transaction for the account's
    /// owner to sign, the whole note's value and where the circuit sends it.
    struct PreparedRagequit: Decodable, Equatable {
        let handle: String
        let tx: Tx
        let value: String
        let recipient: String
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
    /// MEV Blocker's busy answer to a log window (`-32603 service temporarily
    /// unavailable`, Ethereum, prd §1563) is the same kind: asked again, it
    /// answers.
    static func throttled(status: Int, body: String) -> Bool {
        status == 429 || body.range(of: #"too many requests|rate.?limit|temporarily unavailable"#,
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

/// **THE KILL SWITCH (prd §1563).** Private money on Ethereum — your
/// private balance, earning on Aave — is ON in every build, the App Store's
/// and TestFlight's included (user, 2026-10-26: "we want it on for app store
/// and testflight"). This one constant turns it off in a hurry: false, and no
/// screen offers it, the engine refuses Ethereum (`PrivacyNetwork.check`) and
/// nothing reads its pool. Sepolia and the DEBUG test sender stay DEBUG-only.
enum PrivateMainnet {
    static let on = true
}

/// One Privacy Pools v2 deployment the engine may use: Sepolia (the DEBUG
/// build's test money) and Ethereum (prd §1563). `check` refuses every other
/// chain, and Ethereum when the kill switch is off.
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
    /// 0xBow's yield pools here (prd §1563): what is private earns on Aave.
    /// Empty on Sepolia, which has none.
    var yield: [YieldPool] = []

    /// One yield pool: the share token the pool holds (ppETH, ppUSDC), the
    /// token you hold (WETH, USDC), the router that wraps on the way in and
    /// unwraps on the way out (ppETH's takes and pays native ETH), and the
    /// zap that turns loose shares back into the token (after Take it back).
    struct YieldPool: Codable, Equatable {
        /// What the app calls the money: "ETH" for ppETH, "USDC" for ppUSDC.
        let symbol: String
        let native: Bool
        let share: String
        let shareDecimals: Int
        let underlying: String
        let underlyingDecimals: Int
        let router: String
        let zap: String
    }

    var name: String { chainId == 1 ? "Ethereum" : "Sepolia" }
    var isTest: Bool { Self.testnets.contains(chainId) }

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

    /// **ETHEREUM (prd §1563)**, 0xBow's production v2 (pool 1), read
    /// 2026-10-26 from the production relayer (`/v1/details/evm/1`: the
    /// contracts, the signer, the processors and the yield pools), the ASP
    /// (`api-v2.0xbow.io/global/public/entrypoints`: the keystore) and the
    /// chain (`PoolVault.keystore()`, `.aspRegistry()`, each address's code;
    /// the implementations are verified on Sourcify).
    /// `tools/privacy-pools-engine/mainnet-sim.mjs` runs every move against
    /// these addresses in simulation.
    static let ethereum = PrivacyNetwork(
        chainId: 1,
        // State, calls and logs through Tor from MEV Blocker (§1495): the
        // SDK reads logs in 10,000-block windows, which MEV Blocker answers
        // through Tor, now and then after a "temporarily unavailable" the
        // door waits out (measured 2026-10-26: the v2 contracts' 2,912 logs
        // since the keystore's first block, every window answered).
        // PublicNode walls old logs behind a token, Tenderly refuses Tor,
        // and Flashbots answers pruned windows with NOTHING (235 of 2,912).
        rpcUrl: "https://rpc.mevblocker.io",
        aspUrl: "https://api-v2.0xbow.io",
        relayerUrl: "https://relayer-v2-prod-149184580131.us-east1.run.app",
        relayerAddress: "0x9e2f1B234953F46c6091636290E9035618EA3C07",
        transferProcessor: "0x9e2f1B234953F46c6091636290E9035618EA3C07",
        withdrawProcessor: "0x01a8Fa4dbb60187aD8d3c3d08E7Fb8C14198A461",
        entrypoint: "0xca1e072236D231130059eeA6Bfceb7F4e9a1F0C3",
        pool: "0x0Eb42804BF897662aF851370eaeAdcDBEC1b97ed",
        keystore: "0x6E463391c79b7e1A88eF26E0B023f9A6C9938a71",
        aspRegistry: "0x259C0BEa1d783c202509BD3b2688d23b8AEf58B0",
        // The keystore's first log, 25,884,231: older than the PoolVault
        // (25,884,277) and the Entrypoint (25,884,284), and far older than
        // the ASP's own `fromBlock` (25,893,288), which would leave holes.
        fromBlock: 25_884_231,
        yield: [
            YieldPool(symbol: "ETH", native: true,
                      share: "0x66051920D25af4E3596A8a46309F4D045F9D83B7", shareDecimals: 18,
                      underlying: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", underlyingDecimals: 18,
                      router: "0x77613D670BB9fD48A9898D0eac8ebf21B566F960",
                      zap: "0x33c1eEf370bBb447414156CFc4fDABD434776EAf"),
            YieldPool(symbol: "USDC", native: false,
                      share: "0xC246aFb23482fF9596E9cee5f1f678eFe0EB1ad6", shareDecimals: 18,
                      underlying: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", underlyingDecimals: 6,
                      router: "0xe76E793d776c1e207aD7a7fa7C57d27420d85110",
                      zap: "0x9Ea986BcDF6784D85B518b15bEEE1E65b585817B"),
        ])

    /// The node old logs come from (prd §1554): PublicNode answers "pruned
    /// history unavailable" for the keystore's first blocks, and every other
    /// free Sepolia node tried caps the range or rate-limits; Tenderly's
    /// gateway served the whole range (measured 2026-10-26). It lags the
    /// head by a block, so a request it answers "beyond current head" goes
    /// back to `rpcUrl` (`SepoliaLogs`). Ethereum reads its logs from its
    /// own node (`logsUrl` nil there).
    static let sepoliaLogsUrl = "https://sepolia.gateway.tenderly.co"

    var logsUrl: String? { chainId == Self.sepolia.chainId ? Self.sepoliaLogsUrl : nil }

    static let testnets: Set<Int> = [11_155_111]

    /// The networks the engine may open: Sepolia, and Ethereum unless the
    /// kill switch is off.
    static var served: Set<Int> { PrivateMainnet.on ? testnets.union([1]) : testnets }

    /// The network private money uses in this build: Ethereum; in a DEBUG
    /// build Sepolia, unless `-privateNetwork ethereum` asks for Ethereum
    /// (the simulator's test notes live on Sepolia). Nil: none (the kill
    /// switch is off).
    static func current(debugAsks: String?) -> PrivacyNetwork? {
        #if DEBUG
        if debugAsks == "ethereum" { return PrivateMainnet.on ? .ethereum : nil }
        return .sepolia
        #else
        return PrivateMainnet.on ? .ethereum : nil
        #endif
    }

    /// The network a note was made on, if this build serves it.
    static func forChain(_ chainId: Int) -> PrivacyNetwork? {
        switch chainId {
        case sepolia.chainId: .sepolia
        case ethereum.chainId: PrivateMainnet.on ? .ethereum : nil
        default: nil
        }
    }

    /// The yield pool serving `token`: its share, its underlying, or ETH for
    /// the pool whose router takes native ETH.
    func yieldPool(for token: String) -> YieldPool? {
        let t = token.lowercased()
        return yield.first { $0.share.lowercased() == t || $0.underlying.lowercased() == t
            || ($0.native && t == "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee") }
    }

    enum Refusal: Error, Equatable { case notServed(Int), noPins(Int) }

    /// The gate every `open` passes first.
    func check() throws {
        guard Self.served.contains(chainId) else { throw Refusal.notServed(chainId) }
        guard PrivacyArtifacts.pins(chainId: chainId) != nil else { throw Refusal.noPins(chainId) }
    }

    /// The hosts this network's engine reaches, for the door above.
    var hosts: [String] {
        ([rpcUrl, aspUrl, relayerUrl] + (logsUrl.map { [$0] } ?? [])).compactMap { URL(string: $0)?.host?.lowercased() }
    }
}
