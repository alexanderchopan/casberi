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
        /// Whose words these are, when they are not the app's: Move draws the
        /// service's mark in place of its name (§1442n, user: "if we say
        /// relay we should show their logo. and not say 'said'").
        var from: String? = nil
        init(message: String, from: String? = nil) { self.message = message; self.from = from }
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
                #if DEBUG
                NSLog("bundler| %@ %@ → %@", URL(string: url)?.host ?? url, method, error)
                #endif
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

    /// A contract, as opposed to an address someone holds a key to. An
    /// EIP-7702 delegation (`0xef0100` ‖ the delegate, 23 bytes: MetaMask's
    /// and Coinbase's smart-account upgrade of an ordinary wallet) is still a
    /// key-held wallet — its key signs, and Safe takes that signature (prd
    /// §1432, measured on the user's own wallet).
    static func isContract(_ net: Network, _ address: String) async throws -> Bool {
        let code = (try await rpc(net, "eth_getCode", [address, "latest"]) as? String ?? "0x").lowercased()
        return YourAccountOp.isContractCode(code)
    }

    /// The sequence under nonce `key` (24 bytes; empty is key 0).
    static func nonce(_ net: Network, _ account: String, key: [UInt8] = []) async throws -> UInt64 {
        let keyWord = key.count == 24 ? [UInt8](repeating: 0, count: 8) + key : YourAccount.w(0)
        let data = YourAccount.sel("getNonce(address,uint192)") + YourAccount.w(account) + keyWord
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
                throw Failure(message: String(localized: "This device's key for \(net.name) no longer works. Use your account here again from Security"))
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
        try await transact(payments.map(Item.send), reason: reason, dryRun: dryRun, report: report, stage: stage).sent
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

    /// The one account a real install may run on before the adapter path is
    /// proven: a throwaway named by address in DEBUG (`-adapterThrowaway
    /// <0x…>`), never in a build anyone else runs (prd §1447 item 13).
    private static func throwaway(_ account: String) -> Bool {
        #if DEBUG
        guard let named = UserDefaults.standard.string(forKey: "adapterThrowaway") else { return false }
        return WalletWatch.sameAddress(named, account)
        #else
        return false
        #endif
    }

    /// Safe's fallback-handler slot, `keccak256("fallback_manager.handler.address")`.
    private static let fallbackHandlerSlot = "0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5"

    /// The contract the account answers through on `net`: the 7579 adapter
    /// once it is the fallback handler (prd §1447 item 11), else the module.
    static func accountEntry(_ net: Network, _ account: String) async throws -> YourAccountOp.Entry {
        guard let word = try await rpc(net, "eth_getStorageAt", [account, fallbackHandlerSlot, "latest"]) as? String,
              let bytes = SafeABI.hexBytes(word), bytes.count == 32 else {
            throw Failure(message: String(localized: "\(net.name) did not answer"))
        }
        let handler = "0x" + Keccak256.hexString(Array(bytes.suffix(20)))
        return WalletWatch.sameAddress(handler, YourAccount7579.adapter) ? .adapter : .module4337
    }

    /// The Safe's threshold: how many owners a transaction needs (prd §1447).
    static func threshold(_ net: Network, _ account: String) async throws -> Int {
        let answer = try await ethCall(net, to: account, data: YourAccount.sel("getThreshold()"))
        guard let n = SafeCall.decodeUInt(answer) else {
            throw Failure(message: String(localized: "\(net.name) did not answer"))
        }
        return n
    }

    /// This phone's key's allowance on the module, nil when the module has
    /// none for it (never set, or the module not enabled).
    static func allowance(_ net: Network, _ account: String, delegate: String, token: String) async throws -> YourAccountSigning.Allowance? {
        let answer = try await ethCall(net, to: YourAccountSigning.AllowanceModule.address,
                                       data: YourAccountSigning.allowanceCalldata(account: account, delegate: delegate, token: token))
        return YourAccountSigning.decodeAllowance(answer)
    }

    /// Two keys above an amount (prd §1447): the Allowance module on, this
    /// phone's signer a delegate with `amount` of `token` a period, then
    /// threshold 2 — one operation, signed by this phone, on a network the
    /// account exists on. Needs a Signer already an owner, or every send
    /// would wait on a key nobody holds.
    static func setBothKeys(on net: Network, token: String, amount: String, resetMinutes: Int, reason: String,
                            dryRun: Bool = false,
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        guard try await isDeployed(net, account) else {
            throw Failure(message: String(localized: "Your account is not on \(net.name) yet"))
        }
        let all = try await owners(net, account)
        var plain = 0
        for owner in all where owner.caseInsensitiveCompare(YourAccount.sharedSigner) != .orderedSame {
            if try await !isContract(net, owner) { plain += 1 }
        }
        guard plain > 0 else {
            throw Failure(message: String(localized: "Add a signer first: with both keys required, a send waits on it"))
        }
        // prd §1447 item 9: the shared signer cannot be the module's delegate,
        // and at 2-of-2 every user operation needs both keys — so this would
        // leave the account answering only to both. Refused outside a dry run.
        guard dryRun else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next),
              let calls = YourAccountSigning.enableCalls(account: account, delegate: YourAccount.sharedSigner,
                                                         token: token, amount: amount, resetMinutes: resetMinutes) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: true, calls: calls,
                                        rotateTo: nextKey, payments: [], signer: device, reason: reason,
                                        dryRun: dryRun, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// The account onto Safe's 7579 adapter (prd §1447 item 11): one
    /// operation, signed by this phone. SIMULATION ONLY until the adapter's
    /// send path is built and proven — after a real install every send must
    /// speak the adapter's encoding, and today's would be refused.
    static func installAdapter(on net: Network, reason: String, dryRun: Bool,
                               report: @escaping @Sendable (String) -> Void = { _ in },
                               stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard dryRun || throwaway(account) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        await stage(.preparing)
        // Not there yet: the account is created by this same operation, on
        // the phone that made it, as a first send creates it.
        let deployed = try await isDeployed(net, account)
        if deployed {
            guard try await accountEntry(net, account) == .module4337 else {
                throw Failure(message: String(localized: "Your account is already on it"))
            }
        }
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: deployed,
                                        calls: YourAccount7579.installCalls(account: account),
                                        rotateTo: nextKey, payments: [], signer: device, reason: reason,
                                        dryRun: dryRun, report: report, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    // MARK: - The spend limit's session (prd §1447 item 14)

    /// The phone's session key's validator config. Native P-256 only: Base's
    /// RIP-7212 is measured; Ethereum's EIP-7951 is not yet, here.
    private static func sessionInit() throws -> [UInt8] {
        let key = try YourAccountKey.sessionKey()
        return YourAccount7579.validatorInitData(x: key.x, y: key.y)
    }

    /// Whether Smart Sessions is a validator on the account, and whether a
    /// session is enabled on it.
    private static func sessionsInstalled(_ net: Network, _ account: String) async throws -> Bool {
        let answer = try await ethCall(net, to: account, data: YourAccount.sel("isModuleInstalled(uint256,address,bytes)")
            + YourAccount.w(1) + YourAccount.w(YourAccount7579.smartSession) + YourAccount.w(96) + YourAccount.w(0))
        return SafeCall.decodeUInt(answer) == 1
    }

    private static func sessionEnabled(_ net: Network, _ account: String, _ permission: [UInt8]) async throws -> Bool {
        let answer = try await ethCall(net, to: YourAccount7579.smartSession,
                                       data: YourAccount.sel("isPermissionEnabled(bytes32,address)") + permission + YourAccount.w(account))
        return SafeCall.decodeUInt(answer) == 1
    }

    /// The plan this phone installed on `net`, kept beside its keys' public
    /// halves: which windows exist and what each allows. The chain is the
    /// word on whether a window's session is enabled.
    private static func planKey(_ net: Network) -> String { "yourAccount.spendLimit.\(net.chainId)" }

    static func plan(_ net: Network) -> YourAccount7579.Plan? {
        UserDefaults.standard.data(forKey: planKey(net)).flatMap { try? JSONDecoder().decode(YourAccount7579.Plan.self, from: $0) }
    }

    /// Every session the account has on Smart Sessions.
    static func sessionIds(_ net: Network, _ account: String) async throws -> [[UInt8]] {
        let answer = SafeABI.hexBytes(try await ethCall(net, to: YourAccount7579.smartSession,
                                                        data: YourAccount7579.permissionIdsCall(account: account))) ?? []
        guard answer.count >= 64 else { return [] }
        let count = answer[32..<64].reduce(0) { $0 << 8 | Int($1) }
        guard count < 4096, answer.count >= 64 + count * 32 else { return [] }
        return (0..<count).map { Array(answer[(64 + $0 * 32)..<(96 + $0 * 32)]) }
    }

    /// A spend limit (prd §1447 items 14–15): one session per window of
    /// `plan`, each letting this phone's session key move up to the plan's
    /// dollar and ETH totals inside it — the dollar by `transfer`, ETH through
    /// Multicall3. Smart Sessions is installed with them the first time and
    /// enabled beside the old after, every older session removed in the same
    /// operation: a new limit replaces the last. Signed by this phone's
    /// account key like any send. Throwaway-only outside a simulation, which
    /// also runs each call as the account.
    static func installLimit(on net: Network, plan: YourAccount7579.Plan, reason: String, dryRun: Bool,
                             report: @escaping @Sendable (String) -> Void = { _ in },
                             stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard dryRun || throwaway(account) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        await stage(.preparing)
        guard try await isDeployed(net, account), try await accountEntry(net, account) == .adapter else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        let validatorInit = try sessionInit()
        let sessions = plan.windows.compactMap { YourAccount7579.session(validatorInit: validatorInit, plan: plan, window: $0) }
        guard !sessions.isEmpty, sessions.count == plan.windows.count else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let fresh = plan.windows.map { YourAccount7579.permissionId(validatorInit: validatorInit, salt: YourAccount7579.salt(plan, $0)) }
        let installed = try await sessionsInstalled(net, account)
        var calls = [installed ? YourAccount7579.enableSessionsCall(sessions)
                               : YourAccount7579.installSessionsCall(account: account, sessions: sessions)]
        if installed {
            for old in try await sessionIds(net, account) where !fresh.contains(old) {
                calls.append(YourAccount7579.removeSessionCall(old))
            }
        }
        report("windows=\(plan.windows.count) installed=\(installed) calls=\(calls.count) first=\(SafeABI.hex(fresh[0]))")
        if dryRun {
            for call in calls {
                do {
                    let answer = try await rpc(net, "eth_call", [["from": account, "to": call.to, "data": SafeABI.hex(call.data)], "latest"])
                    report("asAccount=\(String(describing: answer).prefix(80))")
                } catch let failure as Failure {
                    report("asAccount refused: \(failure.message)")
                }
            }
        }
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: true, calls: calls,
                                        rotateTo: nextKey, payments: [], signer: device, reason: reason,
                                        dryRun: dryRun, report: report, stage: stage)
        if case .landed = outcome, let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: planKey(net))
        }
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// `units` of `token` (ETH or the network's dollar) to `target`, signed
    /// by the session key alone, on the window of this phone's plan that
    /// holds now: the nonce key names Smart Sessions, the signature is USE
    /// mode, and the EntryPoint's own hash is what Face ID approves. Over
    /// the window's total the policy refuses it in validation, so the
    /// bundler's estimate is where it stops.
    static func limitSend(on net: Network, token: YourAccountOp.Token, to target: String, units: String, reason: String, dryRun: Bool,
                          report: @escaping @Sendable (String) -> Void = { _ in },
                          stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard dryRun || throwaway(account) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        await stage(.preparing)
        guard try await accountEntry(net, account) == .adapter, let plan = plan(net),
              let window = plan.window(at: Int(Date().timeIntervalSince1970)) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        let validatorInit = try sessionInit()
        let permission = YourAccount7579.permissionId(validatorInit: validatorInit, salt: YourAccount7579.salt(plan, window))
        report("window=\(window.from)–\(window.until) permissionId=\(SafeABI.hex(permission))")
        let call: [UInt8]?
        if let contract = token.contract {
            guard WalletWatch.sameAddress(contract, plan.dollar) else {
                throw Failure(message: String(localized: "A spend limit is not available yet"))
            }
            call = YourAccount7579.transferCall(token: contract, to: target, units: units)
        } else {
            call = YourAccount7579.ethSendCall(to: target, wei: units)
        }
        guard let callData = call else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        var op = YourAccountOp.Op(sender: account, nonce: 0, factory: nil, factoryData: [], callData: callData)
        op.entry = .adapter
        op.nonceKey = YourAccount7579.sessionNonceKey
        op.nonce = try await nonce(net, account, key: op.nonceKey)
        op.signature = YourAccount7579.useSignature(permissionId: permission, hash: [UInt8](repeating: 0, count: 32),
                                                    r: [UInt8](repeating: 0x11, count: 32), s: [UInt8](repeating: 0x22, count: 32))
        try await price(&op, on: net)
        let estimate: [String: Any]
        do {
            estimate = try await bundler(net, "eth_estimateUserOperationGas", [op.json, YourAccount.entryPoint]) as? [String: Any] ?? [:]
        } catch let failure as Failure {
            report("estimate refused: \(failure.message)")
            throw failure
        }
        func q(_ k: String) -> UInt64? {
            guard let v = (estimate[k] as? String).flatMap({ UInt64($0.dropFirst(2), radix: 16) }) else { return nil }
            let (m, overflow) = v.multipliedReportingOverflow(by: 12)
            return overflow ? nil : m / 10
        }
        guard let vgl = q("verificationGasLimit"), let cgl = q("callGasLimit"), let pvg = q("preVerificationGas"),
              vgl > 0, cgl > 0 else {
            throw Failure(message: String(localized: "\(net.name) could not price this send"))
        }
        // The dummy fails the challenge before the P-256 check the real
        // signature pays for; that difference, and more, on top.
        op.verificationGasLimit = vgl + 20_000
        op.callGasLimit = cgl
        op.preVerificationGas = pvg
        report("gas vgl=\(vgl) cgl=\(cgl) pvg=\(pvg)")

        // The EntryPoint's own word on the hash, before Face ID sees it.
        let hash = YourAccountOp.userOpHash(op, chainId: net.chainId)
        let theirs = SafeABI.hexBytes(try await ethCall(net, to: YourAccount.entryPoint,
            data: YourAccount.sel("getUserOpHash((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes))")
                + YourAccount.w(32) + op.packedTuple))
        guard theirs == hash, let digest = SafeWebAuthn.signingDigest(challenge: hash) else {
            throw Failure(message: String(localized: "Safe's module disagrees with this iPhone about what is signed, so nothing was"))
        }
        await stage(.signing)
        let (r, s) = try await YourAccountKey.signSession(digest, reason: reason)
        let signature = YourAccount7579.useSignature(permissionId: permission, hash: hash, r: r, s: s)
        // The validator itself, asked before anything goes.
        let verdict = try await ethCall(net, to: YourAccount7579.webAuthnValidator,
                                        data: YourAccount7579.checkCall(hash: hash, useSignature: signature, validatorInit: validatorInit))
        guard SafeCall.decodeUInt(verdict) == 1 else {
            throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
        }
        op.signature = signature
        report("signed: the passkey validator verifies it")
        if dryRun { return Sent(outcome: .dryRun, network: net) }
        return Sent(outcome: try await submit(op, net, account: account, stage: stage), network: net)
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

    /// Add a key held outside Casberi on `net` (prd §1432): one operation,
    /// signed by this iPhone, creating the account there when it is not there
    /// yet, that makes `owner` an owner at threshold 1 and moves to the next
    /// key. Refused for anything but a plain address — a contract (an
    /// exchange's deposit address is often one) cannot sign for a Safe.
    static func addOutsideKey(_ owner: String, on net: Network, reason: String,
                              stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard owner.caseInsensitiveCompare(account) != .orderedSame else {
            throw Failure(message: String(localized: "That is your account's own address"))
        }
        await stage(.preparing)
        if try await isContract(net, owner) {
            throw Failure(message: String(localized: "That address is a contract on \(net.name), not a wallet whose key you hold"))
        }
        let deployed = try await isDeployed(net, account)
        if deployed, try await owners(net, account).contains(where: { $0.caseInsensitiveCompare(owner) == .orderedSame }) {
            return Sent(outcome: .landed(transaction: nil, rotated: false), network: net)
        }
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: deployed,
                                        calls: [YourAccountOp.addOwnerCall(account: account, owner: owner)],
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

    // MARK: - Swap, through Relay (prd §1440)

    /// One Relay call, the body kept whatever the status: Relay's refusals
    /// carry their reason (`message`).
    private static func relay(_ path: String, body: [String: Any]?) async -> (json: Any?, status: Int) {
        guard let u = URL(string: "https://api.relay.link/" + path) else { return (nil, 0) }
        var request = URLRequest(url: u)
        if let body, let payload = try? JSONSerialization.data(withJSONObject: body) {
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, http) = await IngestSupport.sendRequest(request, service: service) else { return (nil, 0) }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed), http.statusCode)
    }

    /// Relay's token search for the sentence's For (prd §1440): its default
    /// list with nothing typed, matches as you type; verified tokens marked.
    static func relayCurrencies(_ net: Network, term: String) async -> [[String: Any]] {
        var body: [String: Any] = ["chainIds": [net.chainId], "limit": 40]
        if term.isEmpty { body["defaultList"] = true } else { body["term"] = term }
        return (await relay("currencies/v2", body: body).json as? [[String: Any]]) ?? []
    }

    /// Relay's dollar price for one whole `token` on `net`, keyless (its
    /// `currencies/token/price`): the sentence's dollars when the Wallet has
    /// not read the account yet (user, 2026-10-20: a dollar value typed
    /// before the token is picked).
    static func relayPrice(_ net: Network, _ token: YourAccountOp.Token) async -> Double? {
        let address = YourAccountSwap.currency(token)
        guard YourAccountSwap.supported(net),
              let json = await relay("currencies/token/price?address=\(address)&chainId=\(net.chainId)", body: nil).json
                as? [String: Any],
              let price = json["price"] as? Double, price > 0, price.isFinite else { return nil }
        return price
    }

    private static func relayRefusal(_ json: Any?, _ net: Network) -> Failure {
        let said = (json as? [String: Any])?["message"] as? String
        return said.map { Failure(message: $0, from: "Relay") }
            ?? Failure(message: String(localized: "Relay did not answer on \(net.name)"))
    }

    /// Relay's price and calls for selling `amount` of `sell` for `buy`, the
    /// account as sender and receiver, on one network.
    static func swapQuote(_ net: Network, sell: YourAccountOp.Token, buy: YourAccountOp.Token,
                          amount: String, account: String) async throws -> YourAccountSwap.Quote {
        guard YourAccountSwap.supported(net) else {
            throw Failure(message: String(localized: "Swaps are not on \(net.name)"))
        }
        let body: [String: Any] = [
            "user": account, "recipient": account,
            "originChainId": net.chainId, "destinationChainId": net.chainId,
            "originCurrency": YourAccountSwap.currency(sell), "destinationCurrency": YourAccountSwap.currency(buy),
            "amount": amount, "tradeType": "EXACT_INPUT",
        ]
        let (json, status) = await relay("quote", body: body)
        guard status == 200, let root = json as? [String: Any],
              let quote = YourAccountSwap.quote(from: root, chainId: net.chainId, sell: sell) else {
            throw relayRefusal(json, net)
        }
        return quote
    }

    /// One keyless GET, as JSON.
    static func fetchJSON(_ url: String) async -> Any? {
        guard let u = URL(string: url),
              let (data, http) = await IngestSupport.sendRequest(URLRequest(url: u), service: service),
              http.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// The account's balance of `token` as a call a simulation can make
    /// mid-sequence: `balanceOf`, or Multicall3's `getEthBalance` for ETH
    /// (deployed at one address on every chain the account is on).
    private static func balanceCall(_ token: YourAccountOp.Token, of account: String) -> [String: Any] {
        if let contract = token.contract {
            return ["from": account, "to": contract,
                    "data": SafeABI.hex(YourAccount.sel("balanceOf(address)") + YourAccount.w(account))]
        }
        return ["from": account, "to": "0xcA11bde05977b3631167028862bE2a173976CA11",
                "data": SafeABI.hex(YourAccount.sel("getEthBalance(address)") + YourAccount.w(account))]
    }

    /// **WHAT COMES BACK, PROVEN BEFORE FACE ID (prd §1440).** The account's
    /// calls, run in order by the network's own node (`eth_simulateV1`, as
    /// the account, against the real state), with the bought token's balance
    /// read around each swap. Refused unless every call succeeds and every
    /// swap pays at least its quoted minimum. Returns what each swap paid.
    private static func simulate(_ net: Network, account: String, approvals: [YourAccountOp.Call],
                                 steps: [(calls: [YourAccountOp.Call], swap: (buy: YourAccountOp.Token, minimum: String)?)])
        async throws -> [String?] {
        func json(_ c: YourAccountOp.Call) -> [String: Any] {
            // The value word as a JSON-RPC quantity: hex, no leading zeros.
            let digits = SafeABI.hex(c.value).dropFirst(2).drop { $0 == "0" }
            return ["from": account, "to": c.to, "value": "0x" + (digits.isEmpty ? "0" : String(digits)),
                    "data": SafeABI.hex(c.data)]
        }
        var calls: [[String: Any]] = approvals.map(json)
        var reads: [(before: Int, after: Int, minimum: String)?] = []
        for step in steps {
            if let swap = step.swap {
                let before = calls.count
                calls.append(balanceCall(swap.buy, of: account))
                calls += step.calls.map(json)
                let after = calls.count
                calls.append(balanceCall(swap.buy, of: account))
                reads.append((before, after, swap.minimum))
            } else {
                calls += step.calls.map(json)
                reads.append(nil)
            }
        }
        let params: [Any] = [["blockStateCalls": [["calls": calls]], "validation": false], "latest"]
        guard let blocks = try await rpc(net, "eth_simulateV1", params) as? [[String: Any]],
              let results = blocks.first?["calls"] as? [[String: Any]], results.count == calls.count else {
            throw Failure(message: String(localized: "\(net.name) could not check this swap, so nothing was signed"))
        }
        if results.contains(where: { ($0["status"] as? String) != "0x1" }) {
            throw Failure(message: String(localized: "This would fail on \(net.name), so nothing was signed"))
        }
        func value(_ i: Int) -> String? {
            (results[i]["returnData"] as? String).flatMap { YourAccountOp.decimal(hexQuantity: String($0.prefix(66))) }
        }
        var paid: [String?] = []
        for read in reads {
            guard let read else { paid.append(nil); continue }
            guard let before = value(read.before), let after = value(read.after) else {
                throw Failure(message: String(localized: "\(net.name) could not check this swap, so nothing was signed"))
            }
            let got = YourAccountOp.difference(after, before)
            guard YourAccountOp.atMost(read.minimum, got) else {
                throw Failure(message: String(localized: "Relay's route would pay less than it quoted, so nothing was signed"))
            }
            paid.append(got)
        }
        return paid
    }

    /// A swap the page describes: what is sold, for what, on one network.
    struct Swap: Equatable, Identifiable, Sendable {
        var id = UUID()
        let network: Network
        let sell: YourAccountOp.Token
        let buy: YourAccountOp.Token
        let amount: String
        /// The quote the page showed; Relay is asked afresh at signing.
        let quote: YourAccountSwap.Quote
    }

    /// One thing in a transaction: a send or a swap (prd §1436, batch swaps).
    enum Item: Equatable, Identifiable, Sendable {
        case send(YourAccountOp.Payment)
        case swap(Swap)
        var id: UUID {
            switch self {
            case .send(let p): p.id
            case .swap(let s): s.id
            }
        }
        var network: Network {
            switch self {
            case .send(let p): p.network
            case .swap(let s): s.network
            }
        }
    }

    struct Transacted: Equatable {
        let sent: Sent
        /// What each swap paid the account, in the batch's order (nil for a
        /// send): measured after landing when one swap bought that token,
        /// else the simulation's figure.
        var bought: [String?] = []
    }

    /// **EVERY SEND AND SWAP IN ONE OPERATION (prd §1436, §1440).** Each swap
    /// is quoted afresh by Relay and its calls checked (`YourAccountSwap.
    /// checked`: Relay's own contracts, exactly the amount sold); approvals
    /// go first, once per token for the sum; then the sends and swaps in the
    /// page's order and the key change. Before Face ID the whole of it is
    /// simulated and refused unless every swap pays its minimum. Relay settles
    /// in the same transaction, so a landed operation is a finished swap.
    static func transact(_ items: [Item], reason: String, dryRun: Bool = false,
                         report: @escaping @Sendable (String) -> Void = { _ in },
                         stage: @escaping @Sendable (Stage) async -> Void) async throws -> Transacted {
        guard let net = items.first?.network, items.allSatisfy({ $0.network == net }) else {
            throw Failure(message: String(localized: "One transaction sends on one network"))
        }
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        var payments: [YourAccountOp.Payment] = []
        var approvals: [(token: String, spender: String, amount: String)] = []
        var steps: [(calls: [YourAccountOp.Call], swap: (buy: YourAccountOp.Token, minimum: String)?)] = []
        for item in items {
            switch item {
            case .send(let p):
                guard let call = YourAccountOp.call(for: p) else {
                    throw Failure(message: String(localized: "This send could not be written"))
                }
                payments.append(p)
                steps.append(([call], nil))
            case .swap(let s):
                let quote = try await swapQuote(net, sell: s.sell, buy: s.buy, amount: s.amount, account: account)
                guard let checked = YourAccountSwap.checked(quote, sell: s.sell, amount: s.amount) else {
                    throw Failure(message: String(localized: "Relay asked for something other than this swap, so nothing was signed"))
                }
                let calls = checked.calls.compactMap(YourAccountSwap.accountCall)
                guard calls.count == checked.calls.count else {
                    throw Failure(message: String(localized: "This swap could not be written"))
                }
                approvals += checked.approvals
                steps.append((calls, (s.buy, quote.minimumBuy)))
                // What leaves the account, for the balance check before any prompt.
                payments.append(.init(network: net, token: s.sell, amount: s.amount,
                                      to: YourAccountSwap.routers.first ?? account, toName: nil))
            }
        }
        guard let approvalCalls = YourAccountSwap.approvalCalls(approvals) else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        let calls = approvalCalls + steps.flatMap(\.calls)
        let swaps = steps.compactMap(\.swap)

        // What the bought tokens hold now, to measure what landed.
        var before: [String: String] = [:]
        for buy in swaps.map(\.buy) where before[buy.contract ?? ""] == nil {
            before[buy.contract ?? ""] = await balance(net, buy, of: account) ?? "0"
        }
        let simulated = swaps.isEmpty ? [] : try await simulate(net, account: account, approvals: approvalCalls, steps: steps)
        report("simulated: \(simulated.compactMap { $0 }.joined(separator: ", "))")

        let deployed = try await isDeployed(net, account)
        let (signerIndex, signer) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        report("account=\(account) deployed=\(deployed) signer=key\(signerIndex) next=key\(next) swaps=\(swaps.count)")
        let outcome = try await operate(net, account: account, deployed: deployed, calls: calls,
                                        rotateTo: nextKey, payments: payments, signer: signer,
                                        reason: reason, dryRun: dryRun, report: report, stage: stage)
        let sent = Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
        guard case .landed = sent.outcome, !swaps.isEmpty else {
            return Transacted(sent: sent, bought: simulated)
        }
        // A token bought by one swap alone: what actually arrived.
        var bought = simulated
        for (i, step) in steps.enumerated() {
            guard let swap = step.swap else { continue }
            let key = swap.buy.contract ?? ""
            guard swaps.filter({ ($0.buy.contract ?? "") == key }).count == 1,
                  let then = before[key], let now = await balance(net, swap.buy, of: account) else { continue }
            let arrived = YourAccountOp.difference(now, then)
            if arrived != "0" { bought[i] = arrived }
        }
        return Transacted(sent: sent, bought: bought)
    }

    // MARK: - Revoke (prd §1437)

    /// Take back what the account let others spend: every revoke on one
    /// network in one operation, signed by this iPhone, with the key change.
    /// The calls are `WalletPrepare`'s own (`revokeTo`/`revokeData`), the
    /// same bytes the prepare card has always shown.
    static func revoke(_ revokes: [(to: String, data: String)], on net: Network, reason: String,
                       stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard let zero = SafeABI.word(uint256: "0") else { throw Failure(message: String(localized: "This send could not be written")) }
        var calls: [YourAccountOp.Call] = []
        for r in revokes {
            guard SafeABI.word(address: r.to) != nil, let data = SafeABI.hexBytes(r.data) else {
                throw Failure(message: String(localized: "This send could not be written"))
            }
            calls.append(.init(operation: 0, to: r.to, value: zero, data: data))
        }
        guard !calls.isEmpty else { throw Failure(message: String(localized: "Nothing to revoke")) }
        await stage(.preparing)
        let deployed = try await isDeployed(net, account)
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: deployed, calls: calls,
                                        rotateTo: nextKey, payments: [], signer: device,
                                        reason: reason, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    // MARK: - One operation, end to end

    /// Build, price, check, hash, sign, verify, send and follow one
    /// operation. Shared by a send, adding the recovery key and recovery.
    private static func operate(_ net: Network, account: String, deployed: Bool, calls: [YourAccountOp.Call],
                                rotateTo next: (x: [UInt8], y: [UInt8])?, payments: [YourAccountOp.Payment],
                                signer: Signer, reason: String, dryRun: Bool = false,
                                report: @escaping @Sendable (String) -> Void = { _ in },
                                stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent.Outcome {
        // Which contract this account answers through on this network
        // (prd §1447 item 11): the 4337 module, or the 7579 adapter.
        let entry: YourAccountOp.Entry = deployed ? try await accountEntry(net, account) : .module4337
        // A token approved to Multicall3 would ride every spend limit's ETH
        // route (prd §1447 item 15): never, from any operation.
        guard !calls.contains(where: YourAccount7579.approvesMulticall3) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        guard let callData = YourAccountOp.callData(calls: calls, rotateTo: next, entry: entry) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        var op = YourAccountOp.Op(sender: account, nonce: 0, factory: nil, factoryData: [], callData: callData)
        op.entry = entry
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
        // Every token the transaction moves, whatever list it came from
        // (prd §1438: the sentence sends and swaps any token you hold).
        var checked = Set<String>()
        for token in payments.map(\.token) where token.contract != nil && !dryRun {
            guard checked.insert(token.contract!.lowercased()).inserted, let total = out[token.contract!] else { continue }
            guard let tokenHeld = await balance(net, token, of: account), YourAccountOp.atMost(total, tokenHeld) else {
                throw Failure(message: String(localized: "Not enough \(token.symbol) on \(net.name)"))
            }
        }

        // What the person approves is computed HERE, and the module must
        // agree: a node's word alone never chooses the bytes this phone signs.
        let hash = YourAccountOp.safeOpHash(op, chainId: net.chainId)
        let theirs: [UInt8]?
        switch entry {
        case .module4337:
            theirs = SafeABI.hexBytes(try await ethCall(net, to: YourAccount.module4337, data: YourAccountOp.operationHashCall(op)))
        case .adapter:
            theirs = SafeABI.hexBytes(try await ethCall(net, to: YourAccount7579.adapter, data: YourAccountOp.safeOpCall(op)))
                .flatMap(YourAccountOp.firstBytes).map(Keccak256.hash)
        }
        guard theirs == hash, let digest = SafeWebAuthn.signingDigest(challenge: hash) else {
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
        return try await submit(op, net, account: account, stage: stage)
    }

    /// Sends a signed operation and follows it to the chain.
    private static func submit(_ op: YourAccountOp.Op, _ net: Network, account: String,
                               stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent.Outcome {
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
        func landed() async -> Bool { ((try? await nonce(net, account, key: op.nonceKey)) ?? op.nonce) > op.nonce }
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
