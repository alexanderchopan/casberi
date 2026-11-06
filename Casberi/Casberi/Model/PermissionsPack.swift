import Foundation
import CoreGraphics

/// **PERMISSIONS' BOX IS A PACK (prd §1654, retiring §1633's lead and strip).**
/// One circle per app that can move your tokens, its area the dollars it can
/// reach; an app with no limit on any of its grants is ringed in amber. The
/// box names nothing and says nothing: the circles are the reading, and the
/// Delegations and Approvals lists under the box carry the words.
///
/// The rules:
/// 1. **One circle per app, by its name.** Uniswap's routers on USDC and WETH
///    are one Uniswap; its dollars add, and it is ringed if any of its grants
///    has no limit. An app nobody can name is its short hex, so two unnamed
///    contracts stay two circles.
/// 2. **Largest first:** the dollars, no limit winning a tie; then the apps
///    nothing priced, no limit first, then a whole collection, then by name.
///    An unpriced app draws at the pack's floor (`CirclePack`'s rule for a
///    share of zero), never as nothing.
/// 3. **Eight, then one More** (`cap`): past eight apps the rest are one grey
///    circle, "N more", whose dollars are theirs; one app past eight is drawn
///    rather than folded, so More always holds two or more.
///
/// 4. **A delegate and a Safe module are circles too (prd §1677).** They are
///    on the page's Delegations list, so a box that left them out said "No
///    approvals" over a list that held one. Each is its own circle, keyed on
///    the contract (never the name), unpriced, filled as no limit — both reach
///    everything of yours — and sorted first among the unpriced.
///
/// 5. **The box is your balance, reached (prd §1710, retiring §1654's pack of
///    apps).** One disc is what the scope's own wallets hold (`held`, venues
///    out: an approval or a delegate reaches a wallet, never Kraken). A
///    delegate or module reaches its accounts' holdings; when that is every
///    held dollar the whole disc is amber with the balance on it. An app's
///    grants are circles inside it at their dollars (`inside`), so the grey
///    left over is what nothing can move.
///
/// Foundation-only (and `CirclePack`), so `permissions-box-selftest.sh`
/// compiles it as shipped.
enum PermissionsPack {
    typealias Grant = WalletApprovalExposure.Grant

    static let cap = 8
    static let moreID = "permissions.more"

    /// A delegate or module, as the Delegations list carries it
    /// (`WalletPermissions.Holder`, reduced to what the pack draws).
    struct Acting: Equatable {
        /// The acting contract or key id — the holder's `key`.
        let key: String
        let name: String
        /// A Safe module; false for a delegate.
        let module: Bool
        /// Which of your wallets it acts for (`WalletPermissions.Holder.accounts`).
        var accounts: [String] = []
    }

    struct Piece: Equatable, Identifiable {
        /// The app's name, or `moreID`.
        let id: String
        /// "Uniswap", or "3 more".
        let name: String
        /// What it reaches, most dollars first, each once.
        let symbols: [String]
        /// The dollars it can move now; 0 when none of its grants is priced.
        let usd: Double
        let unlimited: Bool
        let forAll: Bool
        let grantIDs: [UUID]
        /// How many apps a More circle holds; 1 for an app.
        let apps: Int
        /// The delegate's or module's key; nil for an app's grants.
        var actingKey: String? = nil
        var module = false

        var isActing: Bool { actingKey != nil }

        var isMore: Bool { id == PermissionsPack.moreID }
        var priced: Bool { usd > 0 }
    }

