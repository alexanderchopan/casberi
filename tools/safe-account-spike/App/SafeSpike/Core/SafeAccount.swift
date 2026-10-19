import Foundation

/// "Your account" on a testnet: a Safe 1.4.1 whose one owner is Safe's own
/// shared passkey signer, configured with this device's P-256 key, run
/// through Safe's 4337 module. Every contract is Safe's, deployed and audited
/// (prd §1380); the addresses are Safe's own deployment records, identical on
/// Base, Base Sepolia, Ethereum and Sepolia (measured 2026-10-19).
///
/// The key that signs is a P-256 key the caller holds (the Secure Enclave in
/// the app, a software key in the Mac check). What it signs is the module's
/// SafeOp hash — read from the module itself (`getOperationHash`), never
/// re-derived — as a WebAuthn challenge, in the exact bytes Casberi's §913
/// co-signer already proved on chain (`SafeWebAuthn`).
enum SafeAccount {
    static let safeL2 = "0x29fcB43b46531BcA003ddC8FCB67FFE91900C762"
    static let proxyFactory = "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67"
    static let multiSend = "0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526"
    static let module4337 = "0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226"
    static let moduleSetup = "0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47"
    static let sharedSigner = "0x94a4F6affBd8975951142c3999aEAB7ecee555c2"
    static let entryPoint = "0x0000000071727De22E5E9d8BAf0edAc6f37da032"

    struct Key: Sendable {
        let x: [UInt8]
        let y: [UInt8]
        /// Signs 32 pre-hashed bytes; returns `r ‖ s`, `s` low.
        let sign: @Sendable ([UInt8]) async throws -> (r: [UInt8], s: [UInt8])
    }

    // MARK: - ABI, the little the account needs

