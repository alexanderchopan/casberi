import Foundation

/// **YOUR ACCOUNT ON CHAIN (prd §1424): the reads, and the one send.** Public
/// nodes for the reads, public ERC-4337 bundlers for the send, all keyless and
/// tried in order (`YourAccountOp.Network`), every request through
/// `IngestSupport`'s one transport so the ledger sees its host. Nothing here
/// carries more than the account's own public address and the operation it
/// signed.
///
/// A send (`send(_:)`): which key the account answers to on that network is
/// read from Safe's shared signer, never remembered; the next key is made;
/// the bundler estimates (with a balance override, so a short balance says
/// so in words rather than as an AA21); the module hashes; the Enclave signs
/// behind Face ID; the passkey factory checks the exact bytes; the bundler
/// takes it; the receipt says whether it landed and the shared signer
/// whether the key moved.
enum YourAccountChain {
    typealias Network = YourAccountOp.Network

    struct Failure: Error, Equatable {
        let message: String
    }

    private static let service = "Your account"

    // MARK: - JSON-RPC

    private static func post(_ url: String, _ method: String, _ params: [Any]) async -> (result: Any?, error: String?) {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        let (json, status) = await IngestSupport.postJSONBody(url, body: body, service: service)
        guard let root = json as? [String: Any] else { return (nil, status == 0 ? nil : "HTTP \(status)") }
        if let error = root["error"] as? [String: Any] {
            return (nil, (error["message"] as? String) ?? "\(error)")
        }
        return (root["result"], nil)
    }

    /// A node's answer: the first host that answers wins; a refusal (an
    /// `error` object) is the answer too, since the next host would refuse it
    /// the same way.
    static func rpc(_ net: Network, _ method: String, _ params: [Any]) async throws -> Any {
        var last = "\(net.name) did not answer"
        for url in net.rpcs {
            let (result, error) = await post(url, method, params)
            if let result, !(result is NSNull) { return result }
            if let error { last = error; if method == "eth_call" { break } }
        }
        throw Failure(message: last)
    }

    /// The first bundler that answers. A refusal of the operation itself
    /// (an AA code, a signature) is the answer, never an outage to route past.
    static func bundler(_ net: Network, _ method: String, _ params: [Any]) async throws -> Any {
        var last = "No bundler answered on \(net.name)"
        for url in net.bundlers {
            let (result, error) = await post(url, method, params)
            if let result, !(result is NSNull) { return result }
            if let error {
                last = error
                if error.contains("AA") || error.lowercased().contains("signature") { break }
            }
        }
        throw Failure(message: last)
    }

    static func ethCall(_ net: Network, to: String, data: [UInt8]) async throws -> String {
        guard let hex = try await rpc(net, "eth_call", [["to": to, "data": SafeABI.hex(data)], "latest"]) as? String
        else { throw Failure(message: "\(net.name) gave no answer") }
        return hex
    }

    // MARK: - Reads

    /// What the account holds of `token` on `net`, in base units; nil when no
    /// node answered.
    static func balance(_ net: Network, _ token: YourAccountOp.Token, of account: String) async -> String? {
        if let contract = token.contract {
            let data = YourAccount.sel("balanceOf(address)") + YourAccount.w(account)
            guard let hex = try? await ethCall(net, to: contract, data: data) else { return nil }
            return YourAccountOp.decimal(hexQuantity: hex.count > 2 ? hex : "0x0")
        }
        guard let hex = try? await rpc(net, "eth_getBalance", [account, "latest"]) as? String else { return nil }
        return YourAccountOp.decimal(hexQuantity: hex)
    }

    static func isDeployed(_ net: Network, _ account: String) async throws -> Bool {
        let code = try await rpc(net, "eth_getCode", [account, "latest"]) as? String ?? "0x"
        return code.count > 2
    }

    static func nonce(_ net: Network, _ account: String) async throws -> UInt64 {
        let data = YourAccount.sel("getNonce(address,uint192)") + YourAccount.w(account) + YourAccount.w(0)
        let word = try await ethCall(net, to: YourAccount.entryPoint, data: data)
        return UInt64(word.suffix(16), radix: 16) ?? 0
    }

    /// The x of the key Safe's shared signer holds for the account on `net`:
    /// the chain's own word on which key signs now. nil when it holds none
    /// (the account is not on this network yet, so key 0 signs its creation).
    static func configuredX(_ net: Network, _ account: String) async throws -> [UInt8]? {
        let data = YourAccount.sel("getConfiguration(address)") + YourAccount.w(account)
        let answer = try await ethCall(net, to: YourAccount.sharedSigner, data: data)
        guard let bytes = SafeABI.hexBytes(answer), bytes.count >= 32 else { return nil }
        let x = Array(bytes.prefix(32))
        return x.allSatisfy { $0 == 0 } ? nil : x
    }

    // MARK: - The send

    /// Where a send stands, for the page to say.
    enum Stage: Equatable { case preparing, signing, sending, landing }

