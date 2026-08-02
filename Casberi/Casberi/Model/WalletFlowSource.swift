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

    /// Builds the band for a window, or nil when there's nothing to draw.
    ///
    /// `since` bounds the window (nil = everything the corpus holds, which is
    /// what the room's "watched" range means).
    static func band(from things: [Thing], since: Date?) -> WalletFlow.Band? {
        WalletFlow.band(legs: legs(from: things, since: since))
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
        let legs = legs(from: things, since: since)
        var out = [
            "window=\(window) walletThings=\(wallet.count) legs=\(legs.count) "
                + "priced=\(legs.filter { $0.usd != nil }.count)",
        ]
        guard let band = band(from: things, since: since) else {
            // Each decline names itself, so a blank card is diagnosable from
            // the log alone.
            let pricedCount = legs.filter { $0.usd != nil }.count
            if legs.isEmpty {
                out.append("DECLINED: no directional transfers in the window "
                            + "(swaps and self-moves carry no direction, and spam is excluded)")
            } else if pricedCount == 0 {
                out.append("DECLINED: nothing in the window could be priced")
            } else if Double(pricedCount) / Double(legs.count) < WalletFlow.minPricedShare {
                out.append(String(format:
                    "DECLINED: only %d of %d moves are priced (%.0f%%, floor %.0f%%) — "
                        + "transfers landed before Thing.transferUSD existed never gain a price, "
                        + "so this clears as they age out of the window",
                    pricedCount, legs.count,
                    Double(pricedCount) / Double(legs.count) * 100,
                    WalletFlow.minPricedShare * 100))
            } else {
                out.append("DECLINED: fewer than two lanes survived")
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
        var out: [WalletFlow.Leg] = []
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
            let name = thing.transferCounterparty
                ?? address.map(WalletStore.shortAddress)
                ?? String(localized: "Unknown")
            // Named counterparties group by NAME so one venue behind several
            // router addresses reads as one lane; nameless ones group by
            // address so two unrelated strangers never merge into a single
            // "Unknown" ribbon that means nothing.
            let key = thing.transferCounterparty?.lowercased()
                ?? address
                ?? "unknown:\(thing.id.uuidString)"
            out.append(WalletFlow.Leg(received: received, name: name,
                                      key: key, usd: thing.transferUSD))
        }
        return out
    }
}
