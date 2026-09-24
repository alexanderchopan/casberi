import Foundation

/// A recovery GUARDIAN's arithmetic — Candide's `SocialRecoveryModule`
/// (prd §913). Foundation-only and pure; `scripts/safe-signer-selftest.sh`
/// compiles it whole, and both type hashes are asserted equal to the
/// constants the module's own source publishes.
///
/// **What a guardian signs.** `ExecuteRecovery(address wallet,address[]
/// newOwners,uint256 newThreshold,uint256 nonce)` under the module's EIP-712
/// domain — which, unlike a Safe's, carries a `name` and a `version`. The
/// signature approves ONE owner set for ONE wallet at ONE nonce; the module
/// collects a threshold of guardians, waits out its delay (during which any
/// current owner can cancel), and only then swaps the owners. A guardian's
/// key can do nothing else to the wallet: it cannot spend, cannot execute,
/// and its approval means nothing until the module's own count is met.
///
/// **No address table.** The module is named by the request (its typed
/// data's `verifyingContract`), and `SafeRecoverySigner` then READS that
/// contract: its `NAME()` must be the module's, the wallet must list it as
/// an enabled module, and the wallet must list this phone as a guardian.
/// `getRecoveryHash` on the module is the rail — the same "never sign a
/// hash we computed alone" §425 rests on.
enum SafeRecovery {

    static let moduleName = "Social Recovery Module"

    static let domainTypeString =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    static let executeRecoveryTypeString =
        "ExecuteRecovery(address wallet,address[] newOwners,uint256 newThreshold,uint256 nonce)"

    static var domainTypeHash: [UInt8] { Keccak256.hash(Array(domainTypeString.utf8)) }
    static var executeRecoveryTypeHash: [UInt8] { Keccak256.hash(Array(executeRecoveryTypeString.utf8)) }

    /// One recovery approval, as the request carries it.
    struct Request: Equatable {
        let chainId: Int
        let module: String
        let wallet: String
        let newOwners: [String]
        let newThreshold: Int
        let nonce: Int
        /// The domain's own words — read back from the module before signing.
        let name: String
        let version: String
    }

    // MARK: - The hash

    static func domainSeparator(_ r: Request) -> [UInt8]? {
        guard let chainId = SafeABI.word(uint: r.chainId),
              let module = SafeABI.word(address: r.module)
        else { return nil }
        return Keccak256.hash(domainTypeHash + Keccak256.hash(Array(r.name.utf8))
                              + Keccak256.hash(Array(r.version.utf8)) + chainId + module)
    }

    /// `keccak256(abi.encodePacked(newOwners))` — `encodePacked` pads each
    /// array element to a full word, so this is the concatenation of
    /// address words, which is also EIP-712's encoding of `address[]`.
    static func ownersHash(_ owners: [String]) -> [UInt8]? {
        var packed: [UInt8] = []
        for owner in owners {
            guard let word = SafeABI.word(address: owner) else { return nil }
            packed += word
        }
        return Keccak256.hash(packed)
    }

    static func structHash(_ r: Request) -> [UInt8]? {
        guard !r.newOwners.isEmpty, r.newThreshold >= 1, r.newThreshold <= r.newOwners.count,
              let wallet = SafeABI.word(address: r.wallet),
              let owners = ownersHash(r.newOwners),
              let threshold = SafeABI.word(uint: r.newThreshold),
              let nonce = SafeABI.word(uint: r.nonce)
        else { return nil }
        return Keccak256.hash(executeRecoveryTypeHash + wallet + owners + threshold + nonce)
    }

    /// `getRecoveryHash(wallet, newOwners, newThreshold, nonce)`, locally.
    static func recoveryHash(_ r: Request) -> [UInt8]? {
        guard let domain = domainSeparator(r), let body = structHash(r) else { return nil }
        return Keccak256.hash([0x19, 0x01] + domain + body)
    }

    // MARK: - The typed-data door

    /// The request out of an `eth_signTypedData_v4` envelope, or nil when the
    /// envelope is not an `ExecuteRecovery` in this module's domain.
    static func request(from typed: EIP712.TypedData) -> Request? {
        guard typed.primaryType == "ExecuteRecovery",
              typed.domainName == moduleName,
              let version = typed.domainVersion,
              let chainId = typed.chainId,
              let module = typed.verifyingContract,
              let fields = typed.types["ExecuteRecovery"],
              fields == [EIP712.Field(name: "wallet", type: "address"),
                         EIP712.Field(name: "newOwners", type: "address[]"),
                         EIP712.Field(name: "newThreshold", type: "uint256"),
                         EIP712.Field(name: "nonce", type: "uint256")],
              let wallet = typed.message["wallet"]?.string,
              let ownersRaw = typed.message["newOwners"]?.array,
              let threshold = typed.message["newThreshold"].flatMap(EIP712.int),
              let nonce = typed.message["nonce"].flatMap(EIP712.int)
        else { return nil }
        var owners: [String] = []
        for item in ownersRaw {
            guard let s = item.string, SafeABI.word(address: s) != nil else { return nil }
            owners.append(s)
        }
        guard SafeABI.word(address: wallet) != nil, SafeABI.word(address: module) != nil else { return nil }
        return Request(chainId: chainId, module: module, wallet: wallet, newOwners: owners,
                       newThreshold: threshold, nonce: nonce, name: moduleName, version: version)
    }