    struct Sent: Equatable {
        enum Outcome: Equatable {
            /// On chain and it worked. `transaction` is nil when the nonce
            /// moved but no bundler would say which transaction carried it.
            case landed(transaction: String?, rotated: Bool)
            /// Taken, and not seen on chain within two minutes. NOT a
            /// failure: the page says so and clears the send, so it cannot be
            /// paid twice by a second tap.
            case pending
            case dryRun
        }
        let outcome: Outcome
        let network: Network
    }

    /// Prepare, sign behind Face ID, send and follow it until the chain says
    /// whether it landed. Every payment must be on one network: one operation
    /// is one chain. A thrown `Failure` means NOTHING was paid — or, for
    /// "failed on chain", only the fee — never "it might have".
    ///
    /// `dryRun` (DEBUG's `-yourAccountProbe`) does everything up to the
    /// bundler's `eth_sendUserOperation` — the estimate, both hashes, the
    /// Enclave's signature and the passkey factory's check of it — then
    /// stops: nothing is sent, and a short balance is reported, not refused.
    static func send(_ payments: [YourAccountOp.Payment], reason: String, dryRun: Bool = false,
                     report: @escaping @Sendable (String) -> Void = { _ in },
                     stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let net = payments.first?.network, payments.allSatisfy({ $0.network == net }) else {
            throw Failure(message: String(localized: "One transaction sends on one network"))
        }
        guard let account = YourAccountKey.address, let origin = YourAccountKey.publicKey(0) else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)

