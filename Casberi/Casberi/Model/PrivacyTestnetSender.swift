#if DEBUG
import Foundation
import Security
import P256K

/// **THE TESTNET SENDER (prd §1554) — DEBUG builds only, Sepolia only.**
///
/// Move to private needs something to SEND the deposit. Your account (prd
/// §1424) is the right sender and the one this becomes: but it runs on Base,
/// Ethereum and Robinhood only (Sepolia was removed from it, §1441a), and it
/// signs with a Secure Enclave key a simulator does not have. So until the
/// pool reaches mainnet, a DEBUG build sends from this: one secp256k1 key
/// made on this device, kept in the Keychain on this device only
/// (`…WhenUnlockedThisDeviceOnly`, never synchronizable), whose address owns
/// the private account's keystore entry too.
///
/// It can sign nothing but a testnet transaction (`TestnetTx.Tx` cannot be
/// made for another chain), it is compiled out of every shipped binary, and
/// it holds only Sepolia ETH someone sent it.
///
/// **Since prd §1562 the sender is the private root's owner**
/// (`PrivateAccount`), derived from the root in iCloud Keychain, so a new
/// phone sends from the same address and nothing it held is lost. A phone
/// that made the device-only key before the root keeps sending from it (its
/// Sepolia ETH stays where it is); no new device-only key is made.
enum PrivacyTestnetSender {

    private static let service = "com.casberi.app.testnet-sender"
    private static let account = "sepolia-sender-v1"
    private static let addressKey = "privacyTestnetSender.address"
    static let network = PrivacyNetwork.sepolia

    enum Failure: Error, Equatable {
        case noKey, keychain(OSStatus), curve, node(String), refused(String), reverted(String), timedOut(String)
    }

    // MARK: - The key

    static var address: String? { UserDefaults.standard.string(forKey: addressKey) }

