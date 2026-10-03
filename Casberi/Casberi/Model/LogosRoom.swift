import Foundation

/// The Logos room's SCOPE (prd §991) — the devnet family's template, this
/// network's vocabulary. `FramesSection` is the shape (`order`, `resolve`
/// falling back to `.home`, `emptyHeadline`/`emptyBody` for a scope with
/// nothing yet) and `DSRoomScopeChrome` is the shared control, which draws
/// Home first and the rest in the alphabet (§936 amended): Home · Holdings ·
/// Node · Rewards, then the verbs Create · Explorer · Send.
///
/// **What the family has that Logos does not, and why** (user, 2026-09-29:
/// "i just want to make sure we stay aligned w/ the devnets and wallet and not
/// create some new stuff unless we have to"):
///   • **Permissions** — LEZ's token program has no approve or delegate, so
///     nothing holds standing rights over an account.
///   • **Positions** — LEZ has an AMM program, and it has never run on the
///     testnet (measured 2026-10-03, 6,000 blocks), so there is no shape to
///     read a position against.
///   • **Risk** — nothing has a price, so nothing can move against you.
/// **Holdings** (prd §1084) arrived with v0.3: a token holding is a SHARD on
/// the holder's own account, read off `getAccount`, where v0.2 kept it in a
/// separate account nothing public mapped to an owner — the reason it was
/// absent until now. **Node is the one scope the family did not have**,
/// because it is the one thing Logos lets you run. **Rewards** (prd §1016) is
/// what that node earns, so Node answers "is it healthy" and Rewards "what
/// has it earned".
enum LogosSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case holdings
    case node
    case rewards
    /// The room's VERBS (prd §1039, §1084): make this phone's account, open
    /// the explorer for the page showing, send test coins. Never scopes —
    /// never in `order`, never resolved to, never lit.
    case create
    case explorer
    case send

    var id: String { rawValue }

    /// **HOME'S LIST IS THE ACTIVITY (prd §1039).** The Activity and Accounts
    /// tiles are deleted, as in the Wallet and Frames: Home lists the chain's
    /// moves and the account menu under the tiles picks the account.
    static let order: [LogosSection] = [.home, .holdings, .node, .rewards]

    /// Every verb, drawn after the scopes (`DSScopeTiles.alphabetical`).
    /// Which of them a page shows is `verbs(for:)`.
    static let verbs: [LogosSection] = [.create, .explorer, .send]

    var isVerb: Bool { Self.verbs.contains(self) }

    /// The verbs for the page showing (prd §1084, Frames' rule §774 in this
    /// room's words). This phone holds no Logos key: Create and Explorer.
    /// It holds one: Explorer and Send on the All page and on its own
    /// account's — one account per phone, so Create goes — and Explorer
    /// alone on a watched stranger's page, where nothing can be sent from.
    /// `holdsKey`/`mine` are defaults reads (`LogosKey`), never the Keychain.
    static func verbs(forAccount account: String?, keyAccount: String?) -> [LogosSection] {
        guard let keyAccount else { return [.create, .explorer] }
        if let account, account != keyAccount { return [.explorer] }
        return [.explorer, .send]
    }

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .holdings: return String(localized: "Holdings")
        case .node:     return String(localized: "Node")
        case .rewards:  return String(localized: "Rewards")
        case .create:   return String(localized: "Create")
        case .explorer: return String(localized: "Explorer")
        case .send:     return String(localized: "Send")
        }
    }

    var summary: String {
        switch self {
        case .home:     return String(localized: "The balance, and what moved, dated from its block")
        case .holdings: return String(localized: "The tokens your accounts hold")
        case .node:     return String(localized: "Your node's sync and peers")
        case .rewards:  return String(localized: "What your node earns: mining tickets and reward vouchers")
        case .create:   return String(localized: "Make a Logos account on this phone")
        case .explorer: return String(localized: "Open the testnet's explorer")
        case .send:     return String(localized: "Send test coins from this phone's account")
        }
    }

    /// Every scope is drawn always (prd §611); an empty one says so.
    static func present() -> [LogosSection] { order }

    var emptyHeadline: String? {
        switch self {
        case .holdings: return String(localized: "No tokens")
        case .node:     return String(localized: "No node")
        case .rewards:  return String(localized: "No node")
        case .home, .create, .explorer, .send: return nil
        }
    }

    var emptyBody: String? {
        switch self {
        case .holdings: return String(localized: "A token held by an account you watch.")
        case .node:     return String(localized: "Give the Logos page your node's address.")
        case .rewards:  return String(localized: "Mine with your own Logos node, added on the Logos page.")
        case .home, .create, .explorer, .send: return nil
        }
    }

    static func resolve(_ wanted: LogosSection?, present: [LogosSection]) -> LogosSection {
        guard let wanted, !wanted.isVerb, present.contains(wanted) else { return .home }
        return wanted
    }
}