        // Which key signs: the chain says, and this phone must hold it.
        let deployed = try await isDeployed(net, account)
        let signerIndex: Int
        if deployed {
            guard let x = try await configuredX(net, account), let i = YourAccountKey.index(matchingX: x) else {
                throw Failure(message: String(localized: "This iPhone's keys no longer sign for your account on \(net.name)"))
            }
            signerIndex = i
        } else {
            signerIndex = 0
        }
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next),
              let signer = YourAccountKey.publicKey(signerIndex),
              let callData = YourAccountOp.callData(payments, rotateTo: nextKey) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }

        var op = YourAccountOp.Op(
            sender: account, nonce: deployed ? try await nonce(net, account) : 0,
            factory: deployed ? nil : YourAccount.proxyFactory,
            factoryData: deployed ? [] : YourAccountOp.factoryData(x: origin.x, y: origin.y),
            callData: callData)
        op.signature = YourAccountOp.dummySignature
        try await price(&op, on: net)
        // A balance override lets the bundler estimate whatever the account
        // holds, so a short balance is said below in words.
        let override: [String: Any] = [account: ["balance": "0xde0b6b3a7640000"]]
        let estimate = try await bundler(net, "eth_estimateUserOperationGas", [op.json, YourAccount.entryPoint, override]) as? [String: Any] ?? [:]
        // The dummy fails verification, so verification gas is the fallback
        // path's — an over-estimate, never short; a tenth more on each. A
        // number that overflows is a refusal, never a trap.
        func q(_ k: String) -> UInt64? {
            guard let v = (estimate[k] as? String).flatMap({ UInt64($0.dropFirst(2), radix: 16) }) else { return nil }
            let (m, overflow) = v.multipliedReportingOverflow(by: 11)
            return overflow ? nil : m / 10
        }
        guard let vgl = q("verificationGasLimit"), let cgl = q("callGasLimit"), let pvg = q("preVerificationGas"),
              vgl > 0, cgl > 0 else {
            throw Failure(message: String(localized: "\(net.name) could not price this send"))
        }
        op.verificationGasLimit = vgl
        op.callGasLimit = cgl
        op.preVerificationGas = pvg
        guard let maxCost = op.maxCost else {
            throw Failure(message: String(localized: "\(net.name) could not price this send"))
        }

        // Enough of each token for everything it sends, and ETH for the most
        // the fee can be too.
        let fee = String(maxCost)
        var out: [String: String] = [:]
        for p in payments { out[p.token.contract ?? "", default: "0"] = YourAccountOp.sum(out[p.token.contract ?? "", default: "0"], p.amount) }
        guard let held = await balance(net, YourAccountOp.eth, of: account) else {
            throw Failure(message: String(localized: "\(net.name) did not answer"))
        }
        report("account=\(account) deployed=\(deployed) signer=key\(signerIndex) next=key\(next) held=\(held) fee<=\(fee)")
        let ethNeed = YourAccountOp.sum(out[""] ?? "0", fee)
        if !YourAccountOp.atMost(ethNeed, held) {
            let need = YourAccountOp.spoken(ethNeed, decimals: 18)
            guard dryRun else { throw Failure(message: String(localized: "Needs \(need) ETH on \(net.name), with the fee")) }
            report("short: needs \(need) ETH with the fee")
        }
        for token in YourAccountOp.tokens(on: net) where token.contract != nil && !dryRun {
            guard let total = out[token.contract!] else { continue }
            guard let tokenHeld = await balance(net, token, of: account), YourAccountOp.atMost(total, tokenHeld) else {
                throw Failure(message: String(localized: "Not enough \(token.symbol) on \(net.name)"))
            }
        }

        // What Face ID approves is computed HERE, and the module must agree:
        // a node's word alone never chooses the bytes this phone signs.
        let hash = YourAccountOp.safeOpHash(op, chainId: net.chainId)
        guard SafeABI.hexBytes(try await ethCall(net, to: YourAccount.module4337,
                                                 data: YourAccountOp.operationHashCall(op))) == hash,
              let digest = SafeWebAuthn.signingDigest(challenge: hash) else {
            throw Failure(message: String(localized: "Safe's module disagrees with this iPhone about what is signed, so nothing was"))
        }

        await stage(.signing)
        let feeText = YourAccountOp.spoken(fee, decimals: 18)
        let (r, s) = try await YourAccountKey.sign(digest, with: signerIndex,
                                                   reason: reason + " · " + String(localized: "fee up to \(feeText) ETH"))
        // The exact bytes, checked by Safe's passkey factory before they go.
        guard let assertion = SafeWebAuthn.signatureBytes(r: r, s: s),
              let check = SafeWebAuthn.isValidSignatureForSignerCalldata(message: hash, signature: assertion, x: signer.x, y: signer.y),
              let checkBytes = SafeABI.hexBytes(check),
              SafeWebAuthn.isMagic(try await ethCall(net, to: SafeWebAuthn.factory, data: checkBytes)),
              let signature = YourAccountOp.signature(r: r, s: s) else {
            throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
        }
        op.signature = signature
        report("signed: the passkey factory verifies it")
        if dryRun { return Sent(outcome: .dryRun, network: net) }

        // Followed by its OWN id, known before it goes, so a late or lost
        // answer from the bundler can still be traced to whether it landed.
        let id = SafeABI.hex(YourAccountOp.userOpHash(op, chainId: net.chainId))
        await stage(.sending)
        var refusal: String?
        do {
            _ = try await bundler(net, "eth_sendUserOperation", [op.json, YourAccount.entryPoint])
        } catch let failure as Failure {
            // The operation itself is invalid (prefund, signature, a revert in
            // validation): it can land nowhere, so the refusal is final now.
            // Anything else — a nonce already used, an outage — is followed.
            if failure.message.range(of: #"AA(2[0-4]|3\d)"#, options: .regularExpression) != nil { throw failure }
            refusal = failure.message
        }
        await stage(.landing)
        func landed() async -> Bool { ((try? await nonce(net, account)) ?? op.nonce) > op.nonce }
        for tick in 1...60 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if let receipt = try? await bundler(net, "eth_getUserOperationReceipt", [id]) as? [String: Any] {
                let tx = (receipt["receipt"] as? [String: Any])?["transactionHash"] as? String
                guard (receipt["success"] as? Bool) == true else {
                    throw Failure(message: String(localized: "It reached \(net.name) and failed: nothing moved but the fee"))
                }
                return Sent(outcome: .landed(transaction: tx, rotated: await rotated(net, account, to: next, x: nextKey.x)), network: net)
            }
            // A refusal stands only once the chain shows nothing moved: a
            // bundler that took it and answered late is followed by another
            // one refusing the same operation.
            if let refusal, tick.isMultiple(of: 3) {
                if await landed() {
                    return Sent(outcome: .landed(transaction: nil, rotated: await rotated(net, account, to: next, x: nextKey.x)), network: net)
                }
                if tick >= 15 { throw Failure(message: refusal) }
            }
        }
        if await landed() {
            return Sent(outcome: .landed(transaction: nil, rotated: await rotated(net, account, to: next, x: nextKey.x)), network: net)
        }
        return Sent(outcome: .pending, network: net)
    }

    /// Whether the shared signer now holds the key made for this send; when
    /// it does, the next send makes a new one.
    private static func rotated(_ net: Network, _ account: String, to next: Int, x: [UInt8]) async -> Bool {
        let moved = (try? await configuredX(net, account)) == x
        if moved { YourAccountKey.used(next) }
        return moved
    }

    /// The fee: Pimlico's own price where it answers, else the node's.
    private static func price(_ op: inout YourAccountOp.Op, on net: Network) async throws {
        if let price = try? await bundler(net, "pimlico_getUserOperationGasPrice", []) as? [String: Any],
           let fast = price["fast"] as? [String: Any],
           let maxFee = (fast["maxFeePerGas"] as? String).flatMap({ UInt64($0.dropFirst(2), radix: 16) }),
           let tip = (fast["maxPriorityFeePerGas"] as? String).flatMap({ UInt64($0.dropFirst(2), radix: 16) }) {
            op.maxFeePerGas = maxFee
            op.maxPriorityFeePerGas = tip
            return
        }
        guard let gas = try await rpc(net, "eth_gasPrice", []) as? String,
              let p = UInt64(gas.dropFirst(2), radix: 16) else {
            throw Failure(message: String(localized: "\(net.name) could not price this send"))
        }
        let (doubled, overflow) = p.multipliedReportingOverflow(by: 2)
        guard !overflow else { throw Failure(message: String(localized: "\(net.name) could not price this send")) }
        op.maxFeePerGas = doubled
        op.maxPriorityFeePerGas = p
    }
}
