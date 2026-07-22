import Foundation

/// The combined portfolio read (2026-07-21) — what every watched wallet holds,
/// merged into one answer: the total, the composition, and WHICH wallet holds
/// each position.
///
/// Derived, never fetched. `WalletIngest.topHoldingsByWallet()` already reads
/// each wallet's holdings (and is already called on every foreground pass);
/// this merges those groups in memory, so the combined view costs nothing on
/// the wire and can never disagree with the per-wallet views it's built from.
///
/// The honesty floor is the same one the value line keeps: a wallet that
/// didn't price this pass simply isn't in `groups`, so it contributes nothing
/// rather than a zero — and `walletCount` reports how many actually answered,
/// so a caller can tell "everything, together" from "what we could reach".
struct WalletPortfolio: Equatable {

    /// One wallet's stake in a single symbol — the "held in" read.
    struct Holder: Equatable, Identifiable {
        let address: String
        let label: String
        let usd: Double
        var id: String { address }
    }

    /// One symbol across every wallet, biggest first.
    struct Position: Equatable, Identifiable {
        let symbol: String
        let usd: Double
        /// "chain:address" — the route a treemap cell's tap opens, nil for a
        /// symbol whose biggest position had no routable contract.
        let route: String?
        /// Which wallets hold it, biggest stake first. One entry with a single
        /// wallet watched — the caller decides whether that's worth saying.
        let holders: [Holder]
        var id: String { symbol }
    }

    var totalUSD: Double = 0
    var positions: [Position] = []
    /// How many watched wallets actually contributed a priced read.
    var walletCount: Int = 0

    var isEmpty: Bool { positions.isEmpty }
    var tokenCount: Int { positions.count }
    var top: Position? { positions.first }

    /// The biggest position's share of everything, 0…1 — the concentration
    /// read. nil when there's nothing to be concentrated in (one position IS
    /// the whole portfolio, which says nothing worth a line).
    var topShare: Double? {
        guard positions.count >= 2, totalUSD > 0, let top else { return nil }
        return top.usd / totalUSD
    }

    /// The wallets holding a symbol, biggest stake first — empty for a symbol
    /// this portfolio doesn't hold.
    func holders(forSymbol symbol: String) -> [Holder] {
        positions.first { $0.symbol == symbol }?.holders ?? []
    }

    /// Merges the per-wallet holdings groups into one portfolio. Amounts come
    /// from `bySymbolAll` (every counted position, not the sampled top-8 clip),
    /// so the token count and every share are the real ones.
    ///
    /// A symbol's route is taken from the wallet holding the MOST of it: the
    /// same "biggest position wins" rule `WalletIngest.holdings` already uses
    /// within a single wallet, applied one level up. Routes can differ per
    /// wallet (the same symbol held on two chains) and the biggest stake is
    /// the one a tap should open.
    static func from(groups: [WalletIngest.HoldingsGroup]) -> WalletPortfolio {
        var usdBySymbol: [String: Double] = [:]
        var holdersBySymbol: [String: [Holder]] = [:]
        var routeBySymbol: [String: (usd: Double, route: String)] = [:]

        for group in groups {
            let label = group.label
            let address = group.address ?? label
            for (symbol, usd) in group.bySymbolAll {
                usdBySymbol[symbol, default: 0] += usd
                holdersBySymbol[symbol, default: []]
                    .append(Holder(address: address, label: label, usd: usd))
                guard usd > (routeBySymbol[symbol]?.usd ?? 0),
                      let route = group.routeBySymbol[symbol] else { continue }
                routeBySymbol[symbol] = (usd, route)
            }
        }

        let positions = usdBySymbol
            .sorted { $0.value > $1.value }
            .map { symbol, usd in
                Position(symbol: symbol, usd: usd,
                         route: routeBySymbol[symbol]?.route,
                         holders: (holdersBySymbol[symbol] ?? []).sorted { $0.usd > $1.usd })
            }
        return WalletPortfolio(totalUSD: usdBySymbol.values.reduce(0, +),
                               positions: positions,
                               walletCount: groups.count)
    }

