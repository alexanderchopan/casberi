import Foundation

/// **THE WALLET'S NEEDS YOU, AS ONE RULE (prd §1201, §1232; Day gathers it,
/// §1327 item 9).** What waits on the person with no date to wait for: a Safe
/// transaction still in the queue, a Privacy Pools deposit not yet cleared, a
/// Wise transfer Wise is holding until you act, a zFi order whose escrow waits
/// on the board, and a subscription that went up, for one monthly cycle.
///
/// The Wallet's Home (`FeedScreen.walletUpcoming`) and Day (`DayNeedsSource`)
/// both ask this, over a row's stored values, so the two places can never
/// disagree about what needs you. Values, not a `Thing`, because Day reads its
/// candidates on a context of its own off the main actor.
///
/// Foundation-only over the names it reads: `scripts/day-needs-selftest.sh`
/// compiles it whole against stubs of those names.
enum WalletNeedsYou {

    /// How long a price rise stands in Needs you: one monthly cycle.
    static let priceRiseWindow: TimeInterval = 30 * 86_400

    /// Whether a row of the Wallet's waits on the person now. `safePending`
    /// is the Safe loop-closer's own queue (`SafeBridge.pendingSnapshot`),
    /// because a queued row keeps its old tags after it executes; `zfi` is the
    /// live book, read for the reclaim rows only.
    static func waiting(source: String, ref: String?, tags: [String], capturedAt: Date,
                        safePending: Set<String>, zfi: ZFiOrders.Book, now: Date) -> Bool {
        guard let ref else { return false }
        // **ONLY WHAT WAITS ON YOU (prd §1340).** A Safe transaction in the
        // queue waits on you only when your signature is the one missing
        // ("Your turn", `SafeRoom.Entry.awaitsYou`): one collecting others'
        // signatures, or fully signed, waits on someone else. A Privacy Pools
        // deposit under review waits on the screener; only one asking for
        // your proof waits on you.
        if source == SafeBridge.sourceName { return safePending.contains(ref) && tags.contains("Your turn") }
        if source == PrivacyPoolsBridge.sourceName, ref.hasPrefix(PrivacyPoolsRoom.depositPrefix) {
            return PrivacyPoolsRoom.state(tags: tags) == .needsProof
        }
        // Off chain: a Wise transfer Wise is holding until you act, and a
        // subscription that went up, until the next charge at the new
        // price would land — the decision is keep it or cancel first.
        if source == WiseShape.source { return WiseShape.isStuck(tags: tags) }
        // A Splits payment waiting on its team's signatures (prd §1618 item
        // 3): the team is yours, so the next signature may be.
        // `SplitsShape.source` and `.waitingTag`, spelled here because the
        // needs-you harness compiles this file without SplitsShape.
        if source == "Splits" { return tags.contains("Waiting") }
        // A zFi order whose escrow waits on the board (prd §1282), while
        // the live book still says so.
        if ref.hasPrefix(ZFiOrders.reclaimPrefix) { return ZFiOrders.stillWaiting(ref: ref, in: zfi) }
        // An Aztec upgrade coming while money sits in zk.money (prd §1446),
        // until it can execute; its date rides the ref.
        if ref.hasPrefix("aztec:upgrade:") { return AztecStakeWire.upgradeWaiting(ref: ref, now: now) }
        if source == AppleWalletBridge.sourceName, tags.contains("Price rise") {
            return now.timeIntervalSince(capturedAt) < priceRiseWindow
        }
        return false
    }

    /// Whether the rule needs the zFi book for this row at all — Day reads
    /// the book only when a reclaim row is among its candidates.
    static func readsBook(ref: String?) -> Bool {
        ref?.hasPrefix(ZFiOrders.reclaimPrefix) ?? false
    }
}
