import Foundation

/// EIP-712 in general, and the three shapes a Safe owner is asked to sign
/// (prd §913). Foundation-only and pure, compiled WHOLE by
/// `scripts/safe-signer-selftest.sh` and pinned to the vectors
/// `scripts/support/safe-signer-vectors.py` derives — the spec's own "Ether
/// Mail" digest first, so the encoder is trusted before it is trusted with
/// anything.
///
/// **Why a general encoder exists beside `SafeTxEncoder`.** §425's signer
/// took a SafeTx apart field by field and hashed it with a hand-written
/// preimage, and that is still what signs a transaction. But a request that
/// arrives over WalletConnect is typed data — types, a domain, a message —
/// and the requester expects the digest of exactly that structure. The three
/// structures this app signs (SafeTx, SafeMessage, ExecuteRecovery) are each
/// re-hashed by their own specific encoder and checked against the chain;
/// this general one is what REPRODUCES the requester's hash so the two can
/// be compared, and what hashes the inner typed data of a Safe message (a
/// Snapshot vote's `Vote` struct) where no specific encoder could exist.
///
/// **What it refuses.** A negative integer (no signed field exists in any
/// structure this app signs), a value wider than its type, a type the spec
/// does not define, a struct whose field is missing. Every refusal is nil,
/// never a zero word — a zero word is a valid encoding of a different value.
enum EIP712 {

    struct Field: Equatable {
        let name: String
        let type: String
    }

    /// One typed-data envelope, as `eth_signTypedData_v4` carries it.
    struct TypedData: Equatable {
        let types: [String: [Field]]
        let primaryType: String
        let domain: [String: Value]
        let message: [String: Value]

        var chainId: Int? { domain["chainId"].flatMap(EIP712.int) }
        var verifyingContract: String? { domain["verifyingContract"]?.string }
        var domainName: String? { domain["name"]?.string }
        var domainVersion: String? { domain["version"]?.string }
    }

    /// A JSON value that can be compared — `Any` cannot be `Equatable`, and a
    /// typed-data envelope is compared in the harness and in the peer's
    /// pending-ask state.
    indirect enum Value: Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case array([Value])
        case object([String: Value])

        var string: String? { if case .string(let s) = self { return s }; return nil }
        var array: [Value]? { if case .array(let a) = self { return a }; return nil }
        var object: [String: Value]? { if case .object(let o) = self { return o }; return nil }

