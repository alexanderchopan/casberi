import Foundation

/// ONE DELEGATE, OPENED FROM PERMISSIONS (prd §1594).
///
/// `WalletPermissions.Holder` is what the row draws, and it has already
/// thrown away what the sheet needs: the networks the delegation is set on
/// (merged across chains, §514) and whether the name came from the verified
/// table. This is the same read, folded the same way — one per delegate
/// contract, every account and network it is set on — kept as values so the
/// sheet route carries no `Thing` and a Catalyst sheet needs no environment
/// (§872).
struct WalletDelegation: Equatable, Hashable, Identifiable, Sendable {
    /// The delegate contract, lowercased: the identity, as `Holder.key` is.
    let delegate: String
    /// Its name when something can name it (the delegate table, then your
    /// own label); nil is an UNKNOWN contract, never a guessed name.
    let name: String?
    /// The vendor the verified table names (`WalletSafety.delegateName`),
    /// which is what decides the app the Revoke tile opens. A name you gave
    /// the address yourself is not a vendor.
    let vendor: String?
    /// Network ids in first-seen order (`eth-mainnet`, `base-mainnet`).
    let networks: [String]
    /// Your addresses that delegate to it, in first-seen order.
    let accounts: [String]

    var id: String { delegate }
    var isUnknown: Bool { name == nil }

    /// One per delegate contract over `WalletActingParties.read`'s answer.
    /// Safe modules are not delegations and are left out.
    static func all(_ acting: [WalletActingParties.Account]) -> [WalletDelegation] {
        var order: [String] = []
        var byDelegate: [String: WalletDelegation] = [:]
        for account in acting {
            for party in account.parties {
                guard case .delegate(let network) = party.kind else { continue }
                let key = party.address.lowercased()
                let old = byDelegate[key]
                if old == nil { order.append(key) }
                let networks = (old?.networks ?? []) + ((old?.networks.contains(network) ?? false) ? [] : [network])
                let mine = old?.accounts ?? []
                let accounts = mine.contains { $0.caseInsensitiveCompare(account.address) == .orderedSame }
                    ? mine : mine + [account.address]
                byDelegate[key] = WalletDelegation(delegate: key,
                                                   name: old?.name ?? party.name,
                                                   vendor: old?.vendor ?? WalletSafety.delegateName(for: key),
                                                   networks: networks,
                                                   accounts: accounts)
            }
        }
        return order.compactMap { byDelegate[$0] }
    }

    /// The one for a Permissions row, by the holder's key (the contract).
    static func find(_ key: String, in acting: [WalletActingParties.Account]) -> WalletDelegation? {
        all(acting).first { $0.delegate == key.lowercased() }
    }

    /// The wallet app that set it, where it is undone: only a vendor whose app
    /// takes its scheme, and only while that app is on this phone (§83, the
    /// World App door's rule, §792). MetaMask switches an account back to a
    /// standard one in its own settings; nothing else in the table is an app
    /// this phone can open (Dynamic is a kit inside other apps).
    struct App: Equatable { let name: String; let scheme: String }
    static let apps: [String: App] = [
        "MetaMask": App(name: "MetaMask", scheme: "metamask"),
    ]
    var app: App? { vendor.flatMap { Self.apps[$0] } }
}
