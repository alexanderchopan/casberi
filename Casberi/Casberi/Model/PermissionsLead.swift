import Foundation

/// **PERMISSIONS' BOX LEADS WITH THE WORST ONE (prd §1633).** The page's box
/// was a count over "can spend from you", which says how many and never which.
/// It now names the one permission to look at by its kind ("Unlimited
/// approval") over whose it is ("Uniswap · USDC"), and a strip under it shows
/// the dollars each app can reach, the lead's lit.
///
/// What leads, in order:
/// 1. A delegate nobody can name: it acts as your account and is the one
///    thing here that is never ordinary.
/// 2. The grant with the most dollars at stake (`WalletApprovalExposure`'s
///    own pricing); a grant with no limit wins a tie.
/// 3. With nothing priced, a grant with no limit, then a whole collection,
///    then the oldest.
/// 4. A named delegate, then a Safe module, only when nothing above is
///    there: your own wallet's upgrade and a module you installed are
///    ordinary, so they never push a grant out of the box. They do lead an
///    otherwise empty page, so the box never says no app can spend from you
///    over a list that holds one.
///
/// Foundation-only, so `permissions-box-selftest.sh` compiles it as shipped.
enum PermissionsLead: Equatable {
    case grant(WalletApprovalExposure.Grant)
    /// `name` nil is a contract with no known name: the line draws its
    /// address tail.
    case delegate(key: String, name: String?, accounts: [String])
    /// A Safe module: it moves money with no signature (§1594 keeps its row
    /// still, so it has no verb).
    case module(key: String, name: String, accounts: [String])

    struct Delegate: Equatable {
        let key: String
        let name: String?
        let accounts: [String]
        var module = false
    }

    static func pick(grants: [WalletApprovalExposure.Grant],
                     delegates: [Delegate]) -> PermissionsLead? {
        let modules = delegates.filter(\.module)
        let actors = delegates.filter { !$0.module }
        if let unknown = actors.first(where: { $0.name == nil }) {
            return .delegate(key: unknown.key, name: nil, accounts: unknown.accounts)
        }
        if let grant = worstGrant(grants) { return .grant(grant) }
        if let known = actors.first {
            return .delegate(key: known.key, name: known.name, accounts: known.accounts)
        }
        if let module = modules.first {
            return .module(key: module.key, name: module.name ?? module.key, accounts: module.accounts)
        }
        return nil
    }

    static func worstGrant(_ grants: [WalletApprovalExposure.Grant]) -> WalletApprovalExposure.Grant? {
        let priced = grants.filter { ($0.usd ?? 0) > 0 }
        if let top = priced.max(by: { a, b in
            let ua = a.usd ?? 0, ub = b.usd ?? 0
            return ua == ub ? (!a.unlimited && b.unlimited) : ua < ub
        }) { return top }
        let oldestFirst = grants.sorted { ($0.grantedAt ?? .distantFuture) < ($1.grantedAt ?? .distantFuture) }
        return oldestFirst.first { $0.unlimited && !$0.forAll }
            ?? oldestFirst.first(where: \.forAll)
            ?? oldestFirst.first
    }

    var grantID: UUID? {
        if case .grant(let g) = self { return g.thingID }
        return nil
    }

    // MARK: - The words

    var isUnknownDelegate: Bool {
        if case .delegate(_, nil, _) = self { return true }
        return false
    }

    /// The box's name for it, the approval's kind and nothing more (user,
    /// 2026-10-31, of "Uniswap can take all your USDC": "this is too
    /// literal. needs to say unlimited approval. that's it").
    var title: String {
        switch self {
        case .grant(let g):
            if g.forAll { return String(localized: "Collection approval") }
            if g.unlimited { return String(localized: "Unlimited approval") }
            return String(localized: "Capped approval")
        case .delegate(_, let name, _):
            return name == nil ? String(localized: "Unknown delegate") : String(localized: "Delegate")
        case .module:
            return String(localized: "Safe module")
        }
    }

    /// Whose it is and on what, and nothing else (user: "the rest of this is
    /// hyperbolic and AI slop"): "Uniswap · USDC", "MetaMask · Main".
    var line: String {
        switch self {
        case .grant(let g):
            return "\(g.spender) · \(g.symbol)"
        case .delegate(let key, let name, let accounts):
            // The title already says "Unknown delegate"; the line says which
            // contract (user, 2026-11-02, of "A contract nobody can name":
            // "this is weird language").
            return ([name ?? AddressTail.short(key)]
                    + (accounts.isEmpty ? [] : [accounts.formatted(.list(type: .and))])).joined(separator: " · ")
        case .module(_, let name, let accounts):
            return ([name] + (accounts.isEmpty ? [] : [accounts.formatted(.list(type: .and))])).joined(separator: " · ")
        }
    }

    // MARK: - The strip

    /// One piece of the strip: a priced grant, sized by its dollars.
    struct Segment: Equatable, Identifiable {
        let id: String
        let name: String
        let usd: Double
        let unlimited: Bool
        let lit: Bool
    }

    /// The priced grants, largest first, the lead's lit. Past `shown`, the
    /// rest are one piece, so a wallet with forty grants still draws a strip
    /// whose pieces can be seen.
    static func strip(_ grants: [WalletApprovalExposure.Grant], lead: UUID?, shown: Int = 6) -> [Segment] {
        let priced = grants.filter { ($0.usd ?? 0) > 0 }.sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
        var out = priced.prefix(shown).map {
            Segment(id: $0.id, name: $0.spender, usd: $0.usd ?? 0, unlimited: $0.unlimited,
                    lit: $0.thingID == lead)
        }
        let rest = priced.dropFirst(shown)
        if !rest.isEmpty {
            let sum = rest.compactMap(\.usd).reduce(0, +)
            out.append(Segment(id: "rest", name: String(localized: "\(rest.count) more"), usd: sum,
                               unlimited: false, lit: rest.contains { $0.thingID == lead }))
        }
        return out
    }

    /// Each piece's width in `width`: no piece under `floor`, the floors
    /// taken out of the width before the rest is shared by dollars, so the
    /// strip never runs past its box. Too many pieces for their floors share
    /// the width equally.
    static func widths(_ values: [Double], in width: Double, floor: Double, gap: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let room = max(0, width - gap * Double(values.count - 1))
        if floor * Double(values.count) >= room {
            return Array(repeating: room / Double(values.count), count: values.count)
        }
        var floored = Set<Int>()
        while true {
            let share = values.indices.filter { !floored.contains($0) }
            let sum = share.map { values[$0] }.reduce(0, +)
            let left = room - floor * Double(floored.count)
            let small = share.filter { sum <= 0 || left * values[$0] / sum < floor }
            if small.isEmpty {
                return values.indices.map { floored.contains($0) ? floor : left * values[$0] / sum }
            }
            if small.count == share.count {
                // Every piece left is a sliver: they split what is left.
                return values.indices.map { floored.contains($0) ? floor : left / Double(share.count) }
            }
            floored.formUnion(small)
        }
    }
}
