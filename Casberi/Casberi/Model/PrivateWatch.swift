import BackgroundTasks
import Foundation
import SwiftData

/// **THE PRIVATE WATCH, IN THE BACKGROUND (prd §1562).**
///
/// A `BGAppRefreshTask` (`taskID`, in Info.plist's
/// `BGTaskSchedulerPermittedIdentifiers`) that looks at the fresh addresses
/// for payments and moves them into your private balance, and asks 0xBow's
/// ASP whether a deposit waiting for approval was approved. It says nothing
/// of its own: a move lands its Activity row, and the app's one notification
/// pass (`WalletBackgroundRefresh.runNotifySweep`, the Wallet switch, prd
/// §1237) decides what is told.
///
/// **Through Tor or not at all.** Every read names a fresh address or the
/// pool. iOS gives a refresh about 30 s; tor takes 20–97 s to connect on a
/// cold start (measured, §1554), so the pass waits for Tor for at most
/// `torShare` of its budget and, if it is not up, asks nothing and ends
/// (`privateWatch| tor | not ready`): the next foreground does the work.
/// A process iOS only resumed keeps its running tor and usually gets
/// through.
///
/// iOS decides if and when it runs (never on the Simulator);
/// `-backgroundRefreshProbe YES` runs the same body in the foreground with
/// the same budget and logs `privateWatch|` lines.
enum PrivateWatchTask {
    static let taskID = "com.casberi.app.privatewatch"
    /// iOS's ~30 s, less a margin for completing in time.
    static let budget: TimeInterval = 25
    /// How much of the budget Tor may take to connect.
    static let torShare = 0.6

    /// Registered once at launch (CasberiApp.init), before launch finishes.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false); return
            }
            handle(refresh)
        }
    }

    /// Asks iOS for a run in 15 minutes or later, only while something
    /// private could change: a fresh address, or a deposit waiting.
    @MainActor
    static func schedule() {
        guard PrivateMove.available, !DemoMode.isActive,
              !FreshReceive.shared.entries.isEmpty || PrivateMoney.anyWaiting(PrivateMoneyStore.shared.notes)
                || !PrivatePending.shared.ops.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        Task { @MainActor in schedule() }
        let done = Once()
        let work = Task { @MainActor in
            var ok = true
            if let context = SharedStore.live?.mainContext {
                ok = await PrivateWatch.run(context: context, budget: budget, why: "background")
            }
            await WalletBackgroundRefresh.runNotifySweep()
            done.run { task.setTaskCompleted(success: ok && !Task.isCancelled) }
        }
        task.expirationHandler = {
            work.cancel()
            done.run { task.setTaskCompleted(success: false) }
        }
    }

    /// Apple wants exactly one `setTaskCompleted`.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var ran = false
        func run(_ body: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !ran else { return }
            ran = true
            body()
        }
    }
}

/// The watch's one pass, shared by the background task and its probe. In
/// every build since prd §1567: on Ethereum it asks the ASP about every
/// waiting deposit and moves what a fresh address was paid (ETH, its gas out
/// of what arrived); a USDC payment that needs your private ETH for its gas
/// waits for you to look, since that spends private money and asks for you.
@MainActor
enum PrivateWatch {

    /// One pass inside `budget` seconds: Tor, then the ASP, then (on a
    /// phone that has not found them) each root's notes, then the fresh
    /// addresses (walked back first on a new phone) and a move for each
    /// one paid. False when it could not do its work (Tor not up in time).
    @discardableResult
    static func run(context: ModelContext, budget: TimeInterval, why: String) async -> Bool {
        let started = Date()
        func left() -> TimeInterval { budget - Date().timeIntervalSince(started) }
        let store = PrivateMoneyStore.shared
        let fresh = FreshReceive.shared
        let roots = PrivateRootKey.roots()
        NSLog("privateWatch| start | %@ | budget %.0f s | %d roots | %d notes | %d fresh addresses | tor %@",
              why, budget, roots.count, store.notes.count, fresh.entries.count, String(describing: TorStatus.shared.state))
        guard !DemoMode.isActive else { NSLog("privateWatch| demo | nothing asked"); return true }
        guard !roots.isEmpty || !store.notes.isEmpty || !fresh.entries.isEmpty else {
            NSLog("privateWatch| nothing private on this phone")
            return true
        }
        // Tor first: no read here goes around it.
        if TorRoute.available {
            TorClient.shared.start()
            let deadline = budget * PrivateWatchTask.torShare
            while !isReady(TorStatus.shared.state), Date().timeIntervalSince(started) < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            let waited = Date().timeIntervalSince(started)
            guard isReady(TorStatus.shared.state) else {
                NSLog("privateWatch| tor | not ready in %.1f s (%@) | nothing asked", waited, String(describing: TorStatus.shared.state))
                return false
            }
            NSLog("privateWatch| tor | ready after %.1f s", waited)
        }
        // Approvals: cheap, one request a waiting note.
        let waitingBefore = store.notes.filter { PrivateMoney.kind($0.status) == .waiting }.count
        await store.refresh(force: true)
        NSLog("privateWatch| asp | %d waiting before | %d after | %.1f s", waitingBefore,
              store.notes.filter { PrivateMoney.kind($0.status) == .waiting }.count, Date().timeIntervalSince(started))
        // A new phone: each root's notes found again from the pool's events;
        // on any phone, every root's notes on a cadence, and what was sent and
        // not seen asked about (the review of 2026-10-26, finding 2).
        if left() > 15 { await findNotes(context: context) }
        // The fresh addresses: walked back, then looked at, a move for each paid.
        // The walk took 13 s through Tor for twenty-one addresses (measured):
        // in a 25 s background pass it waits for a later one or the foreground.
        if left() > 15, !Task.isCancelled { await fresh.restore() }
        if left() > 5, !Task.isCancelled { await fresh.check(context: context, force: why != "background") }
        NSLog("privateWatch| done | %@ | %.1f s of %.0f | %d notes | %d fresh addresses", why,
              Date().timeIntervalSince(started), budget, store.notes.count, fresh.entries.count)
        return !Task.isCancelled
    }