    static func sel(_ signature: String) -> [UInt8] { SafeABI.hexBytes(SafeCalldata.selector(signature))! }
    static func w(_ address: String) -> [UInt8] { SafeABI.word(address: address)! }
    static func w(_ n: Int) -> [UInt8] { SafeABI.word(uint: n)! }
    static func w(dec text: String) -> [UInt8] { SafeABI.word(uint256: text)! }
    static func padded(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: (32 - bytes.count % 32) % 32) }
    static func dynamic(_ bytes: [UInt8]) -> [UInt8] { w(bytes.count) + padded(bytes) }
    static func addressBytes(_ address: String) -> [UInt8] { Array(w(address).suffix(20)) }
    static func hex(_ bytes: [UInt8]) -> String { SafeABI.hex(bytes) }
    static func quantity(_ n: UInt64) -> String { "0x" + String(n, radix: 16) }

    /// `P256.Verifiers`: the precompile first, Daimo's verifier after it.
    static var verifiers: [UInt8] { SafeWebAuthn.verifiersWord! }

    /// `configure((uint256 x, uint256 y, uint176 verifiers))`, delegate-called by the Safe.
    static func configure(_ key: Key) -> [UInt8] {
        sel("configure((uint256,uint256,uint176))") + key.x + key.y + verifiers
    }

    struct Call { let operation: UInt8; let to: String; let value: UInt64; let data: [UInt8] }

    /// `multiSend(bytes)` over MultiSend 1.4.1's packed transactions.
    static func multiSend(_ calls: [Call]) -> [UInt8] {
        var packed: [UInt8] = []
        for c in calls {
            packed += [c.operation] + addressBytes(c.to) + w(dec: String(c.value)) + w(c.data.count) + c.data
        }
        return sel("multiSend(bytes)") + w(32) + dynamic(packed)
    }

    /// `Safe.setup`: the shared signer as the one owner, threshold 1, the
    /// 4337 module as module and fallback handler, the key configured — the
    /// two set-up steps batched through MultiSend, both delegate calls.
    static func initializer(_ key: Key) -> [UInt8] {
        let enable = sel("enableModules(address[])") + w(32) + w(1) + w(module4337)
        let setupData = multiSend([
            Call(operation: 1, to: moduleSetup, value: 0, data: enable),
            Call(operation: 1, to: sharedSigner, value: 0, data: configure(key)),
        ])
        let owners = w(1) + w(sharedSigner)
        let headWords = 8
        let ownersOffset = headWords * 32
        let dataOffset = ownersOffset + owners.count
        return sel("setup(address[],uint256,address,bytes,address,address,uint256,address)")
            + w(ownersOffset) + w(1) + w(multiSend) + w(dataOffset)
            + w(module4337) + w(SafeTransaction.zeroAddress) + w(0) + w(SafeTransaction.zeroAddress)
            + owners + dynamic(setupData)
    }

    /// `createProxyWithNonce(singleton, initializer, saltNonce)`.
    static func factoryData(_ key: Key, salt: Int = 0) -> [UInt8] {
        sel("createProxyWithNonce(address,bytes,uint256)") + w(safeL2) + w(96) + w(salt) + dynamic(initializer(key))
    }

    /// The account's address, whether or not it exists yet: SafeProxyFactory
    /// 1.4.1's own CREATE2 — salt `keccak(keccak(initializer) ‖ saltNonce)`,
    /// code `proxyCreationCode ‖ singleton` — with the creation code read
    /// from the factory itself. (Simulating a create answers only until the
    /// account exists: after that the factory reverts "Create2 call failed".)
    static func address(_ net: Chain.Network, _ key: Key, salt: Int = 0) async throws -> String {
        let creation = try await proxyCreationCode(net)
        let saltHash = Keccak256.hash(Keccak256.hash(initializer(key)) + w(salt))
        let codeHash = Keccak256.hash(creation + w(safeL2))
        let digest = Keccak256.hash([0xff] + addressBytes(proxyFactory) + saltHash + codeHash)
        return EIP55.checksum("0x" + Keccak256.hexString(Array(digest.suffix(20))))
    }

    /// The factory's answer by simulation — the check `address` is held to
    /// while an account does not exist yet.
    static func simulatedAddress(_ net: Chain.Network, _ key: Key, salt: Int = 0) async throws -> String {
        let answer = try await Chain.ethCall(net, to: proxyFactory, data: hex(factoryData(key, salt: salt)))
        guard let a = SafeWebAuthn.decodeAddress(answer) else { throw Chain.RPCError(message: "factory gave no address: \(answer)") }
        return a
    }

    nonisolated(unsafe) private static var creationCode: [UInt8]?
    static func proxyCreationCode(_ net: Chain.Network) async throws -> [UInt8] {
        if let creationCode { return creationCode }
        let answer = try await Chain.ethCall(net, to: proxyFactory, data: hex(sel("proxyCreationCode()")))
        guard let bytes = SafeABI.hexBytes(answer), bytes.count >= 64 else { throw Chain.RPCError(message: "no creation code") }
        let length = Int(UInt64(Keccak256.hexString(Array(bytes[56..<64])), radix: 16) ?? 0)
        guard bytes.count >= 64 + length else { throw Chain.RPCError(message: "short creation code") }
        creationCode = Array(bytes[64..<(64 + length)])
        return creationCode!
    }

    /// `executeUserOp(to, value, data, operation)`, the only call the module runs.
    static func execute(_ c: Call) -> [UInt8] {
        sel("executeUserOp(address,uint256,bytes,uint8)") + w(c.to) + w(dec: String(c.value)) + w(128) + w(Int(c.operation)) + dynamic(c.data)
    }

    /// A send, and — when `rotateTo` is given — the key change in the same
    /// transaction (spec §3b): MultiSend, delegate-called, pays then
    /// re-configures the shared signer to the next key. A failed transaction
    /// rotates nothing.
    static func sendCall(to: String, value: UInt64, rotateTo next: Key?) -> [UInt8] {
        guard let next else { return execute(Call(operation: 0, to: to, value: value, data: [])) }
        let batch = multiSend([
            Call(operation: 0, to: to, value: value, data: []),
            Call(operation: 1, to: sharedSigner, value: 0, data: configure(next)),
        ])
        return execute(Call(operation: 1, to: multiSend, value: 0, data: batch))
    }

    // MARK: - The user operation

    struct Op {
        var sender: String
        var nonce: UInt64
        var factory: String?
        var factoryData: [UInt8]
        var callData: [UInt8]
        var verificationGasLimit: UInt64 = 0
        var callGasLimit: UInt64 = 0
        var preVerificationGas: UInt64 = 0
        var maxFeePerGas: UInt64 = 0
        var maxPriorityFeePerGas: UInt64 = 0
        var signature: [UInt8] = []

        var json: [String: Any] {
            var o: [String: Any] = [
                "sender": sender, "nonce": quantity(nonce), "callData": hex(callData),
                "callGasLimit": quantity(callGasLimit), "verificationGasLimit": quantity(verificationGasLimit),
                "preVerificationGas": quantity(preVerificationGas), "maxFeePerGas": quantity(maxFeePerGas),
                "maxPriorityFeePerGas": quantity(maxPriorityFeePerGas), "signature": hex(signature),
            ]
            if let factory { o["factory"] = factory; o["factoryData"] = hex(factoryData) }
            return o
        }

        /// `PackedUserOperation`, ABI-encoded as the module's `getOperationHash` takes it.
        var packedTuple: [UInt8] {
            func u128pair(_ hi: UInt64, _ lo: UInt64) -> [UInt8] {
                Array(w(dec: String(hi)).suffix(16)) + Array(w(dec: String(lo)).suffix(16))
            }
            let initCode = factory.map { addressBytes($0) + factoryData } ?? []
            let tails = [initCode, callData, [], signature].map(dynamic)
            var offset = 9 * 32
            var offsets: [[UInt8]] = []
            for t in tails { offsets.append(w(offset)); offset += t.count }
            return w(sender) + w(dec: String(nonce)) + offsets[0] + offsets[1]
                + u128pair(verificationGasLimit, callGasLimit) + w(dec: String(preVerificationGas))
                + u128pair(maxPriorityFeePerGas, maxFeePerGas) + offsets[2] + offsets[3]
                + tails.reduce([], +)
        }
    }

    /// 12 bytes of no time bounds, then Safe's contract-signature envelope
    /// around the WebAuthn assertion.
    static func signature(r: [UInt8], s: [UInt8]) -> [UInt8] {
        let assertion = SafeWebAuthn.signatureBytes(r: r, s: s)!
        return [UInt8](repeating: 0, count: 12) + SafeWebAuthn.contractSignature(signer: sharedSigner, data: assertion)!
    }

    /// A signature the right shape and length that verifies nothing — for
    /// gas estimation, where a real one cannot exist yet (it signs the gas).
    static var dummySignature: [UInt8] {
        signature(r: [UInt8](repeating: 0x11, count: 32), s: [UInt8](repeating: 0x22, count: 32))
    }

    static func nonce(_ net: Chain.Network, _ sender: String) async throws -> UInt64 {
        let data = sel("getNonce(address,uint192)") + w(sender) + w(0)
        let hexWord = try await Chain.ethCall(net, to: entryPoint, data: hex(data))
        return UInt64(hexWord.suffix(16), radix: 16) ?? 0
    }

    static func operationHash(_ net: Chain.Network, _ op: Op) async throws -> [UInt8] {
        var bare = op
        bare.signature = [UInt8](repeating: 0, count: 12)
        let data = sel("getOperationHash((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes))") + w(32) + bare.packedTuple
        guard let bytes = SafeABI.hexBytes(try await Chain.ethCall(net, to: module4337, data: hex(data))), bytes.count == 32 else {
            throw Chain.RPCError(message: "module gave no hash")
        }
        return bytes
    }

    struct Prepared { var op: Op; let hash: [UInt8]; let notes: [String] }

    /// Build, estimate (with a balance override, so it needs no funds), price
    /// and hash an operation. Nothing is signed or sent here. `origin` is the
    /// key the account was created with: the address and the creation bytes
    /// come from it forever, whichever key signs now (a rotation changes the
    /// signer, never the address).
    static func prepare(_ net: Chain.Network, origin: Key, callData: [UInt8], log: (String) -> Void) async throws -> Prepared {
        let sender = try await address(net, origin)
        let deployed = try await Chain.codeExists(net, sender)
        var op = Op(sender: sender, nonce: deployed ? try await nonce(net, sender) : 0,
                    factory: deployed ? nil : proxyFactory, factoryData: deployed ? [] : factoryData(origin), callData: callData)
        op.signature = dummySignature
        // Fees first: estimation reads them for the prefund check.
        if let price = try? await Chain.bundler(net, "pimlico_getUserOperationGasPrice", []) as? [String: Any],
           let fast = price["fast"] as? [String: Any],
           let maxFee = (fast["maxFeePerGas"] as? String).flatMap({ UInt64($0.dropFirst(2), radix: 16) }),
           let tip = (fast["maxPriorityFeePerGas"] as? String).flatMap({ UInt64($0.dropFirst(2), radix: 16) }) {
            op.maxFeePerGas = maxFee; op.maxPriorityFeePerGas = tip
        } else {
            let gas = try await Chain.call(net.rpc, "eth_gasPrice", []) as? String ?? "0x0"
            let p = UInt64(gas.dropFirst(2), radix: 16) ?? 0
            op.maxFeePerGas = p * 2; op.maxPriorityFeePerGas = p
        }
        let override: [String: Any] = [sender: ["balance": "0xde0b6b3a7640000"]]
        let estimate = try await Chain.bundler(net, "eth_estimateUserOperationGas", [op.json, entryPoint, override]) as? [String: Any] ?? [:]
        func q(_ k: String) -> UInt64 { (estimate[k] as? String).flatMap { UInt64($0.dropFirst(2), radix: 16) } ?? 0 }
        // The dummy fails verification, so verification gas is the fallback
        // path's: an over-estimate, never short. A tenth more on each.
        op.verificationGasLimit = q("verificationGasLimit") * 11 / 10
        op.callGasLimit = q("callGasLimit") * 11 / 10
        op.preVerificationGas = q("preVerificationGas") * 11 / 10
        let hash = try await operationHash(net, op)
        let maxCost = (op.verificationGasLimit + op.callGasLimit + op.preVerificationGas) * op.maxFeePerGas
        let notes = [
            "account \(sender) · \(deployed ? "exists" : "not yet on chain: this operation creates it")",
            "gas: verification \(op.verificationGasLimit), call \(op.callGasLimit), pre \(op.preVerificationGas) · max \(Double(maxCost) / 1e18) ETH",
            "SafeOp hash \(hex(hash))",
        ]
        notes.forEach(log)
        return Prepared(op: op, hash: hash, notes: notes)
    }

    /// Sign the prepared operation with `key`, have the chain check the exact
    /// bytes first (the factory verifies a WebAuthn signature for a key with
    /// no contract deployed — the §913 rail), and return it signed.
    static func sign(_ net: Chain.Network, _ prepared: Prepared, with key: Key, log: (String) -> Void) async throws -> Op {
        guard let digest = SafeWebAuthn.signingDigest(challenge: prepared.hash) else { throw Chain.RPCError(message: "no digest") }
        let (r, s) = try await key.sign(digest)
        let assertion = SafeWebAuthn.signatureBytes(r: r, s: s)!
        let check = SafeWebAuthn.isValidSignatureForSignerCalldata(message: prepared.hash, signature: assertion, x: key.x, y: key.y)!
        let answer = try await Chain.ethCall(net, to: SafeWebAuthn.factory, data: check)
        log(SafeWebAuthn.isMagic(answer) ? "the signature verifies for the key that made it ✓ (whether the account answers to that key is the bundler's call)" : "the chain REFUSES this signature: \(answer)")
        var op = prepared.op
        op.signature = signature(r: r, s: s)
        return op
    }

    static func send(_ net: Chain.Network, _ op: Op, log: (String) -> Void) async throws -> String {
        guard let hash = try await Chain.bundler(net, "eth_sendUserOperation", [op.json, entryPoint]) as? String else {
            throw Chain.RPCError(message: "bundler returned no hash")
        }
        log("sent · \(hash)")
        for _ in 0..<45 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if let receipt = try? await Chain.bundler(net, "eth_getUserOperationReceipt", [hash]) as? [String: Any] {
                let ok = (receipt["success"] as? Bool) ?? false
                let tx = ((receipt["receipt"] as? [String: Any])?["transactionHash"] as? String) ?? "?"
                log(ok ? "mined ✓ · tx \(tx)" : "mined but FAILED · tx \(tx)")
                return tx
            }
        }
        throw Chain.RPCError(message: "no receipt after 90 s (hash \(hash))")
    }

    /// The shared signer's stored key for `account`: the chain's own word on
    /// which key the account now answers to.
    static func configuredKeyX(_ net: Chain.Network, account: String) async throws -> String {
        let data = sel("getConfiguration(address)") + w(account)
        let answer = try await Chain.ethCall(net, to: sharedSigner, data: hex(data))
        return String(answer.dropFirst(2).prefix(64))
    }
}