        static func from(_ any: Any) -> Value? {
            switch any {
            case let s as String: return .string(s)
            case let b as Bool: return .bool(b)
            case let n as NSNumber:
                // A JSON `true` decodes as an NSNumber on Darwin; the Bool
                // case above catches it first there, and this keeps Linux
                // (where JSON bools are plain Bool) on the same path.
                return .number(n.doubleValue)
            case let i as Int: return .number(Double(i))
            case let d as Double: return .number(d)
            case is NSNull: return .null
            case let a as [Any]:
                var out: [Value] = []
                for item in a { guard let v = from(item) else { return nil }; out.append(v) }
                return .array(out)
            case let o as [String: Any]:
                var out: [String: Value] = [:]
                for (k, v) in o { guard let value = from(v) else { return nil }; out[k] = value }
                return .object(out)
            default: return nil
            }
        }
    }

    // MARK: - Parsing

    /// The envelope from a JSON string or an already-decoded object. Nil for
    /// anything missing its four parts or carrying a type table this cannot
    /// read.
    static func parse(_ any: Any) -> TypedData? {
        var root: Any = any
        if let text = any as? String {
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data)
            else { return nil }
            root = decoded
        }
        guard let dict = root as? [String: Any],
              let typesRaw = dict["types"] as? [String: Any],
              let primaryType = dict["primaryType"] as? String,
              let domainRaw = dict["domain"] as? [String: Any],
              let messageRaw = dict["message"] as? [String: Any]
        else { return nil }
        var types: [String: [Field]] = [:]
        for (name, list) in typesRaw {
            guard let fields = list as? [[String: Any]] else { return nil }
            var out: [Field] = []
            for f in fields {
                guard let n = f["name"] as? String, let t = f["type"] as? String else { return nil }
                out.append(Field(name: n, type: t))
            }
            types[name] = out
        }
        guard let domain = Value.from(domainRaw)?.object,
              let message = Value.from(messageRaw)?.object
        else { return nil }
        return TypedData(types: types, primaryType: primaryType, domain: domain, message: message)
    }

    // MARK: - encodeType

    /// The primary type first, then every dependency once, alphabetically —
    /// the spec's rule, and the one the "Ether Mail" vector proves.
    static func encodeType(_ primary: String, types: [String: [Field]]) -> String? {
        guard types[primary] != nil else { return nil }
        var deps: [String] = []
        collectDependencies(primary, types: types, into: &deps)
        let ordered = [primary] + deps.filter { $0 != primary }.sorted()
        return ordered.map { name in
            name + "(" + (types[name] ?? []).map { "\($0.type) \($0.name)" }.joined(separator: ",") + ")"
        }.joined()
    }

    private static func collectDependencies(_ name: String, types: [String: [Field]], into found: inout [String]) {
        guard !found.contains(name), let fields = types[name] else { return }
        found.append(name)
        for field in fields {
            let base = baseType(field.type)
            if types[base] != nil { collectDependencies(base, types: types, into: &found) }
        }
    }

    static func typeHash(_ primary: String, types: [String: [Field]]) -> [UInt8]? {
        guard let encoded = encodeType(primary, types: types) else { return nil }
        return Keccak256.hash(Array(encoded.utf8))
    }

    // MARK: - encodeData

    /// `bytes32` for one value of one type: the word itself for an atomic
    /// type, the keccak for a dynamic one, an array or a struct.
    static func encodeValue(type: String, value: Value, types: [String: [Field]]) -> [UInt8]? {
        if let (inner, count) = arrayType(type) {
            guard let items = value.array else { return nil }
            if let count, items.count != count { return nil }
            var body: [UInt8] = []
            for item in items {
                guard let word = encodeValue(type: inner, value: item, types: types) else { return nil }
                body += word
            }
            return Keccak256.hash(body)
        }
        if types[type] != nil {
            guard let object = value.object else { return nil }
            return hashStruct(type, data: object, types: types)
        }
        switch type {
        case "string":
            guard let s = value.string else { return nil }
            return Keccak256.hash(Array(s.utf8))
        case "bytes":
            guard let s = value.string, let bytes = SafeABI.hexBytes(s) else { return nil }
            return Keccak256.hash(bytes)
        case "address":
            guard let s = value.string else { return nil }
            return SafeABI.word(address: s)
        case "bool":
            switch value {
            case .bool(let b): return SafeABI.word(uint: b ? 1 : 0)
            case .number(let n) where n == 0 || n == 1: return SafeABI.word(uint: Int(n))
            default: return nil
            }
        default: break
        }
        if type.hasPrefix("bytes"), let n = Int(type.dropFirst(5)), (1...32).contains(n) {
            guard let s = value.string, let raw = SafeABI.hexBytes(s), raw.count == n else { return nil }
            return raw + [UInt8](repeating: 0, count: 32 - n)
        }
        if type.hasPrefix("uint") || type.hasPrefix("int") {
            let digits = type.hasPrefix("uint") ? type.dropFirst(4) : type.dropFirst(3)
            let width = digits.isEmpty ? 256 : (Int(digits) ?? 0)
            guard width > 0, width <= 256, width % 8 == 0 else { return nil }
            guard let text = numberText(value), let word = SafeABI.word(uint256: text) else { return nil }
            // A value wider than its declared type is a different value.
            let bits = 256 - width
            if bits > 0 {
                let fullBytes = bits / 8
                guard word.prefix(fullBytes).allSatisfy({ $0 == 0 }) else { return nil }
            }
            return word
        }
        return nil
    }

    static func hashStruct(_ name: String, data: [String: Value], types: [String: [Field]]) -> [UInt8]? {
        guard let fields = types[name], let head = typeHash(name, types: types) else { return nil }
        var body = head
        for field in fields {
            guard let value = data[field.name],
                  let word = encodeValue(type: field.type, value: value, types: types)
            else { return nil }
            body += word
        }
        return Keccak256.hash(body)
    }

    // MARK: - The digest

    /// `EIP712Domain` fields in the spec's canonical order, taken from the
    /// envelope's own type table when it carries one and from the keys the
    /// domain object presents when it does not — which is how the SafeTx and
    /// SafeMessage domains (`chainId`, `verifyingContract`, nothing else)
    /// and Snapshot's (`name`, `version`, nothing else) both hash right.
    static func domainFields(_ td: TypedData) -> [Field] {
        if let declared = td.types["EIP712Domain"] { return declared }
        let order: [(String, String)] = [("name", "string"), ("version", "string"),
                                         ("chainId", "uint256"),
                                         ("verifyingContract", "address"), ("salt", "bytes32")]
        return order.filter { td.domain[$0.0] != nil }.map { Field(name: $0.0, type: $0.1) }
    }

    static func domainSeparator(_ td: TypedData) -> [UInt8]? {
        var types = td.types
        types["EIP712Domain"] = domainFields(td)
        return hashStruct("EIP712Domain", data: td.domain, types: types)
    }

    /// `keccak256(0x19 ‖ 0x01 ‖ domainSeparator ‖ hashStruct(message))`.
    static func digest(_ td: TypedData) -> [UInt8]? {
        guard let ds = domainSeparator(td),
              let sh = hashStruct(td.primaryType, data: td.message, types: td.types)
        else { return nil }
        return Keccak256.hash([0x19, 0x01] + ds + sh)
    }

    // MARK: - Type grammar

    /// `address[]` → (`address`, nil); `uint32[3]` → (`uint32`, 3); a scalar → nil.
    static func arrayType(_ type: String) -> (String, Int?)? {
        guard type.hasSuffix("]"), let open = type.lastIndex(of: "[") else { return nil }
        let inner = String(type[type.startIndex..<open])
        let countText = type[type.index(after: open)..<type.index(before: type.endIndex)]
        guard !inner.isEmpty else { return nil }
        if countText.isEmpty { return (inner, nil) }
        guard let n = Int(countText), n >= 0 else { return nil }
        return (inner, n)
    }

    static func baseType(_ type: String) -> String {
        var t = type
        while let (inner, _) = arrayType(t) { t = inner }
        return t
    }

    /// A number as JSON carries it — `7`, `"7"`, `"0x7"`, or a double that
    /// is really an integer. A fractional double is not a uint.
    static func numberText(_ value: Value) -> String? {
        switch value {
        case .string(let s): return s
        case .number(let d):
            guard d >= 0, d == d.rounded(), d < 9_007_199_254_740_992 else { return nil }
            return String(Int64(d))
        case .bool(let b): return b ? "1" : "0"
        default: return nil
        }
    }

    static func int(_ value: Value) -> Int? {
        guard let text = numberText(value) else { return nil }
        if text.lowercased().hasPrefix("0x") { return Int(text.dropFirst(2), radix: 16) }
        return Int(text)
    }
}
