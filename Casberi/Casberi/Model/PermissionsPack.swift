import Foundation

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
/// Foundation-only, so `permissions-box-selftest.sh` compiles it as shipped.
enum PermissionsPack {
    typealias Grant = WalletApprovalExposure.Grant

    static let cap = 8
    static let moreID = "permissions.more"

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

        var isMore: Bool { id == PermissionsPack.moreID }
        var priced: Bool { usd > 0 }
    }

    static func pieces(_ grants: [Grant], cap: Int = cap) -> [Piece] {
        var order: [String] = []
        var groups: [String: [Grant]] = [:]
        for g in grants {
            if groups[g.spender] == nil { order.append(g.spender) }
            groups[g.spender, default: []].append(g)
        }
        let apps = order.map { name -> Piece in
            let gs = (groups[name] ?? []).sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
            var symbols: [String] = []
            for g in gs where !symbols.contains(g.symbol) { symbols.append(g.symbol) }
            return Piece(id: name, name: name, symbols: symbols,
                         usd: gs.compactMap(\.usd).filter { $0 > 0 }.reduce(0, +),
                         unlimited: gs.contains { $0.unlimited && !$0.forAll },
                         forAll: gs.contains(\.forAll),
                         grantIDs: gs.map(\.thingID), apps: 1)
        }.sorted(by: before)
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
        if a.unlimited != b.unlimited { return a.unlimited }
        if a.forAll != b.forAll { return a.forAll }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// The dollars in reach, or nil when nothing is priced: a $0 would read as
    /// nothing at stake (`WalletPermissions.totalUSD`'s rule).
    static func total(_ pieces: [Piece]) -> Double? {
        let sum = pieces.map(\.usd).reduce(0, +)
        return sum > 0 ? sum : nil
    }
}
