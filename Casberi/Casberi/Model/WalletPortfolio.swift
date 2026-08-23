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

    /// The `Holder.address` a validator balance is filed under. There is no
    /// real address for staked ETH, and inventing one would put a "name this
    /// address" verb on something that isn't one (see `from`).
    static let validatorHolderID = "ethvalidators"

    /// Whether a holder is a PLACE rather than a watched wallet — a connected
    /// exchange venue or the validator pool.
    ///
    /// Matched against the known sentinels rather than by asking whether the
    /// id parses as an address: a misclassified wallet would be stated twice
    /// on screen (once as a face chip, once as a venue), and the set of things
    /// that aren't wallets is small, closed and known right here.
    static func isVenue(_ holderID: String) -> Bool {
        holderID == validatorHolderID || ExchangeBridge.Venue(rawValue: holderID) != nil
    }

    /// Every non-wallet place holding money, biggest first, totalled across
    /// symbols (2026-07-31).
    ///
    /// The balance card's face chips decompose the crown number by wallet, but
    /// the crown number has merged exchange and validator balances since
    /// §163 — so on a setup where the main holding sits on Coinbase, the chips
    /// silently accounted for a fraction of the number they sit beneath and
    /// the caption above still said "wallets". This is the missing half.
    var venueTotals: [Holder] {
        var byID: [String: (label: String, usd: Double)] = [:]
        for position in positions {
            for holder in position.holders where Self.isVenue(holder.address) {
                byID[holder.address, default: (holder.label, 0)].usd += holder.usd
            }
        }
        return byID
            .map { Holder(address: $0.key, label: $0.value.label, usd: $0.value.usd) }
            .sorted { $0.usd > $1.usd }
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
    /// `exchange` carries any connected venue's priced balances (prd §163,
    /// user ruling 2026-07-21: they MERGE — a portfolio built only from watched
    /// addresses is quietly wrong for anyone whose main holding sits on an
    /// exchange). A venue joins as a `Holder` beside the wallets, so the
    /// "Held in" read answers "which of my places holds this" rather than
    /// "which of my addresses" — and every share, the token count and the
    /// concentration line are computed over the merged set for free.
    ///
    /// It does NOT count toward `walletCount`: that number backs the phrase
    /// "in M wallets", and an exchange is not a wallet. Saying otherwise would
    /// be the honesty rule's own failure mode — a true-sounding number that
    /// isn't counting what it says.
    /// `validatorsUSD` is ETH held in watched beacon-chain validators
    /// (`EthValidatorRead.totalUSD()`) — folded in the same shape `exchange`
    /// is: a `Holder` with no real address (there isn't one to name), under
    /// the plain `ETH` symbol, since it's the same asset as everything else
    /// counted there, just sitting in a different kind of account.
    static func from(groups: [WalletIngest.HoldingsGroup],
                     exchange: [(symbol: String, usd: Double, venue: ExchangeBridge.Venue)] = [],
                     validatorsUSD: Double = 0)
    -> WalletPortfolio {
        var usdBySymbol: [String: Double] = [:]
        var holdersBySymbol: [String: [Holder]] = [:]
        var routeBySymbol: [String: (usd: Double, route: String)] = [:]

        for holding in exchange where holding.usd > 0 {
            usdBySymbol[holding.symbol, default: 0] += holding.usd
            // The venue's own name is both the id and the label — there is no
            // address, and inventing a fake one would put a "name this address"
            // verb on something that isn't one.
            holdersBySymbol[holding.symbol, default: []]
                .append(Holder(address: holding.venue.rawValue,
                               label: holding.venue.display, usd: holding.usd))
        }

        if validatorsUSD > 0 {
            usdBySymbol["ETH", default: 0] += validatorsUSD
            holdersBySymbol["ETH", default: []]
                .append(Holder(address: "ethvalidators", label: "ETH Validators", usd: validatorsUSD))
        }

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

    /// "ETH 61%" — how lopsided the book is (2026-07-21, compacted 2026-08-22).
    /// A portfolio-level read by nature: it means nothing about one holding
    /// and everything about the shape of the whole. nil when there's no shape
    /// to report (a single position, or no value at all).
    ///
    /// **The map cannot say this, which is the whole reason it survives the
    /// §447 cut.** `UnitTreemap` is RANK-ORDERED, not area-proportional (its
    /// own doc says why: true squarified cells arrive as slivers too thin to
    /// label), so the biggest cell is four units whether it is 61% of the book
    /// or 22% of it. Every other word that sat around that map was restating
    /// something already on the screen; this is the one fact the drawing is
    /// structurally unable to carry.
    ///
    /// It reads as a FRAGMENT rather than the old sentence ("ETH is 61% of
    /// everything") because it now sits in a tertiary tail beside its sibling
    /// below, under a header that already said what block this is. A sentence
    /// there would be the third voice on one card.
    var concentrationShort: String? {
        guard let top, let share = topShare else { return nil }
        let pct = Int((share * 100).rounded())
        // A share that rounds to 0% or 100% would claim a precision the
        // rounding just destroyed — the two ends stay quiet.
        guard pct > 0, pct < 100 else { return nil }
        return String(localized: "\(top.symbol) \(pct)%")
    }

    /// "21% stables" — the exposure whisper (2026-08-01, compacted 2026-08-22).
    ///
    /// A sibling to `concentrationShort`, deliberately in its exact idiom
    /// rather than a card: this survived design review as one line while its
    /// original other half (a by-chain bar) was cut as trivia — where the book
    /// lives changes no decision, how much of it can move does.
    ///
    /// **The other fact the map cannot draw**, and for a different reason from
    /// its sibling: stablecoins are scattered across the cells BY SYMBOL, so
    /// no arrangement of a per-symbol treemap ever groups them. It is the only
    /// reading on this card that nothing else on the screen carries.
    ///
    /// The rule about what counts, and the reason it's a set and not a prefix
    /// test, lives in `WalletStables`. Nil-ing is delegated there too, so the
    /// two lines can't disagree about when a share is too small to state.
    var stableShort: String? {
        let held = positions.map { (symbol: $0.symbol, usd: $0.usd) }
        guard let share = WalletStables.share(positions: held, totalUSD: totalUSD)
        else { return nil }
        return String(localized: "\(Int((share * 100).rounded()))% stables")
    }

    /// "ETH 61% · 21% stables" — the whole shape of the book in one tertiary
    /// line (2026-08-22, prd §447).
    ///
    /// **This is the residue of a four-line block, and the deletions are the
    /// point.** The holdings card used to print, above one drawing: a 22pt
    /// header, a 22pt concentration sentence, the map's own eyebrow (the
    /// header's words again, verbatim) and a subline whose money was the crown
    /// two cards up and whose wallet count was the face chips directly under
    /// it. §208 — never say one thing twice — with four instances on one card.
    ///
    /// What is left is exactly the pair the treemap cannot draw. Composed HERE
    /// rather than at the call site for the reason the old `concentrationLead`
    /// comment already gave: a sentence assembled in a view would be a second
    /// definition of concentration, and the two would drift.
    ///
    /// nil when neither half has anything to say — a legitimate outcome (a
    /// single-position book with no stables), and the tail then draws nothing
    /// rather than an empty row taking a spacing slot.
    var shapeLine: String? {
        let parts = [concentrationShort, stableShort].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    /// How the flow band names this window in a sentence (2026-08-01). The
    /// pill's "7d" is fine as a chip beside a number; a card whose whole claim
    /// is "this is the period I'm describing" says it in words.
    var flowLabel: String {
        switch self {
        case .week:    return String(localized: "This week")
        case .month:   return String(localized: "This month")
        case .watched: return String(localized: "Since you started watching")
        }
    }

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
