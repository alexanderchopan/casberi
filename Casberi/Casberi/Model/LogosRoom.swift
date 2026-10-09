import Foundation

/// The Logos room's SCOPE (prd §991) — the devnet family's template, this
/// network's vocabulary. Frames' section enum was the shape (`order`, `resolve`
/// falling back to `.home`, `emptyHeadline`/`emptyBody` for a scope with
/// nothing yet) and `DSRoomScopeChrome` is the shared control, which draws
/// Home first and the rest in the alphabet (§936 amended): Home · Chat ·
/// Holdings · Node (prd §1155: Rewards folded into Node to make room for
/// Chat, the four-tile row §1107 kept). The verbs are rows, not tiles (prd §1108): Create is "New
/// account" at the head of the Accounts menu and Send leads Holdings, as in
/// Frames (deleted, prd §1206); Explorer's door is the Logos page's, and every row opens its own
/// transaction there.
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
/// because it is the one thing Logos lets you run, and it carries what that
/// node earns (§1016's Rewards, folded in by §1155): unclaimed rewards are
/// the node's, and only a claim makes them a holding. **Chat** (§1155) reads
/// your Logos conversations from Basecamp through a paired Observer, live,
/// and keeps nothing.
enum LogosSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case chat
    case holdings
    case node

    var id: String { rawValue }

    /// **HOME'S LIST IS THE ACTIVITY (prd §1039).** The Activity and Accounts
    /// tiles are deleted, as in the Wallet and Frames: Home lists the chain's
    /// moves and the account menu under the tiles picks the account.
    static let order: [LogosSection] = [.home, .chat, .holdings, .node]

    /// **WHICH ACTS A PAGE OFFERS (prd §1084's rule, drawn as rows since
    /// §1108).** One account per phone: "New account" heads the Accounts menu
    /// only while this phone holds no Logos key. Send leads Holdings on the
    /// All page and on this phone's own account's, never on a watched
    /// stranger's, where nothing can be sent from. `keyAccount` is a defaults
    /// read (`LogosKey`), never the Keychain.
    static func canCreate(keyAccount: String?) -> Bool { keyAccount == nil }

    static func canSend(account: String?, keyAccount: String?) -> Bool {
        guard let keyAccount else { return false }
        return account == nil || account == keyAccount
    }

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .chat:     return String(localized: "Chat")
        case .holdings: return String(localized: "Holdings")
        case .node:     return String(localized: "Node")
        }
    }

    var summary: String {
        switch self {
        case .home:     return String(localized: "The balance, and what moved, dated from its block")
        case .chat:     return String(localized: "Your Logos chats, read from Basecamp through Observer")
        case .holdings: return String(localized: "The tokens your accounts hold")
        case .node:     return String(localized: "Your node's sync, peers, mining and rewards")
        }
    }

    /// Every scope is drawn always (prd §611); an empty one says so.
    static func present() -> [LogosSection] { order }

    var emptyHeadline: String? {
        switch self {
        case .holdings: return String(localized: "No tokens")
        case .node:     return String(localized: "No node")
        case .home, .chat: return nil
        }
    }

    var emptyBody: String? {
        switch self {
        case .holdings: return String(localized: "A token held by an account you follow.")
        case .node:     return String(localized: "Add your node on the Logos page.")
        case .home, .chat: return nil
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

    /// What an account is called (prd §1091): the name you gave it in the
    /// address book, or its short id. One read, so the page, the menu and
    /// the caption cannot call one account two things.
    static func name(for id: String) -> String {
        AddressBook.shared.name(for: id) ?? LogosWire.short(id)
    }

    /// The row a watched account's rows carry in their ref:
    /// `logos:lez:<account>:<hash>`.
    static func account(ofRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix("logos:lez:") else { return nil }
        let parts = ref.split(separator: ":")
        return parts.count >= 4 ? String(parts[2]) : nil
    }

    /// A node row's ref is `logos:node:<kind>:<seconds>`.
    static func nodeKind(ofRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix("logos:node:") else { return nil }
        let parts = ref.split(separator: ":")
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    /// Every node row is Node's: its health and what it earned (prd §1155).
    static func isNodeRef(_ ref: String?) -> Bool { nodeKind(ofRef: ref) != nil }

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