/// What the room draws, composed from the store — the accounts and their
/// balances, your node's last reading, and the balance line sampled on every
/// pass (`RoomValueHistory`, the devnets' own).
enum LogosRoom {
    static let source = "Logos"

    struct Account: Identifiable, Equatable {
        let id: String
        let balance: Decimal?
    }

    struct Head: Equatable {
        let accounts: [Account]
        let total: Decimal?
        let series: [WalletStore.ValueSample]
        let node: LogosWire.NodeSnapshot?
        let nodeWatched: Bool
        let hasRead: Bool
        /// The day the current chain began, while an account reads empty in
        /// the month after it (prd §1035); nil otherwise.
        var resetDay: Date? = nil
        /// What the accounts in scope hold besides native coins (prd §1084).
        var tokens: [Token] = []
    }

    /// One token held across the accounts in scope, summed by definition —
    /// a room's All is the sum of what it watches, as its crown is.
    struct Token: Equatable, Identifiable {
        var id: String { definition }
        let definition: String
        let name: String?
        let nft: Bool
        /// The balance, or copies left to print for a master; nil for
        /// printed copies, which are counted in `copies`.
        let amount: Decimal?
        let copies: Int
    }

    /// The tokens `ids` hold, merged by definition, in the order they were
    /// found — never sorted by amount, because two tokens' amounts are in
    /// two units.
    @MainActor
    static func tokens(_ ids: [String]) -> [Token] {
        let store = LogosStore.shared
        var order: [String] = []
        var merged: [String: Token] = [:]
        for id in ids {
            guard let h = store.holding(for: id) else { continue }
            let amount = h.amount.flatMap { Decimal(string: $0) }
            let copy = h.kind == "nftCopy"
            if let seen = merged[h.definition] {
                merged[h.definition] = Token(
                    definition: h.definition, name: seen.name, nft: seen.nft,
                    amount: seen.amount == nil && amount == nil ? nil : (seen.amount ?? 0) + (amount ?? 0),
                    copies: seen.copies + (copy ? 1 : 0))
            } else {
                order.append(h.definition)
                merged[h.definition] = Token(definition: h.definition, name: store.tokenNames[h.definition],
                                             nft: h.kind != "fungible", amount: amount,
                                             copies: copy ? 1 : 0)
            }
        }
        return order.compactMap { merged[$0] }
    }

    /// The row a watched account's rows carry in their ref:
    /// `logos:lez:<account>:<hash>`.
    static func account(ofRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix("logos:lez:") else { return nil }
        let parts = ref.split(separator: ":")
        return parts.count >= 4 ? String(parts[2]) : nil
    }

    /// A node row's ref is `logos:node:<kind>:<seconds>`; its kind says which
    /// scope it belongs to.
    static func nodeKind(ofRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix("logos:node:") else { return nil }
        let parts = ref.split(separator: ":")
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    /// What the node EARNED (prd §1016): vouchers, tickets, and mining
    /// starting or stopping. Every other node row is its health.
    static let rewardKinds: Set<String> = ["vouchers", "tickets", "mining", "idle"]

    static func isNodeRef(_ ref: String?) -> Bool {
        nodeKind(ofRef: ref).map { !rewardKinds.contains($0) } ?? false
    }

    static func isRewardsRef(_ ref: String?) -> Bool {
        nodeKind(ofRef: ref).map(rewardKinds.contains) ?? false
    }

    /// `scope` narrows to one account (the deck's pick); nil is All.
    @MainActor
    static func compose(scope: String?) -> Head {
        let store = LogosStore.shared
        let ids = scope.map { id in store.accounts.filter { $0 == id } } ?? store.accounts
        let accounts = ids.map { Account(id: $0, balance: store.balance(for: $0)) }
        let known = accounts.compactMap(\.balance)
        let total: Decimal? = known.isEmpty ? nil : known.reduce(0, +)
        return Head(accounts: accounts, total: total,
                    series: RoomValueHistory.combined(room: source, addresses: ids),
                    node: store.nodeSnapshot, nodeWatched: store.node != nil,
                    hasRead: store.readAt != nil || store.nodeSnapshot != nil,
                    resetDay: store.showsResetNote() ? store.chainStart : nil,
                    tokens: tokens(ids))
    }
}