    #if DEBUG
    /// `-privateRecoveryProbe`: each root by its public id (never its
    /// bytes), its owner, the notes by account, the fresh book by root.
    static func logState() {
        for (id, made) in PrivateRootKey.roots() {
            NSLog("privateRoot| root | %@ | made %@ | owner %@ | notes found here %@", id, made.formatted(.iso8601),
                  (try? PrivateAccount.ownerAddress(id)) ?? "-", PrivateRootKey.found(id) ? "yes" : "no")
        }
        NSLog("privateRoot| device-only account | %@ | sender %@ | iCloud %@",
              PrivateAccount.legacyExists ? "here" : "none", (try? PrivacyTestnetSender.ensure()) ?? "-",
              PrivateRootKey.iCloudSignedIn ? "signed in" : "signed out")
        for n in PrivateMoneyStore.shared.notes {
            NSLog("privateRoot| note | %@ | %@ wei | %@ | %@", n.root ?? PrivateRoot.legacy, n.amount,
                  n.status.rawValue, n.labelHash.isEmpty ? "no hash" : "hash")
        }
        for e in FreshReceive.shared.entries {
            NSLog("privateRoot| fresh | %@ | %u | %@ | %@", e.root ?? PrivateRoot.legacy, e.index,
                  YourAccount.short(e.address), String(describing: e.state))
        }
    }
    #endif

    private static func isReady(_ state: TorState) -> Bool {
        if case .ready = state { return true }
        return false
    }

    /// Each root whose notes this phone has not found yet: its account
    /// opened from the root alone (no prompt: nothing spends), the pool's
    /// events read with its keys, the notes kept, their approval asked.
    static func restoreNotes() async {
        let store = PrivateMoneyStore.shared
        guard let network = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) else { return }
        let pending = PrivateRootKey.roots().filter { !PrivateRootKey.found($0.id) }
        // "Restoring your private balance" (prd §1567) only where something
        // comes back: a root this phone did not make.
        let restoring = pending.contains { !PrivateRootKey.madeHere($0.id) }
        if restoring { store.beginRestore() }
        defer { if restoring { store.endRestore() } }
        for (root, _) in pending {
            guard !Task.isCancelled else { return }
            if await findNotes(of: root, on: network) { PrivateRootKey.markFound(root) }
        }
        await store.refresh(force: true)
    }

    /// One root's notes, read from the pool with its keys and kept: alone
    /// through the engine (finding 8), opened from the root (no prompt:
    /// nothing spends). False when it could not be read.
    @discardableResult
    static func findNotes(of root: String, on network: PrivacyNetwork) async -> Bool {
        let store = PrivateMoneyStore.shared
        // On Ethereum the owner is your account: none, nothing to find yet.
        guard network.isTest || PrivateOnEthereum.owner != nil else { return false }
        let started = Date()
        do {
            let found = try await PrivacyEngine.exclusive {
                if network.isTest {
                    #if DEBUG
                    try await PrivateAccount.open(root, reason: nil)
                    #endif
                } else {
                    try await PrivateOnEthereum.open(root, reason: nil)
                }
                return try await PrivacyEngine.shared.discover()
            }
            store.reconcile(found, root: root, network: network)
            await store.fillLabelHashes()
            NSLog("privateWatch| notes | %@ | %@ | %d found | %d unspent | %d s", network.name, root, found.notes.count,
                  store.notes.filter { $0.root == root }.count, Int(Date().timeIntervalSince(started)))
            return true
        } catch {
            NSLog("privateWatch| notes | %@ | failed | %@", root, String(describing: error))
            return false
        }
    }

    /// **EVERY ROOT'S NOTES, ON A CADENCE (the review of 2026-10-26, finding
    /// 2).** Not only a new phone's: each root's notes are read from the pool
    /// again at most every `findEvery` while Holdings or Needs you shows and
    /// in the background pass (every `findEverySoon` while something is out
    /// and not yet seen), so a deposit that landed and was never kept — the
    /// app closed, a wait ended — is found and kept. Then every operation
    /// sent and not seen is asked about (`PrivatePending.resolve`).
    static let findEvery: TimeInterval = 10 * 60
    static let findEverySoon: TimeInterval = 60
    private static var lastFound: Date = .distantPast

    static func findNotes(context: ModelContext?, force: Bool = false) async {
        guard !DemoMode.isActive, let network = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) else { return }
        let known = Set(PrivateRootKey.roots().map(\.id).filter(PrivateRootKey.found))
        await restoreNotes()
        let soon = !PrivatePending.shared.ops.isEmpty || FreshReceive.shared.entries.contains(where: \.isSent)
        if force || Date().timeIntervalSince(lastFound) > (soon ? findEverySoon : findEvery) {
            lastFound = Date()
            for root in known.sorted() {
                guard !Task.isCancelled else { break }
                await findNotes(of: root, on: network)
            }
        }
        await PrivatePending.shared.resolve(context: context)
    }
}

