import Foundation

/// THE CIRCLE x402 ROOM'S HEAD (2026-08-06) — who is actually selling.
///
/// ## Why the room needs one at all
///
/// This room breaks the assumption every other feed shape rests on: **its rows
/// all share one timestamp.** Providers land on the walk that first sees them,
/// so a fresh connect stamps twenty-two rows `.now` and row order carries no
/// information whatsoever. Newest-first is the feed's whole ranking grammar and
/// here it ranks nothing.
///
/// So the ranking has to live somewhere, and this is it: Orthogonal sells 310
/// services and StablePhone sells 1, which is the single most useful fact about
/// this marketplace and is invisible in a list where they are adjacent rows of
/// equal weight.
///
/// ## Why it may draw numbers when rows may not
///
/// §223's ruling is that **a count is never a thing** — it governs what may LAND
/// as a row, and leaves exactly one honest home for a number: a state surface
/// that updates in place. `PostHogRoom` says this in its own header and this
/// card inherits it word for word. The treemap IS the tally, drawn. What it must
/// never grow is a "+3 services this week" line: that would be the count trying
/// to become news again, one surface over.
///
/// ## Three refusals
///
/// - **Area is service count and only service count.** Not price, not
///   recency, not lane breadth. `UnitTreemap` is rank-ordered rather than
///   area-proportional (its own §300 reasoning: true squarified cells arrive
///   as slivers too thin to label), so the cells say "bigger sells more" and
///   nothing finer.
/// - **The tail is folded and NAMED, never truncated.** A marketplace of 22
///   drawn as a top-5 with the rest silently gone is the §300 failure: a
///   dropped seller looks exactly like a marketplace that had five.
/// - **A zero-priced seller is never advertised "from $0.00".** The floor is
///   the cheapest NON-ZERO call across the whole marketplace and free
///   operations are said separately — `X402Ingest`'s quirk 4, one level up.
///
/// Foundation-only by design, so `scripts/x402-selftest.sh` compiles it WHOLE
/// and unmodified. Nothing here reads a `Thing`.
struct X402Room: Equatable {

    /// One tile: a seller, or the folded tail.
    struct Cell: Identifiable, Equatable {
        /// The seller's slug — or `tailID` for the fold, which names no seller
        /// and must therefore never be tappable.
        let id: String
        let label: String
        let services: Int
        let isTail: Bool

        static let tailID = "__tail__"
    }

    let cells: [Cell]
    /// Every seller the walk saw, drawn or folded.
    let sellers: Int
    /// The marketplace's own size — the walk's `total`, NOT the sum of the
    /// sellers' service counts, which disagree when the walk was truncated.
    let listings: Int
    let minPrice: Int?
    let maxPrice: Int?
    let hasFree: Bool

    /// Cells the map draws before folding. One below `UnitTreemap.maxCells` so
    /// the fold always has a tile of its own to sit in — spelled here rather
    /// than read from the view, because this file is Foundation-only and can't
    /// see it. The harness guards the two against drift.
    static let drawnCap = 5

    // MARK: - Composition

    /// The head, or nil when there is nothing to rank. Nil below two sellers on
    /// purpose: one tile is not a comparison, and a treemap of it is a square
    /// that says "all of it" — a drawing with no information in it.
    static func compose(sellers list: [X402State.Seller], listings: Int) -> X402Room? {
        let ranked = list.sorted {
            // Services descending, then name, so the order is total and a
            // redraw can never reshuffle equal sellers.
            ($0.services, $1.name) > ($1.services, $0.name)
        }
        guard ranked.count >= 2 else { return nil }

        var cells = ranked.prefix(drawnCap).map {
            Cell(id: $0.slug, label: $0.name, services: $0.services, isTail: false)
        }
        let folded = ranked.count - cells.count
        if folded > 0 {
            cells.append(Cell(id: Cell.tailID,
                              label: folded == 1
                                  ? String(localized: "1 more")
                                  : String(localized: "\(folded) more"),
                              services: ranked.dropFirst(drawnCap).reduce(0) { $0 + $1.services },
                              isTail: true))
        }

        // The floor and ceiling across the whole marketplace, zero excluded.
        let lows = ranked.compactMap(\.minPrice)
        let highs = ranked.compactMap(\.maxPrice)
        return X402Room(cells: cells,
                        sellers: ranked.count,
                        listings: max(listings, 0),
                        minPrice: lows.min(),
                        maxPrice: highs.max(),
                        hasFree: ranked.contains(where: \.hasFree))
    }

    // MARK: - Copy

    /// What the room leads with. The SELLER count, not the listing count: a
    /// company is the unit a person can act on, and "955 services" as a headline
    /// reads as a firehose rather than a directory you could shop.
    static func headline(_ room: X402Room) -> String {
        room.sellers == 1
            ? String(localized: "1 company is selling to agents")
            : String(localized: "\(room.sellers) companies are selling to agents")
    }

    /// The size and the price of entry, under the headline. Says nothing it
    /// doesn't know: no listings figure when the walk didn't report one, no
    /// price when nothing quoted a non-zero call.
    static func note(_ room: X402Room, money: (Int) -> String) -> String {
        var parts: [String] = []
        if room.listings > 0 {
            parts.append(room.listings == 1
                         ? String(localized: "1 service")
                         : String(localized: "\(room.listings) services"))
        }
        if let low = room.minPrice {
            // "From" the cheapest REAL call. A marketplace whose floor is a free
            // operation is not a free marketplace, and saying "from $0.00"
            // would be the §83 fake status in the one place money is the point.
            parts.append(room.hasFree
                         ? String(localized: "some free, then from \(money(low)) a call")
                         : String(localized: "from \(money(low)) a call"))
        } else if room.hasFree {
            parts.append(String(localized: "free"))
        }
        return parts.joined(separator: " · ")
    }

    /// The share a cell holds of everything DRAWN — the map's wash, 0…1. Over
    /// the drawn total rather than the marketplace's, so the biggest tile is
    /// always fully washed and the map reads at any scale.
    static func share(_ cell: Cell, in room: X402Room) -> Double {
        let top = room.cells.map(\.services).max() ?? 0
        guard top > 0 else { return 0 }
        return min(1, max(0, Double(cell.services) / Double(top)))
    }
}
