import Foundation
import Observation

/// **YOUR RAILGUN POCKET (prd §1713).** The private balance for any token
/// on Ethereum other than ETH and USDC: a Railgun wallet that belongs to your
/// account (the Safe on this phone), opened in `RailgunEngine`.
///
/// **One root, as the rest of private money (prd §1562).** The wallet's
/// phrase is made from 32 bytes of your private root (`.railgunWallet`) and
/// the SDK's encryption key from another 32 (`.railgunDatabase`), so a new
/// phone with the root in iCloud Keychain gets the same wallet back. They are
/// read without Face ID, as the pool seed is, so the balance reads in the
/// background (user, 2026-11-07: "view freely"); what spends asks for you
/// first (`PrivateRootKey.unlock`), then your account's Face ID.
///
/// **Your account sends both doors.** In: the token's approval to Railgun's
/// proxy and the shield, ONE operation (`YourAccountChain.privateCalls`:
/// simulated against Ethereum's real state, then Face ID; a call that would
/// fail signs nothing). Out: the proxy call carrying the unshield proof, as a
/// plain call from your account, never the EIP-7702 form Railgun's SDK
/// writes for a plain wallet (`forSafe`). Your account pays both doors' gas,
/// as every move of yours does.
///
/// Nothing here draws: Move and Holdings read it (built next); a DEBUG build
/// drives it with `-railgunPocket`.
@MainActor
enum RailgunPocket {

    static var accountNetwork: YourAccountOp.Network { YourAccountOp.ethereum }

    /// Railgun's proxy on Ethereum: the shield's and the unshield's one door.
    static let proxy = "0xfa7093cdd9ee6932b4eb2c9e1cde7ce00b1fa4b9"

    /// The checkpoint's first block (tree 4): a wallet whose creation is not
    /// known scans from here, so nothing sent to it is ever missed.
    static let checkpointBlock = 25_849_756

    enum Failure: Error, Equatable {
        case noAccount, noRoot, curve
        /// Handed over and not in a block after four minutes (prd §1895).
        case notMined
        /// In a block, and reverted: nothing moved but its gas.
        case failedOnChain
        /// A sync the roots did not confirm: nothing is spent from it.
        case untrusted
        /// A prepared call that is not your account's plain call to Railgun.
        case notRailgun
        case nothingSpendable
        case notWritten
        /// No broadcaster answered on Waku (prd §1721 item 3).
        case noBroadcaster
        /// The wallet holds none of the tokens a broadcaster takes its fee in.
        case noFeeToken
        /// It holds one, still in Railgun's screening (fees added within the hour).
        case feeTokenPending
        /// The send and its fee are more than the wallet can spend.
        case feeNotCovered
        /// A fresh sender's gas is more than your private ETH can pay (§1726).
        case noPrivateGas
        /// The fresh sender's gas was sent and has not landed yet: try again.
        case gasOnItsWay
        /// A private send to this wallet's own 0zk address (prd §1988 item 6).
        case ownAddress
    }

    /// Ethereum's WETH: what a little ETH for broadcasters' fees becomes.
    static let weth = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"

    /// Whether this build carries the engine: every build since prd §1721
    /// (user: "i don't want it hidden"). Kept as the one switch the rows and
    /// sentences ask.
    static var available: Bool { true }

    /// Railgun's fees as the proxy last answered them, in basis points
    /// (`shieldFee`/`unshieldFee`, read on every open, §1713 item 6); nil
    /// until an open has read them.
    static var shieldFeeBps: Int?
    static var unshieldFeeBps: Int?

    // MARK: - Opening

    private static func walletKey(_ root: String) -> String { "railgun.wallet." + root }

    /// Whether a Railgun wallet already exists for your current root: the
    /// only case in which Casberi reads one, so no root is ever made just to
    /// look (§1721 item 1).
    static var hasWallet: Bool {
        guard let id = PrivateRootKey.currentID else { return false }
        return UserDefaults.standard.string(forKey: walletKey(id)) != nil
    }

    /// Opens your wallet in the engine, made from root `id`. `reason` asks
    /// for the device owner first (what spends); nil only reads.
    @discardableResult
    static func open(reason: String?) async throws -> RailgunEngineWire.Opened {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        let id = try PrivateRootKey.ensure()
        if let reason { try await PrivateRootKey.unlock(reason: reason) }
        guard var root = PrivateRootKey.root(id) else { throw Failure.noRoot }
        defer { for i in root.indices { root[i] = 0 } }
        guard var entropy = PrivateRoot.derive(root, .railgunWallet),
              var key = PrivateRoot.derive(root, .railgunDatabase) else { throw Failure.curve }
        defer { for i in entropy.indices { entropy[i] = 0 }; for i in key.indices { key[i] = 0 } }
        let engine = RailgunEngine.shared
        if engine.isOpen {
            let opened = try await engine.open(entropy: hex(entropy, prefix: true), encryptionKey: hex(key),
                                               walletID: UserDefaults.standard.string(forKey: walletKey(id)))
            noteFees(opened)
            return opened
        }
        let opened = try await engine.open(entropy: hex(entropy, prefix: true), encryptionKey: hex(key),
                                           walletID: UserDefaults.standard.string(forKey: walletKey(id)),
                                           creationBlock: checkpointBlock)
        UserDefaults.standard.set(opened.walletID, forKey: walletKey(id))
        noteFees(opened)
        // Nothing kept on this phone: the sync that follows builds the trees.
        RailgunSync.shared.firstTime = opened.keptLeaves == 0
        return opened
    }