    // MARK: - Calldata for the reads

    static var nameSelector: String { SafeCalldata.selector("NAME()") }
    static var versionSelector: String { SafeCalldata.selector("VERSION()") }

    static func getRecoveryHashCalldata(_ r: Request) -> String? {
        guard let selector = SafeABI.hexBytes(SafeCalldata.selector("getRecoveryHash(address,address[],uint256,uint256)")),
              let wallet = SafeABI.word(address: r.wallet),
              let offset = SafeABI.word(uint: 4 * 32),
              let threshold = SafeABI.word(uint: r.newThreshold),
              let nonce = SafeABI.word(uint: r.nonce),
              let count = SafeABI.word(uint: r.newOwners.count)
        else { return nil }
        var tail = count
        for owner in r.newOwners {
            guard let word = SafeABI.word(address: owner) else { return nil }
            tail += word
        }
        return SafeABI.hex(selector + wallet + offset + threshold + nonce + tail)
    }

    static func isGuardianCalldata(wallet: String, guardian: String) -> String? {
        twoAddresses("isGuardian(address,address)", wallet, guardian)
    }

    static func thresholdCalldata(wallet: String) -> String? { oneAddress("threshold(address)", wallet) }
    static func guardiansCountCalldata(wallet: String) -> String? { oneAddress("guardiansCount(address)", wallet) }
    static func nonceCalldata(wallet: String) -> String? { oneAddress("nonce(address)", wallet) }
    static func getRecoveryRequestCalldata(wallet: String) -> String? { oneAddress("getRecoveryRequest(address)", wallet) }
    /// Asked of the WALLET, about the module.
    static func isModuleEnabledCalldata(module: String) -> String? { oneAddress("isModuleEnabled(address)", module) }

    private static func oneAddress(_ signature: String, _ a: String) -> String? {
        guard let selector = SafeABI.hexBytes(SafeCalldata.selector(signature)),
              let word = SafeABI.word(address: a) else { return nil }
        return SafeABI.hex(selector + word)
    }

    private static func twoAddresses(_ signature: String, _ a: String, _ b: String) -> String? {
        guard let selector = SafeABI.hexBytes(SafeCalldata.selector(signature)),
              let first = SafeABI.word(address: a), let second = SafeABI.word(address: b) else { return nil }
        return SafeABI.hex(selector + first + second)
    }

    // MARK: - Decoding the answers

    /// A `string` return: one word of offset, one of length, then the bytes.
    static func decodeString(_ hex: String) -> String? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count >= 64,
              let offset = SafeCalldata.smallInt(Array(bytes[0..<32])), offset + 32 <= bytes.count,
              let length = SafeCalldata.smallInt(Array(bytes[offset..<offset + 32])),
              offset + 32 + length <= bytes.count
        else { return nil }
        return String(decoding: bytes[(offset + 32)..<(offset + 32 + length)], as: UTF8.self)
    }

    static func decodeBool(_ hex: String) -> Bool? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count == 32,
              bytes.prefix(31).allSatisfy({ $0 == 0 }), bytes[31] <= 1 else { return nil }
        return bytes[31] == 1
    }

    /// `getRecoveryRequest`'s tuple: `(guardiansApprovalCount, newThreshold,
    /// nonce, executableAt, newOwners[])`. Only the two facts the sheet
    /// states are read; `executableAt == 0` means no recovery is pending.
    struct PendingRecovery: Equatable {
        let approvals: Int
        let executableAt: Int
    }

    static func decodeRecoveryRequest(_ hex: String) -> PendingRecovery? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count >= 32 * 6,
              let offset = SafeCalldata.smallInt(Array(bytes[0..<32])), offset == 32,
              let approvals = SafeCalldata.smallInt(Array(bytes[32..<64])),
              let executableAt = SafeCalldata.smallInt(Array(bytes[128..<160]))
        else { return nil }
        return PendingRecovery(approvals: approvals, executableAt: executableAt)
    }
}

extension SafeCalldata {
    /// A word as a small non-negative Int, nil when it does not fit — the
    /// same refusal `decodeUInt` makes, exposed for the tuple readers above.
    static func smallInt(_ word: [UInt8]) -> Int? {
        guard word.count == 32, word.prefix(24).allSatisfy({ $0 == 0 }) else { return nil }
        var out = 0
        for byte in word.suffix(8) { out = (out << 8) | Int(byte) }
        return out >= 0 ? out : nil
    }
}
