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
    /// fees (fixed before what moves was planned) and broadcasts it; returns
    /// its hash. Nil-built (`FreshTx.Tx`) for anything but a router's deposit
    /// or a token's approval of its router.
    ///
    /// **KEPT BEFORE IT GOES, NEVER WAITED ON HERE (the review of
    /// 2026-10-26, finding 2).** `kept` is told the hash and the nonce before
    /// the node is asked, so a move outlives the app and is never signed
    /// twice; the caller waits as long as it likes and a wait that ends is
    /// not a failure. Only the node's own refusal (`refused`) means the
    /// transaction is not out; no answer at all may still mean it is.
    static func send(to: String, data: String, value: String, index: UInt32, root: String, from: String,
                     network: PrivacyNetwork, gas: Int, tip: UInt64, maxFee: UInt64, nonceAt: String = "pending",
                     kept: (_ hash: String, _ nonce: String) -> Void) async throws -> String {
        // `latest` for a sweep (prd §2009): a send MEV Blocker holds and
        // never mines must not leave the next one waiting behind it.
        let nonce = try await PrivateRPC.call(network, "eth_getTransactionCount", [from, nonceAt]) as? String ?? "0x0"
        // **A RAILGUN RELAY IS RUN BEFORE IT IS SENT (prd §1894).** MEV
        // Blocker drops a transaction that would revert and says nothing:
        // a private swap read "Swapped" and was never mined (2026-11-18,
        // 0x9d7c8c66…). Its approvals ride inside the relay, so a dry run at
        // the latest block is the transaction's own; one that reverts is not
        // signed, and its reason is said.
        if to.lowercased() == FreshTx.railgunRelayAdapt {
            do {
                _ = try await PrivateRPC.call(network, "eth_call", [["from": from, "to": to, "data": data, "value": value,
                                                                      "gas": "0x" + String(gas, radix: 16)], "latest"])
            } catch Failure.refused(let why) {
                NSLog("freshAddress| would revert | %@ | %@", network.name, why)
                throw Failure.reverted(why)
            }
        }
        // **ITS FEE FITS WHAT IT HOLDS (prd §1894).** A fresh address is
        // funded with the gas at one moment's price and sends at the next's:
        // a ceiling over its balance is a transaction no block can take, and
        // MEV Blocker keeps it without a word (2026-11-18, 0x9d7c8c66…, 20
        // minutes unmined). The ceiling comes down to the balance; under the
        // price now, it is not sent.
        var maxFee = maxFee
        let held = UInt64(try await PrivateRPC.decimal(network, "eth_getBalance", [from, "latest"])) ?? 0
        let carried = UInt64(PrivateMoney.decimal(hex: value)) ?? 0
        if held >= carried, gas > 0 {
            let fits = (held - carried) / UInt64(gas)
            if fits < maxFee {
                let price = UInt64(try await PrivateRPC.decimal(network, "eth_gasPrice", [])) ?? 0
                guard fits >= max(price, tip) else {
                    NSLog("freshAddress| gas rose | %@ | holds %llu, needs %llu a unit", network.name, fits, price)
                    throw Failure.refused("its gas rose past what it holds")
                }
                maxFee = fits
            }
        }
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
        // The hash is the signed bytes' own: known, and kept, before it goes.
        let hash = "0x" + Keccak256.hexString(Keccak256.hash(raw))
        kept(hash, PrivateMoney.decimal(hex: nonce))
        do {
            _ = try await PrivateRPC.call(network, "eth_sendRawTransaction", [TestnetTx.hex(raw)])
        } catch Failure.refused(let why) where why.lowercased().contains("already known") {
            // The node has it already: out.
        }
        NSLog("freshAddress| sent | %@ | %@ | gas %d", network.name, hash, gas)
        return hash
    }

    /// **A DOLLAR'S MOVE (prd §1880).** Signs and sends a fresh address's
    /// approval of a SpokePool, a dollar's home deposit on Base or Robinhood,
    /// or a fresh sender's dollar deposit on Ethereum, on `node`; nil-built
    /// (`FreshTx.Tx(dollar:)`) for anything else. Kept before it goes.
    static func sendDollar(chainId: Int, node: String, name: String, to: String, data: String,
                           index: UInt32, root: String, from: String, gas: Int, tip: UInt64, maxFee: UInt64,
                           kept: (_ hash: String, _ nonce: String) -> Void) async throws -> String {
        let nonce = try await PrivateRPC.call(at: node, named: name, "eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        guard let tx = FreshTx.Tx(dollar: chainId, from: from, nonce: nonce, maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
                                  maxFeePerGas: "0x" + String(maxFee, radix: 16), gas: "0x" + String(gas, radix: 16),
                                  to: to, value: "0x0", data: data) else { throw Failure.refused("not a fresh address's move") }
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
        let hash = "0x" + Keccak256.hexString(Keccak256.hash(raw))
        kept(hash, PrivateMoney.decimal(hex: nonce))
        do {
            _ = try await PrivateRPC.call(at: node, named: name, "eth_sendRawTransaction", [TestnetTx.hex(raw)])
        } catch Failure.refused(let why) where why.lowercased().contains("already known") {
        }
        NSLog("freshAddress| sent dollar | %@ | %@ | gas %d", name, hash, gas)
        return hash
    }

    /// **A REFUND SENT ON (prd §1882).** A fresh sender's `amount` of WETH
    /// or USDC to your receive address `receiveIndex`, which this derives
    /// itself under the same root (a receive index, never a sender's): the
    /// only payment a sender's key can make. On Ethereum.
    static func sendRefund(token: String, amount: String, receiveIndex: UInt32, index: UInt32, root: String, from: String,
                           network: PrivacyNetwork, gas: Int, tip: UInt64, maxFee: UInt64) async throws -> String {
        guard network.chainId == FreshTx.homeChain, receiveIndex < FreshAddress.senderBase else { throw Failure.refused("not your receive address") }
        let recipient = try address(receiveIndex, root: root)
        guard let data = FreshTx.transferData(to: recipient, amount: amount) else { throw Failure.refused("not a refund") }
        let nonce = try await PrivateRPC.call(network, "eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        guard let tx = FreshTx.Tx(refund: recipient, nonce: nonce, maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
                                  maxFeePerGas: "0x" + String(maxFee, radix: 16), gas: "0x" + String(gas, radix: 16),
                                  to: token, data: data) else { throw Failure.refused("not a fresh address's move") }
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
        let hash = "0x" + Keccak256.hexString(Keccak256.hash(raw))
        do {
            _ = try await PrivateRPC.call(network, "eth_sendRawTransaction", [TestnetTx.hex(raw)])
        } catch Failure.refused(let why) where why.lowercased().contains("already known") {
        }
        NSLog("freshAddress| refund sent on | %@ | to receive %u", hash, receiveIndex)
        return hash
    }

    /// **AWAY FROM ETHEREUM (prd §1879).** Signs and sends a fresh sender's
    /// Across deposit to Base or Robinhood on Ethereum; nil-built
    /// (`FreshTx.Tx(away:)`) for anything else.
    static func sendAway(to: String, data: String, value: String, index: UInt32, root: String, from: String,
                         network: PrivacyNetwork, gas: Int, tip: UInt64, maxFee: UInt64,
                         kept: (_ hash: String, _ nonce: String) -> Void) async throws -> String {
        let nonce = try await PrivateRPC.call(network, "eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        guard network.chainId == FreshTx.homeChain,
              let tx = FreshTx.Tx(away: from, nonce: nonce, maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
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
        let hash = "0x" + Keccak256.hexString(Keccak256.hash(raw))
        kept(hash, PrivateMoney.decimal(hex: nonce))
        do {
            _ = try await PrivateRPC.call(network, "eth_sendRawTransaction", [TestnetTx.hex(raw)])
        } catch Failure.refused(let why) where why.lowercased().contains("already known") {
        }
        NSLog("freshAddress| sent away | %@ | gas %d", hash, gas)
        return hash
    }

    /// **HOME TO ETHEREUM (prd §1878).** Signs and sends address `index`'s
    /// Across deposit to itself on Base or Robinhood, at exactly this gas and
    /// these fees; nil-built (`FreshTx.Tx(home:)`) for anything else. Kept
    /// before it goes, as `send` is.
    static func sendHome(chainId: Int, node: String, name: String, to: String, data: String, value: String,
                         index: UInt32, root: String, from: String, gas: Int, tip: UInt64, maxFee: UInt64,
                         kept: (_ hash: String, _ nonce: String) -> Void) async throws -> String {
        let nonce = try await PrivateRPC.call(at: node, named: name, "eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        guard let tx = FreshTx.Tx(home: chainId, from: from, nonce: nonce, maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
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
        let hash = "0x" + Keccak256.hexString(Keccak256.hash(raw))
        kept(hash, PrivateMoney.decimal(hex: nonce))
        do {
            _ = try await PrivateRPC.call(at: node, named: name, "eth_sendRawTransaction", [TestnetTx.hex(raw)])
        } catch Failure.refused(let why) where why.lowercased().contains("already known") {
        }
        NSLog("freshAddress| sent home | %@ | %@ | gas %d", name, hash, gas)
        return hash
    }

    /// Waits for `hash` at most `seconds`: true landed, false still out (a
    /// wait that ends says nothing); a reverted one throws.
    static func landed(_ hash: String, on network: PrivacyNetwork, seconds: Int = 240) async throws -> Bool {
        do {
            try await PrivateRPC.waitFor(hash, on: network, seconds: seconds)
            return true
        } catch Failure.timedOut {
            return false
        }
    }
}

/// **THE PRIVATE MONEY NODE (prd §1554, §1567).** One JSON-RPC call to a
/// network's node through the engine's door (Tor, a receipt each): what the
/// fresh addresses and the watch read and send on Sepolia and Ethereum. A
/// node's "slow down" is waited out; its error is thrown.
enum PrivateRPC {
    static func call(_ network: PrivacyNetwork, _ method: String, _ params: [Any]) async throws -> Any {
        try await call(at: network.rpcUrl, named: network.name, method, params)
    }

    /// The same call to any node (prd §1878: Base's and Robinhood's, where a
    /// fresh address sends what it was paid home).
    static func call(at node: String, named name: String, _ method: String, _ params: [Any]) async throws -> Any {
        guard let url = URL(string: node) else { throw FreshSigner.Failure.node("no node") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        request.timeoutInterval = 30
        for attempt in 0..<5 {
            guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.service) else {
                throw FreshSigner.Failure.node("no answer from \(name)")
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
        throw FreshSigner.Failure.node("\(name)'s node is busy")
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

    /// Polls for the receipt, every 3 s for `seconds` (4 min); a reverted one
    /// throws, and so does the end of the wait (`timedOut`) — which says
    /// only that it was not seen yet.
    static func waitFor(_ hash: String, on network: PrivacyNetwork, seconds: Int = 240) async throws {
        for _ in 0..<max(seconds / 3, 1) {
            if let receipt = try? await call(network, "eth_getTransactionReceipt", [hash]) as? [String: Any] {
                guard (receipt["status"] as? String) == "0x1" else { throw FreshSigner.Failure.reverted(hash) }
                return
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw FreshSigner.Failure.timedOut(hash)
    }

    /// `waitFor` on any node (prd §1880: a dollar's approval on Base or Robinhood).
    static func waitFor(at node: String, named name: String, _ hash: String, seconds: Int = 240) async throws {
        for _ in 0..<max(seconds / 3, 1) {
            if let receipt = try? await call(at: node, named: name, "eth_getTransactionReceipt", [hash]) as? [String: Any] {
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
