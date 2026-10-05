import Foundation

/// **SUBSCRIPTIONS BY CATEGORY (the Wallet's Subscriptions tile, prd §1112).**
/// What the tile's map and its picks are made of: every subscription with a
/// monthly cost, in dollars, summed under the catalogue category of the app
/// it bills for (`BillersSource.category(ofMerchant:)`, handed in as
/// `category` so this file stays Foundation-only).
///
/// - **The catalogue's fallback is "Other" here, never "Wallet".** Addresses
///   files an unknown biller under Wallet because a biller is money; on a map
///   of where the money GOES, a Wallet tile would say the money goes to money.
///   The fallback becomes `otherKey`, and that is the same key the treemap's
///   own fold tile wears (`HoldingsTreemapLayout.otherID`, which
///   `subscription-categories-selftest.sh` holds equal), so the unknown
///   merchants and the folded tail are ONE tile.
/// - **Only what has a monthly cost counts (prd §83).** A bill with no known
///   cadence, or a price in a currency with no rate, stays in the list and
///   stays out of the total and the map, as `Subscriptions.total` rules.
/// - **A one-tile map says nothing**, so the map draws from `minTiles` up;
///   the total stands without it.
enum SubscriptionCategories {

    /// The one "Other" tile: the catalogue's fallback and the layout's fold.
    static let otherKey = "@other"

    /// A map of fewer tiles than this draws nothing.
    static let minTiles = 2

    struct Slice: Equatable {
        /// The category's name, or `otherKey`.
        let key: String
        /// What it costs a month, in dollars.
        let monthly: Double
        /// How many counted subscriptions it holds.
        let count: Int
        /// Its share of the counted total.
        let share: Double
    }

    struct Reading: Equatable {
        /// Most a month first; a tie by key, so the order never wobbles.
        let slices: [Slice]
        let monthly: Double
        let counted: Int

        static let empty = Reading(slices: [], monthly: 0, counted: 0)
    }

    /// An item's place on the map: its category, `otherKey` for the fallback.
    static func key(of item: Subscriptions.Item, category: (String) -> String, fallback: String) -> String {
        let c = category(item.name)
        return c == fallback ? otherKey : c
    }

    /// Items → the categories their monthly dollars land in.
    static func read(_ items: [Subscriptions.Item], usd: (Double, String) -> Double?,
                     category: (String) -> String, fallback: String) -> Reading {
        read(measured: items.compactMap { item -> (key: String, measure: Double)? in
            guard let monthly = item.monthly, let dollars = usd(monthly, item.currency) else { return nil }
            return (key: key(of: item, category: category, fallback: fallback), measure: dollars)
        })
    }

    /// Any measure a month, already keyed, → the map's reading. The Wallet
    /// measures dollars; Day measures mails (prd §1117), and both maps are
    /// this one sum, so a slice means the same thing in either room.
    static func read(measured: [(key: String, measure: Double)]) -> Reading {
        var sums: [String: (monthly: Double, count: Int)] = [:]
        var total = 0.0, counted = 0
        for (k, measure) in measured {
            sums[k, default: (0, 0)].monthly += measure
            sums[k, default: (0, 0)].count += 1
            total += measure
            counted += 1
        }
        let slices = sums
            .filter { $0.value.monthly > 0 }
            .map { Slice(key: $0.key, monthly: $0.value.monthly, count: $0.value.count,
                         share: total > 0 ? $0.value.monthly / total : 0) }
            .sorted { $0.monthly != $1.monthly ? $0.monthly > $1.monthly : $0.key < $1.key }
        return Reading(slices: slices, monthly: total, counted: counted)
    }

    /// Whether a map of these drawn tiles says anything.
    static func drawsMap(tiles: Int) -> Bool { tiles >= minTiles }

    /// The categories a drawn tile stands for: its own; for Other, the
    /// fallback AND every category the layout folded into it, because those
    /// draw no tile of their own.
    static func members(of tile: String, drawn: [String], slices: [Slice]) -> Set<String> {
        guard tile == otherKey else { return [tile] }
        let shown = Set(drawn)
        return Set(slices.map(\.key).filter { $0 == otherKey || !shown.contains($0) })
    }

    /// What a pressed tile reads: its members' monthly sum and count.
    static func picked(_ tile: String, drawn: [String], reading: Reading) -> (monthly: Double, counted: Int) {
        let keys = members(of: tile, drawn: drawn, slices: reading.slices)
        let mine = reading.slices.filter { keys.contains($0.key) }
        return (mine.reduce(0) { $0 + $1.monthly }, mine.reduce(0) { $0 + $1.count })
    }

    /// The rows a pressed tile leaves: every item in its members, a monthly
    /// cost or not, in the order given. No tile, every item.
    static func items(_ items: [Subscriptions.Item], in tile: String?, drawn: [String], slices: [Slice],
                      category: (String) -> String, fallback: String) -> [Subscriptions.Item] {
        guard let tile else { return items }
        let keys = members(of: tile, drawn: drawn, slices: slices)
        return items.filter { keys.contains(key(of: $0, category: category, fallback: fallback)) }
    }

    /// What a pick is keyed on: the set of subscriptions it was made over, so
    /// a different set (a refresh, another account) clears it.
    static func signature(_ items: [Subscriptions.Item]) -> String {
        items.map(\.id).sorted().joined(separator: "|")
    }
}
