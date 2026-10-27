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
/// Sepolia only, DEBUG builds only. The demo makes no address and reaches
/// nothing.
@MainActor
@Observable
final class FreshReceive {
    static let shared = FreshReceive()

    private static let key = "freshAddresses.v1"
    /// The roots whose addresses this phone has walked (prd §1562).
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

    /// The address Receive shows: the newest of the current root's (before
    /// the root is read, the newest of all).
    var current: FreshAddress.Entry? {
        let mine = rootID.map { id in entries.filter { $0.root == id } } ?? entries
        return mine.max { ($0.made, $0.index) < ($1.made, $1.index) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }

    private func set(_ id: String, _ state: FreshAddress.State) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].state = state
        save()
    }

    /// The first address of the current root, when there is none yet.
    func ensureCurrent() {
        #if DEBUG
        guard !DemoMode.isActive else { return }
        rootID = try? PrivateRootKey.ensure()
        if current == nil || current?.root != rootID { _ = make() }
        #endif
    }

    /// New address: the next index of the current root, derived on the
    /// phone, never used before.
    @discardableResult
    func make() -> FreshAddress.Entry? {
        #if DEBUG
        guard !DemoMode.isActive else { return nil }
        do {
            let root = try PrivateRootKey.ensure()
            rootID = root
            let index = FreshAddress.nextIndex(entries, root: root)
            let entry = FreshAddress.Entry(index: index, address: try FreshAddressKey.address(index, root: root),
                                           made: Date(), state: .waiting, root: root)
            entries.append(entry)
            save()
            failure = nil
            NSLog("freshAddress| made | %@ | %u | %@", root, index, entry.address)
            return entry
        } catch {
            failure = String(localized: "No new address could be made")
            NSLog("freshAddress| make failed | %@", String(describing: error))
            return nil
        }
        #else
        return nil
        #endif
    }

    /// One look at every watched address; a move for each that was paid
    /// enough. At most every 15 s unless `force`.
    func check(context: ModelContext, force: Bool = false) async {
        #if DEBUG
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
            guard let raw = try? await PrivacyTestnetSender.rpc("eth_getBalance", [entry.address, "latest"]) as? String else {
                continue
            }
            let balance = PrivacyTestnetSender.hexToDecimal(raw)
            NSLog("privateWatch| fresh | %@ | %@ wei", YourAccount.short(entry.address), balance)
            guard balance != "0" else { continue }
            await look(entry, balance: balance, context: context)
        }
        #endif
    }

    #if DEBUG
    // MARK: - A new phone (prd §1562)

    private func markWalked(_ root: String?) {
        if let root { walked.insert(root) } else { walked = [] }
        if let data = try? JSONEncoder().encode(walked.sorted()) { DefaultsWrite.set(data, forKey: Self.walkedKey) }
    }

    /// Walks back the addresses of every root this phone holds and has no
    /// book for: asks each address its balance and nonce through Tor, in
    /// batches to the gap limit, and keeps what the walk found. A root whose
    /// walk could not finish (Tor, the node) is walked again next time.
    func restore() async {
        guard !DemoMode.isActive else { return }
        for (root, _) in PrivateRootKey.roots() where !walked.contains(root) && !PrivateRootKey.madeHere(root) {
            if entries.contains(where: { $0.root == root }) {
                markWalked(root)
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
                            guard let address = try? FreshAddressKey.address(i, root: root) else { return (i, "", nil) }
                            async let balance = PrivacyTestnetSender.rpc("eth_getBalance", [address, "latest"])
                            async let nonce = PrivacyTestnetSender.rpc("eth_getTransactionCount", [address, "latest"])
                            guard let b = try? await balance as? String, let n = try? await nonce as? String else { return (i, address, nil) }
                            return (i, address, .init(index: i, balance: PrivacyTestnetSender.hexToDecimal(b),
                                                      nonce: Int(PrivacyTestnetSender.hexToDecimal(n)) ?? 0))
                        }
                    }
                    var out: [(UInt32, String, PrivateRoot.Seen?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                guard looked.allSatisfy({ $0.2 != nil }) else {
                    NSLog("privateWatch| restore | %@ | the node did not answer for every address; walked again next time", root)
                    return
                }
                for (i, address, s) in looked { addresses[i] = address; seen.append(s!) }
                seen.sort { $0.index < $1.index }
            }
            let book = PrivateRoot.restored(seen)
            for (index, state) in book {
                guard let address = addresses[index] ?? (try? FreshAddressKey.address(index, root: root)) else { continue }
                // Oldest index first, so the newest is the address Receive shows.
                entries.append(.init(index: index, address: address, made: started.addingTimeInterval(Double(index) / 1000),
                                     state: state, root: root))
            }
            save()
            markWalked(root)
            NSLog("privateWatch| restore | %@ | %d asked | %d used | %d in the book | %d s", root, seen.count,
                  seen.filter(\.used).count, book.count, Int(Date().timeIntervalSince(started)))
            for s in seen where s.used {
                NSLog("privateWatch| restore | %@ | %u | %@ | %@ wei | nonce %d", root, s.index,
                      YourAccount.short(addresses[s.index] ?? ""), s.balance, s.nonce)
            }
        }
        rootID = PrivateRootKey.currentID
    }

    // MARK: - A move

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

    private enum FreshFailure: Error { case planned, gas(Int) }

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
