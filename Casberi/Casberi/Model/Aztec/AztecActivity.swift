import Foundation
import SwiftData

/// **YOUR AZTEC ACCOUNT IN ACTIVITY (prd §1711 item 1).** Every transaction
/// the account sends lands as one Wallet row by its hash
/// (`aztectx:<kind>:<hash>`), the words with no verb, what Aztec charged
/// after the seam, Aztec's explorer its door:
///
/// - gas claimed: "30 Fee Juice as gas — 0.31 Fee Juice fee"
/// - a Shield deposit claimed: "25 USDC to your private account"
/// - a private send: "25 USDC to ...a91c on Aztec"
/// - out through Shield: "25 USDC to ...e07a on Ethereum"
/// - an app's: "Swap on nemi.fi"
///
/// The record is `AztecAccountStore.Sent`, kept first, so a row that could
/// not land (no store yet) lands on the next `landAll`. The explorer path is
/// aztecscan's `tx-effects` page, UNMEASURED: the session that wrote this
/// could not reach aztecscan.xyz.
enum AztecActivity {
    static let activityPrefix = "aztectx:"

    static func isActivity(_ ref: String?) -> Bool { ref?.hasPrefix(activityPrefix) == true }

    /// A private move wears the eye-slash, as 0xBow's do (prd §1554); gas
    /// and an app's transaction are not said to be private.
    static func isPrivate(_ ref: String?) -> Bool {
        guard let ref, isActivity(ref) else { return false }
        let kind = ref.dropFirst(activityPrefix.count).split(separator: ":").first.map(String.init)
        return kind.flatMap(AztecTxKind.init).map(\.isPrivate) ?? false
    }

    static func ref(_ tx: AztecAccountStore.Sent) -> String {
        activityPrefix + tx.kind.rawValue + ":" + tx.hash.lowercased()
    }

    static func explorer(_ hash: String) -> String {
        "https://aztecscan.xyz/tx-effects/\(hash.lowercased())"
    }

    /// The row's title, in `AztecWords`' words.
    static func title(_ tx: AztecAccountStore.Sent) -> String {
        let figure = tx.amountUnits.map {
            PrivateMoney.figure($0, decimals: tx.decimals ?? 18, symbol: tx.symbol ?? "")
        } ?? (tx.symbol ?? "")
        return AztecWords.title(tx.kind, figure: figure, to: tx.to, calls: tx.calls ?? [], fee: tx.fee)
    }

    // MARK: - Landing

    /// The store rows land in, set by the shell at launch, as `SafePeer`'s.
    @MainActor static var contextProvider: (() -> ModelContext?)?

    /// Keeps `tx` and lands its row.
    @MainActor
    static func record(_ tx: AztecAccountStore.Sent) {
        guard !DemoMode.isActive else { return }
        AztecAccountStore.shared.addSent(tx)
        if let context = contextProvider?() { land(tx, context: context) }
        NSLog("aztecActivity| %@ | %@", tx.kind.rawValue, title(tx))
    }

    /// Lands every kept transaction whose row is missing.
    @MainActor
    static func landAll() {
        guard !DemoMode.isActive, let context = contextProvider?() else { return }
        for tx in AztecAccountStore.shared.snapshot.sent ?? [] { land(tx, context: context) }
    }

    @MainActor
    private static func land(_ tx: AztecAccountStore.Sent, context: ModelContext) {
        let key = Self.ref(tx)
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == key }))) ?? 0
        guard existing == 0 else { return }
        context.insert(Thing(kind: .link, title: Self.title(tx), content: Self.explorer(tx.hash),
                             source: "Wallet", capturedAt: tx.at, sourceRef: key))
        try? context.save()
    }
}
