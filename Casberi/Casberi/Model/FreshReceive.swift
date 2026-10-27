import Foundation
import Observation
import SwiftData

/// **RECEIVE TO A FRESH ADDRESS (prd §1560).** The book of fresh addresses
/// and the watch on them.
///
/// Receive with the Private switch on shows the newest address
/// (`current`); New address makes the next (`make`). Each look (`check`,
/// while Receive's private sentence shows and while Holdings shows its
/// Private section, at most every 15 s) asks Sepolia what each watched
/// address holds; what arrived and is worth moving goes into your private
/// balance at once:
///
/// 1. the pool's terms for ETH (`Entrypoint.assets`) and the fees;
/// 2. the deposit planned out of what arrived (`FreshAddress.plan`: the
///    gas comes out of it, the address keeps nothing but dust);
/// 3. Face ID opens your private account, the deposit is proved for it
///    (an ordinary `prepareDeposit`: the note is yours), checked against
///    the plan and the gas estimate, signed by the FRESH address's key and
///    sent from it;
/// 4. the note is kept waiting for approval (Holdings' "ETH, moving in"),
///    and one Activity row lands, as a deposit's does.
///
/// Sepolia only, DEBUG builds only: the owner of your private account is
/// the DEBUG testnet sender (`PrivacyTestnetSender`) until your account
/// sends. The demo makes no address and reaches nothing.
@MainActor
@Observable
final class FreshReceive {
    static let shared = FreshReceive()

    private static let key = "freshAddresses.v1"

    private(set) var entries: [FreshAddress.Entry]
    /// Why the last look or move failed, in the line's words.
    private(set) var failure: String?
    @ObservationIgnored private var looking = false
    @ObservationIgnored private var looked: Date = .distantPast

    private init() {
        entries = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([FreshAddress.Entry].self, from: $0) } ?? []
        // A move cannot outlive the app: one under way when it ended is
        // looked at again, as a failed one is.
        entries = entries.map { entry in
            guard case .moving(let amount) = entry.state else { return entry }
            var next = entry
            next.state = .failed(amount: amount)
            return next
        }
    }

    /// The address Receive shows: the newest.
    var current: FreshAddress.Entry? { entries.max { $0.index < $1.index } }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }

    private func set(_ index: UInt32, _ state: FreshAddress.State) {
        guard let i = entries.firstIndex(where: { $0.index == index }) else { return }
        entries[i].state = state
        save()
    }

    /// The first address, when there is none yet.
    func ensureCurrent() {
        if current == nil { _ = make() }
    }

    /// New address: the next index, derived on the phone, never used before.
    @discardableResult
    func make() -> FreshAddress.Entry? {
        #if DEBUG
        guard !DemoMode.isActive else { return nil }
        let index = FreshAddress.nextIndex(entries)
        do {
            let entry = FreshAddress.Entry(index: index, address: try FreshAddressKey.address(index), made: Date(), state: .waiting)
            entries.append(entry)
            save()
            failure = nil
            NSLog("freshAddress| made | %u | %@", index, entry.address)
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
            // itself every 15 s (each try asks Face ID).
            if case .failed = entry.state, !force { continue }
            guard let raw = try? await PrivacyTestnetSender.rpc("eth_getBalance", [entry.address, "latest"]) as? String else {
                continue
            }
            let balance = PrivacyTestnetSender.hexToDecimal(raw)
            guard balance != "0" else { continue }
            await look(entry, balance: balance, context: context)
        }
        #endif
    }

    #if DEBUG
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
            case .tooLittle: set(entry.index, .tooLittle(amount: balance))
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
        set(entry.index, .moving(amount: plan.value))
        failure = nil
        do {
            let owner = try PrivacyTestnetSender.ensure()
            if !PrivacyPoolsKey.exists() { try PrivacyPoolsKey.create() }
            var seed = try PrivacyPoolsKey.seed(reason: String(localized: "Move what you received to your private balance"))
            defer { seed.resetBytes(in: 0..<seed.count) }
            let engine = PrivacyEngine.shared
            _ = try await engine.open(seed: seed, owner: owner, network: network)
            seed.resetBytes(in: 0..<seed.count)
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
            let hash = try await PrivacyTestnetSender.send(deposit.tx, key: try FreshAddressKey.key(entry.index), from: entry.address,
                                                           gas: FreshAddress.gasBudget, tip: fees.tip, maxFee: fees.maxFee)
            PrivateMoneyStore.shared.add(.init(commitment: deposit.commitment, label: deposit.label, labelHash: deposit.labelHash,
                                               symbol: "ETH", amount: plan.value, decimals: 18, chainId: network.chainId,
                                               tx: hash, at: Date(), status: .waiting))
            set(entry.index, .moved(amount: plan.value, tx: hash))
            let figure = PrivateMoney.figure(plan.value, decimals: 18, symbol: "ETH")
            PrivateActivity.land(hash: hash, title: PrivateMoney.activityTitle(figure: figure, to: nil), context: context)
            NSLog("freshAddress| moved | %u | %@ | %@ ETH wei | label hash %@ | %d s",
                  entry.index, hash, plan.value, deposit.labelHash, Int(Date().timeIntervalSince(started)))
            await PrivateMoneyStore.shared.refresh(force: true)
        } catch {
            set(entry.index, .failed(amount: plan.value))
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

    /// `-freshAddressForget YES`: the book and the root go.
    func forget() {
        entries = []
        failure = nil
        save()
        FreshAddressKey.forget()
    }
    #endif
}

/// **A PRIVATE MOVE'S ACTIVITY ROW (prd §1554, §1560).** One Wallet row by
/// its transaction (`private:<hash>`), the words with no verb, Etherscan its
/// door; once per transaction.
enum PrivateActivity {
    @MainActor
    static func land(hash: String, title: String, context: ModelContext) {
        let ref = PrivateMoney.activityPrefix + hash.lowercased()
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return }
        let thing = Thing(kind: .link, title: title, content: "https://sepolia.etherscan.io/tx/" + hash,
                          source: "Wallet", capturedAt: .now, sourceRef: ref)
        context.insert(thing)
        try? context.save()
        NSLog("privateMove| landed | %@", title)
    }
}
