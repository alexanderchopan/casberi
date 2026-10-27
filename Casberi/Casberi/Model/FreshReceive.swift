import Foundation
import Observation
import SwiftData

/// **RECEIVE TO A FRESH ADDRESS (prd §1560, §1562).** The book of fresh
/// addresses and the watch on them.
///
/// Receive with the Private switch on shows the newest address of the
/// current private root (`current`); New address makes the next (`make`).
/// Each look (`check`, while Receive's private sentence shows, while
/// Holdings shows its Private section, and from the background watch,
/// at most every 15 s) asks Sepolia what each watched address holds; what
/// arrived and is worth moving goes into your private balance at once:
///
/// 1. the pool's terms for ETH (`Entrypoint.assets`) and the fees;
/// 2. the deposit planned out of what arrived (`FreshAddress.plan`: the
///    gas comes out of it, the address keeps nothing but dust);
/// 3. the current root's account opens (no prompt: money only goes IN),
///    the deposit is proved for it (an ordinary `prepareDeposit`: the note
///    is yours), checked against the plan and the gas estimate, signed by
///    the FRESH address's key and sent from it;
/// 4. the note is kept waiting for approval (Holdings' "ETH, moving in"),
///    and one Activity row lands, as a deposit's does.
///
/// **A new phone walks them back (prd §1562, `restore`):** every address of
/// a root this phone has no book for is asked its balance and nonce, in
/// order, until twenty in a row were never used (`PrivateRoot.nextBatch`);
/// what was paid and never moved is moved by the next look.
///
/// **On Ethereum (prd §1567)** the same, in every build: what arrives goes
/// into ppETH (earning, §1563), its gas out of what arrived, the address's
/// key from the private root signing its own deposit (`FreshSigner`, only
/// a router's deposit or a token's approval of its router); USDC moves too,
/// its gas paid out of your private ETH. Sepolia stays DEBUG's. The demo
/// makes no address and reaches nothing.
@MainActor
@Observable
final class FreshReceive {
    static let shared = FreshReceive()

    private static let key = "freshAddresses.v1"
    /// The roots whose addresses this phone has walked (prd §1562), by
    /// "root" on Sepolia and "root:chain" elsewhere (prd §1567).
    private static let walkedKey = "freshAddresses.walked.v1"

    private(set) var entries: [FreshAddress.Entry]
    /// Why the last look or move failed, in the line's words.
    private(set) var failure: String?
    /// The root new addresses come from, read in a task (never in a body).
    private(set) var rootID: String?
    @ObservationIgnored private var looking = false
    @ObservationIgnored private var looked: Date = .distantPast
    @ObservationIgnored private var walked: Set<String> = []

    private init() {
        entries = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([FreshAddress.Entry].self, from: $0) } ?? []
        walked = Set(UserDefaults.standard.data(forKey: Self.walkedKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
        // A move cannot outlive the app: one under way when it ended is
        // looked at again, as a failed one is.
        entries = entries.map { entry in
            guard case .moving(let amount) = entry.state else { return entry }
            var next = entry
            next.state = .failed(amount: amount)
            return next
        }
    }

    /// Where Receive shows a fresh address now: Ethereum, or in a DEBUG
    /// build Sepolia unless `-privateNetwork ethereum` (prd §1567). Nil with
    /// the kill switch off.
    var network: PrivacyNetwork? { PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) }

