import Foundation

/// WHAT ELSE CAN ACT AS YOU (2026-08-03, prd §293).
///
/// The approvals card (§292) answers who can move your TOKENS. This answers
/// the harder version account abstraction introduces: who can act as the
/// ACCOUNT — sign in its name, move its funds without asking, or replace what
/// its address even does.
///
/// It is §239's Farcaster signers ("which apps can post as you") pointed at
/// money, and it deliberately wears that pass's shape: an inventory with a
/// door, never a control. Nothing here revokes anything; every row links to
/// where the person can.
///
/// ## Three real mechanisms, three different reads
///
/// 1. **A Safe MODULE.** The highest-stakes fact in this file, and
///    `SafeBridge` already says so in its own alert copy: a module can move
///    funds *without a signature*, bypassing the owner threshold entirely.
///    `syncConfig` has alerted on one being ENABLED since 2026-07-30 — but
///    that alert scrolls away with the stream, and nothing ever stated the
///    standing inventory. Read from the config snapshots already on disk, so
///    it costs no network at all.
/// 2. **An EIP-7702 DELEGATE.** `WalletSafety` detects it, names it from a
///    registry, and alerts on CHANGE — again, news only. The delegate is the
///    code your EOA runs; while it's set, it can do anything the EOA can.
///    Stating the current one is the inventory half of a read the app has had
///    for months.
/// 3. **The ACCOUNT'S OWN KIND.** An ERC-7579 account answers `accountId()`
///    with a string like `vendor.account.1.0.0`. It names what the address IS
///    — which the room currently renders as the word "Contract".
///
/// ## The ceiling, stated because the copy has to state it
///
/// **A 7579 account's installed modules cannot be enumerated.** The standard
/// gives `isModuleInstalled(moduleTypeId, module, context)` — a question you
/// can only ask about a module you already know the address of — and no
/// listing call. Safe's `getModulesPaginated` exists because Safe defined it,
/// not because the standard did. So this reads a Safe's modules in full, names
/// a 7702 delegate in full, and for every other smart account says what KIND
/// it is and declines to claim it knows what's installed. A surface that
/// listed nothing and looked complete would be worse than one that says it
/// can't see.
///
/// Reads only, and the two expensive halves already happened elsewhere in the
/// pass. Prd §112 holds: nothing here signs.
enum WalletActingParties {

    /// ERC-7579's `accountId()` — keccak-derived like every other selector in
    /// this codebase (`AerodromeDeFi`'s idiom), never copied from memory.
    static let accountIdSelector = "0x9cfd7cff"
    /// ERC-4337's `entryPoint()`, same derivation. Implemented by essentially
    /// every 4337 account because the account must reject calls that don't
    /// come from its EntryPoint.
    static let entryPointSelector = "0xb0d691fe"

    // MARK: - Is this address a smart account? (2026-08-03, prd §294)

    /// The smart-account value type lives in `WalletUserOps` — its `vendor`
    /// parser reads a string the remote contract chose, so it belongs where
    /// the harness can compile it as shipped. Aliased here because this is
    /// where it's read from.
    typealias SmartAccount = WalletUserOps.SmartAccount

    /// Detects whether an address with bytecode is a SMART ACCOUNT rather than
    /// an ordinary contract — the read behind `AddressBook.Kind.smartAccount`.
    ///
    /// Two questions, cheapest-and-most-specific first:
    ///
    /// 1. `accountId()` — an ERC-7579 account names itself, which is both the
    ///    detection and the vendor in one call.
    /// 2. `entryPoint()` — a 4337 account points at its EntryPoint. **The
    ///    answer must be one we recognise**: plenty of contracts could expose
    ///    a method by that name returning anything, and "it answered
    ///    something" is not evidence. An unknown EntryPoint leaves the address
    ///    an ordinary contract, which is the under-claiming direction.
    ///
    /// nil means "not a smart account, as far as we can tell" — and the caller
    /// keeps `.contract`, which is what the app said before this existed. So a
    /// missed detection costs the old behaviour, never a wrong claim.
    @MainActor
    static func detectSmartAccount(_ address: String) async -> SmartAccount? {
        if let id = await accountID(address: address) {
            return SmartAccount(accountID: id, entryPoint: nil)
        }
        for network in WalletChainStore.activeNetworkIDs() {
            guard let hex = await WalletApprovals.rpcRead(
                    network: network, method: "eth_call",
                    params: [["to": address, "data": entryPointSelector], "latest"]) as? String
            else { continue }
            let answered = WalletUserOps.addressFromTopic(hex)
            guard WalletUserOps.knownEntryPoints.contains(answered) else { continue }
            return SmartAccount(accountID: nil, entryPoint: answered)
        }
        return nil
    }

    /// What can act as one watched address.
    struct Party: Equatable, Identifiable {
        enum Kind: Equatable {
            /// A Safe module — moves funds with no signature at all.
            case safeModule(safe: String)
            /// The EOA's EIP-7702 delegate — the code the address runs.
            case delegate(network: String)
        }
        let kind: Kind
        /// The acting contract, lowercased.
        let address: String
        /// Its name when something can name it — `WalletIngest.knownLabel`'s
        /// chain, or `WalletSafety`'s delegate registry. nil is left as nil
        /// and rendered as short hex: a wrong name on a permissions notice
        /// sends someone to revoke the wrong thing (§239's rule).
        let name: String?

