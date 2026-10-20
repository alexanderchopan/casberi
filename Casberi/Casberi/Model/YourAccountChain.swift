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

    /// Who signs an operation: this phone's Enclave key through Safe's shared
    /// signer, or the recovery key through its own passkey signer.
    struct Signer {
        let owner: String
        let x: [UInt8]
        let y: [UInt8]
        let sign: (_ digest: [UInt8], _ reason: String) async throws -> (r: [UInt8], s: [UInt8])
    }

    /// The device key the chain says signs for the account on `net` — the
    /// account must exist there, or key 0 signs its creation (only on the
    /// phone that made it).
    private static func deviceSigner(_ net: Network, _ account: String, deployed: Bool) async throws -> (index: Int, signer: Signer) {
        let index: Int
        if deployed {
            guard let x = try await configuredX(net, account), let i = YourAccountKey.index(matchingX: x) else {
                throw Failure(message: String(localized: "This iPhone's keys no longer sign for your account on \(net.name)"))
            }
            // The chain answers to a key this phone made but can no longer
            // use (Face ID re-enrolled, a restore without its keys).
            guard YourAccountKey.holds(i) else {
                throw Failure(message: String(localized: "This iPhone's key for \(net.name) no longer works. Move here with your recovery key"))
            }
            index = i
        } else {
            guard YourAccountKey.holdsOrigin else {
                throw Failure(message: String(localized: "Your account is not on \(net.name) yet, and only the iPhone that made it can put it there"))
            }
            index = 0
        }
        guard let key = YourAccountKey.publicKey(index) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        return (index, Signer(owner: YourAccount.sharedSigner, x: key.x, y: key.y) { digest, reason in
            try await YourAccountKey.sign(digest, with: index, reason: reason)
        })
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
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        let deployed = try await isDeployed(net, account)
        let (signerIndex, signer) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        let calls = payments.compactMap(YourAccountOp.call(for:))
        guard calls.count == payments.count, let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        report("account=\(account) deployed=\(deployed) signer=key\(signerIndex) next=key\(next)")
        let outcome = try await operate(net, account: account, deployed: deployed, calls: calls,
                                        rotateTo: nextKey, payments: payments, signer: signer,
                                        reason: reason, dryRun: dryRun, report: report, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    // MARK: - Recovery (prd §1427)

    /// Where the recovery key stands for the account on one network.
    enum RecoveryState: Equatable {
        /// The account does not exist on this network yet.
        case notThere
        case missing
        case added
    }

    /// The recovery key's Safe passkey signer — the same address on every
    /// network (the factory's own CREATE2), read from the factory once.
    static func recoverySigner(x: [UInt8], y: [UInt8]) async throws -> String {
        let cacheKey = "yourAccount.recoverySigner." + Keccak256.hexString(Keccak256.hash(x + y))
        if let cached = UserDefaults.standard.string(forKey: cacheKey) { return cached }
        guard let data = SafeWebAuthn.getSignerCalldata(x: x, y: y).flatMap(SafeABI.hexBytes) else {
            throw Failure(message: String(localized: "The recovery key has no signer"))
        }
        var answer: String?
        for net in YourAccountOp.networks where answer == nil {
            answer = try? await ethCall(net, to: SafeWebAuthn.factory, data: data)
        }
        guard let answer, let signer = SafeWebAuthn.decodeAddress(answer) else {
            throw Failure(message: String(localized: "The recovery key has no signer"))
        }
        UserDefaults.standard.set(signer, forKey: cacheKey)
        return signer
    }

    static func owners(_ net: Network, _ account: String) async throws -> [String] {
        let answer = try await ethCall(net, to: account, data: YourAccount.sel("getOwners()"))
        return SafeCall.decodeAddressArray(answer) ?? []
    }

    static func recoveryState(_ net: Network, _ account: String, signer: String) async throws -> RecoveryState {
        guard try await isDeployed(net, account) else { return .notThere }
        let all = try await owners(net, account)
        return all.contains { $0.caseInsensitiveCompare(signer) == .orderedSame } ? .added : .missing
    }

    /// Put the recovery key on `net`: one operation, signed by this phone,
    /// that creates the account there when it is not there yet, deploys the
    /// recovery key's signer, adds it as an owner and moves to the next key.
    static func addRecovery(on net: Network, reason: String,
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        let key = try YourAccountRecovery.make(for: account)
        let signer = try await recoverySigner(x: key.x, y: key.y)
        await stage(.preparing)
        let deployed = try await isDeployed(net, account)
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: deployed,
                                        calls: YourAccountOp.addRecoveryCalls(account: account, x: key.x, y: key.y, signer: signer),
                                        rotateTo: nextKey, payments: [], signer: device,
                                        reason: reason, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// Recovery on `net`: the recovery key alone moves the account to this
    /// phone's key `index`. The phone it moves away from stops signing there.
    static func recover(on net: Network, to index: Int, reason: String,
                        stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address,
              let key = YourAccountRecovery.publicKey(for: account),
              let target = YourAccountKey.publicKey(index) else {
            throw Failure(message: String(localized: "This iPhone holds no recovery key for this account"))
        }
        let signer = try await recoverySigner(x: key.x, y: key.y)
        await stage(.preparing)
        guard try await recoveryState(net, account, signer: signer) == .added else {
            throw Failure(message: String(localized: "Your recovery key is not on \(net.name)"))
        }
        let recovery = Signer(owner: signer, x: key.x, y: key.y) { digest, reason in
            try await YourAccountRecovery.sign(digest, for: account, reason: reason)
        }
        let outcome = try await operate(net, account: account, deployed: true,
                                        calls: [YourAccountOp.recoverCall(to: target)], rotateTo: nil,
                                        payments: [], signer: recovery, reason: reason, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: index, x: target.x), network: net)
    }

    /// A landed operation's key change, read back from the shared signer.
    private static func settle(_ outcome: Sent.Outcome, _ net: Network, _ account: String, next: Int, x: [UInt8]) async -> Sent.Outcome {
        guard case .landed(let tx, _) = outcome else { return outcome }
        return .landed(transaction: tx, rotated: await rotated(net, account, to: next, x: x))
    }

    // MARK: - Swap (prd §1430)

    private static func cowURL(_ net: Network, _ path: String) -> String? {
        CowOrder.apiNetwork[net.chainId].map { "https://api.cow.fi/\($0)/api/v1/\(path)" }
    }

    /// One CoW call, the body kept whatever the status: CoW's refusals carry
    /// their reason (`description`), and its order id answers as a bare string.
    private static func cow(_ url: String, body: [String: Any]?) async -> (json: Any?, status: Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        var request = URLRequest(url: u)
        if let body, let payload = try? JSONSerialization.data(withJSONObject: body) {
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, http) = await IngestSupport.sendRequest(request, service: service) else { return (nil, 0) }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed), http.statusCode)
    }

    private static func cowRefusal(_ json: Any?, _ net: Network) -> Failure {
        let said = (json as? [String: Any])?["description"] as? String
        return Failure(message: said.map { String(localized: "CoW said: \($0)") }
                       ?? String(localized: "CoW did not answer on \(net.name)"))
    }

    /// CoW's price for selling `amount` of `sell` for `buy` from the account.
    static func swapQuote(_ net: Network, sell: YourAccountOp.Token, buy: YourAccountOp.Token,
                          amount: String, account: String) async throws -> YourAccountSwap.Quote {
        guard YourAccountSwap.supported(net), let url = cowURL(net, "quote"),
              let sellToken = YourAccountSwap.cowToken(sell, on: net, selling: true),
              let buyToken = YourAccountSwap.cowToken(buy, on: net, selling: false) else {
            throw Failure(message: String(localized: "Swaps are not on \(net.name)"))
        }
        let body: [String: Any] = [
            "sellToken": sellToken, "buyToken": buyToken, "from": account, "receiver": account,
            "sellAmountBeforeFee": amount, "kind": "sell", "signingScheme": "presign", "onchainOrder": false,
            "sellTokenBalance": "erc20", "buyTokenBalance": "erc20", "priceQuality": "verified",
            "appData": YourAccountSwap.appData, "appDataHash": SafeABI.hex(YourAccountSwap.appDataHash),
            "validFor": 1800,
        ]
        let (json, status) = await cow(url, body: body)
        guard status == 200, let root = json as? [String: Any], let quote = YourAccountSwap.quote(from: root) else {
            throw cowRefusal(json, net)
        }
        return quote
    }

    /// Where a placed order stands, CoW's word.
    static func swapStatus(_ net: Network, uid: [UInt8]) async -> String? {
        guard let url = cowURL(net, "orders/" + SafeABI.hex(uid)),
              let root = await cow(url, body: nil).json as? [String: Any] else { return nil }
        return root["status"] as? String
    }

    struct Swapped: Equatable {
        let sent: Sent
        /// CoW's last word on the order: "fulfilled", or still "open".
        let status: String?
    }

    /// Quote afresh, build the order here, have CoW take it under the id
    /// this phone computed, then one operation — wrap, approve, pre-sign, and
    /// the key change — and follow the order until it fills (two minutes).
    static func swap(_ net: Network, sell: YourAccountOp.Token, buy: YourAccountOp.Token, amount: String,
                     reason: String, stage: @escaping @Sendable (Stage) async -> Void) async throws -> Swapped {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        let quote = try await swapQuote(net, sell: sell, buy: buy, amount: amount, account: account)
        guard let order = YourAccountSwap.order(sell: sell, buy: buy, on: net, account: account, quote: quote),
              let uid = YourAccountSwap.uid(order, owner: account, chainId: net.chainId),
              let calls = YourAccountSwap.calls(order: order, uid: uid, sellingETH: sell.contract == nil, network: net),
              let url = cowURL(net, "orders") else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        let (json, status) = await cow(url, body: YourAccountSwap.orderBody(order, owner: account, quoteId: quote.id))
        guard status == 201 || status == 200 else { throw cowRefusal(json, net) }
        // CoW must name the order this phone built, or nothing is signed.
        guard let said = json as? String, SafeABI.hexBytes(said) == uid else {
            throw Failure(message: String(localized: "CoW named a different order, so nothing was signed"))
        }

        let deployed = try await isDeployed(net, account)
        let (signerIndex, signer) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        // What leaves the account, for the balance check before any prompt.
        let spent = YourAccountOp.Payment(network: net, token: sell, amount: quote.sellAmount,
                                          to: CowOrder.settlement, toName: nil)
        let outcome = try await operate(net, account: account, deployed: deployed, calls: calls,
                                        rotateTo: nextKey, payments: [spent], signer: signer,
                                        reason: reason, stage: stage)
        let sent = Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
        guard case .landed = sent.outcome else { return Swapped(sent: sent, status: nil) }
        var last: String?
        for _ in 0..<40 {
            last = await swapStatus(net, uid: uid)
            if last == "fulfilled" || last == "expired" || last == "cancelled" { break }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return Swapped(sent: sent, status: last)
    }

    // MARK: - One operation, end to end

    /// Build, price, check, hash, sign, verify, send and follow one
    /// operation. Shared by a send, adding the recovery key and recovery.
    private static func operate(_ net: Network, account: String, deployed: Bool, calls: [YourAccountOp.Call],
                                rotateTo next: (x: [UInt8], y: [UInt8])?, payments: [YourAccountOp.Payment],
                                signer: Signer, reason: String, dryRun: Bool = false,
                                report: @escaping @Sendable (String) -> Void = { _ in },
                                stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent.Outcome {
        guard let callData = YourAccountOp.callData(calls: calls, rotateTo: next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        var op = YourAccountOp.Op(sender: account, nonce: 0, factory: nil, factoryData: [], callData: callData)
        if deployed {
            op.nonce = try await nonce(net, account)
        } else {
            guard let origin = YourAccountKey.origin else {
                throw Failure(message: String(localized: "This send could not be written"))
            }
            op.factory = YourAccount.proxyFactory
            op.factoryData = YourAccountOp.factoryData(x: origin.x, y: origin.y)
        }
        op.signature = YourAccountOp.dummySignature(owner: signer.owner)
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
        report("held=\(held) fee<=\(fee)")
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

        // What the person approves is computed HERE, and the module must
        // agree: a node's word alone never chooses the bytes this phone signs.
        let hash = YourAccountOp.safeOpHash(op, chainId: net.chainId)
        guard SafeABI.hexBytes(try await ethCall(net, to: YourAccount.module4337,
                                                 data: YourAccountOp.operationHashCall(op))) == hash,
              let digest = SafeWebAuthn.signingDigest(challenge: hash) else {
            throw Failure(message: String(localized: "Safe's module disagrees with this iPhone about what is signed, so nothing was"))
        }

        await stage(.signing)
        let feeText = YourAccountOp.spoken(fee, decimals: 18)
        let (r, s) = try await signer.sign(digest, reason + " · " + String(localized: "fee up to \(feeText) ETH"))
        // The exact bytes, checked by Safe's passkey factory before they go.
        guard let assertion = SafeWebAuthn.signatureBytes(r: r, s: s),
              let check = SafeWebAuthn.isValidSignatureForSignerCalldata(message: hash, signature: assertion, x: signer.x, y: signer.y),
              let checkBytes = SafeABI.hexBytes(check),
              SafeWebAuthn.isMagic(try await ethCall(net, to: SafeWebAuthn.factory, data: checkBytes)),
              let signature = YourAccountOp.signature(r: r, s: s, owner: signer.owner) else {
            throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
        }
        op.signature = signature
        report("signed: the passkey factory verifies it")
        if dryRun { return .dryRun }

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
                return .landed(transaction: tx, rotated: false)
            }
            // A refusal stands only once the chain shows nothing moved: a
            // bundler that took it and answered late is followed by another
            // one refusing the same operation.
            if let refusal, tick.isMultiple(of: 3) {
                if await landed() { return .landed(transaction: nil, rotated: false) }
                if tick >= 15 { throw Failure(message: refusal) }
            }
        }
        if await landed() { return .landed(transaction: nil, rotated: false) }
        return .pending
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
