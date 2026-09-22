import Foundation
import SwiftData

/// The ether.fi Cash room head's reading half (2026-09-21, prd §868) — landed
/// rows turned into the card's own value, with every judgement left to
/// `CardSpendRoom`.
///
/// The THIRD seat on the shared head (prd §858), and the last onchain card this
/// app reads. Gnosis Pay and MetaMask Card have led with what the card cost
/// since §349 and §858; this room led with its newest row, which for a spending
/// card is the §247 gap at its widest — a list of purchases is a statement, and
/// nobody opens a statement to read it line by line. Nothing about the head
/// needed changing to take this seat: `EtherFiCash` already stamps
/// `priceValue`/`priceCurrency` on every spend, in USD, which is the whole
/// membership test.
///
/// **This room is SHARED, and its siblings' are not — that is the only thing
/// here that is genuinely new.** `EtherFiCash.source` is one seat covering two
/// products ("ether.fi — Your staked ETH, and the card"), so the same room also
/// holds `EtherFiUnstake`'s withdrawal-queue rows and this seat's own
/// credit-line risk crossings. Both are `.link` rows carrying no price, so the
/// source filter its two siblings use would hand the head a stack of
/// non-purchases: counted in `allTime`, counted by the footnote as "spends with
/// no readable amount". The rule for which rows are spends lives in
/// `CardSpendSeat`, read by all three sources and by the door under the card,
/// so the head and the door can never disagree about what a spend is.
///
/// **The comparison will usually be refused here, and that is correct.**
/// `EtherFiCash.backfillBlocks` is ~6 days of OP blocks, deliberately — a card
/// is used often enough that a long first backfill would bury the feed on the
/// day someone starts watching. So a fresh connection cannot know a prior
/// 30-day window at all, and `CardSpendRoom.knowsPriorWindow` says so in words
/// rather than estimating it. Nothing here may work around that.
enum EtherFiCashRoomSource {

    /// The seat's own source name, taken from the bridge rather than spelled
    /// again — see `PeerBridge.sourceName`.
    static let source = EtherFiCash.source

    /// Forwards to the shared cap, like its two siblings. ether.fi Cash settles
    /// in USD and only USD (`totalUsdAmt` rides the `Spend` event in fixed
    /// 6-decimal dollars), so this room draws one currency row and the cap is
    /// never reached — it is taken from the shared constant anyway, because a
    /// seat holding its own number is how two rooms on one head start drawing a
    /// different count of rows for a reason nobody chose.
    static let rowCap = CardSpendRoom.rowCap

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> CardSpendRoom? {
        // Live at the BOUNDARY, before any stored property is read
        // (corollary 4) — and `CardSpendSeat.isSpend` reads two of them.
        let rows = things.live.filter { CardSpendSeat.isSpend($0, seat: source) }
        guard !rows.isEmpty else { return nil }
        let room = CardSpendRoom.compose(spends: rows.map(sighting), now: now)
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to what the head reads. The ONLY place a `Thing`
    /// is touched.
    ///
    /// `priceValue`/`priceCurrency` are read as DATA — never `transferAmount`,
    /// which is the formatted display string ("$4.20") and would have to be
    /// parsed back apart, and never the title, which is prose and says on
    /// CREDIT or not.
    @MainActor
    private static func sighting(_ thing: Thing) -> CardSpendRoom.Sighting {
        CardSpendRoom.Sighting(amount: thing.priceValue,
                               currency: thing.priceCurrency,
                               at: thing.capturedAt)
    }

    /// The probe's lines — driven by `-etherfiCashRoomProbe`, calling the REAL
    /// `compose`. `now` is taken so a run can be composed against a fixed clock
    /// and the window boundaries checked.
    ///
    /// It exists because a thin or empty head has SIX causes that render as one
    /// silence, and only the last two are bugs:
    ///
    ///   1. no wallet is watched, or none of them is a Cash safe — most wallets
    ///      hold no ether.fi Cash account, and what you watch is the SAFE
    ///      rather than your EOA (`EtherFiCash`'s own measured header), so this
    ///      is both the common case and the easiest one to arrive at by
    ///      pointing the app at the wrong address;
    ///   2. the card exists and was not used in the last 30 days — a real
    ///      answer the card states out loud;
    ///   3. the room is younger than 60 days, so no comparison is possible and
    ///      `prior` is nil throughout — correct, and easily read as a missing
    ///      feature. It is the COMMON case here, because the backfill is about
    ///      six days;
    ///   4. the room holds plenty of ether.fi rows and none of them is a SPEND
    ///      — this seat's own cause, and the one that reads least like an
    ///      empty room: unstake-queue rows and risk crossings share this room
    ///      and are correctly declined, so a busy feed can sit under a head
    ///      that composed nothing. `spendRows` against `handed` says so;
    ///   5. `priceValue` missing. This should be UNREACHABLE — `totalUsdAmt`
    ///      rides the `Spend` event in fixed 6-decimal USD, the exact inverse
    ///      of Gnosis Pay's per-token decimals trap — so a row printing
    ///      UNREADABLE here means the event's word layout moved, not that a
    ///      decimals call failed;
    ///   6. `priceCurrency` missing while the amount is there, which drops the
    ///      spend from every total with nothing on screen to say so.
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let live = things.live
        let rows = live.filter { CardSpendSeat.isSpend($0, seat: source) }
        let sightings = rows.map(sighting)
        // `roomRows` and `spendRows` are printed apart on purpose — their gap
        // is cause 4, and a single count could not show it.
        let roomRows = live.filter { $0.source == source }.count
        var out: [String] = [
            "etherfiCashRoom| source=\(source) handed=\(things.count)"
                + " roomRows=\(roomRows) spendRows=\(rows.count)"
                + " notSpends=\(roomRows - rows.count)"
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
            out.append("etherfiCashSpend| amount=\(sight.amount.map { String($0) } ?? "UNREADABLE")"
                       + " currency=\(sight.currency ?? "NONE")"
                       + " in=\(window)"
                       + " at=\(sight.at.formatted(.iso8601))")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no Cash safe among the watched"
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
        // is a bug: fewer than two months of history (the common case here, see
        // the type note), a lead currency whose own months are thin while
        // another currency's are not — which cannot happen on this seat, since
        // it settles in USD alone — or a month key that failed to resolve.
        out.append("etherfiCashHistory| months=\(room.months.count)"
                   + " hidden=\(room.monthsHidden)"
                   + " otherCurrency=\(room.monthsOtherCurrency)"
                   + " caption=\(CardSpendRoom.historyNote(room) ?? "none")")
        let peak = room.months.map(\.total).max() ?? 0
        for month in room.months {
            out.append("etherfiCashMonth| \(CardSpendRoom.monthLabel(month.start))"
                       + " (key=\(month.key))"
                       + " total=\(month.total) spends=\(month.spends)"
                       + " share=\(String(format: "%.2f", CardSpendRoom.monthShare(total: month.total, of: peak)))")
        }
        let top = room.lead?.spends ?? 0
        for currency in room.currencies.prefix(rowCap) {
            out.append("etherfiCashCurrency| \(currency.code)"
                       + " · \(CardSpendRoom.currencyLine(currency))"
                       + " · prior=\(currency.prior.map { String($0) } ?? "unknown")"
                       + " · delta=\(CardSpendRoom.deltaLabel(currency) ?? "none")"
                       + " · share=\(String(format: "%.2f", CardSpendRoom.share(spends: currency.spends, of: top)))")
        }
        return out
    }
}