        var id: String {
            switch kind {
            case .safeModule(let safe): "module:\(safe):\(address)"
            case .delegate(let network): "delegate:\(network):\(address)"
            }
        }

        var displayName: String { name ?? WalletStore.shortAddress(address) }

        /// What it can do, in plain words. Deliberately concrete — "can move
        /// funds without a signature" is the sentence that makes a module
        /// worth looking at, and a generic "has permissions" would bury it.
        var capability: String {
            switch kind {
            case .safeModule:
                String(localized: "Can move funds without a signature")
            case .delegate:
                String(localized: "Runs as your wallet")
            }
        }
    }

    /// One watched address and everything that can act as it.
    struct Account: Equatable, Identifiable {
        let address: String
        /// `vendor.account.1.0.0` for an ERC-7579 account; nil for an EOA or
        /// an account that doesn't answer.
        let accountID: String?
        let parties: [Party]
        /// True when this address is a smart account whose modules this app
        /// structurally cannot enumerate (see the type doc). The copy says so
        /// rather than showing an empty list that reads as "nothing installed".
        let modulesUnreadable: Bool

        var id: String { address }
        var isEmpty: Bool { parties.isEmpty && !modulesUnreadable && accountID == nil }
    }

    /// Everything that can act as each of the given (resolved, hex) addresses.
    ///
    /// The Safe half is free (persisted snapshots) and the delegate half is
    /// one `eth_getCode` per address per chain — the read `WalletSafety`
    /// already makes each pass, called here rather than duplicated. Only
    /// `accountId()` is new, and only for addresses that carry code.
    @MainActor
    static func read(addresses: [String]) async -> [Account] {
        guard !addresses.isEmpty else { return [] }
        let safes = SafeBridge.knownModules()
        let delegations = await WalletSafety.currentDelegations(addresses: addresses)

        var out: [Account] = []
        for address in addresses {
            var parties: [Party] = []

            // A Safe's modules — either this address IS the Safe, or it's a
            // Safe we detected through it. Both matter: a module on a Safe you
            // co-sign can move funds you're responsible for.
            for safe in safes where !safe.modules.isEmpty {
                for module in safe.modules {
                    parties.append(Party(kind: .safeModule(safe: safe.safeAddress),
                                         address: module,
                                         name: WalletIngest.knownLabel(for: module)))
                }
            }

            // The 7702 delegate, per chain it's set on.
            for d in delegations where d.address.lowercased() == address.lowercased() {
                parties.append(Party(kind: .delegate(network: d.network),
                                     address: d.delegate.lowercased(),
                                     name: WalletSafety.delegateName(for: d.delegate)
                                        ?? WalletIngest.knownLabel(for: d.delegate)))
            }

            let accountID = await self.accountID(address: address)
            // A 7579 account that isn't a Safe: we know what it is and
            // structurally can't list what's installed on it.
            let isSafe = safes.contains { $0.safeAddress.lowercased() == address.lowercased() }
            let unreadable = accountID != nil && !isSafe

            let account = Account(address: address, accountID: accountID,
                                  parties: dedupe(parties), modulesUnreadable: unreadable)
            if !account.isEmpty { out.append(account) }
        }
        return out
    }

    /// Two Safes can enable the SAME module, and a delegate can be read on
    /// several chains — one row per distinct (kind, address) pair, or the list
    /// repeats itself and inflates how many parties there really are.
    private static func dedupe(_ parties: [Party]) -> [Party] {
        var seen = Set<String>()
        return parties.filter { seen.insert($0.id).inserted }
    }

    /// ERC-7579's `accountId()`, or nil for an EOA / an account that doesn't
    /// implement it. A revert answers "0x", which decodes to nothing — never a
    /// guessed account type.
    @MainActor
    static func accountID(address: String) async -> String? {
        for network in WalletChainStore.activeNetworkIDs() {
            guard let hex = await WalletApprovals.rpcRead(
                    network: network, method: "eth_call",
                    params: [["to": address, "data": accountIdSelector], "latest"]) as? String,
                  let decoded = IngestSupport.decodeABIString(hex),
                  !decoded.isEmpty
            else { continue }
            return decoded
        }
        return nil
    }

    /// `-actingPartiesProbe YES` — one line per account, then one per party.
    @MainActor
    static func probeLines() async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }
        let accounts = await read(addresses: addresses)
        guard !accounts.isEmpty else {
            return ["\(addresses.count) wallet(s) read — nothing can act as any of them"]
        }
        var lines: [String] = []
        for account in accounts {
            lines.append("\(WalletStore.shortAddress(account.address))"
                + " kind=\(account.accountID ?? "EOA")"
                + " parties=\(account.parties.count)"
                + " modulesUnreadable=\(account.modulesUnreadable ? "YES" : "NO")")
            for p in account.parties {
                lines.append("  party| \(p.displayName) (\(p.address)) — \(p.capability)")
            }
        }
        return lines
    }
}
