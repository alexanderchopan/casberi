import Foundation

/// WHICH OF THE WALLET'S CARD ROWS ARE SPENDS (prd §1048, step 2). Gnosis
/// Pay, MetaMask Card, ether.fi, Apple Card and Privacy.com ride the Wallet
/// room's query; a row's line names its card when it is one of these. The
/// Cards tile that totalled them is deleted (prd §1105, its place taken by
/// Subscriptions), and with it the per-card reading it drew.
enum WalletCards {

    /// Privacy.com's `Thing.source`, as `PrivacyBridge` stamps it.
    static let privacySource = "Privacy"

    /// Whether a row is a card spend. The three onchain cards go through
    /// `CardSpendSeat`, which already knows that ether.fi's room also holds
    /// unstake and credit-line rows (§868). Apple Wallet's room holds bank
    /// moves, dues, price creep and silences beside its card purchases, so
    /// only a `.transaction` tagged Card counts. A refund is not a spend.
    static func isSpend(_ thing: Thing) -> Bool {
        guard !isRefund(thing) else { return false }
        switch thing.source {
        case GnosisPayBridge.sourceName, MetaMaskCardBridge.source, EtherFiCash.source:
            return CardSpendSeat.isSpend(thing, seat: thing.source)
        case AppleWalletBridge.sourceName:
            return thing.kind == .transaction && thing.tags.contains("Card")
        case privacySource:
            return thing.kind == .transaction
                && (thing.sourceRef?.hasPrefix("privacy:txn:") ?? false)
        default:
            return false
        }
    }

    static func isRefund(_ thing: Thing) -> Bool {
        thing.tags.contains("Refund") || thing.transferDirection == "received"
    }
}
