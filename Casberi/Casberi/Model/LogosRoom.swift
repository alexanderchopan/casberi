import Foundation

/// The Logos room's SCOPE (prd §991) — the devnet family's template, this
/// network's vocabulary. `FramesSection` is the shape (`order`, `resolve`
/// falling back to `.home`, `emptyHeadline`/`emptyBody` for a scope with
/// nothing yet) and `DSRoomScopeChrome` is the shared control, which draws
/// Home first and the rest in the alphabet (§936 amended): Home · Accounts ·
/// Activity · Node · Rewards.
///
/// **What the family has that Logos does not, and why** (user, 2026-09-29:
/// "i just want to make sure we stay aligned w/ the devnets and wallet and not
/// create some new stuff unless we have to"):
///   • **Holdings** — its job is the split by asset (§688), and the one asset
///     readable here is the native coin. A token lives in its own holding
///     account, which nothing public maps an owner to.
///   • **Permissions** — LEZ's token program has no approve or delegate, so
///     nothing holds standing rights over an account. Which program owns an
///     account is a line on Accounts, not a scope.
///   • **Positions, NFTs** — both exist on LEZ (an AMM program; NFT prints) and
///     wait on the same indexer Holdings does.
///   • **Risk** — nothing has a price, so nothing can move against you.
/// **Node is the one scope the family did not have**, because it is the one
/// thing Logos lets you run. **Rewards** (prd §1016) is what that node earns —
/// mining tickets and reward vouchers, both off the node's own API — so Node
/// answers "is it healthy" and Rewards "what has it earned", and nothing
/// earned sits on Node.
enum LogosSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    case accounts
    case node
    case rewards

    var id: String { rawValue }

    static let order: [LogosSection] = [.home, .activity, .accounts, .node, .rewards]

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .activity: return String(localized: "Activity")
        case .accounts: return String(localized: "Accounts")
        case .node:     return String(localized: "Node")
        case .rewards:  return String(localized: "Rewards")
        }
    }

    var summary: String {
        switch self {
        case .home:     return String(localized: "The balance, and the last few moves")
        case .activity: return String(localized: "What moved, dated from its block")
        case .accounts: return String(localized: "The accounts you watch")
        case .node:     return String(localized: "Your node's sync and peers")
        case .rewards:  return String(localized: "What your node earns: mining tickets and reward vouchers")
        }
    }

    /// Every scope is drawn always (prd §611); an empty one says so.
    static func present() -> [LogosSection] { order }

    var emptyHeadline: String? {
        switch self {
        case .home:     return nil
        case .activity: return String(localized: "None yet")
        case .accounts: return String(localized: "No accounts yet")
        case .node:     return String(localized: "No node")
        case .rewards:  return String(localized: "No node")
        }
    }

    var emptyBody: String? {
        switch self {
        case .home:     return nil
        case .activity: return String(localized: "Covers what moved since you started watching.")
        case .accounts: return String(localized: "Paste an LEZ account id on the Logos page.")
        case .node:     return String(localized: "Give the Logos page your node's address.")
        case .rewards:  return String(localized: "Mine with your own Logos node, added on the Logos page.")
        }
    }

    static func resolve(_ wanted: LogosSection?, present: [LogosSection]) -> LogosSection {
        guard let wanted, present.contains(wanted) else { return .home }
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
                    resetDay: store.showsResetNote() ? store.chainStart : nil)
    }
}