    /// `held`: what each of your wallets holds, keyed lowercased
    /// (`heldByAccount`). A delegate's or module's dollars are its accounts'
    /// (§1710); with no reading they are none, and it sorts as unpriced.
    static func pieces(_ grants: [Grant], acting: [Acting] = [], held: [String: Double] = [:],
                       cap: Int = cap) -> [Piece] {
        var order: [String] = []
        var groups: [String: [Grant]] = [:]
        for g in grants {
            if groups[g.spender] == nil { order.append(g.spender) }
            groups[g.spender, default: []].append(g)
        }
        let granted = order.map { name -> Piece in
            let gs = (groups[name] ?? []).sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
            var symbols: [String] = []
            for g in gs where !symbols.contains(g.symbol) { symbols.append(g.symbol) }
            return Piece(id: name, name: name, symbols: symbols,
                         usd: gs.compactMap(\.usd).filter { $0 > 0 }.reduce(0, +),
                         unlimited: gs.contains { $0.unlimited && !$0.forAll },
                         forAll: gs.contains { $0.forAll },
                         grantIDs: gs.map(\.thingID), apps: 1)
        }
        var keys: Set<String> = []
        let actors = acting.filter { keys.insert($0.key).inserted }.map { a in
            Piece(id: "acting:\(a.key)", name: a.name,
                  symbols: [a.module ? String(localized: "Safe module") : String(localized: "Delegate")],
                  usd: reach(of: [a], held: held), unlimited: true, forAll: false, grantIDs: [], apps: 1,
                  actingKey: a.key, module: a.module)
        }
        let apps = (granted + actors).sorted(by: before)
        guard apps.count > cap + 1 else { return apps }
        let rest = apps.dropFirst(cap)
        let more = Piece(id: moreID, name: String(localized: "\(rest.count) more"), symbols: [],
                         usd: rest.map(\.usd).reduce(0, +), unlimited: false, forAll: false,
                         grantIDs: rest.flatMap(\.grantIDs), apps: rest.count)
        return Array(apps.prefix(cap)) + [more]
    }

