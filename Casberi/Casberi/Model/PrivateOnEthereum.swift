import Foundation
import SwiftData

/// **PRIVATE MONEY ON ETHEREUM (prd §1563).** The same three acts as on
/// Sepolia — into your private balance, from it to an address, and Take it
/// back — with mainnet's one difference: the sender is YOUR ACCOUNT, the 7579
/// Safe on this phone, signing with Face ID. Shipping code, in every build
/// (`PrivateMainnet.on` is the kill switch); the DEBUG test sender is never
/// used here.
///
/// **The owner is your account's address.** A private account's keystore
/// entry names an owner, and the pool lets only that owner take a note back
/// (`PoolVault.ragequit` checks `msg.sender == ownerAddress`, else
/// `PoolVault_InvalidOwnerAddress()`, 0x7db3fe30) and pays it to that owner.
/// So the owner must be an address the person controls and can receive at,
/// on Ethereum — the account itself. It registers by an ordinary Face ID
/// operation (`Keystore.setAuthPolicy` and `setViewingKey` key on
/// `msg.sender`), riding the first deposit; the relayed EIP-712 variant
/// (`setAuthPolicyWithSig`) is not used: it would need the Safe's EIP-1271
/// signature from a passkey, the relayer's standalone registration is not
/// served ("INTL-05"), and the first deposit pays gas from the account
/// anyway. Proven in simulation against mainnet (`mainnet-sim.mjs`): the
/// registration and a deposit as the account, then the ragequit as the
/// account, the ETH back in it.
///
/// **Always earning.** Every deposit goes to the token's yield pool (prd
/// §1541 item 2): ETH into ppETH (the router takes native ETH and refunds
/// what it did not use), USDC into ppUSDC (an approval, then the router).
/// Plain USDC is disabled on 0xBow's Entrypoint; plain ETH is not used.
@MainActor
enum PrivateOnEthereum {

    static var network: PrivacyNetwork { .ethereum }
    static var accountNetwork: YourAccountOp.Network { YourAccountOp.ethereum }

    enum Failure: Error, Equatable { case noAccount, noRoot, notOwner, noPool, curve }

    /// Your account's address: the owner of every private account on Ethereum.
    static var owner: String? { YourAccountKey.address }

    /// Opens root `id`'s private account on Ethereum, owned by your account.
    /// `reason` asks for the device owner first (what spends without your
    /// account's own signature: a relayed send); nil reads, or moves money
    /// with an operation that asks Face ID itself.
    @discardableResult
    static func open(_ id: String, reason: String?) async throws -> String {
        guard PrivateMainnet.on else { throw PrivacyNetwork.Refusal.notServed(network.chainId) }
        guard let owner else { throw Failure.noAccount }
        if let reason { try await PrivateRootKey.unlock(reason: reason) }
        guard var root = PrivateRootKey.root(id) else { throw Failure.noRoot }
        defer { for i in root.indices { root[i] = 0 } }
        guard let derived = PrivateRoot.derive(root, .poolSeed) else { throw Failure.curve }
        var seed = Data(derived)
        defer { seed.resetBytes(in: 0..<seed.count) }
        _ = try await PrivacyEngine.shared.open(seed: seed, owner: owner, network: network)
        return owner
    }

    /// The pool's terms for a token (`Entrypoint.assets` on the share):
    /// the smallest deposit and 0xBow's vetting fee. Read 2026-10-26: ppETH
    /// 0.004, ppUSDC 10, no vetting fee on either.
    static func terms(_ pool: PrivacyNetwork.YieldPool) async -> FreshAddress.AssetConfig? {
        guard let data = FreshAddress.assetsCall(token: pool.share),
              let answer = await ethCall(to: network.entrypoint, data: data) else { return nil }
        return FreshAddress.assetConfig(answer)
    }

