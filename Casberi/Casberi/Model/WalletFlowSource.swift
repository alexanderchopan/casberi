import Foundation
import SwiftData

/// Turns landed wallet things into `WalletFlow.Leg` values — the half of the
/// flow band that has to touch SwiftData, kept apart from the arithmetic so
/// `WalletFlow.swift` stays Foundation-only and harness-testable
/// (`scripts/wallet-viz-selftest.sh`).
///
/// This is also the ONLY place the band reads a `Thing`. Everything downstream
/// holds value types, which is what makes the card immune to the liveness
/// crash class (CLAUDE.md corollaries 1–5) rather than merely guarded against
/// it: there is no stored property left to read after a delete lands.
enum WalletFlowSource {

    /// When per-transfer prices started existing at all.
    ///
    /// `Thing.transferUSD` landed 2026-08-01 (prd §270). A transfer stored
    /// before that carries no price and CANNOT gain one: the read that would
    /// fill it dedupes on `sourceRef`, so an old row is only ever re-seen
    /// while it is still inside the wallet's re-read window, and after that
    /// it is permanently unpriceable.
    ///
    /// Deliberately the START of that day, UTC, not the commit's own
    /// timestamp: the boundary only has to be conservative in the direction of
    /// treating a genuinely-failed price as a failure, and midnight puts a few
    /// hours of real failures on the strict side of the line rather than
    /// excusing them.
    static let pricingEra = Date(timeIntervalSince1970: 1_785_542_400)

    /// Builds the band for a window, or nil when there's nothing to draw.
    ///
    /// `since` bounds the window (nil = everything the corpus holds, which is
    /// what the room's "watched" range means).
    static func band(from things: [Thing], since: Date?) -> WalletFlow.Band? {
        let split = partition(from: things, since: since)
        return WalletFlow.band(legs: split.legs, predating: split.predating)
    }

    /// The band, or the reason there is none — exactly one of the two is
    /// non-nil (prd §589). One walk of the room, so the slot can draw whichever
    /// it got without reading the corpus twice.
    static func verdict(from things: [Thing],
                        since: Date?) -> (band: WalletFlow.Band?, decline: WalletFlow.Decline?) {
        let split = partition(from: things, since: since)
        if let band = WalletFlow.band(legs: split.legs, predating: split.predating) {
            return (band, nil)
        }
        return (nil, WalletFlow.decline(legs: split.legs, predating: split.predating))
    }

    /// The window's legs, split from the ones that can never carry a price.
    ///
    /// The split is what makes `minPricedShare` mean "how well is pricing
    /// working" instead of "how old is this corpus" — see that constant for
    /// the bug this fixes. A leg is set aside ONLY when it is both unpriced
    /// and older than `pricingEra`: an old leg that DID get a price (the heal
    /// reached it while it was still being re-read) is a perfectly good leg,
    /// and a new leg with no price is a real failure that must still count.
    static func partition(from things: [Thing],
                          since: Date?) -> (legs: [WalletFlow.Leg], predating: Int) {
        var kept: [WalletFlow.Leg] = []
        var predating = 0
        for (leg, capturedAt) in datedLegs(from: things, since: since) {
            if leg.usd == nil, capturedAt < pricingEra {
                predating += 1
                continue
            }
            kept.append(leg)
        }
        return (kept, predating)
    }