    private static func noteFees(_ opened: RailgunEngineWire.Opened) {
        if let bps = opened.shieldFeeBps.flatMap(Int.init) { shieldFeeBps = bps }
        if let bps = opened.unshieldFeeBps.flatMap(Int.init) { unshieldFeeBps = bps }
    }

    /// "0.25%": a fee in basis points as Railgun's foot says it.
    static func percent(bps: Int) -> String {
        let pct = Double(bps) / 100
        return (pct.rounded() == pct ? String(format: "%.0f", pct) : String(format: "%.2f", pct)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)) + "%"
    }

    private static func hex(_ bytes: [UInt8], prefix: Bool = false) -> String {
        (prefix ? "0x" : "") + bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the pool and your wallet, every root checked. Throws `untrusted`
    /// when a root does not match: the balance it read is not shown as yours.
    ///
    /// **One sync at a time, joined (prd §1728 item 3).** The Wallet opening
    /// starts one (`RailgunHoldings.warm`); a quote asked while it runs
    /// waits for that one instead of starting a second, and `RailgunSync`
    /// says how long it has run, for Move's line.
    static func sync() async throws -> RailgunEngineWire.Synced {
        if let running { return try await running.value }
        let task = Task { @MainActor () throws -> RailgunEngineWire.Synced in
            let synced = try await RailgunEngine.shared.sync()
            guard RailgunEngineWire.trusted(synced) else { throw Failure.untrusted }
            if RailgunSync.shared.firstTime { RailgunSync.shared.firstReady += 1 }
            return synced
        }
        running = task
        RailgunSync.shared.since = .now
        RailgunSync.shared.reset()
        defer {
            running = nil
            RailgunSync.shared.since = nil
            RailgunSync.shared.firstTime = false
            RailgunSync.shared.reset()
        }
        return try await task.value
    }

    private static var running: Task<RailgunEngineWire.Synced, Error>?

    // MARK: - What a move costs (prd §1728 item 6)

    /// Gas your account pays to move a token in (approve and shield, one
    /// Safe transaction): 793,342 measured on mainnet (§1713), rounded up.
    static let shieldGas = 800_000
    /// Gas a plain unshield takes: 516,069 measured (§1713 item 8), rounded
    /// up. A fresh sender's send is the same call (§1726).
    static let unshieldGas = 520_000

    /// Ethereum's gas price now, in wei; nil when the node does not answer.
    static func gasPriceWei() async -> Decimal? {
        guard let hex = try? await YourAccountChain.rpc(accountNetwork, "eth_gasPrice", []) as? String else { return nil }
        return Decimal(string: PrivateMoney.decimal(hex: hex))
    }

    /// What Privacy Pools' relayer took to bring a fresh sender its gas, as
    /// `privateGasCovers` last asked it, in wei.
    static var lastRelayerFeeWei: Decimal?

    // MARK: - In

    /// Moves `amount` (base units, decimal) of `token` from your account into
    /// your Railgun wallet: approve and shield, one Face ID operation.
    /// Returns the transaction's hash, or nil while it is not yet seen.
    static func shield(token: String, amount: String,
                       stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> String? {
        guard let hexAmount = PrivateMoney.hex(amount) else { throw Failure.notWritten }
        let opened = try await open(reason: nil)
        let prepared = try await RailgunEngine.shared.prepareShield(token: token, amount: hexAmount)
        let calls: [(to: String, data: String, value: String)]
        if token.lowercased() == RailgunRouting.eth {
            // **ETH IN (2026-11-27):** the relay adapter wraps it to WETH and
            // shields it; no approval, and the value is exactly the amount.
            guard let adapter = opened.relayAdapt?.lowercased(), prepared.tx.to.lowercased() == adapter,
                  prepared.approve == nil, PrivateMoney.decimal(hex: prepared.tx.value) == amount else { throw Failure.notRailgun }
            calls = [(to: prepared.tx.to, data: prepared.tx.data, value: amount)]
        } else {
            guard prepared.tx.to.lowercased() == proxy, let approve = prepared.approve,
                  approve.to.lowercased() == token.lowercased(),
                  approve.data.lowercased() == approveCall(amount: hexAmount) else { throw Failure.notRailgun }
            calls = [(to: approve.to, data: approve.data, value: "0"),
                     (to: prepared.tx.to, data: prepared.tx.data, value: PrivateMoney.decimal(hex: prepared.tx.value))]
        }
        let sent = try await YourAccountChain.privateCalls(calls, on: accountNetwork,
                                                           reason: String(localized: "Move to private"), stage: stage)
        let hash = landed(sent)
        NSLog("railgunPocket| shielded | %@ | %@ of %@", hash ?? "not yet seen", amount, token)
        RailgunHoldings.shared.movedIn(token: token)
        return hash
    }

    /// `approve(proxy, amount)`, exactly: the only approval a shield may ask.
    static func approveCall(amount hexAmount: String) -> String {
        let digits = hexAmount.lowercased().hasPrefix("0x") ? String(hexAmount.dropFirst(2)) : hexAmount
        let padded = String(repeating: "0", count: max(0, 64 - digits.count)) + digits.lowercased()
        return "0x095ea7b3" + String(repeating: "0", count: 24) + String(proxy.dropFirst(2)) + padded
    }

    // MARK: - Out

    /// Sends `amount` (base units, decimal) of `token` from your Railgun
    /// wallet to `to`: the proof made on this phone, the proxy call sent by
    /// your account. Asks for the device owner first, then Face ID.
    /// `unlocked` runs once you have said yes, so Move's rows start their
    /// clock after Face ID (prd §1728, §1700x).
    static func send(token: String, amount: String, to: String, unlocked: @MainActor () -> Void = {},
                     stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> String? {
        guard PrivateMoney.isAddress(to), let hexAmount = PrivateMoney.hex(amount) else { throw Failure.notWritten }
        try await open(reason: String(localized: "Send from Railgun"))
        unlocked()
        let synced = try await sync()
        guard let held = synced.balances.first(where: { $0.token.lowercased() == token.lowercased() }),
              let spendable = Decimal(string: PrivateMoney.decimal(hex: held.spendable)),
              let wanted = Decimal(string: amount), wanted <= spendable, wanted > 0 else { throw Failure.nothingSpendable }
        let u = try await RailgunEngine.shared.prepareUnshield(token: token, amount: hexAmount, to: to, forSafe: true)
        guard u.tx.to.lowercased() == proxy, u.type != 4, u.delegate == nil, u.to.lowercased() == to.lowercased() else {
            throw Failure.notRailgun
        }
        let sent = try await YourAccountChain.privateCalls([(to: u.tx.to, data: u.tx.data, value: PrivateMoney.decimal(hex: u.tx.value))],
                                                           on: accountNetwork,
                                                           reason: String(localized: "Send from Railgun"), stage: stage)
        let hash = landed(sent)
        NSLog("railgunPocket| unshielded | %@ | %@ of %@ to %@ | proof %d ms", hash ?? "not yet seen", amount, token, YourAccount.short(to), u.proofMs)
        return hash
    }

    // MARK: - Out, to someone else (prd §1721 item 3)

    /// What sending `amount` (base units, decimal) of `token` from your
    /// Railgun wallet to `to` costs through a broadcaster: the wallet synced
    /// and every root checked, the broadcasters heard on Waku, the fee token
    /// picked (`RailgunRouting.feeToken`) and the fee quoted. Reads only:
    /// nothing is proved or sent, and no Face ID is asked.
    static func quote(token: String, amount: String, to: String) async throws -> RailgunEngineWire.Quote {
        guard PrivateMoney.isAddress(to), let hexAmount = PrivateMoney.hex(amount),
              let wanted = Decimal(string: amount), wanted > 0 else { throw Failure.notWritten }
        try await open(reason: nil)
        let synced = try await sync()
        var spendable: [String: Decimal] = [:]
        for b in synced.balances {
            spendable[b.token.lowercased()] = Decimal(string: PrivateMoney.decimal(hex: b.spendable)) ?? 0
        }
        guard wanted <= spendable[token.lowercased()] ?? 0 else { throw Failure.nothingSpendable }
        // No broadcaster heard, for whatever reason, is one answer: a fresh
        // sender may carry it instead (§1726).
        let taken = (try? await RailgunEngine.shared.broadcasters()) ?? []
        guard !taken.isEmpty else { throw Failure.noBroadcaster }
        guard let feeToken = RailgunRouting.feeToken(sending: token, taken: taken.map(\.token), spendable: spendable) else {
            var whole: [String: Decimal] = [:]
            for b in synced.balances { whole[b.token.lowercased()] = Decimal(string: PrivateMoney.decimal(hex: b.amount)) ?? 0 }
            throw RailgunRouting.feeToken(sending: token, taken: taken.map(\.token), spendable: whole) == nil
                ? Failure.noFeeToken : Failure.feeTokenPending
        }
        let q = try await RailgunEngine.shared.quoteBroadcast(token: token, amount: hexAmount, to: to, feeToken: feeToken)
        let fee = Decimal(string: PrivateMoney.decimal(hex: q.fee)) ?? 0
        guard RailgunRouting.covers(amount: wanted, of: token, fee: fee, in: feeToken, spendable: spendable) else {
            throw Failure.feeNotCovered
        }
        NSLog("railgunPocket| quoted | %@ of %@ to %@ | fee %@ of %@ | %d ms", amount, token, YourAccount.short(to),
              PrivateMoney.decimal(hex: q.fee), feeToken, q.ms)
        return q
    }

    /// Sends the quoted send: asks for the device owner, then the proof made
    /// on this phone pays the broadcaster its fee inside Railgun and the
    /// broadcaster submits it. Your account signs nothing and pays no gas, so
    /// it appears nowhere on the transaction. Returns its hash.
    static func send(_ q: RailgunEngineWire.Quote, unlocked: @MainActor () -> Void = {}) async throws -> String {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        try await PrivateRootKey.unlock(reason: String(localized: "Send from Railgun"))
        unlocked()
        let sent = try await RailgunEngine.shared.broadcastSend(token: q.token, amount: q.amount, to: q.to,
                                                                feeToken: q.feeToken, fee: q.fee)
        NSLog("railgunPocket| broadcast | %@ | %@ of %@ to %@ | proof %d ms", sent.txHash, PrivateMoney.decimal(hex: q.amount),
              q.token, YourAccount.short(q.to), sent.proofMs)
        return sent.txHash
    }

    // MARK: - Out, to someone else, from a fresh sender (prd §1726)

    /// The fresh sender's gas at today's price: `railgunSendGas` at the cap,
    /// in wei, and what Privacy Pools' relayer takes to bring it.
    static func senderGasCost(gas: Int = FreshTx.railgunSendGas) async -> (need: Decimal, network: PrivacyNetwork)? {
        guard let network = PrivacyNetwork.forChain(FreshTx.railgunChain),
              let fees = try? await PrivateRPC.fees(network) else { return nil }
        return (Decimal(gas) * Decimal(fees.maxFee), network)
    }

    /// Whether your private ETH can pay a fresh sender's gas and the relayer.
    static func privateGasCovers(gas: Int = FreshTx.railgunSendGas) async -> Bool {
        guard let (need, network) = await senderGasCost(gas: gas), let ethPool = network.yieldPool(for: PrivateMove.eth),
              let sender = try? senderAddress() else { return false }
        let store = PrivateMoneyStore.shared
        await store.readYield()
        let fee = Decimal(string: await PrivateMove.relayerFee(ethPool, network: network, to: sender.address) ?? "") ?? 0
        lastRelayerFeeWei = fee > 0 ? fee : nil
        let spendable = Decimal(string: store.spendable(chainId: network.chainId, symbol: "ETH")) ?? 0
        return fee > 0 && spendable >= need + fee
    }

    private static func senderKey(_ root: String) -> String { "railgun.sender." + root }

    /// The next send takes a new sender, whatever this one does.
    static func senderUsed(_ sender: (index: UInt32, address: String, root: String)) {
        UserDefaults.standard.set(Int(sender.index - FreshAddress.senderBase) + 1, forKey: senderKey(sender.root))
    }

    /// **LEFTOVER GAS GOES BACK (prd §2009 item 3).** A one-time sender is
    /// funded at a fee ceiling it never all spends, and a send that never
    /// lands spends none (2026-11-18: about $2 left on `...5eea`). What is
    /// left on each sender used so far moves into Railgun as WETH, from that
    /// address, when it is worth more than three times that move's own gas.
    /// Run after a move of yours lands, never on its own.
    static let leftoverShieldGas = 450_000
    static func sweepLeftovers() async {
        guard let network = PrivacyNetwork.forChain(FreshTx.railgunChain), let root = PrivateRootKey.currentID,
              !DemoMode.isActive else { return }
        let used = UserDefaults.standard.integer(forKey: senderKey(root))
        guard used > 0, let fees = try? await PrivateRPC.fees(network) else { return }
        let cost = Decimal(leftoverShieldGas) * Decimal(fees.maxFee)
        for i in 0..<used {
            let index = FreshAddress.senderBase + UInt32(i)
            guard let address = try? FreshSigner.address(index, root: root),
                  let read = try? await PrivateRPC.decimal(network, "eth_getBalance", [address, "latest"]),
                  let held = Decimal(string: read), held > cost * 3 else { continue }
            let amount = NSDecimalNumber(decimal: held - cost).stringValue
            do {
                guard let hexAmount = PrivateMoney.hex(amount) else { continue }
                _ = try await open(reason: nil)
                let prepared = try await RailgunEngine.shared.prepareShield(token: RailgunRouting.eth, amount: hexAmount)
                guard prepared.tx.to.lowercased() == FreshTx.railgunRelayAdapt, prepared.approve == nil,
                      PrivateMoney.decimal(hex: prepared.tx.value) == amount else { continue }
                let hash = try await FreshSigner.send(to: prepared.tx.to, data: prepared.tx.data, value: prepared.tx.value,
                                                      index: index, root: root, from: address, network: network,
                                                      gas: leftoverShieldGas, tip: fees.tip, maxFee: fees.maxFee,
                                                      nonceAt: "latest") { _, _ in }
                RailgunHoldings.shared.movedIn(token: RailgunRouting.eth)
                NSLog("railgunPocket| leftover gas back | %@ | %@ wei from %@", hash, amount, YourAccount.short(address))
            } catch {
                NSLog("railgunPocket| leftover gas stays | %@ | %@", YourAccount.short(address), String(describing: error))
            }
        }
    }

    /// This send's fresh sender: the next unused index under your root
    /// (a private send to Base or Robinhood takes one too, prd §1879).
    static func senderAddress() throws -> (index: UInt32, address: String, root: String) {
        let root = try PrivateRootKey.ensure()
        let used = UInt32(UserDefaults.standard.integer(forKey: senderKey(root)))
        let index = FreshAddress.senderBase + used
        return (index, try FreshSigner.address(index, root: root), root)
    }

    /// Sends `amount` of `token` from your Railgun wallet to `to` with no
    /// broadcaster: a fresh sender, its gas a relayed withdrawal of your
    /// private ETH (the pool to the sender: nothing names your account),
    /// submits the proved unshield. Face ID for the proof and the gas. The
    /// gas sent and not yet landed throws `gasOnItsWay`: the next try finds
    /// it there and goes on. A new sender after each send.
    static func sendFromFresh(token: String, amount: String, to: String, unlocked: @MainActor () -> Void = {},
                              stage: @escaping @MainActor (String) -> Void) async throws -> String {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        guard PrivateMoney.isAddress(to), let hexAmount = PrivateMoney.hex(amount) else { throw Failure.notWritten }
        guard let (need, network) = await senderGasCost(), let ethPool = network.yieldPool(for: PrivateMove.eth) else {
            throw Failure.noPrivateGas
        }
        let sender = try senderAddress()
        try await PrivateRootKey.unlock(reason: String(localized: "Send from Railgun"))
        unlocked()
        // The gas first, so the proof is made against the pool as it is when
        // it goes.
        let held = Decimal(string: try await PrivateRPC.decimal(network, "eth_getBalance", [sender.address, "latest"])) ?? 0
        if held < need {
            let short = need - held
            let fee = Decimal(string: await PrivateMove.relayerFee(ethPool, network: network, to: sender.address) ?? "") ?? 0
            let spendable = Decimal(string: PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "ETH")) ?? 0
            guard fee > 0, spendable >= short + fee else { throw Failure.noPrivateGas }
            stage(String(localized: "Paying its gas from your private ETH…"))
            let tx = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: PrivateMoney.plain(short), to: sender.address,
                                                      reason: String(localized: "Send from Railgun"))
            NSLog("railgunPocket| sender gas | %@ | %@ wei | %@", YourAccount.short(sender.address), PrivateMoney.plain(short), tx)
            guard try await FreshSigner.landed(tx, on: network) else { throw Failure.gasOnItsWay }
        }
        stage(String(localized: "Proving on this iPhone…"))
        try await open(reason: nil)
        let synced = try await sync()
        guard let have = synced.balances.first(where: { $0.token.lowercased() == token.lowercased() }),
              let spendable = Decimal(string: PrivateMoney.decimal(hex: have.spendable)),
              let wanted = Decimal(string: amount), wanted > 0, wanted <= spendable else { throw Failure.nothingSpendable }
        let u = try await RailgunEngine.shared.prepareUnshield(token: token, amount: hexAmount, to: to, forSafe: true)
        guard u.tx.to.lowercased() == proxy, u.type != 4, u.delegate == nil, u.to.lowercased() == to.lowercased(),
              u.tx.data.lowercased().hasPrefix(FreshTx.railgunTransact), PrivateMoney.decimal(hex: u.tx.value) == "0" else {
            throw Failure.notRailgun
        }
        let fees = try await PrivateRPC.fees(network)
        let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                        [["from": sender.address, "to": u.tx.to, "data": u.tx.data, "value": "0x0"]])) ?? 0
        guard estimate > 0, estimate <= FreshTx.railgunSendGas else { throw Failure.notRailgun }
        stage(String(localized: "Sending…"))
        PrivateSendSteps.shared.mark(.sent, from: .railgun)
        let hash = try await FreshSigner.send(to: u.tx.to, data: u.tx.data, value: "0x0", index: sender.index, root: sender.root,
                                              from: sender.address, network: network, gas: FreshTx.railgunSendGas,
                                              tip: fees.tip, maxFee: fees.maxFee) { _, _ in
            // Sent: the next send takes a new sender, whatever this one does.
            UserDefaults.standard.set(Int(sender.index - FreshAddress.senderBase) + 1, forKey: senderKey(sender.root))
        }
        NSLog("railgunPocket| sent from a fresh sender | %@ | %@ of %@ to %@ | proof %d ms", hash, amount, token, YourAccount.short(to), u.proofMs)
        return hash
    }

    /// A little ETH into your Railgun wallet as WETH, for broadcasters' fees:
    /// wrap, approve and shield, one Face ID operation from your account.
    static func addFees(wei: String,
                        stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> String? {
        guard let hexAmount = PrivateMoney.hex(wei) else { throw Failure.notWritten }
        try await open(reason: nil)
        let prepared = try await RailgunEngine.shared.prepareShield(token: weth, amount: hexAmount)
        guard prepared.tx.to.lowercased() == proxy, let approve = prepared.approve,
              approve.to.lowercased() == weth,
              approve.data.lowercased() == approveCall(amount: hexAmount) else { throw Failure.notRailgun }
        // WETH's `deposit()`: the ETH becomes WETH in your account first.
        let calls = [(to: weth, data: "0xd0e30db0", value: wei),
                     (to: approve.to, data: approve.data, value: "0"),
                     (to: prepared.tx.to, data: prepared.tx.data, value: PrivateMoney.decimal(hex: prepared.tx.value))]
        let sent = try await YourAccountChain.privateCalls(calls, on: accountNetwork,
                                                           reason: String(localized: "Move to private"), stage: stage)
        let hash = landed(sent)
        NSLog("railgunPocket| fees added | %@ | %@ wei", hash ?? "not yet seen", wei)
        return hash
    }

    // MARK: - Swap inside your private balance (prd §1875)

    /// A private swap ready to go: the engine's swap, the route it takes, and
    /// how it is carried.
    struct SwapPlan: Equatable, Sendable {
        let wire: RailgunEngineWire.Swap
        let quote: YourAccountSwap.Quote
        /// The broadcaster's quote, or nil: a fresh sender carries it (§1726).
        let broadcast: RailgunEngineWire.SwapQuote?
        /// What comes back into the wallet after Railgun's shield fee.
        let buyBack: String
    }

    /// Prices a swap of `amount` (base units, decimal) of `sell` for `buy`
    /// inside your Railgun wallet: the wallet synced and every root checked,
    /// the route asked of Ethereum's pools for what reaches the adapter after
    /// Railgun's unshield fee, its calls checked (`RailgunSwap.checked`), and
    /// the broadcaster's fee quoted, or the fresh sender's gas found. Reads
    /// only: nothing is proved or sent, no Face ID.
    static func quoteSwap(sell: YourAccountOp.Token, buy: YourAccountOp.Token, amount: String) async throws -> SwapPlan {
        guard let sellToken = sell.contract?.lowercased(), let buyToken = buy.contract?.lowercased(), sellToken != buyToken,
              let wanted = Decimal(string: amount), wanted > 0, let hexAmount = PrivateMoney.hex(amount) else { throw Failure.notWritten }
        let opened = try await open(reason: nil)
        guard let adapter = opened.relayAdapt?.lowercased(), PrivateMoney.isAddress(adapter) else { throw Failure.notRailgun }
        let synced = try await sync()
        var spendable: [String: Decimal] = [:]
        for b in synced.balances { spendable[b.token.lowercased()] = Decimal(string: PrivateMoney.decimal(hex: b.spendable)) ?? 0 }
        guard wanted <= spendable[sellToken] ?? 0 else { throw Failure.nothingSpendable }
        guard let outBps = unshieldFeeBps, let inBps = shieldFeeBps,
              let net = RailgunSwap.afterFee(amount, bps: outBps) else { throw Failure.notWritten }
        let quote = try await YourAccountChain.swapQuote(accountNetwork, sell: sell, buy: buy, amount: net, account: adapter)
        guard RailgunSwap.checked(quote.calls, sell: sellToken, amount: net, adapter: adapter),
              let back = RailgunSwap.afterFee(quote.buyAmount, bps: inBps) else { throw Failure.notRailgun }
        var wire = RailgunEngineWire.Swap(token: sellToken, amount: hexAmount, buyToken: buyToken, calls: RailgunSwap.wire(quote.calls))
        #if DEBUG
        // The calls as written (public: tokens, router, amounts), to replay a
        // refused estimate (2026-11-18: "RelayAdapt multicall failed at index 1").
        for (i, c) in wire.calls.enumerated() { NSLog("railgunPocket| swap call %d | %@ | %@", i, c.to, c.data) }
        NSLog("railgunPocket| swap amounts | gross %@ | net %@ | out %@ | least %@ | venue %@", amount, net, quote.buyAmount, quote.minimumBuy,
              quote.route.map { "\($0.venue.kind)" } ?? "none")
        #endif
        // A broadcaster that carries relay-adapt sends, paid in a token it
        // takes that you hold; else a fresh sender, its gas your private ETH.
        var broadcast: RailgunEngineWire.SwapQuote?
        if let taken = try? await RailgunEngine.shared.broadcasters(), !taken.isEmpty,
           let feeToken = RailgunRouting.feeToken(sending: sellToken, taken: taken.map(\.token), spendable: spendable) {
            var asked = wire
            asked.feeToken = feeToken
            if let q = try? await RailgunEngine.shared.quoteSwap(asked),
               RailgunRouting.covers(amount: wanted, of: sellToken, fee: Decimal(string: PrivateMoney.decimal(hex: q.fee)) ?? 0,
                                     in: feeToken, spendable: spendable) {
                asked.fee = q.fee
                wire = asked
                broadcast = q
            }
        }
        if broadcast == nil, !(await privateGasCovers(gas: FreshTx.railgunSwapGas)) { throw Failure.noPrivateGas }
        NSLog("railgunPocket| swap quoted | %@ of %@ for %@ of %@ | %@", amount, sellToken, back, buyToken,
              broadcast.map { "fee \(PrivateMoney.decimal(hex: $0.fee)) of \($0.feeToken)" } ?? "fresh sender")
        return SwapPlan(wire: wire, quote: quote, broadcast: broadcast, buyBack: back)
    }

    /// Sends the quoted swap through its broadcaster: Face ID, then the proof
    /// made on this phone pays the broadcaster inside Railgun. Your account
    /// signs nothing and appears nowhere. Returns the transaction's hash.
    static func swap(_ plan: SwapPlan, unlocked: @MainActor () -> Void = {}) async throws -> String {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        guard plan.broadcast != nil, plan.wire.fee != nil else { throw Failure.noBroadcaster }
        try await PrivateRootKey.unlock(reason: String(localized: "Swap in Railgun"))
        unlocked()
        let sent = try await RailgunEngine.shared.broadcastSwap(plan.wire)
        NSLog("railgunPocket| swapped | %@ | %@ for %@ | proof %d ms", sent.txHash, plan.wire.token, plan.wire.buyToken, sent.proofMs)
        return sent.txHash
    }

    /// The same swap with no broadcaster: a fresh sender, its gas a relayed
    /// withdrawal of your private ETH, sends the proved call to the relay
    /// adapter. Face ID for the proof and the gas; a new sender after each.
    static func swapFromFresh(_ plan: SwapPlan, unlocked: @MainActor () -> Void = {},
                              stage: @escaping @MainActor (String) -> Void) async throws -> String {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        guard let (need, network) = await senderGasCost(gas: FreshTx.railgunSwapGas),
              let ethPool = network.yieldPool(for: PrivateMove.eth) else { throw Failure.noPrivateGas }
        let sender = try senderAddress()
        try await PrivateRootKey.unlock(reason: String(localized: "Swap in Railgun"))
        unlocked()
        let held = Decimal(string: try await PrivateRPC.decimal(network, "eth_getBalance", [sender.address, "latest"])) ?? 0
        if held < need {
            let short = need - held
            let fee = Decimal(string: await PrivateMove.relayerFee(ethPool, network: network, to: sender.address) ?? "") ?? 0
            let spendable = Decimal(string: PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "ETH")) ?? 0
            guard fee > 0, spendable >= short + fee else { throw Failure.noPrivateGas }
            stage(String(localized: "Paying its gas from your private ETH…"))
            let tx = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: PrivateMoney.plain(short), to: sender.address,
                                                      reason: String(localized: "Swap in Railgun"))
            guard try await FreshSigner.landed(tx, on: network) else { throw Failure.gasOnItsWay }
        }
        stage(String(localized: "Proving on this iPhone…"))
        let opened = try await open(reason: nil)
        guard let adapter = opened.relayAdapt?.lowercased() else { throw Failure.notRailgun }
        var wire = plan.wire
        wire.feeToken = nil
        wire.fee = nil
        let p = try await RailgunEngine.shared.prepareSwap(wire)
        guard p.tx.to.lowercased() == adapter, adapter == FreshTx.railgunRelayAdapt,
              p.tx.data.lowercased().hasPrefix(FreshTx.railgunRelay),
              PrivateMoney.decimal(hex: p.tx.value) == "0" else { throw Failure.notRailgun }
        let fees = try await PrivateRPC.fees(network)
        let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                        [["from": sender.address, "to": p.tx.to, "data": p.tx.data, "value": "0x0"]])) ?? 0
        guard estimate > 0, estimate <= FreshTx.railgunSwapGas else { throw Failure.notRailgun }
        stage(String(localized: "Sending…"))
        PrivateSendSteps.shared.mark(.sent, from: .railgun)
        let hash = try await FreshSigner.send(to: p.tx.to, data: p.tx.data, value: "0x0", index: sender.index, root: sender.root,
                                              from: sender.address, network: network, gas: FreshTx.railgunSwapGas,
                                              tip: fees.tip, maxFee: fees.maxFee) { _, _ in
            UserDefaults.standard.set(Int(sender.index - FreshAddress.senderBase) + 1, forKey: senderKey(sender.root))
        }
        NSLog("railgunPocket| swapped from a fresh sender | %@ | %@ for %@ | proof %d ms", hash, wire.token, wire.buyToken, p.proofMs)
        return hash
    }

    // MARK: - Send to a private address (prd §1877)

    /// A private send ready to go: what moves, and how it is carried.
    struct TransferPlan: Equatable, Sendable {
        let wire: RailgunEngineWire.Transfer
        /// The broadcaster's quote, or nil: a fresh sender carries it.
        let broadcast: RailgunEngineWire.TransferQuote?
    }

    /// Prices sending `amount` (base units, decimal) of `token` from your
    /// Railgun wallet to the private address `to`, inside Railgun: the
    /// broadcaster's fee, or the fresh sender's gas found. Reads only.
    static func quoteTransfer(token: String, amount: String, to: String, memo: String?) async throws -> TransferPlan {
        guard RailgunSwap.isPrivateAddress(to), let hexAmount = PrivateMoney.hex(amount),
              let wanted = Decimal(string: amount), wanted > 0 else { throw Failure.notWritten }
        let opened = try await open(reason: nil)
        // Your own 0zk address says so, never "could not be written" (prd §1988).
        guard to.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != opened.address.lowercased() else { throw Failure.ownAddress }
        let synced = try await sync()
        var spendable: [String: Decimal] = [:]
        for b in synced.balances { spendable[b.token.lowercased()] = Decimal(string: PrivateMoney.decimal(hex: b.spendable)) ?? 0 }
        guard wanted <= spendable[token.lowercased()] ?? 0 else { throw Failure.nothingSpendable }
        let note = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        var wire = RailgunEngineWire.Transfer(token: token.lowercased(), amount: hexAmount,
                                              to: to.trimmingCharacters(in: .whitespacesAndNewlines),
                                              memo: note?.isEmpty == false ? String(note!.prefix(140)) : nil)
        var broadcast: RailgunEngineWire.TransferQuote?
        if let taken = try? await RailgunEngine.shared.broadcasters(), !taken.isEmpty,
           let feeToken = RailgunRouting.feeToken(sending: token.lowercased(), taken: taken.map(\.token), spendable: spendable) {
            var asked = wire
            asked.feeToken = feeToken
            if let q = try? await RailgunEngine.shared.quoteTransfer(asked),
               RailgunRouting.covers(amount: wanted, of: token.lowercased(), fee: Decimal(string: PrivateMoney.decimal(hex: q.fee)) ?? 0,
                                     in: feeToken, spendable: spendable) {
                asked.fee = q.fee
                wire = asked
                broadcast = q
            }
        }
        if broadcast == nil, !(await privateGasCovers()) { throw Failure.noPrivateGas }
        NSLog("railgunPocket| transfer quoted | %@ of %@ | %@", amount, token,
              broadcast.map { "fee \(PrivateMoney.decimal(hex: $0.fee)) of \($0.feeToken)" } ?? "fresh sender")
        return TransferPlan(wire: wire, broadcast: broadcast)
    }

    /// Sends the quoted private send through its broadcaster: Face ID, the
    /// proof on this phone, your account nowhere. Returns the hash.
    static func transfer(_ plan: TransferPlan, unlocked: @MainActor () -> Void = {}) async throws -> String {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        guard plan.broadcast != nil, plan.wire.fee != nil else { throw Failure.noBroadcaster }
        try await PrivateRootKey.unlock(reason: String(localized: "Send from Railgun"))
        unlocked()
        let sent = try await RailgunEngine.shared.broadcastTransfer(plan.wire)
        NSLog("railgunPocket| sent privately | %@ | %@ of %@ | proof %d ms", sent.txHash, plan.wire.amount, plan.wire.token, sent.proofMs)
        return sent.txHash
    }

    /// The same send with no broadcaster: a fresh sender, its gas a relayed
    /// withdrawal of your private ETH, sends the proved transfer to Railgun.
    static func transferFromFresh(_ plan: TransferPlan, unlocked: @MainActor () -> Void = {},
                                  stage: @escaping @MainActor (String) -> Void) async throws -> String {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        guard let (need, network) = await senderGasCost(), let ethPool = network.yieldPool(for: PrivateMove.eth) else {
            throw Failure.noPrivateGas
        }
        let sender = try senderAddress()
        try await PrivateRootKey.unlock(reason: String(localized: "Send from Railgun"))
        unlocked()
        let held = Decimal(string: try await PrivateRPC.decimal(network, "eth_getBalance", [sender.address, "latest"])) ?? 0
        if held < need {
            let short = need - held
            let fee = Decimal(string: await PrivateMove.relayerFee(ethPool, network: network, to: sender.address) ?? "") ?? 0
            let spendable = Decimal(string: PrivateMoneyStore.shared.spendable(chainId: network.chainId, symbol: "ETH")) ?? 0
            guard fee > 0, spendable >= short + fee else { throw Failure.noPrivateGas }
            stage(String(localized: "Paying its gas from your private ETH…"))
            let tx = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: PrivateMoney.plain(short), to: sender.address,
                                                      reason: String(localized: "Send from Railgun"))
            guard try await FreshSigner.landed(tx, on: network) else { throw Failure.gasOnItsWay }
        }
        stage(String(localized: "Proving on this iPhone…"))
        try await open(reason: nil)
        var wire = plan.wire
        wire.feeToken = nil
        wire.fee = nil
        let p = try await RailgunEngine.shared.prepareTransfer(wire)
        guard p.tx.to.lowercased() == proxy, p.tx.data.lowercased().hasPrefix(FreshTx.railgunTransact),
              PrivateMoney.decimal(hex: p.tx.value) == "0" else { throw Failure.notRailgun }
        let fees = try await PrivateRPC.fees(network)
        let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                        [["from": sender.address, "to": p.tx.to, "data": p.tx.data, "value": "0x0"]])) ?? 0
        guard estimate > 0, estimate <= FreshTx.railgunSendGas else { throw Failure.notRailgun }
        stage(String(localized: "Sending…"))
        PrivateSendSteps.shared.mark(.sent, from: .railgun)
        let hash = try await FreshSigner.send(to: p.tx.to, data: p.tx.data, value: "0x0", index: sender.index, root: sender.root,
                                              from: sender.address, network: network, gas: FreshTx.railgunSendGas,
                                              tip: fees.tip, maxFee: fees.maxFee) { _, _ in
            UserDefaults.standard.set(Int(sender.index - FreshAddress.senderBase) + 1, forKey: senderKey(sender.root))
        }
        NSLog("railgunPocket| sent privately from a fresh sender | %@ | %@ of %@ | proof %d ms", hash, wire.amount, wire.token, p.proofMs)
        return hash
    }

    /// Your private address on Railgun (prd §1877): what Receive shows for a
    /// payer with a private balance of their own. Opens the wallet; reads only.
    static func privateAddress() async throws -> String {
        try await open(reason: nil).address
    }

    private static func landed(_ sent: YourAccountChain.Sent) -> String? {
        switch sent.outcome {
        case .landed(let tx, _): tx
        case .pending, .dryRun: nil
        }
    }
}