#if DEBUG

/// **MOVING THE DEVICE-ONLY ACCOUNT IN (prd §1562).** What the account made
/// before the root holds, approved, is withdrawn through 0xBow's relayer to a
/// fresh address of the current root, and the watch deposits it from there
/// into the root's account, as any payment. Face ID opens the device-only
/// seed. What waits for approval waits; what the relayer's fee would mostly
/// eat stays.
@MainActor
enum PrivateMigration {
    enum Outcome: Equatable { case nothing, moved(String), failed(String) }

    static func run(context: ModelContext) async -> Outcome {
        // Alone through the engine (finding 8): the device-only account stays
        // open from the discovery to the relay.
        await PrivacyEngine.exclusive { await runAlone(context: context) }
    }

    private static func runAlone(context: ModelContext) async -> Outcome {
        guard PrivateAccount.legacyExists, !DemoMode.isActive else { return .nothing }
        let store = PrivateMoneyStore.shared
        let engine = PrivacyEngine.shared
        do {
            try await PrivateAccount.open(PrivateRoot.legacy, reason: String(localized: "Back up your private balance"))
            store.reconcile(try await engine.discover(), root: nil)
            await store.refresh(force: true)
            let legacy = store.notes.filter { $0.root == nil }
            let spendable = PrivateMoney.spendable(legacy, chainId: PrivacyNetwork.sepolia.chainId)
            var terms = PrivateMoney.measuredTerms
            if let url = URL(string: PrivacyNetwork.sepolia.relayerUrl + "/v1/details/evm/\(PrivacyNetwork.sepolia.chainId)"),
               let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: PrivacyEngine.service),
               http.statusCode == 200, let read = PrivateMoney.relayerTerms(data) {
                terms = read
            }
            guard let amount = PrivateRoot.migrationAmount(spendable: spendable, terms: terms), let hex = PrivateMoney.hex(amount) else {
                NSLog("privateMigrate| nothing worth moving | spendable %@ wei", spendable)
                return .nothing
            }
            guard let to = FreshReceive.shared.unusedCurrent() else { return .failed(String(localized: "No new address could be made")) }
            // The device-only account is open again: making the address read the root, not the engine.
            let spend = try await engine.prepareWithdraw(tokenId: PrivateMove.eth, amount: hex, to: to.address)
            let relayed = try await engine.relay(handle: spend.handle)
            NSLog("privateMigrate| withdrawn | %@ wei | to %@ (%@ %u) | %@", amount, YourAccount.short(to.address),
                  to.root ?? PrivateRoot.legacy, to.index, relayed.tx)
            if let after = try? await engine.discover() { store.reconcile(after, root: nil) }
            // The watch moves it in from the fresh address.
            await FreshReceive.shared.check(context: context, force: true)
            return .moved(relayed.tx)
        } catch {
            NSLog("privateMigrate| failed | %@", String(describing: error))
            return .failed(PrivateMove.words(error))
        }
    }

    /// Whether the device-only account holds what should be moved in: an
    /// approved balance worth a withdrawal, or a deposit still waiting.
    static func needed(_ notes: [PrivateMoney.Note]) -> Bool {
        let legacy = notes.filter { $0.root == nil }
        let spendable = PrivateMoney.spendable(legacy, chainId: PrivacyNetwork.sepolia.chainId)
        return PrivateRoot.migrationAmount(spendable: spendable, terms: PrivateMoney.measuredTerms) != nil
            || legacy.contains { PrivateMoney.kind($0.status) == .waiting }
    }
}
#endif
