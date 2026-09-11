import SwiftUI

/// **THE HOME SLOT, ONE TEMPLATE FOR EVERY WALLET-FAMILY ROOM (prd §683,
/// user: "Can you make sure we are using the same templates for Wallet, and
/// each devnet please. the home's on all should be same … for the slot").**
///
/// Wallet, Vibenet, Hegotá, Frames and the Privacy devnet each hand-built a
/// Home, and the drift was exactly what you would predict: one drew a
/// sparkline, one drew a ring, one drew a balance hero, one drew a sponsorship
/// figure. Fixing any of them fixed only that one. This is the shape they now
/// share, in the order a person reads it:
///
///   caption → number → change → line → range chips
///
/// and it is `WalletBalanceHeadline` underneath — the Wallet's own crown,
/// which was already parameterised and already tuned (the odometer roll, the
/// scrub, the mark taps, the entrance). Nothing here re-implements it; this
/// view's whole job is to turn a room's samples into the crown's inputs, so
/// that a room supplies FACTS and never layout.
///
/// **The only per-room differences, and they are deliberate:**
///   * `format` / `exactFormat` — the number's unit. The Wallet counts
///     dollars; a devnet counts its own chain's ETH.
///   * what sits BELOW the rail — verb tiles on every devnet, and on the
///     Wallet a Follow-address tile (§683's own amendment), never a list.
///
/// **The room does not pass a slot headline.** The crown owns the number, and
/// a room that also set `DSRoomSlot(headline:)` drew it twice — seen on the
/// simulator the hour this landed, "2.2960 ETH" above "2.2960 ETH".
///
/// **The line appears on the SECOND reading, never the first.** One point is
/// not a history, and a flat line drawn from it would claim a stretch of
/// stability nobody observed (§83). Until then the crown says so itself.
struct RoomHomeCrown: View {
    /// Oldest first. `usd` carries the room's own unit — see
    /// `RoomValueHistory`.
    let samples: [WalletStore.ValueSample]
    /// The scope: one address's name, or how many you follow.
    let caption: String
    var captionAddress: String? = nil
    /// How this room spells a number, rounded and exact.
    var format: (Double) -> String = { WalletValue.money($0) }
    var exactFormat: (Double) -> String = { WalletValue.exactMoney($0) }
    /// Shown when there is no series at all — a room that has read nothing yet
    /// says what it holds rather than drawing a chart of one point.
    var fallbackTotal: Double? = nil
    var chartHeight: CGFloat = DSRoomChassis.crownChart

    @State private var range: WalletRange = WalletRange.remembered(offered: [])

    var body: some View {
        let offered = WalletRange.offered(for: samples)
        let active = offered.contains(range) ? range : WalletRange.remembered(offered: offered)
        let windowed = active.clip(samples)
        let chart = TokenChart.from(samples: windowed)
        WalletBalanceHeadline(
            total: windowed.last?.usd ?? samples.last?.usd ?? fallbackTotal,
            chart: chart,
            caption: caption,
            captionAddress: captionAddress,
            format: format,
            exactFormat: exactFormat,
            chartHeight: chartHeight,
            ranges: offered,
            range: active,
            onPickRange: { picked in
                range = picked
                picked.remember()
            },
            onOpen: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