    /// The address Receive shows: the newest of the current root's on this
    /// network (before the root is read, the newest on this network).
    var current: FreshAddress.Entry? {
        let chain = network?.chainId ?? PrivacyNetwork.sepolia.chainId
        let here = entries.filter { $0.network == chain }
        let mine = rootID.map { id in here.filter { $0.root == id } } ?? here
        return mine.max { ($0.made, $0.index) < ($1.made, $1.index) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }

    private func set(_ id: String, _ state: FreshAddress.State, symbol: String? = nil) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].state = state
        entries[i].symbol = symbol
        save()
    }

    /// The first address of the current root on this network, when there is none yet.
    func ensureCurrent() {
        guard !DemoMode.isActive, network != nil else { return }
        rootID = try? PrivateRootKey.ensure()
        if current == nil || current?.root != rootID { _ = make() }
    }

    /// New address: the next index of the current root, derived on the
    /// phone, never used before on any network (one index per address).
    @discardableResult
    func make() -> FreshAddress.Entry? {
        guard !DemoMode.isActive, let network else { return nil }
        do {
            let root = try PrivateRootKey.ensure()
            rootID = root
            let index = FreshAddress.nextIndex(entries, root: root)
            let entry = FreshAddress.Entry(index: index, address: try FreshSigner.address(index, root: root),
                                           made: Date(), state: .waiting, root: root,
                                           chainId: network.isTest ? nil : network.chainId)
            entries.append(entry)
            save()
            failure = nil
            NSLog("freshAddress| made | %@ | %@ | %u | %@", network.name, root, index, entry.address)
            return entry
        } catch {
            failure = String(localized: "No new address could be made")
            NSLog("freshAddress| make failed | %@", String(describing: error))
            return nil
        }
    }

    /// One look at every watched address; a move for each that was paid
    /// enough. At most every 15 s unless `force`. `force` is a person
    /// looking (Receive or Holdings open): only then may a USDC move spend a
    /// little private ETH on its gas, which asks for you (prd §1567).
    func check(context: ModelContext, force: Bool = false) async {
        guard !DemoMode.isActive, !looking, force || Date().timeIntervalSince(looked) > 15 else { return }
        let watched = FreshAddress.watched(entries)
        guard !watched.isEmpty else { return }
        looking = true
        looked = Date()
        defer { looking = false }
        for entry in watched {
            // A failed move is tried again when Receive opens, never by
            // itself every 15 s.
            if case .failed = entry.state, !force { continue }
            guard !Task.isCancelled else { return }
            guard let network = PrivacyNetwork.forChain(entry.network) else { continue }
            guard let balance = try? await PrivateRPC.decimal(network, "eth_getBalance", [entry.address, "latest"]) else { continue }
            if network.isTest {
                #if DEBUG
                NSLog("privateWatch| fresh | %@ | %@ wei", YourAccount.short(entry.address), balance)
                guard balance != "0" else { continue }
                await look(entry, balance: balance, context: context)
                #endif
                continue
            }
            // On Ethereum a fresh address may be paid USDC too (prd §1567).
            let usdcPool = network.yield.first { !$0.native }
            let usdc = usdcPool == nil ? "0" : ((try? await PrivateRPC.tokenBalance(network, token: usdcPool!.underlying, of: entry.address)) ?? "0")
            NSLog("privateWatch| fresh | %@ | %@ | %@ wei | %@ USDC units", network.name, YourAccount.short(entry.address), balance, usdc)
            if usdc != "0", let usdcPool {
                await lookToken(entry, pool: usdcPool, held: usdc, eth: balance, network: network, interactive: force, context: context)
            } else if balance != "0" {
                await lookEthereum(entry, balance: balance, network: network, context: context)
            }
        }
    }

    // MARK: - A new phone (prd §1562)

    private func walkKey(_ root: String, _ network: PrivacyNetwork) -> String {
        network.isTest ? root : "\(root):\(network.chainId)"
    }

    private func markWalked(_ key: String?) {
        if let key { walked.insert(key) } else { walked = [] }
        if let data = try? JSONEncoder().encode(walked.sorted()) { DefaultsWrite.set(data, forKey: Self.walkedKey) }
    }

    /// Walks back the addresses of every root this phone holds and has no
    /// book for on this network: asks each address its balance and nonce
    /// through Tor (and on Ethereum its USDC), in batches to the gap limit,
    /// and keeps what the walk found. A walk that could not finish (Tor, the
    /// node) is walked again next time.
    func restore() async {
        guard !DemoMode.isActive, let network else { return }
        let pending = PrivateRootKey.roots().filter { !walked.contains(walkKey($0.id, network)) && !PrivateRootKey.madeHere($0.id) }
        guard !pending.isEmpty else { return }
        let store = PrivateMoneyStore.shared
        store.beginRestore()
        defer { store.endRestore() }
        let usdcPool = network.isTest ? nil : network.yield.first { !$0.native }
        for (root, _) in pending {
            if entries.contains(where: { $0.root == root && $0.network == network.chainId }) {
                markWalked(walkKey(root, network))
                continue
            }
            let started = Date()
            var seen: [PrivateRoot.Seen] = []
            var addresses: [UInt32: String] = [:]
            while let batch = PrivateRoot.nextBatch(seen) {
                guard !Task.isCancelled else { return }
                let looked = await withTaskGroup(of: (UInt32, String, PrivateRoot.Seen?).self) { group in
                    for i in batch {
                        group.addTask { @MainActor in
                            guard let address = try? FreshSigner.address(i, root: root) else { return (i, "", nil) }
                            async let balance = PrivateRPC.decimal(network, "eth_getBalance", [address, "latest"])
                            async let nonce = PrivateRPC.decimal(network, "eth_getTransactionCount", [address, "latest"])
                            async let token = usdcPool == nil ? "0" : PrivateRPC.tokenBalance(network, token: usdcPool!.underlying, of: address)
                            guard let b = try? await balance, let n = try? await nonce, let t = try? await token else { return (i, address, nil) }
                            // A token paid counts as paid: the walk keeps the address.
                            return (i, address, .init(index: i, balance: b == "0" && t != "0" ? "1" : b, nonce: Int(n) ?? 0))
                        }
                    }
                    var out: [(UInt32, String, PrivateRoot.Seen?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                guard looked.allSatisfy({ $0.2 != nil }) else {
                    NSLog("privateWatch| restore | %@ | %@ | the node did not answer for every address; walked again next time", network.name, root)
                    return
                }
                for (i, address, s) in looked { addresses[i] = address; seen.append(s!) }
                seen.sort { $0.index < $1.index }
            }
            let book = PrivateRoot.restored(seen)
            for (index, state) in book {
                guard let address = addresses[index] ?? (try? FreshSigner.address(index, root: root)) else { continue }
                // Oldest index first, so the newest is the address Receive shows.
                entries.append(.init(index: index, address: address, made: started.addingTimeInterval(Double(index) / 1000),
                                     state: state, root: root, chainId: network.isTest ? nil : network.chainId))
            }
            save()
            markWalked(walkKey(root, network))
            NSLog("privateWatch| restore | %@ | %@ | %d asked | %d used | %d in the book | %d s", network.name, root, seen.count,
                  seen.filter(\.used).count, book.count, Int(Date().timeIntervalSince(started)))
        }
        rootID = PrivateRootKey.currentID
    }

    // MARK: - A move on Ethereum (prd §1567)

    /// The pool's smallest budget in the token, today: its minimum in shares
    /// (`Entrypoint.assets`) at the share's live rate.
    private func minimumBudget(_ pool: PrivacyNetwork.YieldPool, on network: PrivacyNetwork) async -> String? {
        guard let config = await PrivateOnEthereum.terms(pool), config.enabled,
              let answer = await PrivateOnEthereum.ethCall(to: pool.share, data: PrivateYield.exchangeRateCall),
              let rate = PrivateYield.word(answer, 0), rate != "0" else { return nil }
        return FreshAddress.minimumBudget(minimumShares: config.minimum, exchangeRate: rate, shareDecimals: pool.shareDecimals)
    }

    /// ETH at a fresh address on Ethereum: into ppETH, its gas out of what
    /// arrived, or "too little to move" under the pool's smallest deposit
    /// plus the gas (computed now, never a constant).
    private func lookEthereum(_ entry: FreshAddress.Entry, balance: String, network: PrivacyNetwork, context: ModelContext) async {
        guard let pool = network.yieldPool(for: PrivateMove.eth), entry.root != nil else { return }
        do {
            let fees = try await PrivateRPC.fees(network)
            guard let floor = await minimumBudget(pool, on: network) else { throw FreshFailure.terms }
            let plan = FreshAddress.yieldPlan(balance: balance, maxFee: String(fees.maxFee), minimumBudget: floor)
            NSLog("freshAddress| look | %@ | %u | balance %@ | too little below %@ | plan %@", network.name, entry.index, balance,
                  FreshAddress.tooLittleBelow(minimumBudget: floor, maxFee: String(fees.maxFee)) ?? "-",
                  plan.map { "\($0.budget) (+gas \($0.reserve))" } ?? "none")
            guard let plan else {
                if case .waiting = entry.state { set(entry.id, .tooLittle(amount: balance)) }
                return
            }
            await moveEthereum(entry, plan: plan, pool: pool, network: network, fees: fees, context: context)
        } catch {
            failure = PrivateMove.words(error, network: network)
            NSLog("freshAddress| look failed | %@", String(describing: error))
        }
    }

    private func moveEthereum(_ entry: FreshAddress.Entry, plan: FreshAddress.YieldPlan, pool: PrivacyNetwork.YieldPool,
                              network: PrivacyNetwork, fees: (tip: UInt64, maxFee: UInt64), context: ModelContext) async {
        guard let root = entry.root else { return }
        let started = Date()
        set(entry.id, .moving(amount: plan.budget))
        failure = nil
        do {
            // Into the current root's account, owned by your account; no
            // prompt: money only goes in.
            let account = try PrivateRootKey.ensure()
            try await PrivateOnEthereum.open(account, reason: nil)
            guard let budget = PrivateMoney.hex(plan.budget) else { throw FreshFailure.planned }
            let d = try await PrivacyEngine.shared.prepareYieldDeposit(tokenId: PrivateMove.eth, budget: budget)
            guard FreshAddress.matchesYield(to: d.tx.to, value: d.tx.value, approvals: d.approvals.count, budget: plan.budget, pool: pool) else {
                throw FreshFailure.planned
            }
            let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                            [["from": entry.address, "to": d.tx.to, "data": d.tx.data, "value": d.tx.value]])) ?? 0
            NSLog("freshAddress| proved | %@ | %u | %d ms | estimate %d of %d", network.name, entry.index, d.ms, estimate, FreshAddress.gasBudget)
            guard estimate > 0, estimate <= FreshAddress.gasBudget else { throw FreshFailure.gas(estimate) }
            let hash = try await FreshSigner.send(to: d.tx.to, data: d.tx.data, value: d.tx.value, index: entry.index, root: root,
                                                  from: entry.address, network: network, gas: FreshAddress.gasBudget,
                                                  tip: fees.tip, maxFee: fees.maxFee)
            let worth = PrivateMoney.decimal(hex: d.underlyingNeeded)
            landed(entry, hash: hash, d: d, pool: pool, worth: worth, account: account, network: network, context: context)
            NSLog("freshAddress| moved | %@ | %u | %@ | %@ wei | %d s", network.name, entry.index, hash, worth, Int(Date().timeIntervalSince(started)))
        } catch {
            set(entry.id, .failed(amount: plan.budget))
            failure = (error as? FreshFailure).map { _ in String(localized: "The move did not match what arrived") } ?? PrivateMove.words(error, network: network)
            NSLog("freshAddress| move failed | %@ | %u | %@", network.name, entry.index, String(describing: error))
        }
    }

    /// **USDC AT A FRESH ADDRESS, NO GATEKEEPER (prd §1567).** The address
    /// holds no ETH to move it, so your private ETH pays its gas: a relayed
    /// private withdrawal of just enough ETH to the fresh address (the pool
    /// to the address: nothing names your account), then the address
    /// approves its router and deposits the USDC into ppUSDC. Only while you
    /// look (the withdrawal spends private money: it asks for you), and only
    /// when the approved private ETH covers it and the relayer's fee; else
    /// the line says it arrived and needs a little private ETH to move.
    private func lookToken(_ entry: FreshAddress.Entry, pool: PrivacyNetwork.YieldPool, held: String, eth: String,
                           network: PrivacyNetwork, interactive: Bool, context: ModelContext) async {
        guard let root = entry.root, let ethPool = network.yieldPool(for: PrivateMove.eth) else { return }
        let symbol = pool.symbol
        do {
            let fees = try await PrivateRPC.fees(network)
            guard let floor = await minimumBudget(pool, on: network) else { throw FreshFailure.terms }
            guard let have = Decimal(string: held), let least = Decimal(string: floor), have >= least else {
                if case .waiting = entry.state { set(entry.id, .tooLittle(amount: held), symbol: symbol) }
                return
            }
            guard let gas = FreshAddress.tokenGas(ethHeld: eth, maxFee: String(fees.maxFee)) else { return }
            if gas.shortfall != "0" {
                let store = PrivateMoneyStore.shared
                await store.readYield()
                let fee = await PrivateMove.relayerFee(ethPool, network: network, to: entry.address) ?? "0"
                let spendable = Decimal(string: store.spendable(chainId: network.chainId, symbol: "ETH")) ?? 0
                let cost = (Decimal(string: gas.shortfall) ?? 0) + (Decimal(string: fee) ?? 0)
                guard interactive, spendable >= cost else {
                    set(entry.id, .needsGas(amount: held), symbol: symbol)
                    NSLog("freshAddress| needs gas | %u | %@ %@ | short %@ wei | private ETH %@ | asked %@", entry.index, held, symbol,
                          gas.shortfall, PrivateMoney.plain(spendable), interactive ? "yes" : "no (background)")
                    return
                }
                set(entry.id, .moving(amount: held), symbol: symbol)
                let tx = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: gas.shortfall, to: entry.address,
                                                          reason: String(localized: "Move \(symbol) to private"))
                try await PrivateRPC.waitFor(tx, on: network)
                NSLog("freshAddress| gas from private ETH | %u | %@ wei | %@", entry.index, gas.shortfall, tx)
            }
            set(entry.id, .moving(amount: held), symbol: symbol)
            let account = try PrivateRootKey.ensure()
            try await PrivateOnEthereum.open(account, reason: nil)
            guard let budget = PrivateMoney.hex(held) else { throw FreshFailure.planned }
            let d = try await PrivacyEngine.shared.prepareYieldDeposit(tokenId: pool.underlying, budget: budget)
            let most = PrivateMoney.decimal(hex: d.maxUnderlyingIn)
            guard FreshAddress.matchesYield(to: d.tx.to, value: d.tx.value, approvals: d.approvals.count, budget: held, pool: pool),
                  (Decimal(string: most) ?? .greatestFiniteMagnitude) <= have,
                  let approve = FreshTx.approval(pool: pool, amount: most) else { throw FreshFailure.planned }
            // The approval first (its own transaction), then the deposit,
            // estimated against the state the approval left.
            _ = try await FreshSigner.send(to: approve.to, data: approve.data, value: "0x0", index: entry.index, root: root,
                                           from: entry.address, network: network, gas: FreshTx.approveGas,
                                           tip: fees.tip, maxFee: fees.maxFee)
            let estimate = Int(try await PrivateRPC.decimal(network, "eth_estimateGas",
                                                            [["from": entry.address, "to": d.tx.to, "data": d.tx.data, "value": d.tx.value]])) ?? 0
            guard estimate > 0, estimate <= FreshAddress.gasBudget else { throw FreshFailure.gas(estimate) }
            let hash = try await FreshSigner.send(to: d.tx.to, data: d.tx.data, value: d.tx.value, index: entry.index, root: root,
                                                  from: entry.address, network: network, gas: FreshAddress.gasBudget,
                                                  tip: fees.tip, maxFee: fees.maxFee)
            landed(entry, hash: hash, d: d, pool: pool, worth: PrivateMoney.decimal(hex: d.underlyingNeeded), account: account,
                   network: network, context: context)
            NSLog("freshAddress| moved | %@ | %u | %@ | %@ %@ units", network.name, entry.index, hash, held, symbol)
        } catch {
            set(entry.id, .failed(amount: held), symbol: symbol)
            failure = (error as? FreshFailure).map { _ in String(localized: "The move did not match what arrived") } ?? PrivateMove.words(error, network: network)
            NSLog("freshAddress| token move failed | %u | %@", entry.index, String(describing: error))
        }
    }

    /// A fresh address's deposit landed: the note kept waiting for approval,
    /// the address marked, one Activity row.
    private func landed(_ entry: FreshAddress.Entry, hash: String, d: PrivacyEngineWire.PreparedYieldDeposit, pool: PrivacyNetwork.YieldPool,
                        worth: String, account: String, network: PrivacyNetwork, context: ModelContext) {
        PrivateMoneyStore.shared.add(.init(commitment: d.commitment, label: d.label, labelHash: d.labelHash,
                                           symbol: pool.symbol, amount: PrivateMoney.decimal(hex: d.shares), decimals: pool.shareDecimals,
                                           chainId: network.chainId, tx: hash, at: Date(), status: .waiting, root: account, share: pool.share))
        set(entry.id, .moved(amount: worth, tx: hash), symbol: pool.native ? nil : pool.symbol)
        let figure = PrivateMoney.figure(worth, decimals: pool.underlyingDecimals, symbol: pool.symbol)
        PrivateActivity.land(hash: hash, title: PrivateMoney.activityTitle(figure: figure, to: nil), chainId: network.chainId, context: context)
        Task { await PrivateMoneyStore.shared.refresh(force: true) }
    }

    private enum FreshFailure: Error { case planned, gas(Int), terms }

    #if DEBUG
    // MARK: - A move on Sepolia (prd §1560)

    private func look(_ entry: FreshAddress.Entry, balance: String, context: ModelContext) async {
        do {
            let config = try await assetConfig()
            guard config.enabled else { return }
            let price = UInt64(PrivacyTestnetSender.hexToDecimal(try await PrivacyTestnetSender.rpc("eth_gasPrice", []) as? String ?? "0x0")) ?? 0
            let tipRaw = (try? await PrivacyTestnetSender.rpc("eth_maxPriorityFeePerGas", [])) as? String
            let fees = TestnetTx.fees(gasPrice: price, tip: UInt64(PrivacyTestnetSender.hexToDecimal(tipRaw ?? "0x0")) ?? 0)
            let plan = FreshAddress.plan(balance: balance, maxFee: String(fees.maxFee),
                                         vettingBPS: config.vettingBPS, minimum: config.minimum)
            NSLog("freshAddress| look | %u | balance %@ | plan %@", entry.index, balance, plan.map { "\($0.value) (+gas \($0.reserve))" } ?? "none")
            switch FreshAddress.decide(entry, balance: balance, plan: plan) {
            case .nothing: return
            case .tooLittle: set(entry.id, .tooLittle(amount: balance))
            case .move(let plan): await move(entry, plan: plan, fees: fees, context: context)
            }
        } catch {
            failure = PrivateMove.words(error)
            NSLog("freshAddress| look failed | %@", String(describing: error))
        }
    }

    private func move(_ entry: FreshAddress.Entry, plan: FreshAddress.Plan,
                      fees: (tip: UInt64, maxFee: UInt64), context: ModelContext) async {
        let network = PrivacyNetwork.sepolia
        let started = Date()
        set(entry.id, .moving(amount: plan.value))
        failure = nil
        do {
            // Into the current root's account, whichever root the address
            // came from: new money is kept where a new phone finds it.
            let account = try PrivateRootKey.ensure()
            let engine = PrivacyEngine.shared
            try await PrivateAccount.open(account, reason: nil)
            try await PrivateAccount.registerIfNeeded(account)
            guard let value = PrivateMoney.hex(plan.value) else { throw FreshFailure.planned }
            let deposit = try await engine.prepareDeposit(tokenId: PrivateMove.eth, value: value)
            guard deposit.approvals.isEmpty,
                  FreshAddress.matches(to: deposit.tx.to, value: deposit.tx.value, plan: plan, entrypoint: network.entrypoint) else {
                throw FreshFailure.planned
            }
            let call: [String: Any] = ["from": entry.address, "to": deposit.tx.to, "data": deposit.tx.data, "value": deposit.tx.value]
            let estimate = Int(PrivacyTestnetSender.hexToDecimal(try await PrivacyTestnetSender.rpc("eth_estimateGas", [call]) as? String ?? "0x0")) ?? 0
            NSLog("freshAddress| proved | %u | %d ms | estimate %d of %d", entry.index, deposit.ms, estimate, FreshAddress.gasBudget)
            guard estimate > 0, estimate <= FreshAddress.gasBudget else { throw FreshFailure.gas(estimate) }
            let hash = try await PrivacyTestnetSender.send(deposit.tx, key: try FreshAddressKey.key(entry.index, root: entry.root), from: entry.address,
                                                           gas: FreshAddress.gasBudget, tip: fees.tip, maxFee: fees.maxFee)
            PrivateMoneyStore.shared.add(.init(commitment: deposit.commitment, label: deposit.label, labelHash: deposit.labelHash,
                                               symbol: "ETH", amount: plan.value, decimals: 18, chainId: network.chainId,
                                               tx: hash, at: Date(), status: .waiting, root: account))
            set(entry.id, .moved(amount: plan.value, tx: hash))
            let figure = PrivateMoney.figure(plan.value, decimals: 18, symbol: "ETH")
            PrivateActivity.land(hash: hash, title: PrivateMoney.activityTitle(figure: figure, to: nil), context: context)
            NSLog("freshAddress| moved | %u | %@ | %@ ETH wei | label hash %@ | %d s",
                  entry.index, hash, plan.value, deposit.labelHash, Int(Date().timeIntervalSince(started)))
            await PrivateMoneyStore.shared.refresh(force: true)
        } catch {
            set(entry.id, .failed(amount: plan.value))
            failure = (error as? FreshFailure).map { _ in String(localized: "The move did not match what arrived") } ?? PrivateMove.words(error)
            NSLog("freshAddress| move failed | %u | %@", entry.index, String(describing: error))
        }
    }

    /// The pool's terms for ETH, read off the Entrypoint.
    private func assetConfig() async throws -> FreshAddress.AssetConfig {
        let network = PrivacyNetwork.sepolia
        guard let data = FreshAddress.assetsCall(token: PrivateMove.eth),
              let raw = try await PrivacyTestnetSender.rpc("eth_call", [["to": network.entrypoint, "data": data], "latest"]) as? String,
              let config = FreshAddress.assetConfig(raw) else {
            throw PrivacyTestnetSender.Failure.node("the pool's terms")
        }
        return config
    }

    /// The newest address of the current root that was never used: where a
    /// move from another account is withdrawn to (prd §1562), so the watch
    /// moves it in as it would any payment.
    func unusedCurrent() -> FreshAddress.Entry? {
        ensureCurrent()
        if let entry = current, case .waiting = entry.state { return entry }
        return make()
    }

    /// `-freshAddressForget YES`: the book and the device-only root go.
    func forget() {
        entries = []
        failure = nil
        save()
        FreshAddressKey.forget()
    }

    /// `-privateForgetLocal YES` (prd §1562's proof): what this phone keeps
    /// about the roots' addresses goes; the device-only root's stay, and
    /// nothing in the Keychain is touched.
    func forgetRootBook() {
        entries = entries.filter { $0.root == nil }
        failure = nil
        save()
        markWalked(nil)
    }
    #endif
}

/// **A PRIVATE MOVE'S ACTIVITY ROW (prd §1554, §1560).** One Wallet row by
/// its transaction (`private:<hash>`), the words with no verb, Etherscan its
/// door; once per transaction.
enum PrivateActivity {
    @MainActor
    static func land(hash: String, title: String, chainId: Int = PrivacyNetwork.sepolia.chainId, context: ModelContext) {
        let ref = PrivateMoney.activityPrefix + hash.lowercased()
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return }
        let thing = Thing(kind: .link, title: title, content: PrivateMoney.explorerTx(hash, chainId: chainId),
                          source: "Wallet", capturedAt: .now, sourceRef: ref)
        context.insert(thing)
        try? context.save()
        NSLog("privateMove| landed | %@", title)
    }
}