/// **WHEN THE RAILGUN WALLET IS SYNCING (prd §1728 item 3).** Set while
/// `RailgunPocket.sync` runs, so Move can say "Getting your private balance
/// ready · 12 s" in real seconds instead of a word that never changes.
@MainActor
@Observable
final class RailgunSync {
    static let shared = RailgunSync()
    var since: Date?
    /// No trees are kept on this phone yet (the engine's `keptLeaves` is 0):
    /// this sync builds them, the slow one, once (prd §1885).
    var firstTime = false
    /// Railgun's own scan, 0–100: the slower of its two trees.
    var percent: Int?
    /// Bumped when a first sync finishes, trusted: the shell's toast says so.
    var firstReady = 0
    private var trees: [String: Int] = [:]

    /// A scan line from the page: "progress utxo <status> <n>%".
    func heard(_ line: String) {
        let parts = line.split(separator: " ")
        guard parts.count >= 4, parts[0] == "progress", let n = Int(parts.last!.dropLast()) else { return }
        // A finished tree reports "Complete 0%" (measured on the phone,
        // 2026-11-18): complete is all of it.
        trees[String(parts[1])] = parts[2] == "Complete" ? 100 : max(0, min(100, n))
        percent = trees.values.min()
    }

    func reset() {
        trees = [:]
        percent = nil
    }
}
