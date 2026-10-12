import Foundation

/// The Aztec room's SCOPE (2026-10-11) — the testnets' template (Logos'
/// `LogosSection`), this network's vocabulary: **Home · Holdings · Node**.
///
/// **Home is the network**, because on a private chain the network is the
/// one public thing everybody shares: the proposed block, how far proving
/// lags it, and the minimum fee. Its list is every row the room has.
/// **Node is the sequencers you follow** — Logos' word for the thing you run
/// — and its list is their duty rows.
///
/// **Holdings is the PUBLIC half of an account** (round two): the Fee Juice
/// an account holds publicly. Its private notes are encrypted to its owner,
/// and the box says so rather than drawing a total it cannot know.
/// Permissions, Positions and Risk need an account's private state.
enum AztecSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case holdings
    case node

    var id: String { rawValue }

    static let order: [AztecSection] = [.home, .holdings, .node]

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .holdings: return String(localized: "Holdings")
        case .node:     return String(localized: "Node")
        }
    }

    var summary: String {
        switch self {
        case .home:     return String(localized: "The Aztec testnet's blocks, proving and fees")
        case .holdings: return String(localized: "The Fee Juice your accounts hold publicly")
        case .node:     return String(localized: "The sequencers you follow: duty, stake and schedule")
        }
    }

    /// Every scope is drawn always (prd §611); an empty one says so.
    static func present() -> [AztecSection] { order }

    var emptyHeadline: String? {
        switch self {
        case .node:     return String(localized: "No sequencer")
        case .holdings: return String(localized: "No account")
        case .home:     return nil
        }
    }

    var emptyBody: String? {
        switch self {
        case .node:     return String(localized: "Follow a sequencer's attester address on the Aztec page.")
        case .holdings: return String(localized: "Follow an Aztec account to see its public Fee Juice.")
        case .home:     return nil
        }
    }

    static func resolve(_ wanted: AztecSection?, present: [AztecSection]) -> AztecSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }
}

/// What the room draws, composed from the store.
enum AztecRoom {
    static let source = "Aztec"

    /// The `RoomValueHistory` series Home's line draws: proving lag, blocks.
    static let networkSeries = "network:provenLag"

    struct Head: Equatable {
        let network: AztecStore.Network?
        let sequencers: [AztecWire.Sequencer]
        /// Followed addresses this node has not seen (no reading).
        let unseen: [String]
        let followed: Int
        let hasRead: Bool
        /// Home's line: the proving lag as this phone sampled it.
        var lagSeries: [WalletStore.ValueSample] = []
        /// Stake and schedule, by sequencer address.
        var stakes: [String: AztecWire.Stake] = [:]
        var duties: [String: AztecStore.Duty] = [:]
        var stakeSymbol: String? = nil
        /// Followed accounts and their public Fee Juice (nil: not read yet).
        var accounts: [(address: String, feeJuice: Decimal?)] = []

        static func == (a: Head, b: Head) -> Bool {
            a.network == b.network && a.sequencers == b.sequencers && a.unseen == b.unseen
                && a.followed == b.followed && a.hasRead == b.hasRead && a.lagSeries == b.lagSeries
                && a.stakes == b.stakes && a.duties == b.duties && a.stakeSymbol == b.stakeSymbol
                && a.accounts.map(\.address) == b.accounts.map(\.address)
                && a.accounts.map(\.feeJuice) == b.accounts.map(\.feeJuice)
        }
    }

    /// What a sequencer is called: the name you gave it in the address book,
    /// or its short address — one read, so page, menu and rows agree.
    static func name(for address: String) -> String {
        AddressBook.shared.name(for: address) ?? AztecWire.short(address)
    }

    /// A row's sequencer: refs are `aztec:seq:<address>:<kind>:<slot>`.
    static func sequencer(ofRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix("aztec:seq:") else { return nil }
        let parts = ref.split(separator: ":")
        return parts.count >= 5 ? String(parts[2]) : nil
    }

    /// `scope` narrows to one sequencer (the account menu's pick); nil is All.
    @MainActor
    static func compose(scope: String?) -> Head {
        let store = AztecStore.shared
        let addresses = scope.map { s in store.sequencers.filter { $0 == s } } ?? store.sequencers
        let accounts = scope.map { s in store.accounts.filter { $0 == s } } ?? store.accounts
        return Head(network: store.network,
                    sequencers: addresses.compactMap(store.reading(for:)),
                    unseen: addresses.filter { store.reading(for: $0) == nil },
                    followed: addresses.count,
                    hasRead: store.network != nil || store.readAt != nil,
                    lagSeries: RoomValueHistory.samples(room: source, address: networkSeries),
                    stakes: store.stakes, duties: store.schedule, stakeSymbol: store.stakeSymbol,
                    accounts: accounts.map { ($0, store.publicFeeJuice(for: $0)) })
    }
}