    /// `-flowProbe <days|YES>` — one line per fact, never joined (the
    /// `-todayProbe` truncation lesson).
    ///
    /// Reports the DECLINE as loudly as the draw. A landed count alone can't
    /// separate "no money moved this window" from "every move reached us
    /// unpriced", and those are a quiet week and a broken price read
    /// respectively — the distinction this card lives or dies on.
    @MainActor
    static func probeLines(context: ModelContext, days: Int?) -> [String] {
        let since = days.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }
        let window = days.map { "\($0)d" } ?? "all"
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        let wallet = things.filter { $0.isLive && $0.source == "Wallet" && $0.kind == .transaction }
        let split = partition(from: things, since: since)
        let legs = split.legs
        var out = [
            "window=\(window) walletThings=\(wallet.count) legs=\(legs.count) "
                + "priced=\(legs.filter { $0.usd != nil }.count) "
                // Reported separately from `priced` on purpose: these two
                // numbers moving together vs apart is what tells you whether
                // a blank card is a broken price read or just an old corpus.
                + "predatingPriceData=\(split.predating)",
        ]
        guard let band = WalletFlow.band(legs: legs, predating: split.predating) else {
            // Each decline names itself, so a blank card is diagnosable from
            // the log alone — off the SAME ladder the slot draws (prd §589),
            // so the log can never explain a blank the screen described
            // differently.
            switch WalletFlow.decline(legs: legs, predating: split.predating) {
            case .noLegs(let predating):
                out.append("DECLINED: no directional transfers in the window "
                            + "(swaps and self-moves carry no direction, and spam is excluded)"
                            + (predating > 0
                                ? " — \(predating) were set aside as older than price data"
                                : ""))
            case .nothingPriced(let total):
                out.append("DECLINED: nothing in the window could be priced (\(total) moves)")
            case .belowFloor(let priced, let total):
                // Legs older than price data are already out of this ratio, so
                // unlike before it really does mean "the price read is
                // failing" rather than "this corpus has history".
                out.append(String(format:
                    "DECLINED: only %d of %d PRICEABLE moves are priced (%.0f%%, floor %.0f%%) — "
                        + "these could have been priced and weren't, so suspect the read",
                    priced, total,
                    Double(priced) / Double(total) * 100,
                    WalletFlow.minPricedShare * 100))
            case .oneLane:
                out.append("DECLINED: fewer than two lanes survived")
            case nil:
                out.append("DECLINED: band and decline disagree — a ladder bug")
            }
            return out
        }
        out.append(String(format: "in=$%.2f out=$%.2f net=$%.2f scale=$%.2f unpriced=%d",
                          band.inUSD, band.outUSD, band.netUSD, band.scaleUSD,
                          band.unpricedCount))
        for lane in band.inLanes {
            out.append(String(format: "in  | %@ $%.2f × %d%@",
                              lane.name, lane.usd, lane.count, lane.isOther ? " (folded)" : ""))
        }
        for lane in band.outLanes {
            out.append(String(format: "out | %@ $%.2f × %d%@",
                              lane.name, lane.usd, lane.count, lane.isOther ? " (folded)" : ""))
        }
        return out
    }

    /// The legs a window contributes. Reads every stored property behind a
    /// liveness check, at the boundary, once.
    static func legs(from things: [Thing], since: Date?) -> [WalletFlow.Leg] {
        datedLegs(from: things, since: since).map(\.leg)
    }

    /// Each leg with the date it landed — the same walk, keeping the one fact
    /// `WalletFlow.Leg` deliberately doesn't carry (it is a value type about
    /// money, not a row) but the pricing-era split needs.
    private static func datedLegs(from things: [Thing],
                                  since: Date?) -> [(leg: WalletFlow.Leg, capturedAt: Date)] {
        var out: [(leg: WalletFlow.Leg, capturedAt: Date)] = []
        for thing in things where thing.isLive {
            guard thing.source == "Wallet", thing.kind == .transaction else { continue }
            if let since, thing.capturedAt < since { continue }
            // Spam never becomes a lane. An address-poisoning dust transfer is
            // designed to put a lookalike counterparty in front of you, and a
            // band that drew one would be handing the attacker the label they
            // paid for — the same reason `WalletWarnings` files these under
            // "just so you know" instead of the feed proper.
            if thing.isFlagged { continue }
            // A direction is what makes a leg a FLOW. Swaps and moves between
            // two of your own watched wallets carry none by construction (two
            // legs, no single side), and neither crosses the wallet's edge —
            // so they're absent rather than capped, and the band's unpriced
            // note doesn't claim them.
            guard let direction = thing.transferDirection else { continue }
            let received: Bool
            switch direction {
            case "received": received = true
            case "sent": received = false
            default: continue
            }

            let address = thing.counterpartyAddress
            // A NAME or nothing (user ruling, 2026-08-11: "on the sankey we
            // don't need to show the addresses"). This used to fall back to
            // `WalletStore.shortAddress`, which put `0x1a2b…9f0c` on the
            // ribbon — a string that identifies nobody, costs the widest label
            // in the band, and reads as data we failed to resolve rather than
            // as a fact worth drawing.
            //
            // Empty, NOT "Unknown": several unnamed counterparties are several
            // distinct lanes (see `key` below), and stamping the same word on
            // each would read as one venue drawn several times. The band
            // renders an unnamed lane by its VALUE alone, which is the part we
            // actually know. Grouping is untouched — `key` still keys on the
            // address, so two strangers never merge.
            let name = thing.transferCounterparty ?? ""
            // Named counterparties group by NAME so one venue behind several
            // router addresses reads as one lane; nameless ones group by
            // address so two unrelated strangers never merge into a single
            // "Unknown" ribbon that means nothing.
            let key = thing.transferCounterparty?.lowercased()
                ?? address
                ?? "unknown:\(thing.id.uuidString)"
            out.append((WalletFlow.Leg(received: received, name: name,
                                       key: key, usd: thing.transferUSD),
                        thing.capturedAt))
        }
        return out
    }
}