    static func ethCall(to: String, data: String) async -> String? {
        guard let url = URL(string: network.rpcUrl) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [["to": to, "data": data], "latest"]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (answer, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.service), http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: answer) as? [String: Any] else { return nil }
        return json["result"] as? String
    }

    // MARK: - Into your private balance

    /// What a deposit left: its transaction when one was named, and the
    /// note's commitment, kept either way.
    struct Deposited: Equatable {
        let tx: String?
        let commitment: String
        /// Sent and not seen within two minutes: `PrivatePending` follows it.
        let pending: Bool
    }

    /// Moves at most `budget` (base units, fees included) of `token` (ETH or
    /// USDC) from your account into the root's private account, earning:
    /// the registration the first time, the token's approval, the router's
    /// deposit, all in one Face ID operation, simulated first. Keeps the note
    /// waiting for approval.
    ///
    /// **KEPT WHETHER OR NOT IT WAS SEEN (the review of 2026-10-26, finding
    /// 2).** Landed with no transaction named (only the nonce moved), the
    /// note is kept with no hash; not seen in two minutes (`.pending`), the
    /// note is kept and the operation followed by its id (`PrivatePending`)
    /// until the bundler, the nonce or the pool says what became of it — and
    /// the discovery cadence (`PrivateWatch.findNotes`) finds any note that
    /// landed and was never kept.
    static func deposit(token: String, budget: String, context: ModelContext?,
                        stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void,
                        proving: @escaping () -> Void = {}) async throws -> Deposited {
        guard let pool = network.yieldPool(for: token), let hex = PrivateMoney.hex(budget) else { throw Failure.noPool }
        let account = try PrivateRootKey.ensure()
        // One flow at a time through the engine (finding 8): opened, the
        // registration read and the deposit proved together.
        let (owner, calls, d) = try await PrivacyEngine.exclusive {
            let owner = try await open(account, reason: nil)
            let engine = PrivacyEngine.shared
            var calls: [(to: String, data: String, value: String)] = []
            if try await !engine.isRegistered().registered {
                let registration = try await engine.prepareRegister()
                for tx in registration.txs {
                    guard tx.to.lowercased() == network.keystore.lowercased() else { throw Failure.notOwner }
                    calls.append((tx.to, tx.data, PrivateMoney.decimal(hex: tx.value)))
                }
            }
            proving()
            let d = try await engine.prepareYieldDeposit(tokenId: token, budget: hex)
            return (owner, calls, d)
        }
        var all = calls
        // The router of the token's own pool, carrying at most the budget.
        guard d.tx.to.lowercased() == pool.router.lowercased(), d.share.lowercased() == pool.share.lowercased(),
              let carried = Decimal(string: PrivateMoney.decimal(hex: d.tx.value)), let most = Decimal(string: budget),
              carried <= most else { throw Failure.noPool }
        for a in d.approvals { all.append((a.to, a.data, PrivateMoney.decimal(hex: a.value))) }
        all.append((d.tx.to, d.tx.data, PrivateMoney.decimal(hex: d.tx.value)))
        let followed = YourAccountChain.Followed()
        let sent = try await YourAccountChain.$following.withValue(followed) {
            try await YourAccountChain.privateCalls(all, on: accountNetwork, reason: String(localized: "Move to private"), stage: stage)
        }
        let figure = PrivateMoney.figure(PrivateMoney.decimal(hex: d.underlyingNeeded), decimals: pool.underlyingDecimals, symbol: pool.symbol)
        let title = PrivateMoney.activityTitle(figure: figure, to: nil)
        let hash: String?
        switch sent.outcome {
        case .landed(let tx, _): hash = tx
        case .pending: hash = nil
        case .dryRun: throw YourAccountChain.Failure(message: String(localized: "This send could not be written"))
        }
        PrivateMoneyStore.shared.add(.init(commitment: d.commitment, label: d.label, labelHash: d.labelHash,
                                           symbol: pool.symbol, amount: PrivateMoney.decimal(hex: d.shares),
                                           decimals: pool.shareDecimals, chainId: network.chainId, tx: hash ?? "", at: Date(),
                                           status: .waiting, root: account, share: pool.share))
        if let hash, let context { PrivateActivity.land(hash: hash, title: title, chainId: network.chainId, context: context) }
        if case .pending = sent.outcome, let id = followed.id {
            PrivatePending.shared.add(.init(id: id, chainId: network.chainId, account: owner, nonceKey: SafeABI.hex(followed.nonceKey),
                                            nonce: followed.nonce, at: Date(), commitment: d.commitment, title: title,
                                            reserved: nil, toPrivate: true))
        }
        NSLog("privateEthereum| deposited | %@ | %@ | owner %@ | label hash %@", hash ?? "not yet seen", figure, YourAccount.short(owner), d.labelHash)
        if case .pending = sent.outcome { return Deposited(tx: nil, commitment: d.commitment, pending: true) }
        return Deposited(tx: hash, commitment: d.commitment, pending: false)
    }

    // MARK: - From your private balance

    /// Sends `amount` (base units of the token) from the root's approved
    /// private balance to `to`, through 0xBow's relayer, which posts it and
    /// pays the gas for a fee taken in shares. To a plain address the router
    /// pays the token out (native ETH for ETH); to an address whose owner has
    /// a private account of their own (`balanceToBalance`, prd §1567) it is
    /// a transfer inside the pool, balance to balance, nothing paid out.
    /// Asks for the device owner first. Returns the relayer's transaction
    /// hash. The whole of it runs alone through the engine (finding 8): no
    /// other flow can open another account between the proof and the relay.
    static func send(token: String, amount: String, to: String, balanceToBalance: Bool = false,
                     reason: String = String(localized: "Send from your private balance")) async throws -> String {
        guard network.yieldPool(for: token) != nil, PrivateMoney.isAddress(to), let hex = PrivateMoney.hex(amount) else { throw Failure.noPool }
        guard let account = PrivateRootKey.currentID else { throw Failure.noRoot }
        return try await PrivacyEngine.exclusive {
            try await open(account, reason: reason)
            let engine = PrivacyEngine.shared
            PrivateMoneyStore.shared.reconcile(try await engine.discover(), root: account, network: network)
            let spend = balanceToBalance ? try await engine.prepareTransfer(tokenId: token, amount: hex, to: to)
                : try await engine.prepareWithdraw(tokenId: token, amount: hex, to: to)
            let relayed = try await engine.relay(handle: spend.handle)
            NSLog("privateEthereum| relayed | %@ | %@ | %@ to %@", balanceToBalance ? "balance to balance" : "paid out", relayed.tx, amount, YourAccount.short(to))
            if let after = try? await engine.discover() { PrivateMoneyStore.shared.reconcile(after, root: account, network: network) }
            return relayed.tx
        }
    }

    // MARK: - Balance to balance (prd §1567)

    /// Whether `owner` has a private account of its own on `net`: a viewing
    /// key registered in the keystore. Read with no account open (one
    /// `eth_call` through the engine's door). Nil when the node did not
    /// answer (Tor not up yet): unknown is never read as "no".
    static func hasPrivateAccount(_ owner: String, on net: PrivacyNetwork) async -> Bool? {
        guard let data = PrivateMoney.viewingKeyCall(owner: owner) else { return false }
        guard let answer = try? await PrivateRPC.call(net, "eth_call", [["to": net.keystore, "data": data], "latest"]) as? String else {
            return nil
        }
        return PrivateMoney.hasViewingKey(answer)
    }

    // MARK: - Round-ups into your private balance (prd §1567)

    /// The deposit a Face ID operation on Ethereum carries for round-ups:
    /// `units` of USDC into ppUSDC for the root's account, the registration
    /// with it the first time, the approval and the router's deposit — as
    /// calls for your account's operation, the send's own beside them. The
    /// deposit is proved now; kept (`keep`) once the operation is sent —
    /// landed, or on its way and followed (`PrivatePending`, finding 2).
    struct Ride {
        let calls: [(to: String, data: String, value: String)]
        let keep: PrivateMoney.Note
        let figure: String
    }

    /// **SAVED FROM ETH WHEN THERE IS NO USDC (user, 2026-10-27: "if someone
    /// doesn't have usdc do we swap it for them?").** `units` of the dollar,
    /// at ETH's price, into ppETH: the deposit carries the ETH itself, no
    /// swap. Nil price: no ride.
    static func roundUpsRideInETH(units: String, ethPrice: Double) async throws -> Ride {
        guard let pool = network.yield.first(where: { $0.native }), ethPrice > 0,
              let usd = Decimal(string: units).map({ $0 / pow(10, RoundUps.dollarDecimals) }) else { throw Failure.noPool }
        var wei = usd / Decimal(ethPrice) * pow(10, 18), rounded = Decimal()
        NSDecimalRound(&rounded, &wei, 0, .down)
        let budget = NSDecimalNumber(decimal: rounded).stringValue
        guard let hex = PrivateMoney.hex(budget) else { throw Failure.noPool }
        let account = try PrivateRootKey.ensure()
        let (calls, d) = try await PrivacyEngine.exclusive {
            _ = try await open(account, reason: nil)
            let engine = PrivacyEngine.shared
            var calls: [(to: String, data: String, value: String)] = []
            if try await !engine.isRegistered().registered {
                for tx in try await engine.prepareRegister().txs {
                    guard tx.to.lowercased() == network.keystore.lowercased() else { throw Failure.notOwner }
                    calls.append((tx.to, tx.data, PrivateMoney.decimal(hex: tx.value)))
                }
            }
            return (calls, try await engine.prepareYieldDeposit(tokenId: PrivateMove.eth, budget: hex))
        }
        // The router of ppETH, carrying at most the budget in ETH.
        guard d.tx.to.lowercased() == pool.router.lowercased(), d.share.lowercased() == pool.share.lowercased(),
              let carried = Decimal(string: PrivateMoney.decimal(hex: d.tx.value)), carried <= rounded else { throw Failure.noPool }
        var all = calls
        for a in d.approvals { all.append((a.to, a.data, PrivateMoney.decimal(hex: a.value))) }
        all.append((d.tx.to, d.tx.data, PrivateMoney.decimal(hex: d.tx.value)))
        let note = PrivateMoney.Note(commitment: d.commitment, label: d.label, labelHash: d.labelHash, symbol: pool.symbol,
                                     amount: PrivateMoney.decimal(hex: d.shares), decimals: pool.shareDecimals, chainId: network.chainId,
                                     tx: "", at: Date(), status: .waiting, root: account, share: pool.share)
        return Ride(calls: all, keep: note,
                    figure: PrivateMoney.figure(PrivateMoney.decimal(hex: d.underlyingNeeded), decimals: pool.underlyingDecimals, symbol: pool.symbol))
    }

    static func roundUpsRide(units: String) async throws -> Ride {
        guard let pool = network.yield.first(where: { !$0.native }), let hex = PrivateMoney.hex(units) else { throw Failure.noPool }
        let account = try PrivateRootKey.ensure()
        // Alone through the engine (finding 8): the fresh watch or a send
        // from another root cannot open between this open and this proof.
        let (calls, d) = try await PrivacyEngine.exclusive {
            _ = try await open(account, reason: nil)
            let engine = PrivacyEngine.shared
            var calls: [(to: String, data: String, value: String)] = []
            if try await !engine.isRegistered().registered {
                for tx in try await engine.prepareRegister().txs {
                    guard tx.to.lowercased() == network.keystore.lowercased() else { throw Failure.notOwner }
                    calls.append((tx.to, tx.data, PrivateMoney.decimal(hex: tx.value)))
                }
            }
            return (calls, try await engine.prepareYieldDeposit(tokenId: pool.underlying, budget: hex))
        }
        var all = calls
        guard d.tx.to.lowercased() == pool.router.lowercased(), d.share.lowercased() == pool.share.lowercased(),
              PrivateMoney.decimal(hex: d.tx.value) == "0",
              let most = Decimal(string: PrivateMoney.decimal(hex: d.maxUnderlyingIn)), let budget = Decimal(string: units),
              most <= budget else { throw Failure.noPool }
        for a in d.approvals { all.append((a.to, a.data, PrivateMoney.decimal(hex: a.value))) }
        all.append((d.tx.to, d.tx.data, "0"))
        let note = PrivateMoney.Note(commitment: d.commitment, label: d.label, labelHash: d.labelHash, symbol: pool.symbol,
                                     amount: PrivateMoney.decimal(hex: d.shares), decimals: pool.shareDecimals, chainId: network.chainId,
                                     tx: "", at: Date(), status: .waiting, root: account, share: pool.share)
        return Ride(calls: all, keep: note,
                    figure: PrivateMoney.figure(PrivateMoney.decimal(hex: d.underlyingNeeded), decimals: pool.underlyingDecimals, symbol: pool.symbol))
    }

    // MARK: - Take it back

    /// The ragequit of one note, then the zap turning its shares back into
    /// the token (and WETH into ETH through the pinned SwapRouter02, finding
    /// 1), in ONE Face ID operation from your account — the owner, the only
    /// address the pool lets send it, and the one it pays. Simulated first.
    /// Returns the hash (nil when only the nonce moved, or not yet seen) and
    /// what came back; one not yet seen is followed (`PrivatePending`) and
    /// its note leaves when it lands (finding 2).
    static func takeBack(_ note: PrivateMoney.Note) async throws -> (hash: String?, figure: String, pending: Bool) {
        guard let share = note.share, let pool = network.yieldPool(for: share), let root = note.root else { throw Failure.noPool }
        let (owner, quit) = try await PrivacyEngine.exclusive {
            let owner = try await open(root, reason: nil)
            let engine = PrivacyEngine.shared
            PrivateMoneyStore.shared.reconcile(try await engine.discover(), root: root, network: network)
            return (owner, try await engine.prepareRagequit(commitment: note.commitment))
        }
        guard quit.recipient.lowercased() == owner.lowercased() else { throw Failure.notOwner }
        let shares = PrivateMoney.decimal(hex: quit.value)
        // What the shares are worth now; the share only rises, so unwrapping
        // this much of WETH never asks for more than the zap paid.
        guard let preview = PrivateYield.uint(shares).map({ "0x4cdad506" + $0 }),
              let answer = await ethCall(to: pool.share, data: preview), let worth = PrivateYield.word(answer, 0),
              let after = PrivateYield.takeBackCalls(pool: pool, shares: shares, owner: owner, worth: worth) else { throw Failure.noPool }
        let calls = [(to: quit.tx.to, data: quit.tx.data, value: PrivateMoney.decimal(hex: quit.tx.value))]
            + after.map { (to: $0.to, data: $0.data, value: "0") }
        let followed = YourAccountChain.Followed()
        let sent = try await YourAccountChain.$following.withValue(followed) {
            try await YourAccountChain.privateCalls(calls, on: accountNetwork, reason: String(localized: "Take it back"), stage: { _ in })
        }
        let figure = PrivateMoney.figure(worth, decimals: pool.underlyingDecimals, symbol: pool.symbol)
        switch sent.outcome {
        case .landed(let tx, _):
            PrivateMoneyStore.shared.remove(commitment: note.commitment)
            return (tx, figure, false)
        case .pending:
            if let id = followed.id {
                PrivatePending.shared.add(.init(id: id, chainId: network.chainId, account: owner, nonceKey: SafeABI.hex(followed.nonceKey),
                                                nonce: followed.nonce, at: Date(), commitment: note.commitment,
                                                title: PrivateMoney.takenBackTitle(figure: figure, to: YourAccount.short(owner)),
                                                reserved: nil, toPrivate: true, exits: true))
            }
            return (nil, figure, true)
        case .dryRun:
            throw YourAccountChain.Failure(message: String(localized: "This send could not be written"))
        }
    }
}