    /// The combined treemap's cells — the merged amounts run through the same
    /// builder a single wallet's cells use, so the two maps can't drift on
    /// weighting, value markers, or route markers.
    var treemapCells: [String] {
        WalletIngest.treemapCells(
            bySymbol: Dictionary(uniqueKeysWithValues: positions.map { ($0.symbol, $0.usd) }),
            routes: Dictionary(uniqueKeysWithValues:
                positions.compactMap { p in p.route.map { (p.symbol, $0) } }))
    }

    /// "$19.9K across 13 tokens in 3 wallets" — the combined map's subline.
    /// Names the wallet count because that IS what makes this map different
    /// from the per-wallet ones it replaced.
    var subline: String {
        let amount = TokenStats.compact(totalUSD)
        let tokens = "\(tokenCount) token\(tokenCount == 1 ? "" : "s")"
        guard walletCount > 1 else { return "\(amount) across \(tokens)" }
        return String(localized: "\(amount) across \(tokens) in \(walletCount) wallets")
    }

    /// "ETH is 62% of everything" — the concentration whisper (2026-07-21).
    /// A portfolio-level read by nature: it means nothing about one holding
    /// and everything about the shape of the whole. nil when there's no shape
    /// to report (a single position, or no value at all).
    var concentrationLine: String? {
        guard let top, let share = topShare else { return nil }
        let pct = Int((share * 100).rounded())
        // A share that rounds to 0% or 100% would claim a precision the
        // rounding just destroyed — the two ends stay quiet.
        guard pct > 0, pct < 100 else { return nil }
        return String(localized: "\(top.symbol) is \(pct)% of everything")
    }
}

/// The balance line's window (2026-07-21). "Watched" — the whole record — is
/// the base and the only one that always exists; the calendar windows are
/// OFFERED ONLY WHEN THE SAMPLES REACH BACK THAT FAR, so a chip can never
/// name a period the history doesn't cover (the same rule the delta pill's
/// "watched" label was invented to keep: never claim a range you don't have).
enum WalletRange: String, CaseIterable {
    case week = "7d"
    case month = "30d"
    case watched = "watched"

    private static let memoryKey = "wallet.balance.range"

    var span: TimeInterval? {
        switch self {
        case .week:    return 7 * 86_400
        case .month:   return 30 * 86_400
        case .watched: return nil
        }
    }

    /// What the delta pill says its number is measured over.
    var deltaLabel: String { rawValue }

    /// The samples inside this window — everything, for `.watched`.
    func clip(_ samples: [WalletStore.ValueSample]) -> [WalletStore.ValueSample] {
        guard let span else { return samples }
        let cutoff = Date.now.addingTimeInterval(-span)
        return samples.filter { $0.at >= cutoff }
    }

    /// The windows this history can honestly answer: `.watched` whenever two
    /// samples exist, plus each calendar window whose span the record actually
    /// covers (the first sample predates it) AND which holds two points of its
    /// own. Returns a single entry when there's nothing to choose between —
    /// callers draw no chips for that, since a lone chip is a dead control.
    static func offered(for samples: [WalletStore.ValueSample]) -> [WalletRange] {
        guard samples.count >= 2, let first = samples.first else { return [] }
        return allCases.filter { range in
            guard let span = range.span else { return true }
            return first.at <= Date.now.addingTimeInterval(-span)
                && range.clip(samples).count >= 2
        }
    }

    /// The remembered window, narrowed to what the record can currently answer
    /// — a 30d watcher whose history was wiped falls back rather than showing
    /// an empty line.
    static func remembered(offered: [WalletRange]) -> WalletRange {
        let saved = UserDefaults.standard.string(forKey: memoryKey)
            .flatMap(WalletRange.init(rawValue:))
        if let saved, offered.contains(saved) { return saved }
        return offered.last ?? .watched
    }

    func remember() { UserDefaults.standard.set(rawValue, forKey: Self.memoryKey) }
}
