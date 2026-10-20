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
        let usdc: String
        /// A test network: free money, offered in DEBUG builds only.
        let isTest: Bool
        var id: Int { chainId }
    }

    static let base = Network(
        name: "Base", chainId: 8453,
        rpcs: ["https://mainnet.base.org", "https://base-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/8453/rpc", "https://api.candide.dev/public/v3/8453"],
        usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", isTest: false)
    static let ethereum = Network(
        name: "Ethereum", chainId: 1,
        rpcs: ["https://rpc.mevblocker.io", "https://ethereum-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/1/rpc", "https://api.candide.dev/public/v3/1"],
        usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", isTest: false)
    /// The network behind one of this app's own chain names ("base-mainnet",
    /// the approvals' and receipts' spelling), when the account can act there.
    static func network(appName: String) -> Network? {
        switch appName {
        case "base-mainnet": base
        case "eth-mainnet": ethereum
        default: nil
        }
    }

    static let baseSepolia = Network(
        name: "Base Sepolia", chainId: 84532,
        rpcs: ["https://sepolia.base.org", "https://base-sepolia-rpc.publicnode.com"],
        bundlers: ["https://public.pimlico.io/v2/84532/rpc", "https://api.candide.dev/public/v3/84532"],
        usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", isTest: true)

    /// Two live networks, Base and Ethereum, and one test network, Base
    /// Sepolia, in every build (prd §1439, amends §1435 item 2): a send can be
    /// tried with a faucet's coins, which carry no value, and the sentence
    /// says "test network" wherever Base Sepolia is picked.
    static let networks: [Network] = [base, ethereum, baseSepolia]

    struct Token: Equatable, Hashable, Sendable {
        let symbol: String
        let decimals: Int
        /// nil for the network's own coin.
        let contract: String?
    }

    static let eth = Token(symbol: "ETH", decimals: 18, contract: nil)
    static func usdc(on network: Network) -> Token { Token(symbol: "USDC", decimals: 6, contract: network.usdc) }
    static func tokens(on network: Network) -> [Token] { [eth, usdc(on: network)] }

    /// Which network a `Payment`'s chain is in this app's own spelling
    /// ("base-mainnet"), for reading the Wallet's last holdings.
    static func appName(_ network: Network) -> String? {
        switch network.chainId {
        case 8453: "base-mainnet"
        case 1: "eth-mainnet"
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

    /// Any calls, then the key change, as one operation; one call alone is a
    /// plain `executeUserOp` (a delegate call when its operation says so).
    static func callData(calls: [Call], rotateTo next: (x: [UInt8], y: [UInt8])?) -> [UInt8]? {
        guard !calls.isEmpty || next != nil else { return nil }
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

        static func quantity(_ n: UInt64) -> String { "0x" + String(n, radix: 16) }

        /// The bundler's JSON (EntryPoint v0.7's unpacked form).
        var json: [String: Any] {
            var o: [String: Any] = [
                "sender": sender, "nonce": Self.quantity(nonce), "callData": SafeABI.hex(callData),
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
            return YourAccount.w(sender) + word(nonce) + offsets[0] + offsets[1]
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
                       + YourAccount.w(chainId) + YourAccount.w(YourAccount.module4337))
        let initCode = op.factory.map { YourAccount.addressBytes($0) + op.factoryData } ?? []
        let structHash = k(typeHash + YourAccount.w(op.sender) + u(op.nonce) + k(initCode) + k(op.callData)
                           + u(op.verificationGasLimit) + u(op.callGasLimit) + u(op.preVerificationGas)
                           + u(op.maxPriorityFeePerGas) + u(op.maxFeePerGas) + k([]) + u(0) + u(0)
                           + YourAccount.w(YourAccount.entryPoint))
        return k([0x19, 0x01] + domain + structHash)
    }

    /// EntryPoint v0.7's `getUserOpHash`: the id a bundler's receipt is
    /// asked by, known before the send so an unclear answer can still be
    /// followed to whether it landed.
    static func userOpHash(_ op: Op, chainId: Int) -> [UInt8] {
        let initCode = op.factory.map { YourAccount.addressBytes($0) + op.factoryData } ?? []
        let packed = YourAccount.w(op.sender) + u(op.nonce) + k(initCode) + k(op.callData)
            + pair(op.verificationGasLimit, op.callGasLimit) + u(op.preVerificationGas)
            + pair(op.maxPriorityFeePerGas, op.maxFeePerGas) + k([])
        return k(k(packed) + YourAccount.w(YourAccount.entryPoint) + YourAccount.w(chainId))
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

    /// The right shape and length, verifying nothing: for gas estimation,
    /// where a real signature cannot exist yet (it signs the gas).
    static var dummySignature: [UInt8] { dummySignature(owner: YourAccount.sharedSigner) }
    static func dummySignature(owner: String) -> [UInt8] {
        signature(r: [UInt8](repeating: 0x11, count: 32), s: [UInt8](repeating: 0x22, count: 32), owner: owner)!
    }

    // MARK: - The recovery key's calls (prd §1427)

    /// Deploy the recovery key's Safe passkey signer (idempotent: the
    /// factory returns the existing one) and make it an owner at threshold 1.
    static func addRecoveryCalls(account: String, x: [UInt8], y: [UInt8], signer: String) -> [Call] {
        let create = YourAccount.sel("createSigner(uint256,uint256,uint176)") + x + y + SafeWebAuthn.verifiersWord!
        let add = YourAccount.sel("addOwnerWithThreshold(address,uint256)") + w(signer) + w(1)
        return [Call(operation: 0, to: SafeWebAuthn.factory, value: w(0), data: create),
                Call(operation: 0, to: account, value: w(0), data: add)]
    }

    /// A key held outside Casberi (prd §1432): an address of the person's own
    /// — a Ledger, MetaMask — made an owner at threshold 1, so the account
    /// answers to it with no app of ours (Safe's own web app signs for it).
    static func addOwnerCall(account: String, owner: String) -> Call {
        Call(operation: 0, to: account, value: w(0),
             data: YourAccount.sel("addOwnerWithThreshold(address,uint256)") + w(owner) + w(1))
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
