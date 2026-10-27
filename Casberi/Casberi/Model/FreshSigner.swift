import Foundation
import P256K

/// **A FRESH ADDRESS SIGNS ITS OWN DEPOSIT ON ETHEREUM (prd §1567).**
///
/// Address `i`'s key is `FreshAddress.key(root:index:)` of the fresh root
/// the private root in iCloud Keychain derives (`PrivateRoot.derive(_:
/// .freshAddresses)`, prd §1562): nothing new is kept, and a new phone walks
/// the same addresses back. The key is made for one signature and zeroed.
/// It signs only what `FreshTx` can make — a yield router's deposit, or a
/// token's approval of its own router — so it can pay no one and call
/// nothing else. Not behind Face ID: what it signs moves money INTO your
/// private balance, which only you can spend (prd §1562 item 4).
///
/// Shipping code (the kill switch, `PrivateMainnet.on`, is the way off);
/// the device-only root of the first Sepolia addresses stays DEBUG's
/// (`FreshAddressKey`).
enum FreshSigner {

    enum Failure: Error, Equatable { case noRoot, curve, refused(String), node(String), reverted(String), timedOut(String) }

    /// Address `index`'s key under private root `root`.
    static func key(_ index: UInt32, root: String) throws -> P256K.Recovery.PrivateKey {
        guard var privateRoot = PrivateRootKey.root(root) else { throw Failure.noRoot }
        defer { for i in privateRoot.indices { privateRoot[i] = 0 } }
        guard var fresh = PrivateRoot.derive(privateRoot, .freshAddresses) else { throw Failure.curve }
        defer { for i in fresh.indices { fresh[i] = 0 } }
        guard var k = FreshAddress.key(root: fresh, index: index) else { throw Failure.curve }
        defer { for i in k.indices { k[i] = 0 } }
        return try P256K.Recovery.PrivateKey(dataRepresentation: Data(k), format: .uncompressed)
    }

    /// Address `index` under `root`, checksummed.
    static func address(_ index: UInt32, root: String) throws -> String {
        let k = try key(index, root: root)
        guard let made = SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](k.publicKey.dataRepresentation)) else {
            throw Failure.curve
        }
        return made
    }

    /// Signs `call` as fresh address `index` at exactly this gas and these
    /// fees (fixed before what moves was planned), sends it and waits for it
    /// to land; returns its hash. Nil-built (`FreshTx.Tx`) for anything but a
    /// router's deposit or a token's approval of its router.
    static func send(to: String, data: String, value: String, index: UInt32, root: String, from: String,
                     network: PrivacyNetwork, gas: Int, tip: UInt64, maxFee: UInt64) async throws -> String {
        let nonce = try await PrivateRPC.call(network, "eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        guard let tx = FreshTx.Tx(network: network, nonce: nonce, maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
                                  maxFeePerGas: "0x" + String(maxFee, radix: 16), gas: "0x" + String(gas, radix: 16),
                                  to: to, value: value, data: data) else { throw Failure.refused("not a fresh address's move") }
        let k = try key(index, root: root)
        guard SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](k.publicKey.dataRepresentation))?.lowercased() == from.lowercased() else {
            throw Failure.curve
        }
        let signature = try k.signature(for: HashDigest(tx.signingHash))
        let compact = try signature.compactRepresentation
        let rs = [UInt8](compact.signature)
        guard rs.count == 64, let raw = tx.signed(yParity: Int(compact.recoveryId), r: Array(rs[0..<32]), s: Array(rs[32..<64])) else {
            throw Failure.curve
        }
        guard let hash = try await PrivateRPC.call(network, "eth_sendRawTransaction", [TestnetTx.hex(raw)]) as? String else {
            throw Failure.node("no hash")
        }
        NSLog("freshAddress| sent | %@ | %@ | gas %d", network.name, hash, gas)
        try await PrivateRPC.waitFor(hash, on: network)
        return hash
    }
}

/// **THE PRIVATE MONEY NODE (prd §1554, §1567).** One JSON-RPC call to a
/// network's node through the engine's door (Tor, a receipt each): what the
/// fresh addresses and the watch read and send on Sepolia and Ethereum. A
/// node's "slow down" is waited out; its error is thrown.
enum PrivateRPC {
    static func call(_ network: PrivacyNetwork, _ method: String, _ params: [Any]) async throws -> Any {
        guard let url = URL(string: network.rpcUrl) else { throw FreshSigner.Failure.node("no node") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        request.timeoutInterval = 30
        for attempt in 0..<5 {
            guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.service) else {
                throw FreshSigner.Failure.node("no answer from \(network.name)")
            }
            let text = String(decoding: data.prefix(512), as: UTF8.self)
            if PrivacyEngineWire.throttled(status: http.statusCode, body: text), attempt < 4 {
                try? await Task.sleep(for: .milliseconds(600 << attempt))
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FreshSigner.Failure.node("HTTP \(http.statusCode)")
            }
            if let error = json["error"] as? [String: Any] {
                throw FreshSigner.Failure.refused((error["message"] as? String) ?? "refused")
            }
            return json["result"] ?? NSNull()
        }
        throw FreshSigner.Failure.node("\(network.name)'s node is busy")
    }

    /// A quantity answer as decimal ("0x1bc16d674ec80000" → "2000000000000000000").
    static func decimal(_ network: PrivacyNetwork, _ method: String, _ params: [Any]) async throws -> String {
        PrivateMoney.decimal(hex: try await call(network, method, params) as? String ?? "0x0")
    }

    /// `balanceOf(owner)` of a token, base units.
    static func tokenBalance(_ network: PrivacyNetwork, token: String, of owner: String) async throws -> String {
        guard PrivateMoney.isAddress(owner) else { return "0" }
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.dropFirst(2).lowercased()
        let answer = try await call(network, "eth_call", [["to": token, "data": data], "latest"]) as? String ?? "0x"
        return PrivateYield.word(answer, 0) ?? "0"
    }

    /// Polls for the receipt, every 3 s for 4 min; a reverted one throws.
    static func waitFor(_ hash: String, on network: PrivacyNetwork) async throws {
        for _ in 0..<80 {
            if let receipt = try? await call(network, "eth_getTransactionReceipt", [hash]) as? [String: Any] {
                guard (receipt["status"] as? String) == "0x1" else { throw FreshSigner.Failure.reverted(hash) }
                return
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw FreshSigner.Failure.timedOut(hash)
    }

    /// Today's fees as a fresh address offers them: the node's tip (at least
    /// 1 wei) and a cap of twice the price plus the tip.
    static func fees(_ network: PrivacyNetwork) async throws -> (tip: UInt64, maxFee: UInt64) {
        let price = UInt64(try await decimal(network, "eth_gasPrice", [])) ?? 0
        let tipRaw = (try? await call(network, "eth_maxPriorityFeePerGas", [])) as? String
        return TestnetTx.fees(gasPrice: price, tip: UInt64(PrivateMoney.decimal(hex: tipRaw ?? "0x0")) ?? 0)
    }
}
