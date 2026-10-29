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
        /// Refused for good: the simulation says it would fail, so asking
        /// another key instead (the spend limit's fallback) would not help.
        var settled = false
        init(message: String, from: String? = nil, settled: Bool = false) {
            self.message = message; self.from = from; self.settled = settled
        }
    }

    private static let service = "Your account"

    // MARK: - JSON-RPC

    private static func post(_ url: String, _ method: String, _ params: [Any],
                             as caller: String = service, wait: TimeInterval? = nil) async -> (result: Any?, error: String?, refused: Bool) {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        let (json, status) = await IngestSupport.$torWait.withValue(wait) {
            await IngestSupport.postJSONBody(url, body: body, service: caller)
        }
        guard let root = json as? [String: Any] else { return (nil, status == 0 ? nil : "HTTP \(status)", false) }
        if let error = root["error"] as? [String: Any] {
            return (nil, (error["message"] as? String) ?? "\(error)", true)
        }
        return (root["result"], nil, false)
    }

    /// A node's answer: the first host that answers wins; a refusal (an
    /// `error` object) is the answer too, since the next host would refuse it
    /// the same way.
    static func rpc(_ net: Network, _ method: String, _ params: [Any]) async throws -> Any {
        // YOUR OWN NODE (prd §1517): that network's reads go to it and to
        // nothing else, directly — falling back to the list would send your
        // address where you said not to.
        if let own = OwnNodeStore.settings.address(for: net.chainId) {
            let (result, error, _) = await post(own, method, params, as: OwnNodeStore.service)
            if let result, !(result is NSNull) { return result }
            throw Failure(message: error ?? String(localized: "Your node for \(net.name) did not answer"))
        }
        var last = "\(net.name) did not answer"
        // A node's read is small: 20s over Tor, then a fresh circuit. The
        // bundler keeps the long wait, since pricing an operation is not.
        for url in net.rpcs {
            let (result, error, refused) = await post(url, method, params, wait: 20)
            if let result, !(result is NSNull) { return result }
            if let error { last = error }
            // **A BUSY NODE IS NOT A REFUSAL (prd §1597).** A call the node
            // itself refused (a revert) would be refused by the next the same
            // way; a 429 is the node's load, not the call: `mainnet.base.org`
            // answered 20 of 60 balance reads in a burst over one circuit
            // with a 429, and every one the next node was never asked.
            if refused, method == "eth_call" { break }
        }
        throw Failure(message: last)
    }

    /// The first bundler that answers. A refusal of the operation itself
    /// (an AA code, a signature) is the answer, never an outage to route past.
    static func bundler(_ net: Network, _ method: String, _ params: [Any]) async throws -> Any {
        var last = "No bundler answered on \(net.name)"
        // **ONLY PRICING TAKES LONG (prd §1601).** A send, a receipt or a gas
        // price is as small as a node's read: 20s over Tor, then the next
        // circuit, never the minute (twice) every bundler call waited.
        let wait: TimeInterval? = method == "eth_estimateUserOperationGas" ? nil : 20
        for url in net.bundlers {
            let (result, error, _) = await post(url, method, params, wait: wait)
            if let result, !(result is NSNull) { return result }
            if let error {
                last = worded(error, on: net)
                #if DEBUG
                NSLog("bundler| %@ %@ → %@", URL(string: url)?.host ?? url, method, error)
                #endif
                if error.contains("AA") || error.lowercased().contains("signature") { break }
            }
        }
        throw Failure(message: last)
    }

    /// **WHAT TO ADD, NOT THAT SOMETHING IS SHORT (user, on "Needs … ETH,
    /// with the fee": "we should be able to tell the user that").** The ETH
    /// to add, rounded up so adding it is enough; an account not yet on the
    /// network says why its first send costs more.
    static func shortOfETH(need: String, held: String, on net: Network, deployed: Bool) -> String {
        let add = roundedUp(YourAccountOp.difference(need, held))
        return deployed
            ? String(localized: "Add \(add) ETH on \(net.name) for the fee")
            : String(localized: "Add \(add) ETH on \(net.name): your first send there also sets up your account")
    }

    /// Wei as ETH, rounded UP to two significant figures: 0.000719… is
    /// "0.00072", so adding what is said is enough.
    static func roundedUp(_ wei: String) -> String {
        guard let w = Double(wei), w > 0 else { return "0" }
        let eth = w / 1e18
        let scale = pow(10, 1 - floor(log10(eth)))
        let up = (eth * scale).rounded(.up) / scale
        return up.formatted(.number.precision(.significantDigits(1...2)).locale(Locale(identifier: "en_US_POSIX")))
    }

    /// A bundler's refusal in the app's words (prd §1461 item 4): the ones
    /// a person can meet are said as what happened; the rest keep the
    /// bundler's, which name an AA code the logs can be read by.
    static func worded(_ error: String, on net: Network) -> String {
        let lower = error.lowercased()
        if lower.contains("max gas") || lower.contains("gas limits exceed") || lower.contains("gas limit too high") {
            return String(localized: "Too much for one transaction on \(net.name): send less at once")
        }
        if lower.contains("aa21") || lower.contains("didn't pay prefund") || lower.contains("insufficient funds") {
            return String(localized: "Not enough ETH on \(net.name) for the fee")
        }
        if lower.contains("aa25") || lower.contains("invalid account nonce") {
            return String(localized: "\(net.name) is still taking your last send: try again in a minute")
        }
        if lower.contains("replacement") || lower.contains("already known") || lower.contains("already in the mempool") {
            return String(localized: "This send is already on its way on \(net.name)")
        }
        return error
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

    /// **THE FEE ALREADY PAID IN (user's first swap on Ethereum, measured:
    /// 0.00221 ETH stayed behind).** The EntryPoint takes the most a fee can
    /// be before an operation runs and keeps what was not spent as the
    /// account's deposit, which pays the next fee first; so what can pay is
    /// the balance AND the deposit. "0" when no node answered.
    static func feeDeposit(_ net: Network, of account: String) async -> String {
        let data = YourAccount.sel("balanceOf(address)") + YourAccount.w(account)
        guard let hex = try? await ethCall(net, to: YourAccount.entryPoint, data: data), hex.count > 2 else { return "0" }
        return YourAccountOp.decimal(hexQuantity: hex) ?? "0"
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
    /// `cosigning`: Face ID has passed and the Signer's wallet is asked
    /// (prd §1601: the foot said "Confirm with Face ID" for all of it).
    enum Stage: Equatable { case preparing, signing, cosigning, sending, landing }

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

    /// The account's Signer (prd §1447 item 16): an address of the person's
    /// own, an owner of the Safe, asked for `r ‖ s ‖ v` over the SafeOp hash
    /// when an operation needs both keys.
    struct CoSigner {
        let owner: String
        /// `typedData` is the SafeOp as `eth_signTypedData_v4` takes it,
        /// whose digest is `hash`.
        let sign: (_ hash: [UInt8], _ typedData: String) async throws -> [UInt8]
    }

    /// The device key the chain says signs for the account on `net` — the
    /// account must exist there, or key 0 signs its creation (only on the
    /// phone that made it).
    static func deviceSigner(_ net: Network, _ account: String, deployed: Bool) async throws -> (index: Int, signer: Signer) {
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
    static func send(_ payments: [YourAccountOp.Payment], reason: String, dryRun: Bool = false, coSigner: CoSigner? = nil,
                     report: @escaping @Sendable (String) -> Void = { _ in },
                     stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        try await transact(payments.map(Item.send), reason: reason, dryRun: dryRun, coSigner: coSigner, report: report, stage: stage).sent
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
    /// RIP-7212 and Ethereum's EIP-7951, both measured.
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
    static func installLimit(on net: Network, plan: YourAccount7579.Plan, reason: String, dryRun: Bool, coSigner: CoSigner? = nil,
                             requireBoth: Bool = false,
                             report: @escaping @Sendable (String) -> Void = { _ in },
                             stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        guard try await isDeployed(net, account), try await accountEntry(net, account) == .adapter else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        let (installed, fresh, planCalls, removals) = try await limitCalls(net, account, plan)
        var calls = planCalls
        if removals.count <= 2 {
            calls += removals
        } else {
            // A change of amount or period: the old periods still ahead go
            // in their own operation first, because twelve enabled and
            // twelve removed are more than one operation may hold (measured
            // on Base: 15.5M gas against the bundler's 15M). In between no
            // session stands, so a send takes both keys — never two limits.
            report("removing \(removals.count) periods first")
            if !dryRun {
                let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
                let next = try YourAccountKey.nextKey(after: signerIndex)
                guard let nextKey = YourAccountKey.publicKey(next) else {
                    throw Failure(message: String(localized: "This send could not be written"))
                }
                let outcome = try await operate(net, account: account, deployed: true, calls: removals, rotateTo: nextKey,
                                                payments: [], signer: device, coSigner: coSigner, reason: reason,
                                                report: report, stage: stage)
                let removed = Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
                guard case .landed = removed.outcome else {
                    throw Failure(message: String(localized: "\(net.name) did not take the change yet: try again in a minute"))
                }
            }
        }
        // Turning the limit on (prd §1455): both keys above it, last, while
        // this phone alone still signs.
        if requireBoth, try await threshold(net, account) == 1 {
            calls.append(YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                            data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(2)))
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
                                        rotateTo: nextKey, payments: [], signer: device, coSigner: coSigner, reason: reason,
                                        dryRun: dryRun, report: report, stage: stage)
        if case .landed = outcome, let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: planKey(net))
        }
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// A plan's calls: its sessions enabled (Smart Sessions installed with
    /// them the first time), every older session removed.
    private static func limitCalls(_ net: Network, _ account: String, _ plan: YourAccount7579.Plan) async throws
        -> (installed: Bool, fresh: [[UInt8]], calls: [YourAccountOp.Call], removals: [YourAccountOp.Call]) {
        let validatorInit = try sessionInit()
        let sessions = plan.windows.compactMap { YourAccount7579.session(validatorInit: validatorInit, plan: plan, window: $0) }
        guard !sessions.isEmpty, sessions.count == plan.windows.count else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let fresh = plan.windows.map { YourAccount7579.permissionId(validatorInit: validatorInit, salt: YourAccount7579.salt(plan, $0)) }
        let installed = try await sessionsInstalled(net, account)
        let calls = [installed ? YourAccount7579.enableSessionsCall(sessions)
                               : YourAccount7579.installSessionsCall(account: account, sessions: sessions)]
        // Every older session goes, but one whose period is over: its
        // TimeFramePolicy already refuses it, and removing a year of them
        // with the renewal is more than one operation may hold.
        var removals: [YourAccountOp.Call] = []
        if installed {
            let now = Int(Date().timeIntervalSince1970)
            let over: [[UInt8]] = YourAccountChain.plan(net).map { kept in
                kept.windows.filter { $0.until <= now }
                    .map { YourAccount7579.permissionId(validatorInit: validatorInit, salt: YourAccount7579.salt(kept, $0)) }
            } ?? []
            for old in try await sessionIds(net, account) where !fresh.contains(old) && !over.contains(old) {
                removals.append(YourAccount7579.removeSessionCall(old))
            }
        }
        return (installed, fresh, calls, removals)
    }

    /// **ONE SETTING (prd §1455, user: "needs to be one setting").** A plan
    /// whose periods run out — or are down to the last — is renewed by the
    /// next operation both keys sign anyway: the same amount and period, from
    /// now, the old sessions removed. Nobody is ever asked to set it again.
    static func renewal(_ net: Network, _ account: String) async throws -> (calls: [YourAccountOp.Call], plan: YourAccount7579.Plan)? {
        guard case .on(let plan, let current) = try await limitState(net, account) else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let length = plan.windows.first.map { $0.until - $0.from } ?? 0
        guard current == nil || (plan.windows.last?.until ?? 0) - now <= length else { return nil }
        guard let dollars = Int(plan.dollarCap.dropLast(6)) else { return nil }
        let price = plan.ethCap == "0" ? nil : await exchangePrice(net, YourAccountOp.eth)
        let next = limitPlan(on: net, dollars: dollars, ethPrice: price, minutes: max(length / 60, 1))
        // Riding a send, it removes only the period still running.
        let l = try await limitCalls(net, account, next)
        guard l.removals.count <= 2 else { return nil }
        return (l.calls + l.removals, next)
    }

    /// What the keys chosen at Create add to the operation that opens the
    /// account on `net` (prd §1457): the recovery key, the Signer, and — with
    /// a Signer — the spend limit: the account onto Safe's adapter, the
    /// plan's sessions, and both keys above them, last, while this phone
    /// alone still signs. Nil when nothing was chosen.
    static func setupCalls(_ net: Network, _ account: String) async throws
        -> (calls: [YourAccountOp.Call], plan: YourAccount7579.Plan?)? {
        let choice = YourAccountSetup.choice(for: account) ?? YourAccountSetup.Choice()
        var calls: [YourAccountOp.Call] = []
        // The recovery key rides whenever this phone holds one, chosen at
        // Create or set up later in Security: a network opened after the key
        // was made would otherwise open without it, and Security's Finish
        // would spend a fee there for what the opening send could carry.
        if let key = YourAccountRecovery.publicKey(for: account) {
            let signer = try await recoverySigner(x: key.x, y: key.y)
            calls += YourAccountOp.addRecoveryCalls(account: account, x: key.x, y: key.y, signer: signer, threshold: 1)
        }
        if let owner = choice.signer {
            calls.append(YourAccountOp.addOwnerCall(account: account, owner: owner, threshold: 1))
            // Required at Create (prd §1570): both keys, last, while this
            // phone alone still signs. No allowance: it is retired.
            if choice.required {
                calls.append(YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                                data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(2)))
            }
        }
        return calls.isEmpty ? nil : (calls, nil)
    }

    static func savePlan(_ plan: YourAccount7579.Plan, on net: Network) {
        if let data = try? JSONEncoder().encode(plan) { UserDefaults.standard.set(data, forKey: planKey(net)) }
    }

    // MARK: - The spend limit, as the app turns it on (prd §1455)

    /// The account's Signers on `net`: owners whose key someone holds —
    /// neither this phone's shared passkey signer nor a recovery key's
    /// contract, nor a key exported from this phone (prd §1493), which no
    /// wallet here is asked to sign with.
    static func signers(_ net: Network, _ account: String) async throws -> [String] {
        let asked = try await owners(net, account).filter { owner in
            owner.caseInsensitiveCompare(YourAccount.sharedSigner) != .orderedSame
                && !YourAccountExport.isExported(owner, for: account)
        }
        // Every owner's code at once (prd §1601), in the account's order.
        let contract = try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
            for (i, owner) in asked.enumerated() { group.addTask { (i, try await isContract(net, owner)) } }
            var found: [Int: Bool] = [:]
            for try await (i, c) in group { found[i] = c }
            return found
        }
        return asked.indices.filter { contract[$0] == false }.map { asked[$0] }
    }

    /// Where the spend limit stands on a network: off, on (its plan and the
    /// window that holds now), or on with every window spent.
    enum LimitState: Equatable {
        case off
        case on(YourAccount7579.Plan, current: YourAccount7579.Window?)
    }

    static func limitState(_ net: Network, _ account: String) async throws -> LimitState {
        // **NO PLAN, NOTHING ASKED; THE REST AT ONCE (prd §1601).** Every
        // send asked this before anything else, three round trips over Tor
        // one after another; the four reads are one now.
        guard let plan = plan(net) else { return .off }
        async let deployed = isDeployed(net, account)
        async let threshold = threshold(net, account)
        async let entry = accountEntry(net, account)
        async let sessions = sessionIds(net, account)
        guard try await deployed else { return .off }
        guard try await threshold == 2, try await entry == .adapter, try await !sessions.isEmpty else { return .off }
        return .on(plan, current: plan.window(at: Int(Date().timeIntervalSince1970)))
    }

    /// The same, for a reader that already holds the threshold of an account
    /// that is on `net` (Security's read): the plan this phone set is asked
    /// first, then the adapter and the sessions at once, one round trip over
    /// Tor in place of four.
    static func limitState(_ net: Network, _ account: String, threshold: Int) async throws -> LimitState {
        guard threshold == 2, let plan = plan(net) else { return .off }
        async let entry = accountEntry(net, account)
        async let sessions = sessionIds(net, account)
        guard try await entry == .adapter, try await !sessions.isEmpty else { return .off }
        return .on(plan, current: plan.window(at: Int(Date().timeIntervalSince1970)))
    }

    /// A plan of `dollars` of the network's dollar and as much ETH (at
    /// `ethPrice`, nil leaves ETH to both keys) each `minutes`, set up ahead.
    static func limitPlan(on net: Network, dollars: Int, ethPrice: Double?, minutes: Int, count: Int? = nil) -> YourAccount7579.Plan {
        let dollarCap = String(dollars) + "000000"
        var ethCap = "0"
        if let ethPrice, ethPrice > 0 {
            let wei = (Decimal(dollars) / Decimal(ethPrice)) * pow(10, 18)
            var rounded = Decimal(), value = wei
            NSDecimalRound(&rounded, &value, 0, .down)
            ethCap = NSDecimalNumber(decimal: rounded).stringValue
        }
        let start = Int(Date().timeIntervalSince1970) / 60 * 60
        return YourAccount7579.Plan(chainId: net.chainId, dollar: net.dollar, dollarCap: dollarCap, ethCap: ethCap,
                                    windows: YourAccount7579.windows(start: start, seconds: minutes * 60,
                                                                     count: count ?? YourAccount7579.windowCount(minutes: minutes)))
    }

    /// Turning it on (prd §1455): this phone alone, while one key still
    /// signs — the account onto Safe's adapter if it is not yet, then the
    /// plan's sessions and both keys above them, in one operation. Needs a
    /// Signer, or every send over the limit would wait on nobody.
    static func turnOnLimit(on net: Network, dollars: Int, minutes: Int, reason: String, coSigner: CoSigner? = nil,
                            report: @escaping @Sendable (String) -> Void = { _ in },
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        guard try await isDeployed(net, account) else {
            throw Failure(message: String(localized: "Your account is not on \(net.name) yet"))
        }
        guard try await !signers(net, account).isEmpty else {
            throw Failure(message: String(localized: "Add a signer first: over the limit, a send waits on it"))
        }
        if try await accountEntry(net, account) == .module4337 {
            let moved = try await installAdapter(on: net, reason: reason, dryRun: false, report: report, stage: stage)
            guard case .landed = moved.outcome else {
                throw Failure(message: String(localized: "\(net.name) did not take the change yet: try again in a minute"))
            }
        }
        // The plan this phone set still stands — its sessions enabled, a
        // period ahead — and only both keys went (a key added at one key,
        // prd §1456): both keys again, nothing re-enabled. Enabling twelve
        // sessions and removing twelve is more than one operation may hold
        // (measured on Base: 17.9M gas against the bundler's 15M).
        if try await threshold(net, account) == 1, let kept = plan(net), kept.dollarCap == String(dollars) + "000000",
           kept.windows.first.map({ $0.until - $0.from }) == minutes * 60,
           kept.window(at: Int(Date().timeIntervalSince1970)) != nil {
            let validatorInit = try sessionInit()
            let standing = try await sessionIds(net, account)
            let ids = kept.windows.map { YourAccount7579.permissionId(validatorInit: validatorInit, salt: YourAccount7579.salt(kept, $0)) }
            if ids.allSatisfy(standing.contains) {
                report("plan stands: both keys again")
                let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
                let next = try YourAccountKey.nextKey(after: signerIndex)
                guard let nextKey = YourAccountKey.publicKey(next) else {
                    throw Failure(message: String(localized: "This send could not be written"))
                }
                let calls = [YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                                data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(2))]
                let outcome = try await operate(net, account: account, deployed: true, calls: calls, rotateTo: nextKey,
                                                payments: [], signer: device, reason: reason, report: report, stage: stage)
                return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
            }
        }
        let price = await exchangePrice(net, YourAccountOp.eth)
        let plan = limitPlan(on: net, dollars: dollars, ethPrice: price, minutes: minutes)
        return try await installLimit(on: net, plan: plan, reason: reason, dryRun: false, coSigner: coSigner, requireBoth: true,
                                      report: report, stage: stage)
    }

    /// A new amount or period: a new plan, every older session removed —
    /// a change to the keys, so both sign.
    static func changeLimit(on net: Network, dollars: Int, minutes: Int, coSigner: CoSigner, reason: String,
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        let price = await exchangePrice(net, YourAccountOp.eth)
        let plan = limitPlan(on: net, dollars: dollars, ethPrice: price, minutes: minutes)
        return try await installLimit(on: net, plan: plan, reason: reason, dryRun: false, coSigner: coSigner, stage: stage)
    }

    /// Turning it off: every session removed and one key again — both sign it.
    static func turnOffLimit(on net: Network, coSigner: CoSigner, reason: String,
                             stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        var calls = try await sessionIds(net, account).map(YourAccount7579.removeSessionCall)
        calls.append(YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                        data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(1)))
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: true, calls: calls,
                                        rotateTo: nextKey, payments: [], signer: device, coSigner: coSigner,
                                        reason: reason, stage: stage)
        if case .landed = outcome { UserDefaults.standard.removeObject(forKey: planKey(net)) }
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// **CO-SIGNER REQUIRED (user, 2026-10-27: "we should just turn cosigner
    /// on or off"; the spend limit's allowance retired).** Every send and swap
    /// needs both keys on `net`: from one key this phone alone raises it; an
    /// allowance still standing (§1455) has its sessions removed, which both
    /// keys sign. Nil when nothing was to change.
    static func requireCoSigner(on net: Network, coSigner: CoSigner?, reason: String,
                                stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent? {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        let keys = try await threshold(net, account)
        var calls = (try? await sessionIds(net, account))?.map(YourAccount7579.removeSessionCall) ?? []
        if keys < 2 {
            calls.append(YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                            data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(2)))
        }
        guard !calls.isEmpty else { return nil }
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: true, calls: calls,
                                        rotateTo: nextKey, payments: [], signer: device,
                                        coSigner: keys < 2 ? nil : coSigner, reason: reason, stage: stage)
        if case .landed = outcome { UserDefaults.standard.removeObject(forKey: planKey(net)) }
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// Sends under the limit, on the session key alone (prd §1455): each
    /// the network's dollar or ETH, a round-up's buy with them, in one
    /// operation on the window that holds now. Over the limit, or anything
    /// else, the policy refuses it in validation and nothing is sent — the
    /// caller asks both keys instead.
    static func sessionSend(_ payments: [YourAccountOp.Payment], roundUp: RoundUpBuy? = nil, reason: String,
                            report: @escaping @Sendable (String) -> Void = { _ in },
                            stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let net = payments.first?.network, let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        // The session never buys on the exchanges (prd §1545).
        let roundUp = sessionRoundUp(roundUp, on: net)
        await stage(.preparing)
        // A preview of these sends on the session key, under a minute old,
        // is signed as it stands (prd §1509).
        let kept = await Prepared.take(payments.map(Item.send), roundUp: roundUp, route: .session)
        let (callData, salt) = try await sessionCall(payments, roundUp: roundUp, account: account)
        // Simulated like every other send (prd §1509): the transfers as the
        // account makes them; a refusal sends nothing.
        let steps: [Step] = payments.compactMap { YourAccountOp.call(for: $0).map { ([$0], nil) } }
        let symbols = Dictionary(payments.compactMap { p in p.token.contract.map { ($0.lowercased(), p.token.symbol) } },
                                 uniquingKeysWith: { a, _ in a })
        try require(await check(net, account: account, approvals: [], steps: steps, symbols: symbols), on: net, swaps: false)
        return try await sessionOperation(net, account: account, callData: callData, salt: salt, reason: reason,
                                          pinned: kept?.op, report: report, stage: stage)
    }

    /// **THE SESSION KEY NEVER BUYS ON THE EXCHANGES (prd §1545, user
    /// 2026-10-26).** It may only `transfer` the network's dollar and send
    /// ETH through Multicall3 (§1447 item 15); an `approve` and a router call
    /// are actions it was never given, and it is not widened to take them.
    /// So a round-up's buy rides the session only to another network, as
    /// Relay's `transfer`; a buy on this network waits, its change counted,
    /// for the next send you approve with Face ID.
    static func sessionRoundUp(_ roundUp: RoundUpBuy?, on net: Network) -> RoundUpBuy? {
        roundUp.flatMap { RoundUps.sessionCarries($0.target, from: net.chainId) ? $0 : nil }
    }

    /// The session key's calls for these sends (and a round-up's buy to
    /// another network), and the salt of the window that holds now.
    static func sessionCall(_ payments: [YourAccountOp.Payment], roundUp: RoundUpBuy?, account: String) async throws
        -> (callData: [UInt8], salt: [UInt8]) {
        guard let net = payments.first?.network, payments.allSatisfy({ $0.network == net }),
              let plan = plan(net), let window = plan.window(at: Int(Date().timeIntervalSince1970)) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        var calls: [YourAccount7579.Execution] = []
        for p in payments {
            guard let call = YourAccount7579.sessionCall(token: p.token.contract, dollar: plan.dollar, to: p.to, units: p.amount) else {
                throw Failure(message: String(localized: "A spend limit is not available yet"))
            }
            calls.append(call)
        }
        if let roundUp = sessionRoundUp(roundUp, on: net) {
            let deposit = try await depositAddress(from: net, currency: net.dollar, to: roundUp.target,
                                                   amount: roundUp.units, account: account)
            // So the landed send to it reads as this buy (prd §1523).
            RoundUps.noteDeposit(deposit.address, target: roundUp.target)
            guard let call = YourAccount7579.sessionCall(token: net.dollar, dollar: plan.dollar, to: deposit.address, units: roundUp.units) else {
                throw Failure(message: String(localized: "This send could not be written"))
            }
            calls.append(call)
        }
        let callData = calls.count == 1
            ? YourAccount7579.executeSingle(to: calls[0].target, wei: YourAccountOp.decimal(calls[0].value), data: calls[0].data)
            : YourAccount7579.executeBatch(calls)
        guard let callData else { throw Failure(message: String(localized: "This send could not be written")) }
        return (callData, YourAccount7579.salt(plan, window))
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
        await stage(.preparing)
        guard try await accountEntry(net, account) == .adapter, let plan = plan(net),
              let window = plan.window(at: Int(Date().timeIntervalSince1970)) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        report("window=\(window.from)–\(window.until)")
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
        return try await sessionOperation(net, account: account, callData: callData, salt: YourAccount7579.salt(plan, window),
                                          reason: reason, dryRun: dryRun, report: report, stage: stage)
    }

    /// The session key's operation, priced but unsigned: Smart Sessions'
    /// nonce key, a USE-mode dummy of the right shape, the bundler's
    /// estimate. Over the window's total the policy refuses it here, in the
    /// estimate, so the preview knows a send is over the limit before any
    /// tap (prd §1509).
    static func sessionBuild(_ net: Network, account: String, callData: [UInt8], salt: [UInt8],
                             pinned: YourAccountOp.Op? = nil,
                             report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> YourAccountOp.Op {
        let validatorInit = try sessionInit()
        let permission = YourAccount7579.permissionId(validatorInit: validatorInit, salt: salt)
        var op = YourAccountOp.Op(sender: account, nonce: 0, factory: nil, factoryData: [], callData: callData)
        op.entry = .adapter
        op.nonceKey = YourAccount7579.sessionNonceKey
        op.nonce = try await nonce(net, account, key: op.nonceKey)
        op.signature = YourAccount7579.useSignature(permissionId: permission, hash: [UInt8](repeating: 0, count: 32),
                                                    r: [UInt8](repeating: 0x11, count: 32), s: [UInt8](repeating: 0x22, count: 32))
        if let pinned, pinned.nonce == op.nonce, pinned.nonceKey == op.nonceKey, pinned.callData == op.callData,
           pinned.sender == op.sender {
            op.verificationGasLimit = pinned.verificationGasLimit
            op.callGasLimit = pinned.callGasLimit
            op.preVerificationGas = pinned.preVerificationGas
            op.maxFeePerGas = pinned.maxFeePerGas
            op.maxPriorityFeePerGas = pinned.maxPriorityFeePerGas
            report("pinned: the preview's gas and fee")
            return op
        }
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

        return op
    }

    /// One operation on the session key: Smart Sessions' nonce key, the
    /// window's permission, the EntryPoint's own hash under Face ID, and the
    /// passkey validator asked before it goes.
    private static func sessionOperation(_ net: Network, account: String, callData: [UInt8], salt: [UInt8],
                                         reason: String, dryRun: Bool = false, pinned: YourAccountOp.Op? = nil,
                                         report: @escaping @Sendable (String) -> Void = { _ in },
                                         stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        let validatorInit = try sessionInit()
        let permission = YourAccount7579.permissionId(validatorInit: validatorInit, salt: salt)
        var op = try await sessionBuild(net, account: account, callData: callData, salt: salt, pinned: pinned, report: report)
        let hash = YourAccountOp.userOpHash(op, chainId: net.chainId)
        // The EntryPoint's own word on the hash, before Face ID sees it.
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

    /// Safe's 7579 adapter onto a network that lacks it (prd §1447 item
    /// 18): Rhinestone's OWN publish transaction from Ethereum, read off
    /// Ethereum and replayed through Safe's singleton factory, refused unless
    /// it lands at the adapter's address (the address commits to the code,
    /// so it is the audited adapter, byte for byte). Anyone may send it; the
    /// account sends it as one call, creating itself there first if it must.
    /// Throwaway-only outside a simulation.
    static func publishAdapter(on net: Network, reason: String, dryRun: Bool,
                               report: @escaping @Sendable (String) -> Void = { _ in },
                               stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        guard dryRun || throwaway(account) else {
            throw Failure(message: String(localized: "A spend limit is not available yet"))
        }
        await stage(.preparing)
        if try await isContract(net, YourAccount7579.adapter) {
            report("already published")
            return Sent(outcome: .landed(transaction: nil, rotated: false), network: net)
        }
        guard let tx = try await rpc(YourAccountOp.ethereum, "eth_getTransactionByHash", [YourAccount7579.publishTransaction]) as? [String: Any],
              let to = tx["to"] as? String, WalletWatch.sameAddress(to, YourAccount7579.singletonFactory),
              let input = (tx["input"] as? String).flatMap(SafeABI.hexBytes),
              let lands = YourAccount7579.publishedAddress(input), WalletWatch.sameAddress(lands, YourAccount7579.adapter) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        report("publish: \(input.count) bytes, lands at \(lands)")
        let deployed = try await isDeployed(net, account)
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let call = YourAccountOp.Call(operation: 0, to: YourAccount7579.singletonFactory, value: YourAccount.w(0), data: input)
        let outcome = try await operate(net, account: account, deployed: deployed, calls: [call],
                                        rotateTo: nextKey, payments: [], signer: device, reason: reason,
                                        dryRun: dryRun, report: report, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
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
                                        calls: YourAccountOp.addRecoveryCalls(account: account, x: key.x, y: key.y, signer: signer,
                                                                              threshold: deployed ? try await threshold(net, account) : 1),
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
                                        calls: [YourAccountOp.addOwnerCall(account: account, owner: owner,
                                                                           threshold: deployed ? try await threshold(net, account) : 1)],
                                        rotateTo: nextKey, payments: [], signer: device,
                                        reason: reason, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// Take a plain-key owner off `net` (prd §1493: an exported key's
    /// Remove): one operation, signed by this phone, keeping the threshold.
    /// Already gone is done.
    static func removeOwnerKey(_ owner: String, on net: Network, reason: String,
                               stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        await stage(.preparing)
        guard try await isDeployed(net, account) else {
            return Sent(outcome: .landed(transaction: nil, rotated: false), network: net)
        }
        let all = try await owners(net, account)
        guard all.contains(where: { $0.caseInsensitiveCompare(owner) == .orderedSame }) else {
            return Sent(outcome: .landed(transaction: nil, rotated: false), network: net)
        }
        guard let call = YourAccountOp.removeOwnerCall(account: account, owners: all, owner: owner,
                                                       threshold: try await threshold(net, account)) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: true, calls: [call],
                                        rotateTo: nextKey, payments: [], signer: device,
                                        reason: reason, stage: stage)
        return Sent(outcome: await settle(outcome, net, account, next: next, x: nextKey.x), network: net)
    }

    /// Both keys for every operation the account's own owners sign (prd
    /// §1447 item 16): `signer` an owner and the threshold 2, signed by this
    /// phone while one key still suffices. Under a spend limit the session
    /// key still sends alone; everything else waits on the Signer too.
    /// Throwaway-only until the Signer's side is built.
    static func requireBoth(_ signer: String, on net: Network, reason: String, dryRun: Bool, coSigner: CoSigner? = nil,
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
        if try await isContract(net, signer) {
            throw Failure(message: String(localized: "That address is a contract on \(net.name), not a wallet whose key you hold"))
        }
        let isOwner = try await owners(net, account).contains { $0.caseInsensitiveCompare(signer) == .orderedSame }
        let call = isOwner
            ? YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                 data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(2))
            : YourAccountOp.Call(operation: 0, to: account, value: YourAccount.w(0),
                                 data: YourAccount.sel("addOwnerWithThreshold(address,uint256)") + YourAccount.w(signer) + YourAccount.w(2))
        let (signerIndex, device) = try await deviceSigner(net, account, deployed: true)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        let outcome = try await operate(net, account: account, deployed: true, calls: [call],
                                        rotateTo: nextKey, payments: [], signer: device, coSigner: coSigner, reason: reason,
                                        dryRun: dryRun, report: report, stage: stage)
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

    // MARK: - Relay, for Receive from another network (prd §1453, §1470)

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

    /// A round-up's buy (prd §1452): `units` of the network's dollar, for
    /// `target`.
    struct RoundUpBuy: Equatable, Sendable {
        let units: String
        let target: RoundUps.Target
    }

    /// Relay's deposit address for a route (prd §1452): send `currency`
    /// on `origin` to it and Relay delivers `target` to the account. The
    /// answer is refused unless it names the account as the one that gets
    /// it, the route asked for, and — where Relay hands back the transfer
    /// itself — exactly a transfer of `amount` to that address.
    struct Deposit: Equatable, Sendable {
        let address: String
        let outUSD: Double?
        let feeUSD: Double?
        let seconds: Int?
    }

    static func depositAddress(from origin: Network, currency: String, to target: RoundUps.Target,
                               amount: String, account: String) async throws -> Deposit {
        try await depositAddress(fromChain: origin.chainId, currency: currency, to: target, amount: amount, account: account,
                                 name: origin.name)
    }

    static func depositAddress(fromChain chainId: Int, currency: String, to target: RoundUps.Target,
                               amount: String, account: String, name: String) async throws -> Deposit {
        let body: [String: Any] = [
            "user": account, "recipient": account, "refundTo": account,
            "originChainId": chainId, "originCurrency": currency,
            "destinationChainId": target.chainId, "destinationCurrency": target.address,
            "tradeType": "EXACT_INPUT", "amount": amount, "useDepositAddress": true,
        ]
        let (json, status) = await relay("quote/v2", body: body)
        guard status == 200, let o = json as? [String: Any],
              let step = (o["steps"] as? [[String: Any]])?.first,
              let address = step["depositAddress"] as? String, SafeABI.word(address: address) != nil,
              let details = o["details"] as? [String: Any] else {
            let said = (json as? [String: Any])?["message"] as? String
            throw said.map { Failure(message: $0, from: "Relay") } ?? Failure(message: String(localized: "Relay did not answer on \(name)"))
        }
        func side(_ key: String) -> (chain: Int, address: String)? {
            guard let c = (details[key] as? [String: Any])?["currency"] as? [String: Any],
                  let chain = c["chainId"] as? Int, let a = c["address"] as? String else { return nil }
            return (chain, a)
        }
        let recipient = details["recipient"] as? String ?? ""
        guard WalletWatch.sameAddress(recipient, account),
              let input = side("currencyIn"), input.chain == chainId, input.address.caseInsensitiveCompare(currency) == .orderedSame,
              let output = side("currencyOut"), output.chain == target.chainId,
              output.address.caseInsensitiveCompare(target.address) == .orderedSame else {
            throw Failure(message: String(localized: "Relay asked for something other than this swap, so nothing was signed"))
        }
        // An ERC-20 route hands back the transfer it expects: it must be the
        // one this phone would write.
        if let item = (step["items"] as? [[String: Any]])?.first, let data = item["data"] as? [String: Any],
           let calldata = data["data"] as? String, calldata != "0x" {
            let expected = YourAccountOp.transfer(to: address, amount: amount).map(SafeABI.hex)
            guard let to = data["to"] as? String, to.caseInsensitiveCompare(currency) == .orderedSame,
                  calldata.lowercased() == expected?.lowercased() else {
                throw Failure(message: String(localized: "Relay asked for something other than this swap, so nothing was signed"))
            }
        }
        func usd(_ any: Any?) -> Double? { (any as? String).flatMap(Double.init) ?? (any as? Double) }
        let out = usd((details["currencyOut"] as? [String: Any])?["amountUsd"])
        let fees = o["fees"] as? [String: Any]
        let fee = ["gas", "relayer"].compactMap { usd((fees?[$0] as? [String: Any])?["amountUsd"]) }.reduce(0, +)
        return Deposit(address: address, outUSD: out, feeUSD: fees == nil ? nil : fee, seconds: details["timeEstimate"] as? Int)
    }

    /// Relay's networks (`/chains`), as it lists them.
    static func relayChains() async -> [[String: Any]] {
        let (json, status) = await relay("chains", body: nil)
        guard status == 200 else { return [] }
        return ((json as? [String: Any])?["chains"] as? [[String: Any]]) ?? []
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

    #if DEBUG
    /// `-moveSimulateETH <wei>`: the ETH the simulation pretends the account
    /// holds (a state override in `check`); nil when not asked.
    static var simulatedETH: String? {
        guard let wei = UserDefaults.standard.string(forKey: "moveSimulateETH"), !wei.isEmpty, wei.allSatisfy(\.isNumber) else { return nil }
        return wei
    }
    #endif

    /// One step of a transaction: its calls, and for a swap what it buys and
    /// the least it must pay.
    typealias Step = (calls: [YourAccountOp.Call], swap: (buy: YourAccountOp.Token, minimum: String)?)

    /// What running the calls said (prd §1509 item 1): the verdict Details
    /// draws, what each swap paid (nil for a send), and whether a swap's
    /// route paid less than its minimum.
    struct Simulated: Equatable, Sendable {
        var checked: YourAccountPreview.Checked
        var paid: [String?] = []
        var paysLess = false
    }

    /// **WHAT COMES BACK, PROVEN BEFORE FACE ID (prd §1440, §1509).** The
    /// account's calls, run in order by the network's own node
    /// (`eth_simulateV1`, as the account, against the real state), with the
    /// bought token's balance read around each swap. Never throws: a node
    /// that will not simulate is `notChecked`, a refused call `fails` with
    /// the token it was (`symbols`, by contract) and the node's reason.
    /// Measured 2026-10-24: every node of all three networks answers it, a
    /// revert as the call's `status 0x0` with `error.data`, a value the
    /// account lacks as a refusal of the whole block (-38014).
    static func check(_ net: Network, account: String, approvals: [YourAccountOp.Call], steps: [Step],
                      symbols: [String: String] = [:]) async -> Simulated {
        func json(_ c: YourAccountOp.Call) -> [String: Any] {
            // The value word as a JSON-RPC quantity: hex, no leading zeros.
            let digits = SafeABI.hex(c.value).dropFirst(2).drop { $0 == "0" }
            return ["from": account, "to": c.to, "value": "0x" + (digits.isEmpty ? "0" : String(digits)),
                    "data": SafeABI.hex(c.data)]
        }
        var calls: [[String: Any]] = approvals.map(json)
        // Which of the transaction's own calls each simulated call is (the
        // balance reads around a swap are none).
        var own: [Int?] = approvals.indices.map { $0 }
        var count = approvals.count
        var reads: [(before: Int, after: Int, minimum: String)?] = []
        for step in steps {
            if let swap = step.swap {
                let before = calls.count
                calls.append(balanceCall(swap.buy, of: account)); own.append(nil)
                for c in step.calls { calls.append(json(c)); own.append(count); count += 1 }
                let after = calls.count
                calls.append(balanceCall(swap.buy, of: account)); own.append(nil)
                reads.append((before, after, swap.minimum))
            } else {
                for c in step.calls { calls.append(json(c)); own.append(count); count += 1 }
                reads.append(nil)
            }
        }
        var block: [String: Any] = ["calls": calls]
        #if DEBUG
        // `-moveSimulateETH <wei>` (DEBUG, prd §1542): the simulation runs as
        // if the account held this much ETH, so a swap's preview can be seen
        // passing on a simulator with no funded account. A state override
        // only: nothing is held, and `transact` refuses to sign under it.
        if let wei = Self.simulatedETH, let word = SafeABI.word(uint256: wei) {
            let digits = SafeABI.hex(word).dropFirst(2).drop { $0 == "0" }
            block["stateOverrides"] = [account: ["balance": "0x" + (digits.isEmpty ? "0" : String(digits))]]
        }
        #endif
        let params: [Any] = [["blockStateCalls": [block], "validation": false], "latest"]
        let answer: Any
        do {
            answer = try await rpc(net, "eth_simulateV1", params)
        } catch let failure as Failure {
            // A value the account does not hold refuses the whole block.
            if failure.message.lowercased().contains("insufficient funds") {
                return Simulated(checked: .fails(call: nil, token: "ETH", reason: failure.message))
            }
            return Simulated(checked: .notChecked)
        } catch {
            return Simulated(checked: .notChecked)
        }
        guard let blocks = answer as? [[String: Any]],
              let results = blocks.first?["calls"] as? [[String: Any]], results.count == calls.count else {
            return Simulated(checked: .notChecked)
        }
        if let bad = results.firstIndex(where: { ($0["status"] as? String) != "0x1" }) {
            let error = results[bad]["error"] as? [String: Any]
            let target = (calls[bad]["to"] as? String)?.lowercased() ?? ""
            let reason = YourAccountPreview.revertReason(error?["data"] as? String) ?? (error?["message"] as? String)
            return Simulated(checked: .fails(call: own[bad], token: symbols[target], reason: reason))
        }
        func value(_ i: Int) -> String? {
            (results[i]["returnData"] as? String).flatMap { YourAccountOp.decimal(hexQuantity: String($0.prefix(66))) }
        }
        var paid: [String?] = []
        var least: (String, YourAccountOp.Token)?
        for (n, read) in reads.enumerated() {
            guard let read else { paid.append(nil); continue }
            guard let before = value(read.before), let after = value(read.after) else {
                return Simulated(checked: .notChecked)
            }
            let got = YourAccountOp.difference(after, before)
            guard YourAccountOp.atMost(read.minimum, got) else {
                return Simulated(checked: .fails(call: nil, token: nil, reason: String(localized: "Pays less than the exchange quoted")),
                                 paysLess: true)
            }
            paid.append(got)
            if let buy = steps[n].swap?.buy {
                least = (least.map { YourAccountOp.sum($0.0, read.minimum) } ?? read.minimum, buy)
            }
        }
        if let least { return Simulated(checked: .returnsAtLeast(least.0, least.1), paid: paid) }
        return Simulated(checked: .lands, paid: paid)
    }

    /// The simulation as signing reads it: a swap is refused unless it was
    /// checked and pays its minimum (§1440); a send the node refuses is
    /// refused, and one no node would check goes as before (prd §1509).
    static func require(_ s: Simulated, on net: Network, swaps: Bool) throws {
        switch s.checked {
        case .notChecked:
            if swaps { throw Failure(message: String(localized: "\(net.name) could not check this swap, so nothing was signed")) }
        case .fails:
            if s.paysLess { throw Failure(message: String(localized: "The exchange would pay less than it quoted, so nothing was signed"), settled: true) }
            throw Failure(message: String(localized: "This would fail on \(net.name), so nothing was signed"), settled: true)
        case .lands, .returnsAtLeast:
            break
        }
    }

    /// A swap the page describes: what is sold, for what, on one network.
    struct Swap: Equatable, Identifiable, Sendable {
        var id = UUID()
        let network: Network
        let sell: YourAccountOp.Token
        let buy: YourAccountOp.Token
        let amount: String
        /// The quote the page showed; the pools are asked afresh at signing.
        let quote: YourAccountSwap.Quote
        /// Where what it buys arrives, when that is another network: Across
        /// carries it (prd §1555). Nil for a swap on `network` itself.
        var to: Network? = nil

        /// To another network.
        var crosses: Bool { to.map { $0 != network } ?? false }
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
        /// The round-up's buy did not go with this send — the session key
        /// signed it alone, or no pool would buy — so its change keeps
        /// counting (prd §1545).
        var roundUpWaits = false
        /// A swap to another network it sent (prd §1555), as the Wallet keeps it.
        var crossing: YourAccountAcross.Crossing? = nil
        /// Round-ups into your private balance rode this operation (prd §1567).
        var rode = false
    }

    /// One transaction, assembled and simulated, everything but its gas and
    /// its signature (prd §1509): what Details previews and what Face ID
    /// signs are built by this one function, so they cannot drift apart.
    struct Assembled {
        let items: [Item]
        let net: Network
        let account: String
        /// Every call in order: approvals, the steps, a renewal, the keys
        /// chosen at Create. The key change is added by the operation.
        var calls: [YourAccountOp.Call]
        /// The same, in words, the key change last (`YourAccountPreview`).
        var words: [YourAccountPreview.Step]
        let payments: [YourAccountOp.Payment]
        let approvals: [YourAccountPreview.Approval]
        /// What each swap sells and where, from the quote signed.
        let sold: [YourAccountPreview.Sold]
        let steps: [Step]
        var simulated: Simulated
        let deployed: Bool
        let renewed: YourAccount7579.Plan?
        let setupPlan: YourAccount7579.Plan?
        /// " · and your keys" when the operation opens the account.
        let reasonTail: String
        let signerIndex: Int
        let next: Int
        let nextKey: (x: [UInt8], y: [UInt8])
        let signer: Signer
        /// A round-up's buy that no pool would make: the send goes, and the
        /// change keeps counting (prd §1545).
        var roundUpWaits = false
        /// A swap to another network (prd §1555): the note the Wallet keeps,
        /// and whether ETH was proven to arrive as ETH (nil: not asked, or
        /// the node would not simulate).
        var crossing: YourAccountAcross.Crossing? = nil
        var arrives: Bool? = nil

        /// Whether signing must have a simulation that answered: any swap,
        /// and any crossing.
        var mustCheck: Bool { steps.contains { $0.swap != nil } || crossing != nil }
    }

    /// **EVERY SEND AND SWAP IN ONE OPERATION (prd §1436, §1539).** Each swap
    /// is quoted afresh off the pools and its calls checked (`YourAccountSwap.
    /// checked`: the network's pinned routers, exactly the amount sold);
    /// approvals go first, once per token for the sum; then the sends and
    /// swaps in the page's order and the key change. Before Face ID the whole
    /// of it is simulated (sends too since §1509) and refused unless every
    /// call succeeds and every swap pays its minimum. The pool settles in the
    /// same transaction, so a landed operation is a finished swap.
    ///
    /// **WHAT DETAILS SHOWED IS WHAT IS SIGNED (prd §1509).** A preview of
    /// these same items, made under a minute ago on the same route, is signed
    /// as it stands — its quotes, its gas, its hash — after its simulation is
    /// run once more; anything older is assembled and priced afresh.
    static func transact(_ items: [Item], reason: String, dryRun: Bool = false, coSigner: CoSigner? = nil,
                         roundUp: RoundUpBuy? = nil, renew: Bool = false,
                         ride: [(to: String, data: String, value: String)] = [],
                         report: @escaping @Sendable (String) -> Void = { _ in },
                         stage: @escaping @Sendable (Stage) async -> Void) async throws -> Transacted {
        guard let net = items.first?.network, items.allSatisfy({ $0.network == net }) else {
            throw Failure(message: String(localized: "One transaction sends on one network"))
        }
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        #if DEBUG
        if simulatedETH != nil {
            throw Failure(message: "A pretended balance (-moveSimulateETH) signs nothing")
        }
        #endif
        await stage(.preparing)
        let route: Prepared.Signs = coSigner == nil ? .owner : .bothKeys
        // A riding deposit makes a different operation from the preview's.
        let kept = ride.isEmpty ? await Prepared.take(items, roundUp: roundUp, route: route) : nil
        var a: Assembled
        var approvalCount = 0
        // **THE PREVIEW'S RECHECK RUNS BESIDE THE OPERATION'S OWN READS (prd
        // §1601)**, and Face ID waits for it: nothing is signed that the
        // simulation refused, and nothing waits on it that need not.
        var recheck: Task<Simulated, Never>?
        if let kept, let held = kept.assembled {
            approvalCount = held.approvalCount
            // The preview's own calls, checked once more against the state now.
            recheck = Task {
                await check(net, account: account, approvals: Array(held.calls.prefix(held.approvalCount)),
                            steps: held.steps, symbols: held.symbols)
            }
            a = held.assembled
            report("signing the preview from \(Int(Date().timeIntervalSince(kept.made)))s ago")
        } else {
            let parts = try await assemble(items, account: account, roundUp: roundUp, renew: renew && coSigner != nil, report: report)
            a = parts.assembled
            approvalCount = parts.approvalCount
            try require(a.simulated, on: net, swaps: a.mustCheck)
        }
        // **ROUND-UPS INTO YOUR PRIVATE BALANCE RIDE THIS OPERATION (prd
        // §1567).** The batch's calls (the keystore the first time, USDC's
        // approval, ppUSDC's router) join the send's in ONE Face ID
        // operation, and the whole of it is simulated again with them before
        // anything is signed. **A RIDE THAT DOES NOT CHECK OUT IS DROPPED,
        // NEVER THE SEND (the review of 2026-10-26, finding 5):** the send
        // itself already passed its own simulation above, so a ride the node
        // refuses, or would not simulate, or could not be written, leaves
        // the operation as it was — the send goes alone and the change keeps
        // counting (`Transacted.rode` false).
        var rode = false
        if !ride.isEmpty {
            switch await Self.rideVerdict(ride, check: { extra in
                await check(net, account: account, approvals: Array(a.calls.prefix(approvalCount)),
                            steps: a.steps + [(calls: Array(a.calls.dropFirst(approvalCount + a.steps.reduce(0) { $0 + $1.calls.count })) + extra, swap: nil)])
            }) {
            case .rides(let extra):
                a.calls += extra
                rode = true
                report("a private round-up rides: \(extra.count) calls")
            case .dropped(let why):
                report("the private round-up was dropped (\(why)); the send goes alone")
                NSLog("roundUpsPrivate| ride dropped | %@ | the send goes alone", why)
            }
        }
        // ETH sent to another network must be proven to arrive as ETH: the
        // handler's message run on the receiving network (prd §1555).
        // So must a swap on arrival: the handler and the swap run there (prd §1566).
        if let crossing = a.crossing, a.sold.contains(where: { $0.across.map(YourAccountAcross.viaHandler) == true }),
           a.arrives != true {
            throw Failure(message: String(localized: "Could not check that \(crossing.symbol) arrives on \(YourAccountAcross.networkName(crossing.to)), so nothing was signed"))
        }
        let swaps = a.steps.compactMap(\.swap)
        // Kept before Face ID, and only once the recheck has passed (prd
        // §1601: a kept preview's recheck now runs beside the reads, and a
        // refused one must leave no crossing or buy behind).
        let crossingNow = a.crossing, waits = a.roundUpWaits
        let keepBeforeFaceID: @Sendable () -> Void = {
            // The crossing is kept before Face ID, so the Wallet shows it however
            // the app is left; it gets its transaction once it lands.
            if let crossing = crossingNow, !dryRun { YourAccountAcross.note(crossing) }
            // An exchange buy is known later by its own transaction (prd §1545):
            // kept before Face ID, so a send that lands while the app is away
            // still reads as the buy.
            if let roundUp, !dryRun, !waits, roundUp.target.onExchanges(from: net.chainId) {
                RoundUps.noteSwapBuy(account: account, network: YourAccountOp.appName(net) ?? net.name, dollar: net.dollar, units: roundUp.units,
                                     target: roundUp.target)
            }
        }
        report("simulated: \(a.simulated.paid.compactMap { $0 }.joined(separator: ", "))")

        // What the bought tokens hold now, to measure what landed: read at
        // once, beside the operation's reads, and in hand before Face ID.
        var bought: [YourAccountOp.Token] = []
        for buy in swaps.map(\.buy) where !bought.contains(where: { ($0.contract ?? "") == (buy.contract ?? "") }) { bought.append(buy) }
        let beforeRead = Task {
            await withTaskGroup(of: (String, String).self) { group in
                for buy in bought { group.addTask { (buy.contract ?? "", await balance(net, buy, of: account) ?? "0") } }
                var out: [String: String] = [:]
                for await (key, units) in group { out[key] = units }
                return out
            }
        }
        report("account=\(account) deployed=\(a.deployed) signer=key\(a.signerIndex) next=key\(a.next) swaps=\(swaps.count)")
        let mustCheck = a.mustCheck
        let recheckTask = recheck
        // Done with by Face ID; a send refused before it leaves them asking nothing.
        defer {
            recheckTask?.cancel()
            beforeRead.cancel()
        }
        let outcome = try await operate(net, account: account, deployed: a.deployed, calls: a.calls,
                                        rotateTo: a.nextKey, payments: a.payments, signer: a.signer, coSigner: coSigner,
                                        reason: reason + a.reasonTail, dryRun: dryRun, pinned: kept?.op,
                                        beforeSigning: {
                                            if let recheckTask { try require(await recheckTask.value, on: net, swaps: mustCheck) }
                                            _ = await beforeRead.value
                                            keepBeforeFaceID()
                                        },
                                        report: report, stage: stage)
        if let recheck { a.simulated = await recheck.value }
        let before = await beforeRead.value
        if let renewed = a.renewed, case .landed = outcome { savePlan(renewed, on: net) }
        if let setupPlan = a.setupPlan, case .landed = outcome { savePlan(setupPlan, on: net) }
        let sent = Sent(outcome: await settle(outcome, net, account, next: a.next, x: a.nextKey.x), network: net)
        var crossing = a.crossing
        if var c = crossing, case .landed(let tx, _) = sent.outcome, let tx {
            c.tx = tx
            YourAccountAcross.update(c.id) { $0.tx = tx }
            crossing = c
        }
        guard case .landed = sent.outcome, !swaps.isEmpty else {
            return Transacted(sent: sent, bought: a.simulated.paid, roundUpWaits: a.roundUpWaits, crossing: crossing, rode: rode)
        }
        // A token bought by one swap alone: what actually arrived, every
        // token read at once.
        var paid = a.simulated.paid
        let alone = a.steps.enumerated().compactMap { i, step -> (Int, YourAccountOp.Token)? in
            guard let swap = step.swap, swaps.filter({ ($0.buy.contract ?? "") == (swap.buy.contract ?? "") }).count == 1 else { return nil }
            return (i, swap.buy)
        }
        let now = await withTaskGroup(of: (Int, String?).self) { group in
            for (i, token) in alone { group.addTask { (i, await balance(net, token, of: account)) } }
            var out: [Int: String] = [:]
            for await (i, units) in group { if let units { out[i] = units } }
            return out
        }
        for (i, token) in alone {
            guard let then = before[token.contract ?? ""], let held = now[i] else { continue }
            let arrived = YourAccountOp.difference(held, then)
            if arrived != "0" { paid[i] = arrived }
        }
        return Transacted(sent: sent, bought: paid, roundUpWaits: a.roundUpWaits, crossing: crossing, rode: rode)
    }

    /// Whether a round-up ride joins the operation (finding 5): its calls
    /// written, then the whole simulated with them (`check`); the verdict is
    /// `RoundUps.rideVerdict`'s, so a refusal or an unchecked ride drops it.
    enum Ride { case rides([YourAccountOp.Call]), dropped(String) }

    static func rideVerdict(_ ride: [(to: String, data: String, value: String)],
                            check: ([YourAccountOp.Call]) async -> Simulated) async -> Ride {
        var extra: [YourAccountOp.Call] = []
        for c in ride {
            guard SafeABI.word(address: c.to) != nil, let data = SafeABI.hexBytes(c.data),
                  let value = SafeABI.word(uint256: c.value) else {
                return .dropped(RoundUps.rideVerdict(written: false, checked: .notChecked).why ?? "not written")
            }
            extra.append(.init(operation: 0, to: c.to, value: value, data: data))
        }
        let simulated = await check(extra)
        let checked: RoundUps.RideCheck = switch simulated.checked {
        case .lands, .returnsAtLeast: simulated.paysLess ? .fails : .lands
        case .fails: .fails
        case .notChecked: .notChecked
        }
        let verdict = RoundUps.rideVerdict(written: true, checked: checked)
        if let why = verdict.why { return .dropped(why) }
        return .rides(extra)
    }

    /// What `assemble` hands back beside the transaction: how many of its
    /// calls are approvals, and which token each contract is, so a kept
    /// preview can be simulated again exactly.
    struct AssembledParts {
        let assembled: Assembled
        let approvalCount: Int
        let symbols: [String: String]
        var calls: [YourAccountOp.Call] { assembled.calls }
        var steps: [Step] { assembled.steps }
    }

    /// The calls of one transaction, simulated, with its words. Every swap
    /// is quoted afresh off the pools, for the preview as for signing, so a kept
    /// preview's quotes are never older than the preview (`Prepared.lifetime`).
    static func assemble(_ items: [Item], account: String, roundUp: RoundUpBuy?, renew: Bool,
                         report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> AssembledParts {
        guard let net = items.first?.network else {
            throw Failure(message: String(localized: "One transaction sends on one network"))
        }
        typealias Words = YourAccountPreview
        func figure(_ units: String, _ token: YourAccountOp.Token) -> String { YourAccountOp.spoken(units, decimals: token.decimals) }
        var payments: [YourAccountOp.Payment] = []
        var approvals: [(token: String, spender: String, amount: String)] = []
        var steps: [Step] = []
        var stepWords: [Words.Step] = []
        var symbols: [String: String] = [:]
        var sold: [YourAccountPreview.Sold] = []
        var crossing: YourAccountAcross.Crossing?
        var arrives: Bool?
        for item in items {
            switch item {
            case .swap(let s) where s.crosses:
                // **TO ANOTHER NETWORK, THROUGH ACROSS (prd §1555).** Alone in
                // its transaction (Move keeps it so), so the Wallet can show
                // the whole transaction as the one crossing.
                guard items.count == 1, let dest = s.to else {
                    throw Failure(message: String(localized: "A swap to another network goes alone"))
                }
                let quote = try await crossQuote(net, to: dest, sell: s.sell, buy: s.buy, amount: s.amount, account: account)
                guard let leg = quote.across else { throw Failure(message: String(localized: "This swap could not be written")) }
                let crossCount = leg.asset == .eth ? 1 : 2
                guard quote.calls.count >= crossCount else { throw Failure(message: String(localized: "This swap could not be written")) }
                let swapCalls = Array(quote.calls.dropLast(crossCount))
                let crossCalls = Array(quote.calls.suffix(crossCount))
                let bridged = YourAccountAcross.token(leg.asset, on: net)
                if let route = quote.route {
                    // Swapped first into what crosses, by the pools; only the
                    // swap's minimum crosses, and the simulation holds the
                    // swap to it.
                    let first = YourAccountSwap.Quote(sellAmount: s.amount, buyAmount: leg.inputAmount, minimumBuy: leg.inputAmount,
                                                      route: route, calls: swapCalls)
                    guard let checked = YourAccountSwap.checked(first, sell: s.sell, amount: s.amount, chainId: net.chainId) else {
                        throw Failure(message: String(localized: "This swap could not be written"))
                    }
                    let calls = checked.calls.compactMap(YourAccountSwap.accountCall)
                    guard calls.count == checked.calls.count else { throw Failure(message: String(localized: "This swap could not be written")) }
                    approvals += checked.approvals
                    steps.append((calls, (bridged, leg.inputAmount)))
                    stepWords.append(Words.swap(figure(s.amount, s.sell), s.sell.symbol, atLeast: figure(leg.inputAmount, bridged),
                                                bridged.symbol, on: route.venue.exchange))
                } else if !swapCalls.isEmpty || s.sell != bridged {
                    throw Failure(message: String(localized: "This swap could not be written"))
                }
                guard let checked = YourAccountAcross.checked(crossCalls, leg: leg, account: account,
                                                              now: Int(Date().timeIntervalSince1970)) else {
                    throw Failure(message: String(localized: "Across asked for something other than this swap, so nothing was signed"))
                }
                let calls = checked.calls.compactMap(YourAccountSwap.accountCall)
                guard calls.count == checked.calls.count else { throw Failure(message: String(localized: "This swap could not be written")) }
                approvals += checked.approvals
                steps.append((calls, nil))
                // What Across pays there: the token bought, or for a swap on
                // arrival (prd §1566) the bridged token the handler swaps.
                let landing = YourAccountAcross.token(leg.asset, on: dest)
                let lands = leg.swap == nil ? s.buy : landing
                stepWords.append(Words.crossing(figure(leg.inputAmount, bridged), bridged.symbol, to: dest.name,
                                                arrives: figure(leg.outputAmount, lands), lands.symbol, back: net.name))
                if let there = leg.swap {
                    stepWords.append(Words.swap(figure(leg.outputAmount, landing), landing.symbol,
                                                atLeast: figure(there.minimum, there.buy), there.buy.symbol,
                                                on: String(localized: "\(there.route.venue.exchange) on \(dest.name)")))
                }
                sold.append(YourAccountPreview.Sold(token: s.sell, amount: s.amount, route: quote.route, across: leg))
                if let c = s.sell.contract { symbols[c.lowercased()] = s.sell.symbol }
                if let c = bridged.contract { symbols[c.lowercased()] = bridged.symbol }
                payments.append(.init(network: net, token: s.sell, amount: s.amount,
                                      to: YourAccountAcross.spoke(net.chainId) ?? account, toName: "Across"))
                let refund = leg.asset == .eth ? (contract: YourAccountSwap.book(net.chainId)?.weth ?? "", symbol: "WETH")
                                               : (contract: net.dollar.lowercased(), symbol: net.dollarSymbol)
                // A swap on arrival (prd §1566): its minimum until the arrival
                // is met, and the bridged token, exactly, if it falls back.
                let there = leg.swap
                let fallback = YourAccountAcross.bridged(leg.asset, on: dest.chainId)
                crossing = YourAccountAcross.Crossing(
                    id: UUID().uuidString, account: account.lowercased(), from: net.chainId, to: dest.chainId,
                    sold: "\(figure(s.amount, s.sell)) \(s.sell.symbol)", symbol: s.buy.symbol,
                    contract: s.buy.contract?.lowercased(), decimals: s.buy.decimals, outputUnits: there?.minimum ?? leg.outputAmount,
                    refundContract: refund.contract, refundSymbol: refund.symbol, inputUnits: leg.inputAmount,
                    fillDeadline: leg.fillDeadline, at: .now,
                    atLeast: there == nil ? nil : true, fallbackContract: there == nil ? nil : fallback,
                    fallbackSymbol: there == nil ? nil : (leg.asset == .eth ? "WETH" : landing.symbol),
                    fallbackDecimals: there == nil ? nil : landing.decimals, fallbackUnits: there == nil ? nil : leg.outputAmount,
                    refundDecimals: bridged.decimals == s.buy.decimals ? nil : bridged.decimals)
                // ETH's unwrap and a swap on arrival run on the other network:
                // proven there before Face ID (prd §1555, §1566).
                if YourAccountAcross.viaHandler(leg) { arrives = await arrivalCheck(dest, leg: leg, account: account) }
                report("across: \(leg.inputAmount) \(bridged.symbol) \(net.name)→\(dest.name) out=\(leg.outputAmount) fee=\(leg.feePips)pips arrives=\(arrives.map { String($0) } ?? "-")")
            case .send(let p):
                guard let call = YourAccountOp.call(for: p) else {
                    throw Failure(message: String(localized: "This send could not be written"))
                }
                payments.append(p)
                steps.append(([call], nil))
                stepWords.append(Words.send(figure(p.amount, p.token), p.token.symbol, to: p.toName ?? Words.short(p.to)))
                if let c = p.token.contract { symbols[c.lowercased()] = p.token.symbol }
            case .swap(let s) where YourAccountSwap.wrap(sell: s.sell, buy: s.buy, chainId: net.chainId) != nil:
                // **WETH AND ETH, ONE FOR ONE (prd §1559).** One call to the
                // network's WETH, checked; the simulation holds it to exactly
                // what is sold coming back.
                let quote = try await swapQuote(net, sell: s.sell, buy: s.buy, amount: s.amount, account: account)
                guard let w = quote.wrap,
                      let checked = YourAccountSwap.checkedWrap(quote, sell: s.sell, buy: s.buy, amount: s.amount,
                                                                account: account, chainId: net.chainId) else {
                    throw Failure(message: String(localized: "This swap could not be written"))
                }
                let calls = checked.compactMap(YourAccountSwap.accountCall)
                guard calls.count == checked.count else { throw Failure(message: String(localized: "This swap could not be written")) }
                steps.append((calls, (s.buy, s.amount)))
                sold.append(YourAccountPreview.Sold(token: s.sell, amount: s.amount, route: nil, wrap: w))
                stepWords.append(Words.wrap(w, figure(s.amount, s.sell)))
                if let c = s.sell.contract { symbols[c.lowercased()] = s.sell.symbol }
                if let c = s.buy.contract { symbols[c.lowercased()] = s.buy.symbol }
                payments.append(.init(network: net, token: s.sell, amount: s.amount, to: checked[0].to, toName: nil))
            case .swap(let s):
                let quote = try await swapQuote(net, sell: s.sell, buy: s.buy, amount: s.amount, account: account)
                guard let checked = YourAccountSwap.checked(quote, sell: s.sell, amount: s.amount, chainId: net.chainId) else {
                    throw Failure(message: String(localized: "This swap could not be written"))
                }
                let calls = checked.calls.compactMap(YourAccountSwap.accountCall)
                guard calls.count == checked.calls.count else {
                    throw Failure(message: String(localized: "This swap could not be written"))
                }
                approvals += checked.approvals
                steps.append((calls, (s.buy, quote.minimumBuy)))
                sold.append(YourAccountPreview.Sold(token: s.sell, amount: s.amount, route: quote.route))
                stepWords.append(Words.swap(figure(s.amount, s.sell), s.sell.symbol,
                                            atLeast: figure(quote.minimumBuy, s.buy), s.buy.symbol,
                                            on: quote.exchange ?? "Uniswap"))
                if let c = s.sell.contract { symbols[c.lowercased()] = s.sell.symbol }
                // What leaves the account, for the balance check before any prompt.
                payments.append(.init(network: net, token: s.sell, amount: s.amount,
                                      to: quote.route?.venue.router ?? account, toName: nil))
            }
        }
        // Round-ups (prd §1452, §1545): what the change has reached, last,
        // its dollars counted with the sends' before any prompt. A token on
        // this network is bought on the exchanges, as Swap buys: quoted off
        // the pools, its calls checked, its approval summed with the rest and
        // its minimum held by the simulation. A token on another network is a
        // transfer to Relay's deposit address for the route. When no pool
        // will buy it, the send goes and the change keeps counting.
        var roundUpWaits = false
        if let roundUp {
            let dollar = YourAccountOp.dollar(on: net)
            symbols[net.dollar.lowercased()] = dollar.symbol
            if roundUp.target.onExchanges(from: net.chainId) {
                let buy = YourAccountOp.Token(symbol: roundUp.target.symbol, decimals: roundUp.target.decimals,
                                              contract: roundUp.target.contract)
                do {
                    let quote = try await swapQuote(net, sell: dollar, buy: buy, amount: roundUp.units, account: account)
                    guard let checked = YourAccountSwap.checked(quote, sell: dollar, amount: roundUp.units, chainId: net.chainId)
                    else { throw Failure(message: String(localized: "This swap could not be written")) }
                    let calls = checked.calls.compactMap(YourAccountSwap.accountCall)
                    guard calls.count == checked.calls.count else {
                        throw Failure(message: String(localized: "This swap could not be written"))
                    }
                    approvals += checked.approvals
                    steps.append((calls, (buy, quote.minimumBuy)))
                    sold.append(YourAccountPreview.Sold(token: dollar, amount: roundUp.units, route: quote.route))
                    stepWords.append(Words.roundUpSwap(figure(roundUp.units, dollar), dollar.symbol,
                                                       atLeast: figure(quote.minimumBuy, buy), buy.symbol,
                                                       on: quote.exchange ?? "Uniswap"))
                    payments.append(.init(network: net, token: dollar, amount: roundUp.units,
                                          to: quote.route?.venue.router ?? account, toName: nil))
                    report("roundUp: \(roundUp.units) swapped for \(roundUp.target.symbol) on \(quote.exchange ?? "?")")
                } catch let failure as Failure {
                    roundUpWaits = true
                    stepWords.append(Words.Step(words: String(localized: "Keeps the round-ups for your next send"),
                                                detail: failure.message))
                    report("roundUp: waits, \(failure.message)")
                }
            } else {
                let deposit = try await depositAddress(from: net, currency: net.dollar, to: roundUp.target,
                                                       amount: roundUp.units, account: account)
                // So the landed send to it reads as this buy, never as spending (prd §1523).
                RoundUps.noteDeposit(deposit.address, target: roundUp.target)
                let payment = YourAccountOp.Payment(network: net, token: dollar, amount: roundUp.units,
                                                    to: deposit.address, toName: "Relay")
                guard let call = YourAccountOp.call(for: payment) else {
                    throw Failure(message: String(localized: "This send could not be written"))
                }
                payments.append(payment)
                steps.append(([call], nil))
                stepWords.append(Words.roundUp(figure(roundUp.units, dollar), dollar.symbol,
                                               buys: roundUp.target.symbol, on: roundUp.target.network))
                report("roundUp: \(roundUp.units) to \(deposit.address) for \(roundUp.target.symbol) on \(roundUp.target.network)")
            }
        }
        guard let approvalCalls = YourAccountSwap.approvalCalls(approvals) else {
            throw Failure(message: String(localized: "This swap could not be written"))
        }
        // The approvals in words, once per token for the sum, as they are called.
        var approved: [Words.Approval] = []
        for call in approvalCalls {
            let contract = call.to.lowercased()
            let token = sold.first { $0.token.contract?.lowercased() == contract }?.token
                // A dollar a swap bought first, crossing (prd §1555).
                ?? (contract == net.dollar.lowercased() ? YourAccountOp.dollar(on: net) : nil)
            let units = SafeCalldata.decimal(Array(call.data.suffix(32)))
            // The spender is the router, named by its exchange, or Across's
            // SpokePool (prd §1555).
            let spenderAddress = SafeABI.hex(Array(call.data[16..<36]))
            let spender = YourAccountSwap.exchange(ofRouter: spenderAddress)
                ?? (YourAccountAcross.isSpoke(spenderAddress) ? "Across" : YourAccount.short(spenderAddress))
            approved.append(Words.Approval(figure: token.map { figure(units, $0) } ?? units,
                                           symbol: token?.symbol ?? Words.short(call.to), spender: spender))
        }
        var calls = approvalCalls + steps.flatMap(\.calls)
        var words = approved.map { Words.approve($0.figure, $0.symbol, to: $0.spender) } + stepWords
        // The spend limit renewed with it (prd §1455): only where both keys
        // sign anyway, after everything else.
        var renewed: YourAccount7579.Plan?
        if renew, let r = try await renewal(net, account) {
            calls += r.calls
            renewed = r.plan
            words.append(Words.renewsLimit(periods: r.plan.windows.count))
            report("renewing the spend limit: \(r.plan.windows.count) periods")
        }
        let simulated = await check(net, account: account, approvals: approvalCalls, steps: steps, symbols: symbols)

        let deployed = try await isDeployed(net, account)
        // The keys chosen at Create (prd §1457): with the operation that
        // opens the account on this network, after everything it sends.
        var tail = ""
        var setupPlan: YourAccount7579.Plan?
        if !deployed { words.append(Words.opens(network: net.name)) }
        if !deployed, let setup = try await setupCalls(net, account) {
            calls += setup.calls
            setupPlan = setup.plan
            tail = " · " + String(localized: "and your keys")
            if YourAccountRecovery.publicKey(for: account) != nil { words.append(Words.addsRecovery) }
            if YourAccountSetup.choice(for: account)?.signer != nil { words.append(Words.addsSigner) }
            if let plan = setup.plan { words.append(Words.setsLimit(periods: plan.windows.count)) }
            report("setup: \(setup.calls.count) calls, limit \(setup.plan.map { "\($0.windows.count) periods" } ?? "none")")
        }
        let (signerIndex, signer) = try await deviceSigner(net, account, deployed: deployed)
        let next = try YourAccountKey.nextKey(after: signerIndex)
        guard let nextKey = YourAccountKey.publicKey(next) else {
            throw Failure(message: String(localized: "This send could not be written"))
        }
        words.append(Words.rotate(to: next))
        let assembled = Assembled(items: items, net: net, account: account, calls: calls, words: words,
                                  payments: payments, approvals: approved, sold: sold, steps: steps, simulated: simulated,
                                  deployed: deployed, renewed: renewed, setupPlan: setupPlan, reasonTail: tail,
                                  signerIndex: signerIndex, next: next, nextKey: nextKey, signer: signer,
                                  roundUpWaits: roundUpWaits, crossing: crossing, arrives: arrives)
        return AssembledParts(assembled: assembled, approvalCount: approvalCalls.count, symbols: symbols)
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

    // MARK: - Private money's contract calls (prd §1563)

    /// **YOUR ACCOUNT SENDS PRIVATE MONEY'S CALLS ON ETHEREUM.** The keystore
    /// registration (the account is the owner of its private account), a
    /// yield deposit (a token's approval, then the router), or Take it back
    /// (the ragequit, which the pool lets only the owner send, then the zap
    /// that turns the shares back into the token): each list in ONE
    /// operation, signed with Face ID, the key change with it. Before Face
    /// ID the calls run against the real state as the account
    /// (`eth_simulateV1`, as `check` runs every send) and nothing is signed
    /// unless every call succeeds — a node that will not simulate signs
    /// nothing either. `value` is decimal wei.
    static func privateCalls(_ list: [(to: String, data: String, value: String)], on net: Network, reason: String,
                             stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent {
        guard let account = YourAccountKey.address else {
            throw Failure(message: String(localized: "There is no account on this iPhone"))
        }
        var calls: [YourAccountOp.Call] = []
        for c in list {
            guard SafeABI.word(address: c.to) != nil, let data = SafeABI.hexBytes(c.data),
                  let value = SafeABI.word(uint256: c.value) else {
                throw Failure(message: String(localized: "This send could not be written"))
            }
            calls.append(.init(operation: 0, to: c.to, value: value, data: data))
        }
        guard !calls.isEmpty else { throw Failure(message: String(localized: "This send could not be written")) }
        await stage(.preparing)
        let simulated = await check(net, account: account, approvals: [], steps: [(calls: calls, swap: nil)])
        if case .notChecked = simulated.checked {
            throw Failure(message: String(localized: "\(net.name) could not check this, so nothing was signed"))
        }
        try require(simulated, on: net, swaps: false)
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
                                signer: Signer, coSigner: CoSigner? = nil, reason: String, dryRun: Bool = false,
                                pinned: YourAccountOp.Op? = nil,
                                beforeSigning: @escaping @Sendable () async throws -> Void = {},
                                report: @escaping @Sendable (String) -> Void = { _ in },
                                stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent.Outcome {
        // **EVERY READ BEFORE FACE ID AT ONCE (prd §1601, user: "it should be
        // seamless and lightning fast").** Each is a round trip of a second
        // or more over Tor, and they were asked one after another: the
        // account's contract, its threshold, its nonce, the ETH and the fee
        // deposit, every token sent. None needs another's answer.
        var out: [String: String] = [:]
        for p in payments { out[p.token.contract ?? "", default: "0"] = YourAccountOp.sum(out[p.token.contract ?? "", default: "0"], p.amount) }
        let tokens = dryRun ? [] : payments.map(\.token).filter { $0.contract != nil }.reduce(into: [YourAccountOp.Token]()) { kept, token in
            if !kept.contains(where: { $0.contract!.lowercased() == token.contract!.lowercased() }) { kept.append(token) }
        }
        let given = coSigner
        func entryNow() async throws -> YourAccountOp.Entry { deployed ? try await accountEntry(net, account) : .module4337 }
        func needsSigner() async throws -> Bool { given == nil && deployed ? try await threshold(net, account) >= 2 : false }
        func nonceNow() async throws -> UInt64? { deployed ? try await nonce(net, account) : nil }
        func depositNow() async -> String { deployed ? await feeDeposit(net, of: account) : "0" }
        func tokensNow() async -> [String: String?] {
            await withTaskGroup(of: (String, String?).self) { group in
                for token in tokens { group.addTask { (token.contract!, await balance(net, token, of: account)) } }
                var held: [String: String?] = [:]
                for await (contract, units) in group { held[contract] = units }
                return held
            }
        }
        async let entryRead = entryNow()
        async let bothRead = needsSigner()
        async let nonceRead = nonceNow()
        async let ethRead = balance(net, YourAccountOp.eth, of: account)
        async let depositRead = depositNow()
        async let tokenRead = tokensNow()
        // Which contract this account answers through on this network
        // (prd §1447 item 11): the 4337 module, or the 7579 adapter.
        let entry = try await entryRead
        // **BOTH KEYS MEAN BOTH KEYS, FOR EVERYTHING (prd §1456).** With the
        // spend limit on, every operation the owners sign — a recovery key
        // set up, a Signer added, an approval revoked, recovery itself — needs
        // the Signer as well; one that came without it is given it here.
        var coSigner = coSigner
        if coSigner == nil, deployed, entry == .adapter, try await bothRead {
            guard let asked = await defaultCoSigner(net, account) else {
                throw Failure(message: String(localized: "Your Signer signs this too, and none is on \(net.name)"))
            }
            coSigner = asked
        }
        var op = try await build(net, account: account, deployed: deployed, entry: entry, calls: calls, rotateTo: next,
                                 signerOwner: signer.owner, coSignerOwner: coSigner?.owner, pinned: pinned,
                                 knownNonce: try await nonceRead, report: report)
        guard let maxCost = op.maxCost else {
            throw Failure(message: String(localized: "\(net.name) could not price this send"))
        }

        // What the person approves is computed HERE, and the module must
        // agree: a node's word alone never chooses the bytes this phone signs.
        // Asked now, beside the balances still on their way.
        let hash = YourAccountOp.safeOpHash(op, chainId: net.chainId)
        let opNow = op
        func theirsNow() async throws -> [UInt8]? {
            switch entry {
            case .module4337:
                return SafeABI.hexBytes(try await ethCall(net, to: YourAccount.module4337, data: YourAccountOp.operationHashCall(opNow)))
            case .adapter:
                return SafeABI.hexBytes(try await ethCall(net, to: YourAccount7579.adapter, data: YourAccountOp.safeOpCall(opNow)))
                    .flatMap(YourAccountOp.firstBytes)
            }
        }
        async let theirsRead = theirsNow()

        // Enough of each token for everything it sends, and ETH for the most
        // the fee can be too.
        let fee = String(maxCost)
        guard let onHand = await ethRead else {
            throw Failure(message: String(localized: "\(net.name) did not answer"))
        }
        let held = YourAccountOp.sum(onHand, await depositRead)
        report("held=\(held) fee<=\(fee)")
        let ethNeed = YourAccountOp.sum(out[""] ?? "0", fee)
        if !YourAccountOp.atMost(ethNeed, held) {
            let need = YourAccountOp.spoken(ethNeed, decimals: 18)
            guard dryRun else { throw Failure(message: shortOfETH(need: ethNeed, held: held, on: net, deployed: deployed)) }
            report("short: needs \(need) ETH with the fee")
        }
        // Every token the transaction moves, whatever list it came from
        // (prd §1438: the sentence sends and swaps any token you hold).
        let tokensHeld = await tokenRead
        for token in tokens {
            guard let total = out[token.contract!] else { continue }
            guard let tokenHeld = tokensHeld[token.contract!] ?? nil, YourAccountOp.atMost(total, tokenHeld) else {
                throw Failure(message: String(localized: "Not enough \(token.symbol) on \(net.name)"))
            }
        }

        // The adapter's `getSafeOp` zeroes the signature, so its
        // `operationData` is the one the Signer's check needs too.
        let answer = try await theirsRead
        let operationData = entry == .adapter ? answer : nil
        let theirs = entry == .adapter ? answer.map(Keccak256.hash) : answer
        guard theirs == hash, let digest = SafeWebAuthn.signingDigest(challenge: hash) else {
            throw Failure(message: String(localized: "Safe's module disagrees with this iPhone about what is signed, so nothing was"))
        }
        // The caller's own gate (a kept preview's recheck), already asked.
        try await beforeSigning()

        await stage(.signing)
        let feeText = YourAccountOp.spoken(fee, decimals: 18)
        let (r, s) = try await signer.sign(digest, reason + " · " + String(localized: "fee up to \(feeText) ETH"))
        // The exact bytes, checked by Safe's passkey factory before they go:
        // asked while the Signer is (prd §1601), and answered before anything is sent.
        guard let assertion = SafeWebAuthn.signatureBytes(r: r, s: s),
              let check = SafeWebAuthn.isValidSignatureForSignerCalldata(message: hash, signature: assertion, x: signer.x, y: signer.y),
              let checkBytes = SafeABI.hexBytes(check),
              let signature = YourAccountOp.signature(r: r, s: s, owner: signer.owner) else {
            throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
        }
        let factoryCheck = Task { (try? await ethCall(net, to: SafeWebAuthn.factory, data: checkBytes)).map(SafeWebAuthn.isMagic) }
        func passkeyChecks() async throws {
            switch await factoryCheck.value {
            case true?: break
            case false?: throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
            case nil: throw Failure(message: String(localized: "\(net.name) did not answer, so nothing was sent"))
            }
            report("signed: the passkey factory verifies it")
        }
        op.signature = signature
        if let coSigner {
            // The second key, over the same hash; then the Safe itself is
            // asked whether the two together are its signatures.
            guard let typedData = YourAccountOp.safeOpTypedData(op, chainId: net.chainId) else {
                factoryCheck.cancel()
                throw Failure(message: String(localized: "This send could not be written"))
            }
            await stage(.cosigning)
            let ecdsa: [UInt8]
            do { ecdsa = try await coSigner.sign(hash, typedData) } catch { factoryCheck.cancel(); throw error }
            try await passkeyChecks()
            guard let both = YourAccountOp.bothSignatures(r: r, s: s, owner: signer.owner, signer: coSigner.owner, ecdsa: ecdsa) else {
                throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
            }
            // Both keys live on the adapter (prd §1447 item 16).
            guard entry == .adapter, let operationData else {
                throw Failure(message: String(localized: "A spend limit is not available yet"))
            }
            let check = YourAccount.sel("checkSignatures(bytes32,bytes,bytes)") + hash + YourAccount.w(96)
                + YourAccount.w(96 + YourAccount.dynamic(operationData).count)
                + YourAccount.dynamic(operationData) + YourAccount.dynamic(Array(both.dropFirst(12)))
            do {
                _ = try await ethCall(net, to: account, data: check)
            } catch {
                throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
            }
            op.signature = both
            report("cosigned: the account takes both signatures")
        } else {
            try await passkeyChecks()
        }
        if dryRun { return .dryRun }
        return try await submit(op, net, account: account, stage: stage)
    }

    /// The operation `operate` signs, built and priced but unsigned: its
    /// callData with the key change, its nonce (or its creation), a dummy
    /// signature of the right shape, the bundler's estimate. The preview
    /// (prd §1509) prices exactly this.
    static func build(_ net: Network, account: String, deployed: Bool, entry: YourAccountOp.Entry,
                      calls: [YourAccountOp.Call], rotateTo next: (x: [UInt8], y: [UInt8])?,
                      signerOwner: String, coSignerOwner: String?, pinned: YourAccountOp.Op? = nil,
                      knownNonce: UInt64? = nil,
                      report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> YourAccountOp.Op {
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
            if let knownNonce { op.nonce = knownNonce } else { op.nonce = try await nonce(net, account) }
        } else {
            guard let origin = YourAccountKey.origin else {
                throw Failure(message: String(localized: "This send could not be written"))
            }
            op.factory = YourAccount.proxyFactory
            op.factoryData = YourAccountOp.factoryData(x: origin.x, y: origin.y)
        }
        if let coSignerOwner {
            guard let dummy = YourAccountOp.bothSignatures(r: [UInt8](repeating: 0x11, count: 32), s: [UInt8](repeating: 0x22, count: 32),
                                                           owner: signerOwner, signer: coSignerOwner,
                                                           ecdsa: [UInt8](repeating: 0x11, count: 64) + [27]) else {
                throw Failure(message: String(localized: "This send could not be written"))
            }
            op.signature = dummy
        } else {
            op.signature = YourAccountOp.dummySignature(owner: signerOwner)
        }
        // A preview's own gas and fee, when its operation is this one byte
        // for byte: what Details showed, hash included, is what is signed.
        if let pinned, pinned.sender == op.sender, pinned.nonce == op.nonce, pinned.nonceKey == op.nonceKey,
           pinned.factory == op.factory, pinned.factoryData == op.factoryData, pinned.callData == op.callData,
           pinned.entry == op.entry, pinned.signature.count == op.signature.count {
            op.verificationGasLimit = pinned.verificationGasLimit
            op.callGasLimit = pinned.callGasLimit
            op.preVerificationGas = pinned.preVerificationGas
            op.maxFeePerGas = pinned.maxFeePerGas
            op.maxPriorityFeePerGas = pinned.maxPriorityFeePerGas
            report("pinned: the preview's gas and fee")
            return op
        }
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
        // With both keys the dummy's ECDSA half fails first, so the estimate
        // never reaches the passkey's P-256 check the real pair pays for
        // (AA26 on Base, prd §1447 item 16): that check, and more, on top.
        report("gas verification=\(vgl) call=\(cgl) pre=\(pvg)")
        op.verificationGasLimit = coSignerOwner == nil ? vgl : vgl + 100_000
        op.callGasLimit = cgl
        op.preVerificationGas = pvg
        return op
    }

    // MARK: - Following an operation past `.pending` (the review of 2026-10-26)

    /// The operation `submit` sent in this task: its own id (the user
    /// operation's hash) and its nonce, so a caller can tell later whether a
    /// `.pending` operation landed, failed or still may land. Set through
    /// `$following.withValue(Followed()) { … }`.
    final class Followed: @unchecked Sendable {
        var id: String?
        var nonceKey: [UInt8] = []
        var nonce: UInt64 = 0
    }
    @TaskLocal static var following: Followed?

    /// What the chain says of a followed operation now: the bundler's
    /// receipt (`success`, its transaction), else whether the account's
    /// nonce for its key has passed it (some operation took that nonce).
    /// Nil fields: not answered.
    struct Followup: Equatable, Sendable {
        var receipt: Bool?
        var tx: String?
        var nonceMoved: Bool?
    }

    static func followup(id: String, nonceKey: [UInt8], nonce: UInt64, account: String, on net: Network) async -> Followup {
        if let receipt = try? await bundler(net, "eth_getUserOperationReceipt", [id]) as? [String: Any] {
            let tx = (receipt["receipt"] as? [String: Any])?["transactionHash"] as? String
            return Followup(receipt: (receipt["success"] as? Bool) == true, tx: tx, nonceMoved: true)
        }
        guard let now = try? await self.nonce(net, account, key: nonceKey) else { return Followup() }
        return Followup(nonceMoved: now > nonce)
    }

    /// Sends a signed operation and follows it to the chain.
    private static func submit(_ op: YourAccountOp.Op, _ net: Network, account: String,
                               stage: @escaping @Sendable (Stage) async -> Void) async throws -> Sent.Outcome {
        // Followed by its OWN id, known before it goes, so a late or lost
        // answer from the bundler can still be traced to whether it landed.
        let id = SafeABI.hex(YourAccountOp.userOpHash(op, chainId: net.chainId))
        // A caller that must follow the operation past `.pending` (private
        // money's deposits and round-ups, the review of 2026-10-26) keeps it.
        if let followed = following {
            followed.id = id
            followed.nonceKey = op.nonceKey
            followed.nonce = op.nonce
        }
        await stage(.sending)
        var refusal: String?
        do {
            _ = try await bundler(net, "eth_sendUserOperation", [op.json, YourAccount.entryPoint])
        } catch let failure as Failure {
            // The operation itself is invalid (prefund, signature, a revert in
            // validation): it can land nowhere, so the refusal is final now.
            // Anything else — a nonce already used, an outage — is followed.
            if failure.message.range(of: #"AA(2[0-4]|3\d)"#, options: .regularExpression) != nil { throw failure }
            // No bundler answering in time is not a refusal (prd §1601): one
            // may have taken it late, so it is followed the full two minutes.
            if failure.message != "No bundler answered on \(net.name)" { refusal = failure.message }
        }
        await stage(.landing)
        func landed() async -> Bool { ((try? await nonce(net, account, key: op.nonceKey)) ?? op.nonce) > op.nonce }
        // **ASKED EVERY SECOND, BY THE CLOCK (prd §1601).** Base makes a block
        // every two seconds; the receipt was first asked two seconds after the
        // send and then every two seconds plus the round trip. Two minutes in
        // all, as before, and a refusal stands after thirty seconds.
        let start = Date()
        var tick = 0
        while Date().timeIntervalSince(start) < 120 {
            try await Task.sleep(for: .seconds(1))
            tick += 1
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
                if Date().timeIntervalSince(start) >= 30 { throw Failure(message: refusal) }
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