    private static func before(_ a: Piece, _ b: Piece) -> Bool {
        if a.priced != b.priced { return a.priced }
        if a.priced, a.usd != b.usd { return a.usd > b.usd }
        if a.priced, a.isActing != b.isActing { return a.isActing }
        if a.isActing != b.isActing { return a.isActing }
        if a.unlimited != b.unlimited { return a.unlimited }
        if a.forAll != b.forAll { return a.forAll }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// The dollars the apps' grants reach, or nil when nothing is priced: a
    /// $0 would read as nothing at stake (`WalletPermissions.totalUSD`'s
    /// rule). A delegate's dollars are its accounts' and are the disc's to
    /// state (`Disc.reach`), never added here: two on one wallet would count
    /// it twice.
    static func total(_ pieces: [Piece]) -> Double? {
        let sum = pieces.filter { !$0.isActing }.map(\.usd).reduce(0, +)
        return sum > 0 ? sum : nil
    }

    // MARK: - The disc (prd §1710)

    /// What each wallet holds, keyed lowercased, from the portfolio's holders
    /// with every place left out (`WalletPortfolio.isVenue`): an exchange, the
    /// validators, cash, Privy, Private and what you lent are out of an
    /// approval's reach.
    static func heldByAccount(_ positions: [(holder: String, usd: Double)],
                              isVenue: (String) -> Bool) -> [String: Double] {
        var out: [String: Double] = [:]
        for p in positions where p.usd > 0 && !isVenue(p.holder) {
            out[p.holder.lowercased(), default: 0] += p.usd
        }
        return out
    }

    /// What the delegates and modules reach between them: each account's
    /// holdings once, however many act for it.
    static func reach(of acting: [Acting], held: [String: Double]) -> Double {
        let accounts = Set(acting.flatMap { $0.accounts.map { $0.lowercased() } })
        return accounts.compactMap { held[$0] }.reduce(0, +)
    }

    /// The box's one disc.
    struct Disc: Equatable {
        /// What the scope's wallets hold; 0 when there is no reading.
        let held: Double
        /// What the delegates and modules reach.
        let acting: Double
        /// What the apps' grants reach. Summed per grant: a grant carries no
        /// wallet, so one on a delegated wallet is not netted out — `reach`
        /// caps at `held` rather than state more than you have.
        let granted: Double
        /// Something acts for you with no reading of what it reaches.
        let actingUnread: Bool

        /// Every held dollar is in a delegate's or module's reach — or one
        /// acts and nothing says what you hold: then it reaches everything.
        var whole: Bool {
            (held > 0 && acting >= held - 0.005) || (held <= 0 && actingUnread)
        }

        /// The dollars in reach, never more than you hold; nil when none is
        /// priced.
        var reach: Double? {
            let sum = whole ? held : acting + granted
            let capped = held > 0 ? min(sum, held) : sum
            return capped > 0 ? capped : nil
        }

        /// What the disc's area stands for: the balance, or the reach when
        /// there is no balance read (or the grants' sum outruns it).
        var scale: Double { max(held, acting + granted) }
    }

    static func disc(_ pieces: [Piece], acting: [Acting], held: [String: Double]) -> Disc {
        let h = held.values.reduce(0, +)
        return Disc(held: h,
                    acting: reach(of: acting, held: held),
                    granted: pieces.filter { !$0.isActing && !$0.isMore }.map(\.usd).reduce(0, +),
                    actingUnread: !acting.isEmpty && reach(of: acting, held: held) <= 0)
    }

    /// The circles drawn inside the disc: every priced piece but the whole
    /// disc's own delegates, in the pieces' order.
    static func inner(_ pieces: [Piece], disc: Disc) -> [Piece] {
        pieces.filter { $0.priced && !(disc.whole && $0.isActing) }
    }

    /// Circles for `usd` inside a disc `diameter` across whose area is
    /// `scale` dollars: each circle's area its share of the disc's, the pack
    /// centred on the disc. True area whenever the pack fits the disc at that
    /// size; when it cannot (shares adding up near the whole disc), the pack
    /// shrinks together, ratios kept. In the disc's own coordinates.
    ///
    /// The pack is laid out once for its arrangement and then scaled to the
    /// truth, up or down: §1710's first cut capped the scale at the pack's
    /// fit in the disc's inscribed square, so a $3,200 grant on a $12,480
    /// disc drew at 45pt of a true 50.6 (`permissions-box-selftest.sh`).
    static func inside(_ usd: [Double], scale: Double, diameter: CGFloat,
                       gap: CGFloat = 4) -> [CirclePack.Circle] {
        guard !usd.isEmpty, diameter > 0, scale > 0 else { return [] }
        let packed = CirclePack.layout(shares: usd, in: CGSize(width: diameter, height: diameter),
                                       gap: gap, floor: 0)
        guard !packed.isEmpty else { return [] }
        // A circle's true radius is the disc's times √share. Every circle
        // carries the same ratio (no floor), so the largest names it.
        let largest = usd.indices.max { usd[$0] < usd[$1] } ?? 0
        let truth = diameter / 2 * CGFloat((max(usd[largest], 0) / scale).squareRoot())
        var s = packed[largest].radius > 0 ? truth / packed[largest].radius : 1
        // The cluster's own middle (its bounds'), and how far it reaches from
        // there at that size; past the disc's edge, everything shrinks together.
        let cx = (packed.map { $0.center.x - $0.radius }.min()! + packed.map { $0.center.x + $0.radius }.max()!) / 2
        let cy = (packed.map { $0.center.y - $0.radius }.min()! + packed.map { $0.center.y + $0.radius }.max()!) / 2
        let reach = packed.map { hypot($0.center.x - cx, $0.center.y - cy) + $0.radius }.max()! * s
        if reach > diameter / 2 { s *= diameter / 2 / reach }
        let mid = diameter / 2
        return packed.map { c in
            CirclePack.Circle(center: CGPoint(x: mid + (c.center.x - cx) * s,
                                              y: mid + (c.center.y - cy) * s),
                              radius: c.radius * s)
        }
    }
}
