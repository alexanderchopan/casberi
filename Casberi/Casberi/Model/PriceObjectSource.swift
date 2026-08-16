import Foundation

/// The price object's reading half (prd §369 amendment, 2026-08-16) — a landed
/// `Thing` plus the curve that was just fetched, turned into a `PriceObject`.
///
/// The split is `MoneyReceiptSource`'s and it earns itself the same way:
/// everything that could be wrong while still rendering perfectly — a sentence
/// claiming an extreme that isn't one, a percentage against the wrong anchor —
/// lives in `PriceObject`/`PriceCommentary`, which the harness compiles whole.
///
/// ## The one uncomfortable bit, stated plainly
///
/// `MoneyReceiptSource` is forbidden to parse a title, and its harness greps
/// for exactly that. This file does something that LOOKS like it and is not the
/// same thing, so the difference is worth writing down rather than leaving for
/// somebody to discover and "fix".
///
/// A money row's title is a LOCALIZED SENTENCE — "Sent 0.5 ETH to maria.eth" —
/// whose shape changes per language, so recovering facts from it is guesswork
/// dressed as parsing. A token row's title is a MACHINE-BUILT JOIN this app
/// wrote itself, `"\(name) · $\(symbol)"`, with a fixed separator and no
/// translation anywhere near it (`TokenWatch.swift`). Splitting that back is
/// recovering our own join, not reading prose.
///
/// It is still the weaker source, so it is the FALLBACK: `authorHandle` now
/// carries the symbol for anything watched from 2026-08-16 on, and the split
/// only serves rows that predate the stamp. If the separator isn't there, the
/// whole title becomes the symbol and no name is claimed — the honest failure,
/// rather than half a title in the wrong slot.
enum PriceObjectSource {

    /// The separator `TokenWatch` joins with. One constant so the writer and
    /// the reader cannot drift.
    static let titleJoin = " · "

    /// The object for a charted row, or nil when this isn't one.
    ///
    /// `chart` is threaded in rather than fetched: `TokenChartView` has just
    /// done that work, and a second read for the same answer would be a
    /// request bought twice — plus the two could disagree, which is the one
    /// thing an object and its own evidence must never do.
    @MainActor
    static func object(name: String?, symbol: String,
                       closes: [Double], price: Double, change: Double,
                       window: String, fetchedAt: Date,
                       watched: (price: Double, date: Date)?,
                       coarse: Bool) -> PriceObject {
        PriceObject(
            subject: symbol.isEmpty ? .none : .asset(symbol),
            name: name,
            symbol: symbol.isEmpty ? String(localized: "Price") : symbol,
            price: PriceCommentary.money(price),
            move: PriceObject.Move(change: change, window: window),
            freshness: TokenChartStyle.isFresh(fetchedAt)
                ? .live : .aged(fetchedAt),
            // A coarse curve is five points back-solved from change buckets —
            // real enough to draw, nowhere near enough to make a claim about
            // shape. `PriceCommentary.minimumCloses` would refuse it anyway;
            // this says so at the boundary rather than relying on that.
            sentence: coarse ? nil
                : PriceCommentary.sentence(closes: closes, window: window,
                                           watched: watched))
    }

    /// The asset's name and symbol, from the strongest source available.
    ///
    /// Returns `(name, symbol)`. See the type's doc for why the title split is
    /// legitimate here and is still only the fallback.
    static func identity(title: String, authorHandle: String?) -> (name: String?, symbol: String) {
        if let handle = authorHandle?.trimmingCharacters(in: .whitespaces),
           !handle.isEmpty {
            // The stamp carries the symbol; the title's leading half is the
            // name when it has one.
            let name = title.components(separatedBy: titleJoin).first
            return (name == title ? nil : name, handle)
        }
        let parts = title.components(separatedBy: titleJoin)
        guard parts.count >= 2, let last = parts.last, !last.isEmpty else {
            // No separator: claim nothing. The whole title becomes the symbol,
            // which reads exactly as it does today.
            return (nil, title)
        }
        return (parts.dropLast().joined(separator: titleJoin), last)
    }
}
