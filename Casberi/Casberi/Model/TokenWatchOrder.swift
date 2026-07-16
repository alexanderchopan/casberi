import Foundation
import Observation

/// How the watchlist orders itself — one shared choice the settings screen,
/// the Home tile, and the Feed's tokens shape all read, so a watchlist can
/// never disagree with itself across surfaces (the same rule the lede's
/// shared-pulse-source honesty already keeps). Movers first is the default:
/// past a couple of watched tokens, "what moved" beats "what I watched last."
enum TokenWatchSortMode: String, CaseIterable {
    case movers, manual, recent

    var label: String {
        switch self {
        case .movers: String(localized: "Movers first")
        case .manual: String(localized: "My order")
        case .recent: String(localized: "Recently watched")
        }
    }
}

@Observable
final class TokenWatchOrder {
    static let shared = TokenWatchOrder()
    private static let modeKey = "tokens.watch.sortMode"
    private static let orderKey = "tokens.watch.manualOrder"

    private(set) var mode: TokenWatchSortMode
    /// Watched things' sourceRefs, in the order the person dragged them —
    /// populated only once "My order" is chosen (empty otherwise).
    private(set) var manual: [String]

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.modeKey)
            .flatMap(TokenWatchSortMode.init(rawValue:)) ?? .movers
        manual = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
    }

    func setMode(_ new: TokenWatchSortMode) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.modeKey)
    }

    func saveManual(_ order: [String]) {
        manual = order
        UserDefaults.standard.set(order, forKey: Self.orderKey)
    }

    /// Drops an unwatched token's ref from the saved arrangement — otherwise
    /// re-watching the same token later would silently reclaim its old spot.
    func remove(_ ref: String) {
        guard manual.contains(ref) else { return }
        manual.removeAll { $0 == ref }
        UserDefaults.standard.set(manual, forKey: Self.orderKey)
    }

    /// Orders a watchlist by the current mode. `things` arrives newest-watched
    /// first (the fetch's own order), which IS "recent" — movers reorders by
    /// the magnitude of the 24h move (a pulse not yet fetched sorts after
    /// every real mover, never ahead of one); manual reorders by the saved
    /// drag order, appending anything new (or not yet dragged) after the
    /// known ones so a fresh watch never gets lost off the bottom silently —
    /// it lands right where recency would have put it.
    func apply<T>(_ things: [T], sourceRef: (T) -> String?, change24h: (T) -> Double?) -> [T] {
        switch mode {
        case .recent:
            return things
        case .movers:
            let withIndex = things.enumerated().map { ($0.offset, $0.element) }
            return withIndex.sorted { a, b in
                let ca = change24h(a.1), cb = change24h(b.1)
                switch (ca, cb) {
                case let (ca?, cb?) where abs(ca) != abs(cb): return abs(ca) > abs(cb)
                default: return a.0 < b.0   // stable: ties (incl. no pulse yet) keep recency order
                }
            }.map(\.1)
        case .manual:
            guard !manual.isEmpty else { return things }
            let refIndex = Dictionary(uniqueKeysWithValues: manual.enumerated().map { ($1, $0) })
            let withIndex = things.enumerated().map { ($0.offset, $0.element) }
            return withIndex.sorted { a, b in
                let ia = sourceRef(a.1).flatMap { refIndex[$0] }
                let ib = sourceRef(b.1).flatMap { refIndex[$0] }
                switch (ia, ib) {
                case let (ia?, ib?): return ia < ib
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.0 < b.0   // both new since the last drag: keep recency order
                }
            }.map(\.1)
        }
    }
}
