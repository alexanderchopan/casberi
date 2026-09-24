import Foundation

/// What a paired app may ASK this phone, read out of a WalletConnect request
/// before anything else looks at it (prd §913). Foundation-only and pure;
/// `scripts/safe-signer-selftest.sh` compiles it whole and holds it to one
/// rule: **the allowlist is the whole door.** A method not in
/// `allowedMethods` is refused by name before its params are parsed, and a
/// typed-data envelope that is not one of the three structures this app
/// signs is refused by its primary type. The file never names a refused
/// method, so the harness's negative grep (§8.4's guard, extended here) can
/// prove no sending or free-text path grew in.
///
/// **Chain and address are facts about the request, checked here, not
/// trusted from the envelope.** The session's `chainId` and the typed
/// data's domain must agree — a mainnet request carrying a Base domain is
/// two claims about where a signature will be valid, and the signer would
/// otherwise verify one and produce the other. The address asked for is
/// returned to the caller, who compares it with the key it holds.
enum SafePeerRequest {

    /// The two spellings of "sign this typed data". `eth_signTypedData` is
    /// the pre-v4 name some dapps still send; both carry the same envelope.
    static let allowedMethods: Set<String> = ["eth_signTypedData_v4", "eth_signTypedData"]

    /// A request this file could read into one of the three signable shapes.
    enum Ask: Equatable {
        /// A Safe transaction: the ten fields, and the digest the requester
        /// expects (the general encoder's) for the specific encoder to be
        /// checked against.
        case safeTx(chainId: Int, safe: String, tx: SafeTransaction, requesterHash: [UInt8])
        /// A Safe message: only the 32-byte inner hash travels here.
        case safeMessage(chainId: Int, safe: String, innerHash: [UInt8], requesterHash: [UInt8])
        /// A recovery approval.
        case recovery(SafeRecovery.Request, requesterHash: [UInt8])

        var chainId: Int {
            switch self {
            case .safeTx(let chainId, _, _, _), .safeMessage(let chainId, _, _, _): return chainId
            case .recovery(let r, _): return r.chainId
            }
        }
    }

    struct Parsed: Equatable {
        /// The account the request is addressed to, as the app spelled it.
        let address: String
        let ask: Ask
    }

    enum Refusal: Equatable {
        /// Named so the refusal row can say what was asked; the method string
        /// is the app's, and this file never spells one itself.
        case methodNotOffered(String)
        case paramsUnreadable
        case typedDataUnreadable
        case notASafeShape(primaryType: String)
        /// The session says one chain and the domain another.
        case chainMismatch(request: Int?, domain: Int)
        /// A domain with a name or version on a SafeTx/SafeMessage: a Safe
        /// older than 1.3.0, or something wearing a Safe's type strings.
        case foreignDomain
    }

    // MARK: - The door

    /// `params` is what JSON-RPC carries: `[address, typedData]`, the typed
    /// data as a JSON string (v4) or an object (older senders).
    static func parse(method: String, params: Any, chainId: Int?) -> Result<Parsed, Refusal> {
        guard allowedMethods.contains(method) else { return .failure(.methodNotOffered(method)) }
        guard let list = params as? [Any], list.count >= 2,
              let address = list[0] as? String, SafeABI.word(address: address) != nil
        else { return .failure(.paramsUnreadable) }
        guard let typed = EIP712.parse(list[1]) else { return .failure(.typedDataUnreadable) }
        return ask(from: typed, chainId: chainId).map { Parsed(address: address, ask: $0) }
    }

    /// The envelope alone — the same reading for a pasted request (tier 0),
    /// where there is no session to name a chain.
    static func ask(from typed: EIP712.TypedData, chainId: Int?) -> Result<Ask, Refusal> {
        guard let requesterHash = EIP712.digest(typed) else { return .failure(.typedDataUnreadable) }
        guard let domainChain = typed.chainId, let contract = typed.verifyingContract,
              SafeABI.word(address: contract) != nil
        else { return .failure(.typedDataUnreadable) }
        if let chainId, chainId != domainChain {
            return .failure(.chainMismatch(request: chainId, domain: domainChain))
        }
        switch typed.primaryType {
        case "SafeTx":
            guard typed.domainName == nil, typed.domainVersion == nil else { return .failure(.foreignDomain) }
            guard typed.types["SafeTx"] == safeTxFields, let tx = safeTransaction(typed.message)
            else { return .failure(.typedDataUnreadable) }
            return .success(.safeTx(chainId: domainChain, safe: contract, tx: tx, requesterHash: requesterHash))
        case "SafeMessage":
            guard typed.domainName == nil, typed.domainVersion == nil else { return .failure(.foreignDomain) }
            guard typed.types["SafeMessage"] == [EIP712.Field(name: "message", type: "bytes")],
                  let text = typed.message["message"]?.string,
                  let inner = SafeABI.hexBytes(text), inner.count == 32
            else { return .failure(.typedDataUnreadable) }
            return .success(.safeMessage(chainId: domainChain, safe: contract, innerHash: inner,
                                         requesterHash: requesterHash))
        case "ExecuteRecovery":
            guard let request = SafeRecovery.request(from: typed) else { return .failure(.typedDataUnreadable) }
            return .success(.recovery(request, requesterHash: requesterHash))
        default:
            return .failure(.notASafeShape(primaryType: typed.primaryType))
        }
    }

    // MARK: - SafeTx out of typed data

    static let safeTxFields: [EIP712.Field] = [
        .init(name: "to", type: "address"), .init(name: "value", type: "uint256"),
        .init(name: "data", type: "bytes"), .init(name: "operation", type: "uint8"),
        .init(name: "safeTxGas", type: "uint256"), .init(name: "baseGas", type: "uint256"),
        .init(name: "gasPrice", type: "uint256"), .init(name: "gasToken", type: "address"),
        .init(name: "refundReceiver", type: "address"), .init(name: "nonce", type: "uint256"),
    ]

    static func safeTransaction(_ message: [String: EIP712.Value]) -> SafeTransaction? {
        guard let to = message["to"]?.string,
              let value = message["value"].flatMap(EIP712.numberText),
              let data = message["data"]?.string,
              let operation = message["operation"].flatMap(EIP712.int),
              let safeTxGas = message["safeTxGas"].flatMap(EIP712.numberText),
              let baseGas = message["baseGas"].flatMap(EIP712.numberText),
              let gasPrice = message["gasPrice"].flatMap(EIP712.numberText),
              let gasToken = message["gasToken"]?.string,
              let refundReceiver = message["refundReceiver"]?.string,
              let nonce = message["nonce"].flatMap(EIP712.int),
              operation == 0 || operation == 1, nonce >= 0
        else { return nil }
        return SafeTransaction(to: to, value: value, data: data, operation: operation,
                               safeTxGas: safeTxGas, baseGas: baseGas, gasPrice: gasPrice,
                               gasToken: gasToken, refundReceiver: refundReceiver, nonce: nonce)
    }
}