    /// The device-only sender's address, while its key is on this phone
    /// (made before prd §1562; no new one is ever made).
    static var legacyAddress: String? {
        guard let key = try? read() else { return nil }
        return SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation))
    }

    /// The sender's address: the device-only key's where one was made before
    /// the root (prd §1554), else the root's owner (prd §1562), the root made
    /// the first time.
    static func ensure() throws -> String {
        if let legacy = legacyAddress {
            if address != legacy { UserDefaults.standard.set(legacy, forKey: addressKey) }
            return legacy
        }
        return try PrivateAccount.ownerAddress(try PrivateRootKey.ensure())
    }

    /// The sender's key and address.
    static func signer() throws -> (key: P256K.Recovery.PrivateKey, from: String) {
        if let key = try? read(), let from = legacyAddress { return (key, from) }
        let id = try PrivateRootKey.ensure()
        return (try PrivateAccount.ownerKey(id), try PrivateAccount.ownerAddress(id))
    }

    private static func read() throws -> P256K.Recovery.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw status == errSecItemNotFound ? Failure.noKey : Failure.keychain(status)
        }
        return try P256K.Recovery.PrivateKey(dataRepresentation: data, format: .uncompressed)
    }

    /// `-privacySenderForget YES`: the key and its address go.
    static func forget() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
        UserDefaults.standard.removeObject(forKey: addressKey)
    }

    // MARK: - The node

    static func rpc(_ method: String, _ params: [Any]) async throws -> Any {
        guard let url = URL(string: network.rpcUrl) else { throw Failure.node("no node") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        request.timeoutInterval = 30
        for attempt in 0..<5 {
            guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.service) else {
                throw Failure.node("no answer from the Sepolia node")
            }
            let text = String(decoding: data.prefix(512), as: UTF8.self)
            if PrivacyEngineWire.throttled(status: http.statusCode, body: text), attempt < 4 {
                try? await Task.sleep(for: .milliseconds(600 << attempt))
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure.node("HTTP \(http.statusCode)")
            }
            if let error = json["error"] as? [String: Any] {
                throw Failure.refused((error["message"] as? String) ?? "refused")
            }
            return json["result"] ?? NSNull()
        }
        throw Failure.node("the Sepolia node is busy")
    }

    static func hexToDecimal(_ hex: String) -> String {
        guard let bytes = TestnetTx.quantity(hex) else { return "0" }
        var digits: [Int] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in stride(from: digits.count - 1, through: 0, by: -1) {
                let v = digits[i] * 256 + carry
                digits[i] = v % 10
                carry = v / 10
            }
            while carry > 0 { digits.insert(carry % 10, at: 0); carry /= 10 }
        }
        let s = digits.map(String.init).joined().drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }

    /// The sender's Sepolia ETH, base units, decimal.
    static func balance() async throws -> String {
        try await balance(of: try ensure())
    }

    static func balance(of address: String) async throws -> String {
        hexToDecimal(try await rpc("eth_getBalance", [address, "latest"]) as? String ?? "0x0")
    }

    static func gasPrice() async throws -> String {
        hexToDecimal(try await rpc("eth_gasPrice", []) as? String ?? "0x0")
    }

    // MARK: - Sending

    /// Runs one prepared transaction from the sender against the latest
    /// block without sending it (`eth_call`): a call that would revert throws
    /// `.refused` here, before anything is signed (prd §1561).
    static func simulate(_ prepared: PrivacyEngineWire.Tx) async throws {
        let from = try ensure()
        let call: [String: Any] = ["from": from, "to": prepared.to, "data": prepared.data, "value": prepared.value]
        _ = try await rpc("eth_call", [call, "latest"])
        NSLog("privateMove| simulated | %@", String(prepared.to.suffix(4)))
    }

    /// Signs and sends one prepared transaction from the sender, then waits
    /// for it to land; returns its hash. Refuses anything off Sepolia.
    static func send(_ prepared: PrivacyEngineWire.Tx, gasFloor: Int = 0) async throws -> String {
        let (key, from) = try signer()
        return try await send(prepared, key: key, from: from, gasFloor: gasFloor)
    }

    /// Signs and sends `prepared` from `from` with `key` at the node's
    /// estimate (×1.25) and fees. The root's owner registers its keystore
    /// through here when it is not the sender (prd §1562).
    static func send(_ prepared: PrivacyEngineWire.Tx, key: P256K.Recovery.PrivateKey, from: String,
                     gasFloor: Int = 0) async throws -> String {
        let call: [String: Any] = ["from": from, "to": prepared.to, "data": prepared.data, "value": prepared.value]
        let estimate = Int(hexToDecimal(try await rpc("eth_estimateGas", [call]) as? String ?? "0x0")) ?? 0
        let price = UInt64(hexToDecimal(try await rpc("eth_gasPrice", []) as? String ?? "0x0")) ?? 0
        let tipRaw = (try? await rpc("eth_maxPriorityFeePerGas", [])) as? String
        let fees = TestnetTx.fees(gasPrice: price, tip: UInt64(hexToDecimal(tipRaw ?? "0x0")) ?? 0)
        return try await send(prepared, key: key, from: from, gas: max(estimate * 5 / 4, gasFloor),
                              tip: fees.tip, maxFee: fees.maxFee)
    }

    /// Signs `prepared` with `key` as `from` at exactly this gas and these
    /// fees, sends it and waits for it to land; returns its hash. The fresh
    /// addresses send through here (prd §1560), their fees fixed before the
    /// deposit's value was planned. Refuses anything off Sepolia.
    static func send(_ prepared: PrivacyEngineWire.Tx, key: P256K.Recovery.PrivateKey, from: String,
                     gas: Int, tip: UInt64, maxFee: UInt64) async throws -> String {
        let nonce = try await rpc("eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        guard let tx = TestnetTx.Tx(chainId: network.chainId, nonce: nonce,
                                    maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
                                    maxFeePerGas: "0x" + String(maxFee, radix: 16),
                                    gas: "0x" + String(gas, radix: 16), to: prepared.to,
                                    value: prepared.value, data: prepared.data) else { throw Failure.curve }
        let signature = try key.signature(for: HashDigest(tx.signingHash))
        let compact = try signature.compactRepresentation
        let rs = [UInt8](compact.signature)
        guard rs.count == 64,
              let raw = tx.signed(yParity: Int(compact.recoveryId), r: Array(rs[0..<32]), s: Array(rs[32..<64])) else {
            throw Failure.curve
        }
        guard let hash = try await rpc("eth_sendRawTransaction", [TestnetTx.hex(raw)]) as? String else {
            throw Failure.node("no hash")
        }
        NSLog("privateMove| sent | %@ | gas %d", hash, gas)
        try await waitFor(hash)
        return hash
    }

    /// Polls for the receipt, every 3 s for 4 min; a reverted one throws.
    static func waitFor(_ hash: String) async throws {
        for _ in 0..<80 {
            if let receipt = try? await rpc("eth_getTransactionReceipt", [hash]) as? [String: Any] {
                guard (receipt["status"] as? String) == "0x1" else { throw Failure.reverted(hash) }
                return
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw Failure.timedOut(hash)
    }
}
#endif
