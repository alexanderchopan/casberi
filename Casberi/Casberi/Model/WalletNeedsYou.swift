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
        if source == SafeBridge.sourceName { return safePending.contains(ref) }
        if source == PrivacyPoolsBridge.sourceName, ref.hasPrefix(PrivacyPoolsRoom.depositPrefix) {
            return PrivacyPoolsRoom.state(tags: tags).map { !$0.resolved } ?? false
        }
        // Off chain: a Wise transfer Wise is holding until you act, and a
        // subscription that went up, until the next charge at the new
        // price would land — the decision is keep it or cancel first.
        if source == WiseShape.source { return WiseShape.isStuck(tags: tags) }
        // A zFi order whose escrow waits on the board (prd §1282), while
        // the live book still says so.
        if ref.hasPrefix(ZFiOrders.reclaimPrefix) { return ZFiOrders.stillWaiting(ref: ref, in: zfi) }
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
