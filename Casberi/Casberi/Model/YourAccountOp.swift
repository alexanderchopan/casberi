import Foundation

/// **YOUR ACCOUNT'S SEND (prd §1424) — the bytes.** A send is one ERC-4337
/// user operation through Safe's 4337 module: `executeUserOp`, and inside it
/// either the one payment or, through MultiSend as a delegate call, every
/// payment the person added and then the key change (the wallet spec,
/// section 3b): the shared signer re-configured to the next Enclave key in
/// the same transaction that pays, so a failed send rotates nothing.
///
/// Ported from `tools/safe-account-spike`, whose sends, rotations and the
/// old key's refusal were measured on an iPhone (2026-10-19). Foundation-only
/// and pure: the requests are `YourAccountChain`'s, the keys
/// `YourAccountKey`'s. `scripts/your-account-selftest.sh` pins these bytes.
enum YourAccountOp {

    // MARK: - Where it can send, and what

    struct Network: Equatable, Identifiable, Sendable {
        let name: String
        let chainId: Int
        /// Tried in order; the first answer wins.
        let rpcs: [String]
        /// ERC-4337 v0.7 bundlers, public and keyless, tried in order.
        let bundlers: [String]
        /// The network's dollar: USDC on Base and Ethereum.
        let dollar: String
        var dollarSymbol = "USDC"
        /// A test network: free money, offered in DEBUG builds only.
        let isTest: Bool
        var id: Int { chainId }
    }

