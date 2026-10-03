import Foundation

/// What a typed follow target stands for — the ONE spelling the Wallet's two
/// follow doors share (prd §1090): the account page's field
/// (`WalletWatchField`) and the room's Follow tray (`WalletFollowSheet`).
///
/// Resolving is pure: it never turns a chain on. The chain a target needs
/// rides the answer and is enabled only when the follow is made, so a preview
/// that asks about "toly.sol" while you type does not switch Solana on for a
/// name you never followed.
@MainActor
enum WalletFollow {
    struct Target: Equatable {
        let address: String
        /// The name the person typed, or World's username — the book's label.
        let label: String
        /// The chain a follow of this target keeps on (§788, §802, a `.sol` name).
        let chain: String?
        /// World App's spelling of the username, when that is what resolved.
        var worldAppName: String? = nil
    }

    enum Resolution: Equatable {
        case found(Target)
        /// Nothing by that name, or the lookup could not be made — the
        /// sentence says which.
        case missed(String)
    }

    /// What `input` stands for. Nil when it is neither an address nor a name.
    static func resolve(_ input: String) async -> Resolution? {
        let book = AddressBook.shared
        if case .worldAppUsername(let name)? = NameResolve.followTarget(of: input) {
            switch await WorldAppDeFi.holder(ofUsername: name) {
            case .found(let holder):
                // A World App wallet keeps its money on World Chain; the chain
                // is on by default (§788), and this keeps it on for somebody
                // who switched it off, as a `.sol` name does for Solana.
                return .found(Target(address: holder.address, label: holder.name,
                                     chain: "worldchain-mainnet", worldAppName: holder.name))
            case .notFound:
                return .missed(noWorldAppUser(input))
            case .unreachable:
                return .missed(worldAppUnreachable(input))
            }
        }
        if let family = NameResolve.family(of: input) {
            guard let address = await NameResolve.resolve(input) else {
                // The advice differs by family because the fallback does: a
                // `.sol` name's address is base58 and everything else's is `0x`.
                return .missed(family == .sns
                    ? String(localized: "Couldn't resolve \(input) — check the name, or paste the address.")
                    : String(localized: "Couldn't resolve \(input) — check the name or paste a 0x address."))
            }
            return .found(Target(address: address, label: input,
                                 chain: family == .sns ? "solana-mainnet" : nil))
        }
        guard book.looksLikeAddress(input) else { return nil }
        // A legacy/P2SH Bitcoin address is base58-shaped too, the band Solana
        // pubkeys occupy — check the checksum-verified kind FIRST, or a pasted
        // BTC address flips Solana on by mistake.
        let solana = SNS.isAddress(input) && !BitcoinAddress.isAddress(input)
        return .found(Target(address: input, label: "", chain: solana ? "solana-mainnet" : nil))
    }

    /// Follows a resolved target: the chain it needs, then the one choke
    /// point for the cap (`WalletStore.outcome(ofAdding:)`).
    static func follow(_ target: Target) -> WalletStore.AddOutcome {
        let outcome = WalletStore.shared.outcome(ofAdding: target.address, label: target.label)
        if outcome == .added, let chain = target.chain {
            WalletChainStore.shared.ensureEnabled(chain)
        }
        return outcome
    }

    static func noWorldAppUser(_ name: String) -> String {
        String(localized: "No World App user is named \(name).")
    }

    static func worldAppUnreachable(_ name: String) -> String {
        String(localized: "Couldn't reach World App to look up \(name).")
    }
}
