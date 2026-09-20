import Foundation
import SwiftData

/// The MetaMask Card room head's reading half (2026-09-20, prd §858) — landed
/// rows turned into the card's own value, with every judgement left to
/// `CardSpendRoom`.
///
/// The split is `CursorRoomSource`'s, and the JUDGEMENT half is shared with
/// Gnosis Pay rather than copied: currencies summed into one figure, a spend
/// with no readable amount counted as zero, a month-on-month claim made
/// against a window the room never observed — every one of those lives in
/// `CardSpendRoom`, in a file the harness compiles whole. What is left here is
/// the seat: which `Thing.source` to filter on, and what the probe calls its
/// lines.
///
/// **This seat's history is SHORTER than Gnosis Pay's, and the head already
/// handles it.** `MetaMaskCardBridge` backfills about six days on Linea and
/// one on Base (prd §857b — Base's only usable host serves 2,000 blocks at a
/// time), so a fresh connection cannot know a prior 30-day window at all.
/// `CardSpendRoom.knowsPriorWindow` refuses the comparison rather than
/// estimating it, which is exactly the case it was written for; nothing extra
/// is needed here, and nothing here may work around it.
enum MetaMaskCardRoomSource {

    /// The bridge's own source name, taken from the bridge rather than spelled
    /// again — see `PeerBridge.sourceName`.
    static let source = MetaMaskCardBridge.source

    /// Forwards to the shared cap, like its sibling. MetaMask Card can settle
    /// in seven currencies across its two chains (USD via five stablecoins,
    /// plus EUR and GBP on Linea), which is still inside it.
    static let rowCap = CardSpendRoom.rowCap

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> CardSpendRoom? {
        // Live at the BOUNDARY, before any stored property is read
        // (corollary 4).
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = CardSpendRoom.compose(spends: rows.map(sighting), now: now)
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to what the head reads. The ONLY place a `Thing`
    /// is touched.
    ///
    /// `priceValue`/`priceCurrency` are read as DATA — never `transferAmount`,
    /// which is the token-denominated display string ("12.40 USDC") and would
    /// have to be parsed back apart, and never the title, which is prose.
    ///
    /// A WETH spend carries NEITHER field on purpose (prd §857: the chain has
    /// no price at the moment of the swipe, so writing a bare number would read
    /// as dollars downstream). It arrives here as an unreadable amount and is
    /// COUNTED as `unpriced` rather than dropped silently — which is the right
    /// answer, and is why the card states that count.
    @MainActor
    private static func sighting(_ thing: Thing) -> CardSpendRoom.Sighting {
        CardSpendRoom.Sighting(amount: thing.priceValue,
                               currency: thing.priceCurrency,
                               at: thing.capturedAt)
    }

    /// The probe's lines — driven by `-metamaskCardRoomProbe`, calling the REAL
    /// `compose`. `now` is taken so a run can be composed against a fixed clock
    /// and the window boundaries checked.
    ///
    /// It exists because a thin or empty head has SIX causes that render as one
    /// silence, and only the last two are bugs. Five are its sibling's; the
    /// sixth is this seat's own:
    ///
    ///   1. no wallet is watched, or none of them is a card account — most
    ///      wallets hold no MetaMask Card, which is why the seat is gated on a
    ///      SPEND rather than on a watch;
    ///   2. the card exists and was not used in the last 30 days — a real
    ///      answer the card states out loud;
    ///   3. the room is younger than 60 days, so no comparison is possible and
    ///      `prior` is nil throughout — correct, and easily read as a missing
    ///      feature. It is the COMMON case here for longer than at Gnosis Pay,
    ///      because the backfill is six days at most;
    ///   4. every spend is in WETH, which carries no `priceValue` by design —
    ///      so the window has real spending and no total, and `unpriced` is the
    ///      only thing that says so;
    ///   5. the token's decimals never resolved, so the amount is unreadable
    ///      while the rows still show a title — indistinguishable from 4 on
    ///      screen, which is why the probe prints the currency per spend;
    ///   6. `priceCurrency` missing while the amount is there, which drops the
    ///      spend from every total with nothing on screen to say so.
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        let sightings = rows.map(sighting)
        var out: [String] = [
            "metamaskCardRoom| source=\(source) handed=\(things.count) mmRows=\(rows.count)"
                + " windowDays=\(CardSpendRoom.windowDays)"
                + " windowFrom=\(CardSpendRoom.windowStart(now, back: 1).formatted(.iso8601))"
                + " priorFrom=\(CardSpendRoom.windowStart(now, back: 2).formatted(.iso8601))",
        ]
        // Every spend as data, newest first — the pairing of amount AND
        // currency is the tell, since either one missing silently removes the
        // row from the total while the row itself draws perfectly.
        for sight in sightings.sorted(by: { $0.at > $1.at }) {
            let window = sight.at >= CardSpendRoom.windowStart(now, back: 1) ? "window"
                : (sight.at >= CardSpendRoom.windowStart(now, back: 2) ? "prior" : "older")
            out.append("metamaskCardSpend| amount=\(sight.amount.map { String($0) } ?? "UNREADABLE")"
                       + " currency=\(sight.currency ?? "NONE")"
                       + " in=\(window)"
                       + " at=\(sight.at.formatted(.iso8601))")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no card account among the watched"
                       + " wallets, so nothing has ever settled)")
            return out
        }
        out.append("headline=\(CardSpendRoom.headline(room))")
        out.append("note=\(CardSpendRoom.note(room))")
        out.append("footnote=\(CardSpendRoom.footnote(room, now: now) ?? "none")")
        out.append("totals| currencies=\(room.currencies.count) windowSpends=\(room.spends)"
                   + " unpriced=\(room.unpriced) allTime=\(room.allTime)"
                   + " oldest=\(room.oldest?.formatted(.iso8601) ?? "none")"
                   + " knowsPrior=\(CardSpendRoom.knowsPriorWindow(oldest: room.oldest, now: now) ? "YES" : "no — no comparison will be claimed")")
        // The history strip. An EMPTY strip has three causes and only the last
        // is a bug: fewer than two months of history (the common case on this
        // seat, see the type note), a lead currency whose own months are thin
        // while another currency's are not, or a month key that failed to
        // resolve. The counts say which.
        out.append("metamaskCardHistory| months=\(room.months.count)"
                   + " hidden=\(room.monthsHidden)"
                   + " otherCurrency=\(room.monthsOtherCurrency)"
                   + " caption=\(CardSpendRoom.historyNote(room) ?? "none")")
        let peak = room.months.map(\.total).max() ?? 0
        for month in room.months {
            out.append("metamaskCardMonth| \(CardSpendRoom.monthLabel(month.start))"
                       + " (key=\(month.key))"
                       + " total=\(month.total) spends=\(month.spends)"
                       + " share=\(String(format: "%.2f", CardSpendRoom.monthShare(total: month.total, of: peak)))")
        }
        let top = room.lead?.spends ?? 0
        for currency in room.currencies.prefix(rowCap) {
            out.append("metamaskCardCurrency| \(currency.code)"
                       + " · \(CardSpendRoom.currencyLine(currency))"
                       + " · prior=\(currency.prior.map { String($0) } ?? "unknown")"
                       + " · delta=\(CardSpendRoom.deltaLabel(currency) ?? "none")"
                       + " · share=\(String(format: "%.2f", CardSpendRoom.share(spends: currency.spends, of: top)))")
        }
        return out
    }
}