    static let base = Network(
        name: "Base", chainId: 8453,
        rpcs: ["https://mainnet.base.org", "https://base-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/8453/rpc", "https://api.candide.dev/public/v3/8453"],
        dollar: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", isTest: false)
    static let ethereum = Network(
        name: "Ethereum", chainId: 1,
        rpcs: ["https://rpc.mevblocker.io", "https://ethereum-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/1/rpc", "https://api.candide.dev/public/v3/1"],
        dollar: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", isTest: false)
    /// Robinhood Chain, back with every feature (prd §1454, amending
    /// §1449): every contract the account and its spend limit use is there,
    /// Safe's adapter published at its own address (§1447 item 18); Pimlico's
    /// public bundler serves it, Candide's does not.
    static let robinhood = Network(
        name: "Robinhood", chainId: 4663, // one word in every sentence (prd §1479 item 4)
        rpcs: ["https://rpc.mainnet.chain.robinhood.com", "https://robinhood-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/4663/rpc"],
        dollar: "0x5fc5360d0400a0fd4f2af552add042d716f1d168", dollarSymbol: "USDG", isTest: false)
    /// The network behind one of this app's own chain names ("base-mainnet",
    /// the approvals' and receipts' spelling), when the account can act there.
    static func network(appName: String) -> Network? {
        switch appName {
        case "base-mainnet": base
        case "eth-mainnet": ethereum
        case "robinhood-mainnet": robinhood
        default: nil
        }
    }

    static let baseSepolia = Network(
        name: "Base Sepolia", chainId: 84532,
        rpcs: ["https://sepolia.base.org", "https://base-sepolia-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/84532/rpc", "https://api.candide.dev/public/v3/84532"],
        dollar: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", isTest: true)

    /// The account's networks, the same in every build: Base, Ethereum and
    /// Robinhood Chain (prd §1454), each with send, receive, swap, round-ups
    /// and the spend limit. Base Sepolia is in none, DEBUG included (prd
    /// §1441a, user: "we got rid of sepolia"); its constant stays for the
    /// dry-run probe alone.
    static let networks: [Network] = [base, ethereum, robinhood]

    #if DEBUG
    /// What the throwaway probes may name: the account's networks.
    static var probeNetworks: [Network] { networks }
    #endif

    struct Token: Equatable, Hashable, Sendable {
        let symbol: String
        let decimals: Int
        /// nil for the network's own coin.
        let contract: String?
    }

    static let eth = Token(symbol: "ETH", decimals: 18, contract: nil)
    /// The network's dollar, read off the chain with ETH every time.
    static func dollar(on network: Network) -> Token { Token(symbol: network.dollarSymbol, decimals: 6, contract: network.dollar) }
    static func tokens(on network: Network) -> [Token] { [eth, dollar(on: network)] }

    /// Which network a `Payment`'s chain is in this app's own spelling
    /// ("base-mainnet"), for reading the Wallet's last holdings.
    static func appName(_ network: Network) -> String? {
        switch network.chainId {
        case 8453: "base-mainnet"
        case 1: "eth-mainnet"
        case 4663: "robinhood-mainnet"
        case 84532: "base-sepolia"
        default: nil
        }
    }

    /// One payment: `amount` in the token's base units, as a decimal string.
    struct Payment: Equatable, Identifiable, Sendable {
        var id = UUID()
        let network: Network
        let token: Token
        let amount: String
        /// The checksummed address it goes to.
        let to: String
        /// What the person typed or picked, when it was a name.
        let toName: String?
    }

    // MARK: - Calldata

    typealias Call = YourAccount.Call
    private static func w(_ address: String) -> [UInt8] { YourAccount.w(address) }
    private static func w(_ n: Int) -> [UInt8] { YourAccount.w(n) }
    private static func amountWord(_ decimal: String) -> [UInt8]? { SafeABI.word(uint256: decimal) }

    /// `transfer(address,uint256)`.
    static func transfer(to: String, amount: String) -> [UInt8]? {
        guard let amount = amountWord(amount) else { return nil }
        return YourAccount.sel("transfer(address,uint256)") + w(to) + amount
    }

    /// The call a payment makes from the account.
    static func call(for payment: Payment) -> Call? {
        guard SafeABI.word(address: payment.to) != nil else { return nil }
        if let contract = payment.token.contract {
            guard let data = transfer(to: payment.to, amount: payment.amount) else { return nil }
            return Call(operation: 0, to: contract, value: w(0), data: data)
        }
        guard let value = amountWord(payment.amount) else { return nil }
        return Call(operation: 0, to: payment.to, value: value, data: [])
    }

    /// `executeUserOp(to, value, data, operation)`: the only call the module runs.
    static func execute(_ c: Call) -> [UInt8] {
        YourAccount.sel("executeUserOp(address,uint256,bytes,uint8)")
            + w(c.to) + c.value + w(128) + w(Int(c.operation)) + YourAccount.dynamic(c.data)
    }

    /// The operation's `callData`: every payment, then — when `next` is given
    /// — the shared signer moved to that key, all in one MultiSend.
    static func callData(_ payments: [Payment], rotateTo next: (x: [UInt8], y: [UInt8])?) -> [UInt8]? {
        let calls = payments.compactMap(call(for:))
        guard calls.count == payments.count, !calls.isEmpty else { return nil }
        return callData(calls: calls, rotateTo: next)
    }

    /// The contract an operation goes through (prd §1447 item 11).
    enum Entry: Equatable, Sendable {
        case module4337, adapter
        /// The SafeOp hash's EIP-712 domain: the validating contract itself.
        var verifyingContract: String {
            switch self {
            case .module4337: YourAccount.module4337
            case .adapter: YourAccount7579.adapter
            }
        }
    }

    /// Any calls, then the key change, as one operation; one call alone is a
    /// plain `executeUserOp` (a delegate call when its operation says so).
    /// On the adapter, the same batch through its `execute`: one delegatecall
    /// to MultiSend, mode `0xFF…` (v1's CALLTYPE_DELEGATECALL).
    static func callData(calls: [Call], rotateTo next: (x: [UInt8], y: [UInt8])?, entry: Entry = .module4337) -> [UInt8]? {
        guard !calls.isEmpty || next != nil else { return nil }
        if entry == .adapter {
            var batch = calls
            if let next {
                batch.append(Call(operation: 1, to: YourAccount.sharedSigner, value: w(0),
                                  data: YourAccount.configure(x: next.x, y: next.y)))
            }
            return adapterExecute(delegateTo: YourAccount.multiSend, data: YourAccount.multiSend(batch))
        }
        if next == nil, calls.count == 1 { return execute(calls[0]) }
        var batch = calls
        if let next {
            batch.append(Call(operation: 1, to: YourAccount.sharedSigner, value: w(0),
                              data: YourAccount.configure(x: next.x, y: next.y)))
        }
        return execute(Call(operation: 1, to: YourAccount.multiSend, value: w(0),
                            data: YourAccount.multiSend(batch)))
    }

    /// `createProxyWithNonce(singleton, initializer, saltNonce)`: the first
    /// send's creation of the account, from the key it was made with.
    static func factoryData(x: [UInt8], y: [UInt8], salt: Int = 0) -> [UInt8] {
        YourAccount.sel("createProxyWithNonce(address,bytes,uint256)")
            + w(YourAccount.safeL2) + w(96) + w(salt) + YourAccount.dynamic(YourAccount.initializer(x: x, y: y))
    }

    // MARK: - The user operation

    struct Op: Equatable {
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
        /// Which contract validates and runs it (prd §1447 item 11): Safe's
        /// 4337 module, or — once the account is on it — Safe's 7579 adapter.
        var entry: Entry = .module4337
        /// The nonce's 24-byte key, empty for key 0. On the adapter its first
        /// 20 bytes name the validator (prd §1447 item 14: Smart Sessions).
        var nonceKey: [UInt8] = []

        /// The nonce as the EntryPoint reads it: the key, then the sequence.
        var nonceWord: [UInt8] {
            let key = nonceKey.count == 24 ? nonceKey : [UInt8](repeating: 0, count: 24)
            return key + Array(SafeABI.word(uint256: String(nonce))!.suffix(8))
        }

        static func quantity(_ n: UInt64) -> String { "0x" + String(n, radix: 16) }
        static func quantity(word: [UInt8]) -> String {
            let hex = Keccak256.hexString(Array(word.drop { $0 == 0 }))
            let trimmed = hex.drop { $0 == "0" }
            return "0x" + (trimmed.isEmpty ? "0" : trimmed)
        }

        /// The bundler's JSON (EntryPoint v0.7's unpacked form).
        var json: [String: Any] {
            var o: [String: Any] = [
                "sender": sender, "nonce": Self.quantity(word: nonceWord), "callData": SafeABI.hex(callData),
                "callGasLimit": Self.quantity(callGasLimit),
                "verificationGasLimit": Self.quantity(verificationGasLimit),
                "preVerificationGas": Self.quantity(preVerificationGas),
                "maxFeePerGas": Self.quantity(maxFeePerGas),
                "maxPriorityFeePerGas": Self.quantity(maxPriorityFeePerGas),
                "signature": SafeABI.hex(signature),
            ]
            if let factory { o["factory"] = factory; o["factoryData"] = SafeABI.hex(factoryData) }
            return o
        }

        /// `PackedUserOperation`, ABI-encoded as the module's
        /// `getOperationHash` takes it.
        var packedTuple: [UInt8] {
            func word(_ n: UInt64) -> [UInt8] { SafeABI.word(uint256: String(n))! }
            func pair(_ hi: UInt64, _ lo: UInt64) -> [UInt8] { Array(word(hi).suffix(16)) + Array(word(lo).suffix(16)) }
            let initCode = factory.map { YourAccount.addressBytes($0) + factoryData } ?? []
            let tails = [initCode, callData, [], signature].map(YourAccount.dynamic)
            var offset = 9 * 32
            var offsets: [[UInt8]] = []
            for t in tails { offsets.append(YourAccount.w(offset)); offset += t.count }
            return YourAccount.w(sender) + nonceWord + offsets[0] + offsets[1]
                + pair(verificationGasLimit, callGasLimit) + word(preVerificationGas)
                + pair(maxPriorityFeePerGas, maxFeePerGas) + offsets[2] + offsets[3]
                + tails.reduce([], +)
        }

        /// The most it can cost in gas, in wei; nil if the numbers a bundler
        /// gave overflow, which is a refusal, never a trap.
        var maxCost: UInt64? {
            let (a, o1) = verificationGasLimit.addingReportingOverflow(callGasLimit)
            let (b, o2) = a.addingReportingOverflow(preVerificationGas)
            let (c, o3) = b.multipliedReportingOverflow(by: maxFeePerGas)
            return o1 || o2 || o3 ? nil : c
        }
    }

    // MARK: - The hashes, computed here

    private static func k(_ b: [UInt8]) -> [UInt8] { Keccak256.hash(b) }
    private static func u(_ n: UInt64) -> [UInt8] { SafeABI.word(uint256: String(n))! }
    private static func pair(_ hi: UInt64, _ lo: UInt64) -> [UInt8] { Array(u(hi).suffix(16)) + Array(u(lo).suffix(16)) }

    /// The SafeOp hash the shared signer is asked to sign — EIP-712 over the
    /// op's fields, Safe4337Module 0.3.0's own type, with no time bounds and
    /// no paymaster. Computed HERE so the bytes Face ID approves are never
    /// only a node's word: `YourAccountChain.send` refuses unless the
    /// module's `getOperationHash` agrees (`your-account-selftest.sh` pins it
    /// to Base's answer).
    static func safeOpHash(_ op: Op, chainId: Int) -> [UInt8] {
        let typeHash = k(Array("SafeOp(address safe,uint256 nonce,bytes initCode,bytes callData,uint128 verificationGasLimit,uint128 callGasLimit,uint256 preVerificationGas,uint128 maxPriorityFeePerGas,uint128 maxFeePerGas,bytes paymasterAndData,uint48 validAfter,uint48 validUntil,address entryPoint)".utf8))
        let domain = k(k(Array("EIP712Domain(uint256 chainId,address verifyingContract)".utf8))
                       + YourAccount.w(chainId) + YourAccount.w(op.entry.verifyingContract))
        let initCode = op.factory.map { YourAccount.addressBytes($0) + op.factoryData } ?? []
        let structHash = k(typeHash + YourAccount.w(op.sender) + op.nonceWord + k(initCode) + k(op.callData)
                           + u(op.verificationGasLimit) + u(op.callGasLimit) + u(op.preVerificationGas)
                           + u(op.maxPriorityFeePerGas) + u(op.maxFeePerGas) + k([]) + u(0) + u(0)
                           + YourAccount.w(YourAccount.entryPoint))
        return k([0x19, 0x01] + domain + structHash)
    }

    /// A big-endian word in decimal, for typed data's numbers.
    static func decimal(_ word: [UInt8]) -> String {
        var digits = word.drop { $0 == 0 }.map { UInt32($0) }
        var out: [Character] = []
        while !digits.isEmpty {
            var rest: UInt32 = 0
            var next: [UInt32] = []
            for d in digits {
                let cur = rest << 8 | d
                let q = cur / 10
                rest = cur % 10
                if !next.isEmpty || q != 0 { next.append(q) }
            }
            out.append(Character(String(rest)))
            digits = next
        }
        return out.isEmpty ? "0" : String(out.reversed())
    }

    /// The SafeOp as EIP-712 typed data — what the Signer's wallet is asked
    /// to sign with `eth_signTypedData_v4` (prd §1447 item 17), the same
    /// type, domain and fields `safeOpHash` hashes, so the wallet shows the
    /// person the operation and its digest is this phone's.
    static func safeOpTypedData(_ op: Op, chainId: Int) -> String? {
        func field(_ name: String, _ type: String) -> [String: String] { ["name": name, "type": type] }
        let initCode = op.factory.map { YourAccount.addressBytes($0) + op.factoryData } ?? []
        let typed: [String: Any] = [
            "types": [
                "EIP712Domain": [field("chainId", "uint256"), field("verifyingContract", "address")],
                "SafeOp": [field("safe", "address"), field("nonce", "uint256"), field("initCode", "bytes"),
                           field("callData", "bytes"), field("verificationGasLimit", "uint128"),
                           field("callGasLimit", "uint128"), field("preVerificationGas", "uint256"),
                           field("maxPriorityFeePerGas", "uint128"), field("maxFeePerGas", "uint128"),
                           field("paymasterAndData", "bytes"), field("validAfter", "uint48"),
                           field("validUntil", "uint48"), field("entryPoint", "address")],
            ],
            "primaryType": "SafeOp",
            "domain": ["chainId": chainId, "verifyingContract": op.entry.verifyingContract],
            "message": [
                "safe": op.sender, "nonce": decimal(op.nonceWord), "initCode": SafeABI.hex(initCode),
                "callData": SafeABI.hex(op.callData), "verificationGasLimit": String(op.verificationGasLimit),
                "callGasLimit": String(op.callGasLimit), "preVerificationGas": String(op.preVerificationGas),
                "maxPriorityFeePerGas": String(op.maxPriorityFeePerGas), "maxFeePerGas": String(op.maxFeePerGas),
                "paymasterAndData": "0x", "validAfter": "0", "validUntil": "0", "entryPoint": YourAccount.entryPoint,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: typed, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// EntryPoint v0.7's `getUserOpHash`: the id a bundler's receipt is
    /// asked by, known before the send so an unclear answer can still be
    /// followed to whether it landed.
    static func userOpHash(_ op: Op, chainId: Int) -> [UInt8] {
        let initCode = op.factory.map { YourAccount.addressBytes($0) + op.factoryData } ?? []
        let packed = YourAccount.w(op.sender) + op.nonceWord + k(initCode) + k(op.callData)
            + pair(op.verificationGasLimit, op.callGasLimit) + u(op.preVerificationGas)
            + pair(op.maxPriorityFeePerGas, op.maxFeePerGas) + k([])
        return k(k(packed) + YourAccount.w(YourAccount.entryPoint) + YourAccount.w(chainId))
    }

    /// The adapter's `execute(ModeCode, bytes)` as one delegatecall:
    /// mode byte 0 is the call type (0xFF), the rest zero (default exec);
    /// the calldata is the target's 20 bytes, then what it is called with.
    static func adapterExecute(delegateTo target: String, data: [UInt8]) -> [UInt8] {
        var mode = [UInt8](repeating: 0, count: 32)
        mode[0] = 0xFF
        return YourAccount.sel("execute(bytes32,bytes)") + mode + w(64)
            + YourAccount.dynamic(YourAccount.addressBytes(target) + data)
    }

    /// The adapter's `getSafeOp(userOp, entryPoint)` calldata, the op's
    /// signature cut to the 12 bytes of time bounds; the hash is the keccak
    /// of the `operationData` it answers.
    static func safeOpCall(_ op: Op) -> [UInt8] {
        var bare = op
        bare.signature = [UInt8](repeating: 0, count: 12)
        return YourAccount.sel("getSafeOp((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),address)")
            + w(64) + w(YourAccount.entryPoint) + bare.packedTuple
    }

    /// The first `bytes` of an ABI answer (`getSafeOp`'s `operationData`).
    static func firstBytes(_ answer: [UInt8]) -> [UInt8]? {
        guard answer.count >= 64 else { return nil }
        func int(_ at: Int) -> Int? {
            guard at + 32 <= answer.count, answer[at..<(at + 24)].allSatisfy({ $0 == 0 }) else { return nil }
            return answer[(at + 24)..<(at + 32)].reduce(0) { $0 << 8 | Int($1) }
        }
        guard let offset = int(0), let length = int(offset), offset + 32 + length <= answer.count else { return nil }
        return Array(answer[(offset + 32)..<(offset + 32 + length)])
    }

    /// `getOperationHash` calldata: the module hashes the op with its
    /// signature cut to the 12 bytes of time bounds.
    static func operationHashCall(_ op: Op) -> [UInt8] {
        var bare = op
        bare.signature = [UInt8](repeating: 0, count: 12)
        return YourAccount.sel("getOperationHash((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes))")
            + YourAccount.w(32) + bare.packedTuple
    }

    /// No time bounds (12 zero bytes), then Safe's contract-signature
    /// envelope around the WebAuthn assertion, under the shared signer.
    static func signature(r: [UInt8], s: [UInt8], owner: String = YourAccount.sharedSigner) -> [UInt8]? {
        guard let assertion = SafeWebAuthn.signatureBytes(r: r, s: s),
              let envelope = SafeWebAuthn.contractSignature(signer: owner, data: assertion) else { return nil }
        return [UInt8](repeating: 0, count: 12) + envelope
    }

    /// Both keys (prd §1447 item 16): the passkey's contract signature and
    /// the Signer's `r ‖ s ‖ v` over the same SafeOp hash, in Safe's order —
    /// static parts by owner, ascending, 65 bytes each, the passkey's
    /// assertion after them — behind the 12 bytes of no time bounds.
    static func bothSignatures(r: [UInt8], s: [UInt8], owner: String = YourAccount.sharedSigner,
                               signer: String, ecdsa: [UInt8]) -> [UInt8]? {
        guard ecdsa.count == 65, let assertion = SafeWebAuthn.signatureBytes(r: r, s: s) else { return nil }
        let passkeyFirst = YourAccount.w(owner).lexicographicallyPrecedes(YourAccount.w(signer))
        let passkeyStatic = YourAccount.w(owner) + YourAccount.w(130) + [0]
        let statics = passkeyFirst ? passkeyStatic + ecdsa : ecdsa + passkeyStatic
        return [UInt8](repeating: 0, count: 12) + statics + YourAccount.w(assertion.count) + assertion
    }

    /// The right shape and length, verifying nothing: for gas estimation,
    /// where a real signature cannot exist yet (it signs the gas).
    static var dummySignature: [UInt8] { dummySignature(owner: YourAccount.sharedSigner) }
    static func dummySignature(owner: String) -> [UInt8] {
        signature(r: [UInt8](repeating: 0x11, count: 32), s: [UInt8](repeating: 0x22, count: 32), owner: owner)!
    }

    // MARK: - The recovery key's calls (prd §1427)

    /// Deploy the recovery key's Safe passkey signer (idempotent: the
    /// factory returns the existing one) and make it an owner at threshold 1.
    /// `threshold` is the one the network already keeps (prd §1456): adding
    /// a key never lowers it — at 2 the spend limit stands.
    static func addRecoveryCalls(account: String, x: [UInt8], y: [UInt8], signer: String, threshold: Int = 1) -> [Call] {
        let create = YourAccount.sel("createSigner(uint256,uint256,uint176)") + x + y + SafeWebAuthn.verifiersWord!
        let add = YourAccount.sel("addOwnerWithThreshold(address,uint256)") + w(signer) + w(max(threshold, 1))
        return [Call(operation: 0, to: SafeWebAuthn.factory, value: w(0), data: create),
                Call(operation: 0, to: account, value: w(0), data: add)]
    }

    /// A key held outside Casberi (prd §1432): an address of the person's own
    /// — a Ledger, MetaMask — made an owner at threshold 1, so the account
    /// answers to it with no app of ours (Safe's own web app signs for it).
    static func addOwnerCall(account: String, owner: String, threshold: Int = 1) -> Call {
        Call(operation: 0, to: account, value: w(0),
             data: YourAccount.sel("addOwnerWithThreshold(address,uint256)") + w(owner) + w(max(threshold, 1)))
    }

    /// Safe's owners are a linked list: `removeOwner` names the owner before
    /// the one removed (the sentinel `0x…01` before the first, in
    /// `getOwners` order) and the threshold to keep. Nil when `owner` is not
    /// one, or removing it would leave fewer owners than the threshold.
    static func removeOwnerCall(account: String, owners: [String], owner: String, threshold: Int) -> Call? {
        guard let i = owners.firstIndex(where: { $0.caseInsensitiveCompare(owner) == .orderedSame }),
              owners.count - 1 >= max(threshold, 1) else { return nil }
        let previous = i == 0 ? "0x0000000000000000000000000000000000000001" : owners[i - 1]
        return Call(operation: 0, to: account, value: w(0),
                    data: YourAccount.sel("removeOwner(address,address,uint256)") + w(previous) + w(owner) + w(max(threshold, 1)))
    }

    /// Whether `code` (`eth_getCode`'s answer) is a contract's: anything but
    /// nothing, or an EIP-7702 delegation of a key-held wallet.
    static func isContractCode(_ code: String) -> Bool {
        let c = code.lowercased()
        if c.count <= 2 { return false }
        return !(c.hasPrefix("0xef0100") && c.count == 2 + 46)
    }

    /// Recovery itself: the shared signer moved to this phone's new key, by a
    /// delegate call the recovery key signs. The lost phone's key stops with it.
    static func recoverCall(to next: (x: [UInt8], y: [UInt8])) -> Call {
        Call(operation: 1, to: YourAccount.sharedSigner, value: w(0), data: YourAccount.configure(x: next.x, y: next.y))
    }

    // MARK: - Amounts, as decimal strings (uint256 has no Swift integer)

    /// "0.01" in a token of `decimals` → its base units, "10000000000000000".
    /// nil for anything that is not a plain positive amount, or that carries
    /// more decimals than the token has.
    static func baseUnits(_ text: String, decimals: Int) -> String? {
        let s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty, s.filter({ $0 == "." }).count <= 1,
              s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let whole = parts[0], fraction = parts.count > 1 ? parts[1] : ""
        guard fraction.count <= decimals, !(whole.isEmpty && fraction.isEmpty) else { return nil }
        let digits = (whole + fraction + String(repeating: "0", count: decimals - fraction.count))
            .drop { $0 == "0" }
        guard !digits.isEmpty else { return nil }
        return String(digits)
    }

    /// Base units → a readable amount, at most `places` decimals, trailing
    /// zeros cut, rounded DOWN (never shows more than is there).
    static func display(_ units: String, decimals: Int, places: Int = 6) -> String {
        let digits = units.drop { $0 == "0" }
        guard !digits.isEmpty else { return "0" }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let whole = String(padded.dropLast(decimals))
        var fraction = String(padded.suffix(decimals).prefix(places))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return fraction.isEmpty ? whole : whole + "." + fraction
    }

    /// The amount as the slab and Face ID say it: six places, or, when those
    /// read "0" for a real amount, three significant digits of it
    /// ("0.000000314 ETH", never eighteen places).
    static func spoken(_ units: String, decimals: Int) -> String {
        let six = display(units, decimals: decimals)
        guard six == "0", units.contains(where: { $0 != "0" }) else { return six }
        let whole = display(units, decimals: decimals, places: decimals)
        guard let dot = whole.firstIndex(of: "."),
              let first = whole[dot...].firstIndex(where: { $0 != "0" && $0 != "." }) else { return whole }
        let places = whole.distance(from: whole.index(after: dot), to: first) + 3
        return display(units, decimals: decimals, places: places)
    }

    /// a ≤ b, both decimal strings of base units.
    static func atMost(_ a: String, _ b: String) -> Bool {
        let x = String(a.drop { $0 == "0" }), y = String(b.drop { $0 == "0" })
        return x.count != y.count ? x.count < y.count : x <= y
    }

    /// a + b, both decimal strings.
    static func sum(_ a: String, _ b: String) -> String {
        var out: [Character] = []
        var carry = 0
        let x = Array(a.reversed()), y = Array(b.reversed())
        for i in 0..<max(x.count, y.count) {
            let d = (i < x.count ? Int(String(x[i]))! : 0) + (i < y.count ? Int(String(y[i]))! : 0) + carry
            out.append(Character(String(d % 10)))
            carry = d / 10
        }
        if carry > 0 { out.append(Character(String(carry))) }
        let s = String(out.reversed()).drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }

    /// A `0x` quantity → its decimal string.
    static func decimal(hexQuantity hex: String) -> String? {
        guard let word = SafeABI.word(uint256: hex) else { return nil }
        return SafeCalldata.decimal(word)
    }

    // MARK: - The sentence's arithmetic (prd §1438)

    /// a − b, both decimal strings; "0" when b is the larger (what is left
    /// of a holding once the transaction's earlier lines are taken from it).
    static func difference(_ a: String, _ b: String) -> String {
        guard !atMost(a, b) else { return "0" }
        var out: [Character] = []
        var borrow = 0
        let x = Array(a.reversed()), y = Array(b.reversed())
        for i in 0..<x.count {
            var d = Int(String(x[i]))! - (i < y.count ? Int(String(y[i]))! : 0) - borrow
            borrow = d < 0 ? 1 : 0
            if d < 0 { d += 10 }
            out.append(Character(String(d)))
        }
        let s = String(out.reversed()).drop { $0 == "0" }
        return s.isEmpty ? "0" : String(s)
    }

    /// `percent` of `units`, rounded down: the slider's quarter, half, all.
    static func share(_ units: String, percent: Int) -> String {
        let p = min(max(percent, 0), 100)
        guard p < 100 else { return units.drop { $0 == "0" }.isEmpty ? "0" : String(units.drop { $0 == "0" }) }
        // units × p, then ÷ 100, by long arithmetic.
        var product: [Int] = []
        var carry = 0
        for c in units.reversed() {
            let v = Int(String(c))! * p + carry
            product.append(v % 10)
            carry = v / 10
        }
        while carry > 0 { product.append(carry % 10); carry /= 10 }
        let digits = String(product.reversed().map { Character(String($0)) }).drop { $0 == "0" }
        guard digits.count > 2 else { return "0" }
        return String(digits.dropLast(2))
    }

    /// Dollars typed in the sentence → the token's base units at `price`
    /// dollars a whole token, rounded down. nil for anything not an amount.
    static func baseUnits(dollars text: String, price: Double, decimals: Int) -> String? {
        let s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard price > 0, let usd = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")), usd > 0 else { return nil }
        var tokens = usd / Decimal(price)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &tokens, min(decimals, 18), .down)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        return baseUnits(text, decimals: decimals)
    }

    /// Base units → dollars at `price` a whole token.
    static func dollars(_ units: String, decimals: Int, price: Double) -> Double {
        (Double(display(units, decimals: decimals, places: min(decimals, 12))) ?? 0) * price
    }

    /// An ERC-20 `symbol()` answer: an ABI string, or the bytes32 some old
    /// tokens return. nil for anything else, or a symbol no one could read.
    static func abiString(_ hex: String) -> String? {
        guard let bytes = SafeABI.hexBytes(hex), !bytes.isEmpty else { return nil }
        var raw: [UInt8]
        if bytes.count >= 96, bytes[0..<31].allSatisfy({ $0 == 0 }), bytes[31] == 32 {
            let length = bytes[32..<64].reduce(0) { $0 * 256 + Int($1) }
            guard length > 0, length <= 64, bytes.count >= 64 + length else { return nil }
            raw = Array(bytes[64..<(64 + length)])
        } else if bytes.count == 32 {
            raw = Array(bytes.prefix { $0 != 0 })
        } else {
            return nil
        }
        guard let s = String(bytes: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s.count <= 16, !s.contains(where: \.isNewline) else { return nil }
        return s
    }
}
