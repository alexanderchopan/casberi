import Foundation
import Observation
import SwiftData

/// **TAKE IT BACK (prd §1561).** A deposit 0xBow's ASP refused (or wants a
/// proof for, or has left waiting past a week) comes back the public way: the
/// pool's ragequit, which needs no approval. The circuit fixes where it goes —
/// the address that owns the private account, the one the deposit came from —
/// and it takes the whole note.
///
/// The steps: the private account's seed behind Face ID, the account opened
/// and its notes found (the engine must hold the note), the ragequit proved on
/// the phone, the transaction run against the latest block (`eth_call`) and
/// refused there if it would revert, then signed and sent by the owner. Done,
/// the note leaves the store (and Needs you), and Activity gets one row with
/// no verb: "0.0001 ETH back to ...DeBb".
///
/// On Sepolia (DEBUG builds only) the owner is the DEBUG test sender; on
/// Ethereum (prd §1563) it is your account, which sends the ragequit and the
/// zap that turns its shares back into the token in one Face ID operation.
@MainActor
@Observable
final class PrivateTakeBack {
    static let shared = PrivateTakeBack()

    enum Stage: Equatable {
        case opening, preparing, proving, checking, sending
        /// On Ethereum: your account's operation, waiting to land.
        case landing
        case failed(String)
    }

    /// What each note being taken back is doing, by commitment.
    private(set) var stages: [String: Stage] = [:]

    func stage(_ note: PrivateMoney.Note) -> Stage? { stages[note.commitment] }

    /// Whether any take-back is under way: one at a time.
    var busy: Bool {
        stages.values.contains { if case .failed = $0 { false } else { true } }
    }

    /// The stage in Needs you's own words, for the row's line.
    static func words(_ stage: Stage) -> String {
        switch stage {
        case .opening: String(localized: "Confirm with Face ID")
        case .preparing: String(localized: "Preparing…")
        case .proving: String(localized: "Proving…")
        case .checking: String(localized: "Checking…")
        case .sending: String(localized: "Waiting for Sepolia…")
        case .landing: String(localized: "Waiting for Ethereum…")
        case .failed(let why): why
        }
    }

    /// Takes one note back; returns the landed transaction's hash, or nil.
    @discardableResult
    func run(_ note: PrivateMoney.Note, context: ModelContext?) async -> String? {
        let id = note.commitment
        guard !busy else { return nil }
        // On Ethereum (prd §1563): the ragequit and the zap in one Face ID
        // operation from your account, the owner the pool pays.
        if note.chainId == PrivacyNetwork.ethereum.chainId {
            if DemoMode.isActive || note.labelHash == "0" {
                stages[id] = .failed(DemoMode.isActive ? YourAccountDemo.actsLater : String(localized: "A sample: nothing to take back"))
                return nil
            }
            do {
                stages[id] = .preparing
                let (hash, figure) = try await PrivateOnEthereum.takeBack(note)
                stages[id] = nil
                if let context, let owner = PrivateOnEthereum.owner {
                    PrivateActivity.land(hash: hash, title: PrivateMoney.takenBackTitle(figure: figure, to: YourAccount.short(owner)),
                                         chainId: note.chainId, context: context)
                }
                NSLog("privateTakeBack| ethereum landed | %@ | %@", hash, figure)
                return hash
            } catch {
                stages[id] = .failed(PrivateMove.words(error, network: .ethereum))
                NSLog("privateTakeBack| ethereum failed | %@", String(describing: error))
                return nil
            }
        }
        #if DEBUG
        if DemoMode.isActive {
            stages[id] = .failed(YourAccountDemo.actsLater)
            return nil
        }
        // `-privateNeedsSample`'s rows have no deposit behind them.
        if note.labelHash == "0" {
            stages[id] = .failed(String(localized: "A sample: nothing to take back"))
            return nil
        }
        let engine = PrivacyEngine.shared
        let started = Date()
        do {
            // The note's own account (prd §1562): the device-only one or a root's.
            let account = note.root ?? PrivateRoot.legacy
            stages[id] = .opening
            let owner = try await PrivateAccount.open(account, reason: String(localized: "Take it back"))
            stages[id] = .preparing
            PrivateMoneyStore.shared.reconcile(try await engine.discover(), root: note.root)
            stages[id] = .proving
            let quit = try await engine.prepareRagequit(commitment: note.commitment)
            NSLog("privateTakeBack| proved | %@ wei | %d ms", PrivateMoney.decimal(hex: quit.value), quit.ms)
            // The circuit sends it to the account's owner; anything else is
            // not the way back this act promises.
            guard quit.recipient.lowercased() == owner.lowercased() else {
                throw PrivacyEngineWire.Failure(name: "NotOwner", message: "the ragequit pays \(quit.recipient)")
            }
            stages[id] = .checking
            try await PrivacyTestnetSender.simulate(quit.tx)
            stages[id] = .sending
            // A root's owner sends its own ragequit; the device-only account's is the sender.
            let hash = try await (note.root == nil
                ? PrivacyTestnetSender.send(quit.tx)
                : PrivacyTestnetSender.send(quit.tx, key: try PrivateAccount.ownerKey(account), from: owner))
            PrivateMoneyStore.shared.remove(commitment: note.commitment)
            stages[id] = nil
            let figure = PrivateMoney.figure(PrivateMoney.decimal(hex: quit.value), decimals: 18, symbol: "ETH")
            if let context { PrivateActivity.land(hash: hash, title: PrivateMoney.takenBackTitle(figure: figure, to: YourAccount.short(owner)), context: context) }
            NSLog("privateTakeBack| landed | %@ | %@ | %d s", hash, figure, Int(Date().timeIntervalSince(started)))
            return hash
        } catch {
            stages[id] = .failed(PrivateMove.words(error))
            NSLog("privateTakeBack| failed | %@", String(describing: error))
            return nil
        }
        #else
        stages[id] = .failed(String(localized: "Not in this build"))
        return nil
        #endif
    }

}
