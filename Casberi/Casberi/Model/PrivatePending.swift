import Foundation
import SwiftData

/// **WHAT WAS SENT AND NOT YET SEEN (the review of 2026-10-26, findings 2
/// and 3).** Your account's operation follows itself for two minutes
/// (`YourAccountChain.submit`); one not seen by then is `.pending` — NOT a
/// failure, and it may still land. Before, a deposit or a round-up ride in
/// that state was simply not recorded: the note was never kept, and the
/// round-ups count stayed whole, so the next send rode or bought it again.
///
/// Now each such operation is kept here by its own id (the user operation's
/// hash) and nonce, with the note it carries (kept at once, waiting) and the
/// round-ups it reserved. `resolve` runs after the pool's notes were read
/// (`PrivateWatch.findNotes`, while Holdings or Needs you shows and in the
/// background pass) and asks the chain: landed (the bundler's receipt, or
/// the note in the pool) lands its Activity row once a transaction is named;
/// failed (a failed receipt, or the nonce taken and the note never in the
/// pool after `PrivateMoney.pendingGrace`) puts the reserve back on the count
/// and drops the note; anything else waits, however long.
@MainActor
final class PrivatePending {
    static let shared = PrivatePending()

    private static let key = "privateMoney.pending.v1"

    private(set) var ops: [PrivateMoney.PendingOp]

    private init() {
        ops = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PrivateMoney.PendingOp].self, from: $0) } ?? []
    }

    func add(_ op: PrivateMoney.PendingOp) {
        ops.removeAll { $0.id == op.id }
        ops.append(op)
        save()
        NSLog("privatePending| kept | %@… | %@ | reserved %@", String(op.id.prefix(10)), op.commitment.map { String($0.prefix(10)) } ?? "no note",
              op.reserved ?? "-")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ops) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }

    /// Asks the chain about each operation still out. Run after the pool's
    /// notes were read, so a note that landed is already in the store.
    func resolve(context: ModelContext?) async {
        guard !ops.isEmpty, !DemoMode.isActive else { return }
        let store = PrivateMoneyStore.shared
        for op in ops {
            guard !Task.isCancelled else { return }
            guard let net = YourAccountOp.networks.first(where: { $0.chainId == op.chainId }),
                  let key = SafeABI.hexBytes(op.nonceKey) else { continue }
            let followup = await YourAccountChain.followup(id: op.id, nonceKey: key, nonce: op.nonce, account: op.account, on: net)
            let carriesNote = op.commitment != nil && !op.exits
            let inPool = carriesNote && op.commitment.map(store.seenInPool) == true
            let verdict = PrivateMoney.pendingVerdict(receipt: followup.receipt, nonceMoved: followup.nonceMoved, inPool: inPool,
                                                      carriesNote: carriesNote, age: Date().timeIntervalSince(op.at))
            NSLog("privatePending| %@… | receipt %@ | nonce moved %@ | in pool %@ | %@", String(op.id.prefix(10)),
                  followup.receipt.map { $0 ? "success" : "failed" } ?? "-", followup.nonceMoved.map { $0 ? "yes" : "no" } ?? "-",
                  inPool ? "yes" : "no", String(describing: verdict))
            switch verdict {
            case .waiting:
                continue
            case .landed:
                if op.exits, let c = op.commitment { store.remove(commitment: c) }
                if let tx = followup.tx, let title = op.title, let context {
                    PrivateActivity.land(hash: tx, title: title, chainId: op.chainId, context: context)
                }
            case .failed:
                // The batch it carried goes back on the count it came off.
                if let reserved = op.reserved {
                    if op.toPrivate {
                        RoundUps.setPrivateSaved(RoundUps.released(reserved, onto: RoundUps.privateSaved(on: op.chainId)), on: op.chainId)
                    } else {
                        RoundUps.setSaved(RoundUps.released(reserved, onto: RoundUps.saved(on: op.chainId)), on: op.chainId)
                    }
                }
                if carriesNote, let c = op.commitment { store.remove(commitment: c) }
            }
            ops.removeAll { $0.id == op.id }
            save()
        }
    }
}
